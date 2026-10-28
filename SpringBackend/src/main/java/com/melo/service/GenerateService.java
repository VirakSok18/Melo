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
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Service
public class GenerateService {

    private static final Logger logger = LoggerFactory.getLogger(GenerateService.class);

    private static final int MIN_SIZE = 5;
    private static final int MAX_SIZE = 50;
    private static final int DEFAULT_SIZE = 20;

    @Autowired
    private SupabaseConfig supabaseConfig;

    @Autowired
    private WebSearchService webSearchService;

    @Autowired
    private GroqService groqService;

    @Autowired
    private DeezerSearchService deezerSearchService;

    @Autowired
    private ListeningHistoryService listeningHistoryService;

    @Autowired
    private RecommendationService recommendationService;

    @Autowired
    private YouTubeService youTubeService;

    private final HttpClient httpClient = HttpClient.newHttpClient();
    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final Pattern LATEST_PATTERN = Pattern.compile(
            "\\b(latest|newest|recent|trending|fresh|just released|released this week|this week|this month|new songs|new music|top hits|hits now|\\d{4})\\b",
            Pattern.CASE_INSENSITIVE);

    public Map<String, Object> generatePlaylist(String mood, int requestedSize, String userId, String jwt,
                                                  List<String> artistIds, List<String> trackIds) {
        int size = clampSize(requestedSize, mood);

        boolean hasChips = (artistIds != null && !artistIds.isEmpty()) || (trackIds != null && !trackIds.isEmpty());
        logger.info("Generate playlist: mood='{}', size={}, userId={}, artistIds={}, trackIds={}", mood, size, userId, artistIds, trackIds);

        // 0) Pin tracks from chips: fetch real tracks by Deezer IDs and pin them
        //    at the front of the playlist. These always appear regardless of mood/AI.
        List<Map<String, String>> pinnedSongs = new ArrayList<>();
        if (trackIds != null) {
            for (String trackId : trackIds) {
                try {
                    SearchResultDto track = deezerSearchService.getTrackById(trackId);
                    if (track != null) {
                        pinnedSongs.add(createSongMap(track, "chip"));
                    }
                } catch (Exception e) {
                    logger.warn("Failed to fetch pinned track {}: {}", trackId, e.getMessage());
                }
            }
        }
        int remainingSlots = size - pinnedSongs.size();

        if (artistIds != null) {
            for (String artistId : artistIds) {
                try {
                    List<SearchResultDto> topTracks = deezerSearchService.getArtistTopTracks(artistId, Math.min(remainingSlots, 5));
                    if (topTracks != null) {
                        for (SearchResultDto track : topTracks) {
                            if (pinnedSongs.size() >= size) break;
                            pinnedSongs.add(createSongMap(track, "chip"));
                        }
                    }
                } catch (Exception e) {
                    logger.warn("Failed to fetch top tracks for artist {}: {}", artistId, e.getMessage());
                }
            }
        }

        // If mood is blank but chips exist, return pinned tracks directly
        if (mood.isBlank()) {
            if (!pinnedSongs.isEmpty()) {
                Map<String, Object> chipResponse = new LinkedHashMap<>();
                chipResponse.put("success", true);
                chipResponse.put("mood", mood);
                chipResponse.put("title", "Your Picks");
                chipResponse.put("description", "Tracks you selected");
                chipResponse.put("size", pinnedSongs.size());
                chipResponse.put("source", "chip");
                chipResponse.put("songs", pinnedSongs);
                return chipResponse;
            }
        }

        // Khmer path: Deezer has no Khmer music, so an artist-specific Khmer
        // request must bypass Deezer entirely and be built from YouTube, where
        // the artist name is verified against each video title. This also pins
        // the exact videoId per song so playback never falls back to a wrong
        // YouTube match.
        String khmerArtist = recommendationService.findKhmerArtistInText(mood);
        boolean isKhmerMusicRequest = isKhmerMusicRequest(mood);
        if (khmerArtist != null) {
            Map<String, Object> khmerResponse = buildKhmerPlaylist(khmerArtist, mood, remainingSlots);
            if (khmerResponse != null) {
                List<Map<String, String>> khmerSongs = (List<Map<String, String>>) khmerResponse.get("songs");
                if (khmerSongs != null) pinnedSongs.addAll(khmerSongs);
                logger.info("Generated playlist '{}' via khmer-artist path with {} songs", mood, pinnedSongs.size());
                khmerResponse.put("songs", pinnedSongs);
                khmerResponse.put("size", pinnedSongs.size());
                return khmerResponse;
            }
            logger.warn("Khmer artist path returned no songs for '{}', falling through to AI", mood);
        }

        // Live path
        if (isLatestRequest(mood) && !isKhmerMusicRequest) {
            List<Map<String, String>> liveSongs = buildLivePlaylist(mood, remainingSlots);
            if (!liveSongs.isEmpty()) {
                pinnedSongs.addAll(liveSongs);
                logger.info("Generated playlist '{}' via live with {} songs", mood, pinnedSongs.size());
                Map<String, Object> liveResponse = new LinkedHashMap<>();
                liveResponse.put("success", true);
                liveResponse.put("mood", mood);
                liveResponse.put("title", "New & Trending");
                liveResponse.put("description", "Fresh tracks pulled live from the charts");
                liveResponse.put("size", pinnedSongs.size());
                liveResponse.put("source", "live");
                liveResponse.put("songs", pinnedSongs);
                return liveResponse;
            }
            logger.warn("Live path returned no songs for '{}', falling back to AI", mood);
        }

        // 1) Web search for recent context (trimmed to keep the Groq request small)
        String searchQuery = mood + " songs playlist recommendations";
        List<String> snippets = webSearchService.search(searchQuery);
        String webContext = snippets.isEmpty() ? "" : String.join("\n", snippets);
        if (webContext.length() > 1500) {
            webContext = webContext.substring(0, 1500);
        }

        String aiTitle = "";
        String aiDescription = "";
        List<Map<String, String>> picks;

        Map<String, Object> aiResult = groqService.generatePlaylistFromMood(mood, remainingSlots, "", webContext);
        picks = extractSongs(aiResult);
        aiTitle = (String) aiResult.getOrDefault("title", "");
        aiDescription = (String) aiResult.getOrDefault("description", "");

        String source;
        if (!picks.isEmpty()) {
            source = webContext.isBlank() ? "ai-fallback" : "ai";
        } else {
            aiResult = groqService.generatePlaylistFromMood(mood, remainingSlots, "", "");
            picks = extractSongs(aiResult);
            if (!picks.isEmpty()) {
                source = "ai-fallback";
                if (aiTitle.isEmpty()) aiTitle = (String) aiResult.getOrDefault("title", "");
                if (aiDescription.isEmpty()) aiDescription = (String) aiResult.getOrDefault("description", "");
            } else {
                picks = ruleBasedFallback(mood, remainingSlots, List.of(), "");
                source = "rule-based";
            }
        }

        // A Khmer request is a hard cultural/language constraint, not merely a
        // vibe hint. Keep the AI's mood and situation choices, but accept only
        // Khmer artists, then fill any gap with verified Khmer YouTube tracks.
        if (isKhmerMusicRequest) {
            picks = keepKhmerPicks(picks);
            if (picks.size() < remainingSlots) {
                picks.addAll(verifiedKhmerFill(mood, remainingSlots - picks.size()));
            }
        }

        // Artist-request detection — skip when user explicitly picked chips
        String dominantArtist = findDominantArtist(picks);
        if (dominantArtist != null && !hasChips) {
            Map<String, Object> artistResponse = buildArtistPlaylist(dominantArtist, mood, remainingSlots);
            if (artistResponse != null) {
                List<Map<String, String>> artistSongs = (List<Map<String, String>>) artistResponse.get("songs");
                if (artistSongs != null) pinnedSongs.addAll(artistSongs);
                artistResponse.put("songs", pinnedSongs);
                artistResponse.put("size", pinnedSongs.size());
                return artistResponse;
            }
            logger.warn("Artist path returned no songs for '{}', falling back to AI resolve", dominantArtist);
        }

        // Resolve each pick
        for (Map<String, String> pick : picks) {
            if (pinnedSongs.size() >= size) break;
            Map<String, String> resolved = resolveTrack(pick);
            // Never let a failed Khmer lookup quietly become a generic song.
            if (!isKhmerMusicRequest || ("khmer".equals(resolved.get("source"))
                    && resolved.getOrDefault("videoId", "").length() > 0)) {
                pinnedSongs.add(resolved);
            }
        }

        // Chart fill if still too few
        if (pinnedSongs.size() < size && !isKhmerMusicRequest) {
            for (SearchResultDto t : deezerSearchService.getChartTracks(size - pinnedSongs.size())) {
                pinnedSongs.add(createSongMap(t, "ai"));
            }
        }

        pinnedSongs.removeIf(s -> {
            String vid = s.getOrDefault("videoId", "");
            String did = s.getOrDefault("deezerId", "");
            String id = s.getOrDefault("id", "");
            return vid.isBlank() && did.isBlank() && id.isBlank();
        });

        logger.info("Generated playlist '{}' via {} with {} songs", mood, source, pinnedSongs.size());

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("success", true);
        response.put("mood", mood);
        response.put("title", aiTitle);
        response.put("description", aiDescription);
        response.put("size", pinnedSongs.size());
        response.put("source", hasChips ? "chip-" + source : source);
        response.put("songs", pinnedSongs);
        return response;
    }

