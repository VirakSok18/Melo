import 'dart:async';

class ApiConfig {
  /// App is now fully frontend-based and zero-backend dependent.
  static const String productionUrl = '';

  static Future<String> get baseUrl async => '';

  static String get baseUrlSync => '';

  /// Backend is not needed or probed.
  static Future<bool> get isReachable async => false;

  static Future<void> refreshHost() async {}

  static void startAutoRefresh(
      {Duration interval = const Duration(seconds: 20)}) {}

  static void stopAutoRefresh() {}

  static void reset() {}
}
