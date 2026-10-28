import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'listening_history_service.dart';
import 'liked_songs_service.dart';
import '../utils/track_filter.dart';

class HomeService {
  static Map<String, dynamic>? _cachedData;
  static DateTime? _cacheTime;
  static DateTime? _discoveriesCacheTime;
  static const Duration _cacheTtl = Duration(hours: 12);
  static const Duration _discoveriesTtl = Duration(minutes: 30);
  static const _apiBase = 'https://api.deezer.com';

  static Future<void> _loadFromDisk() async {
    if (_cachedData != null && _cacheTime != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('home_cache_data');
      if (raw != null) {
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        _cachedData = _sanitizeHomeData(parsed);
        final ts = prefs.getString('home_cache_time');
        _cacheTime = ts != null ? DateTime.tryParse(ts) : DateTime.now();
        final discTs = prefs.getString('home_discoveries_cache_time');
        _discoveriesCacheTime =
            discTs != null ? DateTime.tryParse(discTs) : _cacheTime;

        // Immediately filter out any recommend-less songs from the loaded disk cache
        try {
          final lessKeys =
              await ListeningHistoryService.getAllRecommendLessKeys();
          if (lessKeys.isNotEmpty &&
              _cachedData != null &&
              _cachedData!['newDiscoveries'] != null) {
            final list =
                (_cachedData!['newDiscoveries'] as List<dynamic>?) ?? [];
            list.removeWhere((item) {
              if (item is! Map<String, dynamic>) return false;
              final tTitle = (item['title'] ?? '')
                  .toString()
                  .toLowerCase()
                  .replaceAll(RegExp(r'[^\w\s]'), '')
                  .trim();
              final tArtist = (item['artist'] ?? '')
                  .toString()
                  .toLowerCase()
                  .replaceAll(RegExp(r'[^\w\s]'), '')
                  .trim();
              final key = '$tTitle|$tArtist';
              return lessKeys.contains(key) ||
                  lessKeys.contains(tTitle) ||
                  lessKeys.contains(tArtist);
            });
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Home disk cache load error: $e');
    }
  }

  static bool isAllowedTrack(dynamic item) {
    if (item is! Map<String, dynamic>) return false;
    final title = (item['title'] ?? '').toString().trim();
    if (title.isEmpty) return false;
    return TrackFilter.isAllowedMap(item);
  }

  static Map<String, dynamic> _sanitizeHomeData(Map<String, dynamic> data) {
    final trending = (data['trendingNow'] as List<dynamic>? ?? [])
        .where(isAllowedTrack)
        .toList();
    final discoveries = (data['newDiscoveries'] as List<dynamic>? ?? [])
        .where(isAllowedTrack)
        .toList();

    return {
      ...data,
      'trendingNow': trending,
      'newDiscoveries': discoveries,
    };
  }

  /// Immediately remove a song or artist from the New Discoveries cache in memory and on disk
  static void removeTrackFromDiscoveries(String title, String artist) {
    try {
      final cleanTitle =
          title.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
      final cleanArtist =
          artist.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();

      if (_cachedData != null && _cachedData!['newDiscoveries'] != null) {
        final list = (_cachedData!['newDiscoveries'] as List<dynamic>?) ?? [];
        list.removeWhere((item) {
          if (item is! Map<String, dynamic>) return false;
          final tTitle = (item['title'] ?? '')
              .toString()
              .toLowerCase()
              .replaceAll(RegExp(r'[^\w\s]'), '')
              .trim();
          final tArtist = (item['artist'] ?? '')
              .toString()
              .toLowerCase()
              .replaceAll(RegExp(r'[^\w\s]'), '')
              .trim();
          return (tTitle.isNotEmpty && tTitle == cleanTitle) ||
              (cleanTitle.isNotEmpty &&
                  cleanArtist.isNotEmpty &&
                  tTitle == cleanTitle &&
                  tArtist == cleanArtist);
        });
      }
      _discoveriesCacheTime = null;
      _saveToDisk();
    } catch (e) {
      debugPrint('[HomeService] removeTrackFromDiscoveries error: $e');
    }
  }

  static Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'home_cache_time', (_cacheTime ?? DateTime.now()).toIso8601String());
      await prefs.setString('home_discoveries_cache_time',
          (_discoveriesCacheTime ?? DateTime.now()).toIso8601String());
      await prefs.setString('home_cache_data', jsonEncode(_cachedData));
    } catch (e) {
      debugPrint('Home disk cache save error: $e');
    }
  }

