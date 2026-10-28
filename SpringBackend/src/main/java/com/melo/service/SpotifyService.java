package com.melo.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.melo.config.SpotifyConfig;
import com.melo.dto.ArtistDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.*;
import org.springframework.http.client.ClientHttpResponse;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import jakarta.annotation.PostConstruct;
import java.io.InputStream;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class SpotifyService {

    private static final Logger logger = LoggerFactory.getLogger(SpotifyService.class);
    private static final String TOKEN_URL = "https://accounts.spotify.com/api/token";
    private static final String API_BASE = "https://api.spotify.com/v1";

    @Autowired
    private SpotifyConfig spotifyConfig;

    @Autowired
    @org.springframework.beans.factory.annotation.Qualifier("spotifyRestTemplate")
    private RestTemplate restTemplate;

    private RestTemplate noErrorRestTemplate;

    private String accessToken;
    private Instant tokenExpiry;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private Map<String, List<Map<String, String>>> curatedArtists = new HashMap<>();

    private final ConcurrentHashMap<String, CacheEntry> searchCache = new ConcurrentHashMap<>();
    private static final long CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

    private static class CacheEntry {
        final List<ArtistDto> results;
        final Instant timestamp;
        CacheEntry(List<ArtistDto> results) {
            this.results = results;
            this.timestamp = Instant.now();
        }
        boolean isExpired() {
            return Instant.now().isAfter(timestamp.plusMillis(CACHE_TTL_MS));
        }
    }

    public static class SpotifyApiException extends RuntimeException {
        private final int statusCode;
        private final String responseBody;

        public SpotifyApiException(int statusCode, String responseBody, Throwable cause) {
            super("Spotify API error " + statusCode + ": " + responseBody, cause);
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public int getStatusCode() { return statusCode; }
        public String getResponseBody() { return responseBody; }
    }

    @PostConstruct
    public void init() {
        try {
            ClassPathResource resource = new ClassPathResource("artists.json");
            InputStream is = resource.getInputStream();
            @SuppressWarnings("unchecked")
            Map<String, List<Map<String, String>>> loaded = objectMapper.readValue(is,
                    new com.fasterxml.jackson.core.type.TypeReference<Map<String, List<Map<String, String>>>>() {});
            curatedArtists = loaded;
            logger.info("Loaded curated artists for {} genres: {}", curatedArtists.size(), curatedArtists.keySet());
        } catch (Exception e) {
            logger.error("Failed to load artists.json", e);
        }
    }

    private RestTemplate getNoErrorRestTemplate() {
        if (noErrorRestTemplate == null) {
            SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
            factory.setConnectTimeout(3000);
            factory.setReadTimeout(3000);
            noErrorRestTemplate = new RestTemplate(factory);
            noErrorRestTemplate.setErrorHandler(new org.springframework.web.client.ResponseErrorHandler() {
                @Override
                public boolean hasError(ClientHttpResponse response) { return false; }
                @Override
                public void handleError(ClientHttpResponse response) {}
            });
        }
        return noErrorRestTemplate;
    }

    private String getAccessToken() {
        if (accessToken != null && tokenExpiry != null && Instant.now().isBefore(tokenExpiry)) {
            return accessToken;
        }

        logger.info("Requesting new Spotify access token...");
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);

        String body = "grant_type=client_credentials"
                + "&client_id=" + spotifyConfig.getClientId()
                + "&client_secret=" + spotifyConfig.getClientSecret();

        HttpEntity<String> request = new HttpEntity<>(body, headers);

        try {
            ResponseEntity<String> response = restTemplate.postForEntity(TOKEN_URL, request, String.class);
            if (response.getStatusCode().is2xxSuccessful()) {
                JsonNode json = objectMapper.readTree(response.getBody());
                accessToken = json.get("access_token").asText();
                int expiresIn = json.get("expires_in").asInt();
                tokenExpiry = Instant.now().plusSeconds(expiresIn - 60);
                logger.info("Spotify token obtained, expires in {}s", expiresIn);
                return accessToken;
            } else {
                logger.error("Spotify auth failed: {}", response.getStatusCode());
                return null;
            }
        } catch (Exception e) {
            logger.error("Spotify token request failed: {}", e.getMessage());
            return null;
        }
    }

    private HttpHeaders authHeaders() {
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(getAccessToken());
        return headers;
    }

    public List<ArtistDto> getCuratedArtists(List<String> genres) {
        List<ArtistDto> result = new ArrayList<>();

        for (String genre : genres) {
            List<Map<String, String>> genreArtists = curatedArtists.get(genre);
            if (genreArtists == null) {
                logger.warn("No curated artists for genre: {}", genre);
                continue;
            }

            for (Map<String, String> entry : genreArtists) {
                String id = entry.get("id");
                String name = entry.get("name");
                String image = entry.get("image");

                if (image == null || name == null || name.equals("Unknown")) {
                    continue;
                }

                ArtistDto dto = new ArtistDto(id, name, image, List.of(), 0);
                result.add(dto);
            }
        }

        logger.info("Returning {} curated artists for genres: {}", result.size(), genres);
        return result;
    }

    public List<ArtistDto> searchArtists(String query, int limit) {
        String lowerQuery = query.toLowerCase().trim();

        // 0. Check cache first
        CacheEntry cached = searchCache.get(lowerQuery);
        if (cached != null && !cached.isExpired()) {
            logger.info("Search '{}' returning {} cached results", query, cached.results.size());
            return cached.results;
        }

        Set<String> seenIds = new LinkedHashSet<>();
        List<ArtistDto> result = new ArrayList<>();

        // 1. Search local curated artists first (instant, no API calls)
        for (Map.Entry<String, List<Map<String, String>>> entry : curatedArtists.entrySet()) {
            for (Map<String, String> artist : entry.getValue()) {
                String name = artist.get("name");
                String id = artist.get("id");
                String image = artist.get("image");
                if (name != null && name.toLowerCase().contains(lowerQuery)
                        && image != null && !seenIds.contains(id)) {
                    seenIds.add(id);
                    result.add(new ArtistDto(id, name, image, List.of(), 0));
                    if (result.size() >= limit) {
                        logger.info("Local search '{}' returned {} artists", query, result.size());
                        searchCache.put(lowerQuery, new CacheEntry(result));
                        return result;
                    }
                }
            }
        }

        // 2. Try Spotify API for broader results (with retry on 429)
        String token = getAccessToken();
        if (token == null) {
            logger.warn("No Spotify token, returning local results only");
        } else {
            int maxAttempts = 2;
            for (int attempt = 1; attempt <= maxAttempts; attempt++) {
                try {
                    String encodedQuery = URLEncoder.encode(query, StandardCharsets.UTF_8);
                    String url = String.format("%s/search?q=%s&type=artist&limit=%d",
                            API_BASE, encodedQuery, limit);

                    HttpHeaders authHeaders = new HttpHeaders();
                    authHeaders.setBearerAuth(token);
                    HttpEntity<Void> request = new HttpEntity<>(authHeaders);
                    ResponseEntity<String> response = getNoErrorRestTemplate().exchange(
                            url, HttpMethod.GET, request, String.class);

                    int status = response.getStatusCode().value();

                    if (status == 200) {
                        JsonNode json = objectMapper.readTree(response.getBody());
                        JsonNode artistsNode = json.get("artists");
                        if (artistsNode != null) {
                            JsonNode items = artistsNode.get("items");
                            if (items != null && items.isArray()) {
                                for (JsonNode item : items) {
                                    ArtistDto dto = extractArtist(item);
                                    if (dto != null && !seenIds.contains(dto.getId())) {
                                        seenIds.add(dto.getId());
                                        result.add(dto);
                                        if (result.size() >= limit) break;
                                    }
                                }
                            }
                        }
                        break; // success, no retry needed
                    } else if (status == 429 && attempt < maxAttempts) {
                        logger.warn("Spotify search rate limited (429), retrying in 2s (attempt {}/{})",
                                attempt, maxAttempts);
                        Thread.sleep(2000);
                    } else {
                        logger.warn("Spotify search returned status {}, using local results only", status);
                        break;
                    }
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    logger.warn("Search retry interrupted");
                    break;
                } catch (Exception e) {
                    logger.warn("Spotify search failed ({}), using local results only", e.getMessage());
                    break;
                }
            }
        }

        logger.info("Search '{}' returned {} artists (local + spotify)", query, result.size());
        // Only cache if we got results (don't cache empty/failed searches)
        if (!result.isEmpty()) {
            searchCache.put(lowerQuery, new CacheEntry(result));
        }
        return result;
    }

    private ArtistDto extractArtist(JsonNode node) {
        try {
            String id = node.get("id").asText();
            String name = node.get("name").asText();

            String image = null;
            JsonNode images = node.get("images");
            if (images != null && images.isArray() && !images.isEmpty()) {
                image = images.get(0).get("url").asText();
            }

            List<String> genres = new ArrayList<>();
            JsonNode genresNode = node.get("genres");
            if (genresNode != null && genresNode.isArray()) {
                for (JsonNode g : genresNode) {
                    genres.add(g.asText());
                }
            }

            return new ArtistDto(id, name, image != null ? image : "", genres, 0);
        } catch (Exception e) {
            return null;
        }
    }
}
