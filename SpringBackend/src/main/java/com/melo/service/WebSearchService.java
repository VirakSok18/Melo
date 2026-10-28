package com.melo.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.melo.config.TavilyConfig;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.net.URI;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class WebSearchService {

    private static final Logger logger = LoggerFactory.getLogger(WebSearchService.class);

    @Autowired
    private TavilyConfig tavilyConfig;

    private final RestTemplate restTemplate = new RestTemplate();
    private final ObjectMapper objectMapper = new ObjectMapper();

    private static class CacheEntry {
        final List<String> snippets;
        final Instant expiresAt;

        CacheEntry(List<String> snippets, Instant expiresAt) {
            this.snippets = snippets;
            this.expiresAt = expiresAt;
        }
    }

    private final Map<String, CacheEntry> cache = new ConcurrentHashMap<>();

    /**
     * Search the web for context about a mood/request. Returns a flat list of
     * plain-text snippets (title + content). Never throws — on any failure it
     * returns an empty list so the caller can fall back to Groq-from-memory.
     */
    public List<String> search(String query) {
        if (query == null || query.isBlank()) {
            return List.of();
        }

        String key = query.trim().toLowerCase();
        CacheEntry cached = cache.get(key);
        if (cached != null && cached.expiresAt.isAfter(Instant.now())) {
            logger.info("Tavily cache hit for '{}' ({} snippets)", query, cached.snippets.size());
            return cached.snippets;
        }

        try {
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("api_key", tavilyConfig.getApiKey());
            body.put("query", query);
            body.put("search_depth", "basic");
            body.put("max_results", 8);
            body.put("include_answer", false);

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);

            HttpEntity<Map<String, Object>> request = new HttpEntity<>(body, headers);

            ResponseEntity<String> response = restTemplate.exchange(
                URI.create(tavilyConfig.getApiUrl()), HttpMethod.POST, request, String.class);

            List<String> snippets = new ArrayList<>();

            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                JsonNode json = objectMapper.readTree(response.getBody());
                JsonNode results = json.get("results");
                if (results != null && results.isArray()) {
                    for (JsonNode item : results) {
                        String title = item.has("title") ? item.get("title").asText() : "";
                        String content = item.has("content") ? item.get("content").asText() : "";
                        if (title.isBlank() && content.isBlank()) continue;
                        snippets.add((title.isBlank() ? "" : title) + " " + content.trim());
                    }
                }
            }

            if (!snippets.isEmpty()) {
                long ttlMs = Math.max(1, tavilyConfig.getCacheTtlHours()) * 3600_000L;
                cache.put(key, new CacheEntry(snippets, Instant.now().plusMillis(ttlMs)));
                logger.info("Tavily search '{}' returned {} snippets (cached for {}h)",
                        query, snippets.size(), tavilyConfig.getCacheTtlHours());
            } else {
                logger.warn("Tavily search '{}' returned no results", query);
            }

            return snippets;

        } catch (Exception e) {
            logger.warn("Tavily search failed for '{}': {}", query, e.getMessage());
            return List.of();
        }
    }
}