    // ---- Khmer artist path ----
    // Deezer has no Khmer music, so the generator builds artist-specific Khmer
    // playlists from YouTube where the artist name is verified against the video
    // title. Each song pins its exact videoId so playback (which searches YouTube
    // by title+artist) resolves to the correct audio instead of a lookalike.

    private Map<String, Object> buildKhmerPlaylist(String artist, String mood, int size) {
        List<Map<String, String>> songs = new ArrayList<>();
        Set<String> seen = new HashSet<>();

        List<SearchResultDto> tracks = recommendationService.getKhmerArtistSongs(artist, size + 5);
        for (SearchResultDto track : tracks) {
            if (songs.size() >= size) break;
            String key = (track.getTitle() + "|" + track.getArtist()).toLowerCase();
            if (!seen.add(key)) continue;

            Map<String, String> item = new LinkedHashMap<>();
            item.put("title", track.getTitle());
            item.put("artist", track.getArtist());
            item.put("artistId", "khmer");
            item.put("artistImage", "");
            item.put("image", "");
            item.put("duration", track.getDuration() != null ? track.getDuration() : "");
            item.put("deezerId", "");
            item.put("previewUrl", "");
            item.put("source", "khmer");

            if (track.getVideoId() != null && !track.getVideoId().isEmpty()) {
                youTubeService.rememberVideoId(track.getTitle(), track.getArtist(), track.getVideoId());
                item.put("videoId", track.getVideoId());
                item.put("id", "yt_" + track.getVideoId());
                songs.add(item);
            }
        }

        if (songs.isEmpty()) {
            logger.warn("No verified Khmer songs found for '{}'", artist);
            return null;
        }

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("success", true);
        response.put("mood", mood);
        response.put("title", artist + " — Khmer Songs");
        response.put("description", "Verified " + artist + " songs from YouTube");
        response.put("size", songs.size());
        response.put("source", "khmer");
        response.put("songs", songs);
        return response;
    }

