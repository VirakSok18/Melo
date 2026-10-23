import 'dart:async';
import 'package:flutter/material.dart';

class CookieItem {
  final String message;
  final IconData? icon;
  final Color? iconColor;
  final Duration duration;

  const CookieItem({
    required this.message,
    this.icon,
    this.iconColor,
    this.duration = const Duration(seconds: 3),
  });
}

class CookieService extends ChangeNotifier {
  static final CookieService _instance = CookieService._internal();
  factory CookieService() => _instance;
  CookieService._internal();

  static CookieService get instance => _instance;

  CookieItem? _current;
  CookieItem? get current => _current;

  Timer? _timer;
  int _sequence = 0;
  int get sequence => _sequence;

  /// Display a top floating pill cookie notification across the app
  static void show({
    required String message,
    IconData? icon,
    Color? iconColor,
    Duration duration = const Duration(seconds: 3),
  }) {
    _instance._show(
      CookieItem(
        message: message,
        icon: icon,
        iconColor: iconColor,
        duration: duration,
      ),
    );
  }

  void _show(CookieItem item) {
    _timer?.cancel();
    _current = item;
    _sequence++;
    notifyListeners();

    _timer = Timer(item.duration, () {
      dismiss();
    });
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    _current = null;
    notifyListeners();
  }
}
