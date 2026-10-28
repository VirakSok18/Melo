package com.melo.controller;

import com.melo.service.NewReleasesService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/new-releases")
@CrossOrigin(origins = "*")
public class NewReleasesController {

    private static final Logger logger = LoggerFactory.getLogger(NewReleasesController.class);

    @Autowired
    private NewReleasesService newReleasesService;

    @GetMapping
    public ResponseEntity<Map<String, Object>> getNewReleases(
            @RequestParam String userId,
            @RequestParam(required = false, defaultValue = "false") boolean force) {
        logger.info("GET /api/new-releases - userId='{}', force={}", userId, force);

        try {
            List<Map<String, Object>> songs = newReleasesService.getNewReleases(userId, force);
            return ResponseEntity.ok(Map.of("success", true, "songs", songs));
        } catch (Exception e) {
            logger.error("Failed to get new releases: {}", e.getMessage());
            return ResponseEntity.ok(Map.of("success", true, "songs", List.of()));
        }
    }
}
