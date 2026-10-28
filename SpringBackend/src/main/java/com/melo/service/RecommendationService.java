package com.melo.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.melo.config.DeezerConfig;
import com.melo.dto.SearchResultDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import jakarta.annotation.PostConstruct;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

@Service
public class RecommendationService {

    private static final Logger logger = LoggerFactory.getLogger(RecommendationService.class);

    @Autowired
    @org.springframework.beans.factory.annotation.Qualifier("deezerRestTemplate")
    private RestTemplate deezerRestTemplate;

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final ExecutorService executor = Executors.newFixedThreadPool(5);

    private Map<String, List<String>> genreToArtistNames = new HashMap<>();
    private Map<String, String> artistNameToGenre = new HashMap<>();
    private Map<String, List<String>> genreToDeezerIds = new ConcurrentHashMap<>();

    // Khmer artist support
    private Set<String> khmerArtistNames = new HashSet<>();
    private Map<String, List<String>> khmerGenreToArtists = new HashMap<>();
    private Map<String, String> khmerNameOriginalCase = new HashMap<>();

    private final ConcurrentHashMap<String, CacheEntry> radioCache = new ConcurrentHashMap<>();
    private static final long CACHE_TTL_MS = 30 * 60 * 1000;

    public Map<String, List<String>> getGenreToArtistNames() {
        return genreToArtistNames;
    }

    public boolean isKhmerArtist(String artistName) {
        if (artistName == null) return false;
        // Check curated list first
        if (khmerArtistNames.contains(artistName.toLowerCase())) return true;
        // Detect Khmer script (Unicode range U+1780–U+17FF)
        for (char c : artistName.toCharArray()) {
            if (c >= '\u1780' && c <= '\u17FF') return true;
        }
        return false;
    }

    /**
     * Finds the FIRST curated Khmer artist name that appears in the given text
     * (case-insensitive), so the generator can detect "Tena khmer artist songs".
     * Returns the original-cased name (e.g. "Tena", "VannDa").
     */
    public String findKhmerArtistInText(String text) {
        if (text == null) return null;
        String lower = text.toLowerCase();
        String best = null;
        // Longest name wins, so "Preap Sovath" beats "Sovath"-type overlaps.
        for (String name : khmerArtistNames) {
            if (lower.contains(name)) {
                if (best == null || name.length() > best.length()) {
                    best = name;
                }
            }
        }
        if (best == null) return null;
        return khmerNameOriginalCase.getOrDefault(best, best);
    }

    /**
     * Curated Cambodian artists whose YouTube search results can be verified
     * against the artist name. Used when a request is for Khmer music in
     * general, rather than for one named artist.
     */
    public List<String> getKhmerArtistNames() {
        List<String> artists = new ArrayList<>(khmerNameOriginalCase.values());
        artists.sort(String.CASE_INSENSITIVE_ORDER);
        return artists;
    }

    private static class CacheEntry {
        final List<SearchResultDto> results;
        final long timestamp;
        CacheEntry(List<SearchResultDto> results) {
            this.results = results;
            this.timestamp = System.currentTimeMillis();
        }
        boolean isExpired() {
            return System.currentTimeMillis() - timestamp > CACHE_TTL_MS;
        }
    }

    @PostConstruct
    public void init() {
        try {
            ClassPathResource resource = new ClassPathResource("artists.json");
            InputStream is = resource.getInputStream();
            @SuppressWarnings("unchecked")
            Map<String, List<Map<String, String>>> loaded = objectMapper.readValue(is,
                    new com.fasterxml.jackson.core.type.TypeReference<Map<String, List<Map<String, String>>>>() {});

            for (Map.Entry<String, List<Map<String, String>>> entry : loaded.entrySet()) {
                String genre = entry.getKey();
                List<String> names = new ArrayList<>();
                for (Map<String, String> artist : entry.getValue()) {
                    String name = artist.get("name");
                    if (name != null) {
                        names.add(name);
                        artistNameToGenre.put(name.toLowerCase(), genre);
                    }
                }
                genreToArtistNames.put(genre, names);
            }

            // Pre-resolve Deezer IDs in background
            executor.submit(this::preloadDeezerIds);

            // Load Khmer artists
            loadKhmerArtists();

            logger.info("RecommendationService loaded {} genres, {} artist mappings, {} khmer artists",
                    genreToArtistNames.size(), artistNameToGenre.size(), khmerArtistNames.size());
        } catch (Exception e) {
            logger.error("Failed to load artists.json for recommendations", e);
        }
    }

