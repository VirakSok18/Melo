import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ApiService {
  static String get baseUrl => '${ApiConfig.baseUrlSync}/api/auth';

  static Future<Map<String, dynamic>> sendOtp(String email) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/signup/send-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 10));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> verifyOtp(
      String email, String code) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/signup/verify-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'code': code}),
        )
        .timeout(const Duration(seconds: 10));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> sendForgotPasswordOtp(
      String email) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/forgot-password/send-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 10));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> verifyForgotPasswordOtp(
      String email, String code) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/forgot-password/verify-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'code': code}),
        )
        .timeout(const Duration(seconds: 10));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> resetPassword(
      String email, String code, String newPassword) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/forgot-password/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(
              {'email': email, 'code': code, 'newPassword': newPassword}),
        )
        .timeout(const Duration(seconds: 10));
    return jsonDecode(response.body);
  }
}
