package com.melo.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.melo.config.DeezerConfig;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.stereotype.Service;

import org.springframework.web.client.RestTemplate;

import javax.crypto.Cipher;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CompletableFuture;

@Service
public class DeezerStreamService {

    private static final Logger logger = LoggerFactory.getLogger(DeezerStreamService.class);
    private static final String MAGIC_KEY = "g4el58wc0zvf9na1";
    private static final int BLOCK_SIZE = 2048;
    private static final byte[] IV = {0, 1, 2, 3, 4, 5, 6, 7};

    @Autowired
    private DeezerConfig deezerConfig;

    @Autowired
    @org.springframework.beans.factory.annotation.Qualifier("deezerPrivateRestTemplate")
    private RestTemplate restTemplate;

    private final ObjectMapper mapper = new ObjectMapper();

    // Session state
    private String sessionId;
    private String apiToken;
    private String licenseToken;
    private long sessionExpiresAt = 0;

    // Caches (Extended to 6 Hours)
    private final ConcurrentHashMap<String, String> streamCache = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, String> trackTokenCache = new ConcurrentHashMap<>();
    private static final long STREAM_CACHE_TTL = 6 * 60 * 60 * 1000;

    // Decrypted audio cache + prefetch (6 Hours TTL)
    private final ConcurrentHashMap<String, byte[]> decryptedCache = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, Long> decryptedCacheTime = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, CompletableFuture<byte[]>> prefetchFutures = new ConcurrentHashMap<>();
    private static final long DECRYPTED_CACHE_TTL = 6 * 60 * 60 * 1000;
    private final java.util.concurrent.ExecutorService prefetchExecutor = java.util.concurrent.Executors.newFixedThreadPool(2);

    private static class CacheEntry {
        final String url;
        final long createdAt;
        CacheEntry(String url) { this.url = url; this.createdAt = System.currentTimeMillis(); }
        boolean isExpired() { return System.currentTimeMillis() - createdAt > STREAM_CACHE_TTL; }
    }
    private final ConcurrentHashMap<String, CacheEntry> cdnUrlCache = new ConcurrentHashMap<>();

    public String getStreamUrl(String title, String artist) {
        if (title == null || title.trim().isEmpty()) return null;
        if (deezerConfig.getArl() == null || deezerConfig.getArl().isEmpty()) {
            logger.warn("[Deezer] No ARL configured, skipping");
            return null;
        }

        String cacheKey = (title + " " + (artist != null ? artist : "")).toLowerCase().trim();

        CacheEntry cached = cdnUrlCache.get(cacheKey);
        if (cached != null && !cached.isExpired()) {
            logger.info("[Deezer] Cache hit for '{}'", cacheKey);
            return cached.url;
        }

        long start = System.currentTimeMillis();

        try {
            ensureAuthenticated();
            if (apiToken == null || licenseToken == null) {
                logger.warn("[Deezer] Authentication failed, skipping");
                return null;
            }

            String trackId = searchTrack(title, artist);
            if (trackId == null) {
                logger.info("[Deezer] No track found for '{}' ({}ms)", cacheKey, System.currentTimeMillis() - start);
                return null;
            }

            String cdnUrl = getCdnUrl(trackId);
            if (cdnUrl == null) {
                logger.warn("[Deezer] Failed to get CDN URL for trackId={} ({}ms)", trackId, System.currentTimeMillis() - start);
                return null;
            }

            // Append trackId so Flutter can extract it for Blowfish key derivation
            String urlWithTrackId = cdnUrl + "?trackId=" + trackId;
            cdnUrlCache.put(cacheKey, new CacheEntry(urlWithTrackId));
            streamCache.put(trackId, cdnUrl);

            logger.info("[Deezer] Stream resolved for '{}' trackId={} ({}ms)", cacheKey, trackId, System.currentTimeMillis() - start);
            return urlWithTrackId;

        } catch (Exception e) {
            logger.error("[Deezer] Stream resolution failed for '{}': {}", cacheKey, e.getMessage());
            return null;
        }
    }

    public String getRawCdnUrl(String trackId) {
        if (trackId == null) return null;

        String cached = streamCache.get(trackId);
        if (cached != null) return cached;

        try {
            ensureAuthenticated();
            if (apiToken == null || licenseToken == null) return null;

            String cdnUrl = getCdnUrl(trackId);
            if (cdnUrl != null) {
                streamCache.put(trackId, cdnUrl);
            }
            return cdnUrl;
        } catch (Exception e) {
            logger.error("[Deezer] Failed to get CDN URL for trackId={}: {}", trackId, e.getMessage());
            return null;
        }
    }

