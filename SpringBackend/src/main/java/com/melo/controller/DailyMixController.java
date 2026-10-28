package com.melo.controller;

import com.melo.service.DailyMixService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/daily-mixes")
@CrossOrigin(origins = "*")
public class DailyMixController {

    private static final Logger logger = LoggerFactory.getLogger(DailyMixController.class);

    @Autowired
    private DailyMixService dailyMixService;

    @GetMapping
    public ResponseEntity<Map<String, Object>> getDailyMixes(
            @RequestParam String userId,
            @RequestHeader(value = "Authorization", required = false) String authHeader) {

        logger.info("GET /api/daily-mixes - userId={}", userId);

        String jwt = null;
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            jwt = authHeader.substring(7);
        }

        try {
            Map<String, Object> result = dailyMixService.getDailyMixes(userId, jwt);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            logger.error("Failed to get daily mixes: {}", e.getMessage(), e);
            return ResponseEntity.ok(Map.of(
                "success", true,
                "playlists", java.util.List.of()
            ));
        }
    }
}
