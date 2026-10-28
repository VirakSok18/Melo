package com.melo.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

@Configuration
public class DeezerConfig {

    public static final String API_BASE = "https://api.deezer.com";
    public static final String GW_BASE = "https://www.deezer.com/ajax/gw-light.php";
    public static final String MEDIA_BASE = "https://media.deezer.com/v1";

    @Value("${deezer.arl:}")
    private String arl;

    public String getArl() {
        return arl;
    }

    @Bean("deezerRestTemplate")
    public RestTemplate deezerRestTemplate() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(10000);
        factory.setReadTimeout(10000);
        return new RestTemplate(factory);
    }

    @Bean("deezerPrivateRestTemplate")
    public RestTemplate deezerPrivateRestTemplate() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(10000);
        factory.setReadTimeout(15000);
        return new RestTemplate(factory);
    }
}
