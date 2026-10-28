package com.melo;

import com.melo.config.BakongConfig;
import com.melo.dto.KhqrGenerateRequest;
import com.melo.dto.KhqrResponseDto;
import com.melo.service.BakongPaymentService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class BakongPaymentServiceTest {

    private BakongConfig bakongConfig;
    private BakongPaymentService paymentService;

    @BeforeEach
    void setUp() {
        bakongConfig = new BakongConfig();
        bakongConfig.setAccountId("virak_sok@bkrt");
        bakongConfig.setMerchantName("Melo Music");
        bakongConfig.setMerchantCity("Phnom Penh");
        bakongConfig.setToken(""); // Empty token so external network call is not made in unit test
        paymentService = new BakongPaymentService(bakongConfig);
    }

    @Test
    void testGenerateKhqrHas130SecondsExpiry() {
        KhqrGenerateRequest request = new KhqrGenerateRequest();
        request.setPlanType("monthly");
        request.setAmount(2.99);
        request.setCurrency("USD");

        long before = System.currentTimeMillis();
        KhqrResponseDto response = paymentService.generateKhqr(request);
        long after = System.currentTimeMillis();

        assertNotNull(response);
        assertNotNull(response.getMd5());
        assertEquals(32, response.getMd5().length());

        // Expiry should be approx 130 seconds from now
        long expectedMin = before + 129 * 1000L;
        long expectedMax = after + 131 * 1000L;
        assertTrue(response.getExpiresAtEpochMs() >= expectedMin && response.getExpiresAtEpochMs() <= expectedMax,
                "Expiry epoch should be 130s in the future");
    }

    @Test
    void testStrict4ChecksPerMd5Cap() {
        String testMd5 = "test_md5_hash_1234567890abcdef";

        // Without token, checkTransactionStatus returns PENDING awaiting token,
        // but still consumes MD5 checks if token is set. Let's test with a fake token.
        bakongConfig.setToken("dummy_token");

        // Checks 1, 2, 3, 4
        for (int i = 1; i <= 4; i++) {
            Map<String, Object> res = paymentService.checkTransactionStatus(testMd5);
            assertNotEquals("LIMIT_REACHED", res.get("status"), "Check " + i + " should not be limit reached");
            assertEquals(4 - i, res.get("checksRemaining"), "Checks remaining should decrease");
        }

        // 5th check must be rejected immediately to protect NBC quota
        Map<String, Object> res5 = paymentService.checkTransactionStatus(testMd5);
        assertEquals("LIMIT_REACHED", res5.get("status"), "5th check must return LIMIT_REACHED");
        assertEquals(0, res5.get("checksRemaining"));
    }

    @Test
    void testWebhookSuccessCachesImmediately() {
        String testMd5 = "test_paid_md5_hash_success";

        // Simulate instant webhook / verified payment
        paymentService.processWebhook(Map.of("md5", testMd5, "status", "PAID"));

        // Subsequent check must return SUCCESS with 0 checks consumed
        Map<String, Object> statusRes = paymentService.checkTransactionStatus(testMd5);
        assertEquals("SUCCESS", statusRes.get("status"));
        assertEquals(0, statusRes.get("checksRemaining"));
    }
}

