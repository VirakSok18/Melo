package com.melo.controller;

import com.melo.service.ArtistFollowService;
import com.melo.service.SupabaseService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/profile")
@CrossOrigin(origins = "*")
public class ProfileController {

    private static final Logger logger = LoggerFactory.getLogger(ProfileController.class);

    @Autowired
    private SupabaseService supabaseService;

    @Autowired
    private ArtistFollowService artistFollowService;

    @PostMapping("/avatar")
    public ResponseEntity<Map<String, Object>> uploadAvatar(
            @RequestParam("file") MultipartFile file,
            @RequestParam("userId") String userId) {

        logger.info("POST /api/profile/avatar for user: {}", userId);

        try {
            String originalName = file.getOriginalFilename();
            String ext = originalName != null && originalName.contains(".")
                    ? originalName.substring(originalName.lastIndexOf(".") + 1)
                    : "jpg";

            String avatarUrl = supabaseService.uploadAvatar(userId, file.getBytes(), ext);

            supabaseService.updateProfile(userId, Map.of("avatar_url", avatarUrl));

            return ResponseEntity.ok(Map.of("success", true, "url", avatarUrl));
        } catch (Exception e) {
            logger.error("Avatar upload failed", e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "success", false,
                    "message", e.getMessage() != null ? e.getMessage() : "Upload failed"
            ));
        }
    }

    @GetMapping("/check-username")
    public ResponseEntity<Map<String, Object>> checkUsername(@RequestParam String username) {
        logger.info("GET /api/profile/check-username?username={}", username);
        try {
            boolean available = supabaseService.checkUsernameAvailable(username);
            return ResponseEntity.ok(Map.of("success", true, "available", available));
        } catch (Exception e) {
            logger.error("Username check failed", e);
            return ResponseEntity.internalServerError().body(Map.of("success", false, "message", e.getMessage()));
        }
    }

    @PostMapping("/setup")
    public ResponseEntity<Map<String, Object>> completeSetup(
            @RequestBody Map<String, Object> body,
            @RequestHeader(value = "Authorization", required = false) String authHeader) {

        String userId = (String) body.get("userId");
        logger.info("POST /api/profile/setup for user: {}", userId);

        try {
            String userToken = authHeader != null ? authHeader.replace("Bearer ", "") : null;
            java.util.HashMap<String, Object> updates = new java.util.HashMap<>();
            if (body.containsKey("username")) updates.put("username", body.get("username"));
            if (body.containsKey("displayName")) updates.put("display_name", body.get("displayName"));
            if (body.containsKey("avatarUrl")) updates.put("avatar_url", body.get("avatarUrl"));
            if (body.containsKey("favoriteGenres")) updates.put("favorite_genres", body.get("favoriteGenres"));
            if (body.containsKey("favoriteArtists")) updates.put("favorite_artists", body.get("favoriteArtists"));
            updates.put("profile_setup_completed", true);

            supabaseService.updateProfile(userId, updates, userToken);

            // Auto-sync favorite_artists into artist_follows table
            if (body.containsKey("favoriteArtists")) {
                Object artistsObj = body.get("favoriteArtists");
                if (artistsObj instanceof List<?> artistsList) {
                    String jwt = userToken;
                    for (Object artistObj : artistsList) {
                        if (artistObj instanceof Map<?, ?> artistMap) {
                            String artistId = (String) artistMap.get("id");
                            String artistName = (String) artistMap.get("name");
                            String artistImage = artistMap.get("image") != null ? (String) artistMap.get("image") : "";
                            if (artistId != null && artistName != null) {
                                artistFollowService.followArtist(userId, artistId, artistName, artistImage, jwt);
                            }
                        }
                    }
                    logger.info("Auto-synced {} artists as follows for user {}", artistsList.size(), userId);
                }
            }

            return ResponseEntity.ok(Map.of("success", true));
        } catch (Exception e) {
            logger.error("Setup failed", e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "success", false,
                    "message", e.getMessage() != null ? e.getMessage() : "Setup failed"
            ));
        }
    }
}
