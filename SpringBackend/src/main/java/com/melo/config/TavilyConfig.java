package com.melo.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;

@Configuration
public class TavilyConfig {

    @Value("${tavily.api-key}")
    private String apiKey;

    @Value("${tavily.api-url:https://api.tavily.com/search}")
    private String apiUrl;

    @Value("${tavily.cache-ttl-hours:24}")
    private long cacheTtlHours;

    public String getApiKey() { return apiKey; }
    public String getApiUrl() { return apiUrl; }
    public long getCacheTtlHours() { return cacheTtlHours; }
}