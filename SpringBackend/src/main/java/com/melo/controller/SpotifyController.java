package com.melo.controller;

import com.melo.dto.ArtistDto;
import com.melo.service.DeezerSearchService;
import com.melo.service.DeezerService;
import com.melo.service.SpotifyService;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

@RestController
@RequestMapping("/api/spotify")
@CrossOrigin(origins = "*")
public class SpotifyController {

    private static final Logger logger = LoggerFactory.getLogger(SpotifyController.class);

    @Autowired
    private SpotifyService spotifyService;

    @Autowired
    private DeezerService deezerService;

    @Autowired
    private DeezerSearchService deezerSearchService;

    private final ConcurrentHashMap<String, String> deezerIdCache = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, ArtistDto> resolvedArtists = new ConcurrentHashMap<>();
    private final AtomicBoolean resolutionDone = new AtomicBoolean(false);

    @PostConstruct
    public void init() {
        new Thread(this::resolveAllDeezerIds, "deezer-id-resolver").start();
    }

    private void resolveAllDeezerIds() {
        logger.info("Starting background resolution of Deezer IDs for curated artists...");
        long start = System.currentTimeMillis();
        List<String> allGenres = List.of("Pop", "Hip Hop", "R&B", "Rock", "Latin", "K-Pop", "Jazz",
                "Electronic", "Indie", "Country", "Metal", "Reggae", "Folk", "Soul", "Punk", "Blues",
                "Alternative", "Dance", "Lo-Fi", "Anime", "Gaming", "Classical", "Ambient");

        List<ArtistDto> allArtists = spotifyService.getCuratedArtists(allGenres);
        ExecutorService executor = Executors.newFixedThreadPool(5);
        List<Future<?>> futures = new ArrayList<>();

        for (ArtistDto artist : allArtists) {
            futures.add(executor.submit(() -> {
                try {
                    String deezerId = artist.getId();
                    if (deezerId != null && !deezerId.isEmpty()) {
                        deezerIdCache.put(artist.getName(), deezerId);
                        resolvedArtists.put(artist.getName(),
                                new ArtistDto(deezerId, artist.getName(), artist.getImage(), artist.getGenres(), artist.getPopularity()));
                    } else {
                        resolvedArtists.put(artist.getName(), artist);
                    }
                } catch (Exception e) {
                    resolvedArtists.put(artist.getName(), artist);
                }
            }));
        }

        for (Future<?> f : futures) {
            try { f.get(10, TimeUnit.SECONDS); } catch (Exception ignored) {}
        }
        executor.shutdown();
        resolutionDone.set(true);
        logger.info("Deezer ID resolution complete: {}/{} artists resolved in {}ms",
                deezerIdCache.size(), allArtists.size(), System.currentTimeMillis() - start);
    }

    @GetMapping("/artists")
    public ResponseEntity<Map<String, Object>> getArtists(
            @RequestParam(required = false) List<String> genres) {

        logger.info("GET /api/spotify/artists?genres={}", genres);

        try {
            if (genres == null || genres.isEmpty()) {
                genres = List.of("Pop", "Hip Hop", "R&B");
            }

            List<ArtistDto> curatedArtists = spotifyService.getCuratedArtists(genres);
            List<ArtistDto> result = new ArrayList<>();

            for (ArtistDto artist : curatedArtists) {
                ArtistDto resolved = resolvedArtists.get(artist.getName());
                result.add(resolved != null ? resolved : artist);
            }

            logger.info("Returning {} curated artists for genres: {} (resolved={})",
                    result.size(), genres, resolutionDone.get());
            return ResponseEntity.ok(Map.of("success", true, "data", result));

        } catch (Exception e) {
            logger.error("Failed to get artists", e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "success", false,
                    "error", e.getClass().getSimpleName(),
                    "message", e.getMessage() != null ? e.getMessage() : "Unknown error"
            ));
        }
    }

    @GetMapping("/search")
    public ResponseEntity<Map<String, Object>> searchArtists(
            @RequestParam String q,
            @RequestParam(defaultValue = "10") int limit) {

        logger.info("GET /api/spotify/search?q={}", q);

        try {
            List<ArtistDto> artists = deezerService.searchArtists(q, limit);
            return ResponseEntity.ok(Map.of("success", true, "data", artists));
        } catch (Exception e) {
            logger.error("Search failed", e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "success", false,
                    "error", e.getClass().getSimpleName(),
                    "message", e.getMessage() != null ? e.getMessage() : "Unknown error"
            ));
        }
    }
}
