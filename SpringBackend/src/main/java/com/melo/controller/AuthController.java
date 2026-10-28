package com.melo.controller;

import com.melo.dto.ApiResponse;
import com.melo.dto.ResetPasswordRequest;
import com.melo.dto.SendOtpRequest;
import com.melo.dto.VerifyOtpRequest;
import com.melo.service.OtpService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.regex.Pattern;

@RestController
@RequestMapping("/api/auth")
@CrossOrigin(origins = "*")
public class AuthController {

    private static final Logger logger = LoggerFactory.getLogger(AuthController.class);
    private static final Pattern EMAIL_PATTERN = Pattern.compile("^[A-Za-z0-9+_.-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,6}$");

    @Autowired
    private OtpService otpService;

    private String sanitizeEmail(String email) {
        if (email == null) return "";
        return email.trim().toLowerCase();
    }

    private boolean isValidEmail(String email) {
        return email != null && email.length() <= 100 && EMAIL_PATTERN.matcher(email).matches();
    }

    private boolean isValidOtpCode(String code) {
        return code != null && code.trim().length() == 6 && code.trim().matches("\\d{6}");
    }

    @PostMapping("/signup/send-otp")
    public ResponseEntity<ApiResponse> sendOtp(@RequestBody SendOtpRequest request) {
        String email = sanitizeEmail(request.getEmail());
        if (!isValidEmail(email)) {
            return ResponseEntity.badRequest().body(ApiResponse.error("Valid email address is required (max 100 characters)"));
        }

        try {
            otpService.sendSignupOtp(email);
            return ResponseEntity.ok(ApiResponse.ok("Verification code sent to your email"));
        } catch (RuntimeException e) {
            logger.error("Send OTP failed for {}: {}", email, e.getMessage());
            return ResponseEntity.status(429).body(ApiResponse.error(e.getMessage()));
        } catch (Exception e) {
            logger.error("Send OTP error for {}: {}", email, e.getMessage(), e);
            return ResponseEntity.internalServerError().body(ApiResponse.error("Failed to send verification email"));
        }
    }

    @PostMapping("/signup/verify-otp")
    public ResponseEntity<ApiResponse> verifyOtp(@RequestBody VerifyOtpRequest request) {
        String email = sanitizeEmail(request.getEmail());
        String code = request.getCode() != null ? request.getCode().trim() : "";

        if (!isValidEmail(email) || !isValidOtpCode(code)) {
            return ResponseEntity.badRequest().body(ApiResponse.error("Valid email and 6-digit code are required"));
        }

        boolean verified = otpService.verifySignupOtp(email, code);
        if (verified) {
            return ResponseEntity.ok(ApiResponse.ok("Email verified successfully"));
        } else {
            return ResponseEntity.badRequest().body(ApiResponse.error("Invalid or expired verification code"));
        }
    }

    @PostMapping("/forgot-password/send-otp")
    public ResponseEntity<ApiResponse> sendForgotPasswordOtp(@RequestBody SendOtpRequest request) {
        String email = sanitizeEmail(request.getEmail());
        if (!isValidEmail(email)) {
            return ResponseEntity.badRequest().body(ApiResponse.error("Valid email address is required"));
        }

        try {
            otpService.sendPasswordResetOtp(email);
            return ResponseEntity.ok(ApiResponse.ok("Password reset code sent to your email"));
        } catch (RuntimeException e) {
            logger.error("Send reset OTP failed for {}: {}", email, e.getMessage());
            return ResponseEntity.status(429).body(ApiResponse.error(e.getMessage()));
        } catch (Exception e) {
            logger.error("Send reset OTP error for {}: {}", email, e.getMessage(), e);
            return ResponseEntity.internalServerError().body(ApiResponse.error("Failed to send reset code"));
        }
    }

    @PostMapping("/forgot-password/verify-otp")
    public ResponseEntity<ApiResponse> verifyForgotPasswordOtp(@RequestBody VerifyOtpRequest request) {
        String email = sanitizeEmail(request.getEmail());
        String code = request.getCode() != null ? request.getCode().trim() : "";

        if (!isValidEmail(email) || !isValidOtpCode(code)) {
            return ResponseEntity.badRequest().body(ApiResponse.error("Valid email and 6-digit code are required"));
        }

        boolean verified = otpService.verifyPasswordResetOtp(email, code);
        if (verified) {
            return ResponseEntity.ok(ApiResponse.ok("Code verified successfully"));
        } else {
            return ResponseEntity.badRequest().body(ApiResponse.error("Invalid or expired verification code"));
        }
    }

    @PostMapping("/forgot-password/reset-password")
    public ResponseEntity<ApiResponse> resetPassword(@RequestBody ResetPasswordRequest request) {
        String email = sanitizeEmail(request.getEmail());
        String code = request.getCode() != null ? request.getCode().trim() : "";
        String newPassword = request.getNewPassword();

        if (!isValidEmail(email) || !isValidOtpCode(code)) {
            return ResponseEntity.badRequest().body(ApiResponse.error("Valid email and 6-digit code are required"));
        }
        if (newPassword == null || newPassword.length() < 6 || newPassword.length() > 128) {
            return ResponseEntity.badRequest().body(ApiResponse.error("New password must be between 6 and 128 characters"));
        }

        try {
            boolean success = otpService.resetPassword(email, code, newPassword);
            if (success) {
                return ResponseEntity.ok(ApiResponse.ok("Password reset successfully"));
            } else {
                return ResponseEntity.badRequest().body(ApiResponse.error("Invalid or expired verification code"));
            }
        } catch (Exception e) {
            logger.error("Password reset error for {}: {}", email, e.getMessage(), e);
            return ResponseEntity.internalServerError().body(ApiResponse.error("Failed to reset password"));
        }
    }
}
