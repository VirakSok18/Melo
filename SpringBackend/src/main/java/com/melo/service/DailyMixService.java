package com.melo.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.melo.config.SupabaseConfig;
import com.melo.dto.SearchResultDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.LocalDate;
import java.util.*;

@Service
public class DailyMixService {

    private static final Logger logger = LoggerFactory.getLogger(DailyMixService.class);

    @Autowired
    private SupabaseConfig supabaseConfig;

    @Autowired
    private DeezerSearchService deezerSearchService;

    @Autowired
    private ListeningHistoryService listeningHistoryService;

    private final HttpClient httpClient = HttpClient.newHttpClient();
    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final int SONGS_PER_PLAYLIST = 20;

    public Map<String, Object> getDailyMixes(String userId, String jwt) {
        String today = LocalDate.now().toString();

        String token = (jwt != null && !jwt.isEmpty()) ? jwt : supabaseConfig.getSupabaseAnonKey();

        // Check cache FIRST — if all 3 mixes exist for today, return immediately
        List<Map<String, Object>> allMixes = new ArrayList<>();
        boolean allCached = true;
        for (int i = 1; i <= 3; i++) {
            List<Map<String, String>> cached = getTodayMix(userId, i, today, token);
            if (cached != null && !cached.isEmpty()) {
                allMixes.add(buildMixResponse(i, cached));
            } else {
                allCached = false;
                break;
            }
        }
        if (allCached) {
            logger.info("All 3 daily mixes cached for today, user {}", userId);
            return Map.of("success", true, "playlists", allMixes);
        }
        allMixes.clear();

        // Cache miss — load data for generation
        Map<String, Object> profile = loadProfile(userId, jwt);
        List<String> favoriteArtists = extractStringList(profile, "favorite_artists", "name");

        List<Map<String, Object>> history = listeningHistoryService.getRecentHistory(userId, 30, token);
        boolean hasHistory = !history.isEmpty();

        List<Map<String, Object>> topArtists;
        if (hasHistory) {
            topArtists = listeningHistoryService.getTopArtistsByCompletion(history, 15);
        } else {
            topArtists = new ArrayList<>();
            for (String name : favoriteArtists) {
                topArtists.add(Map.of("artist", name, "score", 100));
            }
        }

        List<Map<String, Object>> topGenres;
        if (hasHistory) {
            topGenres = listeningHistoryService.getTopGenres(history, 5);
        } else {
            topGenres = List.of();
        }

        Set<String> recentlyPlayed = getRecentlyPlayedSongs(userId, 3, token);

        for (int i = 1; i <= 3; i++) {
            List<Map<String, String>> cached = getTodayMix(userId, i, today, token);
            if (cached != null && !cached.isEmpty()) {
                allMixes.add(buildMixResponse(i, cached));
                continue;
            }

            List<Map<String, String>> playlist;
            switch (i) {
                case 1:
                    playlist = buildYourMix(topArtists, history, recentlyPlayed, hasHistory, favoriteArtists);
                    break;
                case 2:
                    playlist = buildDiscoveryMix(topArtists, topGenres, history, recentlyPlayed, hasHistory, favoriteArtists);
                    break;
                default:
                    playlist = buildYourRadio(topArtists, history, recentlyPlayed, hasHistory, favoriteArtists);
                    break;
            }

            playlist.removeIf(song -> recentlyPlayed.contains(
                (song.get("title") + "|" + song.get("artist")).toLowerCase()));

            if (playlist.size() < SONGS_PER_PLAYLIST) {
                fillWithCharts(playlist, SONGS_PER_PLAYLIST - playlist.size(), recentlyPlayed);
            }

            Collections.shuffle(playlist);
            if (playlist.size() > SONGS_PER_PLAYLIST) {
                playlist = playlist.subList(0, SONGS_PER_PLAYLIST);
            }

            if (!playlist.isEmpty()) {
                saveMix(userId, i, today, playlist, token);
            }
            allMixes.add(buildMixResponse(i, playlist));
        }

        return Map.of("success", true, "playlists", allMixes);
    }

