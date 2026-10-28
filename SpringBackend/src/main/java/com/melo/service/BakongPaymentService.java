package com.melo.service;

import com.melo.config.BakongConfig;
import com.melo.dto.KhqrGenerateRequest;
import com.melo.dto.KhqrResponseDto;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.text.DecimalFormat;
import java.text.DecimalFormatSymbols;
import java.time.LocalDate;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

@Slf4j
@Service
@RequiredArgsConstructor
public class BakongPaymentService {

    public static final int DAILY_QUOTA_MAX = 90; // NBC limit is 100/day; strict safety cap at 90
    public static final int MAX_CHECKS_PER_MD5 = 4; // Carma schedule: exactly 4 checks (20s, 45s, 80s, 130s)

    private final BakongConfig bakongConfig;
    private final RestTemplate restTemplate = new RestTemplate();

    private final AtomicInteger dailyChecksCount = new AtomicInteger(0);
    private volatile LocalDate currentQuotaDate = LocalDate.now();
    private final Map<String, AtomicInteger> md5CheckCounts = new ConcurrentHashMap<>();
    private final Map<String, Map<String, Object>> paidTransactions = new ConcurrentHashMap<>();

    /**
     * Generates a standard EMVCo-compliant dynamic KHQR payload string and calculates its MD5.
     * Expiration set to 130 seconds to match the strict 4-check schedule.
     */
    public KhqrResponseDto generateKhqr(KhqrGenerateRequest request) {
        double amount = "yearly".equalsIgnoreCase(request.getPlanType()) ? 24.99 : 2.99;
        if (request.getAmount() != null && request.getAmount() > 0) {
            amount = request.getAmount();
        }

        String currency = "USD";
        String currencyCode = "840"; // ISO 4217 for USD
        if ("KHR".equalsIgnoreCase(request.getCurrency())) {
            currency = "KHR";
            currencyCode = "116"; // ISO 4217 for KHR
        }

        String billNumber = "MELO" + System.currentTimeMillis() % 10000000;
        String accountId = bakongConfig.getAccountId();
        String merchantName = bakongConfig.getMerchantName();
        String merchantCity = bakongConfig.getMerchantCity();

        // Build EMVCo TLV structure for KHQR
        StringBuilder sb = new StringBuilder();
        appendTlv(sb, "00", "01"); // Payload Format Indicator
        appendTlv(sb, "01", "12"); // Point of Initiation Method (12 = Dynamic with Amount)

        // Tag 29: KHQR solo/individual merchant account information.
        StringBuilder tag29 = new StringBuilder();
        appendTlv(tag29, "00", accountId);
        appendTlv(sb, "29", tag29.toString());

        appendTlv(sb, "52", "5999"); // Merchant Category Code (5999 = General / Individual)
        appendTlv(sb, "53", currencyCode); // Transaction Currency

        DecimalFormatSymbols symbols = new DecimalFormatSymbols(Locale.US);
        DecimalFormat df = "KHR".equals(currency) ? new DecimalFormat("#", symbols) : new DecimalFormat("0.00", symbols);
        String formattedAmount = df.format(amount);
        appendTlv(sb, "54", formattedAmount); // Transaction Amount

        appendTlv(sb, "58", "KH"); // Country Code
        appendTlv(sb, "59", merchantName); // Merchant Name
        appendTlv(sb, "60", merchantCity); // Merchant City

        // Tag 62: Additional Data Field (Sub-tag 01: Bill / Reference Number)
        StringBuilder tag62 = new StringBuilder();
        appendTlv(tag62, "01", billNumber); // Bill Number
        appendTlv(sb, "62", tag62.toString());

        // Tag 99: Timestamp and Expiration Template
        long nowEpochMs = System.currentTimeMillis();
        long expEpochMs = nowEpochMs + (130L * 1000L); // Exactly 130s expiry
        StringBuilder tag99 = new StringBuilder();
        appendTlv(tag99, "00", String.valueOf(nowEpochMs));
        appendTlv(tag99, "01", String.valueOf(expEpochMs));
        appendTlv(sb, "99", tag99.toString());

        // Tag 63: CRC16 Checksum
        sb.append("6304");
        String crc = calculateCrc16(sb.toString());
        String fullKhqrString = sb.toString() + crc;

        // Calculate MD5 hash of the complete KHQR string
        String md5 = calculateMd5(fullKhqrString);

        // Deep links for 1-tap payment from mobile phone
        String encodedKhqr = URLEncoder.encode(fullKhqrString, StandardCharsets.UTF_8);
        String bakongDeepLink = "bakong://qr?data=" + encodedKhqr;
        String abaDeepLink = "aba://qr?data=" + encodedKhqr;
        String acledaDeepLink = "acledamobile://qr?data=" + encodedKhqr;
        String wingDeepLink = "wingmoney://qr?data=" + encodedKhqr;

        long expiresAt = System.currentTimeMillis() + (130 * 1000); // 130 seconds validity

        log.info("Generated KHQR: bill={}, amount={}, md5={}, expires in 130s", billNumber, formattedAmount, md5);

        return KhqrResponseDto.builder()
                .qrString(fullKhqrString)
                .md5(md5)
                .billNumber(billNumber)
                .amount(amount)
                .currency(currency)
                .merchantName(merchantName)
                .bakongDeepLink(bakongDeepLink)
                .abaDeepLink(abaDeepLink)
                .acledaDeepLink(acledaDeepLink)
                .wingDeepLink(wingDeepLink)
                .expiresAtEpochMs(expiresAt)
                .build();
    }

