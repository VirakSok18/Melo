package com.melo.controller;

import com.melo.dto.ArtistDto;
import com.melo.dto.SearchResultDto;
import com.melo.service.DeezerSearchService;
import com.melo.service.ListeningHistoryService;
import com.melo.service.SpotifyService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.*;
import java.util.concurrent.*;

@RestController
@RequestMapping("/api/home")
@CrossOrigin(origins = "*")
public class HomeController {

    private static final Logger logger = LoggerFactory.getLogger(HomeController.class);

    @Autowired
    private DeezerSearchService deezerSearchService;

    @Autowired
    private SpotifyService spotifyService;

    @Autowired
    private ListeningHistoryService listeningHistoryService;

    private volatile Map<String, String> curatedDeezerIds = null;

    private String getCuratedDeezerId(String artistName) {
        if (curatedDeezerIds == null) {
            synchronized (this) {
                if (curatedDeezerIds == null) {
                    Map<String, String> map = new HashMap<>();
                    List<String> allGenres = List.of("Pop", "Hip Hop", "R&B", "Rock", "Latin", "K-Pop", "Jazz",
                            "Electronic", "Indie", "Country", "Metal", "Reggae", "Folk", "Soul", "Punk", "Blues",
                            "Alternative", "Dance", "Lo-Fi", "Anime", "Gaming", "Classical", "Ambient");
                    for (var artist : spotifyService.getCuratedArtists(allGenres)) {
                        if (artist.getId() != null && !artist.getId().isEmpty()) {
                            map.put(artist.getName().toLowerCase().trim(), artist.getId());
                        }
                    }
                    curatedDeezerIds = map;
                    logger.info("Loaded {} curated Deezer IDs from artists.json", map.size());
                }
            }
        }
        return curatedDeezerIds.get(artistName.toLowerCase().trim());
    }

    @GetMapping
    public ResponseEntity<Map<String, Object>> getHomeData(
            @RequestParam(required = false, defaultValue = "") String genres,
            @RequestParam(required = false, defaultValue = "") String artists,
            @RequestParam(required = false) String userId,
            @RequestHeader(value = "Authorization", required = false) String authHeader) {

        String jwt = extractJwt(authHeader);
        logger.info("GET /api/home - genres='{}', artists='{}', userId='{}'", genres, artists, userId);

        List<String> genreList = genres.isEmpty() ? List.of() : Arrays.asList(genres.split(","));
        List<Map<String, String>> artistList = new ArrayList<>();
        if (!artists.isEmpty()) {
            try {
                String[] artistPairs = artists.split("\\|");
                for (String pair : artistPairs) {
                    String[] parts = pair.split("::");
                    if (parts.length >= 2) {
                        artistList.add(Map.of("id", parts[0].trim(), "name", parts[1].trim()));
                    }
                }
            } catch (Exception e) {
                logger.warn("Failed to parse artists: {}", e.getMessage());
            }
        }

        ExecutorService executor = Executors.newFixedThreadPool(5);
        try {
            Future<List<Map<String, Object>>> trendingFuture = executor.submit(() -> getTrendingTracks());
            Future<List<Map<String, Object>>> yourArtistsFuture = executor.submit(() -> getYourArtists(artistList));
            Future<List<Map<String, Object>>> dailyPlaylistFuture = executor.submit(() -> getDailyPlaylist());
            Future<List<Map<String, Object>>> newDiscoveriesFuture = executor.submit(() -> getNewDiscoveries(userId, jwt));

            Map<String, Object> result = new LinkedHashMap<>();

            int songCount = 20;
            result.put("yourVibe", Map.of(
                    "genres", genreList,
                    "songCount", songCount
            ));

            try { result.put("trendingNow", trendingFuture.get(15, TimeUnit.SECONDS)); }
            catch (Exception e) { result.put("trendingNow", List.of()); logger.warn("trending failed: {}", e.getMessage()); }

            result.put("newlyReleased", List.of());

            try { result.put("yourArtists", yourArtistsFuture.get(15, TimeUnit.SECONDS)); }
            catch (Exception e) { result.put("yourArtists", List.of()); logger.warn("your artists failed: {}", e.getMessage()); }

            try { result.put("dailyPlaylist", dailyPlaylistFuture.get(15, TimeUnit.SECONDS)); }
            catch (Exception e) { result.put("dailyPlaylist", List.of()); logger.warn("daily playlist failed: {}", e.getMessage()); }

            try { result.put("newDiscoveries", newDiscoveriesFuture.get(15, TimeUnit.SECONDS)); }
            catch (Exception e) { result.put("newDiscoveries", List.of()); logger.warn("discoveries failed: {}", e.getMessage()); }

            return ResponseEntity.ok(Map.of("success", true, "data", result));

        } finally {
            executor.shutdown();
        }
    }

