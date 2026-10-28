package com.melo.controller;

import com.melo.service.ListeningHistoryService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/listening")
@CrossOrigin(origins = "*")
public class ListeningHistoryController {

    private static final Logger logger = LoggerFactory.getLogger(ListeningHistoryController.class);

    @Autowired
    private ListeningHistoryService listeningHistoryService;

    @GetMapping("/history")
    public ResponseEntity<Map<String, Object>> getHistory(
            @RequestParam String userId,
            @RequestParam(defaultValue = "30") int days,
            @RequestHeader(value = "Authorization", required = false) String authHeader) {

        String jwt = extractJwt(authHeader);
        List<Map<String, Object>> history = listeningHistoryService.getRecentHistory(userId, days, jwt);
        return ResponseEntity.ok(Map.of("success", true, "history", history));
    }

    @PostMapping("/log")
    public ResponseEntity<Map<String, Object>> logEvent(@RequestBody Map<String, Object> body,
                                                        @RequestHeader(value = "Authorization", required = false) String authHeader) {
        String userId = (String) body.get("userId");
        String trackId = (String) body.get("trackId");
        String title = (String) body.get("title");
        String artist = (String) body.get("artist");
        String image = (String) body.getOrDefault("image", "");
        String genre = (String) body.getOrDefault("genre", "");
        boolean skipped = (boolean) body.getOrDefault("skipped", false);
        boolean completed = (boolean) body.getOrDefault("completed", false);
        boolean replayed = (boolean) body.getOrDefault("replayed", false);
        int listenDuration = (int) body.getOrDefault("listenDuration", 0);
        String source = (String) body.getOrDefault("source", "vibe");
        String artistId = (String) body.getOrDefault("artistId", "");
        String artistImage = (String) body.getOrDefault("artistImage", "");

        String jwt = extractJwt(authHeader);

        logger.info("POST /api/listening/log - {} by {} [skipped={}, completed={}, replayed={}]",
            title, artist, skipped, completed, replayed);

        listeningHistoryService.logEvent(userId, trackId, title, artist, image, genre,
            skipped, completed, replayed, listenDuration, source, artistId, artistImage, jwt);

        return ResponseEntity.ok(Map.of("success", true));
    }

    @PostMapping("/recommend-more")
    public ResponseEntity<Map<String, Object>> recommendMore(@RequestBody Map<String, Object> body,
                                                            @RequestHeader(value = "Authorization", required = false) String authHeader) {
        String userId = (String) body.get("userId");
        String genre = (String) body.get("genre");
        String songKey = (String) body.get("songKey");
        String jwt = extractJwt(authHeader);

        List<String> current = listeningHistoryService.getRecommendMore(userId, genre, jwt);
        if (!current.contains(songKey)) {
            current.add(songKey);
            listeningHistoryService.updateTasteProfile(userId, genre, "recommend_more", current, jwt);
        }

        List<String> less = listeningHistoryService.getRecommendLess(userId, genre, jwt);
        if (less.contains(songKey)) {
            less.remove(songKey);
            listeningHistoryService.updateTasteProfile(userId, genre, "recommend_less", less, jwt);
        }

        logger.info("Recommend more: {} by user {} for genre {}", songKey, userId, genre);
        return ResponseEntity.ok(Map.of("success", true));
    }

    @PostMapping("/recommend-less")
    public ResponseEntity<Map<String, Object>> recommendLess(@RequestBody Map<String, Object> body,
                                                            @RequestHeader(value = "Authorization", required = false) String authHeader) {
        String userId = (String) body.get("userId");
        String genre = (String) body.get("genre");
        String songKey = (String) body.get("songKey");
        String jwt = extractJwt(authHeader);

        List<String> current = listeningHistoryService.getRecommendLess(userId, genre, jwt);
        if (!current.contains(songKey)) {
            current.add(songKey);
            listeningHistoryService.updateTasteProfile(userId, genre, "recommend_less", current, jwt);
        }

        List<String> more = listeningHistoryService.getRecommendMore(userId, genre, jwt);
        if (more.contains(songKey)) {
            more.remove(songKey);
            listeningHistoryService.updateTasteProfile(userId, genre, "recommend_more", more, jwt);
        }

        logger.info("Recommend less: {} by user {} for genre {}", songKey, userId, genre);
        return ResponseEntity.ok(Map.of("success", true));
    }

    @PostMapping("/remove-recommendation")
    public ResponseEntity<Map<String, Object>> removeRecommendation(@RequestBody Map<String, Object> body,
                                                                    @RequestHeader(value = "Authorization", required = false) String authHeader) {
        String userId = (String) body.get("userId");
        String genre = (String) body.get("genre");
        String songKey = (String) body.get("songKey");
        String type = (String) body.get("type");
        String jwt = extractJwt(authHeader);

        String field = "more".equals(type) ? "recommend_more" : "recommend_less";
        List<String> current = listeningHistoryService.getRecommendMore(userId, genre, jwt);
        if ("less".equals(type)) {
            current = listeningHistoryService.getRecommendLess(userId, genre, jwt);
        }

        if (current.contains(songKey)) {
            current.remove(songKey);
            listeningHistoryService.updateTasteProfile(userId, genre, field, current, jwt);
        }

        return ResponseEntity.ok(Map.of("success", true));
    }

    private String extractJwt(String authHeader) {
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            return authHeader.substring(7);
        }
        return null;
    }
}
