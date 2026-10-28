package com.melo.controller;

import com.melo.service.SupabaseService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.Map;

@RestController
@RequestMapping("/api/playlist-cover")
@CrossOrigin(origins = "*")
public class PlaylistCoverController {

    private static final Logger logger = LoggerFactory.getLogger(PlaylistCoverController.class);

    @Autowired
    private SupabaseService supabaseService;

    @PostMapping
    public ResponseEntity<Map<String, Object>> uploadCover(
            @RequestParam("file") MultipartFile file,
            @RequestParam("userId") String userId,
            @RequestParam("playlistId") String playlistId) {

        logger.info("POST /api/playlist-cover for user: {}, playlist: {}", userId, playlistId);

        try {
            String originalName = file.getOriginalFilename();
            String ext = originalName != null && originalName.contains(".")
                    ? originalName.substring(originalName.lastIndexOf(".") + 1)
                    : "jpg";

            String coverUrl = supabaseService.uploadPlaylistCover(userId, playlistId, file.getBytes(), ext);

            return ResponseEntity.ok(Map.of("success", true, "url", coverUrl));
        } catch (Exception e) {
            logger.error("Playlist cover upload failed", e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "success", false,
                    "message", e.getMessage() != null ? e.getMessage() : "Upload failed"
            ));
        }
    }
}
