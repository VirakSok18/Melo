package com.melo.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.melo.config.SupabaseConfig;
import com.melo.dto.SearchResultDto;
import com.melo.service.DeezerSearchService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.LocalDate;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

@RestController
@RequestMapping("/api/vibe")
@CrossOrigin(origins = "*")
public class VibeController {

    private static final Logger logger = LoggerFactory.getLogger(VibeController.class);

    private static final int TOTAL_TRACKS = 20;
    private static final int PERSONALIZED_RATIO = 3;
    private static final int CLASSIC_RATIO = 7;

    @Autowired
    private DeezerSearchService deezerSearchService;

    @Autowired
    private SupabaseConfig supabaseConfig;

    private final HttpClient httpClient = HttpClient.newHttpClient();
    private final ObjectMapper objectMapper = new ObjectMapper();

    private final Map<String, List<Map<String, String>>> classicsCache = new ConcurrentHashMap<>();

    @GetMapping("/playlist")
    public ResponseEntity<Map<String, Object>> getPlaylist(
            @RequestParam String userId,
            @RequestParam String genre,
            @RequestParam(defaultValue = "false") boolean force) {

        logger.info("GET /api/vibe/playlist - userId={}, genre={}, force={}", userId, genre, force);

        try {
            if (!force) {
                List<Map<String, String>> cached = getTodayPlaylist(userId, genre);
                if (cached != null && !cached.isEmpty()) {
                    return ResponseEntity.ok(Map.of(
                        "success", true,
                        "songs", cached
                    ));
                }
            }

            List<Map<String, String>> tracks = buildPersonalizedPlaylist(userId, genre);
            if (!tracks.isEmpty()) {
                savePlaylist(userId, genre, tracks);
            }

            return ResponseEntity.ok(Map.of(
                "success", true,
                "songs", tracks
            ));

        } catch (Exception e) {
            logger.error("Playlist generation failed for genre {}: {}", genre, e.getMessage(), e);
            return ResponseEntity.ok(Map.of(
                "success", true,
                "songs", List.of()
            ));
        }
    }

    @PostMapping("/playlists")
    public ResponseEntity<Map<String, Object>> getBatchPlaylists(
            @RequestParam String userId,
            @RequestBody List<String> genres) {

        logger.info("POST /api/vibe/playlists - userId={}, genres={}", userId, genres);

        try {
            Map<String, List<Map<String, String>>> allResults = new LinkedHashMap<>();

            for (String genre : genres) {
                List<Map<String, String>> tracks = buildPersonalizedPlaylist(userId, genre);
                if (!tracks.isEmpty()) {
                    savePlaylist(userId, genre, tracks);
                }
                allResults.put(genre, tracks);
            }

            return ResponseEntity.ok(Map.of(
                "success", true,
                "playlists", allResults
            ));

        } catch (Exception e) {
            logger.error("Batch playlist generation failed: {}", e.getMessage(), e);
            return ResponseEntity.ok(Map.of(
                "success", true,
                "playlists", Map.of()
            ));
        }
    }