    // ---- Artist request path (any artist, no curated list needed) ----
    // When the user asks for a specific artist ("Suly Pheng songs", "only The
    // Weeknd"), the AI usually names that artist for every pick but may invent
    // the song titles. So we keep the artist, discard the made-up titles, and
    // build the playlist from real tracks: Deezer top tracks when available,
    // verified YouTube videos otherwise (covers Khmer and other non-Deezer
    // artists).

    private String findDominantArtist(List<Map<String, String>> picks) {
        if (picks == null || picks.isEmpty()) return null;
        Map<String, Integer> counts = new LinkedHashMap<>();
        Map<String, String> originalCase = new LinkedHashMap<>();
        int total = 0;
        for (Map<String, String> pick : picks) {
            String artist = pick.getOrDefault("artist", "").trim();
            if (artist.isEmpty()) continue;
            String key = artist.toLowerCase();
            counts.merge(key, 1, Integer::sum);
            originalCase.putIfAbsent(key, artist);
            total++;
        }
        if (total == 0) return null;
        for (Map.Entry<String, Integer> e : counts.entrySet()) {
            if (e.getValue() * 100 >= total * 60) {
                return originalCase.get(e.getKey());
            }
        }
        return null;
    }

    private Map<String, Object> buildArtistPlaylist(String artist, String mood, int size) {
        List<Map<String, String>> songs = new ArrayList<>();
        Set<String> seen = new HashSet<>();

        // 1) Try Deezer top tracks first — real titles, art, duration, lyrics.
        if (!recommendationService.isKhmerArtist(artist)) {
            try {
                String artistId = deezerSearchService.findArtistId(artist);
                if (artistId != null) {
                    for (SearchResultDto t : deezerSearchService.getArtistTopTracks(artistId, size + 5)) {
                        if (songs.size() >= size) break;
                        String key = (t.getTitle() + "|" + t.getArtist()).toLowerCase();
                        if (seen.add(key)) songs.add(createSongMap(t, "artist"));
                    }
                }
            } catch (Exception e) {
                logger.warn("Deezer artist top tracks failed for '{}': {}", artist, e.getMessage());
            }
        }

        // 2) Deezer empty (or Khmer artist) → verified YouTube videos. Each
        //    track pins its exact videoId so playback is always correct.
        if (songs.size() < size) {
            for (SearchResultDto track : recommendationService.getKhmerArtistSongs(artist, size + 5)) {
                if (songs.size() >= size) break;
                String key = (track.getTitle() + "|" + track.getArtist()).toLowerCase();
                if (!seen.add(key)) continue;

                Map<String, String> item = new LinkedHashMap<>();
                item.put("title", track.getTitle());
                item.put("artist", track.getArtist());
                item.put("artistId", "khmer");
                item.put("artistImage", "");
                item.put("image", "");
                item.put("duration", track.getDuration() != null ? track.getDuration() : "");
                item.put("deezerId", "");
                item.put("previewUrl", "");
                item.put("source", "artist");
                if (track.getVideoId() != null && !track.getVideoId().isEmpty()) {
                    youTubeService.rememberVideoId(track.getTitle(), track.getArtist(), track.getVideoId());
                    item.put("videoId", track.getVideoId());
                    item.put("id", "yt_" + track.getVideoId());
                    songs.add(item);
                }
            }
        }

        if (songs.isEmpty()) {
            logger.warn("Artist path found no songs for '{}'", artist);
            return null;
        }

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("success", true);
        response.put("mood", mood);
        response.put("title", artist + " — Playlist");
        response.put("description", "Songs by " + artist);
        response.put("size", songs.size());
        response.put("source", "artist");
        response.put("songs", songs);
        return response;
    }

