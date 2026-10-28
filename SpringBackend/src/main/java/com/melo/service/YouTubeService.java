package com.melo.service;

import com.melo.dto.YouTubeResultDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

@Service
public class YouTubeService {

    private static final Logger logger = LoggerFactory.getLogger(YouTubeService.class);

    private final ConcurrentHashMap<String, YouTubeResultDto> searchCache = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, String> videoIdCache = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, StreamCacheEntry> streamCache = new ConcurrentHashMap<>();
    private final Set<String> failedSearches = ConcurrentHashMap.newKeySet();
    private static final long STREAM_CACHE_TTL_MS = 10 * 60 * 1000; // 10 min (URLs are IP-locked & expire fast)

    @org.springframework.beans.factory.annotation.Autowired
    private JioSaavnService jioSaavnService;

    @org.springframework.beans.factory.annotation.Autowired
    private DeezerStreamService deezerStreamService;

    private static class StreamCacheEntry {
        final String streamUrl;
        final long createdAt;
        StreamCacheEntry(String streamUrl) {
            this.streamUrl = streamUrl;
            this.createdAt = System.currentTimeMillis();
        }
        boolean isExpired() {
            return System.currentTimeMillis() - createdAt > STREAM_CACHE_TTL_MS;
        }
    }

    public String getStreamUrl(String title, String artist) {
        return getStreamUrl(title, artist, false, 0);
    }

    public String getStreamUrl(String title, String artist, boolean forceRefresh) {
        return getStreamUrl(title, artist, forceRefresh, 0);
    }

    private static final java.util.Set<String> BAD_TITLE_KEYWORDS = java.util.Set.of(
        "karaoke", "instrumental", "cover", "no vocals", "without vocals",
        "backing track", "sing along", "sing-along", "piano version",
        "acoustic version", "ukulele", "string quartet", "orchestral",
        "a cappella", "acappella", "choir", "music box", "lullaby",
        "nightcore", "sped up", "slowed", "slowed + reverb",
        "remix", "mashup", "megamix", "extended mix", "radio edit",
        "karaoke version", "karaoke mix", "instrumental version"
    );

    // Only penalize these if the ORIGINAL search title doesn't already contain them
    private static final java.util.Set<String> CONDITIONAL_BAD_KEYWORDS = java.util.Set.of(
        "live", "concert", "stage", "performance", "acoustic live",
        "official video", "music video", "behind the scenes"
    );

    private static String cleanQuery(String title, String artist) {
        String cleaned = title
                .replaceAll("\\([^)]*\\)", "")
                .replaceAll("\\[[^]]*\\]", "")
                .replaceAll("\\{[^}]*\\}", "")
                .replaceAll("[\"']", "")
                .replaceAll("\\s+", " ")
                .trim();
        return (cleaned + " " + artist).trim();
    }

    public String getStreamUrl(String title, String artist, boolean forceRefresh, int expectedDuration) {
        String cacheKey = (title + " " + artist).toLowerCase().trim();

        if (!forceRefresh) {
            StreamCacheEntry cached = streamCache.get(cacheKey);
            if (cached != null && !cached.isExpired()) {
                logger.info("Stream URL cache hit for '{}' (0ms)", cacheKey);
                return cached.streamUrl;
            }
        } else {
            streamCache.remove(cacheKey);
        }

        // Try Deezer CDN (non-IP-locked, proxied+decrypted) — PRIMARY SOURCE
        if (deezerStreamService != null) {
            try {
                String deezerUrl = deezerStreamService.getStreamUrl(title, artist);
                if (deezerUrl != null && !deezerUrl.isEmpty()) {
                    streamCache.put(cacheKey, new StreamCacheEntry(deezerUrl));
                    logger.info("Stream URL resolved via Deezer CDN for '{}' (fast)", cacheKey);
                    return deezerUrl;
                }
            } catch (Exception e) {
                logger.warn("Deezer CDN lookup error for '{}': {}", cacheKey, e.getMessage());
            }
        }

        // Deezer failed — return null so caller falls back to /play download
        logger.warn("No Deezer stream for '{}', caller should use /play fallback", cacheKey);
        return null;
    }

