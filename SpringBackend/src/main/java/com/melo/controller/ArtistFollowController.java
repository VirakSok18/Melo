package com.melo.controller;

import com.melo.service.ArtistFollowService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/artists")
@CrossOrigin(origins = "*")
public class ArtistFollowController {

    private static final Logger logger = LoggerFactory.getLogger(ArtistFollowController.class);

    @Autowired
    private ArtistFollowService artistFollowService;

    @PostMapping("/follow")
    public ResponseEntity<Map<String, Object>> follow(@RequestBody Map<String, Object> body,
                                                       @RequestHeader(value = "Authorization", required = false) String authHeader) {
        String userId = (String) body.get("userId");
        String artistId = (String) body.get("artistId");
        String artistName = (String) body.get("artistName");
        String artistImage = (String) body.getOrDefault("artistImage", "");
        String jwt = extractJwt(authHeader);

        logger.info("Follow artist: {} ({}) by user {}", artistName, artistId, userId);

        artistFollowService.followArtist(userId, artistId, artistName, artistImage, jwt);

        return ResponseEntity.ok(Map.of("success", true));
    }

    @DeleteMapping("/follow")
    public ResponseEntity<Map<String, Object>> unfollow(@RequestParam String userId,
                                                         @RequestParam String artistId,
                                                         @RequestHeader(value = "Authorization", required = false) String authHeader) {
        String jwt = extractJwt(authHeader);

        logger.info("Unfollow artist: {} by user {}", artistId, userId);

        artistFollowService.unfollowArtist(userId, artistId, jwt);

        return ResponseEntity.ok(Map.of("success", true));
    }

    @GetMapping("/followed")
    public ResponseEntity<Map<String, Object>> getFollowed(@RequestParam String userId,
                                                            @RequestHeader(value = "Authorization", required = false) String authHeader) {
        String jwt = extractJwt(authHeader);

        List<Map<String, Object>> followed = artistFollowService.getFollowedArtists(userId, jwt);

        return ResponseEntity.ok(Map.of("success", true, "artists", followed));
    }

    private String extractJwt(String authHeader) {
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            return authHeader.substring(7);
        }
        return null;
    }
}
