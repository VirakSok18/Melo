package com.melo.service;

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
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@Service
public class ArtistFollowService {

    private static final Logger logger = LoggerFactory.getLogger(ArtistFollowService.class);
    private static final ObjectMapper mapper = new ObjectMapper();

    @Autowired
    private SupabaseConfig supabaseConfig;

    private final HttpClient client = HttpClient.newHttpClient();

    public void followArtist(String userId, String artistId, String artistName, String artistImage, String jwt) {
        String url = supabaseConfig.getSupabaseUrl() + "/rest/v1/artist_follows";
        String token = jwt != null ? jwt : supabaseConfig.getSupabaseAnonKey();

        try {
            String json = mapper.writeValueAsString(Map.of(
                "user_id", userId,
                "artist_id", artistId,
                "artist_name", artistName,
                "artist_image", artistImage != null ? artistImage : ""
            ));

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .header("Authorization", "Bearer " + token)
                    .header("apikey", supabaseConfig.getSupabaseAnonKey())
                    .header("Content-Type", "application/json")
                    .header("Prefer", "return=minimal")
                    .POST(HttpRequest.BodyPublishers.ofString(json))
                    .build();

            HttpResponse<Void> response = client.send(request, HttpResponse.BodyHandlers.discarding());

            if (response.statusCode() >= 200 && response.statusCode() < 300) {
                logger.info("Artist followed: {} by user {}", artistId, userId);
            } else if (response.statusCode() == 409) {
                logger.info("Artist already followed: {} by user {}", artistId, userId);
            } else {
                logger.error("Follow artist failed: {}", response.statusCode());
            }
        } catch (Exception e) {
            logger.error("Follow artist error", e);
        }
    }

    public void unfollowArtist(String userId, String artistId, String jwt) {
        String url = supabaseConfig.getSupabaseUrl() + "/rest/v1/artist_follows?user_id=eq." + userId + "&artist_id=eq." + artistId;
        String token = jwt != null ? jwt : supabaseConfig.getSupabaseAnonKey();

        try {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .header("Authorization", "Bearer " + token)
                    .header("apikey", supabaseConfig.getSupabaseAnonKey())
                    .header("Prefer", "return=minimal")
                    .DELETE()
                    .build();

            HttpResponse<Void> response = client.send(request, HttpResponse.BodyHandlers.discarding());

            if (response.statusCode() >= 200 && response.statusCode() < 300) {
                logger.info("Artist unfollowed: {} by user {}", artistId, userId);
            } else {
                logger.error("Unfollow artist failed: {}", response.statusCode());
            }
        } catch (Exception e) {
            logger.error("Unfollow artist error", e);
        }
    }

    public List<Map<String, Object>> getFollowedArtists(String userId, String jwt) {
        String url = supabaseConfig.getSupabaseUrl() + "/rest/v1/artist_follows?user_id=eq." + userId + "&select=artist_id,artist_name,artist_image,created_at&order=created_at.desc";
        String token = jwt != null ? jwt : supabaseConfig.getSupabaseAnonKey();

        try {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .header("Authorization", "Bearer " + token)
                    .header("apikey", supabaseConfig.getSupabaseAnonKey())
                    .header("Content-Type", "application/json")
                    .GET()
                    .build();

            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                return new ArrayList<>(mapper.readValue(response.body(), List.class));
            } else {
                logger.error("Get followed artists failed: {}", response.statusCode());
            }
        } catch (Exception e) {
            logger.error("Get followed artists error", e);
        }

        return List.of();
    }
}
