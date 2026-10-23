import 'package:shared_preferences/shared_preferences.dart';
import '../utils/track_filter.dart';

class RecentQueryService {
  static const String _musicKey = 'recent_search_queries_music';
  static const String _peopleKey = 'recent_search_queries_people';
  static const int _maxItems = 12;
  static List<String>? _musicCache;
  static List<String>? _peopleCache;

  static Future<List<String>> getRecentQueries({bool isPeople = false}) async {
    if (isPeople && _peopleCache != null) {
      return _peopleCache!
          .where((q) => TrackFilter.isAllowed(query: q))
          .toList();
    }
    if (!isPeople && _musicCache != null) {
      return _musicCache!
          .where((q) => TrackFilter.isAllowed(query: q))
          .toList();
    }

    final prefs = await SharedPreferences.getInstance();
    final key = isPeople ? _peopleKey : _musicKey;
    final list = prefs.getStringList(key) ?? [];
    final filtered =
        list.where((q) => TrackFilter.isAllowed(query: q)).toList();

    if (filtered.length != list.length) {
      await prefs.setStringList(key, filtered);
    }

    if (isPeople) {
      _peopleCache = filtered;
      return _peopleCache!;
    } else {
      _musicCache = filtered;
      return _musicCache!;
    }
  }

  static Future<void> addQuery(String query, {bool isPeople = false}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || TrackFilter.isBlocked(query: trimmed)) return;
    final prefs = await SharedPreferences.getInstance();
    final items = await getRecentQueries(isPeople: isPeople);
    items.removeWhere((e) => e.toLowerCase() == trimmed.toLowerCase());
    items.insert(0, trimmed);
    if (items.length > _maxItems) {
      items.removeRange(_maxItems, items.length);
    }
    final key = isPeople ? _peopleKey : _musicKey;
    if (isPeople) {
      _peopleCache = items;
    } else {
      _musicCache = items;
    }
    await prefs.setStringList(key, items);
  }

  static Future<void> removeQuery(String query, {bool isPeople = false}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final items = await getRecentQueries(isPeople: isPeople);
    items.removeWhere((e) => e.toLowerCase() == trimmed.toLowerCase());
    final key = isPeople ? _peopleKey : _musicKey;
    if (isPeople) {
      _peopleCache = items;
    } else {
      _musicCache = items;
    }
    await prefs.setStringList(key, items);
  }

  static Future<void> clearAll({bool isPeople = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = isPeople ? _peopleKey : _musicKey;
    if (isPeople) {
      _peopleCache = [];
    } else {
      _musicCache = [];
    }
    await prefs.remove(key);
  }
}
