import 'package:flutter/material.dart';
import 'premium_service.dart';
import 'deep_link_service.dart';
import '../view/ad_screen/ad_player_screen.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  int _songsCompletedSinceLastAd = 0;
  static const int songsInterval = 4; // Triggers every 4 completed songs
  bool _isAdShowing = false;

  int get songsCompletedSinceLastAd => _songsCompletedSinceLastAd;
  bool get isAdShowing => _isAdShowing;

  bool get willShowAdNext =>
      !PremiumService().isPremium &&
      (_songsCompletedSinceLastAd + 1 >= songsInterval) &&
      (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  /// Call whenever a song completes playback
  /// Returns true if an ad was displayed, false otherwise.
  Future<bool> onSongCompleted({BuildContext? context}) async {
    // Premium users never get ads
    if (PremiumService().isPremium) {
      _songsCompletedSinceLastAd = 0;
      return false;
    }

    // Never show video ads when app is in background or phone is locked!
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      debugPrint(
          '[AdService] App is in background ($lifecycle) -> skipping ad to keep music playing seamlessly');
      return false;
    }

    _songsCompletedSinceLastAd++;
    debugPrint(
        '[AdService] Songs completed since last ad: $_songsCompletedSinceLastAd / $songsInterval');

    if (_songsCompletedSinceLastAd >= songsInterval) {
      _songsCompletedSinceLastAd = 0;
      return await showAd(context: context);
    }

    return false;
  }

  /// Manually show the video ad break
  Future<bool> showAd({BuildContext? context}) async {
    if (_isAdShowing) return false;
    if (PremiumService().isPremium) return false;

    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }

    final targetContext =
        context ?? DeepLinkService().navigatorKey.currentContext;
    if (targetContext == null) {
      debugPrint('[AdService] No valid BuildContext to show ad');
      return false;
    }

    _isAdShowing = true;
    try {
      await AdPlayerScreen.show(targetContext);
      return true;
    } catch (e) {
      debugPrint('[AdService] Error presenting ad player: $e');
      return false;
    } finally {
      _isAdShowing = false;
    }
  }

  /// Reset counter (e.g., when user upgrades)
  void reset() {
    _songsCompletedSinceLastAd = 0;
  }
}
