package com.melo.controller;

import com.melo.dto.KhqrGenerateRequest;
import com.melo.dto.KhqrResponseDto;
import com.melo.service.BakongPaymentService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@Slf4j
@RestController
@RequestMapping("/api/payment/khqr")
@RequiredArgsConstructor
@CrossOrigin(origins = "*")
public class PaymentController {

    private final BakongPaymentService paymentService;

    /**
     * Generate dynamic KHQR code with amount and deep links.
     */
    @PostMapping("/generate")
    public ResponseEntity<?> generateKhqr(@RequestBody KhqrGenerateRequest request) {
        if (request == null) {
            return ResponseEntity.badRequest().body(Map.of("status", "FAILED", "message", "Request body is required"));
        }
        if (request.getAmount() != null && (request.getAmount() < 0.01 || request.getAmount() > 5000.0)) {
            return ResponseEntity.badRequest().body(Map.of("status", "FAILED", "message", "Amount must be between $0.01 and $5000.00"));
        }
        KhqrResponseDto response = paymentService.generateKhqr(request);
        return ResponseEntity.ok(response);
    }

    /**
     * Check transaction status by MD5.
     */
    @GetMapping("/status")
    public ResponseEntity<Map<String, Object>> checkStatus(@RequestParam(required = false) String md5) {
        if (md5 == null || md5.trim().isEmpty() || md5.length() > 64) {
            return ResponseEntity.badRequest().body(Map.of("status", "FAILED", "message", "Invalid MD5 reference"));
        }
        Map<String, Object> status = paymentService.checkTransactionStatus(md5.trim());
        return ResponseEntity.ok(status);
    }

    /**
     * Webhook endpoint for instant payment callbacks (Railway, Bakong Relay, Gateways).
     */
    @PostMapping("/webhook")
    public ResponseEntity<Map<String, Object>> handleWebhook(@RequestBody(required = false) Map<String, Object> payload) {
        Map<String, Object> result = paymentService.processWebhook(payload != null ? payload : Map.of());
        return ResponseEntity.ok(result);
    }

    /**
     * Quota inspection endpoint.
     */
    @GetMapping("/quota")
    public ResponseEntity<Map<String, Object>> getQuota() {
        return ResponseEntity.ok(Map.of(
                "dailyChecksCount", paymentService.getDailyChecksCount(),
                "dailyQuotaRemaining", paymentService.getDailyQuotaRemaining(),
                "dailyQuotaMax", BakongPaymentService.DAILY_QUOTA_MAX,
                "maxChecksPerMd5", BakongPaymentService.MAX_CHECKS_PER_MD5
        ));
    }
}

