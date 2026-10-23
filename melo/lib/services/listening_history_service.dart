import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_service.dart';

class ListeningHistoryService {
  static List<Map<String, dynamic>> _cache = [];
  static bool _loaded = false;
  static bool _diskLoaded = false;
  static const String _diskKey = 'listening_history_cache';
  static final ValueNotifier<int> onUpdate = ValueNotifier<int>(0);

  static int get count => _cache.length;
  static List<Map<String, dynamic>> get cachedHistory =>
      List.unmodifiable(_cache);

  static Future<void> init() async {
    if (_diskLoaded) return;
    await _loadFromDisk();
  }

  static Future<void> _loadFromDisk() async {
    _diskLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final raw = prefs.getString('${_diskKey}_$userId');
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>;
        _cache = list.map((e) => Map<String, dynamic>.from(e)).toList();
        _loaded = true;
      }
    } catch (e) {
      print('History disk cache load error: $e');
    }
  }

  static Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      await prefs.setString('${_diskKey}_$userId', jsonEncode(_cache));
    } catch (e) {
      print('History disk cache save error: $e');
    }
  }

  static Future<void> clearCache() async {
    _cache = [];
    _loaded = false;
    _diskLoaded = false;
    onUpdate.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await prefs.remove('${_diskKey}_$userId');
      }
    } catch (e) {
      print('History disk cache clear error: $e');
    }
  }

  /// Removes a single song entry from local cache and Supabase history table
  static Future<void> removeFromHistory({
    required String title,
    required String artist,
    String? trackId,
  }) async {
    _cache.removeWhere((e) {
      final eTrackId = e['trackId']?.toString();
      if (trackId != null &&
          trackId.isNotEmpty &&
          eTrackId != null &&
          eTrackId.isNotEmpty &&
          eTrackId == trackId) {
        return true;
      }
      return e['title']?.toString().toLowerCase().trim() ==
              title.toLowerCase().trim() &&
          e['artist']?.toString().toLowerCase().trim() ==
              artist.toLowerCase().trim();
    });
    await _saveToDisk();

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Delete by track_id if present
      if (trackId != null && trackId.isNotEmpty) {
        await Supabase.instance.client
            .from('listening_history')
            .delete()
            .eq('user_id', user.id)
            .eq('track_id', trackId)
            .timeout(const Duration(seconds: 8));
      }

      // Also delete by title + artist to ensure any duplicate entries are purged
      if (title.isNotEmpty) {
        await Supabase.instance.client
            .from('listening_history')
            .delete()
            .eq('user_id', user.id)
            .eq('title', title)
            .eq('artist', artist)
            .timeout(const Duration(seconds: 8));
      }
    } catch (e) {
      print('History item remove error: $e');
    }
  }

  /// Clears entire listening history from local cache and Supabase history table
  static Future<void> clearAllHistory() async {
    _cache = [];
    _loaded = true;
    _saveToDisk();
    onUpdate.value++;

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      await Supabase.instance.client
          .from('listening_history')
          .delete()
          .eq('user_id', user.id)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      print('History clear all error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getHistory(
      {int days = 30, bool force = false}) async {
    if (!_diskLoaded) await _loadFromDisk();
    if (!force && _loaded && _cache.isNotEmpty) return _cache;
    if (!force && _loaded && _cache.isEmpty) return _cache;

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return [];

      final since = DateTime.now()
          .toUtc()
          .subtract(Duration(days: days))
          .toIso8601String();
      final rows = await Supabase.instance.client
          .from('listening_history')
          .select()
          .eq('user_id', user.id)
          .gte('created_at', since)
          .order('created_at', ascending: false)
          .limit(200)
          .timeout(const Duration(seconds: 15));

      _cache = (rows as List)
          .map((r) => {
                'trackId': r['track_id']?.toString() ?? '',
                'title': r['title']?.toString() ?? '',
                'artist': r['artist']?.toString() ?? '',
                'image': r['image']?.toString() ?? '',
                'artistId': r['artist_id']?.toString() ?? '',
                'artistImage': r['artist_image']?.toString() ?? '',
                'genre': r['genre']?.toString() ?? '',
                'skipped': r['skipped'] == true,
                'completed': r['completed'] == true,
                'replayed': r['replayed'] == true,
                'listenDuration': r['listen_duration'] ?? 0,
                'source': r['source']?.toString() ?? 'vibe',
                'created_at': r['created_at']?.toString() ?? '',
              })
          .toList();
      _loaded = true;
      await _saveToDisk();
      return _cache;
    } catch (e) {
      print('History fetch error: $e');
    }
    return _cache;
  }

  static Future<void> logEvent({
    required String trackId,
    required String title,
    required String artist,
    String image = '',
    String genre = '',
    bool skipped = false,
    bool completed = false,
    bool replayed = false,
    int listenDuration = 0,
    String source = 'vibe',
    String artistId = '',
    String artistImage = '',
  }) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final entry = {
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'image': image,
        'genre': genre,
        'skipped': skipped,
        'completed': completed,
        'replayed': replayed,
        'listenDuration': listenDuration,
        'source': source,
        'artistId': artistId,
        'artistImage': artistImage,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      _cache.removeWhere((e) => e['title'] == title && e['artist'] == artist);
      _cache.insert(0, entry);
      _loaded = true;
      _saveToDisk();

      await Supabase.instance.client.from('listening_history').insert({
        'user_id': user.id,
        'track_id': trackId,
        'title': title,
        'artist': artist,
        'image': image,
        'genre': genre,
        'skipped': skipped,
        'completed': completed,
        'replayed': replayed,
        'listen_duration': listenDuration,
        'source': source,
        'artist_id': artistId,
        'artist_image': artistImage,
      }).timeout(const Duration(seconds: 5));

      onUpdate.value++;
    } catch (e) {
      print('Listening history log error: $e');
    }
  }

  /// Reads the user's taste-profile row for [genre], applies the change to the
  /// recommend_more / recommend_less song-key lists, and upserts it back.
  static Future<void> _updateTasteProfile(
    String genre, {
    String? addToMore,
    String? addToLess,
    String? removeFromMore,
    String? removeFromLess,
  }) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final existing = await Supabase.instance.client
          .from('user_taste_profiles')
          .select()
          .eq('user_id', user.id)
          .eq('genre', genre)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      List<String> toList(dynamic v) =>
          (v as List<dynamic>? ?? []).map((e) => e.toString()).toList();

      final more = toList(existing?['recommend_more']);
      final less = toList(existing?['recommend_less']);

      if (addToMore != null && !more.contains(addToMore)) {
        more.insert(0, addToMore);
        less.remove(addToMore);
        if (more.length > 50) more.removeRange(50, more.length);
      }
      if (addToLess != null && !less.contains(addToLess)) {
        less.insert(0, addToLess);
        more.remove(addToLess);
        if (less.length > 50) less.removeRange(50, less.length);
      }
      if (removeFromMore != null) more.remove(removeFromMore);
      if (removeFromLess != null) less.remove(removeFromLess);

      await Supabase.instance.client.from('user_taste_profiles').upsert({
        'user_id': user.id,
        'genre': genre,
        'liked_artists': existing?['liked_artists'] ?? [],
        'liked_songs': existing?['liked_songs'] ?? [],
        'disliked_artists': existing?['disliked_artists'] ?? [],
        'disliked_songs': existing?['disliked_songs'] ?? [],
        'recommend_more': more,
        'recommend_less': less,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,genre');

      onUpdate.value++;
    } catch (e) {
      print('Taste profile update error: $e');
    }
  }

  static Future<void> recommendMore(String genre, String title, String artist) {
    return _updateTasteProfile(genre, addToMore: '$title|$artist');
  }

  static Future<void> recommendLess(String genre, String title, String artist) {
    HomeService.removeTrackFromDiscoveries(title, artist);
    return _updateTasteProfile(genre, addToLess: '$title|$artist');
  }

  static Future<void> removeRecommendation(
      String genre, String title, String artist, String type) {
    final key = '$title|$artist';
    if (type == 'more') {
      return _updateTasteProfile(genre, removeFromMore: key);
    }
    if (type == 'less') {
      return _updateTasteProfile(genre, removeFromLess: key);
    }
    return _updateTasteProfile(genre, removeFromMore: key, removeFromLess: key);
  }

  /// Gets all recommend_less keys across all genres to filter out of autoplay / smart queue / vibe mixes
  static Future<Set<String>> getAllRecommendLessKeys() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return {};

      final rows = await Supabase.instance.client
          .from('user_taste_profiles')
          .select('recommend_less')
          .eq('user_id', user.id)
          .timeout(const Duration(seconds: 5));

      final keys = <String>{};
      final list = rows as List<dynamic>? ?? [];
      for (final r in list) {
        final lessList = r['recommend_less'] as List<dynamic>? ?? [];
        for (final item in lessList) {
          final str = item.toString().toLowerCase().trim();
          if (str.isNotEmpty) keys.add(str);
        }
      }
      return keys;
    } catch (e) {
      debugPrint('[Taste] Error fetching recommend_less keys: $e');
      return {};
    }
  }
}