    private void preloadDeezerIds() {
        logger.info("Pre-loading Deezer IDs for curated artists...");
        for (Map.Entry<String, List<String>> entry : genreToArtistNames.entrySet()) {
            String genre = entry.getKey();
            List<String> deezerIds = new CopyOnWriteArrayList<>();
            List<Future<Void>> futures = new ArrayList<>();

            for (String name : entry.getValue()) {
                futures.add(executor.submit(() -> {
                    String id = searchDeezerArtistId(name);
                    if (id != null) {
                        deezerIds.add(id);
                    }
                    return null;
                }));
            }

            for (Future<Void> f : futures) {
                try { f.get(5, TimeUnit.SECONDS); } catch (Exception ignored) {}
            }

            genreToDeezerIds.put(genre, deezerIds);
            logger.info("Pre-loaded {} Deezer IDs for genre '{}'", deezerIds.size(), genre);
        }
    }

    private void loadKhmerArtists() {
        try {
            ClassPathResource resource = new ClassPathResource("khmer_artists.json");
            InputStream is = resource.getInputStream();
            @SuppressWarnings("unchecked")
            Map<String, List<Map<String, String>>> loaded = objectMapper.readValue(is,
                    new com.fasterxml.jackson.core.type.TypeReference<Map<String, List<Map<String, String>>>>() {});

            for (Map.Entry<String, List<Map<String, String>>> entry : loaded.entrySet()) {
                String genre = entry.getKey();
                List<String> names = new ArrayList<>();
                for (Map<String, String> artist : entry.getValue()) {
                    String name = artist.get("name");
                    if (name != null) {
                        names.add(name);
                        khmerArtistNames.add(name.toLowerCase());
                        khmerNameOriginalCase.put(name.toLowerCase(), name);
                    }
                }
                khmerGenreToArtists.put(genre, names);
            }
            logger.info("Loaded {} Khmer artist names across {} sub-genres",
                    khmerArtistNames.size(), khmerGenreToArtists.size());
        } catch (Exception e) {
            logger.error("Failed to load khmer_artists.json", e);
        }
    }

    private String getKhmerSubGenre(String artistName) {
        String lower = artistName.toLowerCase();
        for (Map.Entry<String, List<String>> entry : khmerGenreToArtists.entrySet()) {
            for (String name : entry.getValue()) {
                if (name.toLowerCase().equals(lower)) {
                    return entry.getKey();
                }
            }
        }
        return null;
    }

