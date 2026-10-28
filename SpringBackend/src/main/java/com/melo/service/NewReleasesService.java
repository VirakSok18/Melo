package com.melo.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.melo.config.SupabaseConfig;
import com.melo.dto.SearchResultDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.*;

@Service
public class NewReleasesService {

    private static final Logger logger = LoggerFactory.getLogger(NewReleasesService.class);

    @Autowired
    private SupabaseConfig supabaseConfig;

    @Autowired
    private DeezerSearchService deezerSearchService;

    @Autowired
    private RecommendationService recommendationService;

    private final HttpClient httpClient = HttpClient.newHttpClient();
    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final long MEMORY_CACHE_TTL_MS = 12 * 60 * 60 * 1000;
    private final Map<String, MemoryCacheEntry> memoryCache = new java.util.concurrent.ConcurrentHashMap<>();

    private static class MemoryCacheEntry {
        final List<Map<String, Object>> songs;
        final long createdAt;
        MemoryCacheEntry(List<Map<String, Object>> songs) {
            this.songs = songs;
            this.createdAt = System.currentTimeMillis();
        }
        boolean isExpired() {
            return System.currentTimeMillis() - createdAt > MEMORY_CACHE_TTL_MS;
        }
    }

    public List<Map<String, Object>> getNewReleases(String userId, boolean force) {
        if (!force) {
            // Fastest: in-memory cache (survives app restarts while backend stays up)
            MemoryCacheEntry mem = memoryCache.get(userId);
            if (mem != null && !mem.isExpired() && mem.songs.size() >= 5) {
                logger.info("New releases: using memory cache for user {} ({} songs)", userId, mem.songs.size());
                return mem.songs;
            }

            // Slower: Supabase persisted cache
            List<Map<String, Object>> cached = getCachedReleases(userId);
            if (cached != null && cached.size() >= 5) {
                memoryCache.put(userId, new MemoryCacheEntry(cached));
                logger.info("New releases: using Supabase cache for user {} ({} songs)", userId, cached.size());
                return cached;
            }
            if (cached != null && !cached.isEmpty()) {
                logger.info("New releases: cache has only {} songs, regenerating", cached.size());
            }
        }

        List<Map<String, Object>> releases = generateReleases(userId);
        memoryCache.put(userId, new MemoryCacheEntry(releases));
        saveReleases(userId, releases);

        logger.info("New releases: generated {} songs for user {}", releases.size(), userId);
        return releases;
    }

    private List<Map<String, Object>> generateReleases(String userId) {
        List<Map<String, Object>> result = new ArrayList<>();
        Set<String> seen = new HashSet<>();

        List<String> topArtists = getTopArtistsFromHistory(userId, 5);
        List<String> topGenres = getTopGenresFromHistory(userId, 3);

        if (topGenres.isEmpty()) {
            topGenres = getFavoriteGenresFromProfile(userId);
        }
        if (topArtists.isEmpty()) {
            topArtists = getFavoriteArtistsFromProfile(userId);
        }

        logger.info("New releases: top artists={}, top genres={}", topArtists, topGenres);

        // Empty profile + empty history → fill all 10 from chart
        if (topArtists.isEmpty() && topGenres.isEmpty()) {
            return getChartTracksResult(10, "Trending now");
        }

        // Tier 1: top artists → newest album tracks (up to 4), interleaved across artists
        Map<String, List<SearchResultDto>> artistTracks = new LinkedHashMap<>();
        for (String artist : topArtists) {
            try {
                List<SearchResultDto> tracks = deezerSearchService.getNewestTracksByArtist(artist, 3);
                if (!tracks.isEmpty()) {
                    artistTracks.put(artist, tracks);
                }
                Thread.sleep(300);
            } catch (Exception e) {
                logger.warn("Tier 1 failed for '{}': {}", artist, e.getMessage());
            }
        }
        // Round-robin interleaving
        int maxPerArtist = artistTracks.values().stream().mapToInt(List::size).max().orElse(0);
        for (int i = 0; i < maxPerArtist && result.size() < 4; i++) {
            for (Map.Entry<String, List<SearchResultDto>> entry : artistTracks.entrySet()) {
                if (result.size() >= 4) break;
                if (i < entry.getValue().size()) {
                    SearchResultDto track = entry.getValue().get(i);
                    String key = trackKey(track);
                    if (!seen.contains(key)) {
                        seen.add(key);
                        result.add(buildTrackItem(track, entry.getKey(), "favorite"));
                    }
                }
            }
        }

        // Tier 2: "Because you like [Genre]" — curated genre artists' newest tracks (up to 8 total)
        Map<String, List<String>> genreMap = recommendationService.getGenreToArtistNames();
        String tier2Genre = topGenres.isEmpty() ? null : topGenres.get(0);
        if (tier2Genre != null && genreMap.containsKey(tier2Genre)) {
            List<String> genreArtists = genreMap.get(tier2Genre);
            for (String artist : genreArtists) {
                if (result.size() >= 8) break;
                if (seen.contains(artist.toLowerCase())) continue;
                try {
                    List<SearchResultDto> tracks = deezerSearchService.getNewestTracksByArtist(artist, 2);
                    for (SearchResultDto track : tracks) {
                        if (result.size() >= 8) break;
                        String key = trackKey(track);
                        if (!seen.contains(key)) {
                            seen.add(key);
                            result.add(buildTrackItem(track, "Because you like " + tier2Genre, "similar"));
                        }
                    }
                    Thread.sleep(300);
                } catch (Exception e) {
                    logger.warn("Tier 2 failed for '{}': {}", artist, e.getMessage());
                }
            }
        }

        // Tier 3: "Trending now" — live Deezer chart (fill to 10)
        if (result.size() < 10) {
            try {
                List<SearchResultDto> chartTracks = deezerSearchService.getChartTracks(15);
                for (SearchResultDto track : chartTracks) {
                    if (result.size() >= 10) break;
                    String key = trackKey(track);
                    if (!seen.contains(key)) {
                        seen.add(key);
                        result.add(buildTrackItem(track, "Trending now", "trending"));
                    }
                }
            } catch (Exception e) {
                logger.warn("Tier 3 chart failed: {}", e.getMessage());
            }
        }

        // If still <5, fill more from chart
        if (result.size() < 5) {
            logger.warn("New releases: only {} songs, adding more chart fallbacks", result.size());
            try {
                List<SearchResultDto> moreChart = deezerSearchService.getChartTracks(25);
                for (SearchResultDto track : moreChart) {
                    if (result.size() >= 10) break;
                    String key = trackKey(track);
                    if (!seen.contains(key)) {
                        seen.add(key);
                        result.add(buildTrackItem(track, "Trending now", "trending"));
                    }
                }
            } catch (Exception e) {
                logger.warn("Chart fallback failed: {}", e.getMessage());
            }
        }

        return result;
    }

