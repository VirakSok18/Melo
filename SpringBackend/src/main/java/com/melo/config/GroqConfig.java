package com.melo.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;

@Configuration
public class GroqConfig {

    @Value("${groq.api-key}")
    private String apiKey;

    @Value("${groq.model}")
    private String model;

    @Value("${groq.api-url}")
    private String apiUrl;

    public String getApiKey() { return apiKey; }
    public String getModel() { return model; }
    public String getApiUrl() { return apiUrl; }
}