    private List<YouTubeResultDto> searchMultipleResults(String query, int expectedDuration, int searchCount) {
        try {
            List<String> commandList = new ArrayList<>();
            commandList.add("yt-dlp");
            commandList.add("--no-download");
            commandList.add("--print");
            commandList.add("%(id)s|||%(title)s|||%(duration)s");
            commandList.add("--no-warnings");
            commandList.add("--no-playlist");
            commandList.add("--flat-playlist");
            commandList.add("ytsearch" + searchCount + ":" + query);
            String[] command = commandList.toArray(new String[0]);

            long start = System.currentTimeMillis();
            ProcessBuilder pb = new ProcessBuilder(command);
            pb.redirectErrorStream(true);
            Process process = pb.start();

            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            List<YouTubeResultDto> results = new ArrayList<>();
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
                    if (!videoId.isEmpty()) {
                        results.add(new YouTubeResultDto(videoId, title, "", duration));
                    }
                }
            }

            boolean finished = process.waitFor(15, TimeUnit.SECONDS);
            if (!finished) {
                process.destroyForcibly();
                logger.warn("yt-dlp search timed out for: {} ({}ms)", query, System.currentTimeMillis() - start);
                return results;
            }

            logger.info("yt-dlp search returned {} results for '{}' ({}ms)", results.size(), query, System.currentTimeMillis() - start);
            return results;

        } catch (Exception e) {
            logger.error("yt-dlp search error for '{}': {}", query, e.getMessage());
            return new ArrayList<>();
        }
    }

    private YouTubeResultDto pickBestMatch(List<YouTubeResultDto> results, int expectedDuration, String searchTitle, String searchArtist) {
        // Normalize search terms for comparison
        String searchLower = (searchTitle + " " + searchArtist).toLowerCase()
                .replaceAll("[^a-z0-9\\s]", "")
                .replaceAll("\\s+", " ")
                .trim();

        // Check if the original search title itself is a live/concert version
        String searchTitleLower = searchTitle.toLowerCase();
        boolean searchIsLive = CONDITIONAL_BAD_KEYWORDS.stream().anyMatch(searchTitleLower::contains);

        // Score each result: duration match + title similarity
        YouTubeResultDto best = results.get(0);
        double bestScore = -1;

        for (YouTubeResultDto result : results) {
            double score = 0;

            // Always penalize karaoke/instrumental/cover results heavily
            String ytTitleLower = result.getTitle().toLowerCase();
            boolean isAlwaysBad = BAD_TITLE_KEYWORDS.stream().anyMatch(ytTitleLower::contains);
            if (isAlwaysBad) {
                score -= 200;
            }

            // Only penalize live/concert if the original song ISN'T a live version
            if (!searchIsLive) {
                boolean isConditionallyBad = CONDITIONAL_BAD_KEYWORDS.stream().anyMatch(ytTitleLower::contains);
                if (isConditionallyBad) {
                    score -= 200;
                }
            }

            // Bonus: if search is live and result is live, give extra match points
            if (searchIsLive) {
                boolean ytIsLive = CONDITIONAL_BAD_KEYWORDS.stream().anyMatch(ytTitleLower::contains);
                if (ytIsLive) {
                    score += 30;
                }
            }

            // Title similarity score (0-150 points)
            String ytTitle = result.getTitle().toLowerCase()
                    .replaceAll("[^a-z0-9\\s]", "")
                    .replaceAll("\\s+", " ")
                    .trim();
            double titleSim = calculateSimilarity(searchLower, ytTitle);
            score += titleSim * 150;

            // Artist-name verification: when an artist is requested, the video
            // title must actually contain that artist's name (word-boundary
            // match). Without this, "Please Come Back" by Suly Pheng can match
            // a Harry Styles video with the same words. A huge swing makes the
            // artist decisive: an artist-matched result always beats one that
            // doesn't mention the artist at all.
            if (searchArtist != null && !searchArtist.isBlank()) {
                String artistNorm = searchArtist.toLowerCase()
                        .replaceAll("[^a-z0-9\\s]", "")
                        .replaceAll("\\s+", " ")
                        .trim();
                if (!artistNorm.isEmpty()) {
                    if (ytTitle.contains(artistNorm)) {
                        score += 300;
                    } else {
                        score -= 300;
                    }
                }
            }

            // Duration match score (0-50 points)
            if (expectedDuration > 0 && result.getDurationSeconds() > 0) {
                int diff = Math.abs(result.getDurationSeconds() - expectedDuration);
                if (diff <= 3) {
                    score += 50; // very close
                } else if (diff <= 7) {
                    score += 40;
                } else if (diff <= 15) {
                    score += 25;
                } else {
                    // Too far off — reject this result entirely
                    score -= 200;
                }
            }

            // Small bonus for shorter titles (less likely to be compilations)
            if (ytTitle.length() < searchLower.length() * 1.5) {
                score += 5;
            }

            logger.debug("Candidate '{}': titleSim={}, score={}", result.getTitle(), titleSim, score);

            if (score > bestScore) {
                bestScore = score;
                best = result;
            }
        }

        logger.info("Best match picked with score={} for search '{}'", bestScore, searchLower);

        // Reject if title similarity is too low
        if (bestScore < 30) {
            logger.warn("Best match score too low ({}), likely wrong song for '{}'. Skipping.", bestScore, searchLower);
            return null;
        }
        return best;
    }

    private double calculateSimilarity(String a, String b) {
        if (a.isEmpty() || b.isEmpty()) return 0;

        // Exact match
        if (a.equals(b)) return 1.0;

        // Check if one contains the other — penalize large length differences
        if (a.contains(b) || b.contains(a)) {
            int maxLen = Math.max(a.length(), b.length());
            int minLen = Math.min(a.length(), b.length());
            double lenRatio = (double) minLen / maxLen;
            return 0.7 + (lenRatio * 0.3); // 0.7-1.0 depending on length ratio
        }

        // Word overlap ratio
        Set<String> wordsA = new LinkedHashSet<>(java.util.Arrays.asList(a.split("\\s+")));
        Set<String> wordsB = new LinkedHashSet<>(java.util.Arrays.asList(b.split("\\s+")));

        int matches = 0;
        for (String w : wordsA) {
            if (wordsB.contains(w)) matches++;
        }

        int totalWords = Math.max(wordsA.size(), wordsB.size());
        return totalWords > 0 ? (double) matches / totalWords : 0;
    }

    private String runYtDlpExtract(String query, int expectedDuration, int searchCount) {
        try {
            List<String> commandList = new ArrayList<>();
            commandList.add("yt-dlp");
            commandList.add("-f");
            commandList.add("bestaudio");
            commandList.add("--get-url");
            commandList.add("--no-warnings");
            commandList.add("--no-playlist");
            if (expectedDuration > 0) {
                int minDur = expectedDuration - 7;
                int maxDur = expectedDuration + 7;
                commandList.add("--match-filter");
                commandList.add("duration>" + minDur + "&duration<" + maxDur);
            }
            commandList.add("--extractor-args");
            commandList.add("youtube:player_client=android");
            commandList.add("ytsearch" + searchCount + ":" + query);
            String[] command = commandList.toArray(new String[0]);

            long start = System.currentTimeMillis();
            logger.info("Running yt-dlp extract for: {} (count={})", query, searchCount);
            ProcessBuilder pb = new ProcessBuilder(command);
            pb.redirectErrorStream(true);
            Process process = pb.start();

            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            String streamUrl = reader.readLine();

            boolean finished = process.waitFor(20, TimeUnit.SECONDS);
            if (!finished) {
                process.destroyForcibly();
                logger.warn("yt-dlp extract timed out for: {} ({}ms)", query, System.currentTimeMillis() - start);
                return null;
            }

            int exitCode = process.exitValue();
            if (exitCode != 0 || streamUrl == null || streamUrl.isEmpty()) {
                logger.warn("yt-dlp extract failed (exit {}): {} ({}ms)", exitCode, query, System.currentTimeMillis() - start);
                return null;
            }

            streamUrl = streamUrl.trim();
            logger.info("yt-dlp extract succeeded in {}ms", System.currentTimeMillis() - start);
            return streamUrl;

        } catch (Exception e) {
            logger.error("yt-dlp extract error for '{}': {}", query, e.getMessage());
            return null;
        }
    }

    public String getCachedVideoId(String title, String artist) {
        String key = (title + " " + artist).toLowerCase().trim();
        String id = videoIdCache.get(key);
        return (id == null || id.isEmpty()) ? null : id;
    }

    public boolean hasFailedBefore(String title, String artist) {
        String key = (title + " " + artist).toLowerCase().trim();
        return failedSearches.contains(key);
    }

    public void rememberFailure(String title, String artist) {
        String key = (title + " " + artist).toLowerCase().trim();
        failedSearches.add(key);
    }

    public void rememberVideoId(String title, String artist, String videoId) {
        if (videoId == null || videoId.isEmpty()) return;
        String key = (title + " " + artist).toLowerCase().trim();
        videoIdCache.put(key, videoId);
    }

    public YouTubeResultDto searchTrack(String title, String artist, int expectedDuration) {
        String cacheKey = (title + " " + artist).toLowerCase().trim();

        YouTubeResultDto cached = searchCache.get(cacheKey);
        if (cached != null) {
            logger.info("YouTube cache hit for '{}' (0ms)", cacheKey);
            return cached;
        }

        String query = title + " " + artist + " lyric";
        String cleanedQuery = cleanQuery(title, artist) + " lyric";

        try {
            List<YouTubeResultDto> results = searchMultipleResults(query, expectedDuration, 20);
            if (results.isEmpty() && !cleanedQuery.equals(query)) {
                results = searchMultipleResults(cleanedQuery, expectedDuration, 20);
            }
            if (results.isEmpty()) {
                results = searchMultipleResults(title + " " + artist + " official audio", expectedDuration, 20);
            }

            if (!results.isEmpty()) {
                YouTubeResultDto best = pickBestMatch(results, expectedDuration, title, artist);
                if (best != null) {
                    videoIdCache.put(cacheKey, best.getVideoId());
                }
                searchCache.put(cacheKey, best);
                return best;
            }

            return null;

        } catch (Exception e) {
            logger.error("YouTube search failed for '{} {}': {}", title, artist, e.getMessage());
            return null;
        }
    }

    /**
     * Prefetch stream URLs. Client-side playback handles streaming directly.
     */
    public void prefetchStreamUrls(List<YouTubeResultDto> tracks) {
        // No-op: client handles playback and streaming directly
    }

    private String resolveByVideoId(String videoId) {
        try {
            long start = System.currentTimeMillis();

            List<String> commandList = new ArrayList<>();
            commandList.add("yt-dlp");
            commandList.add("-f");
            commandList.add("bestaudio");
            commandList.add("--get-url");
            commandList.add("--no-warnings");
            commandList.add("--no-playlist");
            commandList.add("--extractor-args");
            commandList.add("youtube:player_client=android");
            commandList.add("https://www.youtube.com/watch?v=" + videoId);
            String[] command = commandList.toArray(new String[0]);

            ProcessBuilder pb = new ProcessBuilder(command);
            pb.redirectErrorStream(true);
            Process process = pb.start();

            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            String streamUrl = reader.readLine();

            boolean finished = process.waitFor(5, TimeUnit.SECONDS);
            if (!finished) {
                process.destroyForcibly();
                return null;
            }

            int exitCode = process.exitValue();
            if (exitCode != 0 || streamUrl == null || streamUrl.isEmpty()) {
                logger.warn("yt-dlp resolve failed for videoId={} (exit {}, {}ms)", videoId, exitCode, System.currentTimeMillis() - start);
                return null;
            }

            logger.info("yt-dlp resolve videoId={} ({}ms)", videoId, System.currentTimeMillis() - start);
            return streamUrl.trim();

        } catch (Exception e) {
            logger.error("yt-dlp resolve error for videoId={}: {}", videoId, e.getMessage());
            return null;
        }
    }
}
