package com.melo.controller;

import com.melo.service.DeezerStreamService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.InputStreamResource;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

import java.io.*;
import java.util.Map;

@RestController
@RequestMapping("/api/deezer")
@CrossOrigin(origins = "*")
public class DeezerStreamController {

    private static final Logger logger = LoggerFactory.getLogger(DeezerStreamController.class);

    @Autowired
    private DeezerStreamService deezerStreamService;

    @GetMapping("/play")
    public ResponseEntity<InputStreamResource> playTrack(
            @RequestParam("trackId") String trackId,
            @RequestHeader(value = "Range", required = false) String range) {

        logger.info("GET /api/deezer/play - trackId={}", trackId);

        if (trackId == null || trackId.isEmpty()) {
            return ResponseEntity.badRequest().build();
        }

        try {
            byte[] decrypted = deezerStreamService.getDecryptedAudio(trackId);
            if (decrypted == null) {
                return ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY).build();
            }

            int totalLen = decrypted.length;

            if (range != null && range.startsWith("bytes=")) {
                String[] parts = range.substring(6).split("-");
                int start = Integer.parseInt(parts[0]);
                int end = (parts.length > 1 && !parts[1].isEmpty()) ? Integer.parseInt(parts[1]) : totalLen - 1;
                end = Math.min(end, totalLen - 1);
                int len = end - start + 1;
                byte[] slice = new byte[len];
                System.arraycopy(decrypted, start, slice, 0, len);

                HttpHeaders headers = new HttpHeaders();
                headers.setContentType(MediaType.parseMediaType("audio/mpeg"));
                headers.set(HttpHeaders.ACCEPT_RANGES, "bytes");
                headers.set("Content-Range", "bytes " + start + "-" + end + "/" + totalLen);
                headers.setContentLength(len);

                return ResponseEntity.status(HttpStatus.PARTIAL_CONTENT)
                        .headers(headers)
                        .body(new InputStreamResource(new ByteArrayInputStream(slice)));
            }

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.parseMediaType("audio/mpeg"));
            headers.set(HttpHeaders.ACCEPT_RANGES, "bytes");
            headers.setContentLength(totalLen);

            return ResponseEntity.ok()
                    .headers(headers)
                    .body(new InputStreamResource(new ByteArrayInputStream(decrypted)));

        } catch (Exception e) {
            logger.error("[Deezer] Play failed for trackId={}: {}", trackId, e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    @PostMapping("/stream")
    public ResponseEntity<Map<String, Object>> getStreamInfo(@RequestBody Map<String, String> body) {
        String title = body.getOrDefault("title", "");
        String artist = body.getOrDefault("artist", "");

        if (title.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("success", false, "error", "title is required"));
        }

        String proxyUrl = deezerStreamService.getStreamUrl(title, artist);
        if (proxyUrl != null) {
            String trackId = proxyUrl.contains("trackId=") ? proxyUrl.substring(proxyUrl.indexOf("trackId=") + 8) : null;
            if (trackId != null) {
                deezerStreamService.prefetchDecrypted(trackId);
            }
            return ResponseEntity.ok(Map.of("success", true, "streamUrl", proxyUrl));
        }
        return ResponseEntity.ok(Map.of("success", false, "error", "Track not found on Deezer"));
    }
}