    private List<SearchResultDto> getKhmerSmartQueue(String artistName, int limit) {
        String cacheKey = "khmer_" + artistName.toLowerCase();
        CacheEntry cached = radioCache.get(cacheKey);
        if (cached != null && !cached.isExpired()) {
            logger.info("Khmer recommendation cache hit for '{}'", artistName);
            return cached.results;
        }

        List<SearchResultDto> results = new CopyOnWriteArrayList<>();
        Set<String> seen = ConcurrentHashMap.newKeySet();

        // Step 1: Find sub-genre for this artist
        String subGenre = getKhmerSubGenre(artistName);

        // Step 2: Fire all searches IN PARALLEL (like Deezer algorithm does)
        List<Future<Void>> futures = new ArrayList<>();

        // 2a: Current artist's own top songs (always include)
        futures.add(executor.submit(() -> {
            List<SearchResultDto> tracks = searchKhmerArtistOnYouTube(artistName, 5);
            for (SearchResultDto track : tracks) {
                String key = (track.getTitle() + "|" + track.getArtist()).toLowerCase();
                if (seen.add(key)) {
                    results.add(track);
                }
            }
            return null;
        }));

        // 2b: Same sub-genre artists' top tracks (like Deezer's same-genre curated artists)
        if (subGenre != null) {
            List<String> sameGenre = khmerGenreToArtists.getOrDefault(subGenre, Collections.emptyList());
            List<String> genreArtists = new ArrayList<>();
            for (String name : sameGenre) {
                if (!name.equalsIgnoreCase(artistName)) {
                    genreArtists.add(name);
                }
            }
            Collections.shuffle(genreArtists);
            // Pick up to 5 same-genre artists, get 3 songs each
            for (int i = 0; i < Math.min(5, genreArtists.size()); i++) {
                final String relatedArtist = genreArtists.get(i);
                futures.add(executor.submit(() -> {
                    List<SearchResultDto> tracks = searchKhmerArtistOnYouTube(relatedArtist, 3);
                    for (SearchResultDto track : tracks) {
                        String key = (track.getTitle() + "|" + track.getArtist()).toLowerCase();
                        if (seen.add(key)) {
                            results.add(track);
                        }
                    }
                    return null;
                }));
            }
        }

        // 2c: Popular Khmer artists from other sub-genres (like Deezer's related artists)
        List<String> otherGenreArtists = new ArrayList<>();
        for (Map.Entry<String, List<String>> entry : khmerGenreToArtists.entrySet()) {
            if (subGenre == null || !entry.getKey().equals(subGenre)) {
                for (String name : entry.getValue()) {
                    if (!name.equalsIgnoreCase(artistName)) {
                        otherGenreArtists.add(name);
                    }
                }
            }
        }
        Collections.shuffle(otherGenreArtists);
        for (int i = 0; i < Math.min(4, otherGenreArtists.size()); i++) {
            final String otherArtist = otherGenreArtists.get(i);
            futures.add(executor.submit(() -> {
                List<SearchResultDto> tracks = searchKhmerArtistOnYouTube(otherArtist, 2);
                for (SearchResultDto track : tracks) {
                    String key = (track.getTitle() + "|" + track.getArtist()).toLowerCase();
                    if (seen.add(key)) {
                        results.add(track);
                    }
                }
                return null;
            }));
        }

        // Wait for all parallel calls (max 10 seconds total)
        for (Future<Void> f : futures) {
            try { f.get(10, TimeUnit.SECONDS); } catch (Exception ignored) {}
        }

        // Step 3: If still not enough, fill with more of the current artist's songs
        if (results.size() < limit) {
            List<SearchResultDto> moreOwn = searchKhmerArtistOnYouTube(artistName, limit + 5);
            for (SearchResultDto track : moreOwn) {
                String key = (track.getTitle() + "|" + track.getArtist()).toLowerCase();
                if (seen.add(key)) {
                    results.add(track);
                }
                if (results.size() >= limit) break;
            }
        }

        // Step 4: Shuffle and trim (like Deezer algorithm)
        List<SearchResultDto> finalResults = new ArrayList<>(results);
        Collections.shuffle(finalResults);
        if (finalResults.size() > limit) {
            finalResults = finalResults.subList(0, limit);
        }

        radioCache.put(cacheKey, new CacheEntry(finalResults));
        logger.info("Khmer smart queue for '{}' generated {} tracks (sub-genre={}, own songs included)",
                artistName, finalResults.size(), subGenre);

        return finalResults;
    }

    private List<SearchResultDto> searchKhmerArtistOnYouTube(String artistName, int limit) {
        List<SearchResultDto> results = new ArrayList<>();
        try {
            String query = artistName + " official audio";
            String[] command = {
                "yt-dlp",
                "--no-download",
                "--print", "%(id)s|||%(title)s|||%(duration)s",
                "--no-warnings",
                "--no-playlist",
                "--flat-playlist",
                "ytsearch" + Math.min(limit + 2, 20) + ":" + query
            };

            ProcessBuilder pb = new ProcessBuilder(command);
            pb.redirectErrorStream(true);
            Process process = pb.start();

            BufferedReader reader = new BufferedReader(new java.io.InputStreamReader(process.getInputStream()));
            String line;
            while ((line = reader.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty()) continue;
                String[] parts = line.split("\\|\\|\\|", 3);
                if (parts.length >= 2) {
                    String videoId = parts[0].trim();
                    String title = parts[1].trim();
                    int duration = 0;
                    if (parts.length >= 3) {
                        try {
                            duration = (int) Double.parseDouble(parts[2].trim());
                        } catch (NumberFormatException ignored) {}
                    }

                    // Verify: artist name must appear in the video title as a
                    // whole word (case-insensitive). "Tena" must not match
                    // "Tenacious" or "Tenaissance" — only real Tena videos pass.
                    String titleLower = title.toLowerCase();
                    String artistLower = artistName.toLowerCase();
                    String pattern = "(^|[^a-z0-9])" + java.util.regex.Pattern.quote(artistLower) + "([^a-z0-9]|$)";
                    if (!java.util.regex.Pattern.compile(pattern).matcher(titleLower).find()) {
                        continue; // Skip — likely not this artist's song
                    }

                    if (!videoId.isEmpty()) {
                        String formattedDuration = String.format("%d:%02d", duration / 60, duration % 60);
                        SearchResultDto dto = new SearchResultDto("song", "", title, artistName, "", formattedDuration, 0, "", 0);
                        dto.setArtistId("khmer");
                        dto.setVideoId(videoId);
                        results.add(dto);
                    }
                }
            }

            boolean finished = process.waitFor(10, TimeUnit.SECONDS);
            if (!finished) {
                process.destroyForcibly();
            }

        } catch (Exception e) {
            logger.warn("Khmer YouTube search failed for '{}': {}", artistName, e.getMessage());
        }
        return results;
    }

