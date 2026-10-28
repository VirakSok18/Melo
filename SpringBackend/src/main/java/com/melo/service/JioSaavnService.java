package com.melo.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class JioSaavnService {

    private static final Logger logger = LoggerFactory.getLogger(JioSaavnService.class);
    private final RestTemplate restTemplate = new RestTemplate();
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final ConcurrentHashMap<String, String> cache = new ConcurrentHashMap<>();
    private static final String DES_KEY = "38586bea";

    public String getStreamUrl(String title, String artist) {
        if (title == null || title.trim().isEmpty()) {
            return null;
        }

        String cacheKey = (title + " " + (artist != null ? artist : "")).toLowerCase().trim();
        if (cache.containsKey(cacheKey)) {
            logger.info("[JioSaavn] Cache hit for '{}' -> {}", cacheKey, cache.get(cacheKey));
            return cache.get(cacheKey);
        }

        long start = System.currentTimeMillis();

        String cleanedTitle = title.replaceAll("\\([^)]*\\)", "")
                .replaceAll("\\[[^]]*\\]", "")
                .replaceAll("[\"']", "")
                .replaceAll("\\s+", " ")
                .trim();
        String cleanedArtist = (artist != null ? artist : "")
                .replaceAll("[\"']", "")
                .replaceAll("\\s+", " ")
                .trim();

        List<String> queries = new ArrayList<>();
        queries.add((cleanedTitle + " " + cleanedArtist).trim());
        queries.add((title + " " + (artist != null ? artist : "")).trim());
        if (!cleanedTitle.isEmpty() && !cleanedTitle.equalsIgnoreCase(title)) {
            queries.add(cleanedTitle);
        }

        for (String query : queries) {
            try {
                String encodedQuery = URLEncoder.encode(query, StandardCharsets.UTF_8);
                String apiUrl = "https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&cc=in&n=5&p=1&q=" + encodedQuery;

                String response = restTemplate.getForObject(apiUrl, String.class);
                if (response == null || response.isEmpty()) {
                    continue;
                }

                JsonNode root = objectMapper.readTree(response);
                JsonNode results = root.get("results");
                if (results == null || !results.isArray() || results.size() == 0) {
                    continue;
                }

                for (JsonNode item : results) {
                    String encryptedUrl = item.has("encrypted_media_url") ? item.get("encrypted_media_url").asText() : null;
                    if (encryptedUrl != null && !encryptedUrl.isEmpty()) {
                        String decryptedUrl = decryptUrl(encryptedUrl);
                        if (decryptedUrl != null && !decryptedUrl.isEmpty()) {
                            cache.put(cacheKey, decryptedUrl);
                            logger.info("[JioSaavn] Instant stream resolved for query '{}' in {}ms -> {}", query, System.currentTimeMillis() - start, decryptedUrl);
                            return decryptedUrl;
                        }
                    }
                }
            } catch (Exception e) {
                logger.warn("[JioSaavn] Error trying query '{}': {}", query, e.getMessage());
            }
        }

        logger.info("[JioSaavn] No results found for '{}' after trying multiple queries ({}ms)", title, System.currentTimeMillis() - start);
        return null;
    }

    private String decryptUrl(String encryptedUrl) {
        try {
            byte[] bytes = Base64.getDecoder().decode(encryptedUrl);
            Cipher cipher = Cipher.getInstance("DES/ECB/PKCS5Padding");
            SecretKeySpec keySpec = new SecretKeySpec(DES_KEY.getBytes(StandardCharsets.UTF_8), "DES");
            cipher.init(Cipher.DECRYPT_MODE, keySpec);
            byte[] decrypted = cipher.doFinal(bytes);
            String url = new String(decrypted, StandardCharsets.UTF_8);

            // Upgrade quality to 320kbps CDN URL if available
            return url.replace("_96.mp4", "_320.mp4")
                      .replace("_128.mp4", "_320.mp4")
                      .replace("_160.mp4", "_320.mp4");
        } catch (Exception e) {
            logger.debug("[JioSaavn] Decryption failed for URL: {}", e.getMessage());
            return null;
        }
    }
}
