import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum PremiumPlanType {
  free,
  monthly,
  yearly,
}

class PremiumService extends ChangeNotifier {
  static final PremiumService _instance = PremiumService._internal();
  factory PremiumService() => _instance;
  PremiumService._internal() {
    _loadState();
  }

  static const String _keyPlan = 'melo_premium_plan';
  static const String _keyNextBilling = 'melo_premium_next_billing';
  static const String _keyCardLast4 = 'melo_premium_card_last4';
  static const String _keyCardBrand = 'melo_premium_card_brand';
  static const String _keyCardExpiry = 'melo_premium_card_expiry';
  static const String _keyCardHolder = 'melo_premium_card_holder';
  static const String _keyAutoRenew = 'melo_premium_auto_renew';
  static const String _keyAiGenerations = 'melo_ai_generations_count';
  static const String _keySkipTimestamps = 'melo_skip_timestamps';

  PremiumPlanType _plan = PremiumPlanType.yearly;
  DateTime? _nextBillingDate;
  String? _cardLast4;
  String? _cardBrand;
  String? _cardExpiry;
  String? _cardHolder;
  bool _autoRenew = true;
  bool _isLoaded = true;
  int _aiGenerationsCount = 0;
  List<int> _skipTimestamps = [];

  bool get isLoaded => _isLoaded;
  PremiumPlanType get plan => PremiumPlanType.yearly;
  bool get isPremium => true;

  bool get isYearly => true;
  bool get isMonthly => false;
  bool get isFree => false;
  bool get autoRenew => _autoRenew;
  bool get hasCard => _cardLast4 != null && _cardLast4!.isNotEmpty;
  DateTime? get nextBillingDate => _nextBillingDate;