    private List<Map<String, String>> buildPersonalizedPlaylist(String userId, String genre) {
        List<String[]> userArtists = getUserFavoriteArtists(userId);
        List<String[]> matchingArtists = matchArtistsToGenre(genre, userArtists);

        if (matchingArtists.isEmpty()) {
            List<Map<String, String>> allClassics = resolveClassics(genre, TOTAL_TRACKS);
            logger.info("No matching artists for '{}', returning {} classics", genre, allClassics.size());
            return allClassics;
        }

        int classicCount = (TOTAL_TRACKS * CLASSIC_RATIO) / (PERSONALIZED_RATIO + CLASSIC_RATIO);
        int personalizedCount = TOTAL_TRACKS - classicCount;

        List<Map<String, String>> classics = resolveClassics(genre, classicCount + 4);
        List<Map<String, String>> personalized = getUserArtistTracks(matchingArtists, personalizedCount + 2);

        // Interleave tracks so artists are mixed evenly across the playlist
        Collections.shuffle(personalized);
        Collections.shuffle(classics);

        Set<String> seen = new LinkedHashSet<>();
        List<Map<String, String>> playlist = new ArrayList<>();

        int pIdx = 0;
        int cIdx = 0;
        while (playlist.size() < TOTAL_TRACKS && (pIdx < personalized.size() || cIdx < classics.size())) {
            if (pIdx < personalized.size() && playlist.size() < personalizedCount) {
                Map<String, String> track = personalized.get(pIdx++);
                String key = (track.getOrDefault("title", "").toLowerCase() + "|" + track.getOrDefault("artist", "").toLowerCase());
                if (seen.add(key)) playlist.add(track);
            }
            if (cIdx < classics.size() && playlist.size() < TOTAL_TRACKS) {
                Map<String, String> track = classics.get(cIdx++);
                String key = (track.getOrDefault("title", "").toLowerCase() + "|" + track.getOrDefault("artist", "").toLowerCase());
                if (seen.add(key)) playlist.add(track);
            }
            if (pIdx >= personalized.size() && cIdx >= classics.size()) break;
        }

        // If still under 20, fill with more classics
        if (playlist.size() < TOTAL_TRACKS) {
            List<Map<String, String>> extraClassics = resolveClassics(genre, TOTAL_TRACKS + 5);
            for (Map<String, String> track : extraClassics) {
                String key = (track.getOrDefault("title", "").toLowerCase() + "|" + track.getOrDefault("artist", "").toLowerCase());
                if (seen.add(key)) {
                    playlist.add(track);
                }
                if (playlist.size() >= TOTAL_TRACKS) break;
            }
        }

        Collections.shuffle(playlist);
        logger.info("Built playlist for '{}': {} total (interleaved and shuffled)", genre, playlist.size());
        return playlist;
    }

