package com.melo.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Data
@Configuration
@ConfigurationProperties(prefix = "bakong")
public class BakongConfig {
    private String accountId = "virak_sok@bkrt";
    private String merchantName = "Melo Music";
    private String merchantCity = "Phnom Penh";
    private String acquiringBank = "Bakong";
    private String accountInformation = "855962205999";
    private String apiUrl = "https://api-bakong.nbc.gov.kh/v1";
    private String token = "";
}

