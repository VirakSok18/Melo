package com.melo.controller;

import com.melo.dto.YouTubeResultDto;
import com.melo.service.YouTubeService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

import java.io.*;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.*;
import java.time.Duration;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;

@RestController
@RequestMapping("/api/youtube")
@CrossOrigin(origins = "*")
public class YouTubeController {

    private static final Logger logger = LoggerFactory.getLogger(YouTubeController.class);

    private static final String YT_UA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

    private static final String FFMPEG_LOCATION = "C:\\Users\\holme\\AppData\\Local\\Microsoft\\WinGet\\Links";

    @Autowired
    private YouTubeService youTubeService;

    @PostMapping("/search")
    public ResponseEntity<Map<String, Object>> searchTrack(
            @RequestBody Map<String, String> body) {

        String title = body.getOrDefault("title", "");
        String artist = body.getOrDefault("artist", "");
        int duration = 0;
        try {
            duration = Integer.parseInt(body.getOrDefault("duration", "0"));
        } catch (NumberFormatException ignored) {}

        logger.info("POST /api/youtube/search - title='{}', artist='{}', duration={}", title, artist, duration);

        if (title.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "error", "title is required"
            ));
        }

        try {
            YouTubeResultDto result = youTubeService.searchTrack(title, artist, duration);
            if (result != null) {
                return ResponseEntity.ok(Map.of("success", true, "data", result));
            } else {
                return ResponseEntity.ok(Map.of(
                        "success", false,
                        "error", "No results found"
                ));
            }
        } catch (Exception e) {
            logger.error("YouTube search failed", e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "success", false,
                    "error", e.getMessage() != null ? e.getMessage() : "Unknown error"
            ));
        }
    }

    @PostMapping("/stream")
    public ResponseEntity<Map<String, Object>> getStreamUrl(
            @RequestBody Map<String, String> body) {

        String title = body.getOrDefault("title", "");
        String artist = body.getOrDefault("artist", "");
        boolean force = Boolean.parseBoolean(body.getOrDefault("force", "false"));
        int duration = 0;
        try {
            duration = Integer.parseInt(body.getOrDefault("duration", "0"));
        } catch (NumberFormatException ignored) {}

        logger.info("POST /api/youtube/stream - title='{}', artist='{}', force={}, duration={}", title, artist, force, duration);

        if (title.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "error", "title is required"
            ));
        }

        try {
            String streamUrl = youTubeService.getStreamUrl(title, artist, force, duration);
            if (streamUrl != null) {
                return ResponseEntity.ok(Map.of("success", true, "streamUrl", streamUrl));
            } else {
                return ResponseEntity.ok(Map.of(
                        "success", false,
                        "error", "Could not extract stream URL"
                ));
            }
        } catch (Exception e) {
            logger.error("Stream extraction failed", e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "success", false,
                    "error", e.getMessage() != null ? e.getMessage() : "Unknown error"
            ));
        }
    }

    @PostMapping("/prefetch")
    public ResponseEntity<Map<String, Object>> prefetchStreamUrls(
            @RequestBody java.util.List<Map<String, String>> tracks) {

        logger.info("POST /api/youtube/prefetch - {} tracks", tracks.size());

        java.util.List<com.melo.dto.YouTubeResultDto> dtos = new java.util.ArrayList<>();
        for (Map<String, String> track : tracks) {
            String title = track.getOrDefault("title", "");
            String artist = track.getOrDefault("artist", "");
            String videoId = track.getOrDefault("videoId", "");
            int duration = 0;
            try {
                duration = Integer.parseInt(track.getOrDefault("duration", "0"));
            } catch (NumberFormatException ignored) {}

            if (!title.isEmpty()) {
                dtos.add(new com.melo.dto.YouTubeResultDto(videoId, title, artist, duration));
            }
        }

        youTubeService.prefetchStreamUrls(dtos);

        return ResponseEntity.ok(Map.of("success", true, "prefetched", dtos.size()));
    }

    /**
     * Audio proxy. yt-dlp extracts googlevideo stream URLs that are signed for
     * the BACKEND's IP — the phone gets 403 from its own network. This endpoint
     * fetches the audio from YouTube server-side (where the URL works) and
     * streams the bytes to the phone, with Range support so ExoPlayer can seek.
     */
    @GetMapping("/proxy")
    public ResponseEntity<StreamingResponseBody> proxyAudio(
            @RequestParam("url") String url,
            @RequestHeader(value = "Range", required = false) String range) {

        URI uri;
        try {
            uri = URI.create(url);
            String scheme = uri.getScheme() == null ? "" : uri.getScheme().toLowerCase();
            String host = uri.getHost() == null ? "" : uri.getHost().toLowerCase();
            boolean allowedHost = host.endsWith("googlevideo.com")
                    || host.endsWith("youtube.com")
                    || host.endsWith("googleusercontent.com");
            if (!("https".equals(scheme) || "http".equals(scheme)) || !allowedHost) {
                logger.warn("Proxy rejected URL (host={}): {}", host, shorten(url));
                return ResponseEntity.badRequest().build();
            }
        } catch (Exception e) {
            logger.warn("Proxy rejected malformed URL: {}", shorten(url));
            return ResponseEntity.badRequest().build();
        }

        HttpClient client = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .followRedirects(HttpClient.Redirect.NORMAL)
                .build();

        HttpRequest.Builder builder = HttpRequest.newBuilder(uri).header("User-Agent", YT_UA);
        if (range != null && !range.isEmpty()) {
            builder.header("Range", range);
        }

        HttpResponse<InputStream> upstream;
        try {
            upstream = client.send(builder.build(), HttpResponse.BodyHandlers.ofInputStream());
        } catch (Exception e) {
            logger.warn("Proxy upstream request failed for {}: {}", shorten(url), e.getMessage());
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY).build();
        }

        int upstreamCode = upstream.statusCode();
        String contentType = upstream.headers().firstValue("Content-Type").orElse("audio/mp4");
        String contentRange = upstream.headers().firstValue("Content-Range").orElse(null);
        String contentLength = upstream.headers().firstValue("Content-Length").orElse(null);
        String acceptRanges = upstream.headers().firstValue("Accept-Ranges").orElse(null);

        StreamingResponseBody body = outputStream -> {
            try (InputStream in = upstream.body(); OutputStream out = outputStream) {
                byte[] buf = new byte[64 * 1024];
                int n;
                while ((n = in.read(buf)) != -1) {
                    out.write(buf, 0, n);
                    out.flush();
                }
            } catch (IOException e) {
                // Client disconnected mid-stream (seek/skip/close) — expected.
            }
        };

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.parseMediaType(contentType));
        if (contentRange != null) headers.set(HttpHeaders.CONTENT_RANGE, contentRange);
        if (acceptRanges != null) headers.set(HttpHeaders.ACCEPT_RANGES, acceptRanges);
        if (contentLength != null) {
            try {
                headers.setContentLength(Long.parseLong(contentLength));
            } catch (NumberFormatException ignored) {}
        }

        logger.info("GET /api/youtube/proxy -> upstream HTTP {} for {}", upstreamCode, shorten(url));
        return ResponseEntity.status(upstreamCode).headers(headers).body(body);
    }

    /**
     * Endpoint /play kept for compatibility. Playback is handled directly
     * on the client via DeezerProxy, JioSaavn CDN, and ClientStreamService.
     */
    @GetMapping("/play")
    public ResponseEntity<Void> playAudio(
            @RequestParam(value = "title", defaultValue = "") String title,
            @RequestParam(value = "artist", defaultValue = "") String artist,
            @RequestParam(value = "duration", defaultValue = "0") int durationSeconds,
            @RequestParam(value = "prefetch", defaultValue = "false") boolean prefetch) {

        logger.debug("GET /api/youtube/play - title='{}', artist='{}', prefetch={} (client-managed)", title, artist, prefetch);
        return ResponseEntity.noContent().build();
    }

    private static String shorten(String url) {
        if (url == null) return "";
        return url.length() > 80 ? url.substring(0, 80) + "..." : url;
    }

    @PostMapping("/download")
    public ResponseEntity<Resource> downloadSong(@RequestBody Map<String, String> body) {
        String title = body.getOrDefault("title", "");
        String artist = body.getOrDefault("artist", "");

        logger.info("POST /api/youtube/download - title='{}', artist='{}'", title, artist);

        if (title.isEmpty()) {
            return ResponseEntity.badRequest().build();
        }

        Path tempDir = null;
        try {
            // Create temp directory for yt-dlp output
            tempDir = Files.createTempDirectory("melo_dl_");
            String query = artist.isEmpty() ? title : title + " " + artist;

            // Let yt-dlp handle the filename via output template
            String outputTemplate = tempDir.toString() + File.separator + "%(title)s.%(ext)s";

            String[] command = {
                "yt-dlp",
                "-x", "--audio-format", "mp3", "--audio-quality", "5",
                "-f", "18/bestaudio",
                "--extractor-args", "youtube:player_client=android",
                "-o", outputTemplate,
                "--ffmpeg-location", FFMPEG_LOCATION,
                "--no-playlist", "--no-warnings",
                "--socket-timeout", "30",
                "ytsearch1:" + query
            };

            logger.info("Running yt-dlp: {}", String.join(" ", command));
            ProcessBuilder pb = new ProcessBuilder(command);
            pb.redirectErrorStream(true);
            Process process = pb.start();

            // Capture output for debugging
            StringBuilder output = new StringBuilder();
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    output.append(line).append("\n");
                    logger.debug("yt-dlp: {}", line);
                }
            }

            boolean finished = process.waitFor(90, TimeUnit.SECONDS);
            int exitCode = finished ? process.exitValue() : -1;

            if (exitCode != 0) {
                logger.warn("yt-dlp failed (exit={}): {}\nOutput: {}", exitCode, query, output.toString());
                deleteDir(tempDir);
                return ResponseEntity.internalServerError().build();
            }

            // Find the downloaded mp3 file in temp dir
            Path mp3File = null;
            try (var stream = Files.list(tempDir)) {
                mp3File = stream
                    .filter(p -> p.toString().endsWith(".mp3"))
                    .findFirst()
                    .orElse(null);
            }

            if (mp3File == null || Files.size(mp3File) == 0) {
                logger.warn("No MP3 file found after yt-dlp for '{} {}'", title, artist);
                deleteDir(tempDir);
                return ResponseEntity.internalServerError().build();
            }

            long fileSize = Files.size(mp3File);
            logger.info("Downloaded '{} {}' - {} bytes", title, artist, fileSize);

            FileSystemResource resource = new FileSystemResource(mp3File.toFile());
            return ResponseEntity.ok()
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .header(HttpHeaders.CONTENT_DISPOSITION,
                    "attachment; filename=\"" + title + " - " + artist + ".mp3\"")
                .contentLength(fileSize)
                .body(resource);

        } catch (Exception e) {
            logger.error("Download failed for '{} {}': {}", title, artist, e.getMessage());
            if (tempDir != null) deleteDir(tempDir);
            return ResponseEntity.internalServerError().build();
        }
    }

    private void deleteDir(Path dir) {
        if (dir == null || !Files.exists(dir)) return;
        try (var stream = Files.list(dir)) {
            stream.forEach(p -> {
                try { Files.deleteIfExists(p); } catch (IOException ignored) {}
            });
            Files.deleteIfExists(dir);
        } catch (IOException ignored) {}
    }
}