    private List<Map<String, String>> buildYourMix(List<Map<String, Object>> topArtists,
                                                     List<Map<String, Object>> history,
                                                     Set<String> recentlyPlayed,
                                                     boolean hasHistory,
                                                     List<String> favoriteArtists) {
        List<Map<String, String>> playlist = new ArrayList<>();
        Set<String> usedSongs = new HashSet<>();

        if (hasHistory) {
            // Score every unique song from history
            Map<String, int[]> songScores = new LinkedHashMap<>();
            Map<String, Map<String, String>> songInfo = new LinkedHashMap<>();

            for (Map<String, Object> entry : history) {
                String title = (String) entry.getOrDefault("title", "");
                String artist = (String) entry.getOrDefault("artist", "");
                String key = title.toLowerCase() + "|" + artist.toLowerCase();
                if (key.equals("|")) continue;

                songScores.putIfAbsent(key, new int[]{0, 0, 0});
                if ((Boolean) entry.getOrDefault("completed", false)) songScores.get(key)[0]++;
                if ((Boolean) entry.getOrDefault("replayed", false)) songScores.get(key)[1]++;
                if ((Boolean) entry.getOrDefault("skipped", false)) songScores.get(key)[2]++;

                songInfo.putIfAbsent(key, Map.of(
                    "title", title,
                    "artist", artist,
                    "image", entry.getOrDefault("image", "").toString()
                ));
            }

            // Sort by score and take top songs
            List<Map.Entry<String, int[]>> sorted = new ArrayList<>(songScores.entrySet());
            sorted.sort((a, b) -> {
                int scoreA = b.getValue()[0] * 10 + b.getValue()[1] * 20 - b.getValue()[2] * 5;
                int scoreB = a.getValue()[0] * 10 + a.getValue()[1] * 20 - a.getValue()[2] * 5;
                return scoreA - scoreB;
            });

            for (Map.Entry<String, int[]> entry : sorted) {
                if (playlist.size() >= SONGS_PER_PLAYLIST) break;
                String songKey = entry.getKey();
                if (recentlyPlayed.contains(songKey)) continue;
                if (usedSongs.contains(songKey)) continue;

                Map<String, String> info = songInfo.get(songKey);
                if (info == null) continue;
                playlist.add(createSongMap(
                    new SearchResultDto("song", "", info.get("title"), info.get("artist"),
                        info.getOrDefault("image", ""), "", 0, "", 0)));
                usedSongs.add(songKey);
            }
        } else {
            // Cold start: get top tracks from favorite artists
            for (String artistName : favoriteArtists) {
                if (playlist.size() >= SONGS_PER_PLAYLIST) break;
                try {
                    String artistId = deezerSearchService.findArtistId(artistName);
                    if (artistId == null) continue;
                    List<SearchResultDto> tracks = deezerSearchService.getArtistTopTracks(artistId, 4);
                    for (SearchResultDto track : tracks) {
                        if (playlist.size() >= SONGS_PER_PLAYLIST) break;
                        String songKey = (track.getTitle() + "|" + track.getArtist()).toLowerCase();
                        if (usedSongs.contains(songKey)) continue;
                        playlist.add(createSongMap(track));
                        usedSongs.add(songKey);
                    }
                } catch (Exception e) {
                    logger.warn("Cold start mix1 failed for '{}': {}", artistName, e.getMessage());
                }
            }
        }

        return playlist;
    }

