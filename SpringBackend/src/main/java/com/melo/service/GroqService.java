package com.melo.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.melo.config.GroqConfig;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import java.util.*;

@Service
public class GroqService {

    private static final Logger logger = LoggerFactory.getLogger(GroqService.class);

    @Autowired
    private GroqConfig groqConfig;

    private final RestTemplate restTemplate = new RestTemplate();
    private final ObjectMapper objectMapper = new ObjectMapper();

    public Map<String, List<Map<String, String>>> generateAllPlaylists(
            List<String> genres,
            Map<String, List<Map<String, Object>>> historyByGenre,
            Map<String, List<String>> recommendMoreByGenre,
            Map<String, List<String>> recommendLessByGenre) {

        for (int attempt = 1; attempt <= 2; attempt++) {
            try {
                String prompt = buildPrompt(genres, historyByGenre, recommendMoreByGenre, recommendLessByGenre);

                HttpHeaders headers = new HttpHeaders();
                headers.setContentType(MediaType.APPLICATION_JSON);
                headers.setBearerAuth(groqConfig.getApiKey());

                Map<String, Object> body = new LinkedHashMap<>();
                body.put("model", groqConfig.getModel());
                body.put("messages", List.of(
                    Map.of("role", "system", "content",
                        "You are a music recommendation AI. Return ONLY a JSON object where each key is a genre " +
                        "and each value is a JSON array of 20 objects with 'title' and 'artist' fields only. " +
                        "No markdown, no explanation, just the JSON object."),
                    Map.of("role", "user", "content", prompt)
                ));
                body.put("temperature", 0.8);
                body.put("max_tokens", 5000);

                HttpEntity<Map<String, Object>> request = new HttpEntity<>(body, headers);

                ResponseEntity<String> response = restTemplate.exchange(
                    groqConfig.getApiUrl(), HttpMethod.POST, request, String.class);

                if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                    JsonNode json = objectMapper.readTree(response.getBody());
                    String content = json.get("choices").get(0).get("message").get("content").asText();

                    content = content.trim();
                    if (content.startsWith("```")) {
                        content = content.replaceAll("^```(json)?\\s*", "").replaceAll("\\s*```$", "");
                    }

                    JsonNode root = objectMapper.readTree(content);
                    Map<String, List<Map<String, String>>> result = new LinkedHashMap<>();

                    for (String genre : genres) {
                        List<Map<String, String>> songs = new ArrayList<>();
                        if (root.has(genre) && root.get(genre).isArray()) {
                            for (JsonNode song : root.get(genre)) {
                                Map<String, String> entry = new LinkedHashMap<>();
                                entry.put("title", song.get("title").asText());
                                entry.put("artist", song.get("artist").asText());
                                songs.add(entry);
                            }
                        }
                        result.put(genre, songs);
                        logger.info("Groq generated {} songs for genre: {}", songs.size(), genre);
                    }
                    return result;
                }
            } catch (HttpClientErrorException.TooManyRequests e) {
                logger.warn("Groq rate limit hit (attempt {}/2), waiting 35s...", attempt);
                if (attempt == 1) {
                    try { Thread.sleep(35000); } catch (InterruptedException ie) { Thread.currentThread().interrupt(); }
                }
            } catch (Exception e) {
                logger.error("Groq batch playlist generation failed: {}", e.getMessage(), e);
                return Map.of();
            }
        }
        return Map.of();
    }

    public Map<String, List<Map<String, String>>> generateNewReleases(
            List<String> topArtists,
            List<String> topGenres,
            List<Map<String, Object>> listeningHistory) {

        for (int attempt = 1; attempt <= 2; attempt++) {
            try {
                String prompt = buildNewReleasesPrompt(topArtists, topGenres, listeningHistory);

                HttpHeaders headers = new HttpHeaders();
                headers.setContentType(MediaType.APPLICATION_JSON);
                headers.setBearerAuth(groqConfig.getApiKey());

                Map<String, Object> body = new LinkedHashMap<>();
                body.put("model", groqConfig.getModel());
                body.put("messages", List.of(
                    Map.of("role", "system", "content",
                        "You are a music curator. Given a user's favorite artists and genres, recommend " +
                        "recent and popular songs they would enjoy. Return ONLY a JSON object with three keys: " +
                        "\"tier1\", \"tier2\", \"tier3\". Each key maps to a JSON array of 5 objects with " +
                        "'title' and 'artist' fields. No markdown, no explanation, just the JSON object."),
                    Map.of("role", "user", "content", prompt)
                ));
                body.put("temperature", 0.9);
                body.put("max_tokens", 3000);

                HttpEntity<Map<String, Object>> request = new HttpEntity<>(body, headers);

                ResponseEntity<String> response = restTemplate.exchange(
                    groqConfig.getApiUrl(), HttpMethod.POST, request, String.class);

                if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                    JsonNode json = objectMapper.readTree(response.getBody());
                    String content = json.get("choices").get(0).get("message").get("content").asText();

                    content = content.trim();
                    if (content.startsWith("```")) {
                        content = content.replaceAll("^```(json)?\\s*", "").replaceAll("\\s*```$", "");
                    }

                    JsonNode root = objectMapper.readTree(content);
                    Map<String, List<Map<String, String>>> result = new LinkedHashMap<>();

                    for (String tier : List.of("tier1", "tier2", "tier3")) {
                        List<Map<String, String>> songs = new ArrayList<>();
                        if (root.has(tier) && root.get(tier).isArray()) {
                            for (JsonNode song : root.get(tier)) {
                                Map<String, String> entry = new LinkedHashMap<>();
                                entry.put("title", song.get("title").asText());
                                entry.put("artist", song.get("artist").asText());
                                songs.add(entry);
                            }
                        }
                        result.put(tier, songs);
                        logger.info("Groq new releases: {} generated {} songs", tier, songs.size());
                    }
                    return result;
                }
            } catch (HttpClientErrorException.TooManyRequests e) {
                logger.warn("Groq rate limit hit for new releases (attempt {}/2), waiting 35s...", attempt);
                if (attempt == 1) {
                    try { Thread.sleep(35000); } catch (InterruptedException ie) { Thread.currentThread().interrupt(); }
                }
            } catch (Exception e) {
                logger.error("Groq new releases generation failed: {}", e.getMessage(), e);
                return Map.of();
            }
        }
        return Map.of();
    }

    /**
     * Generate a playlist from a free-form mood/request. Returns a map with
     * keys "title" (creative playlist name), "description" (one-sentence vibe),
     * and "songs" (list of {title, artist} maps). Includes optional web-search
     * context and the user's taste profile. Never throws — on failure it
     * returns an empty songs list so the caller can fall back.
     */
    public Map<String, Object> generatePlaylistFromMood(
            String mood, int size, String tasteContext, String webContext) {

        for (int attempt = 1; attempt <= 2; attempt++) {
            try {
                String prompt = buildMoodPrompt(mood, size, tasteContext, webContext);

                HttpHeaders headers = new HttpHeaders();
                headers.setContentType(MediaType.APPLICATION_JSON);
                headers.setBearerAuth(groqConfig.getApiKey());

                Map<String, Object> body = new LinkedHashMap<>();
                body.put("model", groqConfig.getModel());
                body.put("messages", List.of(
                    Map.of("role", "system", "content", getMoodSystemPrompt()),
                    Map.of("role", "user", "content", prompt)
                ));
                body.put("temperature", 0.9);
                body.put("max_tokens", Math.min(16000, size * 150 + 700));
                body.put("response_format", Map.of("type", "json_object"));

                HttpEntity<Map<String, Object>> request = new HttpEntity<>(body, headers);

                ResponseEntity<String> response = restTemplate.exchange(
                    groqConfig.getApiUrl(), HttpMethod.POST, request, String.class);

                if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                    JsonNode json = objectMapper.readTree(response.getBody());
                    String content = json.get("choices").get(0).get("message").get("content").asText();

                    content = content.trim();
                    if (content.startsWith("```")) {
                        content = content.replaceAll("^```(json)?\\s*", "").replaceAll("\\s*```$", "");
                    }

                    JsonNode root = objectMapper.readTree(content);
                    return parseMoodResponse(root, size, mood);
                }
            } catch (HttpClientErrorException.TooManyRequests e) {
                logger.warn("Groq rate limit hit (attempt {}/2), waiting 35s...", attempt);
                if (attempt == 1) {
                    try { Thread.sleep(35000); } catch (InterruptedException ie) { Thread.currentThread().interrupt(); }
                }
            } catch (Exception e) {
                logger.error("Groq mood playlist generation failed: {}", e.getMessage(), e);
                return Map.of("title", "", "description", "", "songs", List.of());
            }
        }
        return Map.of("title", "", "description", "", "songs", List.of());
    }

    private Map<String, Object> parseMoodResponse(JsonNode root, int size, String mood) {
        // Handle new format: {"title": "...", "description": "...", "songs": [...]}
        if (root.isObject() && root.has("songs") && root.get("songs").isArray()) {
            String title = root.has("title") ? root.get("title").asText("") : "";
            String description = root.has("description") ? root.get("description").asText("") : "";
            List<Map<String, String>> songs = parseSongArray(root.get("songs"), size);
            logger.info("Groq mood generation returned {} songs, title='{}' for '{}'", songs.size(), title, mood);
            return Map.of("title", title, "description", description, "songs", songs);
        }

        // Handle plain array format: [{...}, {...}, ...]
        if (root.isArray()) {
            List<Map<String, String>> songs = parseSongArray(root, size);
            logger.info("Groq mood generation returned {} songs (no title) for '{}'", songs.size(), mood);
            return Map.of("title", "", "description", "", "songs", songs);
        }

        // Tolerate {"songs": [...]} without title/description
        if (root.has("songs") && root.get("songs").isArray()) {
            List<Map<String, String>> songs = parseSongArray(root.get("songs"), size);
            return Map.of("title", "", "description", "", "songs", songs);
        }

        logger.warn("Groq mood response was not a valid JSON object: {}", root);
        return Map.of("title", "", "description", "", "songs", List.of());
    }

    private List<Map<String, String>> parseSongArray(JsonNode arrayNode, int maxSize) {
        List<Map<String, String>> songs = new ArrayList<>();
        for (JsonNode song : arrayNode) {
            if (!song.has("title") || !song.has("artist")) continue;
            Map<String, String> entry = new LinkedHashMap<>();
            entry.put("title", song.get("title").asText());
            entry.put("artist", song.get("artist").asText());
            songs.add(entry);
        }
        if (songs.size() > maxSize) {
            songs = songs.subList(0, maxSize);
        }
        return songs;
    }

    private String getMoodSystemPrompt() {
        return "You are a world-class music curator. The user gives you a playlist request.\n\n" +

            "RULES:\n" +
            "1. Follow the user's request LITERALLY. If they name a specific artist " +
            "(e.g. 'only The Weeknd songs'), EVERY song must be by that artist. " +
            "If they name a specific song or album, include it. If they name a mood " +
            "or feeling, pick songs that deliver that feeling.\n" +
            "2. Only pick songs that ACTUALLY EXIST. Use correct titles and artist names.\n" +
            "3. Mix well-known hits with deeper cuts. Don't just pick the most famous songs.\n" +
            "4. Do NOT invent songs or artists.\n" +
            "5. Create a cohesive emotional arc — songs flow into each other.\n\n" +

            "MOOD GUIDANCE (only when the request is about a feeling, not a specific artist):\n" +
            "- \"songs to help me sleep\" → CALM, SAFETY, WARMTH. Soft, slow, gentle tracks.\n" +
            "- \"late night drive\" → SOLITUDE, FREEDOM, ATMOSPHERE. Moody, synth-heavy.\n" +
            "- \"love songs\" → VULNERABILITY, INTIMACY, CONNECTION. Romantic, tender.\n" +
            "- \"hype workout\" → POWER, ADRENALINE, INVINCIBILITY. Aggressive, high energy.\n\n" +

            "OUTPUT — ONLY valid JSON, no markdown:\n" +
            "{\"title\": \"Short creative name for the playlist\", " +
            "\"description\": \"One sentence describing the playlist\", " +
            "\"songs\": [{\"title\": \"...\", \"artist\": \"...\"}, ...]}";
    }

    private String buildMoodPrompt(String mood, int size, String tasteContext, String webContext) {
        StringBuilder sb = new StringBuilder();
        sb.append("Create a playlist for: \"").append(mood).append("\"\n\n");
        sb.append("Desired duration: ~").append(size * 4).append(" minutes (").append(size).append(" songs)\n\n");

        if (isKhmerMusicRequest(mood)) {
            sb.append("HARD CONSTRAINT: This is a Khmer/Cambodian music request. Every song must be by a Khmer/Cambodian artist and must be Khmer music. ");
            sb.append("Do not include international songs, even if their mood or genre fits. Within that constraint, preserve every requested mood, situation, energy, era, and genre detail.\n\n");
        }

        if (tasteContext != null && !tasteContext.isBlank()) {
            sb.append(tasteContext).append("\n");
        }

        if (webContext != null && !webContext.isBlank()) {
            sb.append("Web context (current songs matching this request — use only if they fit):\n");
            sb.append(webContext).append("\n");
        }

        sb.append("\nFollow the request literally. If it names a specific artist, use only that artist's songs. ");
        sb.append("If it describes a feeling, pick songs that create that feeling.\n");
        sb.append("Return: {\"title\": \"...\", \"description\": \"...\", \"songs\": [{\"title\": \"...\", \"artist\": \"...\"}, ...]}");

        return sb.toString();
    }

    private boolean isKhmerMusicRequest(String mood) {
        if (mood == null || mood.isBlank()) return false;
        return mood.matches("(?s).*\\p{IsKhmer}.*")
                || mood.matches("(?is).*\\b(khmer|cambodian|cambodia)\\b.*");
    }

    private String buildNewReleasesPrompt(List<String> topArtists,
                                           List<String> topGenres,
                                           List<Map<String, Object>> listeningHistory) {
        StringBuilder sb = new StringBuilder();

        sb.append("My top artists: ").append(String.join(", ", topArtists)).append("\n");
        sb.append("My favorite genres: ").append(String.join(", ", topGenres)).append("\n\n");

        if (!listeningHistory.isEmpty()) {
            sb.append("Recent listening:\n");
            for (Map<String, Object> entry : listeningHistory) {
                String title = (String) entry.getOrDefault("title", "");
                String artist = (String) entry.getOrDefault("artist", "");
                boolean skipped = (boolean) entry.getOrDefault("skipped", false);
                boolean completed = (boolean) entry.getOrDefault("completed", false);
                boolean replayed = (boolean) entry.getOrDefault("replayed", false);

                sb.append("- \"").append(title).append("\" by ").append(artist);
                if (skipped) sb.append(" [SKIPPED]");
                else if (replayed) sb.append(" [REPLAYED]");
                else if (completed) sb.append(" [COMPLETED]");
                sb.append("\n");
            }
            sb.append("\n");
        }

        sb.append("Generate:\n");
        sb.append("- tier1: 5 recent/popular songs by my top artists\n");
        sb.append("- tier2: 5 songs by similar artists in my favorite genres\n");
        sb.append("- tier3: 5 trending/popular songs across all genres\n\n");
        sb.append("Return JSON: {\"tier1\": [{\"title\": \"...\", \"artist\": \"...\"}, ...], ");
        sb.append("\"tier2\": [{\"title\": \"...\", \"artist\": \"...\"}, ...], ");
        sb.append("\"tier3\": [{\"title\": \"...\", \"artist\": \"...\"}, ...]}");

        return sb.toString();
    }

    private String buildPrompt(List<String> genres,
                                Map<String, List<Map<String, Object>>> historyByGenre,
                                Map<String, List<String>> recommendMoreByGenre,
                                Map<String, List<String>> recommendLessByGenre) {
        StringBuilder sb = new StringBuilder();
        sb.append("Generate playlists of 20 songs for each genre: ");
        sb.append(String.join(", ", genres)).append(".\n\n");

        for (String genre : genres) {
            sb.append("--- ").append(genre).append(" ---\n");

            List<Map<String, Object>> history = historyByGenre.getOrDefault(genre, List.of());
            if (!history.isEmpty()) {
                sb.append("Recent listening history:\n");
                for (Map<String, Object> entry : history) {
                    String title = (String) entry.getOrDefault("title", "");
                    String artist = (String) entry.getOrDefault("artist", "");
                    boolean skipped = (boolean) entry.getOrDefault("skipped", false);
                    boolean completed = (boolean) entry.getOrDefault("completed", false);
                    boolean replayed = (boolean) entry.getOrDefault("replayed", false);

                    sb.append("- \"").append(title).append("\" by ").append(artist);
                    if (skipped) sb.append(" [SKIPPED]");
                    else if (replayed) sb.append(" [REPLAYED]");
                    else if (completed) sb.append(" [COMPLETED]");
                    sb.append("\n");
                }
                sb.append("\n");
            }

            List<String> more = recommendMoreByGenre.getOrDefault(genre, List.of());
            if (!more.isEmpty()) {
                sb.append("Wants MORE of: ").append(String.join(", ", more)).append("\n");
            }

            List<String> less = recommendLessByGenre.getOrDefault(genre, List.of());
            if (!less.isEmpty()) {
                sb.append("Wants LESS of: ").append(String.join(", ", less)).append("\n");
            }

            sb.append("\n");
        }

        sb.append("Return JSON: {\"").append(genres.get(0)).append("\": [{\"title\": \"...\", \"artist\": \"...\"}, ...]");
        for (int i = 1; i < genres.size(); i++) {
            sb.append(", \"").append(genres.get(i)).append("\": [{\"title\": \"...\", \"artist\": \"...\"}, ...]");
        }
        sb.append("}");
        return sb.toString();
    }
}
