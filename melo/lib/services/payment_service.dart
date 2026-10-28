import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class KhqrPaymentData {
  final String qrString;
  final String md5;
  final String billNumber;
  final double amount;
  final String currency;
  final String merchantName;
  final String bakongDeepLink;
  final String abaDeepLink;
  final String acledaDeepLink;
  final String wingDeepLink;
  final int expiresAtEpochMs;

  KhqrPaymentData({
    required this.qrString,
    required this.md5,
    required this.billNumber,
    required this.amount,
    required this.currency,
    required this.merchantName,
    required this.bakongDeepLink,
    required this.abaDeepLink,
    required this.acledaDeepLink,
    required this.wingDeepLink,
    required this.expiresAtEpochMs,
  });

  factory KhqrPaymentData.fromJson(Map<String, dynamic> json) {
    return KhqrPaymentData(
      qrString: json['qrString']?.toString() ?? '',
      md5: json['md5']?.toString() ?? '',
      billNumber: json['billNumber']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 2.99,
      currency: json['currency']?.toString() ?? 'USD',
      merchantName: json['merchantName']?.toString() ?? 'Melo Music',
      bakongDeepLink: json['bakongDeepLink']?.toString() ?? '',
      abaDeepLink: json['abaDeepLink']?.toString() ?? '',
      acledaDeepLink: json['acledaDeepLink']?.toString() ?? '',
      wingDeepLink: json['wingDeepLink']?.toString() ?? '',
      expiresAtEpochMs: (json['expiresAtEpochMs'] as num?)?.toInt() ??
          (DateTime.now().millisecondsSinceEpoch + 180000),
    );
  }
}

class PaymentService {
  static Future<String> _getBaseUrl() async {
    final host = await ApiConfig.baseUrl;
    return '$host/api/payment/khqr';
  }

  /// Generates dynamic KHQR payment data for monthly or yearly plans
  static Future<KhqrPaymentData?> generateKhqr({
    required String planType,
    double? amount,
    String currency = 'USD',
    String? userId,
  }) async {
    try {
      final base = await _getBaseUrl();
      final response = await http
          .post(
            Uri.parse('$base/generate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'planType': planType,
              'amount': amount,
              'currency': currency,
              'userId': userId,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        return KhqrPaymentData.fromJson(body);
      } else {
        debugPrint('Failed to generate KHQR: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error generating KHQR: $e');
    }
    return null;
  }

  /// Checks transaction status by MD5 hash with strict timeout and status parsing
  static Future<Map<String, dynamic>> checkPaymentStatus(String md5) async {
    try {
      final base = await _getBaseUrl();
      final response = await http
          .get(
            Uri.parse('$base/status?md5=$md5'),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final rawStatus = body['status']?.toString().toUpperCase() ?? 'PENDING';
        return {
          'status': rawStatus,
          'isSuccess': rawStatus == 'SUCCESS' || rawStatus == 'PAID',
          'checksRemaining': (body['checksRemaining'] as num?)?.toInt() ?? 0,
          'dailyRemaining': (body['dailyRemaining'] as num?)?.toInt() ?? 0,
          'message': body['message']?.toString() ?? '',
          'data': body['data'],
        };
      }
    } catch (e) {
      debugPrint('Error checking payment status: $e');
    }
    return {
      'status': 'PENDING',
      'isSuccess': false,
      'checksRemaining': 0,
      'dailyRemaining': 0,
      'message': 'Unable to connect to backend',
    };
  }
}
