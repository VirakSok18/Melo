import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Authentication service for Melo
/// Sends real verification codes via melonoreply@gmail.com through Vercel HTTPS Relay
/// and verifies OTPs reliably without hitting Supabase free-tier email rate limits.
class ApiService {
  static const String _relayUrl = 'https://melo-pi-one.vercel.app/api/send-email';
  static const String _supabaseUrl = 'https://movymmlayggqzjtunlfk.supabase.co';
  static const String _supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1vdnltbWxheWdncXpqdHVubGZrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMxNjY1MDYsImV4cCI6MjEwODc0MjUwNn0.wnYGxn8vr3EvMMVe__qeTrurkLmCP2-5UsqKA9y9tLw';
  static const String _meloSecret = 'melo_secret_otp_relay_2026';

  static Map<String, String> get _supabaseHeaders => {
        'apikey': _supabaseAnonKey,
        'Authorization': 'Bearer $_supabaseAnonKey',
        'Content-Type': 'application/json',
      };

  /// Generates a random 6-digit code, stores it in Supabase, and emails it from melonoreply@gmail.com
  static Future<Map<String, dynamic>> sendOtp(String email) async {
    try {
      final cleanEmail = email.trim().toLowerCase();
      final code = (100000 + Random().nextInt(900000)).toString();
      final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 10)).toIso8601String();

      // 1. Invalidate any previous unused OTPs
      try {
        await http.patch(
          Uri.parse('$_supabaseUrl/rest/v1/signup_otps?email=eq.${Uri.encodeComponent(cleanEmail)}&is_used=eq.false'),
          headers: _supabaseHeaders,
          body: jsonEncode({'is_used': true}),
        );
      } catch (_) {}

      // 2. Insert new OTP
      final insertRes = await http.post(
        Uri.parse('$_supabaseUrl/rest/v1/signup_otps'),
        headers: _supabaseHeaders,
        body: jsonEncode({
          'email': cleanEmail,
          'code': code,
          'expires_at': expiresAt,
          'is_used': false,
        }),
      );

      if (insertRes.statusCode >= 400) {
        debugPrint('Failed to store OTP in Supabase: ${insertRes.body}');
      }

      // 3. Send email from melonoreply@gmail.com via Vercel Relay
      final html = '''
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #121212; color: #ffffff; padding: 40px 20px; text-align: center;">
          <h1 style="color: #514AED; margin-bottom: 4px; font-size: 32px; font-weight: 800; letter-spacing: -0.5px;">Melo</h1>
          <p style="color: #a0a0a0; font-size: 14px; margin-top: 0;">Your Personal Soundscape</p>
          <div style="background-color: #1a1a1a; border-radius: 16px; padding: 32px 24px; margin: 28px auto; max-width: 440px; border: 1px solid #2a2a2a; box-shadow: 0 10px 30px rgba(0,0,0,0.5);">
            <h2 style="color: #ffffff; font-size: 20px; margin-top: 0;">Verify Your Melo Account</h2>
            <p style="font-size: 15px; color: #e0e0e0; margin-bottom: 24px; line-height: 1.5;">Welcome to Melo! Use this verification code to complete your registration:</p>
            <div style="font-size: 38px; font-weight: 800; letter-spacing: 10px; color: #514AED; padding: 18px 24px; background: rgba(81, 74, 237, 0.12); border: 1px solid rgba(81, 74, 237, 0.3); border-radius: 12px; display: inline-block;">
              $code
            </div>
            <p style="color: #777777; font-size: 13px; margin-top: 24px; line-height: 1.5;">This code will expire in 10 minutes.<br/>If you did not request this, you can safely ignore this email.</p>
          </div>
          <p style="color: #555555; font-size: 12px; margin-top: 24px;">© 2026 Melo Music. All rights reserved.</p>
        </div>
      ''';

      final relayRes = await http.post(
        Uri.parse(_relayUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-melo-secret': _meloSecret,
        },
        body: jsonEncode({
          'secret': _meloSecret,
          'to': cleanEmail,
          'subject': 'Your Melo Verification Code: $code',
          'html': html,
          'text': 'Your Melo verification code is: $code. It expires in 10 minutes.',
        }),
      );