    private List<Map<String, String>> buildDiscoveryMix(List<Map<String, Object>> topArtists,
                                                         List<Map<String, Object>> topGenres,
                                                         List<Map<String, Object>> history,
                                                         Set<String> recentlyPlayed,
                                                         boolean hasHistory,
                                                         List<String> favoriteArtists) {
        List<Map<String, String>> playlist = new ArrayList<>();
        Set<String> usedSongs = new HashSet<>();

        int targetFamiliar = SONGS_PER_PLAYLIST / 2;
        int targetNew = SONGS_PER_PLAYLIST - targetFamiliar;

        // 50% familiar: songs from history + popular tracks
        if (hasHistory) {
            Map<String, int[]> songScores = new LinkedHashMap<>();
            Map<String, Map<String, String>> songInfo = new LinkedHashMap<>();

            for (Map<String, Object> entry : history) {
                String title = (String) entry.getOrDefault("title", "");
                String artist = (String) entry.getOrDefault("artist", "");
                String key = title.toLowerCase() + "|" + artist.toLowerCase();
                if (key.equals("|")) continue;

                songScores.putIfAbsent(key, new int[]{0, 0, 0});
                if ((Boolean) entry.getOrDefault("completed", false)) songScores.get(key)[0]++;
                if ((Boolean) entry.getOrDefault("replayed", false)) songScores.get(key)[1]++;
                if ((Boolean) entry.getOrDefault("skipped", false)) songScores.get(key)[2]++;

                songInfo.putIfAbsent(key, Map.of(
                    "title", title,
                    "artist", artist,
                    "image", entry.getOrDefault("image", "").toString()
                ));
            }

            List<Map.Entry<String, int[]>> sorted = new ArrayList<>(songScores.entrySet());
            sorted.sort((a, b) -> {
                int scoreA = b.getValue()[0] * 10 + b.getValue()[1] * 20 - b.getValue()[2] * 5;
                int scoreB = a.getValue()[0] * 10 + a.getValue()[1] * 20 - a.getValue()[2] * 5;
                return scoreA - scoreB;
            });

            int count = 0;
            for (Map.Entry<String, int[]> entry : sorted) {
                if (count >= targetFamiliar) break;
                String songKey = entry.getKey();
                if (recentlyPlayed.contains(songKey)) continue;
                if (usedSongs.contains(songKey)) continue;

                Map<String, String> info = songInfo.get(songKey);
                if (info == null) continue;
                playlist.add(createSongMap(
                    new SearchResultDto("song", "", info.get("title"), info.get("artist"),
                        info.getOrDefault("image", ""), "", 0, "", 0)));
                usedSongs.add(songKey);
                count++;
            }
        }

        // 50% new: popular tracks from artists similar to top artists
        // Use genre-based search to find similar music (more reliable than Deezer related API)
        List<String> searchQueries = new ArrayList<>();

        // Get genres from top artists to search for similar music
        for (Map<String, Object> genreEntry : topGenres) {
            String genre = (String) genreEntry.get("genre");
            if (!genre.isEmpty()) {
                searchQueries.add(genre + " popular");
                searchQueries.add(genre + " hits");
            }
        }

        // Also use top artist names for search
        List<String> seedArtists = new ArrayList<>();
        for (Map<String, Object> a : topArtists) {
            seedArtists.add((String) a.get("artist"));
        }
        if (seedArtists.isEmpty()) {
            seedArtists.addAll(favoriteArtists);
        }

        // Get top 5 artist names for genre discovery
        for (int i = 0; i < Math.min(5, seedArtists.size()); i++) {
            searchQueries.add(seedArtists.get(i) + " similar");
        }

        int count = 0;
        for (String query : searchQueries) {
            if (count >= targetNew) break;
            try {
                List<SearchResultDto> tracks = deezerSearchService.search(query, 5);
                for (SearchResultDto track : tracks) {
                    if (count >= targetNew) break;
                    String songKey = (track.getTitle() + "|" + track.getArtist()).toLowerCase();
                    if (recentlyPlayed.contains(songKey)) continue;
                    if (usedSongs.contains(songKey)) continue;
                    if ("song".equals(track.getType())) {
                        playlist.add(createSongMap(track));
                        usedSongs.add(songKey);
                        count++;
                    }
                }
            } catch (Exception e) {
                logger.warn("Discovery search failed for '{}': {}", query, e.getMessage());
            }
        }

        return playlist;
    }

