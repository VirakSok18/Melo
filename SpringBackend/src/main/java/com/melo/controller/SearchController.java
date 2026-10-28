package com.melo.controller;

import com.melo.dto.SearchResultDto;
import com.melo.service.DeezerSearchService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class SearchController {

    private static final Logger logger = LoggerFactory.getLogger(SearchController.class);

    @Autowired
    private DeezerSearchService deezerSearchService;

    @GetMapping("/search")
    public ResponseEntity<Map<String, Object>> search(
            @RequestParam String q,
            @RequestParam(defaultValue = "15") int limit) {

        logger.info("GET /api/search?q={}", q);

        try {
            List<SearchResultDto> results = deezerSearchService.search(q, limit);
            return ResponseEntity.ok(Map.of("success", true, "data", results));
        } catch (Exception e) {
            logger.error("Search failed", e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "success", false,
                    "error", e.getMessage() != null ? e.getMessage() : "Unknown error"
            ));
        }
    }

    @GetMapping("/artist/{id}/top")
    public ResponseEntity<Map<String, Object>> getArtistTopTracks(
            @PathVariable String id,
            @RequestParam(defaultValue = "10") int limit) {

        logger.info("GET /api/artist/{}/top?limit={}", id, limit);

        try {
            List<SearchResultDto> tracks = deezerSearchService.getArtistTopTracks(id, limit);
            return ResponseEntity.ok(Map.of("success", true, "data", tracks));
        } catch (Exception e) {
            logger.error("Artist top tracks failed", e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "success", false,
                    "error", e.getMessage() != null ? e.getMessage() : "Unknown error"
            ));
        }
    }

    @GetMapping("/artist/{id}")
    public ResponseEntity<Map<String, Object>> getArtistInfo(@PathVariable String id) {
        logger.info("GET /api/artist/{}", id);
        try {
            Map<String, Object> info = deezerSearchService.getArtistInfo(id);
            return ResponseEntity.ok(Map.of("success", true, "data", info));
        } catch (Exception e) {
            logger.error("Artist info failed", e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "success", false,
                    "error", e.getMessage() != null ? e.getMessage() : "Unknown error"
            ));
        }
    }

    @GetMapping("/artist/{id}/albums")
    public ResponseEntity<Map<String, Object>> getArtistAlbums(@PathVariable String id) {
        logger.info("GET /api/artist/{}/albums", id);
        try {
            List<Map<String, Object>> albums = deezerSearchService.getArtistAlbums(id);
            return ResponseEntity.ok(Map.of("success", true, "data", albums));
        } catch (Exception e) {
            logger.error("Artist albums failed", e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "success", false,
                    "error", e.getMessage() != null ? e.getMessage() : "Unknown error"
            ));
        }
    }

    @GetMapping("/album/{id}")
    public ResponseEntity<Map<String, Object>> getAlbumInfo(@PathVariable String id) {
        logger.info("GET /api/album/{}", id);
        try {
            Map<String, Object> info = deezerSearchService.getAlbumInfo(id);
            return ResponseEntity.ok(Map.of("success", true, "data", info));
        } catch (Exception e) {
            logger.error("Album info failed", e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "success", false,
                    "error", e.getMessage() != null ? e.getMessage() : "Unknown error"
            ));
        }
    }

    @GetMapping("/album/{id}/tracks")
    public ResponseEntity<Map<String, Object>> getAlbumTracks(@PathVariable String id) {
        logger.info("GET /api/album/{}/tracks", id);
        try {
            List<Map<String, Object>> tracks = deezerSearchService.getAlbumTracks(id);
            return ResponseEntity.ok(Map.of("success", true, "data", tracks));
        } catch (Exception e) {
            logger.error("Album tracks failed", e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "success", false,
                    "error", e.getMessage() != null ? e.getMessage() : "Unknown error"
            ));
        }
    }
}
