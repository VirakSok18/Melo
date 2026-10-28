package com.melo.security;

import jakarta.servlet.*;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Slf4j
@Component
public class RateLimitFilter implements Filter {

    // Store request counts: key -> [count, windowStartTimeMs]
    private final Map<String, RequestCounter> requestCounts = new ConcurrentHashMap<>();

    // Limits
    private static final int AUTH_LIMIT = 5; // Max 5 requests
    private static final long AUTH_WINDOW_MS = 15 * 60 * 1000; // per 15 minutes

    private static final int PAYMENT_LIMIT = 45; // Max 45 requests
    private static final long PAYMENT_WINDOW_MS = 60 * 1000; // per minute (polling allowance)

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {

        if (request instanceof HttpServletRequest httpRequest && response instanceof HttpServletResponse httpResponse) {
            String path = httpRequest.getRequestURI();
            String clientIp = getClientIp(httpRequest);

            if (path.startsWith("/api/auth/")) {
                String key = "AUTH:" + clientIp;
                if (!isAllowed(key, AUTH_LIMIT, AUTH_WINDOW_MS)) {
                    log.warn("Rate limit exceeded for IP {} on path {}", clientIp, path);
                    httpResponse.setStatus(429);
                    httpResponse.setContentType("application/json");
                    httpResponse.getWriter().write("{\"success\":false,\"message\":\"Too many attempts. Please wait 15 minutes before trying again.\"}");
                    return;
                }
            } else if (path.startsWith("/api/payment/")) {
                String key = "PAYMENT:" + clientIp;
                if (!isAllowed(key, PAYMENT_LIMIT, PAYMENT_WINDOW_MS)) {
                    log.warn("Payment rate limit exceeded for IP {}", clientIp);
                    httpResponse.setStatus(429);
                    httpResponse.setContentType("application/json");
                    httpResponse.getWriter().write("{\"status\":\"FAILED\",\"message\":\"Too many requests. Please slow down.\"}");
                    return;
                }
            }
        }

        chain.doFilter(request, response);
    }

    private boolean isAllowed(String key, int maxRequests, long windowMs) {
        long now = System.currentTimeMillis();
        RequestCounter counter = requestCounts.compute(key, (k, existing) -> {
            if (existing == null || (now - existing.startTime) > windowMs) {
                return new RequestCounter(1, now);
            }
            existing.count++;
            return existing;
        });

        return counter.count <= maxRequests;
    }

    private String getClientIp(HttpServletRequest request) {
        String xForwardedFor = request.getHeader("X-Forwarded-For");
        if (xForwardedFor != null && !xForwardedFor.isEmpty()) {
            return xForwardedFor.split(",")[0].trim();
        }
        return request.getRemoteAddr() != null ? request.getRemoteAddr() : "unknown";
    }

    private static class RequestCounter {
        int count;
        long startTime;

        RequestCounter(int count, long startTime) {
            this.count = count;
            this.startTime = startTime;
        }
    }
}