  /// Debug helper for testing subscription expiry scenarios
  Future<void> debugSetNextBillingDate(DateTime date,
      {PremiumPlanType plan = PremiumPlanType.monthly}) async {
    _plan = plan;
    _nextBillingDate = date;
    _autoRenew = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyPlan, plan == PremiumPlanType.yearly ? 'yearly' : 'monthly');
    await prefs.setInt(_keyNextBilling, date.millisecondsSinceEpoch);
    await prefs.setBool(_keyAutoRenew, false);
    notifyListeners();
  }

  String get cardLast4 => _cardLast4 ?? '';
  String get cardBrand => _cardBrand ?? 'VISA';
  String get cardExpiry => _cardExpiry ?? '';
  String get cardHolder => _cardHolder ?? '';

  // Feature limits: fully free and unlimited
  int get aiGenerationsCount => _aiGenerationsCount;
  bool get canGenerateAiPlaylist => true;
  int get remainingAiTrials => 999;

  bool get canDownloadOffline => true;
  bool get canSyncListenAlong => true;

  int get skipsInLastHour => 0;

  bool get canSkipTrack => true;
  int get remainingHourlySkips => 999;

  /// Checks if an on-demand track switch is allowed:
  /// Fully free: Always returns true for unlimited on-demand playback and skips.
  bool checkAndConsumeTrackSwitch(
    BuildContext context, {
    String? newTitle,
    String? newArtist,
    String? newId,
  }) {
    return true;
  }

  String get planName => 'Pro Pass';

  String get planPrice => 'Free';

  String get billingPeriod => 'Unlimited';

  String get formattedNextBillingDate => 'Unlimited';

  Future<void> init() async {
    _plan = PremiumPlanType.yearly;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> _loadState() async {
    _plan = PremiumPlanType.yearly;
    _isLoaded = true;
    notifyListeners();
  }

  /// Syncs subscription state from Supabase when user logs in
  Future<void> fetchRemoteSubscription() async {
    // Melo is fully free
    _plan = PremiumPlanType.yearly;
    notifyListeners();
  }

  Future<void> _syncToSupabase() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final planStr = _plan == PremiumPlanType.yearly
          ? 'yearly'
          : (_plan == PremiumPlanType.monthly ? 'monthly' : 'free');

      await Supabase.instance.client.from('user_subscriptions').upsert({
        'user_id': user.id,
        'plan': planStr,
        'status': 'active',
        'card_brand': _cardBrand,
        'card_last4': _cardLast4,
        'card_expiry': _cardExpiry,
        'card_holder': _cardHolder,
        'next_billing_date': _nextBillingDate?.toIso8601String(),
        'auto_renew': _autoRenew,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id').timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[PremiumService] Error syncing subscription to Supabase: $e');
    }
  }

  Future<void> recordAiGeneration() async {
    _aiGenerationsCount++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAiGenerations, _aiGenerationsCount);
    notifyListeners();
  }

  Future<void> recordSkip() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - 3600000;
    _skipTimestamps = _skipTimestamps.where((t) => t >= cutoff).toList();
    _skipTimestamps.add(now);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _keySkipTimestamps,
      _skipTimestamps.map((e) => e.toString()).toList(),
    );
    notifyListeners();
  }

  Future<void> upgradeTo(
    PremiumPlanType newPlan, {
    required String cardBrand,
    required String cardLast4,
    required String cardExpiry,
    required String cardHolder,
  }) async {
    _plan = newPlan;
    final now = DateTime.now();

    final baseDate =
        (_nextBillingDate != null && _nextBillingDate!.isAfter(now))
            ? _nextBillingDate!
            : now;

    _nextBillingDate = newPlan == PremiumPlanType.yearly
        ? DateTime(baseDate.year + 1, baseDate.month, baseDate.day)
        : DateTime(baseDate.year, baseDate.month + 1, baseDate.day);
    _autoRenew = false;
    _cardBrand = cardBrand;
    _cardLast4 = cardLast4;
    _cardExpiry = cardExpiry;
    _cardHolder = cardHolder.toUpperCase().trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyPlan, newPlan == PremiumPlanType.yearly ? 'yearly' : 'monthly');
    await prefs.setInt(
        _keyNextBilling, _nextBillingDate!.millisecondsSinceEpoch);
    await prefs.setString(_keyCardBrand, _cardBrand!);
    await prefs.setString(_keyCardLast4, _cardLast4!);
    await prefs.setString(_keyCardExpiry, _cardExpiry!);
    await prefs.setString(_keyCardHolder, _cardHolder!);
    await prefs.setBool(_keyAutoRenew, true);

    notifyListeners();
    await _syncToSupabase();
  }

  Future<void> cancelSubscription() async {
    _autoRenew = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoRenew, false);
    notifyListeners();
    await _syncToSupabase();
  }

  Future<void> removeCard() async {
    _cardLast4 = null;
    _cardBrand = null;
    _cardExpiry = null;
    _cardHolder = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCardBrand);
    await prefs.remove(_keyCardLast4);
    await prefs.remove(_keyCardExpiry);
    await prefs.remove(_keyCardHolder);

    notifyListeners();
    await _syncToSupabase();
  }

  Future<void> toggleAutoRenew(bool value) async {
    _autoRenew = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoRenew, value);
    notifyListeners();
    await _syncToSupabase();
  }

  Future<void> updateCard({
    required String brand,
    required String last4,
    required String expiry,
    required String cardHolder,
  }) async {
    _cardBrand = brand;
    _cardLast4 = last4;
    _cardExpiry = expiry;
    _cardHolder = cardHolder.toUpperCase().trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCardBrand, _cardBrand!);
    await prefs.setString(_keyCardLast4, _cardLast4!);
    await prefs.setString(_keyCardExpiry, _cardExpiry!);
    await prefs.setString(_keyCardHolder, _cardHolder!);

    notifyListeners();
    await _syncToSupabase();
  }

  /// Clears local user premium state upon sign out
  Future<void> clearLocalState() async {
    _plan = PremiumPlanType.yearly;
    _nextBillingDate = null;
    _cardLast4 = null;
    _cardBrand = null;
    _cardExpiry = null;
    _cardHolder = null;
    _autoRenew = true;
    _aiGenerationsCount = 0;
    _skipTimestamps.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPlan);
    await prefs.remove(_keyNextBilling);
    await prefs.remove(_keyCardLast4);
    await prefs.remove(_keyCardBrand);
    await prefs.remove(_keyCardExpiry);
    await prefs.remove(_keyCardHolder);
    await prefs.remove(_keyAutoRenew);
    await prefs.remove(_keyAiGenerations);
    await prefs.remove(_keySkipTimestamps);

    notifyListeners();
  }

  /// Convenience method to show a compact premium upsell sheet
  static void showUpsell(BuildContext context,
      {String? reason, String? feature}) {
    // No-op: App is completely free with no payment blocks.
  }
}