    private static final List<String> TRENDING_ARTISTS = List.of(
        "Kendrick Lamar", "Billie Eilish", "Drake", "The Weeknd", "Taylor Swift",
        "Bad Bunny", "Sabrina Carpenter", "Chappell Roan", "SZA", "Tyler the Creator",
        "Dua Lipa", "Post Malone", "Ariana Grande", "Beyonce", "Travis Scott"
    );

    private List<Map<String, Object>> getTrendingTracks() {
        try {
            List<SearchResultDto> chartTracks = deezerSearchService.getChartTracks(20);
            if (!chartTracks.isEmpty()) {
                List<Map<String, Object>> result = new ArrayList<>();
                Set<String> seen = new HashSet<>();
                int position = 1;
                for (SearchResultDto track : chartTracks) {
                    if (result.size() >= 20) break;
                    String key = track.getTitle().toLowerCase() + "|" + track.getArtist().toLowerCase();
                    if (seen.contains(key)) continue;
                    seen.add(key);

                    Map<String, Object> item = new LinkedHashMap<>();
                    item.put("id", track.getId());
                    item.put("title", track.getTitle());
                    item.put("artist", track.getArtist());
                    item.put("artistId", track.getArtistId() != null ? track.getArtistId() : "");
                    item.put("artistImage", track.getArtistImage() != null ? track.getArtistImage() : "");
                    item.put("image", track.getImage());
                    item.put("duration", track.getDuration());
                    item.put("rank", track.getRank());
                    item.put("preview", track.getPreviewUrl());
                    item.put("position", position);
                    position++;
                    result.add(item);
                }
                logger.info("Trending: returning {} tracks from live chart", result.size());
                return result;
            }
        } catch (Exception e) {
            logger.warn("Trending live chart failed: {}, using curated fallback", e.getMessage());
        }

        List<Map<String, Object>> result = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (String artist : TRENDING_ARTISTS) {
            if (result.size() >= 20) break;
            try {
                List<SearchResultDto> tracks = deezerSearchService.getNewestTracksByArtist(artist, 2);
                for (SearchResultDto track : tracks) {
                    if (result.size() >= 20) break;
                    String key = track.getTitle().toLowerCase() + "|" + track.getArtist().toLowerCase();
                    if (seen.contains(key)) continue;
                    seen.add(key);

                    Map<String, Object> item = new LinkedHashMap<>();
                    item.put("id", track.getId());
                    item.put("title", track.getTitle());
                    item.put("artist", track.getArtist());
                    item.put("artistId", track.getArtistId() != null ? track.getArtistId() : "");
                    item.put("artistImage", track.getArtistImage() != null ? track.getArtistImage() : "");
                    item.put("image", track.getImage());
                    item.put("duration", track.getDuration());
                    item.put("rank", track.getRank());
                    item.put("preview", track.getPreviewUrl());
                    item.put("position", result.size() + 1);
                    result.add(item);
                }
                Thread.sleep(200);
            } catch (Exception e) {
                logger.warn("Trending fallback failed for '{}': {}", artist, e.getMessage());
            }
        }
        logger.info("Trending: returning {} tracks (curated fallback)", result.size());
        return result;
    }

