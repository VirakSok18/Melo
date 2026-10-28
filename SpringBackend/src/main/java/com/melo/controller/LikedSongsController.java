package com.melo.controller;

import com.melo.service.LikedSongsService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/liked-songs")
@CrossOrigin(origins = "*")
public class LikedSongsController {

    private static final Logger logger = LoggerFactory.getLogger(LikedSongsController.class);

    @Autowired
    private LikedSongsService likedSongsService;

    @GetMapping
    public ResponseEntity<Map<String, Object>> getLikedSongs(
            @RequestParam String userId,
            @RequestHeader(value = "Authorization", required = false) String authHeader) {

        String jwt = null;
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            jwt = authHeader.substring(7);
        }

        List<Map<String, Object>> songs = likedSongsService.getLikedSongs(userId, jwt);
        return ResponseEntity.ok(Map.of("success", true, "songs", songs));
    }

    @PostMapping
    public ResponseEntity<Map<String, Object>> likeSong(
            @RequestBody Map<String, String> body,
            @RequestHeader(value = "Authorization", required = false) String authHeader) {

        String jwt = null;
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            jwt = authHeader.substring(7);
        }

        String userId = body.get("userId");
        String trackId = body.get("trackId");
        String title = body.get("title");
        String artist = body.get("artist");
        String image = body.getOrDefault("image", "");
        String artistId = body.getOrDefault("artistId", "");
        String artistImage = body.getOrDefault("artistImage", "");

        boolean ok = likedSongsService.likeSong(userId, trackId, title, artist, image, artistId, artistImage, jwt);
        return ResponseEntity.ok(Map.of("success", ok));
    }

    @DeleteMapping
    public ResponseEntity<Map<String, Object>> unlikeSong(
            @RequestParam String userId,
            @RequestParam String trackId,
            @RequestHeader(value = "Authorization", required = false) String authHeader) {

        String jwt = null;
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            jwt = authHeader.substring(7);
        }

        boolean ok = likedSongsService.unlikeSong(userId, trackId, jwt);
        return ResponseEntity.ok(Map.of("success", ok));
    }

    @GetMapping("/check")
    public ResponseEntity<Map<String, Object>> checkLiked(
            @RequestParam String userId,
            @RequestParam String trackId,
            @RequestHeader(value = "Authorization", required = false) String authHeader) {

        String jwt = null;
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            jwt = authHeader.substring(7);
        }

        boolean liked = likedSongsService.isSongLiked(userId, trackId, jwt);
        return ResponseEntity.ok(Map.of("success", true, "liked", liked));
    }
}
