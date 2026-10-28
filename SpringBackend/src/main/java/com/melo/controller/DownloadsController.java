package com.melo.controller;

import com.melo.config.SupabaseConfig;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.*;

@RestController
@RequestMapping("/api/downloads")
@CrossOrigin(origins = "*")
public class DownloadsController {

    private static final Logger logger = LoggerFactory.getLogger(DownloadsController.class);

    @Autowired
    private SupabaseConfig supabaseConfig;

    private final HttpClient httpClient = HttpClient.newHttpClient();
    private final ObjectMapper objectMapper = new ObjectMapper();

    @GetMapping
    public ResponseEntity<Map<String, Object>> getDownloads(
            @RequestParam String userId,
            @RequestHeader(value = "Authorization", required = false) String authHeader) {

        String jwt = extractJwt(authHeader);

        try {
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/downloaded_songs?user_id=eq." + userId +
                "&order=created_at.desc" +
                "&select=track_id,title,artist,image,artist_id,artist_image,file_size,created_at";

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
                    entry.put("trackId", node.get("track_id").asText());
                    entry.put("title", node.get("title").asText());
                    entry.put("artist", node.get("artist").asText());
                    entry.put("image", node.has("image") ? node.get("image").asText() : "");
                    entry.put("artistId", node.has("artist_id") ? node.get("artist_id").asText() : "");
                    entry.put("artistImage", node.has("artist_image") ? node.get("artist_image").asText() : "");
                    entry.put("fileSize", node.has("file_size") ? node.get("file_size").asLong() : 0);
                    result.add(entry);
                }
                return ResponseEntity.ok(Map.of("success", true, "songs", result));
            }
        } catch (Exception e) {
            logger.error("Error fetching downloads: {}", e.getMessage());
        }
        return ResponseEntity.ok(Map.of("success", true, "songs", List.of()));
    }

    @PostMapping
    public ResponseEntity<Map<String, Object>> saveDownload(
            @RequestBody Map<String, Object> body,
            @RequestHeader(value = "Authorization", required = false) String authHeader) {

        String userId = (String) body.get("userId");
        String trackId = (String) body.get("trackId");
        String title = (String) body.get("title");
        String artist = (String) body.get("artist");
        String image = (String) body.getOrDefault("image", "");
        long fileSize = body.get("fileSize") != null ? ((Number) body.get("fileSize")).longValue() : 0;
        String artistId = (String) body.getOrDefault("artistId", "");
        String artistImage = (String) body.getOrDefault("artistImage", "");

        String jwt = extractJwt(authHeader);
        String token = (jwt != null && !jwt.isEmpty()) ? jwt : supabaseConfig.getSupabaseAnonKey();

        try {
            Map<String, Object> insertBody = new LinkedHashMap<>();
            insertBody.put("user_id", userId);
            insertBody.put("track_id", trackId);
            insertBody.put("title", title);
            insertBody.put("artist", artist);
            insertBody.put("image", image);
            insertBody.put("file_size", fileSize);
            insertBody.put("artist_id", artistId);
            insertBody.put("artist_image", artistImage);

            String json = objectMapper.writeValueAsString(insertBody);

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(supabaseConfig.getSupabaseUrl() + "/rest/v1/downloaded_songs"))
                .header("Authorization", "Bearer " + token)
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .header("Prefer", "resolution=merge-duplicates")
                .POST(HttpRequest.BodyPublishers.ofString(json))
                .build();

            HttpResponse<Void> response = httpClient.send(request, HttpResponse.BodyHandlers.discarding());
            if (response.statusCode() >= 200 && response.statusCode() < 300) {
                logger.info("Download metadata saved for user: {} - {} by {}", userId, title, artist);
                return ResponseEntity.ok(Map.of("success", true));
            }
        } catch (Exception e) {
            logger.error("Error saving download metadata: {}", e.getMessage());
        }
        return ResponseEntity.internalServerError().body(Map.of("success", false));
    }

    @DeleteMapping
    public ResponseEntity<Map<String, Object>> deleteDownload(
            @RequestParam String userId,
            @RequestParam String trackId,
            @RequestHeader(value = "Authorization", required = false) String authHeader) {

        String jwt = extractJwt(authHeader);
        String token = (jwt != null && !jwt.isEmpty()) ? jwt : supabaseConfig.getSupabaseAnonKey();

        try {
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/downloaded_songs?user_id=eq." + userId +
                "&track_id=eq." + trackId;

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Authorization", "Bearer " + token)
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .DELETE()
                .build();

            HttpResponse<Void> response = httpClient.send(request, HttpResponse.BodyHandlers.discarding());
            if (response.statusCode() >= 200 && response.statusCode() < 300) {
                logger.info("Download deleted for user: {} track: {}", userId, trackId);
                return ResponseEntity.ok(Map.of("success", true));
            }
        } catch (Exception e) {
            logger.error("Error deleting download: {}", e.getMessage());
        }
        return ResponseEntity.internalServerError().body(Map.of("success", false));
    }

    private String extractJwt(String authHeader) {
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            return authHeader.substring(7);
        }
        return null;
    }
}