    private List<Map<String, String>> buildYourRadio(List<Map<String, Object>> topArtists,
                                                      List<Map<String, Object>> history,
                                                      Set<String> recentlyPlayed,
                                                      boolean hasHistory,
                                                      List<String> favoriteArtists) {
        List<Map<String, String>> playlist = new ArrayList<>();
        Set<String> usedSongs = new HashSet<>();

        // 30% mixed artists: grab top tracks from a wider set of artists
        List<String> seedArtists = new ArrayList<>();
        for (Map<String, Object> a : topArtists) {
            seedArtists.add((String) a.get("artist"));
        }
        if (seedArtists.isEmpty()) {
            seedArtists.addAll(favoriteArtists);
        }

        int targetMixed = (int) (SONGS_PER_PLAYLIST * 0.3);
        int count = 0;

        // Get top 3-4 tracks from each top artist (mix of favorites)
        for (String artistName : seedArtists) {
            if (count >= targetMixed) break;
            try {
                String artistId = deezerSearchService.findArtistId(artistName);
                if (artistId == null) continue;
                List<SearchResultDto> tracks = deezerSearchService.getArtistTopTracks(artistId, 3);
                for (SearchResultDto track : tracks) {
                    if (count >= targetMixed) break;
                    String songKey = (track.getTitle() + "|" + track.getArtist()).toLowerCase();
                    if (recentlyPlayed.contains(songKey)) continue;
                    if (usedSongs.contains(songKey)) continue;
                    playlist.add(createSongMap(track));
                    usedSongs.add(songKey);
                    count++;
                }
            } catch (Exception e) {
                logger.warn("Radio mix failed for '{}': {}", artistName, e.getMessage());
            }
        }

        // 70% listening history: your most-listened songs
        if (hasHistory) {
            Map<String, int[]> songCounts = new LinkedHashMap<>();
            Map<String, Map<String, String>> songInfo = new LinkedHashMap<>();

            for (Map<String, Object> entry : history) {
                String title = (String) entry.getOrDefault("title", "");
                String artist = (String) entry.getOrDefault("artist", "");
                String key = title.toLowerCase() + "|" + artist.toLowerCase();
                if (key.equals("|")) continue;

                songCounts.putIfAbsent(key, new int[]{0, 0, 0});
                songCounts.get(key)[0]++;
                if ((Boolean) entry.getOrDefault("completed", false)) songCounts.get(key)[1]++;
                if ((Boolean) entry.getOrDefault("replayed", false)) songCounts.get(key)[2]++;

                songInfo.putIfAbsent(key, Map.of(
                    "title", title,
                    "artist", artist,
                    "image", entry.getOrDefault("image", "").toString()
                ));
            }

            List<Map.Entry<String, int[]>> sorted = new ArrayList<>(songCounts.entrySet());
            sorted.sort((a, b) -> {
                int scoreA = b.getValue()[0] * 5 + b.getValue()[1] * 15 + b.getValue()[2] * 10;
                int scoreB = a.getValue()[0] * 5 + a.getValue()[1] * 15 + a.getValue()[2] * 10;
                return scoreA - scoreB;
            });

            for (Map.Entry<String, int[]> entry : sorted) {
                if (playlist.size() >= SONGS_PER_PLAYLIST) break;
                String songKey = entry.getKey();
                if (recentlyPlayed.contains(songKey)) continue;
                if (usedSongs.contains(songKey)) continue;

                Map<String, String> info = songInfo.get(songKey);
                if (info == null) continue;
                playlist.add(createSongMap(
                    new SearchResultDto("song", "", info.get("title"), info.get("artist"),
                        info.getOrDefault("image", ""), "", 0, "", 0)));
                usedSongs.add(songKey);
            }
        }

        return playlist;
    }

    private Map<String, Object> buildMixResponse(int number, List<Map<String, String>> songs) {
        String name;
        String description;
        switch (number) {
            case 1:
                name = "Your Mix";
                description = "Songs you know and love";
                break;
            case 2:
                name = "Discovery Mix";
                description = "Your favorites plus new finds";
                break;
            default:
                name = "Your Radio";
                description = "Your top artists and most-played songs";
                break;
        }
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("number", number);
        response.put("name", name);
        response.put("description", description);
        response.put("songs", songs);
        return response;
    }

    private void fillWithCharts(List<Map<String, String>> playlist, int needed, Set<String> recentlyPlayed) {
        try {
            List<SearchResultDto> chartTracks = deezerSearchService.getChartTracks(needed + 10);
            Set<String> existing = new HashSet<>();
            for (Map<String, String> song : playlist) {
                existing.add((song.get("title") + "|" + song.get("artist")).toLowerCase());
            }
            int added = 0;
            for (SearchResultDto track : chartTracks) {
                if (added >= needed) break;
                String songKey = (track.getTitle() + "|" + track.getArtist()).toLowerCase();
                if (recentlyPlayed.contains(songKey)) continue;
                if (existing.contains(songKey)) continue;
                if ("song".equals(track.getType())) {
                    playlist.add(createSongMap(track));
                    existing.add(songKey);
                    added++;
                }
            }
        } catch (Exception e) {
            logger.warn("Failed to fill with chart tracks: {}", e.getMessage());
        }
    }

    private Map<String, String> createSongMap(SearchResultDto track) {
        Map<String, String> item = new LinkedHashMap<>();
        item.put("title", track.getTitle());
        item.put("artist", track.getArtist());
        item.put("image", track.getImage() != null ? track.getImage() : "");
        item.put("duration", track.getDuration() != null ? track.getDuration() : "");
        item.put("deezerId", track.getId());
        item.put("previewUrl", track.getPreviewUrl() != null ? track.getPreviewUrl() : "");
        return item;
    }

