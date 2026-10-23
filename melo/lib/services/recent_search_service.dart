import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'search_service.dart';
import '../utils/track_filter.dart';

class RecentSearchService {
  static const String _key = 'recent_search_items';
  static const int _maxItems = 15;
  static List<SearchResult>? _cache;

  static Future<List<SearchResult>> getRecentSearches() async {
    if (_cache != null) {
      return _cache!
          .where((e) =>
              TrackFilter.isAllowed(artist: e.artist, title: e.title, id: e.id))
          .toList();
    }
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_key);
    var list = jsonList == null
        ? <SearchResult>[]
        : jsonList.map((s) => SearchResult.fromJson(jsonDecode(s))).toList();

    final filtered = list
        .where((e) =>
            TrackFilter.isAllowed(artist: e.artist, title: e.title, id: e.id))
        .toList();

    // If items were purged, save cleaned list back to disk
    if (filtered.length != list.length) {
      await prefs.setStringList(
        _key,
        filtered
            .map((e) => jsonEncode({
                  'type': e.type,
                  'id': e.id,
                  'title': e.title,
                  'artist': e.artist,
                  'artistId': e.artistId,
                  'artistImage': e.artistImage,
                  'image': e.image,
                  'duration': e.duration,
                  'nbFan': e.nbFan,
                  'previewUrl': e.previewUrl,
                }))
            .toList(),
      );
    }

    _cache = filtered;
    return _cache!;
  }

  static Future<void> addItem(SearchResult item) async {
    if (TrackFilter.isBlocked(
        artist: item.artist, title: item.title, id: item.id)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final items = await getRecentSearches();
    items.removeWhere((e) => e.id == item.id);
    items.insert(0, item);
    if (items.length > _maxItems) {
      items.removeRange(_maxItems, items.length);
    }
    _cache = items;
    await prefs.setStringList(
      _key,
      items.map((e) => jsonEncode({
        'type': e.type,
        'id': e.id,
        'title': e.title,
        'artist': e.artist,
        'artistId': e.artistId,
        'artistImage': e.artistImage,
        'image': e.image,
        'duration': e.duration,
        'nbFan': e.nbFan,
        'previewUrl': e.previewUrl,
      })).toList(),
    );
  }

  static Future<void> removeItem(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getRecentSearches();
    items.removeWhere((e) => e.id == id);
    _cache = items;
    await prefs.setStringList(
      _key,
      items.map((e) => jsonEncode({
        'type': e.type,
        'id': e.id,
        'title': e.title,
        'artist': e.artist,
        'artistId': e.artistId,
        'artistImage': e.artistImage,
        'image': e.image,
        'duration': e.duration,
        'nbFan': e.nbFan,
        'previewUrl': e.previewUrl,
      })).toList(),
    );
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    _cache = [];
    await prefs.remove(_key);
  }
}
