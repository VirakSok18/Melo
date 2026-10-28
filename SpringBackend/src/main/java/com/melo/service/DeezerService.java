package com.melo.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.melo.config.DeezerConfig;
import com.melo.dto.ArtistDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class DeezerService {

    private static final Logger logger = LoggerFactory.getLogger(DeezerService.class);

    @Autowired
    @org.springframework.beans.factory.annotation.Qualifier("deezerRestTemplate")
    private RestTemplate deezerRestTemplate;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private final ConcurrentHashMap<String, CacheEntry> searchCache = new ConcurrentHashMap<>();
    private static final long CACHE_TTL_MS = 30 * 60 * 1000; // 30 minutes

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

    public List<ArtistDto> searchArtists(String query, int limit) {
        String lowerQuery = query.toLowerCase().trim();

        // Check cache
        CacheEntry cached = searchCache.get(lowerQuery);
        if (cached != null && !cached.isExpired()) {
            logger.info("Deezer search '{}' returning {} cached results", query, cached.results.size());
            return cached.results.subList(0, Math.min(limit, cached.results.size()));
        }

        try {
            String encodedQuery = URLEncoder.encode(query, StandardCharsets.UTF_8);
            String url = String.format("%s/search/artist?q=%s&limit=%d",
                    DeezerConfig.API_BASE, encodedQuery, Math.min(limit, 100));

            ResponseEntity<String> response = deezerRestTemplate.exchange(
                    url, HttpMethod.GET, null, String.class);

            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                JsonNode json = objectMapper.readTree(response.getBody());
                JsonNode data = json.get("data");

                if (data != null && data.isArray()) {
                    List<ArtistDto> results = new ArrayList<>();
                    for (JsonNode item : data) {
                        ArtistDto dto = extractArtist(item);
                        if (dto != null) {
                            results.add(dto);
                        }
                    }

                    // Sort by popularity (nb_fan) descending
                    results.sort((a, b) -> b.getPopularity() - a.getPopularity());

                    logger.info("Deezer search '{}' returned {} artists", query, results.size());
                    if (!results.isEmpty()) {
                        searchCache.put(lowerQuery, new CacheEntry(results));
                    }
                    return results.subList(0, Math.min(limit, results.size()));
                }
            }
        } catch (Exception e) {
            logger.warn("Deezer search failed ({}): {}", query, e.getMessage());
        }

        return Collections.emptyList();
    }

    private ArtistDto extractArtist(JsonNode node) {
        try {
            int id = node.get("id").asInt();
            String name = node.get("name").asText();

            // Use picture_medium (250x250) for good quality + reasonable size
            String image = null;
            if (node.has("picture_medium") && !node.get("picture_medium").asText().isEmpty()) {
                image = node.get("picture_medium").asText();
            } else if (node.has("picture_big") && !node.get("picture_big").asText().isEmpty()) {
                image = node.get("picture_big").asText();
            }

            // Use nb_fan as popularity score
            int popularity = 0;
            if (node.has("nb_fan")) {
                popularity = node.get("nb_fan").asInt();
            }

            return new ArtistDto(String.valueOf(id), name, image != null ? image : "", List.of(), popularity);
        } catch (Exception e) {
            return null;
        }
    }
}
