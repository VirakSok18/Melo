package com.melo.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.melo.config.DeezerConfig;
import com.melo.dto.SearchResultDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.*;

@Service
public class DeezerSearchService {

    private static final Logger logger = LoggerFactory.getLogger(DeezerSearchService.class);

    @Autowired
    @org.springframework.beans.factory.annotation.Qualifier("deezerRestTemplate")
    private RestTemplate deezerRestTemplate;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final List<String> VARIATION_KEYWORDS = List.of(
            "remix", "sped up", "slowed", "speed up", "slowed + reverb", "reverb",
            "cover", "acoustic", "live", "karaoke", "instrumental", "piano",
            "ukulele", "string quartet", "orchestral", "mashup", "edit",
            "vip", "version", "demo", "raw", "unplugged", "a cappella",
            "nightcore", "lo-fi", "lofi", "chill", "study", "sleep",
            "workout", "running", "mix", "megamix", "extended", "radio edit",
            "dirty", "clean", "explicit", "alternate"
    );

    private boolean isOriginalTrack(String title) {
        String lower = title.toLowerCase();
        return VARIATION_KEYWORDS.stream().noneMatch(lower::contains);
    }

    public List<SearchResultDto> search(String query, int limit) {
        List<SearchResultDto> results = new ArrayList<>();

        try {
            String encodedQuery = URLEncoder.encode(query, StandardCharsets.UTF_8);

            // Search artists first
            String artistUrl = String.format("%s/search/artist?q=%s&limit=%d",
                    DeezerConfig.API_BASE, encodedQuery, Math.min(5, limit));
            List<SearchResultDto> artists = searchArtists(artistUrl);
            String qTrim = query.trim();
            if (qTrim.equalsIgnoreCase("Eve") || qTrim.equalsIgnoreCase("いぶ") || qTrim.equalsIgnoreCase("Eve (いぶ)")) {
                artists.removeIf(a -> "837".equals(a.getId()));
                if (artists.stream().noneMatch(a -> "69128312".equals(a.getId()))) {
                    artists.add(0, new SearchResultDto("artist", "69128312", "Eve", "",
                            "https://cdn-images.dzcdn.net/images/artist/d338715a1c099cecc59363cd8c68ae3d/500x500-000000-80-0-0.jpg", "", 69898, ""));
                }
            }
            results.addAll(artists);

            // Search tracks
            String trackUrl = String.format("%s/search/track?q=%s&limit=%d",
                    DeezerConfig.API_BASE, encodedQuery, Math.min(limit, 10));
            List<SearchResultDto> tracks = searchTracks(trackUrl);

            // Check if Deezer search returned a clean track with the exact query title from the top result
            String queryLower = query.toLowerCase().trim();

            // Find the highest-ranked artist from track results (including remixes)
            String bestArtistName = "";
            int bestRank = -1;
            for (SearchResultDto t : tracks) {
                if (t.getArtist() != null && !t.getArtist().isEmpty() && t.getRank() > bestRank) {
                    bestRank = t.getRank();
                    bestArtistName = t.getArtist();
                }
            }

            // Check if any existing track is a clean original by that artist
            final String artistToCheck = bestArtistName;
            boolean hasOriginal = tracks.stream().anyMatch(t -> {
                String titleLower = t.getTitle().toLowerCase().trim();
                return isOriginalTrack(t.getTitle())
                    && t.getArtist().equalsIgnoreCase(artistToCheck)
                    && (titleLower.equals(queryLower) || queryLower.contains(titleLower));
            });

            // If no original by that artist, look up their top tracks
            if (!hasOriginal && !bestArtistName.isEmpty()) {
                String bestArtistId = "";
                try {
                    String artistSearchUrl = String.format("%s/search/artist?q=%s&limit=1",
                            DeezerConfig.API_BASE, URLEncoder.encode(bestArtistName, StandardCharsets.UTF_8));
                    List<SearchResultDto> artistResults = searchArtists(artistSearchUrl);
                    if (!artistResults.isEmpty()) {
                        bestArtistId = artistResults.get(0).getId();
                    }
                } catch (Exception e) {
                    logger.warn("Artist lookup failed for '{}': {}", bestArtistName, e.getMessage());
                }

                if (!bestArtistId.isEmpty()) {
                    try {
                        String topTracksUrl = String.format("%s/artist/%s/top?limit=25",
                                DeezerConfig.API_BASE, bestArtistId);
                        List<SearchResultDto> topTracks = searchTracks(topTracksUrl);
                        for (SearchResultDto t : topTracks) {
                            String titleLower = t.getTitle().toLowerCase().trim();
                            if (isOriginalTrack(t.getTitle()) && (
                                titleLower.contains(queryLower) ||
                                queryLower.contains(titleLower))) {
                                // Never inject a duplicate of a track already
                                // present in the search results.
                                boolean alreadyExists = tracks.stream().anyMatch(existing ->
                                    existing.getId().equals(t.getId())
                                    || (existing.getTitle().equalsIgnoreCase(t.getTitle())
                                        && existing.getArtist().equalsIgnoreCase(t.getArtist())));
                                if (!alreadyExists) {
                                    t.setRank(999999);
                                    tracks.add(0, t);
                                    logger.info("Found original '{}' by '{}' from artist top tracks", t.getTitle(), bestArtistName);
                                } else {
                                    logger.info("Skipped duplicate original '{}' — already in results", t.getTitle());
                                }
                                break;
                            }
                        }
                    } catch (Exception e) {
                        logger.warn("Artist top tracks fallback failed for '{}': {}", bestArtistName, e.getMessage());
                    }
                }
            }

            tracks.sort((a, b) -> {
                boolean aOriginal = isOriginalTrack(a.getTitle());
                boolean bOriginal = isOriginalTrack(b.getTitle());
                if (aOriginal != bOriginal) {
                    return aOriginal ? -1 : 1;
                }
                return Integer.compare(b.getRank(), a.getRank());
            });

            // Remove any remaining duplicates (same id, or same title+artist)
            // so the UI never shows the same song twice.
            tracks = deduplicateTracks(tracks);
            results.addAll(tracks);

            // Search albums last
            String albumUrl = String.format("%s/search/album?q=%s&limit=%d",
                    DeezerConfig.API_BASE, encodedQuery, Math.min(5, limit));
            List<SearchResultDto> albums = searchAlbums(albumUrl);
            results.addAll(albums);

            logger.info("Deezer combined search '{}' returned {} tracks, {} artists, {} albums",
                    query, tracks.size(), artists.size(), albums.size());

        } catch (Exception e) {
            logger.error("Deezer search failed for '{}': {}", query, e.getMessage());
        }

        return results;
    }

