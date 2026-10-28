package com.melo.repository;

import com.melo.model.SignupOtp;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.Optional;

@Repository
public interface SignupOtpRepository extends JpaRepository<SignupOtp, Long> {

    Optional<SignupOtp> findTopByEmailAndCodeAndUsedFalseAndExpiresAtAfterOrderByCreatedAtDesc(
            String email, String code, LocalDateTime now);

    @Modifying
    @Query("UPDATE SignupOtp o SET o.used = true WHERE o.email = :email AND o.used = false")
    void invalidateAllByEmail(String email);

    long countByEmailAndCreatedAtAfter(String email, LocalDateTime since);
}
