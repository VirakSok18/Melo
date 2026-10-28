import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PremiumPlanType {
  free,
  monthly,
  yearly,
}

/// PremiumService: All features are now completely free and unlocked.
/// No paywalls, no subscription gates, no limits.
/// Includes client-side rate limiting to prevent spam abuse.
class PremiumService extends ChangeNotifier {
  static final PremiumService _instance = PremiumService._internal();
  factory PremiumService() => _instance;
  PremiumService._internal() {
    _loadState();
  }

  static const String _keyAiGenerations = 'melo_ai_generations_count';

  PremiumPlanType _plan = PremiumPlanType.yearly;
  bool _isLoaded = true;
  int _aiGenerationsCount = 0;
  DateTime? _lastAiGenerationTime;

  bool get isLoaded => _isLoaded;
  PremiumPlanType get plan => _plan;

  /// All users have full free Premium access
  bool get isPremium => true;
  bool get isYearly => true;
  bool get isMonthly => false;
  bool get isFree => false;
  bool get autoRenew => false;
  bool get hasCard => false;
  DateTime? get nextBillingDate => null;

  Future<void> debugSetNextBillingDate(DateTime date,
      {PremiumPlanType plan = PremiumPlanType.monthly}) async {}

  String get cardLast4 => '';
  String get cardBrand => '';
  String get cardExpiry => '';
  String get cardHolder => '';

  // Feature limits: completely unlocked and free
  int get aiGenerationsCount => _aiGenerationsCount;
  bool get canGenerateAiPlaylist => true;
  int get remainingAiTrials => 999;

  bool get canDownloadOffline => true;
  bool get canSyncListenAlong => true;

  int get skipsInLastHour => 0;
  bool get canSkipTrack => true;
  int get remainingHourlySkips => 999;

  /// Anti-spam protection: ensures rapid consecutive clicks do not overwhelm the system
  bool canTriggerAiGeneration() {
    final now = DateTime.now();
    if (_lastAiGenerationTime != null &&
        now.difference(_lastAiGenerationTime!) < const Duration(seconds: 4)) {
      return false;
    }
    return true;
  }

  /// On-demand track switch is always permitted for free
  bool checkAndConsumeTrackSwitch(
    BuildContext context, {
    String? newTitle,
    String? newArtist,
    String? newId,
  }) {
    return true;
  }

  String get planName => 'Pro (Free Access)';
  String get planPrice => 'Free';
  String get billingPeriod => 'Unlimited Lifetime Access';
  String get formattedNextBillingDate => 'Lifetime';

  Future<void> init() async {
    await _loadState();
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _aiGenerationsCount = prefs.getInt(_keyAiGenerations) ?? 0;
    } catch (_) {}
    _plan = PremiumPlanType.yearly;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> fetchRemoteSubscription() async {
    // App is free — no remote billing checks needed
  }

  Future<void> recordAiGeneration() async {
    _lastAiGenerationTime = DateTime.now();
    _aiGenerationsCount++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyAiGenerations, _aiGenerationsCount);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> recordSkip() async {
    // Unlimited skips allowed
  }

  Future<void> upgradeTo(
    PremiumPlanType newPlan, {
    required String cardBrand,
    required String cardLast4,
    required String cardExpiry,
    required String cardHolder,
  }) async {
    notifyListeners();
  }

  Future<void> cancelSubscription() async {
    notifyListeners();
  }

  Future<void> removeCard() async {
    notifyListeners();
  }

  Future<void> toggleAutoRenew(bool value) async {
    notifyListeners();
  }

  Future<void> updateCard({
    required String brand,
    required String last4,
    required String expiry,
    required String cardHolder,
  }) async {
    notifyListeners();
  }

  Future<void> clearLocalState() async {
    _aiGenerationsCount = 0;
    _lastAiGenerationTime = null;
    notifyListeners();
  }

  /// Paywall upsell is disabled: Melo is 100% free
  static void showUpsell(BuildContext context,
      {String? reason, String? feature}) {
    // No-op: all features are free and unlocked
  }
}