    private List<SearchResultDto> deduplicateTracks(List<SearchResultDto> tracks) {
        List<SearchResultDto> unique = new ArrayList<>();
        java.util.Set<String> seenIds = new java.util.HashSet<>();
        java.util.Set<String> seenTitleArtist = new java.util.HashSet<>();
        for (SearchResultDto t : tracks) {
            String idKey = t.getId() == null ? "" : t.getId().trim().toLowerCase();
            String taKey = ((t.getTitle() == null ? "" : t.getTitle().trim().toLowerCase())
                    + "|" + (t.getArtist() == null ? "" : t.getArtist().trim().toLowerCase()));
            boolean dupById = !idKey.isEmpty() && !seenIds.add(idKey);
            boolean dupByTitle = !taKey.equals("|") && !seenTitleArtist.add(taKey);
            if (dupById || dupByTitle) {
                logger.debug("Dropped duplicate search result: '{}' by '{}'", t.getTitle(), t.getArtist());
                continue;
            }
            unique.add(t);
        }
        return unique;
    }

    private List<SearchResultDto> searchTracks(String url) {
        List<SearchResultDto> results = new ArrayList<>();
        try {
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

                            String artistName = "";
                            String artistId = "";
                            String artistImage = "";
                            if (item.has("artist") && item.get("artist").has("name")) {
                                artistName = item.get("artist").get("name").asText();
                            }
                            if (item.has("artist") && item.get("artist").has("id")) {
                                artistId = String.valueOf(item.get("artist").get("id").asInt());
                            }
                            if (item.has("artist") && item.get("artist").has("picture_medium")) {
                                artistImage = item.get("artist").get("picture_medium").asText();
                            }

                            String albumImage = "";
                            String albumDate = "";
                            if (item.has("album") && item.get("album").has("cover_medium")) {
                                albumImage = item.get("album").get("cover_medium").asText();
                            }
                            if (item.has("album") && item.get("album").has("release_date")) {
                                albumDate = item.get("album").get("release_date").asText();
                            }

                            String duration = formatDuration(item.get("duration").asInt());

                            int rank = item.has("rank") ? item.get("rank").asInt() : 0;

                            SearchResultDto dto = new SearchResultDto("song", id, title, artistName, albumImage, duration, 0, preview, rank);
                            dto.setArtistId(artistId);
                            dto.setArtistImage(artistImage);
                            dto.setReleaseDate(albumDate);
                            results.add(dto);
                        } catch (Exception ignored) {}
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Deezer track search failed: {}", e.getMessage());
        }
        return results;
    }

    private List<SearchResultDto> searchArtists(String url) {
        List<SearchResultDto> results = new ArrayList<>();
        try {
            ResponseEntity<String> response = deezerRestTemplate.exchange(url, HttpMethod.GET, null, String.class);
            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                JsonNode json = objectMapper.readTree(response.getBody());
                JsonNode data = json.get("data");
                if (data != null && data.isArray()) {
                    for (JsonNode item : data) {
                        try {
                            String id = String.valueOf(item.get("id").asInt());
                            String name = item.get("name").asText();
                            String image = item.has("picture_medium") ? item.get("picture_medium").asText() : "";
                            int nbFan = item.has("nb_fan") ? item.get("nb_fan").asInt() : 0;

                            results.add(new SearchResultDto("artist", id, name, "", image, "", nbFan, ""));
                        } catch (Exception ignored) {}
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Deezer artist search failed: {}", e.getMessage());
        }
        return results;
    }

    private List<SearchResultDto> searchAlbums(String url) {
        List<SearchResultDto> results = new ArrayList<>();
        try {
            ResponseEntity<String> response = deezerRestTemplate.exchange(url, HttpMethod.GET, null, String.class);
            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                JsonNode json = objectMapper.readTree(response.getBody());
                JsonNode data = json.get("data");
                if (data != null && data.isArray()) {
                    for (JsonNode item : data) {
                        try {
                            String id = String.valueOf(item.get("id").asInt());
                            String title = item.get("title").asText();
                            String image = item.has("cover_medium") ? item.get("cover_medium").asText() : "";

                            String artistName = "";
                            if (item.has("artist") && item.get("artist").has("name")) {
                                artistName = item.get("artist").get("name").asText();
                            }

                            results.add(new SearchResultDto("album", id, title, artistName, image, "", 0, ""));
                        } catch (Exception ignored) {}
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Deezer album search failed: {}", e.getMessage());
        }
        return results;
    }

    private String formatDuration(int seconds) {
        int min = seconds / 60;
        int sec = seconds % 60;
        return String.format("%d:%02d", min, sec);
    }

    public String findArtistId(String artistName) {
        if (artistName == null) return null;
        String trimmed = artistName.trim();
        if (trimmed.equalsIgnoreCase("Eve") || trimmed.equalsIgnoreCase("いぶ") || trimmed.equalsIgnoreCase("Eve (いぶ)")) {
            return "69128312";
        }
        try {
            String encodedQuery = URLEncoder.encode(artistName, StandardCharsets.UTF_8);
            String url = String.format("%s/search/artist?q=%s&limit=5",
                    DeezerConfig.API_BASE, encodedQuery);
            List<SearchResultDto> results = searchArtists(url);
            if (!results.isEmpty()) {
                // Pick the artist with the most fans (handles name collisions like "Drake")
                SearchResultDto best = results.get(0);
                for (SearchResultDto r : results) {
                    if (r.getNbFan() > best.getNbFan()) {
                        best = r;
                    }
                }
                logger.info("findArtistId '{}': picked '{}' (id={}, fans={}) from {} results",
                        artistName, best.getTitle(), best.getId(), best.getNbFan(), results.size());
                return best.getId();
            }
        } catch (Exception e) {
            logger.warn("Deezer artist ID lookup failed for '{}': {}", artistName, e.getMessage());
        }
        return null;
    }

    private List<SearchResultDto> fetchJapaneseEveTracks(int limit) {
        List<SearchResultDto> results = new ArrayList<>();
        Set<String> seenTitles = new HashSet<>();
        String[] albumIds = {"190575092", "413691027", "298076772", "199101422", "199098832"};
        String artistImage = "https://cdn-images.dzcdn.net/images/artist/d338715a1c099cecc59363cd8c68ae3d/500x500-000000-80-0-0.jpg";

        for (String albumId : albumIds) {
            if (results.size() >= limit) break;
            try {
                String albumUrl = String.format("%s/album/%s", DeezerConfig.API_BASE, albumId);
                ResponseEntity<String> albumResp = deezerRestTemplate.exchange(albumUrl, HttpMethod.GET, null, String.class);
                if (albumResp.getStatusCode().is2xxSuccessful() && albumResp.getBody() != null) {
                    JsonNode albumJson = objectMapper.readTree(albumResp.getBody());
                    String albumCover = albumJson.has("cover_medium") ? albumJson.get("cover_medium").asText() : "";
                    String releaseDate = albumJson.has("release_date") ? albumJson.get("release_date").asText() : "";
                    JsonNode tracksNode = albumJson.get("tracks");
                    JsonNode data = tracksNode != null ? tracksNode.get("data") : null;
                    if (data != null && data.isArray()) {
                        for (JsonNode item : data) {
                            if (results.size() >= limit) break;
                            String title = item.has("title") ? item.get("title").asText() : "";
                            String cleanTitle = title.toLowerCase().replaceAll("[^a-z0-9]", "");
                            if (!seenTitles.add(cleanTitle)) continue;

                            String id = String.valueOf(item.get("id").asInt());
                            String duration = formatDuration(item.has("duration") ? item.get("duration").asInt() : 0);
                            String preview = item.has("preview") ? item.get("preview").asText() : "";
                            int rank = item.has("rank") ? item.get("rank").asInt() : 0;

                            SearchResultDto dto = new SearchResultDto("song", id, title, "Eve", albumCover, duration, 0, preview, rank);
                            dto.setArtistId("69128312");
                            dto.setArtistImage(artistImage);
                            dto.setReleaseDate(releaseDate);
                            results.add(dto);
                        }
                    }
                }
            } catch (Exception e) {
                logger.warn("Failed fetching Japanese Eve album {}: {}", albumId, e.getMessage());
            }
        }
        return results;
    }

    public List<SearchResultDto> getArtistTopTracks(String artistId, int limit) {
        if ("69128312".equals(artistId)) {
            return fetchJapaneseEveTracks(limit);
        }
        List<SearchResultDto> results = new ArrayList<>();
        try {
            String url = String.format("%s/artist/%s/top?limit=%d",
                    DeezerConfig.API_BASE, artistId, Math.min(limit, 25));
            results = searchTracks(url);
            logger.info("Deezer artist top tracks for '{}' returned {} tracks", artistId, results.size());
        } catch (Exception e) {
            logger.warn("Deezer artist top tracks failed for '{}': {}", artistId, e.getMessage());
        }
        return results;
    }

    public SearchResultDto getTrackById(String trackId) {
        try {
            String url = String.format("%s/track/%s", DeezerConfig.API_BASE, trackId);
            ResponseEntity<String> response = deezerRestTemplate.exchange(url, HttpMethod.GET, null, String.class);
            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                JsonNode json = objectMapper.readTree(response.getBody());
                String id = String.valueOf(json.get("id").asInt());
                String title = json.has("title") ? json.get("title").asText() : "";
                String artistName = json.has("artist") && json.get("artist").has("name")
                        ? json.get("artist").get("name").asText() : "";
                String albumImage = "";
                if (json.has("album") && json.get("album").has("cover_medium")) {
                    albumImage = json.get("album").get("cover_medium").asText();
                }
                String duration = formatDuration(json.has("duration") ? json.get("duration").asInt() : 0);
                String preview = json.has("preview") ? json.get("preview").asText() : "";
                int rank = json.has("rank") ? json.get("rank").asInt() : 0;
                return new SearchResultDto("song", id, title, artistName, albumImage, duration, 0, preview, rank);
            }
        } catch (Exception e) {
            logger.warn("Deezer getTrackById failed for '{}': {}", trackId, e.getMessage());
        }
        return null;
    }

    public List<String> getRelatedArtistIds(String deezerArtistId) {
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

    public Map<String, Object> getArtistInfo(String artistId) {
        try {
            String url = String.format("%s/artist/%s", DeezerConfig.API_BASE, artistId);
            ResponseEntity<String> response = deezerRestTemplate.exchange(url, HttpMethod.GET, null, String.class);
            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                JsonNode json = objectMapper.readTree(response.getBody());
                String name = json.has("name") ? json.get("name").asText() : "";
                String image = json.has("picture_medium") ? json.get("picture_medium").asText() : "";
                int nbFan = json.has("nb_fan") ? json.get("nb_fan").asInt() : 0;
                String pictureBig = json.has("picture_big") ? json.get("picture_big").asText() : "";
                Map<String, Object> result = new java.util.LinkedHashMap<>();
                result.put("name", name);
                result.put("image", image);
                result.put("pictureBig", pictureBig);
                result.put("nbFan", nbFan);
                return result;
            }
        } catch (Exception e) {
            logger.warn("Deezer artist info failed for '{}': {}", artistId, e.getMessage());
        }
        return Map.of();
    }

    public List<Map<String, Object>> getArtistAlbums(String artistId) {
        List<Map<String, Object>> results = new ArrayList<>();
        try {
            String url = String.format("%s/artist/%s/albums?limit=50", DeezerConfig.API_BASE, artistId);
            ResponseEntity<String> response = deezerRestTemplate.exchange(url, HttpMethod.GET, null, String.class);
            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                JsonNode json = objectMapper.readTree(response.getBody());
                JsonNode data = json.get("data");
                if (data != null && data.isArray()) {
                    List<String> albumIds = new ArrayList<>();
                    for (JsonNode item : data) {
                        try {
                            Map<String, Object> album = new HashMap<>();
                            String albumId = String.valueOf(item.get("id").asInt());
                            album.put("id", albumId);
                            album.put("title", item.get("title").asText());
                            album.put("image", item.has("cover_medium") ? item.get("cover_medium").asText() : "");
                            album.put("bigImage", item.has("cover_big") ? item.get("cover_big").asText() : "");
                            album.put("year", item.has("release_date") ? item.get("release_date").asText().substring(0, 4) : "");
                            album.put("releaseDate", item.has("release_date") ? item.get("release_date").asText() : "");
                            album.put("artistName", item.has("artist") && item.get("artist").has("name") ? item.get("artist").get("name").asText() : "");
                            album.put("nbTracks", 0);
                            results.add(album);
                            albumIds.add(albumId);
                        } catch (Exception ignored) {}
                    }

                    java.util.concurrent.ExecutorService executor = java.util.concurrent.Executors.newFixedThreadPool(5);
                    java.util.List<java.util.concurrent.Future<Void>> futures = new ArrayList<>();
                    for (int i = 0; i < results.size(); i++) {
                        final int idx = i;
                        final String aId = albumIds.get(i);
                        futures.add(executor.submit(() -> {
                            try {
                                String albumUrl = String.format("%s/album/%s", DeezerConfig.API_BASE, aId);
                                ResponseEntity<String> albumResp = deezerRestTemplate.exchange(albumUrl, HttpMethod.GET, null, String.class);
                                if (albumResp.getStatusCode().is2xxSuccessful() && albumResp.getBody() != null) {
                                    JsonNode albumJson = objectMapper.readTree(albumResp.getBody());
                                    int nbTracks = albumJson.has("nb_tracks") ? albumJson.get("nb_tracks").asInt() : 0;
                                    results.get(idx).put("nbTracks", nbTracks);
                                }
                            } catch (Exception ignored) {}
                            return null;
                        }));
                    }
                    for (java.util.concurrent.Future<Void> f : futures) {
                        try { f.get(5, java.util.concurrent.TimeUnit.SECONDS); } catch (Exception ignored) {}
                    }
                    executor.shutdown();

                }
                logger.info("Deezer artist albums for '{}' returned {} albums", artistId, results.size());
            }
        } catch (Exception e) {
            logger.warn("Deezer artist albums failed for '{}': {}", artistId, e.getMessage());
        }
        return results;
    }

    public Map<String, Object> getAlbumInfo(String albumId) {
        try {
            String url = String.format("%s/album/%s", DeezerConfig.API_BASE, albumId);
            ResponseEntity<String> response = deezerRestTemplate.exchange(url, HttpMethod.GET, null, String.class);
            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                JsonNode json = objectMapper.readTree(response.getBody());
                String title = json.has("title") ? json.get("title").asText() : "";
                String image = json.has("cover_medium") ? json.get("cover_medium").asText() : "";
                String bigImage = json.has("cover_big") ? json.get("cover_big").asText() : "";
                String xlImage = json.has("cover_xl") ? json.get("cover_xl").asText() : "";
                int nbTracks = json.has("nb_tracks") ? json.get("nb_tracks").asInt() : 0;
                String year = json.has("release_date") ? json.get("release_date").asText() : "";
                String artistName = "";
                String artistId = "";
                if (json.has("artist") && json.get("artist").has("name")) {
                    artistName = json.get("artist").get("name").asText();
                    artistId = String.valueOf(json.get("artist").get("id").asInt());
                }
                return Map.of(
                    "title", title, "image", image, "bigImage", bigImage, "xlImage", xlImage,
                    "nbTracks", nbTracks, "year", year,
                    "artistName", artistName, "artistId", artistId
                );
            }
        } catch (Exception e) {
            logger.warn("Deezer album info failed for '{}': {}", albumId, e.getMessage());
        }
        return Map.of();
    }

    public List<SearchResultDto> searchTracksOnly(String query, int limit) {
        List<SearchResultDto> results = new ArrayList<>();
        try {
            String encodedQuery = URLEncoder.encode(query, StandardCharsets.UTF_8);
            String url = String.format("%s/search/track?q=%s&limit=%d",
                    DeezerConfig.API_BASE, encodedQuery, Math.min(limit, 10));
            results = searchTracks(url);
            logger.info("Deezer tracks-only search '{}' returned {} tracks", query, results.size());
        } catch (Exception e) {
            logger.warn("Deezer tracks-only search failed for '{}': {}", query, e.getMessage());
        }
        return results;
    }

    public List<Map<String, Object>> getAlbumTracks(String albumId) {
        List<Map<String, Object>> results = new ArrayList<>();
        try {
            String url = String.format("%s/album/%s/tracks?limit=50", DeezerConfig.API_BASE, albumId);
            ResponseEntity<String> response = deezerRestTemplate.exchange(url, HttpMethod.GET, null, String.class);
            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                JsonNode json = objectMapper.readTree(response.getBody());
                JsonNode data = json.get("data");

                String artistImage = "";
                try {
                    String albumUrl = String.format("%s/album/%s", DeezerConfig.API_BASE, albumId);
                    ResponseEntity<String> albumResp = deezerRestTemplate.exchange(albumUrl, HttpMethod.GET, null, String.class);
                    if (albumResp.getStatusCode().is2xxSuccessful() && albumResp.getBody() != null) {
                        JsonNode albumJson = objectMapper.readTree(albumResp.getBody());
                        if (albumJson.has("artist") && albumJson.get("artist").has("picture_medium")) {
                            artistImage = albumJson.get("artist").get("picture_medium").asText();
                        }
                    }
                } catch (Exception ignored) {}

                if (data != null && data.isArray()) {
                    for (JsonNode item : data) {
                        try {
                            Map<String, Object> track = new HashMap<>();
                            track.put("id", String.valueOf(item.get("id").asInt()));
                            track.put("title", item.has("title") ? item.get("title").asText() : "");
                            String artistName = "";
                            String trackArtistId = "";
                            if (item.has("artist") && item.get("artist").has("name")) {
                                artistName = item.get("artist").get("name").asText();
                                trackArtistId = String.valueOf(item.get("artist").get("id").asInt());
                            }
                            track.put("artist", artistName);
                            track.put("artistId", trackArtistId);
                            track.put("artistImage", artistImage);
                            String preview = item.has("preview") ? item.get("preview").asText() : "";
                            track.put("preview", preview);
                            int duration = item.has("duration") ? item.get("duration").asInt() : 0;
                            track.put("duration", formatDuration(duration));
                            int rank = item.has("rank") ? item.get("rank").asInt() : 0;
                            track.put("rank", rank);
                            int position = item.has("track_position") ? item.get("track_position").asInt() : 0;
                            track.put("position", position);
                            results.add(track);
                        } catch (Exception ignored) {}
                    }
                }
                logger.info("Deezer album tracks for '{}' returned {} tracks", albumId, results.size());
            }
        } catch (Exception e) {
            logger.warn("Deezer album tracks failed for '{}': {}", albumId, e.getMessage());
        }
        return results;
    }

    public List<SearchResultDto> getNewestTracksByArtist(String artistName, int maxTracks) {
        List<SearchResultDto> results = new ArrayList<>();
        try {
            String artistId = findArtistId(artistName);
            if (artistId == null) {
                logger.warn("getNewestTracksByArtist: no Deezer artist found for '{}'", artistName);
                return results;
            }

            String albumsUrl = String.format("%s/artist/%s/albums?limit=20&sort=release_date_desc", DeezerConfig.API_BASE, artistId);
            ResponseEntity<String> albumsResp = deezerRestTemplate.exchange(albumsUrl, HttpMethod.GET, null, String.class);
            if (!albumsResp.getStatusCode().is2xxSuccessful() || albumsResp.getBody() == null) {
                return results;
            }

            JsonNode albumsJson = objectMapper.readTree(albumsResp.getBody());
            JsonNode albumsData = albumsJson.get("data");
            if (albumsData == null || !albumsData.isArray() || albumsData.isEmpty()) {
                return results;
            }

            String newestAlbumId = albumsData.get(0).get("id").asText();
            String newestAlbumTitle = albumsData.get(0).has("title") ? albumsData.get(0).get("title").asText() : "";
            String newestAlbumImage = "";
            if (albumsData.get(0).has("cover_medium")) {
                newestAlbumImage = albumsData.get(0).get("cover_medium").asText();
            }
            String newestAlbumDate = "";
            if (albumsData.get(0).has("release_date")) {
                newestAlbumDate = albumsData.get(0).get("release_date").asText();
            }

            String tracksUrl = String.format("%s/album/%s/tracks?limit=%d", DeezerConfig.API_BASE, newestAlbumId, Math.min(maxTracks, 50));
            ResponseEntity<String> tracksResp = deezerRestTemplate.exchange(tracksUrl, HttpMethod.GET, null, String.class);
            if (tracksResp.getStatusCode().is2xxSuccessful() && tracksResp.getBody() != null) {
                JsonNode tracksJson = objectMapper.readTree(tracksResp.getBody());
                JsonNode tracksData = tracksJson.get("data");
                if (tracksData != null && tracksData.isArray()) {
                    for (JsonNode item : tracksData) {
                        if (results.size() >= maxTracks) break;
                        try {
                            String id = String.valueOf(item.get("id").asInt());
                            String title = item.get("title").asText();
                            String preview = item.has("preview") ? item.get("preview").asText() : "";
                            String trackArtist = artistName;
                            if (item.has("artist") && item.get("artist").has("name")) {
                                trackArtist = item.get("artist").get("name").asText();
                            }
                            String artistImg = "";
                            if (item.has("artist") && item.get("artist").has("picture_medium")) {
                                artistImg = item.get("artist").get("picture_medium").asText();
                            }
                            String trackImage = newestAlbumImage;
                            String duration = formatDuration(item.has("duration") ? item.get("duration").asInt() : 0);
                            int rank = item.has("rank") ? item.get("rank").asInt() : 0;
                            final String finalArtistId = artistId;
                            final String finalArtistImg = artistImg;
                            SearchResultDto dto = new SearchResultDto("song", id, title, trackArtist, trackImage, duration, 0, preview, rank);
                            dto.setArtistId(finalArtistId);
                            dto.setArtistImage(finalArtistImg);
                            dto.setReleaseDate(newestAlbumDate);
                            results.add(dto);
                        } catch (Exception ignored) {}
                    }
                }
            }

            logger.info("getNewestTracksByArtist '{}': {} tracks from album '{}' ({})", artistName, results.size(), newestAlbumTitle, newestAlbumDate);
        } catch (Exception e) {
            logger.warn("getNewestTracksByArtist failed for '{}': {}", artistName, e.getMessage());
        }
        return results;
    }

    public List<SearchResultDto> getTracksByArtistAndYear(String artistName, int year, int maxTracks) {
        List<SearchResultDto> results = new ArrayList<>();
        try {
            String artistId = findArtistId(artistName);
            if (artistId == null) {
                logger.warn("getTracksByArtistAndYear: no Deezer artist found for '{}'", artistName);
                return results;
            }

            String albumsUrl = String.format("%s/artist/%s/albums?limit=50&sort=release_date_desc", DeezerConfig.API_BASE, artistId);
            ResponseEntity<String> albumsResp = deezerRestTemplate.exchange(albumsUrl, HttpMethod.GET, null, String.class);
            if (!albumsResp.getStatusCode().is2xxSuccessful() || albumsResp.getBody() == null) {
                return results;
            }

            JsonNode albumsJson = objectMapper.readTree(albumsResp.getBody());
            JsonNode albumsData = albumsJson.get("data");
            if (albumsData == null || !albumsData.isArray()) {
                return results;
            }

            // Collect albums released in the target year
            List<String> yearAlbumIds = new ArrayList<>();
            Map<String, String> yearAlbumTitles = new HashMap<>();
            Map<String, String> yearAlbumImages = new HashMap<>();
            Map<String, String> yearAlbumDates = new HashMap<>();
            for (JsonNode album : albumsData) {
                if (results.size() >= maxTracks) break;
                if (!album.has("release_date")) continue;
                String releaseDate = album.get("release_date").asText();
                if (releaseDate == null || releaseDate.length() < 4) continue;
                try {
                    int albumYear = Integer.parseInt(releaseDate.substring(0, 4));
                    if (albumYear != year) continue;
                } catch (NumberFormatException e) {
                    continue;
                }
                String albumId = String.valueOf(album.get("id").asInt());
                String albumTitle = album.has("title") ? album.get("title").asText() : "";
                String albumImage = album.has("cover_medium") ? album.get("cover_medium").asText() : "";
                yearAlbumIds.add(albumId);
                yearAlbumTitles.put(albumId, albumTitle);
                yearAlbumImages.put(albumId, albumImage);
                yearAlbumDates.put(albumId, releaseDate);
            }

            // Grab tracks from those albums until we hit the limit
            for (String albumId : yearAlbumIds) {
                if (results.size() >= maxTracks) break;
                String albumImage = yearAlbumImages.getOrDefault(albumId, "");
                String albumDate = yearAlbumDates.getOrDefault(albumId, "");
                String tracksUrl = String.format("%s/album/%s/tracks?limit=%d", DeezerConfig.API_BASE, albumId, Math.min(maxTracks, 50));
                ResponseEntity<String> tracksResp = deezerRestTemplate.exchange(tracksUrl, HttpMethod.GET, null, String.class);
                if (tracksResp.getStatusCode().is2xxSuccessful() && tracksResp.getBody() != null) {
                    JsonNode tracksJson = objectMapper.readTree(tracksResp.getBody());
                    JsonNode tracksData = tracksJson.get("data");
                    if (tracksData != null && tracksData.isArray()) {
                        for (JsonNode item : tracksData) {
                            if (results.size() >= maxTracks) break;
                            try {
                                String id = String.valueOf(item.get("id").asInt());
                                String title = item.get("title").asText();
                                String preview = item.has("preview") ? item.get("preview").asText() : "";
                                String trackArtist = artistName;
                                if (item.has("artist") && item.get("artist").has("name")) {
                                    trackArtist = item.get("artist").get("name").asText();
                                }
                                String artistImg = "";
                                if (item.has("artist") && item.get("artist").has("picture_medium")) {
                                    artistImg = item.get("artist").get("picture_medium").asText();
                                }
                                String duration = formatDuration(item.has("duration") ? item.get("duration").asInt() : 0);
                                int rank = item.has("rank") ? item.get("rank").asInt() : 0;
                                SearchResultDto dto = new SearchResultDto("song", id, title, trackArtist, albumImage, duration, 0, preview, rank);
                                dto.setArtistId(artistId);
                                dto.setArtistImage(artistImg);
                                dto.setReleaseDate(albumDate);
                                results.add(dto);
                            } catch (Exception ignored) {}
                        }
                    }
                }
            }

            logger.info("getTracksByArtistAndYear '{}' ({}) : {} tracks", artistName, year, results.size());
        } catch (Exception e) {
            logger.warn("getTracksByArtistAndYear failed for '{}' ({}): {}", artistName, year, e.getMessage());
        }
        return results;
    }

    public List<SearchResultDto> getChartTracks(int limit) {
        List<SearchResultDto> results = new ArrayList<>();
        try {
            String url = String.format("%s/chart/0/tracks?limit=%d", DeezerConfig.API_BASE, Math.min(limit, 25));
            results = searchTracks(url);
            logger.info("Deezer chart tracks returned {} tracks", results.size());
        } catch (Exception e) {
            logger.warn("Deezer chart tracks failed: {}", e.getMessage());
        }
        return results;
    }

    public List<SearchResultDto> getGenreTopTracks(int deezerGenreId, int limit) {
        List<SearchResultDto> allTracks = new ArrayList<>();
        try {
            String artistsUrl = String.format("%s/genre/%d/artists?limit=15", DeezerConfig.API_BASE, deezerGenreId);
            ResponseEntity<String> response = deezerRestTemplate.exchange(artistsUrl, HttpMethod.GET, null, String.class);
            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                JsonNode json = objectMapper.readTree(response.getBody());
                JsonNode data = json.get("data");
                if (data != null && data.isArray()) {
                    List<String> artistIds = new ArrayList<>();
                    for (JsonNode item : data) {
                        artistIds.add(String.valueOf(item.get("id").asInt()));
                    }

                    for (String artistId : artistIds) {
                        if (allTracks.size() >= limit) break;
                        try {
                            String topUrl = String.format("%s/artist/%s/top?limit=%d",
                                    DeezerConfig.API_BASE, artistId, Math.min(limit, 25));
                            List<SearchResultDto> tracks = searchTracks(topUrl);
                            allTracks.addAll(tracks);
                        } catch (Exception e) {
                            logger.warn("Failed to get top tracks for artist {}: {}", artistId, e.getMessage());
                        }
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Deezer genre top tracks failed for genre {}: {}", deezerGenreId, e.getMessage());
        }

        allTracks.sort((a, b) -> Integer.compare(b.getRank(), a.getRank()));

        List<SearchResultDto> deduplicated = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (SearchResultDto track : allTracks) {
            String key = track.getTitle().toLowerCase() + "|" + track.getArtist().toLowerCase();
            if (!seen.contains(key)) {
                seen.add(key);
                deduplicated.add(track);
                if (deduplicated.size() >= limit) break;
            }
        }

        logger.info("Deezer genre top tracks for genre {} returned {} tracks", deezerGenreId, deduplicated.size());
        return deduplicated;
    }

    public List<SearchResultDto> getCuratedGenreTopTracks(List<Map<String, String>> artists, int limit) {
        List<SearchResultDto> allTracks = new ArrayList<>();
        try {
            for (Map<String, String> artistInfo : artists) {
                if (allTracks.size() >= limit * 2) break;
                try {
                    String artistName = artistInfo.getOrDefault("name", "");
                    String artistId = artistInfo.getOrDefault("id", "");
                    boolean isDeezerId = "true".equals(artistInfo.getOrDefault("isDeezerId", "false"));

                    if (artistName.isEmpty()) continue;

                    String deezerId;
                    if (isDeezerId && !artistId.isEmpty()) {
                        deezerId = artistId;
                    } else {
                        String foundId = findArtistId(artistName);
                        if (foundId == null) continue;
                        deezerId = foundId;
                    }

                    String topUrl = String.format("%s/artist/%s/top?limit=%d",
                            DeezerConfig.API_BASE, deezerId, Math.min(limit, 25));
                    List<SearchResultDto> tracks = searchTracks(topUrl);
                    allTracks.addAll(tracks);
                } catch (Exception e) {
                    logger.warn("Failed to get top tracks for curated artist '{}': {}", artistInfo.get("name"), e.getMessage());
                }
            }
        } catch (Exception e) {
            logger.warn("Deezer curated genre top tracks failed: {}", e.getMessage());
        }

        allTracks.sort((a, b) -> Integer.compare(b.getRank(), a.getRank()));

        List<SearchResultDto> deduplicated = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (SearchResultDto track : allTracks) {
            String key = track.getTitle().toLowerCase() + "|" + track.getArtist().toLowerCase();
            if (!seen.contains(key)) {
                seen.add(key);
                deduplicated.add(track);
                if (deduplicated.size() >= limit) break;
            }
        }

        logger.info("Deezer curated genre top tracks returned {} tracks", deduplicated.size());
        return deduplicated;
    }
}