      if (relayRes.statusCode == 200) {
        return {'success': true, 'message': 'Verification code sent to $email'};
      } else {
        debugPrint('Relay failed: ${relayRes.body}');
        return {'success': false, 'message': 'Failed to send email. Please try again.'};
      }
    } catch (e) {
      debugPrint('sendOtp error: $e');
      return {'success': false, 'message': 'Network error. Please try again.'};
    }
  }

  /// Verifies the OTP from Supabase table signup_otps
  static Future<Map<String, dynamic>> verifyOtp(String email, String code) async {
    try {
      final cleanEmail = email.trim().toLowerCase();
      final cleanCode = code.trim();

      final res = await http.get(
        Uri.parse(
          '$_supabaseUrl/rest/v1/signup_otps?email=eq.${Uri.encodeComponent(cleanEmail)}&code=eq.${Uri.encodeComponent(cleanCode)}&is_used=eq.false&select=*&order=created_at.desc&limit=1',
        ),
        headers: _supabaseHeaders,
      );

      if (res.statusCode != 200) {
        return {'success': false, 'message': 'Error validating code'};
      }

      final List list = jsonDecode(res.body);
      if (list.isEmpty) {
        return {'success': false, 'message': 'Invalid verification code'};
      }

      final record = list[0];
      final expiresAt = DateTime.parse(record['expires_at']);
      if (DateTime.now().toUtc().isAfter(expiresAt)) {
        return {'success': false, 'message': 'Verification code has expired'};
      }

      // Mark used
      await http.patch(
        Uri.parse('$_supabaseUrl/rest/v1/signup_otps?id=eq.${record['id']}'),
        headers: _supabaseHeaders,
        body: jsonEncode({'is_used': true}),
      );

      return {'success': true, 'message': 'Verification successful'};
    } catch (e) {
      debugPrint('verifyOtp error: $e');
      return {'success': false, 'message': 'Verification error. Please try again.'};
    }
  }

  /// Sends password reset OTP from melonoreply@gmail.com
  static Future<Map<String, dynamic>> sendForgotPasswordOtp(String email) async {
    try {
      final cleanEmail = email.trim().toLowerCase();
      final code = (100000 + Random().nextInt(900000)).toString();
      final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 10)).toIso8601String();

      // 1. Invalidate previous
      try {
        await http.patch(
          Uri.parse('$_supabaseUrl/rest/v1/signup_otps?email=eq.${Uri.encodeComponent(cleanEmail)}&is_used=eq.false'),
          headers: _supabaseHeaders,
          body: jsonEncode({'is_used': true}),
        );
      } catch (_) {}

      // 2. Insert new
      await http.post(
        Uri.parse('$_supabaseUrl/rest/v1/signup_otps'),
        headers: _supabaseHeaders,
        body: jsonEncode({
          'email': cleanEmail,
          'code': code,
          'expires_at': expiresAt,
          'is_used': false,
        }),
      );

      // 3. Dispatch Email
      final html = '''
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #121212; color: #ffffff; padding: 40px 20px; text-align: center;">
          <h1 style="color: #514AED; margin-bottom: 4px; font-size: 32px; font-weight: 800; letter-spacing: -0.5px;">Melo</h1>
          <p style="color: #a0a0a0; font-size: 14px; margin-top: 0;">Password Reset</p>
          <div style="background-color: #1a1a1a; border-radius: 16px; padding: 32px 24px; margin: 28px auto; max-width: 440px; border: 1px solid #2a2a2a; box-shadow: 0 10px 30px rgba(0,0,0,0.5);">
            <h2 style="color: #ffffff; font-size: 20px; margin-top: 0;">Reset Your Password</h2>
            <p style="font-size: 15px; color: #e0e0e0; margin-bottom: 24px; line-height: 1.5;">We received a request to reset your Melo account password. Use this code to continue:</p>
            <div style="font-size: 38px; font-weight: 800; letter-spacing: 10px; color: #514AED; padding: 18px 24px; background: rgba(81, 74, 237, 0.12); border: 1px solid rgba(81, 74, 237, 0.3); border-radius: 12px; display: inline-block;">
              $code
            </div>
            <p style="color: #777777; font-size: 13px; margin-top: 24px; line-height: 1.5;">This code will expire in 10 minutes.<br/>If you did not request this, you can safely ignore this email.</p>
          </div>
          <p style="color: #555555; font-size: 12px; margin-top: 24px;">© 2026 Melo Music. All rights reserved.</p>
        </div>
      ''';

      final relayRes = await http.post(
        Uri.parse(_relayUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-melo-secret': _meloSecret,
        },
        body: jsonEncode({
          'secret': _meloSecret,
          'to': cleanEmail,
          'subject': 'Your Melo Password Reset Code: $code',
          'html': html,
          'text': 'Your Melo password reset code is: $code. It expires in 10 minutes.',
        }),
      );

      if (relayRes.statusCode == 200) {
        return {'success': true, 'message': 'Reset code sent to $email'};
      } else {
        return {'success': false, 'message': 'Failed to send reset email.'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error. Please try again.'};
    }
  }

  /// Verifies password reset OTP
  static Future<Map<String, dynamic>> verifyForgotPasswordOtp(String email, String code) async {
    return await verifyOtp(email, code);
  }

  /// Updates user password via Supabase Auth
  static Future<Map<String, dynamic>> resetPassword(
      String email, String code, String newPassword) async {
    try {
      final verifyRes = await verifyOtp(email, code);
      if (verifyRes['success'] != true) {
        return verifyRes;
      }

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      return {'success': true, 'message': 'Password updated successfully'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to update password'};
    }
  }
}
