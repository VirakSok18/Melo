package com.melo.service;

import com.melo.config.SupabaseConfig;
import com.melo.model.SignupOtp;
import com.melo.repository.SignupOtpRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import jakarta.mail.MessagingException;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.Random;

@Service
public class OtpService {

    private static final Logger logger = LoggerFactory.getLogger(OtpService.class);

    @Autowired
    private SignupOtpRepository otpRepository;

    @Autowired
    private EmailService emailService;

    @Autowired
    private SupabaseConfig supabaseConfig;

    private static final int OTP_EXPIRY_MINUTES = 10;
    private static final int MAX_OTPS_PER_HOUR = 3;

    @Transactional
    public void sendSignupOtp(String email) throws MessagingException {
        // Rate limit: max 3 OTPs per hour
        LocalDateTime oneHourAgo = LocalDateTime.now().minusHours(1);
        long recentCount = otpRepository.countByEmailAndCreatedAtAfter(email, oneHourAgo);
        if (recentCount >= MAX_OTPS_PER_HOUR) {
            throw new RuntimeException("Too many requests. Please try again later.");
        }

        // Invalidate any previous unused OTPs for this email
        otpRepository.invalidateAllByEmail(email);

        // Generate 6-digit OTP
        String otp = String.format("%06d", new Random().nextInt(999999));

        // Store OTP with expiry
        SignupOtp signupOtp = new SignupOtp(email, otp, LocalDateTime.now().plusMinutes(OTP_EXPIRY_MINUTES));
        otpRepository.save(signupOtp);

        // Send email
        emailService.sendVerificationEmail(email, otp);
    }

    public boolean verifySignupOtp(String email, String code) {
        return otpRepository
                .findTopByEmailAndCodeAndUsedFalseAndExpiresAtAfterOrderByCreatedAtDesc(
                        email, code, LocalDateTime.now())
                .isPresent();
    }

    @Transactional
    public void sendPasswordResetOtp(String email) throws MessagingException {
        // Rate limit: max 3 OTPs per hour
        LocalDateTime oneHourAgo = LocalDateTime.now().minusHours(1);
        long recentCount = otpRepository.countByEmailAndCreatedAtAfter(email, oneHourAgo);
        if (recentCount >= MAX_OTPS_PER_HOUR) {
            throw new RuntimeException("Too many requests. Please try again later.");
        }

        // Invalidate any previous unused OTPs for this email
        otpRepository.invalidateAllByEmail(email);

        // Generate 6-digit OTP
        String otp = String.format("%06d", new Random().nextInt(999999));

        // Store OTP with expiry
        SignupOtp signupOtp = new SignupOtp(email, otp, LocalDateTime.now().plusMinutes(OTP_EXPIRY_MINUTES));
        otpRepository.save(signupOtp);

        // Send password reset email
        emailService.sendPasswordResetEmail(email, otp);
    }

    public boolean verifyPasswordResetOtp(String email, String code) {
        return otpRepository
                .findTopByEmailAndCodeAndUsedFalseAndExpiresAtAfterOrderByCreatedAtDesc(
                        email, code, LocalDateTime.now())
                .isPresent();
    }

    @Transactional
    public boolean resetPassword(String email, String code, String newPassword) {
        Optional<SignupOtp> otpOpt = otpRepository
                .findTopByEmailAndCodeAndUsedFalseAndExpiresAtAfterOrderByCreatedAtDesc(
                        email, code, LocalDateTime.now());

        if (otpOpt.isEmpty()) {
            return false;
        }

        // Call Supabase RPC to update password
        try {
            String rpcUrl = supabaseConfig.getSupabaseUrl() + "/rest/v1/rpc/reset_user_password";
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("apikey", supabaseConfig.getSupabaseAnonKey());
            headers.set("Authorization", "Bearer " + supabaseConfig.getSupabaseAnonKey());

            Map<String, String> body = new HashMap<>();
            body.put("user_email", email.trim().toLowerCase());
            body.put("new_password", newPassword);

            HttpEntity<Map<String, String>> request = new HttpEntity<>(body, headers);
            ResponseEntity<String> response = supabaseConfig.supabaseRestTemplate().postForEntity(rpcUrl, request, String.class);

            if (response.getStatusCode().is2xxSuccessful() && !"false".equalsIgnoreCase(response.getBody())) {
                // Mark OTP as used
                SignupOtp otp = otpOpt.get();
                otp.setUsed(true);
                otpRepository.save(otp);
                return true;
            } else {
                logger.error("Supabase password reset RPC returned false for {}", email);
                return false;
            }
        } catch (Exception e) {
            logger.error("Error executing Supabase password reset RPC for {}: {}", email, e.getMessage(), e);
            throw new RuntimeException("Failed to update password in database: " + e.getMessage());
        }
    }
}
