import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../view/premium_screen/premium_upsell_sheet.dart';
import 'playback_service.dart';

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

  PremiumPlanType _plan = PremiumPlanType.free;
  DateTime? _nextBillingDate;
  String? _cardLast4;
  String? _cardBrand;
  String? _cardExpiry;
  String? _cardHolder;
  bool _autoRenew = true;
  bool _isLoaded = false;
  int _aiGenerationsCount = 0;
  List<int> _skipTimestamps = [];

  bool get isLoaded => _isLoaded;
  PremiumPlanType get plan => _plan;
  bool get isPremium {
    if (_plan == PremiumPlanType.free) return false;
    // Check if subscription period has ended
    if (_nextBillingDate != null) {
      if (DateTime.now().isAfter(_nextBillingDate!)) {
        return false;
      }
    }
    return true;
  }

  bool get isYearly => _plan == PremiumPlanType.yearly && isPremium;
  bool get isMonthly => _plan == PremiumPlanType.monthly && isPremium;
  bool get isFree => !isPremium;
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

  // Feature limits according to Business Plan
  int get aiGenerationsCount => _aiGenerationsCount;
  bool get canGenerateAiPlaylist => isPremium || _aiGenerationsCount < 2;
  int get remainingAiTrials =>
      isPremium ? 999 : (2 - _aiGenerationsCount).clamp(0, 2);

  bool get canDownloadOffline => isPremium;
  bool get canSyncListenAlong => isPremium;

  int get skipsInLastHour {
    final cutoff = DateTime.now().millisecondsSinceEpoch - 3600000;
    return _skipTimestamps.where((t) => t >= cutoff).length;
  }

  bool get canSkipTrack => isPremium || skipsInLastHour < 6;
  int get remainingHourlySkips =>
      isPremium ? 999 : (6 - skipsInLastHour).clamp(0, 6);

  /// Checks if an on-demand track switch is allowed:
  /// - If user is Premium -> always true
  /// - If player is idle / no track playing -> always true (free session start)
  /// - If user is actively playing a track and picking a NEW track:
  ///   - If skips available -> records 1 skip and returns true
  ///   - If skips exhausted -> shows Premium upsell sheet and returns false
  bool checkAndConsumeTrackSwitch(
    BuildContext context, {
    String? newTitle,
    String? newArtist,
    String? newId,
  }) {
    if (isPremium) return true;

    // Check if player is currently active
    final playback = PlaybackService();
    final current = playback.currentTrack;

    // If nothing is playing or re-triggering the same song, no skip is used
    if (current == null) {
      return true;
    }

    final isSameSong =
        (newId != null && newId.isNotEmpty && current.id == newId) ||
            (newTitle != null &&
                newTitle.isNotEmpty &&
                current.title.toLowerCase() == newTitle.toLowerCase() &&
                (newArtist == null ||
                    newArtist.isEmpty ||
                    current.artist.toLowerCase() == newArtist.toLowerCase()));

    if (isSameSong) {
      return true;
    }

    // Actively interrupting the current track -> requires an hourly skip
    if (!canSkipTrack) {
      PremiumService.showUpsell(
        context,
        reason:
            "You've used all 6 skips this hour. Upgrade to Melo Premium for unlimited on-demand song skips.",
        feature: 'Unlimited On-Demand Skips',
      );
      return false;
    }

    recordSkip();
    return true;
  }

  String get planName {
    if (!isPremium) return 'Free Tier';
    switch (_plan) {
      case PremiumPlanType.yearly:
        return '1 Year Pro Pass';
      case PremiumPlanType.monthly:
        return '1 Month Pro Pass';
      case PremiumPlanType.free:
        return 'Free Tier';
    }
  }

  String get planPrice {
    switch (_plan) {
      case PremiumPlanType.yearly:
        return '\$24.99 (1 Year)';
      case PremiumPlanType.monthly:
        return '\$2.99 (30 Days)';
      case PremiumPlanType.free:
        return '\$0.00';
    }
  }

  String get billingPeriod {
    switch (_plan) {
      case PremiumPlanType.yearly:
        return '1 Year (365 Days)';
      case PremiumPlanType.monthly:
        return '1 Month (30 Days)';
      case PremiumPlanType.free:
        return 'Free Tier';
    }
  }

  String get formattedNextBillingDate {
    if (_nextBillingDate == null) {
      final now = DateTime.now();
      final target = _plan == PremiumPlanType.yearly
          ? DateTime(now.year + 1, now.month, now.day)
          : DateTime(now.year, now.month + 1, now.day);
      return _formatDate(target);
    }
    return _formatDate(_nextBillingDate!);
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  RealtimeChannel? _subscriptionChannel;
  Timer? _pollTimer;

  Future<void> init() async {
    await _loadState();
    await fetchRemoteSubscription();
    _subscribeToSubscriptionChanges();
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    // Polls Supabase every 4 seconds in the foreground as a reliable fallback
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      fetchRemoteSubscription();
    });
  }

  void _subscribeToSubscriptionChanges() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    _subscriptionChannel?.unsubscribe();
    _subscriptionChannel = Supabase.instance.client
        .channel('user_subscriptions_realtime_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_subscriptions',
          callback: (payload) {
            debugPrint(
                '[PremiumService] Realtime subscription event (${payload.eventType}): ${payload.newRecord}');
            fetchRemoteSubscription();
          },
        )
        .subscribe();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final planStr = prefs.getString(_keyPlan);
    if (planStr == 'yearly') {
      _plan = PremiumPlanType.yearly;
    } else if (planStr == 'monthly') {
      _plan = PremiumPlanType.monthly;
    } else {
      _plan = PremiumPlanType.free;
    }

    final billingMs = prefs.getInt(_keyNextBilling);
    if (billingMs != null) {
      _nextBillingDate = DateTime.fromMillisecondsSinceEpoch(billingMs);
    }

    _cardLast4 = prefs.getString(_keyCardLast4);
    _cardBrand = prefs.getString(_keyCardBrand);
    _cardExpiry = prefs.getString(_keyCardExpiry);
    _cardHolder = prefs.getString(_keyCardHolder);
    _autoRenew = prefs.getBool(_keyAutoRenew) ?? true;
    _aiGenerationsCount = prefs.getInt(_keyAiGenerations) ?? 0;

    final skipListStr = prefs.getStringList(_keySkipTimestamps) ?? [];
    _skipTimestamps = skipListStr
        .map((e) => int.tryParse(e) ?? 0)
        .where((t) => t > 0)
        .toList();

    _isLoaded = true;
    notifyListeners();
  }

  /// Syncs subscription state from Supabase when user logs in
  Future<void> fetchRemoteSubscription() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final res = await Supabase.instance.client
          .from('user_subscriptions')
          .select()
          .eq('user_id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (res != null) {
        final planStr = res['plan'] as String? ?? 'free';
        if (planStr == 'yearly') {
          _plan = PremiumPlanType.yearly;
        } else if (planStr == 'monthly') {
          _plan = PremiumPlanType.monthly;
        } else {
          _plan = PremiumPlanType.free;
        }

        final nextBillingStr = res['next_billing_date'] as String?;
        if (nextBillingStr != null) {
          _nextBillingDate = DateTime.tryParse(nextBillingStr);
        }

        _cardBrand = res['card_brand'] as String?;
        _cardLast4 = res['card_last4'] as String?;
        _cardExpiry = res['card_expiry'] as String?;
        _cardHolder = res['card_holder'] as String?;
        _autoRenew = res['auto_renew'] as bool? ?? true;

        // Update local SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyPlan, planStr);
        if (_nextBillingDate != null) {
          await prefs.setInt(
              _keyNextBilling, _nextBillingDate!.millisecondsSinceEpoch);
        } else {
          await prefs.remove(_keyNextBilling);
        }
        if (_cardBrand != null) {
          await prefs.setString(_keyCardBrand, _cardBrand!);
        }
        if (_cardLast4 != null) {
          await prefs.setString(_keyCardLast4, _cardLast4!);
        }
        if (_cardExpiry != null) {
          await prefs.setString(_keyCardExpiry, _cardExpiry!);
        }
        if (_cardHolder != null) {
          await prefs.setString(_keyCardHolder, _cardHolder!);
        }
        await prefs.setBool(_keyAutoRenew, _autoRenew);

        notifyListeners();
      } else {
        // If row was deleted in Supabase, revert to free
        _plan = PremiumPlanType.free;
        _nextBillingDate = null;
        _autoRenew = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyPlan, 'free');
        await prefs.remove(_keyNextBilling);
        await prefs.setBool(_keyAutoRenew, false);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[PremiumService] Error fetching remote subscription: $e');
    }
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
        'status': _plan != PremiumPlanType.free ? 'active' : 'free',
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

    // If user currently has active remaining days, stack/extend from existing expiry date
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
    _plan = PremiumPlanType.free;
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
    PremiumUpsellSheet.show(
      context,
      reason: reason,
      feature: feature,
    );
  }
}