    private List<Map<String, Object>> getNewReleases(List<Map<String, String>> artists) {
        List<Map<String, Object>> result = new ArrayList<>();
        Set<String> seen = new HashSet<>();

        for (Map<String, String> artist : artists) {
            if (result.size() >= 10) break;
            try {
                String artistName = artist.get("name");
                if (artistName == null || artistName.isEmpty()) continue;

                String deezerId = getCuratedDeezerId(artistName);
                if (deezerId == null || deezerId.isEmpty()) {
                    deezerId = deezerSearchService.findArtistId(artistName);
                }

                if (deezerId == null || deezerId.isEmpty()) {
                    logger.warn("No Deezer artist found for '{}'", artistName);
                    continue;
                }

                List<Map<String, Object>> albums = deezerSearchService.getArtistAlbums(deezerId);
                for (Map<String, Object> album : albums) {
                    if (result.size() >= 10) break;
                    String albumId = (String) album.get("id");
                    if (!seen.contains(albumId)) {
                        seen.add(albumId);
                        if (album.get("artistName") == null || album.get("artistName").toString().isEmpty()) {
                            album.put("artistName", artistName);
                        }
                        result.add(album);
                    }
                }
            } catch (Exception e) {
                logger.warn("Failed to get albums for artist {}: {}", artist.get("name"), e.getMessage());
            }
        }

        if (result.isEmpty()) {
            List<SearchResultDto> searchResults = deezerSearchService.search("new album 2025", 10);
            for (SearchResultDto r : searchResults) {
                if ("album".equals(r.getType()) && result.size() < 10) {
                    Map<String, Object> item = new LinkedHashMap<>();
                    item.put("id", r.getId());
                    item.put("title", r.getTitle());
                    item.put("artistName", r.getArtist());
                    item.put("image", r.getImage());
                    result.add(item);
                }
            }
        }

        logger.info("New releases: returning {} albums", result.size());
        return result;
    }

    private List<Map<String, Object>> getYourArtists(List<Map<String, String>> artists) {
        List<Map<String, Object>> result = new ArrayList<>();
        Set<String> seenNames = new HashSet<>();

        for (Map<String, String> artist : artists) {
            if (result.size() >= 6) break;
            try {
                String artistName = artist.get("name");
                if (artistName == null || artistName.isEmpty()) continue;

                String normalizedName = artistName.toLowerCase().trim();
                if (seenNames.contains(normalizedName)) continue;
                seenNames.add(normalizedName);

                String deezerId = getCuratedDeezerId(artistName);
                if (deezerId == null || deezerId.isEmpty()) {
                    deezerId = deezerSearchService.findArtistId(artistName);
                }

                if (deezerId == null || deezerId.isEmpty()) {
                    logger.warn("No Deezer artist found for '{}'", artistName);
                    continue;
                }

                Map<String, Object> info = deezerSearchService.getArtistInfo(deezerId);
                if (!info.isEmpty()) {
                    Map<String, Object> artistInfo = new LinkedHashMap<>(info);
                    artistInfo.put("id", deezerId);
                    artistInfo.put("name", artistName);
                    result.add(artistInfo);
                }
            } catch (Exception e) {
                logger.warn("Failed to get info for artist {}: {}", artist.get("name"), e.getMessage());
            }
        }
        logger.info("Your artists: returning {} artists", result.size());
        return result;
    }

    private List<Map<String, Object>> getDailyPlaylist() {
        List<SearchResultDto> allTracks = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        String[] queries = {"Chill Vibes", "Feel Good Hits", "Good Mood", "Summer Mix", "Late Night"};
        for (String q : queries) {
            List<SearchResultDto> results = deezerSearchService.search(q, 10);
            for (SearchResultDto r : results) {
                if ("song".equals(r.getType())) {
                    String key = r.getTitle().toLowerCase() + "|" + r.getArtist().toLowerCase();
                    if (!seen.contains(key)) {
                        seen.add(key);
                        allTracks.add(r);
                    }
                }
            }
            if (allTracks.size() >= 24) break;
        }

        Collections.shuffle(allTracks);

        List<Map<String, Object>> result = new ArrayList<>();
        for (SearchResultDto track : allTracks) {
            if (result.size() >= 24) break;
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("id", track.getId());
            item.put("title", track.getTitle());
            item.put("artist", track.getArtist());
            item.put("image", track.getImage());
            item.put("duration", track.getDuration());
            item.put("preview", track.getPreviewUrl());
            result.add(item);
        }
        logger.info("Daily playlist: returning {} tracks", result.size());
        return result;
    }