    /**
     * Checks if the transaction has been completed via Bakong Open API.
     * Enforces strict Carma-style rate limiting: max 4 checks per QR and 90 checks/day global ceiling.
     */
    public Map<String, Object> checkTransactionStatus(String md5) {
        Map<String, Object> result = new HashMap<>();

        if (md5 == null || md5.trim().isEmpty()) {
            result.put("status", "FAILED");
            result.put("message", "Invalid MD5 reference");
            return result;
        }

        String cleanMd5 = md5.trim();

        // 1. Reset daily quota if calendar day rolled over
        LocalDate today = LocalDate.now();
        if (today.isAfter(currentQuotaDate)) {
            synchronized (this) {
                if (today.isAfter(currentQuotaDate)) {
                    log.info("Resetting daily Bakong check quota for new day: {}", today);
                    dailyChecksCount.set(0);
                    md5CheckCounts.clear();
                    currentQuotaDate = today;
                }
            }
        }

        // 2. Check in-memory verified cache (from webhooks or prior successful verification)
        // Once verified, return SUCCESS with 0 NBC calls forever!
        if (paidTransactions.containsKey(cleanMd5)) {
            Map<String, Object> cached = new HashMap<>(paidTransactions.get(cleanMd5));
            cached.put("checksRemaining", 0);
            cached.put("dailyRemaining", Math.max(0, DAILY_QUOTA_MAX - dailyChecksCount.get()));
            return cached;
        }

        // 3. Enforce per-MD5 check limit (strict max 4 checks)
        AtomicInteger checkCounter = md5CheckCounts.computeIfAbsent(cleanMd5, k -> new AtomicInteger(0));
        if (checkCounter.get() >= MAX_CHECKS_PER_MD5) {
            log.warn("MD5 {} reached maximum allowed checks ({}/{}). Refusing further calls to protect quota.",
                    cleanMd5, checkCounter.get(), MAX_CHECKS_PER_MD5);
            result.put("status", "LIMIT_REACHED");
            result.put("message", "Maximum 4 verification checks reached for this QR code");
            result.put("checksRemaining", 0);
            result.put("dailyRemaining", Math.max(0, DAILY_QUOTA_MAX - dailyChecksCount.get()));
            return result;
        }

        // 4. Enforce daily server-wide quota ceiling (90 checks max)
        if (dailyChecksCount.get() >= DAILY_QUOTA_MAX) {
            log.warn("Daily Bakong quota ceiling reached ({}/{}). Halting checks to protect integration.",
                    dailyChecksCount.get(), DAILY_QUOTA_MAX);
            result.put("status", "QUOTA_EXCEEDED");
            result.put("message", "Daily payment verification quota reached (90/day). Please retry tomorrow.");
            result.put("checksRemaining", 0);
            result.put("dailyRemaining", 0);
            return result;
        }

        String token = bakongConfig.getToken();
        if (token == null || token.trim().isEmpty()) {
            result.put("status", "PENDING");
            result.put("message", "Awaiting Bakong verification token");
            result.put("md5", cleanMd5);
            return result;
        }

        // Increment quota and check counters
        int currentCheck = checkCounter.incrementAndGet();
        int currentDaily = dailyChecksCount.incrementAndGet();
        log.info("Checking Bakong payment for MD5: {} (Check {}/{}, Daily {}/{})",
                cleanMd5, currentCheck, MAX_CHECKS_PER_MD5, currentDaily, DAILY_QUOTA_MAX);

        try {
            String checkUrl = bakongConfig.getApiUrl() + "/check_transaction_by_md5";
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.setBearerAuth(token);

            Map<String, String> body = Map.of("md5", cleanMd5);
            HttpEntity<Map<String, String>> requestEntity = new HttpEntity<>(body, headers);

            ResponseEntity<Map> response = restTemplate.postForEntity(checkUrl, requestEntity, Map.class);
            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                Map responseBody = response.getBody();
                Object responseCode = responseBody.get("responseCode");
                Object dataObj = responseBody.get("data");

                // NBC returns responseCode 0 when payment has arrived
                boolean isSuccess = responseCode != null &&
                        ("0".equals(responseCode.toString()) || Integer.valueOf(0).equals(responseCode));

                if (isSuccess && dataObj != null) {
                    result.put("status", "SUCCESS");
                    result.put("data", dataObj);
                    result.put("message", "Payment verified successfully");
                    result.put("checksRemaining", 0);
                    result.put("dailyRemaining", Math.max(0, DAILY_QUOTA_MAX - dailyChecksCount.get()));
                    paidTransactions.put(cleanMd5, result);
                    log.info("Payment confirmed SUCCESS for MD5: {}", cleanMd5);
                    return result;
                }
            }

            result.put("status", "PENDING");
            result.put("message", "Payment pending");
            result.put("checksRemaining", Math.max(0, MAX_CHECKS_PER_MD5 - currentCheck));
            result.put("dailyRemaining", Math.max(0, DAILY_QUOTA_MAX - dailyChecksCount.get()));
        } catch (Exception e) {
            log.warn("Bakong status check error for md5 {}: {}", cleanMd5, e.getMessage());
            result.put("status", "PENDING");
            result.put("message", "Payment pending: " + e.getMessage());
            result.put("checksRemaining", Math.max(0, MAX_CHECKS_PER_MD5 - currentCheck));
            result.put("dailyRemaining", Math.max(0, DAILY_QUOTA_MAX - dailyChecksCount.get()));
        }

