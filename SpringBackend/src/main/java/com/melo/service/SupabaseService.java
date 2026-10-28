package com.melo.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.melo.config.SupabaseConfig;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URL;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Map;

@Service
public class SupabaseService {

    private static final Logger logger = LoggerFactory.getLogger(SupabaseService.class);

    @Autowired
    private SupabaseConfig supabaseConfig;

    @Autowired
    private RestTemplate supabaseRestTemplate;

    public String uploadAvatar(String userId, byte[] fileData, String ext) {
        String path = userId + "/profile." + ext;
        String url = supabaseConfig.getSupabaseUrl() + "/storage/v1/object/avatars/" + path;

        try {
            HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Authorization", "Bearer " + supabaseConfig.getSupabaseAnonKey());
            conn.setRequestProperty("apikey", supabaseConfig.getSupabaseAnonKey());
            conn.setRequestProperty("Content-Type", getContentType(ext));
            conn.setRequestProperty("Upsert", "true");
            conn.setRequestProperty("Prefer", "resolution=merge-duplicates");
            conn.setDoOutput(true);

            conn.getOutputStream().write(fileData);
            conn.getOutputStream().flush();

            int code = conn.getResponseCode();
            InputStream is = code >= 400 ? conn.getErrorStream() : conn.getInputStream();
            String response = new String(is.readAllBytes());

            if (code >= 400) {
                logger.error("Upload failed ({}): {}", code, response);
                throw new RuntimeException("Upload failed: " + response);
            }

            String publicUrl = supabaseConfig.getSupabaseUrl() + "/storage/v1/object/public/avatars/" + path;
            logger.info("Avatar uploaded: {}", publicUrl);
            return publicUrl;
        } catch (Exception e) {
            logger.error("Avatar upload error", e);
            throw new RuntimeException("Failed to upload avatar: " + e.getMessage());
        }
    }

    public String uploadPlaylistCover(String userId, String playlistId, byte[] fileData, String ext) {
        String path = "covers/" + userId + "_" + playlistId + "." + ext;
        String url = supabaseConfig.getSupabaseUrl() + "/storage/v1/object/avatars/" + path;

        try {
            HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Authorization", "Bearer " + supabaseConfig.getSupabaseAnonKey());
            conn.setRequestProperty("apikey", supabaseConfig.getSupabaseAnonKey());
            conn.setRequestProperty("Content-Type", getContentType(ext));
            conn.setRequestProperty("Upsert", "true");
            conn.setRequestProperty("Prefer", "resolution=merge-duplicates");
            conn.setDoOutput(true);

            conn.getOutputStream().write(fileData);
            conn.getOutputStream().flush();

            int code = conn.getResponseCode();
            InputStream is = code >= 400 ? conn.getErrorStream() : conn.getInputStream();
            String response = new String(is.readAllBytes());

            if (code >= 400) {
                logger.error("Cover upload failed ({}): {}", code, response);
                throw new RuntimeException("Upload failed: " + response);
            }

            String publicUrl = supabaseConfig.getSupabaseUrl() + "/storage/v1/object/public/avatars/" + path;
            logger.info("Playlist cover uploaded: {}", publicUrl);
            return publicUrl;
        } catch (Exception e) {
            logger.error("Playlist cover upload error", e);
            throw new RuntimeException("Failed to upload playlist cover: " + e.getMessage());
        }
    }

    public boolean checkUsernameAvailable(String username) {
        String url = supabaseConfig.getSupabaseUrl() + "/rest/v1/profiles?username=eq." + username + "&select=id";
        try {
            HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
            conn.setRequestMethod("GET");
            conn.setRequestProperty("Authorization", "Bearer " + supabaseConfig.getSupabaseAnonKey());
            conn.setRequestProperty("apikey", supabaseConfig.getSupabaseAnonKey());

            int code = conn.getResponseCode();
            InputStream is = code >= 400 ? conn.getErrorStream() : conn.getInputStream();
            String response = new String(is.readAllBytes());

            logger.info("Username check response ({}): {}", code, response);
            return code == 200 && (response.equals("[]") || response.isBlank());
        } catch (Exception e) {
            logger.error("Username check error", e);
            return false;
        }
    }

    public void updateProfile(String userId, Map<String, Object> data) {
        updateProfile(userId, data, null);
    }

    public void updateProfile(String userId, Map<String, Object> data, String userToken) {
        String url = supabaseConfig.getSupabaseUrl() + "/rest/v1/profiles?id=eq." + userId;
        String token = userToken != null ? userToken : supabaseConfig.getSupabaseAnonKey();

        try {
            String json = new ObjectMapper().writeValueAsString(data);

            HttpClient client = HttpClient.newHttpClient();
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .header("Authorization", "Bearer " + token)
                    .header("apikey", supabaseConfig.getSupabaseAnonKey())
                    .header("Content-Type", "application/json")
                    .header("Prefer", "return=minimal")
                    .method("PATCH", HttpRequest.BodyPublishers.ofString(json))
                    .build();

            HttpResponse<Void> response = client.send(request, HttpResponse.BodyHandlers.discarding());

            if (response.statusCode() >= 200 && response.statusCode() < 300) {
                logger.info("Profile updated for user: {}", userId);
            } else {
                logger.error("Profile update failed: {}", response.statusCode());
                throw new RuntimeException("Profile update failed: " + response.statusCode());
            }
        } catch (RuntimeException e) {
            throw e;
        } catch (Exception e) {
            logger.error("Profile update error", e);
            throw new RuntimeException("Profile update error: " + e.getMessage());
        }
    }

    private String getContentType(String ext) {
        return switch (ext.toLowerCase()) {
            case "png" -> "image/png";
            case "gif" -> "image/gif";
            case "webp" -> "image/webp";
            default -> "image/jpeg";
        };
    }
}