    private List<String[]> getUserFavoriteArtists(String userId) {
        Map<String, String> artistMap = new LinkedHashMap<>();
        try {
            // 1. Fetch onboarding favorite artists
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/profiles?id=eq." + userId + "&select=favorite_artists";

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Authorization", "Bearer " + supabaseConfig.getSupabaseAnonKey())
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .GET()
                .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 200) {
                JsonNode json = objectMapper.readTree(response.body());
                if (json.isArray() && json.size() > 0) {
                    JsonNode artists = json.get(0).get("favorite_artists");
                    if (artists != null && artists.isArray()) {
                        for (JsonNode a : artists) {
                            String name = a.has("name") ? a.get("name").asText() : "";
                            String id = a.has("id") ? a.get("id").asText() : "";
                            if (!name.isEmpty()) {
                                artistMap.put(name.toLowerCase(), id);
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Failed to fetch user favorite artists: {}", e.getMessage());
        }

        try {
            // 2. Fetch followed artists
            String followsUrl = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/artist_follows?user_id=eq." + userId + "&select=artist_id,artist_name";

            HttpRequest followsRequest = HttpRequest.newBuilder()
                .uri(URI.create(followsUrl))
                .header("Authorization", "Bearer " + supabaseConfig.getSupabaseAnonKey())
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .GET()
                .build();

            HttpResponse<String> followsResp = httpClient.send(followsRequest, HttpResponse.BodyHandlers.ofString());
            if (followsResp.statusCode() == 200) {
                JsonNode json = objectMapper.readTree(followsResp.body());
                if (json.isArray()) {
                    for (JsonNode f : json) {
                        String name = f.has("artist_name") ? f.get("artist_name").asText() : "";
                        String id = f.has("artist_id") ? f.get("artist_id").asText() : "";
                        if (!name.isEmpty()) {
                            artistMap.put(name.toLowerCase(), id);
                        }
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Failed to fetch user artist follows: {}", e.getMessage());
        }

        List<String[]> result = new ArrayList<>();
        for (Map.Entry<String, String> entry : artistMap.entrySet()) {
            result.add(new String[]{entry.getValue(), entry.getKey()});
        }
        return result;
    }

    private List<String[]> matchArtistsToGenre(String genre, List<String[]> userArtists) {
        List<String[]> matched = new ArrayList<>();
        try {
            ClassPathResource resource = new ClassPathResource("artists.json");
            JsonNode json = objectMapper.readTree(resource.getInputStream());
            JsonNode genreNode = json.get(genre);
            if (genreNode == null || !genreNode.isArray()) return matched;

            Map<String, String> genreArtistDeezerIds = new HashMap<>();
            for (JsonNode node : genreNode) {
                if (node.has("name") && node.has("id")) {
                    genreArtistDeezerIds.put(node.get("name").asText().toLowerCase(), node.get("id").asText());
                }
            }

            for (String[] artist : userArtists) {
                String deezerId = genreArtistDeezerIds.get(artist[1].toLowerCase());
                if (deezerId != null) {
                    matched.add(new String[]{deezerId, artist[1]});
                }
            }
        } catch (Exception e) {
            logger.warn("Failed to match artists to genre '{}': {}", genre, e.getMessage());
        }
        return matched;
    }

    private List<Map<String, String>> getUserArtistTracks(List<String[]> matchingArtists, int count) {
        List<Map<String, String>> tracks = new ArrayList<>();
        if (matchingArtists.isEmpty()) return tracks;

        int tracksPerArtist = Math.max(1, count / matchingArtists.size());

        for (String[] artist : matchingArtists) {
            if (tracks.size() >= count) break;
            try {
                String deezerId = artist[0];
                boolean isDeezerId = deezerId.matches("\\d+");

                String artistId;
                if (isDeezerId) {
                    artistId = deezerId;
                } else {
                    String foundId = deezerSearchService.findArtistId(artist[1]);
                    if (foundId == null) continue;
                    artistId = foundId;
                }

                List<SearchResultDto> topTracks = deezerSearchService.getArtistTopTracks(artistId, tracksPerArtist + 2);
                for (SearchResultDto track : topTracks) {
                    if (tracks.size() >= count) break;
                    Map<String, String> item = new LinkedHashMap<>();
                    item.put("title", track.getTitle());
                    item.put("artist", track.getArtist());
                    item.put("artistId", track.getArtistId() != null ? track.getArtistId() : "");
                    item.put("artistImage", track.getArtistImage() != null ? track.getArtistImage() : "");
                    item.put("image", track.getImage() != null ? track.getImage() : "");
                    item.put("duration", track.getDuration() != null ? track.getDuration() : "");
                    item.put("deezerId", track.getId());
                    item.put("previewUrl", track.getPreviewUrl() != null ? track.getPreviewUrl() : "");
                    item.put("source", "personalized");
                    tracks.add(item);
                }
            } catch (Exception e) {
                logger.warn("Failed to get tracks for artist '{}': {}", artist[1], e.getMessage());
            }
        }
        return tracks;
    }

    private List<Map<String, String>> resolveClassics(String genre, int limit) {
        String cacheKey = genre + "_" + limit;
        if (classicsCache.containsKey(cacheKey)) {
            return classicsCache.get(cacheKey);
        }

        List<String[]> curatedTracks = loadCuratedTracks(genre);
        if (curatedTracks.isEmpty()) {
            logger.warn("No curated tracks found for genre '{}'", genre);
            return List.of();
        }

        List<Map<String, String>> resolved = new ArrayList<>();
        for (String[] track : curatedTracks) {
            if (resolved.size() >= limit) break;
            String title = track[0];
            String artist = track[1];

            try {
                String query = title + " " + artist;
                List<SearchResultDto> results = deezerSearchService.searchTracksOnly(query, 5);

                SearchResultDto bestMatch = null;
                for (SearchResultDto r : results) {
                    if (r.getTitle().equalsIgnoreCase(title) && r.getArtist().equalsIgnoreCase(artist)) {
                        bestMatch = r;
                        break;
                    }
                }

                if (bestMatch == null && !results.isEmpty()) {
                    bestMatch = results.get(0);
                }

                if (bestMatch != null) {
                    Map<String, String> item = new LinkedHashMap<>();
                    item.put("title", bestMatch.getTitle());
                    item.put("artist", bestMatch.getArtist());
                    item.put("artistId", bestMatch.getArtistId() != null ? bestMatch.getArtistId() : "");
                    item.put("artistImage", bestMatch.getArtistImage() != null ? bestMatch.getArtistImage() : "");
                    item.put("image", bestMatch.getImage() != null ? bestMatch.getImage() : "");
                    item.put("duration", bestMatch.getDuration() != null ? bestMatch.getDuration() : "");
                    item.put("deezerId", bestMatch.getId());
                    item.put("previewUrl", bestMatch.getPreviewUrl() != null ? bestMatch.getPreviewUrl() : "");
                    item.put("source", "classic");
                    resolved.add(item);
                } else {
                    Map<String, String> item = new LinkedHashMap<>();
                    item.put("title", title);
                    item.put("artist", artist);
                    item.put("artistId", "");
                    item.put("artistImage", "");
                    item.put("image", "");
                    item.put("duration", "");
                    item.put("deezerId", "");
                    item.put("previewUrl", "");
                    item.put("source", "classic");
                    resolved.add(item);
                }
            } catch (Exception e) {
                logger.warn("Failed to resolve track '{} - {}': {}", title, artist, e.getMessage());
                Map<String, String> item = new LinkedHashMap<>();
                item.put("title", title);
                item.put("artist", artist);
                item.put("artistId", "");
                item.put("artistImage", "");
                item.put("image", "");
                item.put("duration", "");
                item.put("deezerId", "");
                item.put("previewUrl", "");
                item.put("source", "classic");
                resolved.add(item);
            }
        }

        classicsCache.put(cacheKey, resolved);
        return resolved;
    }

    private List<String[]> loadCuratedTracks(String genre) {
        try {
            ClassPathResource resource = new ClassPathResource("genre_tracks.json");
            JsonNode json = objectMapper.readTree(resource.getInputStream());
            JsonNode genreNode = json.get(genre);
            if (genreNode != null && genreNode.isArray()) {
                List<String[]> tracks = new ArrayList<>();
                for (JsonNode node : genreNode) {
                    String title = node.has("title") ? node.get("title").asText() : "";
                    String artist = node.has("artist") ? node.get("artist").asText() : "";
                    if (!title.isEmpty() && !artist.isEmpty()) {
                        tracks.add(new String[]{title, artist});
                    }
                }
                return tracks;
            }
        } catch (Exception e) {
            logger.warn("Failed to load curated tracks for genre '{}': {}", genre, e.getMessage());
        }
        return List.of();
    }

    private List<Map<String, String>> getTodayPlaylist(String userId, String genre) {
        try {
            String date = LocalDate.now().toString();
            String encodedGenre = URLEncoder.encode(genre, "UTF-8");
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/daily_playlists?user_id=eq." + userId +
                "&genre=eq." + encodedGenre +
                "&playlist_date=eq." + date +
                "&select=songs";

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Authorization", "Bearer " + supabaseConfig.getSupabaseAnonKey())
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .GET()
                .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                JsonNode json = objectMapper.readTree(response.body());
                if (json.isArray() && json.size() > 0) {
                    JsonNode songs = json.get(0).get("songs");
                    if (songs != null && songs.isArray()) {
                        List<Map<String, String>> result = new ArrayList<>();
                        for (JsonNode song : songs) {
                            Map<String, String> entry = new LinkedHashMap<>();
                            entry.put("title", song.get("title").asText());
                            entry.put("artist", song.get("artist").asText());
                            entry.put("image", song.has("image") ? song.get("image").asText() : "");
                            entry.put("duration", song.has("duration") ? song.get("duration").asText() : "");
                            entry.put("deezerId", song.has("deezerId") ? song.get("deezerId").asText() : "");
                            entry.put("previewUrl", song.has("previewUrl") ? song.get("previewUrl").asText() : "");
                            result.add(entry);
                        }
                        return result;
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Failed to fetch cached playlist: {}", e.getMessage());
        }
        return null;
    }

    private void savePlaylist(String userId, String genre, List<Map<String, String>> playlist) {
        try {
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("user_id", userId);
            body.put("genre", genre);
            body.put("playlist_date", LocalDate.now().toString());
            body.put("songs", playlist);

            String json = objectMapper.writeValueAsString(body);

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(supabaseConfig.getSupabaseUrl() + "/rest/v1/daily_playlists"))
                .header("Authorization", "Bearer " + supabaseConfig.getSupabaseAnonKey())
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .header("Prefer", "resolution=merge-duplicates")
                .POST(HttpRequest.BodyPublishers.ofString(json))
                .build();

            httpClient.send(request, HttpResponse.BodyHandlers.discarding());
            logger.info("Playlist saved for user {} genre {} with {} songs", userId, genre, playlist.size());
        } catch (Exception e) {
            logger.error("Failed to save playlist: {}", e.getMessage());
        }
    }
}
