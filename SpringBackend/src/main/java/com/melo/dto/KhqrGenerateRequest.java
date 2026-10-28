package com.melo.dto;

import lombok.Data;

@Data
public class KhqrGenerateRequest {
    private String planType; // "monthly", "yearly", "custom"
    private Double amount;
    private String currency; // "USD" or "KHR"
    private String userId;
}

