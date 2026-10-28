package com.melo.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.melo.service.GenerateService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/generate")
@CrossOrigin(origins = "*")
public class GenerateController {

    private static final Logger logger = LoggerFactory.getLogger(GenerateController.class);

    @Autowired
    private GenerateService generateService;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @PostMapping("/playlist")
    public ResponseEntity<Map<String, Object>> generatePlaylist(
            @RequestBody(required = false) String rawBody,
            @RequestHeader(value = "Authorization", required = false) String authHeader) {

        String jwt = null;
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            jwt = authHeader.substring(7);
        }

        String mood = "";
        int requestedSize = 0;
        String userId = "";
        List<String> artistIds = new ArrayList<>();
        List<String> trackIds = new ArrayList<>();

        try {
            if (rawBody != null && !rawBody.isBlank()) {
                JsonNode body = objectMapper.readTree(rawBody);
                if (body.has("mood")) mood = body.get("mood").asText();
                if (body.has("size") && body.get("size").isNumber()) {
                    requestedSize = body.get("size").asInt();
                }
                if (body.has("userId")) userId = body.get("userId").asText();
                if (body.has("artistIds") && body.get("artistIds").isArray()) {
                    for (JsonNode node : body.get("artistIds")) {
                        artistIds.add(node.asText());
                    }
                }
                if (body.has("trackIds") && body.get("trackIds").isArray()) {
                    for (JsonNode node : body.get("trackIds")) {
                        trackIds.add(node.asText());
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Failed to parse generate request body: {}", e.getMessage());
        }

        if (mood.isBlank() && artistIds.isEmpty() && trackIds.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of(
                "success", false,
                "error", "mood, artistIds, or trackIds is required"
            ));
        }

        logger.info("POST /api/generate/playlist - mood='{}', size={}, userId={}, artistIds={}, trackIds={}",
                mood, requestedSize, userId, artistIds, trackIds);

        try {
            Map<String, Object> result = generateService.generatePlaylist(mood, requestedSize, userId, jwt, artistIds, trackIds);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            logger.error("Playlist generation failed: {}", e.getMessage(), e);
            return ResponseEntity.ok(Map.of(
                "success", false,
                "error", e.getMessage() != null ? e.getMessage() : "Generation failed",
                "songs", java.util.List.of()
            ));
        }
    }
}