    private List<Map<String, Object>> getChartTracksResult(int limit, String reason) {
        List<Map<String, Object>> result = new ArrayList<>();
        try {
            List<SearchResultDto> chartTracks = deezerSearchService.getChartTracks(limit);
            for (SearchResultDto track : chartTracks) {
                result.add(buildTrackItem(track, reason, "trending"));
            }
        } catch (Exception e) {
            logger.warn("Chart fallback failed: {}", e.getMessage());
        }
        return result;
    }

    private List<String> getTopArtistsFromHistory(String userId, int limit) {
        try {
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/listening_history?user_id=eq." + userId +
                "&select=artist" +
                "&skipped=eq.false" +
                "&order=created_at.desc" +
                "&limit=200";

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Authorization", "Bearer " + supabaseConfig.getSupabaseAnonKey())
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .GET()
                .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                JsonNode json = objectMapper.readTree(response.body());
                if (json.isArray()) {
                    Map<String, Integer> artistCounts = new LinkedHashMap<>();
                    for (JsonNode node : json) {
                        String artist = node.get("artist").asText();
                        if (artist != null && !artist.isEmpty()) {
                            artistCounts.merge(artist, 1, Integer::sum);
                        }
                    }
                    return artistCounts.entrySet().stream()
                        .sorted(Map.Entry.<String, Integer>comparingByValue().reversed())
                        .limit(limit)
                        .map(Map.Entry::getKey)
                        .toList();
                }
            }
        } catch (Exception e) {
            logger.error("Failed to get top artists from history: {}", e.getMessage());
        }
        return List.of();
    }

    private List<String> getTopGenresFromHistory(String userId, int limit) {
        try {
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/listening_history?user_id=eq." + userId +
                "&select=genre" +
                "&skipped=eq.false" +
                "&genre=not.is.null" +
                "&order=created_at.desc" +
                "&limit=200";

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Authorization", "Bearer " + supabaseConfig.getSupabaseAnonKey())
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .GET()
                .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                JsonNode json = objectMapper.readTree(response.body());
                if (json.isArray()) {
                    Map<String, Integer> genreCounts = new LinkedHashMap<>();
                    for (JsonNode node : json) {
                        String genre = node.get("genre").asText();
                        if (genre != null && !genre.isEmpty()) {
                            genreCounts.merge(genre, 1, Integer::sum);
                        }
                    }
                    return genreCounts.entrySet().stream()
                        .sorted(Map.Entry.<String, Integer>comparingByValue().reversed())
                        .limit(limit)
                        .map(Map.Entry::getKey)
                        .toList();
                }
            }
        } catch (Exception e) {
            logger.warn("Failed to get top genres from history: {}", e.getMessage());
        }
        return List.of();
    }

    private List<String> getFavoriteGenresFromProfile(String userId) {
        try {
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/profiles?id=eq." + userId +
                "&select=favorite_genres";

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Authorization", "Bearer " + supabaseConfig.getSupabaseAnonKey())
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .GET()
                .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                JsonNode json = objectMapper.readTree(response.body());
                if (json.isArray() && json.size() > 0) {
                    JsonNode genresNode = json.get(0).get("favorite_genres");
                    if (genresNode != null && genresNode.isArray()) {
                        List<String> genres = new ArrayList<>();
                        for (JsonNode g : genresNode) {
                            genres.add(g.asText());
                        }
                        logger.info("New releases: favorite genres from profile: {}", genres);
                        return genres;
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Failed to get favorite genres from profile: {}", e.getMessage());
        }
        return List.of();
    }

    private List<String> getFavoriteArtistsFromProfile(String userId) {
        try {
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/profiles?id=eq." + userId +
                "&select=favorite_artists";

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Authorization", "Bearer " + supabaseConfig.getSupabaseAnonKey())
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .GET()
                .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                JsonNode json = objectMapper.readTree(response.body());
                if (json.isArray() && json.size() > 0) {
                    JsonNode artistsNode = json.get(0).get("favorite_artists");
                    if (artistsNode != null && artistsNode.isArray()) {
                        List<String> artists = new ArrayList<>();
                        for (JsonNode a : artistsNode) {
                            if (a.has("name")) {
                                artists.add(a.get("name").asText());
                            }
                        }
                        logger.info("New releases: favorite artists from profile: {}", artists);
                        return artists;
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Failed to get favorite artists from profile: {}", e.getMessage());
        }
        return List.of();
    }

    private Map<String, Object> buildTrackItem(SearchResultDto track, String reason, String source) {
        Map<String, Object> item = new LinkedHashMap<>();
        item.put("id", track.getId());
        item.put("title", track.getTitle());
        item.put("artist", track.getArtist());
        item.put("image", track.getImage());
        item.put("duration", track.getDuration());
        item.put("reason", reason);
        item.put("source", source);
        return item;
    }

    private String trackKey(Map<String, Object> track) {
        return (track.get("title") + "|" + track.get("artist")).toLowerCase();
    }

    private String trackKey(SearchResultDto track) {
        return (track.getTitle() + "|" + track.getArtist()).toLowerCase();
    }

    private List<Map<String, Object>> getCachedReleases(String userId) {
        try {
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/daily_new_releases?user_id=eq." + userId +
                "&order=created_at.desc" +
                "&limit=1" +
                "&select=songs,created_at";

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Authorization", "Bearer " + supabaseConfig.getSupabaseAnonKey())
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .GET()
                .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                JsonNode json = objectMapper.readTree(response.body());
                if (json.isArray() && json.size() > 0) {
                    JsonNode row = json.get(0);
                    String createdAt = row.has("created_at") ? row.get("created_at").asText() : null;

                    if (createdAt != null) {
                        java.time.OffsetDateTime generatedAt = java.time.OffsetDateTime.parse(createdAt);
                        java.time.OffsetDateTime now = java.time.OffsetDateTime.now();
                        java.time.Duration elapsed = java.time.Duration.between(generatedAt, now);
                        if (elapsed.toHours() < 12) {
                            JsonNode songs = row.get("songs");
                            if (songs != null && songs.isArray()) {
                                List<Map<String, Object>> result = new ArrayList<>();
                                for (JsonNode node : songs) {
                                    Map<String, Object> item = new LinkedHashMap<>();
                                    node.fields().forEachRemaining(e -> {
                                        JsonNode val = e.getValue();
                                        if (val.isTextual()) {
                                            item.put(e.getKey(), val.asText());
                                        } else if (val.isNumber()) {
                                            item.put(e.getKey(), val.asInt());
                                        } else {
                                            item.put(e.getKey(), val.toString());
                                        }
                                    });
                                    result.add(item);
                                }
                                return result;
                            }
                        } else {
                            logger.info("New releases: cache is {} hours old, regenerating", elapsed.toHours());
                        }
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Failed to get cached releases: {}", e.getMessage());
        }
        return null;
    }

    private void saveReleases(String userId, List<Map<String, Object>> releases) {
        try {
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("user_id", userId);
            body.put("release_date", java.time.LocalDate.now().toString());
            body.put("songs", releases);
            body.put("created_at", java.time.OffsetDateTime.now().toString());

            String json = objectMapper.writeValueAsString(body);

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(supabaseConfig.getSupabaseUrl() + "/rest/v1/daily_new_releases"))
                .header("Authorization", "Bearer " + supabaseConfig.getSupabaseAnonKey())
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .header("Prefer", "resolution=merge-duplicates")
                .POST(HttpRequest.BodyPublishers.ofString(json))
                .build();

            httpClient.send(request, HttpResponse.BodyHandlers.discarding());
        } catch (Exception e) {
            logger.warn("Failed to save releases: {}", e.getMessage());
        }
    }
}