    /**
     * Search via the public Deezer API (reliable, no CSRF needed).
     * Returns the track ID or null.
     */
    private String searchTrack(String title, String artist) {
        try {
            String query = java.net.URLEncoder.encode((title + " " + (artist != null ? artist : "")).trim(), "UTF-8");
            String url = "https://api.deezer.com/search?q=" + query + "&limit=5";

            HttpHeaders headers = new HttpHeaders();
            headers.setAccept(Collections.singletonList(MediaType.APPLICATION_JSON));

            HttpEntity<Void> entity = new HttpEntity<>(headers);
            ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.GET, entity, String.class);

            if (!response.getStatusCode().is2xxSuccessful() || response.getBody() == null) {
                logger.warn("[Deezer] Public search HTTP {} for '{}'", response.getStatusCode(), query);
                return null;
            }

            String respBody = response.getBody();
            JsonNode root = mapper.readTree(respBody);

            JsonNode data = root.get("data");
            if (data == null || !data.isArray() || data.isEmpty()) {
                logger.info("[Deezer] No results from public API for '{}'", query);
                return null;
            }

            logger.info("[Deezer] Public API returned {} results for '{}'", data.size(), query);

            String titleLower = title.toLowerCase().trim();
            String artistLower = (artist != null ? artist : "").toLowerCase().trim();

            // Try exact match first
            for (JsonNode track : data) {
                String trackTitle = track.has("title") ? track.get("title").asText().toLowerCase() : "";
                String trackArtist = "";
                if (track.has("artist") && track.get("artist").has("name")) {
                    trackArtist = track.get("artist").get("name").asText().toLowerCase();
                }

                if (trackTitle.contains(titleLower) &&
                    (artistLower.isEmpty() || trackArtist.contains(artistLower))) {
                    String id = String.valueOf(track.get("id").asLong());
                    logger.info("[Deezer] Matched '{}' by '{}' (id={})", trackTitle, trackArtist, id);
                    return id;
                }
            }

            // Fallback: first result
            JsonNode first = data.get(0);
            String firstTitle = first.has("title") ? first.get("title").asText() : "";
            String firstArtist = "";
            if (first.has("artist") && first.get("artist").has("name")) {
                firstArtist = first.get("artist").get("name").asText();
            }
            logger.info("[Deezer] No exact match, using first: '{}' by '{}' (id={})", firstTitle, firstArtist, first.get("id").asLong());
            return String.valueOf(first.get("id").asLong());

        } catch (Exception e) {
            logger.error("[Deezer] Public search failed for '{} {}': {}", title, artist, e.getMessage());
            return null;
        }
    }

    /**
     * Get CDN URL via private gw-light API.
     * Flow: song.getListData → track token → media.deezer.com/get_url → encrypted CDN URL.
     */
    private String getCdnUrl(String trackId) {
        try {
            String trackToken = getTrackToken(trackId);
            if (trackToken == null) {
                logger.warn("[Deezer] No track token for trackId={}", trackId);
                return null;
            }

            String body = "{" +
                "\"license_token\":\"" + licenseToken + "\"," +
                "\"media\":[{\"type\":\"FULL\",\"formats\":[{\"cipher\":\"BF_CBC_STRIPE\",\"format\":\"MP3_128\"}]}]," +
                "\"track_tokens\":[\"" + trackToken + "\"]" +
                "}";

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);

            HttpEntity<String> entity = new HttpEntity<>(body, headers);
            ResponseEntity<String> response = restTemplate.exchange(
                DeezerConfig.MEDIA_BASE + "/get_url", HttpMethod.POST, entity, String.class);

            if (!response.getStatusCode().is2xxSuccessful() || response.getBody() == null) {
                logger.warn("[Deezer] media/get_url HTTP {}", response.getStatusCode());
                return null;
            }

            String respBody = response.getBody();
            logger.info("[Deezer] media/get_url response ({} chars): {}", respBody.length(),
                respBody.length() > 300 ? respBody.substring(0, 300) + "..." : respBody);

            JsonNode root = mapper.readTree(respBody);

            if (root.has("errors")) {
                logger.warn("[Deezer] media/get_url errors: {}", root.get("errors").toString());
                return null;
            }

            JsonNode data = root.get("data");
            if (data == null || !data.isArray() || data.isEmpty()) return null;

            JsonNode media = data.get(0).get("media");
            if (media == null || !media.isArray() || media.isEmpty()) return null;

            JsonNode sources = media.get(0).get("sources");
            if (sources == null || !sources.isArray() || sources.isEmpty()) return null;

            String cdnUrl = sources.get(0).get("url").asText();
            logger.info("[Deezer] CDN URL for trackId={}: {}...", trackId, cdnUrl.substring(0, Math.min(80, cdnUrl.length())));
            return cdnUrl;

        } catch (Exception e) {
            logger.warn("[Deezer] CDN URL resolution failed for trackId={}: {}", trackId, e.getMessage());
            return null;
        }
    }

    /**
     * Get track token via gw-light song.getListData.
     * Uses form-encoded body (gw-light requirement).
     */
    private String getTrackToken(String trackId) {
        String cached = trackTokenCache.get(trackId);
        if (cached != null) return cached;

        try {
            String url = DeezerConfig.GW_BASE + "?method=song.getListData&input=3&api_version=1.0&api_token=" + apiToken;

            String jsonBody = "{\"sng_ids\":[" + trackId + "]}";

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("Cookie", buildCookieHeader());

            HttpEntity<String> entity = new HttpEntity<>(jsonBody, headers);
            ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.POST, entity, String.class);

            if (!response.getStatusCode().is2xxSuccessful() || response.getBody() == null) {
                logger.warn("[Deezer] song.getListData HTTP {} for trackId={}", response.getStatusCode(), trackId);
                return null;
            }

            String respBody = response.getBody();
            logger.info("[Deezer] song.getListData for trackId={}: {}", trackId,
                respBody.length() > 300 ? respBody.substring(0, 300) + "..." : respBody);

            JsonNode root = mapper.readTree(respBody);

            // gw-light returns "error":[] (empty) on success, "error":{"KEY":"msg"} on failure
            JsonNode errorNode = root.get("error");
            if (errorNode != null && errorNode.isObject() && !errorNode.isEmpty()) {
                logger.warn("[Deezer] song.getListData error for trackId={}: {}", trackId, errorNode.toString());
                return null;
            }

            JsonNode results = root.get("results");
            if (results == null) return null;

            JsonNode data = results.get("data");
            if (data == null || !data.isArray() || data.isEmpty()) return null;

            JsonNode trackData = data.get(0);
            String token = null;

            if (trackData.has("TRACK_TOKEN") && !trackData.get("TRACK_TOKEN").asText().isEmpty()) {
                token = trackData.get("TRACK_TOKEN").asText();
            } else if (trackData.has("FALLBACK") && trackData.get("FALLBACK").has("TRACK_TOKEN")) {
                token = trackData.get("FALLBACK").get("TRACK_TOKEN").asText();
            }

            if (token != null) {
                trackTokenCache.put(trackId, token);
                logger.info("[Deezer] Got track token for trackId={}: {}...", trackId, token.substring(0, Math.min(30, token.length())));
            } else {
                logger.warn("[Deezer] No TRACK_TOKEN in response for trackId={}", trackId);
            }
            return token;

        } catch (Exception e) {
            logger.warn("[Deezer] Track token failed for trackId={}: {}", trackId, e.getMessage());
            return null;
        }
    }

    /**
     * Ensure we have a valid session with api_token and license_token.
     * All gw-light calls use form-encoded bodies.
     */
    private synchronized void ensureAuthenticated() {
        if (apiToken != null && licenseToken != null && System.currentTimeMillis() < sessionExpiresAt) {
            return;
        }

        try {
            String arl = deezerConfig.getArl();
            if (arl == null || arl.isEmpty()) return;

            // Step 1: Ping to get session ID (form-encoded, no body needed)
            String pingUrl = DeezerConfig.GW_BASE + "?method=deezer.ping&api_version=1.0&api_token=";
            HttpHeaders pingHeaders = new HttpHeaders();
            pingHeaders.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
            pingHeaders.set("Cookie", "arl=" + arl);
            pingHeaders.setContentLength(0);

            HttpEntity<String> pingEntity = new HttpEntity<>("", pingHeaders);
            ResponseEntity<String> pingResp = restTemplate.exchange(pingUrl, HttpMethod.POST, pingEntity, String.class);

            if (!pingResp.getStatusCode().is2xxSuccessful() || pingResp.getBody() == null) {
                logger.warn("[Deezer] Ping failed: HTTP {}", pingResp.getStatusCode());
                return;
            }

            String pingBody = pingResp.getBody();
            logger.info("[Deezer] Ping response: {}", pingBody.length() > 200 ? pingBody.substring(0, 200) + "..." : pingBody);

            JsonNode pingRoot = mapper.readTree(pingBody);
            JsonNode results = pingRoot.get("results");
            if (results == null || !results.has("SESSION")) {
                logger.warn("[Deezer] No SESSION in ping response: {}", pingBody);
                return;
            }
            sessionId = results.get("SESSION").asText();
            logger.info("[Deezer] Got session: {}", sessionId.substring(0, Math.min(20, sessionId.length())));

            // Step 2: Get user data (api_token + license_token)
            String userDataUrl = DeezerConfig.GW_BASE + "?method=deezer.getUserData&input=3&api_version=1.0&api_token=";
            HttpHeaders userHeaders = new HttpHeaders();
            userHeaders.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
            userHeaders.set("Cookie", "arl=" + arl + "; sid=" + sessionId);
            userHeaders.setContentLength(0);

            HttpEntity<String> userEntity = new HttpEntity<>("", userHeaders);
            ResponseEntity<String> userResp = restTemplate.exchange(userDataUrl, HttpMethod.POST, userEntity, String.class);

            if (!userResp.getStatusCode().is2xxSuccessful() || userResp.getBody() == null) {
                logger.warn("[Deezer] getUserData failed: HTTP {}", userResp.getStatusCode());
                return;
            }

            String userBody = userResp.getBody();
            logger.info("[Deezer] getUserData response ({} chars): {}", userBody.length(),
                userBody.length() > 400 ? userBody.substring(0, 400) + "..." : userBody);

            JsonNode userRoot = mapper.readTree(userBody);
            JsonNode userResults = userRoot.get("results");
            if (userResults == null) {
                logger.warn("[Deezer] No 'results' in getUserData response");
                return;
            }

            if (userResults.has("checkForm")) {
                apiToken = userResults.get("checkForm").asText();
            }

            JsonNode user = userResults.get("USER");
            if (user != null && user.has("OPTIONS")) {
                JsonNode options = user.get("OPTIONS");
                if (options.has("license_token")) {
                    licenseToken = options.get("license_token").asText();
                }
            }

            if (apiToken != null && licenseToken != null) {
                sessionExpiresAt = System.currentTimeMillis() + (55 * 60 * 1000);
                logger.info("[Deezer] Authenticated OK — apiToken={}... licenseToken={}...",
                    apiToken.substring(0, Math.min(10, apiToken.length())),
                    licenseToken.substring(0, Math.min(10, licenseToken.length())));
            } else {
                logger.warn("[Deezer] Auth incomplete: apiToken={}, licenseToken={}", apiToken, licenseToken);
            }

        } catch (Exception e) {
            logger.error("[Deezer] Auth error: {}", e.getMessage(), e);
        }
    }

    private String buildCookieHeader() {
        String arl = deezerConfig.getArl();
        if (sessionId != null && !sessionId.isEmpty()) {
            return "arl=" + arl + "; sid=" + sessionId;
        }
        return "arl=" + arl;
    }

    public byte[] decryptAudio(byte[] encrypted, String trackId) throws Exception {
        byte[] key = calculateBfKey(trackId);

        Cipher cipher = Cipher.getInstance("Blowfish/CBC/NoPadding");
        SecretKeySpec keySpec = new SecretKeySpec(key, "Blowfish");
        IvParameterSpec ivSpec = new IvParameterSpec(IV);

        byte[] decrypted = new byte[encrypted.length];
        int offset = 0;
        int blockIndex = 0;

        while (offset < encrypted.length) {
            int blockSize = Math.min(BLOCK_SIZE, encrypted.length - offset);

            if (blockIndex % 3 == 0) {
                byte[] block = new byte[blockSize];
                System.arraycopy(encrypted, offset, block, 0, blockSize);

                int paddedSize = ((blockSize + 7) / 8) * 8;
                byte[] padded = new byte[paddedSize];
                System.arraycopy(block, 0, padded, 0, blockSize);

                cipher.init(Cipher.DECRYPT_MODE, keySpec, ivSpec);
                byte[] decryptedBlock = cipher.doFinal(padded);

                System.arraycopy(decryptedBlock, 0, decrypted, offset, blockSize);
            } else {
                System.arraycopy(encrypted, offset, decrypted, offset, blockSize);
            }

            offset += blockSize;
            blockIndex++;
        }

        return decrypted;
    }

    private byte[] calculateBfKey(String trackId) throws Exception {
        MessageDigest md5 = MessageDigest.getInstance("MD5");
        byte[] md5Bytes = md5.digest(trackId.getBytes(StandardCharsets.UTF_8));

        StringBuilder md5Hex = new StringBuilder();
        for (byte b : md5Bytes) {
            md5Hex.append(String.format("%02x", b));
        }

        byte[] key = new byte[16];
        for (int i = 0; i < 16; i++) {
            char md5CharFirst = md5Hex.charAt(i);
            char md5CharSecond = md5Hex.charAt(i + 16);
            char magicChar = MAGIC_KEY.charAt(i);
            key[i] = (byte) (md5CharFirst ^ md5CharSecond ^ magicChar);
        }

        return key;
    }

    public void prefetchDecrypted(String trackId) {
        if (trackId == null || trackId.isEmpty()) return;
        if (decryptedCacheTime.containsKey(trackId)) return;
        if (prefetchFutures.containsKey(trackId)) return;

        logger.info("[Deezer] Starting prefetch for trackId={}", trackId);
        CompletableFuture<byte[]> future = CompletableFuture.supplyAsync(() -> {
            try {
                Thread.sleep(100);
                byte[] result = downloadAndDecryptTrack(trackId);
                if (result != null) {
                    decryptedCache.put(trackId, result);
                    decryptedCacheTime.put(trackId, System.currentTimeMillis());
                    logger.info("[Deezer] Prefetch complete for trackId={} ({} bytes)", trackId, result.length);
                }
                return result;
            } catch (Exception e) {
                logger.error("[Deezer] Prefetch error for trackId={}: {}", trackId, e.getMessage());
                return null;
            }
        }, prefetchExecutor);
        prefetchFutures.put(trackId, future);
    }

    public byte[] getDecryptedAudio(String trackId) {
        Long cachedTime = decryptedCacheTime.get(trackId);
        if (cachedTime != null && System.currentTimeMillis() - cachedTime < DECRYPTED_CACHE_TTL) {
            byte[] cached = decryptedCache.get(trackId);
            if (cached != null) {
                logger.info("[Deezer] Decrypted cache hit for trackId={} ({} bytes)", trackId, cached.length);
                return cached;
            }
        }

        CompletableFuture<byte[]> future = prefetchFutures.remove(trackId);
        if (future != null) {
            try {
                logger.info("[Deezer] Waiting on in-flight prefetch for trackId={}", trackId);
                byte[] result = future.get(30, java.util.concurrent.TimeUnit.SECONDS);
                if (result != null) {
                    decryptedCache.put(trackId, result);
                    decryptedCacheTime.put(trackId, System.currentTimeMillis());
                    return result;
                }
            } catch (Exception e) {
                logger.warn("[Deezer] Prefetch wait failed for trackId={}: {}", trackId, e.getMessage());
            }
        }

        return downloadAndDecryptTrack(trackId);
    }

    private byte[] downloadAndDecryptTrack(String trackId) {
        try {
            String cdnUrl = getRawCdnUrl(trackId);
            if (cdnUrl == null) return null;

            long start = System.currentTimeMillis();
            java.net.http.HttpClient client = java.net.http.HttpClient.newBuilder()
                    .connectTimeout(java.time.Duration.ofSeconds(10))
                    .followRedirects(java.net.http.HttpClient.Redirect.NORMAL)
                    .build();

            java.net.http.HttpRequest request = java.net.http.HttpRequest.newBuilder()
                    .uri(java.net.URI.create(cdnUrl))
                    .header("User-Agent", "Mozilla/5.0")
                    .GET()
                    .build();

            java.net.http.HttpResponse<byte[]> response = client.send(request, java.net.http.HttpResponse.BodyHandlers.ofByteArray());
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                logger.warn("[Deezer] CDN download failed: HTTP {} for trackId={}", response.statusCode(), trackId);
                return null;
            }

            byte[] encrypted = response.body();
            logger.info("[Deezer] Downloaded {} bytes in {}ms for trackId={}", encrypted.length, System.currentTimeMillis() - start, trackId);

            byte[] decrypted;
            if ((encrypted[0] & 0xFF) == 0xFF && ((encrypted[1] & 0xE0) == 0xE0)) {
                decrypted = encrypted;
            } else {
                long decStart = System.currentTimeMillis();
                decrypted = decryptAudio(encrypted, trackId);
                logger.info("[Deezer] Decrypted in {}ms for trackId={}", System.currentTimeMillis() - decStart, trackId);
            }

            return decrypted;

        } catch (Exception e) {
            logger.error("[Deezer] downloadAndDecryptTrack failed for trackId={}: {}", trackId, e.getMessage());
            return null;
        }
    }
}