    /**
     * Strict Khmer-artist search: returns ONLY the requested artist's own songs,
     * verified on YouTube (artist name must appear in the video title). Used by
     * the generator so "Tena songs" returns real Tena tracks — and each track
     * carries the exact videoId so playback plays the correct audio.
     */
    public List<SearchResultDto> getKhmerArtistSongs(String artistName, int limit) {
        return searchKhmerArtistOnYouTube(artistName, limit);
    }

    public List<SearchResultDto> getSmartQueue(String artistName, int limit) {
        // Khmer artist → use YouTube-based path (Deezer doesn't have Khmer music)
        if (isKhmerArtist(artistName)) {
            return getKhmerSmartQueue(artistName, limit);
        }

        String cacheKey = artistName.toLowerCase();
        CacheEntry cached = radioCache.get(cacheKey);
        if (cached != null && !cached.isExpired()) {
            logger.info("Recommendation cache hit for '{}'", artistName);
            return cached.results;
        }

        List<SearchResultDto> results = new CopyOnWriteArrayList<>();
        Set<String> seen = ConcurrentHashMap.newKeySet();

        // Step 1: Find artist Deezer ID (fast if preloaded, else search)
        String genre = artistNameToGenre.get(cacheKey);
        String deezerArtistId = findDeezerArtistIdFast(artistName, genre);

        // Step 2: Fire radio + related artist top tracks IN PARALLEL
        List<Future<Void>> futures = new ArrayList<>();

        // Radio call
        if (deezerArtistId != null) {
            futures.add(executor.submit(() -> {
                List<SearchResultDto> radio = getArtistRadio(deezerArtistId);
                for (SearchResultDto track : radio) {
                    String key = (track.getTitle() + "|" + track.getArtist()).toLowerCase();
                    if (seen.add(key)) {
                        results.add(track);
                    }
                }
                return null;
            }));
        }

        // Related artists top tracks - all in parallel
        if (genre != null) {
            // Curated artists: use same-genre artists from artists.json
            List<String> sameGenreArtists = genreToArtistNames.getOrDefault(genre, Collections.emptyList());
            List<String> relatedIds = genreToDeezerIds.getOrDefault(genre, Collections.emptyList());

            int count = 0;
            for (int i = 0; i < sameGenreArtists.size() && count < 5; i++) {
                String name = sameGenreArtists.get(i);
                if (name.equalsIgnoreCase(artistName)) continue;
                if (i < relatedIds.size()) {
                    String relatedId = relatedIds.get(i);
                    final String rId = relatedId;
                    futures.add(executor.submit(() -> {
                        List<SearchResultDto> tracks = getArtistTopTracks(rId, 5);
                        for (SearchResultDto track : tracks) {
                            String key = (track.getTitle() + "|" + track.getArtist()).toLowerCase();
                            if (seen.add(key)) {
                                results.add(track);
                            }
                        }
                        return null;
                    }));
                    count++;
                }
            }
        } else if (deezerArtistId != null) {
            // Non-curated artists: use Deezer's related artists endpoint
            List<String> relatedArtistIds = getRelatedArtistIds(deezerArtistId);
            for (String relatedId : relatedArtistIds) {
                final String rId = relatedId;
                futures.add(executor.submit(() -> {
                    List<SearchResultDto> tracks = getArtistTopTracks(rId, 5);
                    for (SearchResultDto track : tracks) {
                        String key = (track.getTitle() + "|" + track.getArtist()).toLowerCase();
                        if (seen.add(key)) {
                            results.add(track);
                        }
                    }
                    return null;
                }));
            }
        }

        // Wait for all parallel calls (max 5 seconds total)
        for (Future<Void> f : futures) {
            try { f.get(5, TimeUnit.SECONDS); } catch (Exception ignored) {}
        }

        // Fallback: if radio + related returned nothing, find real artist from track search, then get related
        if (results.isEmpty()) {
            String realArtistId = findRealArtistIdFromTracks(artistName);
            if (realArtistId != null) {
                // Get some of the original artist's own top tracks
                List<SearchResultDto> ownTracks = getArtistTopTracks(realArtistId, 5);
                for (SearchResultDto track : ownTracks) {
                    String key = (track.getTitle() + "|" + track.getArtist()).toLowerCase();
                    if (seen.add(key)) {
                        results.add(track);
                    }
                }
                // Get related artists' top tracks
                List<String> relatedArtistIds = getRelatedArtistIds(realArtistId);
                for (String relatedId : relatedArtistIds) {
                    final String rId = relatedId;
                    List<SearchResultDto> tracks = getArtistTopTracks(rId, 5);
                    for (SearchResultDto track : tracks) {
                        String key = (track.getTitle() + "|" + track.getArtist()).toLowerCase();
                        if (seen.add(key)) {
                            results.add(track);
                        }
                    }
                }
            }
            // If still empty, use track search as last resort
            if (results.isEmpty()) {
                List<SearchResultDto> fallbackTracks = searchDeezerTracks(artistName, limit);
                for (SearchResultDto track : fallbackTracks) {
                    String key = (track.getTitle() + "|" + track.getArtist()).toLowerCase();
                    if (seen.add(key)) {
                        results.add(track);
                    }
                }
            }
        }

        // Shuffle and trim
        List<SearchResultDto> finalResults = new ArrayList<>(results);
        Collections.shuffle(finalResults);
        if (finalResults.size() > limit) {
            finalResults = finalResults.subList(0, limit);
        }

        radioCache.put(cacheKey, new CacheEntry(finalResults));
        logger.info("Smart queue for '{}' generated {} tracks (genre={})", artistName, finalResults.size(), genre);

        return finalResults;
    }