    // ---- Live "latest/new/trending" path ----

    private boolean isLatestRequest(String mood) {
        return mood != null && LATEST_PATTERN.matcher(mood).find();
    }

    private List<Map<String, String>> buildLivePlaylist(String mood, int size) {
        List<Map<String, String>> songs = new ArrayList<>();
        Set<String> seen = new HashSet<>();

        Integer targetYear = extractYear(mood);
        String genre = detectGenre(mood);

        // 1) If a genre is named in the request, lead with that genre's newest
        //    tracks so the playlist actually matches the genre asked for.
        if (genre != null) {
            Map<String, List<String>> genreArtists = recommendationService.getGenreToArtistNames();
            List<String> artists = genreArtists.get(genre);
            if (artists != null) {
                List<String> shuffled = new ArrayList<>(artists);
                Collections.shuffle(shuffled);
                for (String artist : shuffled) {
                    if (songs.size() >= size) break;
                    try {
                        List<SearchResultDto> newest;
                        if (targetYear != null) {
                            newest = deezerSearchService.getTracksByArtistAndYear(artist, targetYear, 3);
                        } else {
                            newest = deezerSearchService.getNewestTracksByArtist(artist, 3);
                        }
                        for (SearchResultDto t : newest) {
                            if (songs.size() >= size) break;
                            if (targetYear != null && !matchesYear(t, targetYear)) continue;
                            String key = (t.getTitle() + "|" + t.getArtist()).toLowerCase();
                            if (seen.add(key)) songs.add(createSongMap(t, "live"));
                        }
                    } catch (Exception e) {
                        logger.warn("Newest tracks for '{}' failed: {}", artist, e.getMessage());
                    }
                }
            }
        }

        // 1b) If a year was requested but the genre path alone didn't fill the
        //     list, search Deezer for "<genre> <year>" which returns that year's
        //     actual releases.
        if (targetYear != null && songs.size() < size) {
            String query = (genre != null ? genre : "") + " " + targetYear;
            try {
                List<SearchResultDto> yearTracks = deezerSearchService.searchTracksOnly(query.trim(), size * 3);
                for (SearchResultDto t : yearTracks) {
                    if (songs.size() >= size) break;
                    if (!matchesYear(t, targetYear)) continue;
                    String key = (t.getTitle() + "|" + t.getArtist()).toLowerCase();
                    if (seen.add(key)) songs.add(createSongMap(t, "live"));
                }
            } catch (Exception e) {
                logger.warn("Year search '{}' failed: {}", query, e.getMessage());
            }
        }

        // 2) Fill the rest from the global chart (currently trending)
        if (songs.size() < size) {
            try {
                List<SearchResultDto> chart = deezerSearchService.getChartTracks(size + 5);
                for (SearchResultDto t : chart) {
                    if (songs.size() >= size) break;
                    if (targetYear != null && !matchesYear(t, targetYear)) continue;
                    String key = (t.getTitle() + "|" + t.getArtist()).toLowerCase();
                    if (seen.add(key)) songs.add(createSongMap(t, "live"));
                }
            } catch (Exception e) {
                logger.warn("Live chart fetch failed: {}", e.getMessage());
            }
        }

        logger.info("Live playlist for '{}': {} songs (genre={}, year={})", mood, songs.size(), genre, targetYear);
        return songs;
    }

