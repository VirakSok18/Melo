import 'package:flutter/material.dart';

/// AdService: Melo is completely ad-free.
class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  int get songsCompletedSinceLastAd => 0;
  bool get isAdShowing => false;
  bool get willShowAdNext => false;

  /// Ad breaks are completely disabled
  Future<bool> onSongCompleted({BuildContext? context}) async {
    return false;
  }

  Future<bool> showAd({BuildContext? context}) async {
    return false;
  }

  void reset() {}
}