    private String findDeezerArtistIdFast(String artistName, String genre) {
        // Check preloaded IDs first
        if (genre != null) {
            List<String> names = genreToArtistNames.getOrDefault(genre, Collections.emptyList());
            List<String> ids = genreToDeezerIds.getOrDefault(genre, Collections.emptyList());
            for (int i = 0; i < names.size(); i++) {
                if (names.get(i).equalsIgnoreCase(artistName) && i < ids.size()) {
                    return ids.get(i);
                }
            }
        }
        // Fallback: search Deezer
        return searchDeezerArtistId(artistName);
    }

    private String searchDeezerArtistId(String artistName) {
        try {
            String encoded = URLEncoder.encode(artistName, StandardCharsets.UTF_8);
            String url = String.format("%s/search/artist?q=%s&limit=5", DeezerConfig.API_BASE, encoded);
            ResponseEntity<String> response = deezerRestTemplate.exchange(url, HttpMethod.GET, null, String.class);
            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                JsonNode json = objectMapper.readTree(response.getBody());
                JsonNode data = json.get("data");
                if (data != null && data.isArray() && data.size() > 0) {
                    String bestId = null;
                    int bestFans = -1;
                    String searchLower = artistName.toLowerCase();
                    for (JsonNode item : data) {
                        String name = item.has("name") ? item.get("name").asText() : "";
                        int fans = item.has("nb_fan") ? item.get("nb_fan").asInt() : 0;
                        boolean exactMatch = name.equalsIgnoreCase(artistName);
                        if (exactMatch) {
                            if (fans > bestFans) {
                                bestFans = fans;
                                bestId = String.valueOf(item.get("id").asInt());
                            }
                        } else if (bestId == null && fans > bestFans) {
                            bestFans = fans;
                            bestId = String.valueOf(item.get("id").asInt());
                        }
                    }
                    if (bestId != null) {
                        return bestId;
                    }
                    return String.valueOf(data.get(0).get("id").asInt());
                }
            }
        } catch (Exception e) {
            logger.warn("Deezer artist lookup failed for '{}': {}", artistName, e.getMessage());
        }
        return null;
    }

    private List<String> getRelatedArtistIds(String deezerArtistId) {
        List<String> relatedIds = new ArrayList<>();
        try {
            String url = String.format("%s/artist/%s/related", DeezerConfig.API_BASE, deezerArtistId);
            ResponseEntity<String> response = deezerRestTemplate.exchange(url, HttpMethod.GET, null, String.class);
            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                JsonNode json = objectMapper.readTree(response.getBody());
                JsonNode data = json.get("data");
                if (data != null && data.isArray()) {
                    int count = 0;
                    for (JsonNode item : data) {
                        if (count >= 5) break;
                        relatedIds.add(String.valueOf(item.get("id").asInt()));
                        count++;
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Deezer related artists failed for '{}': {}", deezerArtistId, e.getMessage());
        }
        return relatedIds;
    }

    private String findRealArtistIdFromTracks(String artistName) {
        try {
            String encoded = URLEncoder.encode(artistName, StandardCharsets.UTF_8);
            String url = String.format("%s/search/track?q=%s&limit=10", DeezerConfig.API_BASE, encoded);
            ResponseEntity<String> response = deezerRestTemplate.exchange(url, HttpMethod.GET, null, String.class);
            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                JsonNode json = objectMapper.readTree(response.getBody());
                JsonNode data = json.get("data");
                if (data != null && data.isArray()) {
                    Map<String, Integer> idCounts = new HashMap<>();
                    String searchLower = artistName.toLowerCase();
                    for (JsonNode item : data) {
                        if (item.has("artist") && item.get("artist").has("name") && item.get("artist").has("id")) {
                            String trackArtist = item.get("artist").get("name").asText().toLowerCase();
                            if (trackArtist.contains(searchLower) || searchLower.contains(trackArtist)) {
                                String id = String.valueOf(item.get("artist").get("id").asInt());
                                idCounts.merge(id, 1, Integer::sum);
                            }
                        }
                    }
                    if (!idCounts.isEmpty()) {
                        return idCounts.entrySet().stream()
                                .max(Map.Entry.comparingByValue())
                                .map(Map.Entry::getKey)
                                .orElse(null);
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Failed to find real artist ID from tracks for '{}': {}", artistName, e.getMessage());
        }
        return null;
    }

    private List<SearchResultDto> searchDeezerTracks(String artistName, int limit) {
        List<SearchResultDto> results = new ArrayList<>();
        try {
            String encoded = URLEncoder.encode(artistName, StandardCharsets.UTF_8);
            String url = String.format("%s/search/track?q=%s&limit=%d", DeezerConfig.API_BASE, encoded, Math.min(limit, 20));
            ResponseEntity<String> response = deezerRestTemplate.exchange(url, HttpMethod.GET, null, String.class);
            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                JsonNode json = objectMapper.readTree(response.getBody());
                JsonNode data = json.get("data");
                if (data != null && data.isArray()) {
                    String searchLower = artistName.toLowerCase();
                    for (JsonNode item : data) {
                        try {
                            boolean readable = item.has("readable") && item.get("readable").asBoolean();
                            if (!readable) continue;
                            String trackArtist = "";
                            int artistId = -1;
                            if (item.has("artist") && item.get("artist").has("name")) {
                                trackArtist = item.get("artist").get("name").asText();
                                artistId = item.get("artist").get("id").asInt();
                            }
                            if (!trackArtist.toLowerCase().contains(searchLower) && !searchLower.contains(trackArtist.toLowerCase())) {
                                continue;
                            }
                            String id = String.valueOf(item.get("id").asInt());
                            String title = item.get("title").asText();
                            String preview = item.has("preview") ? item.get("preview").asText() : "";
                            String albumImage = "";
                            if (item.has("album") && item.get("album").has("cover_medium")) {
                                albumImage = item.get("album").get("cover_medium").asText();
                            }
                            String artistImg = "";
                            if (item.has("artist") && item.get("artist").has("picture_medium")) {
                                artistImg = item.get("artist").get("picture_medium").asText();
                            }
                            String duration = formatDuration(item.get("duration").asInt());
                            int rank = item.has("rank") ? item.get("rank").asInt() : 0;
                            SearchResultDto dto = new SearchResultDto("song", id, title, trackArtist, albumImage, duration, 0, preview, rank);
                            dto.setArtistId(String.valueOf(artistId));
                            dto.setArtistImage(artistImg);
                            results.add(dto);
                            if (results.size() >= limit) break;
                        } catch (Exception ignored) {}
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Deezer track search failed for '{}': {}", artistName, e.getMessage());
        }
        return results;
    }

    private List<SearchResultDto> getArtistRadio(String deezerArtistId) {
        List<SearchResultDto> results = new ArrayList<>();
        try {
            String url = String.format("%s/artist/%s/radio", DeezerConfig.API_BASE, deezerArtistId);
            ResponseEntity<String> response = deezerRestTemplate.exchange(url, HttpMethod.GET, null, String.class);
            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                JsonNode json = objectMapper.readTree(response.getBody());
                JsonNode data = json.get("data");
                if (data != null && data.isArray()) {
                    for (JsonNode item : data) {
                        try {
                            boolean readable = item.has("readable") && item.get("readable").asBoolean();
                            if (!readable) continue;
                            String id = String.valueOf(item.get("id").asInt());
                            String title = item.get("title").asText();
                            String preview = item.has("preview") ? item.get("preview").asText() : "";
                            String artistN = "";
                            String artistImg = "";
                            if (item.has("artist") && item.get("artist").has("name")) {
                                artistN = item.get("artist").get("name").asText();
                            }
                            if (item.has("artist") && item.get("artist").has("picture_medium")) {
                                artistImg = item.get("artist").get("picture_medium").asText();
                            }
                            String albumImage = "";
                            if (item.has("album") && item.get("album").has("cover_medium")) {
                                albumImage = item.get("album").get("cover_medium").asText();
                            }
                            String duration = formatDuration(item.get("duration").asInt());
                            int rank = item.has("rank") ? item.get("rank").asInt() : 0;
                            SearchResultDto dto = new SearchResultDto("song", id, title, artistN, albumImage, duration, 0, preview, rank);
                            dto.setArtistId(deezerArtistId);
                            dto.setArtistImage(artistImg);
                            results.add(dto);
                        } catch (Exception ignored) {}
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Deezer artist radio failed for '{}': {}", deezerArtistId, e.getMessage());
        }
        return results;
    }

    private List<SearchResultDto> getArtistTopTracks(String deezerArtistId, int limit) {
        List<SearchResultDto> results = new ArrayList<>();
        try {
            String url = String.format("%s/artist/%s/top?limit=%d", DeezerConfig.API_BASE, deezerArtistId, Math.min(limit, 10));
            ResponseEntity<String> response = deezerRestTemplate.exchange(url, HttpMethod.GET, null, String.class);
            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                JsonNode json = objectMapper.readTree(response.getBody());
                JsonNode data = json.get("data");
                if (data != null && data.isArray()) {
                    for (JsonNode item : data) {
                        try {
                            String id = String.valueOf(item.get("id").asInt());
                            String title = item.get("title").asText();
                            String preview = item.has("preview") ? item.get("preview").asText() : "";
                            String artistN = "";
                            String artistImg = "";
                            if (item.has("artist") && item.get("artist").has("name")) {
                                artistN = item.get("artist").get("name").asText();
                            }
                            if (item.has("artist") && item.get("artist").has("picture_medium")) {
                                artistImg = item.get("artist").get("picture_medium").asText();
                            }
                            String albumImage = "";
                            if (item.has("album") && item.get("album").has("cover_medium")) {
                                albumImage = item.get("album").get("cover_medium").asText();
                            }
                            String duration = formatDuration(item.get("duration").asInt());
                            int rank = item.has("rank") ? item.get("rank").asInt() : 0;
                            SearchResultDto dto = new SearchResultDto("song", id, title, artistN, albumImage, duration, 0, preview, rank);
                            dto.setArtistId(deezerArtistId);
                            dto.setArtistImage(artistImg);
                            results.add(dto);
                        } catch (Exception ignored) {}
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Deezer artist top tracks failed for '{}': {}", deezerArtistId, e.getMessage());
        }
        return results;
    }

    private String formatDuration(int seconds) {
        int min = seconds / 60;
        int sec = seconds % 60;
        return String.format("%d:%02d", min, sec);
    }
}