    private Integer extractYear(String mood) {
        if (mood == null) return null;
        Matcher m = Pattern.compile("\\b(19\\d{2}|20\\d{2})\\b").matcher(mood);
        if (m.find()) {
            return Integer.parseInt(m.group(1));
        }
        return null;
    }

    private boolean matchesYear(SearchResultDto t, int year) {
        String date = t.getReleaseDate();
        if (date == null || date.isBlank()) return false;
        try {
            return Integer.parseInt(date.substring(0, 4)) == year;
        } catch (Exception e) {
            return false;
        }
    }

    private String detectGenre(String mood) {
        if (mood == null) return null;
        String lower = mood.toLowerCase();

        // Common user spellings -> genre keys in artists.json
        Map<String, String> aliases = new LinkedHashMap<>();
        aliases.put("hip hop", "Hip Hop");
        aliases.put("hiphop", "Hip Hop");
        aliases.put("r&b", "R&B");
        aliases.put("rnb", "R&B");
        aliases.put("rb", "R&B");
        aliases.put("k-pop", "K-Pop");
        aliases.put("kpop", "K-Pop");
        aliases.put("lo-fi", "Lo-Fi");
        aliases.put("lofi", "Lo-Fi");
        aliases.put("edm", "Electronic");
        aliases.put("electronica", "Electronic");

        for (Map.Entry<String, String> alias : aliases.entrySet()) {
            if (lower.contains(alias.getKey())) {
                return alias.getValue();
            }
        }

        Map<String, List<String>> genreArtists = recommendationService.getGenreToArtistNames();
        for (String genre : genreArtists.keySet()) {
            if (lower.contains(genre.toLowerCase())) {
                return genre;
            }
        }
        return null;
    }

    // ---- AI fallback: pure rule-based playlist from mood keywords + favorites ----

    private List<Map<String, String>> ruleBasedFallback(String mood, int size,
                                                         List<String> favoriteArtists, String token) {
        logger.info("Using rule-based fallback for '{}' (size {})", mood, size);
        List<Map<String, String>> songs = new ArrayList<>();
        Set<String> seen = new HashSet<>();

        // 1) Favorite artists' top tracks first (personalized)
        for (String artist : favoriteArtists) {
            if (songs.size() >= size) break;
            try {
                String artistId = deezerSearchService.findArtistId(artist);
                if (artistId == null) continue;
                List<SearchResultDto> tracks = deezerSearchService.getArtistTopTracks(artistId, 3);
                for (SearchResultDto t : tracks) {
                    if (songs.size() >= size) break;
                    String key = (t.getTitle() + "|" + t.getArtist()).toLowerCase();
                    if (seen.add(key)) {
                        songs.add(createSongMap(t, "ai"));
                    }
                }
            } catch (Exception e) {
                logger.warn("Rule-based fallback artist '{}' failed: {}", artist, e.getMessage());
            }
        }

        // 2) Fill the rest with Deezer search on the mood itself
        if (songs.size() < size) {
            try {
                List<SearchResultDto> tracks = deezerSearchService.searchTracksOnly(mood, size + 5);
                for (SearchResultDto t : tracks) {
                    if (songs.size() >= size) break;
                    String key = (t.getTitle() + "|" + t.getArtist()).toLowerCase();
                    if (seen.add(key)) {
                        songs.add(createSongMap(t, "ai"));
                    }
                }
            } catch (Exception e) {
                logger.warn("Rule-based fallback mood search failed: {}", e.getMessage());
            }
        }

        // 3) Last resort: charts
        if (songs.size() < size) {
            for (SearchResultDto t : deezerSearchService.getChartTracks(size)) {
                if (songs.size() >= size) break;
                String key = (t.getTitle() + "|" + t.getArtist()).toLowerCase();
                if (seen.add(key)) {
                    songs.add(createSongMap(t, "ai"));
                }
            }
        }

        return songs;
    }

    private boolean isKhmerMusicRequest(String mood) {
        if (mood == null || mood.isBlank()) return false;
        String lower = mood.toLowerCase(Locale.ROOT);
        return lower.matches("(?s).*\\p{IsKhmer}.*")
                || Pattern.compile("\\b(khmer|cambodian|cambodia)\\b", Pattern.CASE_INSENSITIVE)
                .matcher(mood).find();
    }

