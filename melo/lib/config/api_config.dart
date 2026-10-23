import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  /// Set via --dart-define=BACKEND_URL=https://your-backend.com
  static const String productionUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: '',
  );

  static const int _port = 8080;
  static const Duration _timeout = Duration(seconds: 2);

  static const List<String> _hosts = [
    '10.0.2.2', // Android Emulator
    'localhost', // Local development
  ];

  static const String _prefsHostKey = 'api_resolved_host';

  static String? _resolvedHost;
  static Timer? _autoRefreshTimer;

  static Future<String> get baseUrl async {
    if (productionUrl.isNotEmpty) return productionUrl;
    // Use the in-memory (or last-known persisted) host immediately so we never
    // block app startup on a slow multi-host probe — this matters offline.
    if (_resolvedHost == null) {
      final prefs = await SharedPreferences.getInstance();
      _resolvedHost = prefs.getString(_prefsHostKey);
    }
    if (_resolvedHost == null) {
      await refreshHost();
    }
    final host = _resolvedHost ?? _hosts.first;
    return 'http://$host:$_port';
  }

  static String get baseUrlSync {
    if (productionUrl.isNotEmpty) return productionUrl;
    return 'http://${_resolvedHost ?? _hosts.first}:$_port';
  }

  /// Probes all candidate hosts in parallel and returns the first one that
  /// accepts a connection, or null if none are reachable right now.
  static Future<String?> _probeHost() async {
    final results = await Future.wait(
      _hosts.map((host) async {
        try {
          final socket = await Socket.connect(host, _port, timeout: _timeout);
          socket.destroy();
          return host;
        } catch (_) {
          return null;
        }
      }),
    );
    for (final host in results) {
      if (host != null) return host;
    }
    return null;
  }

  /// True if backend is reachable.
  static Future<bool> get isReachable async {
    if (productionUrl.isNotEmpty) return true;
    return (await _probeHost()) != null;
  }

  /// Re-probes the hosts and updates the persisted host to whichever is
  /// currently reachable, so the app follows the phone between networks (WiFi
  /// vs hotspot). If nothing is reachable right now, keeps the current host —
  /// a known host beats losing one that may come back later.
  static Future<void> refreshHost() async {
    if (productionUrl.isNotEmpty) return;
    final detected = await _probeHost();
    if (detected == null || detected == _resolvedHost) return;
    _resolvedHost = detected;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsHostKey, detected);
    } catch (_) {}
  }

  /// Periodically re-probes so a network switch while the app is running is
  /// picked up automatically. Cheap: 3 parallel sockets, near-instant when a
  /// host is reachable, ~2s worst case when none are.
  static void startAutoRefresh(
      {Duration interval = const Duration(seconds: 20)}) {
    if (productionUrl.isNotEmpty) return;
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(interval, (_) => refreshHost());
  }

  static void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  static void reset() {
    _resolvedHost = null;
  }
}
