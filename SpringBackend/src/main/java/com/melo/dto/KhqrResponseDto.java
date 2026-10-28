package com.melo.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class KhqrResponseDto {
    private String qrString;
    private String md5;
    private String billNumber;
    private Double amount;
    private String currency;
    private String merchantName;
    private String bakongDeepLink;
    private String abaDeepLink;
    private String acledaDeepLink;
    private String wingDeepLink;
    private Long expiresAtEpochMs;
}

