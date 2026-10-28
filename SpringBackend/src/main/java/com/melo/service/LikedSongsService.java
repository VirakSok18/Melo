package com.melo.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.melo.config.SupabaseConfig;
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
public class LikedSongsService {

    private static final Logger logger = LoggerFactory.getLogger(LikedSongsService.class);

    @Autowired
    private SupabaseConfig supabaseConfig;

    private final HttpClient httpClient = HttpClient.newHttpClient();
    private final ObjectMapper objectMapper = new ObjectMapper();

    public List<Map<String, Object>> getLikedSongs(String userId, String jwt) {
        try {
            String token = (jwt != null && !jwt.isEmpty()) ? jwt : supabaseConfig.getSupabaseAnonKey();
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/liked_songs?user_id=eq." + userId +
                "&order=created_at.desc" +
                "&select=id,track_id,title,artist,image,artist_id,artist_image,created_at";

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
                    entry.put("id", node.get("id").asText());
                    entry.put("trackId", node.get("track_id").asText());
                    entry.put("title", node.get("title").asText());
                    entry.put("artist", node.get("artist").asText());
                    entry.put("image", node.has("image") ? node.get("image").asText() : "");
                    entry.put("artistId", node.has("artist_id") ? node.get("artist_id").asText() : "");
                    entry.put("artistImage", node.has("artist_image") ? node.get("artist_image").asText() : "");
                    entry.put("createdAt", node.has("created_at") ? node.get("created_at").asText() : "");
                    result.add(entry);
                }
                logger.info("Fetched {} liked songs for user {}", result.size(), userId);
                return result;
            } else {
                logger.warn("Failed to fetch liked songs: status {}", response.statusCode());
            }
        } catch (Exception e) {
            logger.error("Error fetching liked songs: {}", e.getMessage());
        }
        return List.of();
    }

    public boolean likeSong(String userId, String trackId, String title, String artist, String image, String artistId, String artistImage, String jwt) {
        try {
            String token = (jwt != null && !jwt.isEmpty()) ? jwt : supabaseConfig.getSupabaseAnonKey();

            Map<String, Object> body = new LinkedHashMap<>();
            body.put("user_id", userId);
            body.put("track_id", trackId);
            body.put("title", title);
            body.put("artist", artist);
            body.put("image", image);
            body.put("artist_id", artistId);
            body.put("artist_image", artistImage);

            String json = objectMapper.writeValueAsString(body);

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(supabaseConfig.getSupabaseUrl() + "/rest/v1/liked_songs"))
                .header("Authorization", "Bearer " + token)
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .header("Prefer", "resolution=merge-duplicates")
                .POST(HttpRequest.BodyPublishers.ofString(json))
                .build();

            HttpResponse<Void> response = httpClient.send(request, HttpResponse.BodyHandlers.discarding());
            boolean ok = response.statusCode() >= 200 && response.statusCode() < 300;
            if (ok) {
                logger.info("Liked song '{}' by {} for user {}", title, artist, userId);
            } else {
                logger.warn("Failed to like song: status {}", response.statusCode());
            }
            return ok;
        } catch (Exception e) {
            logger.error("Error liking song: {}", e.getMessage());
            return false;
        }
    }

    public boolean unlikeSong(String userId, String trackId, String jwt) {
        try {
            String token = (jwt != null && !jwt.isEmpty()) ? jwt : supabaseConfig.getSupabaseAnonKey();
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/liked_songs?user_id=eq." + userId + "&track_id=eq." + trackId;

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Authorization", "Bearer " + token)
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .DELETE()
                .build();

            HttpResponse<Void> response = httpClient.send(request, HttpResponse.BodyHandlers.discarding());
            boolean ok = response.statusCode() >= 200 && response.statusCode() < 300;
            if (ok) {
                logger.info("Unliked song trackId={} for user {}", trackId, userId);
            } else {
                logger.warn("Failed to unlike song: status {}", response.statusCode());
            }
            return ok;
        } catch (Exception e) {
            logger.error("Error unliking song: {}", e.getMessage());
            return false;
        }
    }

    public boolean isSongLiked(String userId, String trackId, String jwt) {
        try {
            String token = (jwt != null && !jwt.isEmpty()) ? jwt : supabaseConfig.getSupabaseAnonKey();
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/liked_songs?user_id=eq." + userId +
                "&track_id=eq." + trackId +
                "&select=id";

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
                return json.isArray() && json.size() > 0;
            }
        } catch (Exception e) {
            logger.error("Error checking liked status: {}", e.getMessage());
        }
        return false;
    }
}