  static Future<Map<String, dynamic>?> getCachedData() async {
    if (_cachedData != null) return _sanitizeHomeData(_cachedData!);
    await _loadFromDisk();
    return _cachedData != null ? _sanitizeHomeData(_cachedData!) : null;
  }

  static Future<Map<String, dynamic>?> fetchHomeData(
      {bool force = false}) async {
    // Always ensure disk cache is in memory first so we have offline fallback
    await _loadFromDisk();

    if (!force) {
      if (_cachedData != null &&
          _cacheTime != null &&
          !isTrendingEmpty &&
          DateTime.now().difference(_cacheTime!) < _cacheTtl &&
          _discoveriesCacheTime != null &&
          !isDiscoveriesEmpty &&
          DateTime.now().difference(_discoveriesCacheTime!) < _discoveriesTtl) {
        return _sanitizeHomeData(_cachedData!);
      }
    }

    try {
      final user = Supabase.instance.client.auth.currentUser;
      List<String> userGenres = [];
      if (user != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final cached = prefs.getString('profile_favorite_genres');
          if (cached != null && cached.isNotEmpty) {
            userGenres = (jsonDecode(cached) as List<dynamic>)
                .map((e) => e.toString())
                .toList();
          }
        } catch (_) {}
      }

      final results = await Future.wait([
        _fetchChartTracks(),
        _fetchDiscoveries(),
      ], eagerError: true);

      final trending = results[0];
      final discoveries = results[1];

      // Only overwrite cache if we received valid fresh data
      if (trending.isNotEmpty || discoveries.isNotEmpty) {
        _cachedData = {
          'trendingNow': trending.isNotEmpty
              ? trending
              : (_cachedData?['trendingNow'] ?? []),
          'newDiscoveries': discoveries.isNotEmpty
              ? discoveries
              : (_cachedData?['newDiscoveries'] ?? []),
          'yourVibe': {
            'genres': userGenres.isNotEmpty
                ? userGenres
                : ((_cachedData?['yourVibe']
                        as Map<String, dynamic>?)?['genres'] ??
                    []),
            'songCount': 20,
          },
        };
        _cacheTime = DateTime.now();
        _discoveriesCacheTime = DateTime.now();
        await _saveToDisk();
      }
      return _cachedData != null ? _sanitizeHomeData(_cachedData!) : null;
    } catch (e) {
      debugPrint('Home data fetch error (offline / network): $e');
    }
    return _cachedData != null ? _sanitizeHomeData(_cachedData!) : null;
  }

  /// Fetches ONLY the new discoveries section every 30 minutes without re-fetching
  /// the 12-hour trending charts.
  static Future<List<Map<String, dynamic>>?> fetchDiscoveriesOnly(
      {bool force = false}) async {
    if (!force) {
      if (_cachedData != null &&
          _discoveriesCacheTime != null &&
          !isDiscoveriesEmpty &&
          DateTime.now().difference(_discoveriesCacheTime!) < _discoveriesTtl) {
        final disc = (_cachedData!['newDiscoveries'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .where(isAllowedTrack)
            .toList();
        return disc;
      }
      await _loadFromDisk();
      if (_cachedData != null &&
          _discoveriesCacheTime != null &&
          !isDiscoveriesEmpty &&
          DateTime.now().difference(_discoveriesCacheTime!) < _discoveriesTtl) {
        final disc = (_cachedData!['newDiscoveries'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .where(isAllowedTrack)
            .toList();
        return disc;
      }
    }

    try {
      final discoveries = await _fetchDiscoveries();
      if (discoveries.isNotEmpty) {
        final cleanDiscoveries = discoveries.where(isAllowedTrack).toList();
        _cachedData ??= {};
        _cachedData!['newDiscoveries'] = cleanDiscoveries;
        _discoveriesCacheTime = DateTime.now();
        await _saveToDisk();
        return cleanDiscoveries;
      }
    } catch (e) {
      debugPrint('Discoveries fetch error (offline or timeout): $e');
    }
    return (_cachedData?['newDiscoveries'] as List<dynamic>?)
        ?.whereType<Map<String, dynamic>>()
        .where(isAllowedTrack)
        .toList();
  }

  /// Fetch trending/viral TikTok tracks from Deezer
  static Future<List<Map<String, dynamic>>> _fetchChartTracks() async {
    try {
      // Primary: Official TikTok Hits World & Viral TikTok Songs
      final resp = await http.get(
        Uri.parse('$_apiBase/playlist/4403076402/tracks?limit=25'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final list = data['data'] as List? ?? [];
        if (list.isNotEmpty) {
          return list
              .whereType<Map<String, dynamic>>()
              .where((t) => t['readable'] != false)
              .map((t) => _trackToMap(t))
              .where(isAllowedTrack)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[Home] TikTok trending fetch error: $e');
    }

    // Fallback: Global Top Chart
    try {
      final resp = await http.get(
        Uri.parse('$_apiBase/chart/0/tracks?limit=20'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final list = data['data'] as List? ?? [];
        return list
            .whereType<Map<String, dynamic>>()
            .where((t) => t['readable'] != false)
            .map((t) => _trackToMap(t))
            .where(isAllowedTrack)
            .toList();
      }
    } catch (_) {}

    return [];
  }

  /// Fetch discovery tracks — dynamically filters out any tracks the user has
  /// already listened to, liked, or marked as 'recommend less', guaranteeing genuine new discoveries!
  static Future<List<Map<String, dynamic>>> _fetchDiscoveries() async {
    try {
      final history = await ListeningHistoryService.getHistory();
      final liked = await LikedSongsService.getLikedSongs();
      final recommendLessKeys =
          await ListeningHistoryService.getAllRecommendLessKeys();

      final playedKeys = <String>{};
      final dislikedArtists = <String>{};
      final artistDislikeCount = <String, int>{};

      for (final k in recommendLessKeys) {
        final rawLower = k.toLowerCase().trim();
        playedKeys.add(rawLower);

        if (k.contains('|')) {
          final parts = k.split('|');
          final songTitle =
              parts[0].toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
          final artistName =
              parts[1].toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
          if (songTitle.isNotEmpty) playedKeys.add(songTitle);
          if (songTitle.isNotEmpty && artistName.isNotEmpty) {
            playedKeys.add('$songTitle|$artistName');
          }
          if (artistName.isNotEmpty) {
            artistDislikeCount[artistName] =
                (artistDislikeCount[artistName] ?? 0) + 1;
            // If user recommended less on 2+ songs by this artist, exclude the entire artist
            if (artistDislikeCount[artistName]! >= 2) {
              dislikedArtists.add(artistName);
            }
          }
        } else {
          final clean =
              k.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
          if (clean.isNotEmpty) playedKeys.add(clean);
        }
      }
      for (final h in history) {
        final id = h['track_id']?.toString() ?? h['id']?.toString() ?? '';
        final title = (h['title'] ?? '')
            .toString()
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .trim();
        final artist = (h['artist'] ?? '')
            .toString()
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .trim();
        if (id.isNotEmpty) playedKeys.add(id);
        if (title.isNotEmpty) playedKeys.add('$title|$artist');
        if (title.isNotEmpty) playedKeys.add(title);
      }
      for (final l in liked) {
        final id = l['trackId']?.toString() ?? l['id']?.toString() ?? '';
        final title = (l['title'] ?? '')
            .toString()
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .trim();
        final artist = (l['artist'] ?? '')
            .toString()
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .trim();
        if (id.isNotEmpty) playedKeys.add(id);
        if (title.isNotEmpty) playedKeys.add('$title|$artist');
        if (title.isNotEmpty) playedKeys.add(title);
      }

      // Query high quality global discovery and viral hit playlist pools
      final pools = [
        '$_apiBase/playlist/3155776842/tracks?limit=30', // Hits of the Moment
        '$_apiBase/playlist/1313621735/tracks?limit=30', // Global Viral Hits
        '$_apiBase/playlist/11161893/tracks?limit=30', // Pop & Fresh Vibes
      ];

      final candidates = <Map<String, dynamic>>[];
      for (final url in pools) {
        try {
          final resp = await http.get(
            Uri.parse(url),
            headers: {'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 6));
          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body);
            final list = data['data'] as List? ?? [];
            candidates.addAll(list.whereType<Map<String, dynamic>>());
          }
        } catch (_) {}
      }

      final discoveries = <Map<String, dynamic>>[];
      final seenDiscoveries = <String>{};
      final seenArtists = <String>{};

      for (final t in candidates) {
        if (t['readable'] == false) continue;
        final trackId = t['id']?.toString() ?? '';
        final rawTitle = (t['title'] ?? '').toString();
        final rawArtist = (t['artist']?['name'] ?? '').toString();
        final cleanTitle =
            rawTitle.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
        final cleanArtist =
            rawArtist.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();

        if (cleanArtist.contains('stella lefty') ||
            cleanArtist == 'sombr' ||
            cleanArtist.contains('sombr') ||
            cleanArtist.contains('grand orchestre du splendid')) {
          continue;
        }

        // Enforce max 1 song per artist in New Discoveries
        if (seenArtists.contains(cleanArtist)) {
          continue;
        }

        // Skip if played before, already in history/likes, or marked recommend-less
        if (playedKeys.contains(trackId) ||
            playedKeys.contains(cleanTitle) ||
            playedKeys.contains('$cleanTitle|$cleanArtist') ||
            dislikedArtists.contains(cleanArtist)) {
          continue;
        }

        final mapped = _trackToMap(t);
        if (!isAllowedTrack(mapped)) continue;

        if (seenDiscoveries.add(cleanTitle)) {
          seenArtists.add(cleanArtist);
          discoveries.add(mapped);
          if (discoveries.length >= 10) break;
        }
      }

      return discoveries;
    } catch (e) {
      debugPrint('[Home] Discoveries error: $e');
    }
    return [];
  }

  static Map<String, dynamic> _trackToMap(Map<String, dynamic> track) {
    final artist = track['artist'] as Map<String, dynamic>? ?? {};
    final album = track['album'] as Map<String, dynamic>? ?? {};
    return {
      'id': track['id']?.toString() ?? '',
      'title': track['title'] ?? '',
      'artist': artist['name'] ?? '',
      'artistId': artist['id']?.toString() ?? '',
      'artistImage': artist['picture_big'] ?? artist['picture'] ?? '',
      'image': album['cover_big'] ?? album['cover'] ?? '',
      'duration': _formatDuration(track['duration'] ?? 0),
      'previewUrl': track['preview'] ?? '',
      'deezerId': track['id']?.toString() ?? '',
    };
  }

  static String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  static bool get isTrendingEmpty {
    final list = _cachedData?['trendingNow'] as List<dynamic>?;
    return list == null || list.isEmpty;
  }

  static bool get isDiscoveriesEmpty {
    final list = _cachedData?['newDiscoveries'] as List<dynamic>?;
    return list == null || list.isEmpty;
  }

  /// True when the in-memory cache is missing, empty, or past its 12h TTL — used by
  /// the home screen to decide whether a resume or retry should refetch.
  static bool get isStale =>
      _cachedData == null ||
      _cacheTime == null ||
      isTrendingEmpty ||
      DateTime.now().difference(_cacheTime!) >= _cacheTtl;

  /// True when New Discoveries are missing, empty, or older than 30 minutes.
  static bool get isDiscoveriesStale =>
      _cachedData == null ||
      _discoveriesCacheTime == null ||
      isDiscoveriesEmpty ||
      DateTime.now().difference(_discoveriesCacheTime!) >= _discoveriesTtl;

  static void invalidateDiscoveriesCache() {
    _discoveriesCacheTime = null;
  }

  static void clearCache() {
    _cachedData = null;
    _cacheTime = null;
    _discoveriesCacheTime = null;
  }

  static Future<void> clearDiskCache() async {
    _cachedData = null;
    _cacheTime = null;
    _discoveriesCacheTime = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('home_cache_time');
      await prefs.remove('home_discoveries_cache_time');
      await prefs.remove('home_cache_data');
    } catch (e) {
      debugPrint('Home prefs clear error: $e');
    }
  }
}