        return result;
    }

    /**
     * Processes incoming instant payment webhooks from Bakong Relay or Payment Gateways.
     */
    public Map<String, Object> processWebhook(Map<String, Object> payload) {
        log.info("Received Bakong payment webhook: {}", payload);
        Map<String, Object> response = new HashMap<>();

        if (payload == null || payload.isEmpty()) {
            response.put("status", "IGNORED");
            response.put("message", "Empty payload");
            return response;
        }

        String md5 = null;
        if (payload.containsKey("md5")) {
            md5 = String.valueOf(payload.get("md5"));
        } else if (payload.containsKey("hash")) {
            md5 = String.valueOf(payload.get("hash"));
        } else if (payload.get("data") instanceof Map<?, ?> dataMap) {
            if (dataMap.containsKey("md5")) {
                md5 = String.valueOf(dataMap.get("md5"));
            } else if (dataMap.containsKey("hash")) {
                md5 = String.valueOf(dataMap.get("hash"));
            }
        }

        if (md5 != null && !md5.trim().isEmpty()) {
            String cleanMd5 = md5.trim();
            Map<String, Object> successResult = new HashMap<>();
            successResult.put("status", "SUCCESS");
            successResult.put("data", payload);
            successResult.put("message", "Payment verified via instant webhook");
            paidTransactions.put(cleanMd5, successResult);

            response.put("status", "PROCESSED");
            response.put("md5", cleanMd5);
            log.info("Successfully recorded instant webhook payment for MD5: {}", cleanMd5);
            return response;
        }

        response.put("status", "ACKNOWLEDGED");
        return response;
    }

    public int getDailyChecksCount() {
        return dailyChecksCount.get();
    }

    public int getDailyQuotaRemaining() {
        return Math.max(0, DAILY_QUOTA_MAX - dailyChecksCount.get());
    }

    private void appendTlv(StringBuilder sb, String tag, String value) {
        if (value == null) return;
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        String len = String.format("%02d", bytes.length);
        sb.append(tag).append(len).append(value);
    }

    private String calculateCrc16(String input) {
        int crc = 0xFFFF;
        int polynomial = 0x1021;
        byte[] bytes = input.getBytes(StandardCharsets.UTF_8);

        for (byte b : bytes) {
            for (int i = 0; i < 8; i++) {
                boolean bit = ((b >> (7 - i)) & 1) == 1;
                boolean c15 = ((crc >> 15) & 1) == 1;
                crc <<= 1;
                if (c15 ^ bit) crc ^= polynomial;
            }
        }
        crc &= 0xFFFF;
        return String.format("%04X", crc);
    }

    private String calculateMd5(String input) {
        try {
            MessageDigest md = MessageDigest.getInstance("MD5");
            byte[] digest = md.digest(input.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (byte b : digest) {
                sb.append(String.format("%02x", b));
            }
            return sb.toString();
        } catch (Exception e) {
            return UUID.randomUUID().toString().replace("-", "");
        }
    }
}