    private List<Map<String, Object>> getNewDiscoveries(String userId, String jwt) {
        List<Map<String, Object>> allTracks = new ArrayList<>();
        Set<String> seenKeys = new HashSet<>();
        Set<String> artistsHeard = new HashSet<>();

        // Build listening history data
        List<Map<String, Object>> history = List.of();
        Map<String, int[]> artistStats = new LinkedHashMap<>();
        Map<String, Integer> genreCounts = new LinkedHashMap<>();

        if (userId != null && !userId.isEmpty()) {
            try {
                history = listeningHistoryService.getRecentHistory(userId, 30, jwt);

                for (Map<String, Object> entry : history) {
                    String artist = (String) entry.get("artist");
                    if (artist != null && !artist.isEmpty()) {
                        artistsHeard.add(artist.toLowerCase().trim());
                        artistStats.putIfAbsent(artist, new int[]{0, 0});
                        artistStats.get(artist)[0]++;
                        if ((Boolean) entry.getOrDefault("completed", false)) {
                            artistStats.get(artist)[1]++;
                        }
                    }
                    String genre = (String) entry.getOrDefault("genre", "");
                    if (!genre.isEmpty()) {
                        genreCounts.merge(genre, 1, Integer::sum);
                    }
                }
            } catch (Exception e) {
                logger.warn("Failed to load history for discoveries: {}", e.getMessage());
            }
        }

        // SOURCE 1: Underexplored artists — heard 1-2 times, completed
        List<String> underexploredArtists = new ArrayList<>();
        for (Map.Entry<String, int[]> e : artistStats.entrySet()) {
            if (e.getValue()[0] <= 2 && e.getValue()[1] > 0) {
                underexploredArtists.add(e.getKey());
            }
        }

        for (String artistName : underexploredArtists) {
            if (allTracks.size() >= 4) break;
            try {
                String artistId = deezerSearchService.findArtistId(artistName);
                if (artistId == null) continue;

                List<SearchResultDto> tracks = deezerSearchService.getArtistTopTracks(artistId, 3);
                for (SearchResultDto track : tracks) {
                    if (allTracks.size() >= 4) break;
                    String key = track.getTitle().toLowerCase() + "|" + track.getArtist().toLowerCase();
                    if (seenKeys.contains(key)) continue;

                    // Skip tracks already in history
                    boolean alreadyHeard = false;
                    for (Map<String, Object> h : history) {
                        String hTitle = ((String) h.getOrDefault("title", "")).toLowerCase();
                        String hArtist = ((String) h.getOrDefault("artist", "")).toLowerCase();
                        if (track.getTitle().toLowerCase().equals(hTitle) && track.getArtist().toLowerCase().equals(hArtist)) {
                            alreadyHeard = true;
                            break;
                        }
                    }
                    if (alreadyHeard) continue;

                    seenKeys.add(key);
                    Map<String, Object> item = buildTrackItem(track);
                    item.put("source", "underexplored");
                    allTracks.add(item);
                }
                Thread.sleep(100);
            } catch (Exception e) {
                logger.warn("Underexplored failed for '{}': {}", artistName, e.getMessage());
            }
        }

        // SOURCE 2: Similar artists — top 3 favorite artists → related artists
        List<String> topArtists = new ArrayList<>();
        artistStats.entrySet().stream()
            .sorted((a, b) -> {
                int scoreA = b.getValue()[1] * 20 - b.getValue()[0] * 2;
                int scoreB = a.getValue()[1] * 20 - a.getValue()[0] * 2;
                return Integer.compare(scoreA, scoreB);
            })
            .limit(3)
            .forEach(e -> topArtists.add(e.getKey()));

        for (String artistName : topArtists) {
            if (allTracks.size() >= 8) break;
            try {
                String artistId = deezerSearchService.findArtistId(artistName);
                if (artistId == null) continue;

                List<String> relatedIds = deezerSearchService.getRelatedArtistIds(artistId);
                for (String relatedId : relatedIds) {
                    if (allTracks.size() >= 8) break;

                    // Get related artist name to check if already heard
                    Map<String, Object> relatedInfo = deezerSearchService.getArtistInfo(relatedId);
                    String relatedName = (String) relatedInfo.getOrDefault("name", "");
                    if (relatedName.isEmpty()) continue;
                    if (artistsHeard.contains(relatedName.toLowerCase().trim())) continue;

                    List<SearchResultDto> tracks = deezerSearchService.getArtistTopTracks(relatedId, 2);
                    for (SearchResultDto track : tracks) {
                        if (allTracks.size() >= 8) break;
                        String key = track.getTitle().toLowerCase() + "|" + track.getArtist().toLowerCase();
                        if (seenKeys.contains(key)) continue;
                        seenKeys.add(key);
                        Map<String, Object> item = buildTrackItem(track);
                        item.put("source", "similar");
                        allTracks.add(item);
                    }
                    Thread.sleep(100);
                }
                Thread.sleep(100);
            } catch (Exception e) {
                logger.warn("Similar artist failed for '{}': {}", artistName, e.getMessage());
            }
        }

        // SOURCE 3: Fresh finds — real popular songs from curated artists in user's top genres they haven't heard
        List<String> topGenres = new ArrayList<>();
        genreCounts.entrySet().stream()
            .sorted((a, b) -> b.getValue() - a.getValue())
            .limit(3)
            .forEach(e -> topGenres.add(e.getKey()));

        for (String genre : topGenres) {
            if (allTracks.size() >= 12) break;
            try {
                // Get curated artists for this genre from artists.json
                List<String> genreList = List.of(genre);
                List<com.melo.dto.ArtistDto> curatedArtists = spotifyService.getCuratedArtists(genreList);

                // Shuffle to get variety each day
                List<com.melo.dto.ArtistDto> shuffled = new ArrayList<>(curatedArtists);
                Collections.shuffle(shuffled);

                for (com.melo.dto.ArtistDto curated : shuffled) {
                    if (allTracks.size() >= 12) break;
                    String artistName = curated.getName();
                    if (artistName == null || artistName.isEmpty()) continue;
                    if (artistsHeard.contains(artistName.toLowerCase().trim())) continue;

                    String deezerId = deezerSearchService.findArtistId(artistName);
                    if (deezerId == null) continue;

                    List<SearchResultDto> tracks = deezerSearchService.getArtistTopTracks(deezerId, 2);
                    for (SearchResultDto track : tracks) {
                        if (allTracks.size() >= 12) break;
                        String key = track.getTitle().toLowerCase() + "|" + track.getArtist().toLowerCase();
                        if (seenKeys.contains(key)) continue;
                        seenKeys.add(key);
                        Map<String, Object> item = buildTrackItem(track);
                        item.put("source", "fresh");
                        allTracks.add(item);
                    }
                    Thread.sleep(100);
                }
            } catch (Exception e) {
                logger.warn("Fresh finds failed for genre '{}': {}", genre, e.getMessage());
            }
        }

        // Shuffle and cap at 10
        Collections.shuffle(allTracks);
        if (allTracks.size() > 10) {
            allTracks = new ArrayList<>(allTracks.subList(0, 10));
        }

        logger.info("New discoveries: returning {} tracks (underexplored={}, similar={}, fresh={})",
            allTracks.size(),
            allTracks.stream().filter(t -> "underexplored".equals(t.get("source"))).count(),
            allTracks.stream().filter(t -> "similar".equals(t.get("source"))).count(),
            allTracks.stream().filter(t -> "fresh".equals(t.get("source"))).count());

        return allTracks;
    }

    private Map<String, Object> buildTrackItem(SearchResultDto track) {
        Map<String, Object> item = new LinkedHashMap<>();
        item.put("id", track.getId());
        item.put("title", track.getTitle());
        item.put("artist", track.getArtist());
        item.put("artistId", track.getArtistId() != null ? track.getArtistId() : "");
        item.put("artistImage", track.getArtistImage() != null ? track.getArtistImage() : "");
        item.put("image", track.getImage());
        item.put("duration", track.getDuration());
        item.put("preview", track.getPreviewUrl());
        return item;
    }

    private String extractJwt(String authHeader) {
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            return authHeader.substring(7);
        }
        return null;
    }
}