    private Map<String, Object> loadProfile(String userId, String jwt) {
        try {
            String token = (jwt != null && !jwt.isEmpty()) ? jwt : supabaseConfig.getSupabaseAnonKey();
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/profiles?id=eq." + userId +
                "&select=favorite_artists,favorite_genres";

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Authorization", "Bearer " + token)
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .GET()
                .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 200) {
                JsonNode json = objectMapper.readTree(response.body());
                if (json.isArray() && json.size() > 0) {
                    return objectMapper.convertValue(json.get(0), Map.class);
                }
            }
        } catch (Exception e) {
            logger.warn("Failed to load profile: {}", e.getMessage());
        }
        return Map.of();
    }

    @SuppressWarnings("unchecked")
    private List<String> extractStringList(Map<String, Object> profile, String field, String subKey) {
        List<String> result = new ArrayList<>();
        Object value = profile.get(field);
        if (value instanceof List) {
            for (Object item : (List<?>) value) {
                if (item instanceof Map) {
                    Map<String, Object> map = (Map<String, Object>) item;
                    Object subValue = map.get(subKey);
                    if (subValue != null && !subValue.toString().isEmpty()) {
                        result.add(subValue.toString());
                    }
                } else if (item != null) {
                    result.add(item.toString());
                }
            }
        }
        return result;
    }

    private List<String> extractStringList(Map<String, Object> profile, String field) {
        List<String> result = new ArrayList<>();
        Object value = profile.get(field);
        if (value instanceof List) {
            for (Object item : (List<?>) value) {
                if (item != null && !item.toString().isEmpty()) {
                    result.add(item.toString());
                }
            }
        }
        return result;
    }

    private List<Map<String, String>> getTodayMix(String userId, int playlistNumber, String date, String token) {
        try {
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/daily_playlists?user_id=eq." + userId +
                "&playlist_date=eq." + date +
                "&playlist_number=eq." + playlistNumber +
                "&select=songs";

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Authorization", "Bearer " + token)
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
            logger.warn("Failed to fetch cached mix #{}: {}", playlistNumber, e.getMessage());
        }
        return null;
    }

    private Set<String> getRecentlyPlayedSongs(String userId, int days, String token) {
        Set<String> result = new HashSet<>();
        try {
            String since = LocalDate.now().minusDays(days).atStartOfDay().toString();
            String url = supabaseConfig.getSupabaseUrl() +
                "/rest/v1/listening_history?user_id=eq." + userId +
                "&created_at=gte." + since +
                "&select=title,artist";

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Authorization", "Bearer " + token)
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .GET()
                .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 200) {
                JsonNode json = objectMapper.readTree(response.body());
                for (JsonNode node : json) {
                    String title = node.get("title").asText().toLowerCase();
                    String artist = node.get("artist").asText().toLowerCase();
                    result.add(title + "|" + artist);
                }
            }
        } catch (Exception e) {
            logger.warn("Failed to get recently played songs: {}", e.getMessage());
        }
        return result;
    }

    private void saveMix(String userId, int playlistNumber, String date, List<Map<String, String>> playlist, String token) {
        try {
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("user_id", userId);
            body.put("genre", "daily_mix");
            body.put("playlist_number", playlistNumber);
            body.put("playlist_date", date);
            body.put("songs", playlist);

            String json = objectMapper.writeValueAsString(body);

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(supabaseConfig.getSupabaseUrl() + "/rest/v1/daily_playlists"))
                .header("Authorization", "Bearer " + token)
                .header("apikey", supabaseConfig.getSupabaseAnonKey())
                .header("Content-Type", "application/json")
                .header("Prefer", "resolution=merge-duplicates")
                .POST(HttpRequest.BodyPublishers.ofString(json))
                .build();

            HttpResponse<Void> response = httpClient.send(request, HttpResponse.BodyHandlers.discarding());
            if (response.statusCode() >= 200 && response.statusCode() < 300) {
                logger.info("Saved mix #{} for user {} with {} songs", playlistNumber, userId, playlist.size());
            } else {
                logger.warn("Failed to save mix #{}: status {}", playlistNumber, response.statusCode());
            }
        } catch (Exception e) {
            logger.error("Failed to save mix #{}: {}", playlistNumber, e.getMessage());
        }
    }
}