    private List<Map<String, String>> keepKhmerPicks(List<Map<String, String>> picks) {
        List<Map<String, String>> khmerPicks = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (Map<String, String> pick : picks) {
            String artist = pick.getOrDefault("artist", "");
            String title = pick.getOrDefault("title", "");
            if (!recommendationService.isKhmerArtist(artist)) continue;
            if (title.isBlank() || artist.isBlank()) continue;
            if (seen.add((title + "|" + artist).toLowerCase(Locale.ROOT))) {
                khmerPicks.add(pick);
            }
        }
        logger.info("Kept {} verified Khmer-artist AI picks from {} candidates", khmerPicks.size(), picks.size());
        return khmerPicks;
    }

    private List<Map<String, String>> verifiedKhmerFill(String mood, int needed) {
        List<Map<String, String>> fill = new ArrayList<>();
        if (needed <= 0) return fill;

        List<String> artists = recommendationService.getKhmerArtistNames();
        if (artists.isEmpty()) return fill;
        // Rotate the trusted artist pool so different requests do not always
        // start with the same names; the original request still remains the
        // playlist's mood/context for naming and ordering.
        Collections.rotate(artists, -Math.floorMod(mood.toLowerCase(Locale.ROOT).hashCode(), artists.size()));
        Set<String> seen = new HashSet<>();
        for (String artist : artists) {
            if (fill.size() >= needed) break;
            try {
                for (SearchResultDto track : recommendationService.getKhmerArtistSongs(artist, 3)) {
                    if (fill.size() >= needed) break;
                    String title = track.getTitle();
                    String trackArtist = track.getArtist();
                    if (title == null || title.isBlank() || trackArtist == null || trackArtist.isBlank()) continue;
                    if (!seen.add((title + "|" + trackArtist).toLowerCase(Locale.ROOT))) continue;
                    Map<String, String> pick = new LinkedHashMap<>();
                    pick.put("title", title);
                    pick.put("artist", trackArtist);
                    fill.add(pick);
                }
            } catch (Exception e) {
                logger.debug("Could not load verified Khmer tracks for '{}': {}", artist, e.getMessage());
            }
        }
        return fill;
    }

    private Map<String, String> resolveTrack(Map<String, String> pick) {
        String title = pick.getOrDefault("title", "");
        String artist = pick.getOrDefault("artist", "");
        Map<String, String> item = new LinkedHashMap<>();
        item.put("title", title);
        item.put("artist", artist);
        item.put("artistId", "");
        item.put("artistImage", "");
        item.put("image", "");
        item.put("duration", "");
        item.put("deezerId", "");
        item.put("previewUrl", "");
        item.put("source", "ai");

        if (title.isEmpty() && artist.isEmpty()) return item;

        // Khmer artists have no Deezer presence — resolving through Deezer pulls
        // in wrong/unrelated tracks. Resolve via verified YouTube instead, and
        // if that can't match the title, substitute a real song by the artist.
        if (recommendationService.isKhmerArtist(artist)) {
            logger.info("Skipping Deezer resolution for Khmer artist '{}' — resolving via YouTube", artist);
            resolveViaYouTube(item, title, artist);
            return item;
        }

        try {
            String query = (title + " " + artist).trim();
            List<SearchResultDto> results = deezerSearchService.searchTracksOnly(query, 5);

            SearchResultDto bestMatch = null;
            for (SearchResultDto r : results) {
                boolean titleMatch = r.getTitle().equalsIgnoreCase(title);
                boolean artistMatch = artist.isEmpty() || r.getArtist().equalsIgnoreCase(artist);
                if (titleMatch && artistMatch) {
                    bestMatch = r;
                    break;
                }
            }
            if (bestMatch == null && !results.isEmpty()) {
                // Prefer a result that at least matches the requested artist,
                // so an artist-specific request never pulls in other artists.
                String lowerArtist = artist.toLowerCase();
                for (SearchResultDto r : results) {
                    if (r.getArtist() != null && r.getArtist().toLowerCase().contains(lowerArtist)) {
                        bestMatch = r;
                        break;
                    }
                }
            }
            if (bestMatch == null && !results.isEmpty()) {
                bestMatch = results.get(0);
            }

            if (bestMatch != null) {
                item.put("title", bestMatch.getTitle());
                item.put("artist", bestMatch.getArtist());
                item.put("artistId", bestMatch.getArtistId() != null ? bestMatch.getArtistId() : "");
                item.put("artistImage", bestMatch.getArtistImage() != null ? bestMatch.getArtistImage() : "");
                item.put("image", bestMatch.getImage() != null ? bestMatch.getImage() : "");
                item.put("duration", bestMatch.getDuration() != null ? bestMatch.getDuration() : "");
                item.put("deezerId", bestMatch.getId());
                item.put("previewUrl", bestMatch.getPreviewUrl() != null ? bestMatch.getPreviewUrl() : "");
            } else {
                // Deezer has nothing for this song — fall back to YouTube so
                // playback still lands on the right audio. This covers Khmer
                // and other artists that aren't on Deezer but weren't caught
                // by the Khmer path.
                logger.info("No Deezer match for '{}' by '{}' — resolving via YouTube", title, artist);
                resolveViaYouTube(item, title, artist);
            }
        } catch (Exception e) {
            logger.warn("Deezer resolution failed for '{}' by '{}': {}", title, artist, e.getMessage());
            resolveViaYouTube(item, title, artist);
        }
        return item;
    }

