package com.melo.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.melo.config.SupabaseConfig;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.URLDecoder;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.*;

@Service
public class ListeningHistoryService {

    private static final Logger logger = LoggerFactory.getLogger(ListeningHistoryService.class);

    @Autowired
    private SupabaseConfig supabaseConfig;

    private final HttpClient httpClient = HttpClient.newHttpClient();
    private final ObjectMapper objectMapper = new ObjectMapper();

    public void logEvent(String userId, String trackId, String title, String artist,
                          String image, String genre, boolean skipped, boolean completed,
                          boolean replayed, int listenDuration, String source,
                          String artistId, String artistImage, String jwt) {
        try {
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("user_id", userId);
            body.put("track_id", trackId);
            body.put("title", title);
            body.put("artist", artist);
            body.put("image", image);
            body.put("genre", genre);
            body.put("skipped", skipped);
            body.put("completed", completed);
            body.put("replayed", replayed);
            body.put("listen_duration", listenDuration);
            body.put("source", source);
            body.put("artist_id", artistId);
            body.put("artist_image", artistImage);

            String json = objectMapper.writeValueAsString(body);

            String token = (jwt != null && !jwt.isEmpty()) ? jwt : supabaseConfig.getSupabaseAnonKey();

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(supabaseConfig.getSupabaseUrl() + "/rest/v1/listening_history"))
                .header("Authorization", "Bearer " + token)
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .header("Prefer", "return=minimal")
                .POST(HttpRequest.BodyPublishers.ofString(json))
                .build();

            HttpResponse<Void> response = httpClient.send(request, HttpResponse.BodyHandlers.discarding());
            if (response.statusCode() >= 200 && response.statusCode() < 300) {
                logger.info("Listening event logged for user: {} - {} by {}", userId, title, artist);
            } else {
                logger.error("Failed to log listening event: {}", response.statusCode());
            }
        } catch (Exception e) {
            logger.error("Error logging listening event: {}", e.getMessage());
        }
    }

    public List<Map<String, Object>> getHistory(String userId, String genre, int limit, String jwt) {
        try {
            String encodedGenre = URLEncoder.encode(genre, "UTF-8");
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/listening_history?user_id=eq." + userId +
                "&genre=eq." + encodedGenre +
                "&order=created_at.desc" +
                "&limit=" + limit +
                "&select=title,artist,image,track_id,skipped,completed,replayed,listen_duration,created_at";

            String token = (jwt != null && !jwt.isEmpty()) ? jwt : supabaseConfig.getSupabaseAnonKey();

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Authorization", "Bearer " + token)
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .GET()
                .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                JsonNode json = objectMapper.readTree(response.body());
                List<Map<String, Object>> result = new ArrayList<>();
                for (JsonNode node : json) {
                    Map<String, Object> entry = new LinkedHashMap<>();
                    entry.put("title", node.get("title").asText());
                    entry.put("artist", node.get("artist").asText());
                    entry.put("image", node.has("image") ? node.get("image").asText() : "");
                    entry.put("trackId", node.has("track_id") ? node.get("track_id").asText() : "");
                    entry.put("skipped", node.get("skipped").asBoolean());
                    entry.put("completed", node.get("completed").asBoolean());
                    entry.put("replayed", node.get("replayed").asBoolean());
                    entry.put("listenDuration", node.get("listen_duration").asInt());
                    result.add(entry);
                }
                return result;
            }
        } catch (Exception e) {
            logger.error("Error fetching listening history: {}", e.getMessage());
        }
        return List.of();
    }

    public List<String> getRecommendMore(String userId, String genre, String jwt) {
        return getTasteField(userId, genre, "recommend_more", jwt);
    }

    public List<String> getRecommendLess(String userId, String genre, String jwt) {
        return getTasteField(userId, genre, "recommend_less", jwt);
    }

    private List<String> getTasteField(String userId, String genre, String field, String jwt) {
        try {
            String encodedGenre = URLEncoder.encode(genre, "UTF-8");
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/user_taste_profiles?user_id=eq." + userId +
                "&genre=eq." + encodedGenre +
                "&select=" + field;

            String token = (jwt != null && !jwt.isEmpty()) ? jwt : supabaseConfig.getSupabaseAnonKey();

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Authorization", "Bearer " + token)
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .GET()
                .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                JsonNode json = objectMapper.readTree(response.body());
                if (json.isArray() && json.size() > 0) {
                    JsonNode arr = json.get(0).get(field);
                    if (arr != null && arr.isArray()) {
                        List<String> result = new ArrayList<>();
                        for (JsonNode item : arr) {
                            result.add(item.asText());
                        }
                        return result;
                    }
                }
            }
        } catch (Exception e) {
            logger.error("Error fetching taste field {}: {}", field, e.getMessage());
        }
        return List.of();
    }

    public void updateTasteProfile(String userId, String genre, String field, List<String> values, String jwt) {
        try {
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("user_id", userId);
            body.put("genre", genre);
            body.put(field, values);
            body.put("updated_at", new Date().toString());

            String json = objectMapper.writeValueAsString(body);

            String token = (jwt != null && !jwt.isEmpty()) ? jwt : supabaseConfig.getSupabaseAnonKey();

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(supabaseConfig.getSupabaseUrl() + "/rest/v1/user_taste_profiles"))
                .header("Authorization", "Bearer " + token)
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .header("Prefer", "resolution=merge-duplicates")
                .POST(HttpRequest.BodyPublishers.ofString(json))
                .build();

            httpClient.send(request, HttpResponse.BodyHandlers.discarding());
        } catch (Exception e) {
            logger.error("Error updating taste profile: {}", e.getMessage());
        }
    }

    public List<Map<String, Object>> getRecentHistory(String userId, int days) {
        return getRecentHistory(userId, days, null);
    }

    public List<Map<String, Object>> getRecentHistory(String userId, int days, String jwt) {
        try {
            String since = java.time.LocalDate.now().minusDays(days).atStartOfDay().toString();
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/listening_history?user_id=eq." + userId +
                "&created_at=gte." + since +
                "&order=created_at.desc" +
                "&limit=500" +
                "&select=track_id,title,artist,image,artist_id,artist_image,genre,skipped,completed,replayed,listen_duration,created_at";

            String token = (jwt != null && !jwt.isEmpty()) ? jwt : supabaseConfig.getSupabaseAnonKey();

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Authorization", "Bearer " + token)
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .GET()
                .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 200) {
                JsonNode json = objectMapper.readTree(response.body());
                List<Map<String, Object>> result = new ArrayList<>();
                for (JsonNode node : json) {
                    Map<String, Object> entry = new LinkedHashMap<>();
                    entry.put("title", node.get("title").asText());
                    entry.put("artist", node.get("artist").asText());
                    entry.put("image", node.has("image") ? node.get("image").asText() : "");
                    entry.put("trackId", node.has("track_id") ? node.get("track_id").asText() : "");
                    entry.put("artistId", node.has("artist_id") ? node.get("artist_id").asText() : "");
                    entry.put("artistImage", node.has("artist_image") ? node.get("artist_image").asText() : "");
                    entry.put("genre", node.has("genre") ? node.get("genre").asText() : "");
                    entry.put("skipped", node.get("skipped").asBoolean());
                    entry.put("completed", node.get("completed").asBoolean());
                    entry.put("replayed", node.get("replayed").asBoolean());
                    entry.put("listenDuration", node.has("listen_duration") ? node.get("listen_duration").asInt() : 0);
                    entry.put("created_at", node.has("created_at") ? node.get("created_at").asText() : "");
                    result.add(entry);
                }
                logger.info("Fetched {} history entries for user {} (last {} days)", result.size(), userId, days);
                return result;
            } else {
                logger.warn("Failed to fetch history: {}", response.statusCode());
            }
        } catch (Exception e) {
            logger.error("Error fetching recent history: {}", e.getMessage());
        }
        return List.of();
    }

    public List<Map<String, Object>> getTopArtistsByCompletion(String userId, int days, int limit) {
        List<Map<String, Object>> history = getRecentHistory(userId, days);
        return getTopArtistsByCompletion(history, limit);
    }

    public List<Map<String, Object>> getTopArtistsByCompletion(List<Map<String, Object>> history, int limit) {
        Map<String, int[]> artistStats = new LinkedHashMap<>();

        for (Map<String, Object> entry : history) {
            String artist = (String) entry.get("artist");
            if (artist == null || artist.isEmpty()) continue;
            artistStats.putIfAbsent(artist, new int[]{0, 0, 0});
            if ((Boolean) entry.getOrDefault("completed", false)) artistStats.get(artist)[0]++;
            if ((Boolean) entry.getOrDefault("replayed", false)) artistStats.get(artist)[1]++;
            if ((Boolean) entry.getOrDefault("skipped", false)) artistStats.get(artist)[2]++;
        }

        List<Map<String, Object>> ranked = new ArrayList<>();
        for (Map.Entry<String, int[]> e : artistStats.entrySet()) {
            int score = e.getValue()[0] * 10 + e.getValue()[1] * 20 - e.getValue()[2] * 5;
            if (score > 0) {
                Map<String, Object> item = new LinkedHashMap<>();
                item.put("artist", e.getKey());
                item.put("score", score);
                item.put("completions", e.getValue()[0]);
                item.put("replays", e.getValue()[1]);
                item.put("skips", e.getValue()[2]);
                ranked.add(item);
            }
        }

        ranked.sort((a, b) -> (int) b.get("score") - (int) a.get("score"));
        if (ranked.size() > limit) ranked = ranked.subList(0, limit);
        return ranked;
    }

    public List<Map<String, Object>> getTopGenres(String userId, int days, int limit) {
        List<Map<String, Object>> history = getRecentHistory(userId, days);
        return getTopGenres(history, limit);
    }

    public List<Map<String, Object>> getTopGenres(List<Map<String, Object>> history, int limit) {
        Map<String, int[]> genreStats = new LinkedHashMap<>();

        for (Map<String, Object> entry : history) {
            String genre = (String) entry.getOrDefault("genre", "");
            if (genre.isEmpty()) continue;
            genreStats.putIfAbsent(genre, new int[]{0, 0});
            int duration = (int) entry.getOrDefault("listenDuration", 0);
            genreStats.get(genre)[0] += duration;
            genreStats.get(genre)[1]++;
        }

        List<Map<String, Object>> ranked = new ArrayList<>();
        for (Map.Entry<String, int[]> e : genreStats.entrySet()) {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("genre", e.getKey());
            item.put("totalDuration", e.getValue()[0]);
            item.put("playCount", e.getValue()[1]);
            ranked.add(item);
        }

        ranked.sort((a, b) -> (int) b.get("totalDuration") - (int) a.get("totalDuration"));
        if (ranked.size() > limit) ranked = ranked.subList(0, limit);
        return ranked;
    }

    public List<String> getRecentlyPlayedArtists(String userId, int days) {
        List<Map<String, Object>> history = getRecentHistory(userId, days);
        LinkedHashSet<String> seen = new LinkedHashSet<>();
        for (Map<String, Object> entry : history) {
            String artist = (String) entry.get("artist");
            if (artist != null && !artist.isEmpty()) {
                seen.add(artist);
            }
        }
        return new ArrayList<>(seen);
    }

    public List<Map<String, Object>> getUnderexploredArtists(String userId, int maxListens) {
        List<Map<String, Object>> history = getRecentHistory(userId, 30);
        Map<String, int[]> artistCounts = new LinkedHashMap<>();

        for (Map<String, Object> entry : history) {
            String artist = (String) entry.get("artist");
            if (artist == null || artist.isEmpty()) continue;
            artistCounts.putIfAbsent(artist, new int[]{0, 0});
            artistCounts.get(artist)[0]++;
            if ((Boolean) entry.getOrDefault("completed", false)) artistCounts.get(artist)[1]++;
        }

        List<Map<String, Object>> underexplored = new ArrayList<>();
        for (Map.Entry<String, int[]> e : artistCounts.entrySet()) {
            if (e.getValue()[0] <= maxListens && e.getValue()[1] > 0) {
                Map<String, Object> item = new LinkedHashMap<>();
                item.put("artist", e.getKey());
                item.put("listens", e.getValue()[0]);
                item.put("completions", e.getValue()[1]);
                underexplored.add(item);
            }
        }
        return underexplored;
    }

    public List<String> getRecentlyPlayedArtistsForPlaylist(String userId, int days) {
        return getRecentlyPlayedArtists(userId, days);
    }
}
