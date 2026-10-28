import 'dart:async';

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
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency']?.toString() ?? 'USD',
      merchantName: json['merchantName']?.toString() ?? 'Melo Music',
      bakongDeepLink: json['bakongDeepLink']?.toString() ?? '',
      abaDeepLink: json['abaDeepLink']?.toString() ?? '',
      acledaDeepLink: json['acledaDeepLink']?.toString() ?? '',
      wingDeepLink: json['wingDeepLink']?.toString() ?? '',
      expiresAtEpochMs: (json['expiresAtEpochMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class PaymentService {
  /// App is now fully free. Payment endpoints are disabled.
  static Future<KhqrPaymentData?> generateKhqr({
    required String planType,
    double? amount,
    String currency = 'USD',
    String? userId,
  }) async {
    return null;
  }

  static Future<Map<String, dynamic>> checkPaymentStatus(String md5) async {
    return {
      'status': 'SUCCESS',
      'isSuccess': true,
      'checksRemaining': 0,
      'dailyRemaining': 0,
      'message': 'All features are free to use.',
      'data': null,
    };
  }
}