    /**
     * Searches YouTube for a title+artist that Deezer couldn't resolve, and pins
     * the exact videoId so playback downloads that precise video — never a
     * re-searched lookalike (e.g. "Please Come Back" matching a Harry Styles
     * video). If the title can't be verified on YouTube either, substitutes a
     * REAL song by the same artist (Deezer top track, or verified YouTube video
     * for Khmer/non-Deezer artists) so the playlist stays full with correct
     * audio instead of a bare/wrong entry.
     */
    private void resolveViaYouTube(Map<String, String> item, String title, String artist) {
        try {
            com.melo.dto.YouTubeResultDto match = youTubeService.searchTrack(title, artist, 0);
            if (match != null && match.getVideoId() != null && !match.getVideoId().isEmpty()) {
                youTubeService.rememberVideoId(title, artist, match.getVideoId());
                item.put("title", title);
                item.put("artist", artist);
                item.put("duration", match.getDurationSeconds() > 0
                        ? String.format("%d:%02d", match.getDurationSeconds() / 60, match.getDurationSeconds() % 60) : "");
                item.put("videoId", match.getVideoId());
                item.put("id", "yt_" + match.getVideoId());
                item.put("source", "khmer");
                return;
            }
        } catch (Exception e) {
            logger.warn("YouTube fallback error for '{}' by '{}': {}", title, artist, e.getMessage());
        }

        // Title not verifiable — substitute a real song by the same artist.
        logger.info("Title '{}' by '{}' not verified — substituting a real song by the artist", title, artist);
        replaceWithArtistSong(item, artist);
    }

    /**
     * Replaces an unverifiable pick with a real, playable song by the same
     * artist: Deezer top track, or a verified YouTube video (Khmer/non-Deezer).
     */
    private void replaceWithArtistSong(Map<String, String> item, String artist) {
        if (artist == null || artist.isBlank()) return;

        // 1) Deezer top track for non-Khmer artists.
        if (!recommendationService.isKhmerArtist(artist)) {
            try {
                String artistId = deezerSearchService.findArtistId(artist);
                if (artistId != null) {
                    List<SearchResultDto> tops = deezerSearchService.getArtistTopTracks(artistId, 5);
                    if (!tops.isEmpty()) {
                        SearchResultDto t = tops.get(0);
                        item.put("id", t.getId() != null ? t.getId() : "");
                        item.put("title", t.getTitle());
                        item.put("artist", t.getArtist());
                        item.put("artistId", t.getArtistId() != null ? t.getArtistId() : "");
                        item.put("artistImage", t.getArtistImage() != null ? t.getArtistImage() : "");
                        item.put("image", t.getImage() != null ? t.getImage() : "");
                        item.put("duration", t.getDuration() != null ? t.getDuration() : "");
                        item.put("deezerId", t.getId());
                        item.put("previewUrl", t.getPreviewUrl() != null ? t.getPreviewUrl() : "");
                        item.put("source", "ai");
                        return;
                    }
                }
            } catch (Exception e) {
                logger.warn("Deezer artist substitute failed for '{}': {}", artist, e.getMessage());
            }
        }

        // 2) Verified YouTube video (Khmer/non-Deezer artists).
        try {
            List<SearchResultDto> tracks = recommendationService.getKhmerArtistSongs(artist, 5);
            if (!tracks.isEmpty()) {
                SearchResultDto t = tracks.get(0);
                item.put("title", t.getTitle());
                item.put("artist", t.getArtist());
                item.put("artistId", "khmer");
                item.put("artistImage", "");
                item.put("image", "");
                item.put("duration", t.getDuration() != null ? t.getDuration() : "");
                item.put("deezerId", "");
                item.put("previewUrl", "");
                item.put("source", "khmer");
                if (t.getVideoId() != null && !t.getVideoId().isEmpty()) {
                    youTubeService.rememberVideoId(t.getTitle(), t.getArtist(), t.getVideoId());
                    item.put("videoId", t.getVideoId());
                    item.put("id", "yt_" + t.getVideoId());
                }
                return;
            }
        } catch (Exception e) {
            logger.warn("YouTube artist substitute failed for '{}': {}", artist, e.getMessage());
        }

        logger.warn("No substitute found for artist '{}' — keeping original pick", artist);
    }

