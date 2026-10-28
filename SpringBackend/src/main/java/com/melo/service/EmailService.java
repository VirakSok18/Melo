package com.melo.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Service;

import jakarta.mail.MessagingException;
import jakarta.mail.internet.MimeMessage;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Map;

@Service
public class EmailService {

    private static final Logger logger = LoggerFactory.getLogger(EmailService.class);
    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Autowired(required = false)
    private JavaMailSender mailSender;

    @Value("${email.relay-url:${EMAIL_RELAY_URL:https://melo-pi.vercel.app/api/send-email}}")
    private String emailRelayUrl;

    @Value("${email.relay-secret:${EMAIL_RELAY_SECRET:melo_secret_otp_relay_2026}}")
    private String emailRelaySecret;

    public void sendVerificationEmail(String email, String otp) throws MessagingException {
        logger.info("[OTP] Generated verification code for {}: {}", email, otp);

        String htmlContent = """
            <div style="font-family: Arial, sans-serif; max-width: 600px; margin: auto; padding: 20px; border: 1px solid #eee; border-radius: 10px;">
                <h2 style="color: #514AED; text-align: center;">Verify Your Account</h2>
                <p>Hello,</p>
                <p>Welcome to Melo! Use the code below to verify your email address and complete your registration. This code will expire in 10 minutes.</p>
                <div style="text-align: center; margin: 30px 0;">
                    <span style="font-size: 32px; font-weight: bold; letter-spacing: 5px; color: #514AED; background: #f9f9f9; padding: 10px 20px; border-radius: 5px; border: 1px dashed #514AED;">
                        %s
                    </span>
                </div>
                <p>If you didn't attempt to sign up, you can safely ignore this email.</p>
                <p>Stay tuned,<br>The Melo Team</p>
            </div>
            """.formatted(otp);

        // 1. Try Vercel HTTPS Email Relay (runs via Gmail melonoreply@gmail.com without SMTP blocks)
        if (emailRelayUrl != null && !emailRelayUrl.isBlank()) {
            try {
                sendViaRelay(email, "Melo Account Verification Code", htmlContent);
                return;
            } catch (Exception e) {
                logger.error("Failed to send verification email via Vercel Relay to {}: {}", email, e.getMessage());
            }
        }

        // 2. Fallback to JavaMail if local SMTP port 587 is available
        if (mailSender != null) {
            try {
                MimeMessage message = mailSender.createMimeMessage();
                MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");

                helper.setTo(email);
                helper.setSubject("Melo Account Verification Code");
                helper.setFrom("Melo <melonoreply@gmail.com>");
                helper.setText(htmlContent, true);
                mailSender.send(message);
                logger.info("Sent verification email via local JavaMail to {}", email);
            } catch (Exception e) {
                logger.error("JavaMail fallback also failed for {}: {}", email, e.getMessage());
            }
        }
    }

    public void sendPasswordResetEmail(String email, String otp) throws MessagingException {
        logger.info("[OTP] Generated password reset code for {}: {}", email, otp);

        String htmlContent = """
            <div style="font-family: Arial, sans-serif; max-width: 600px; margin: auto; padding: 20px; border: 1px solid #eee; border-radius: 10px;">
                <h2 style="color: #514AED; text-align: center;">Reset Your Password</h2>
                <p>Hello,</p>
                <p>We received a request to reset your Melo account password. Use the verification code below to set a new password. This code will expire in 10 minutes.</p>
                <div style="text-align: center; margin: 30px 0;">
                    <span style="font-size: 32px; font-weight: bold; letter-spacing: 5px; color: #514AED; background: #f9f9f9; padding: 10px 20px; border-radius: 5px; border: 1px dashed #514AED;">
                        %s
                    </span>
                </div>
                <p>If you didn't request a password reset, you can safely ignore this email. Your password will remain unchanged.</p>
                <p>Stay tuned,<br>The Melo Team</p>
            </div>
            """.formatted(otp);

        // 1. Try Vercel HTTPS Email Relay
        if (emailRelayUrl != null && !emailRelayUrl.isBlank()) {
            try {
                sendViaRelay(email, "Melo Password Reset Code", htmlContent);
                return;
            } catch (Exception e) {
                logger.error("Failed to send password reset email via Vercel Relay to {}: {}", email, e.getMessage());
            }
        }

        // 2. Fallback to JavaMail if available
        if (mailSender != null) {
            try {
                MimeMessage message = mailSender.createMimeMessage();
                MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");

                helper.setTo(email);
                helper.setSubject("Melo Password Reset Code");
                helper.setFrom("Melo <melonoreply@gmail.com>");
                helper.setText(htmlContent, true);
                mailSender.send(message);
                logger.info("Sent password reset email via local JavaMail to {}", email);
            } catch (Exception e) {
                logger.error("JavaMail fallback also failed for {}: {}", email, e.getMessage());
            }
        }
    }

    private void sendViaRelay(String email, String subject, String htmlContent) throws Exception {
        Map<String, Object> payload = Map.of(
                "secret", emailRelaySecret,
                "to", email,
                "subject", subject,
                "html", htmlContent,
                "text", "Your Melo verification code is in this email."
        );

        String json = objectMapper.writeValueAsString(payload);

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(emailRelayUrl.trim()))
                .header("Content-Type", "application/json")
                .header("x-melo-secret", emailRelaySecret)
                .timeout(Duration.ofSeconds(12))
                .POST(HttpRequest.BodyPublishers.ofString(json, StandardCharsets.UTF_8))
                .build();

        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() >= 200 && response.statusCode() < 300) {
            logger.info("Successfully sent email via Vercel Gmail Relay to {}", email);
        } else {
            throw new RuntimeException("Email Relay returned status " + response.statusCode() + ": " + response.body());
        }
    }
}
