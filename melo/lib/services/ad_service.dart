import 'package:flutter/material.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  int _songsCompletedSinceLastAd = 0;
  static const int songsInterval = 4;

  int get songsCompletedSinceLastAd => _songsCompletedSinceLastAd;
  bool get isAdShowing => false;

  // Fully free: no ads ever
  bool get willShowAdNext => false;

  /// Call whenever a song completes playback - no ads
  Future<bool> onSongCompleted({BuildContext? context}) async {
    _songsCompletedSinceLastAd = 0;
    return false;
  }

  /// Manually show the video ad break - disabled
  Future<bool> showAd({BuildContext? context}) async {
    return false;
  }

  /// Reset counter
  void reset() {
    _songsCompletedSinceLastAd = 0;
  }
}