    private Map<String, String> createSongMap(SearchResultDto track, String source) {
        Map<String, String> item = new LinkedHashMap<>();
        item.put("id", track.getId() != null ? track.getId() : "");
        item.put("title", track.getTitle());
        item.put("artist", track.getArtist());
        item.put("artistId", track.getArtistId() != null ? track.getArtistId() : "");
        item.put("artistImage", track.getArtistImage() != null ? track.getArtistImage() : "");
        item.put("image", track.getImage() != null ? track.getImage() : "");
        item.put("duration", track.getDuration() != null ? track.getDuration() : "");
        item.put("deezerId", track.getId());
        item.put("previewUrl", track.getPreviewUrl() != null ? track.getPreviewUrl() : "");
        item.put("source", source);
        if (track.getReleaseDate() != null && !track.getReleaseDate().isBlank()) {
            item.put("releaseDate", track.getReleaseDate());
        }
        return item;
    }

    // ---- Size inference ----

    private int clampSize(int requestedSize, String mood) {
        if (requestedSize > 0) return Math.max(MIN_SIZE, Math.min(MAX_SIZE, requestedSize));

        String lower = mood == null ? "" : mood.toLowerCase();

        Matcher num = Pattern.compile("(\\d+)\\s*(?:songs?|tracks?)").matcher(lower);
        if (num.find()) return clampInt(Integer.parseInt(num.group(1)));

        Matcher hour = Pattern.compile("(\\d+)\\s*(?:hour|hr)").matcher(lower);
        if (hour.find()) return clampInt((int) Math.round(Integer.parseInt(hour.group(1)) * 60.0 / 3.5));

        if (lower.contains("an hour") || lower.contains("one hour") || lower.contains("60 minutes")) return 17;
        if (lower.contains("half an hour") || lower.contains("30 minutes")) return 9;

        Matcher min = Pattern.compile("(\\d+)\\s*(?:minute|min)").matcher(lower);
        if (min.find()) return clampInt((int) Math.round(Integer.parseInt(min.group(1)) / 3.5));

        return DEFAULT_SIZE;
    }

    private int clampInt(int value) {
        return Math.max(MIN_SIZE, Math.min(MAX_SIZE, value));
    }

    // ---- Taste context ----

    private String buildTasteContext(List<String> favoriteArtists, List<String> favoriteGenres,
                                     List<Map<String, Object>> history) {
        StringBuilder sb = new StringBuilder();

        if (!history.isEmpty()) {
            sb.append("DO NOT include these songs (user already knows them — avoid ALL of these):\n");
            for (Map<String, Object> entry : history) {
                String title = (String) entry.getOrDefault("title", "");
                String artist = (String) entry.getOrDefault("artist", "");
                if (title.isEmpty() && artist.isEmpty()) continue;
                sb.append("\"").append(title).append("\" by ").append(artist).append("\n");
            }
            sb.append("\n");
        }

        if (!favoriteGenres.isEmpty()) {
            sb.append("User's preferred genres: ").append(String.join(", ", favoriteGenres)).append("\n");
            sb.append("Pick songs from these genres but from DIFFERENT artists than the avoid list above.\n\n");
        }

        return sb.toString();
    }

    // ---- Supabase helpers (mirrors DailyMixService) ----

    @SuppressWarnings("unchecked")
    private List<Map<String, String>> extractSongs(Map<String, Object> result) {
        Object songsObj = result.get("songs");
        if (songsObj instanceof List) {
            return (List<Map<String, String>>) songsObj;
        }
        return List.of();
    }

    private List<Map<String, String>> filterHistory(List<Map<String, String>> picks, Set<String> historyKeys) {
        if (historyKeys.isEmpty()) return picks;
        List<Map<String, String>> filtered = new ArrayList<>();
        for (Map<String, String> pick : picks) {
            String t = pick.getOrDefault("title", "").toLowerCase().trim();
            String a = pick.getOrDefault("artist", "").toLowerCase().trim();
            String key = t + "|" + a;
            if (!historyKeys.contains(key)) {
                filtered.add(pick);
            }
        }
        logger.info("Filtered {} history songs, {} remaining from {} picks", picks.size() - filtered.size(), filtered.size(), picks.size());
        return filtered;
    }

    private Map<String, Object> loadProfile(String userId, String token) {
        try {
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
}
