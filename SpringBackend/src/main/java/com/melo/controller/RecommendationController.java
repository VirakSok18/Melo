package com.melo.controller;

import com.melo.dto.SearchResultDto;
import com.melo.service.RecommendationService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/recommendations")
@CrossOrigin(origins = "*")
public class RecommendationController {

    private static final Logger logger = LoggerFactory.getLogger(RecommendationController.class);

    @Autowired
    private RecommendationService recommendationService;

    @GetMapping("/next")
    public ResponseEntity<Map<String, Object>> getSmartQueue(
            @RequestParam String artist,
            @RequestParam(defaultValue = "15") int limit) {

        logger.info("GET /api/recommendations/next?artist={}&limit={}", artist, limit);

        try {
            List<SearchResultDto> tracks = recommendationService.getSmartQueue(artist, limit);
            return ResponseEntity.ok(Map.of("success", true, "data", tracks));
        } catch (Exception e) {
            logger.error("Smart queue generation failed", e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "success", false,
                    "error", e.getMessage() != null ? e.getMessage() : "Unknown error"
            ));
        }
    }
}
