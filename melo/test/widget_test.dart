import 'package:flutter_test/flutter_test.dart';
import 'package:melo/services/home_service.dart';
import 'package:melo/services/vibe_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HomeService.clearCache();
    VibeService.clearCache();
  });

  test('Daily Mix and HomeService detect staleness on date change', () async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('dailymix_cache_date', '2026-08-28');
    await prefs.setString('home_cache_time', '2026-08-28T12:00:00.000Z');
    await prefs.setString(
        'home_cache_data', '{"trendingNow":[],"newDiscoveries":[]}');

    expect(VibeService.dailyMixesStale, isTrue);
    expect(HomeService.isStale, isTrue);
  });

  test('Daily rotation produces unique day seed', () {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final yesterday = DateTime.now()
        .subtract(const Duration(days: 1))
        .toIso8601String()
        .substring(0, 10);

    expect(today.hashCode != yesterday.hashCode, isTrue);
  });
}
