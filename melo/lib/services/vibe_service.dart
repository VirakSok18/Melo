import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'search_service.dart';
import 'listening_history_service.dart';
import '../utils/track_filter.dart';

class VibeService {
  static Map<String, List<Map<String, dynamic>>> _cache = {};
  static final Map<String, Map<String, dynamic>> _resolvedClassicsCache = {};
  static bool _prefetched = false;
  static const _deezerApi = 'https://api.deezer.com';
  static const _totalTracks = 20;

  static String _today() {
    final now = DateTime.now();
    return now.toIso8601String().substring(0, 10);
  }

  // --- Asset data (loaded once) ---
  static Map<String, dynamic>? _artistsJson;
  static Map<String, dynamic>? _genreTracksJson;

  static Future<Map<String, dynamic>> _loadArtistsJson() async {
    if (_artistsJson != null) return _artistsJson!;
    final raw = await rootBundle.loadString('asset/data/artists.json');
    _artistsJson = jsonDecode(raw) as Map<String, dynamic>;
    return _artistsJson!;
  }

  static Future<Map<String, dynamic>> _loadGenreTracksJson() async {
    if (_genreTracksJson != null) return _genreTracksJson!;
    final raw = await rootBundle.loadString('asset/data/genre_tracks.json');
    _genreTracksJson = jsonDecode(raw) as Map<String, dynamic>;
    return _genreTracksJson!;
  }

  // --- Disk cache ---
  static String _getUserScopedKey(String base) {
    final user = Supabase.instance.client.auth.currentUser;
    final uid = user?.id ?? 'anon';
    return '${base}_$uid';
  }

  static Future<void> _loadFromDisk() async {
    if (_cache.isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateKey = _getUserScopedKey('vibe_cache_date');
      final dataKey = _getUserScopedKey('vibe_cache_data');

      final cachedDate = prefs.getString(dateKey);
      if (cachedDate != _today()) {
        await prefs.remove(dateKey);
        await prefs.remove(dataKey);
        return;
      }

      final raw = prefs.getString(dataKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _cache = decoded.map((k, v) => MapEntry(
            k,
            (v as List<dynamic>)
                .map((e) => Map<String, dynamic>.from(e))
                .where(TrackFilter.isAllowedMap)
                .toList()));
      }
    } catch (e) {
      print('Vibe disk cache load error: $e');
    }
  }

  static Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateKey = _getUserScopedKey('vibe_cache_date');
      final dataKey = _getUserScopedKey('vibe_cache_data');
      await prefs.setString(dateKey, _today());
      await prefs.setString(dataKey, jsonEncode(_cache));
    } catch (e) {
      print('Vibe disk cache save error: $e');
    }
  }

  // --- Public API ---

  static Future<List<Map<String, dynamic>>> getPlaylist(String genre,
      {bool force = false}) async {
    final cacheKey = genre.toLowerCase();

    if (!force) {
      if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;
      await _loadFromDisk();
      if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;
    }

    // Check backend for today's playlist
    if (!force) {
      final backendPlaylist = await _getTodayPlaylist(genre);
      if (backendPlaylist != null && backendPlaylist.isNotEmpty) {
        _cache[cacheKey] = backendPlaylist;
        await _saveToDisk();
        return backendPlaylist;
      }
    }

    // Build new playlist from Deezer
    final tracks = await _buildPlaylist(genre);
    if (tracks.isNotEmpty) {
      _cache[cacheKey] = tracks;
      await _saveToDisk();
      await _savePlaylist(genre, tracks);
    }
    return tracks;
  }

  static Future<void> preFetch(List<String> genres) async {
    if (genres.isEmpty) return;
    await _loadFromDisk();

    final uncached =
        genres.where((g) => !_cache.containsKey(g.toLowerCase())).toList();
    if (uncached.isEmpty) {
      _prefetched = true;
      return;
    }

    for (final genre in uncached) {
      final tracks = await _buildPlaylist(genre);
      if (tracks.isNotEmpty) {
        _cache[genre.toLowerCase()] = tracks;
        await _savePlaylist(genre, tracks);
      }
    }

    _prefetched = true;
    await _saveToDisk();
  }

  static bool get isPrefetched => _prefetched;

  static void clearCache() {
    _cache.clear();
    _prefetched = false;
    clearDailyMixesCache();
  }

  static Future<void> clearDiskCache() async {
    clearCache();
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateKey = _getUserScopedKey('vibe_cache_date');
      final dataKey = _getUserScopedKey('vibe_cache_data');
      final mixDateKey = _getUserScopedKey('dailymix_v4_cache_date');
      final mixDataKey = _getUserScopedKey('dailymix_v4_cache_data');

      await prefs.remove(dateKey);
      await prefs.remove(dataKey);
      await prefs.remove(mixDateKey);
      await prefs.remove(mixDataKey);
      await prefs.remove('vibe_cache_date');
      await prefs.remove('vibe_cache_data');
      await prefs.remove('dailymix_cache_date');
      await prefs.remove('dailymix_cache_data');
      await prefs.remove('dailymix_v3_cache_date');
      await prefs.remove('dailymix_v3_cache_data');
      await prefs.remove('dailymix_v4_cache_date');
      await prefs.remove('dailymix_v4_cache_data');
    } catch (e) {
      print('Vibe prefs clear error: $e');
    }
  }

  // --- Build playlist (Deezer direct for track data) ---

  static Future<List<Map<String, dynamic>>> _buildPlaylist(String genre) async {
    try {
      await _loadArtistsJson();
      await _loadGenreTracksJson();
      final userArtists = await _getUserFavoriteArtists();
      final matchingArtists = _matchArtistsToGenre(genre, userArtists);

      final classicCount = (_totalTracks * 6) ~/ 10;
      final personalizedCount = _totalTracks - classicCount;

      final classics = await _resolveClassics(genre, classicCount + 6);
      final personalized = matchingArtists.isNotEmpty
          ? await _getUserArtistTracks(matchingArtists, personalizedCount + 4)
          : <Map<String, dynamic>>[];

      final seen = <String>{};
      final playlist = <Map<String, dynamic>>[];

      // Seed random with today's date so today's order and selection rotates daily
      final todayHash = _today().hashCode;
      final dayRandom = Random(todayHash);

      personalized.shuffle(dayRandom);
      for (final track in personalized) {
        final key = '${track['title']}|${track['artist']}'.toLowerCase();
        if (seen.add(key)) playlist.add(track);
        if (playlist.length >= personalizedCount) break;
      }

      classics.shuffle(dayRandom);
      for (final track in classics) {
        final key = '${track['title']}|${track['artist']}'.toLowerCase();
        if (seen.add(key)) playlist.add(track);
        if (playlist.length >= _totalTracks) break;
      }

      // If still under 20 (due to failed searches or duplicate titles), resolve all remaining curated classics
      if (playlist.length < _totalTracks) {
        final allClassics = await _resolveClassics(genre, 30);
        allClassics.shuffle(dayRandom);
        for (final track in allClassics) {
          final key = '${track['title']}|${track['artist']}'.toLowerCase();
          if (seen.add(key)) playlist.add(track);
          if (playlist.length >= _totalTracks) break;
        }
      }

      // If STILL under 20, fetch top tracks from curated artists in that genre
      if (playlist.length < _totalTracks) {
        final genreNode = _artistsJson?[genre];
        if (genreNode is List && genreNode.isNotEmpty) {
          for (final node in genreNode) {
            if (playlist.length >= _totalTracks) break;
            final artistId = node['id']?.toString() ?? '';
            final artistName = node['name']?.toString() ?? '';
            if (artistId.isNotEmpty) {
              final topTracks = await _getUserArtistTracks([
                {'id': artistId, 'name': artistName}
              ], 4);
              for (final t in topTracks) {
                final key = '${t['title']}|${t['artist']}'.toLowerCase();
                if (seen.add(key)) playlist.add(t);
                if (playlist.length >= _totalTracks) break;
              }
            }
          }
        }
      }

      final shuffledInterleaved = _interleaveTracksByArtist(playlist);
      return shuffledInterleaved;
    } catch (e) {
      print('[Vibe] Build playlist error for $genre: $e');
      return [];
    }
  }

  static Future<List<Map<String, String>>> _getUserFavoriteArtists() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return [];

      final Map<String, String> artistMap = {}; // name.toLowerCase() -> id

      // 1. Fetch onboarding favorite artists from profile
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('favorite_artists')
            .eq('id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 6));

        final artistsRaw = profile?['favorite_artists'] as List<dynamic>? ?? [];
        for (final a in artistsRaw) {
          final id = (a['id'] ?? '').toString();
          final name = (a['name'] ?? '').toString();
          if (name.isNotEmpty) {
            artistMap[name.toLowerCase()] = id;
          }
        }
      } catch (e) {
        debugPrint('[Vibe] Failed to fetch profile favorite artists: $e');
      }

      // 2. Fetch followed artists from artist_follows table
      try {
        final follows = await Supabase.instance.client
            .from('artist_follows')
            .select('artist_id, artist_name')
            .eq('user_id', user.id)
            .timeout(const Duration(seconds: 6));

        final followsList = follows as List<dynamic>? ?? [];
        for (final f in followsList) {
          final id = (f['artist_id'] ?? '').toString();
          final name = (f['artist_name'] ?? '').toString();
          if (name.isNotEmpty) {
            artistMap[name.toLowerCase()] = id;
          }
        }
      } catch (e) {
        debugPrint('[Vibe] Failed to fetch artist follows: $e');
      }

      final result = <Map<String, String>>[];
      artistMap.forEach((nameLower, id) {
        result.add({
          'id': id,
          'name': nameLower,
        });
      });
      return result;
    } catch (e) {
      debugPrint('[Vibe] Failed to fetch user artists: $e');
      return [];
    }
  }

  // --- Match user artists to genre ---

  static List<Map<String, String>> _matchArtistsToGenre(
      String genre, List<Map<String, String>> userArtists) {
    final artistsJson = _artistsJson;
    if (artistsJson == null) return [];

    final genreNode = artistsJson[genre];
    if (genreNode == null || genreNode is! List) return [];

    final genreArtists = <String, String>{};
    for (final node in genreNode) {
      if (node['name'] != null && node['id'] != null) {
        genreArtists[node['name'].toString().toLowerCase()] =
            node['id'].toString();
      }
    }

    final matched = <Map<String, String>>[];
    for (final artist in userArtists) {
      final deezerId = genreArtists[artist['name']?.toLowerCase()];
      if (deezerId != null) {
        matched.add({'id': deezerId, 'name': artist['name']!});
      }
    }
    return matched;
  }

  // --- Get tracks from user's favorite artists (Deezer direct) ---

  static Future<List<Map<String, dynamic>>> _getUserArtistTracks(
      List<Map<String, String>> matchingArtists, int count,
      {int offset = 0}) async {
    final tracks = <Map<String, dynamic>>[];
    if (matchingArtists.isEmpty) return tracks;

    final tracksPerArtist = max(1, count ~/ matchingArtists.length);

    for (final artist in matchingArtists) {
      if (tracks.length >= count) break;
      try {
        final artistId = artist['id']!;
        if (int.tryParse(artistId) == null) continue;

        final limit = offset + tracksPerArtist + 2;
        final resp = await http.get(
          Uri.parse('$_deezerApi/artist/$artistId/top?limit=$limit'),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 8));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final rawTopTracks = data['data'] as List? ?? [];
          final topTracks = rawTopTracks.length > offset
              ? rawTopTracks.sublist(offset)
              : rawTopTracks;
          for (final track in topTracks) {
            if (tracks.length >= count) break;
            final t = SearchResult.fromDeezerTrack(track);
            tracks.add({
              'title': t.title,
              'artist': t.artist,
              'artistId': t.artistId,
              'artistImage': t.artistImage,
              'image': t.image,
              'duration': t.duration,
              'deezerId': t.id,
              'previewUrl': t.previewUrl,
              'source': 'personalized',
            });
          }
        }
      } catch (e) {
        print('[Vibe] Failed to get tracks for ${artist['name']}: $e');
      }
    }
    return tracks;
  }

  // --- Resolve curated classic tracks via Deezer search ---

  static Future<List<Map<String, dynamic>>> _resolveClassics(
      String genre, int limit) async {
    final genreTracks = _genreTracksJson;
    if (genreTracks == null) return [];

    final tracksNode = genreTracks[genre];
    if (tracksNode == null || tracksNode is! List) return [];

    final curated = <Map<String, String>>[];
    for (final node in tracksNode) {
      final title = node['title']?.toString() ?? '';
      final artist = node['artist']?.toString() ?? '';
      if (title.isNotEmpty && artist.isNotEmpty) {
        curated.add({'title': title, 'artist': artist});
      }
    }

    final resolved = <Map<String, dynamic>>[];
    final toFetch = <Map<String, String>>[];

    for (final track in curated) {
      final key = '${track['title']}|${track['artist']}'.toLowerCase();
      if (_resolvedClassicsCache.containsKey(key)) {
        resolved.add(_resolvedClassicsCache[key]!);
        if (resolved.length >= limit) return resolved;
      } else {
        toFetch.add(track);
      }
    }

    if (resolved.length < limit && toFetch.isNotEmpty) {
      final needed = limit - resolved.length;
      final candidates = toFetch.take(needed + 4).toList();

      final fetchFutures = candidates.map((track) async {
        final key = '${track['title']}|${track['artist']}'.toLowerCase();
        try {
          final query =
              Uri.encodeComponent('${track['title']} ${track['artist']}');
          final resp = await http.get(
            Uri.parse('$_deezerApi/search?q=$query&limit=3'),
            headers: {'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 4));

          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body);
            final results = data['data'] as List? ?? [];
            SearchResult? bestMatch;
            for (final r in results) {
              final t = SearchResult.fromDeezerTrack(r);
              if (t.title.toLowerCase() == track['title']!.toLowerCase() &&
                  t.artist.toLowerCase() == track['artist']!.toLowerCase()) {
                bestMatch = t;
                break;
              }
            }
            bestMatch ??= results.isNotEmpty
                ? SearchResult.fromDeezerTrack(results[0])
                : null;

            if (bestMatch != null) {
              final map = {
                'title': bestMatch.title,
                'artist': bestMatch.artist,
                'artistId': bestMatch.artistId,
                'artistImage': bestMatch.artistImage,
                'image': bestMatch.image,
                'duration': bestMatch.duration,
                'deezerId': bestMatch.id,
                'previewUrl': bestMatch.previewUrl,
                'source': 'classic',
              };
              _resolvedClassicsCache[key] = map;
              return map;
            }
          }
        } catch (e) {
          debugPrint('[Vibe] Failed to resolve "${track['title']}": $e');
        }
        return null;
      });

      final fetchedResults = await Future.wait(fetchFutures);
      for (final res in fetchedResults) {
        if (res != null) {
          resolved.add(res);
          if (resolved.length >= limit) break;
        }
      }
    }

    return resolved;
  }

  // --- Supabase direct for playlist storage (no backend needed) ---

  static Future<List<Map<String, dynamic>>?> _getTodayPlaylist(
      String genre) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return null;

      final today = _today();
      final response = await Supabase.instance.client
          .from('daily_playlists')
          .select('songs')
          .eq('user_id', user.id)
          .eq('genre', genre)
          .eq('playlist_date', today)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (response != null) {
        final songs = (response['songs'] as List<dynamic>? ?? [])
            .map((s) => Map<String, dynamic>.from(s))
            .where(TrackFilter.isAllowedMap)
            .toList();
        if (songs.isNotEmpty) {
          return _interleaveTracksByArtist(songs);
        }
      }
    } catch (e) {
      print('[Vibe] Failed to fetch cached playlist from Supabase: $e');
    }
    return null;
  }

  static List<Map<String, dynamic>> _interleaveTracksByArtist(
      List<Map<String, dynamic>> list) {
    if (list.length <= 2) return list;

    // Group tracks by artist preserving order
    final byArtist = <String, List<Map<String, dynamic>>>{};
    for (final track in list) {
      final artist = (track['artist'] ?? '').toString().toLowerCase();
      byArtist.putIfAbsent(artist, () => []).add(track);
    }

    final artistKeys = byArtist.keys.toList();

    final result = <Map<String, dynamic>>[];
    bool added = true;
    int round = 0;

    while (added && result.length < list.length) {
      added = false;
      for (final key in artistKeys) {
        final artistTracks = byArtist[key]!;
        if (round < artistTracks.length) {
          result.add(artistTracks[round]);
          added = true;
        }
      }
      round++;
    }

    return result;
  }

  static Future<void> _savePlaylist(
      String genre, List<Map<String, dynamic>> playlist) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final today = _today();
      await Supabase.instance.client.from('daily_playlists').upsert({
        'user_id': user.id,
        'genre': genre,
        'playlist_date': today,
        'songs': playlist,
      }, onConflict: 'user_id,genre,playlist_date').timeout(
          const Duration(seconds: 10));
    } catch (e) {
      print('[Vibe] Failed to save playlist to Supabase: $e');
    }
  }

  // --- Daily Mixes (100% Frontend Algorithms) ---

  static Map<String, Map<String, dynamic>> _dailyMixesCache = {};
  static String? _dailyMixesDate;

  static Future<void> _loadDailyMixesFromDisk() async {
    if (_dailyMixesCache.isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateKey = _getUserScopedKey('dailymix_v4_cache_date');
      final dataKey = _getUserScopedKey('dailymix_v4_cache_data');

      final cachedDate = prefs.getString(dateKey);
      if (cachedDate != _today()) {
        await prefs.remove(dateKey);
        await prefs.remove(dataKey);
        return;
      }

      final raw = prefs.getString(dataKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _dailyMixesCache = decoded
            .map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
        _dailyMixesDate = cachedDate;
      }
    } catch (e) {
      print('DailyMix disk cache load error: $e');
    }
  }

  static Future<void> _saveDailyMixesToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateKey = _getUserScopedKey('dailymix_v4_cache_date');
      final dataKey = _getUserScopedKey('dailymix_v4_cache_data');
      await prefs.setString(dateKey, _dailyMixesDate ?? _today());
      await prefs.setString(dataKey, jsonEncode(_dailyMixesCache));
    } catch (e) {
      print('DailyMix disk cache save error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getCachedDailyMixes() async {
    if (_dailyMixesCache.isNotEmpty) return _dailyMixesToMapList();
    await _loadDailyMixesFromDisk();
    return _dailyMixesToMapList();
  }

  static Future<List<Map<String, dynamic>>> _fetchChartTracks(int limit) async {
    try {
      final resp = await http.get(
        Uri.parse('$_deezerApi/chart/0/tracks?limit=$limit'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final tracks = data['data'] as List? ?? [];
        return tracks.map((r) {
          final t = SearchResult.fromDeezerTrack(r);
          return {
            'title': t.title,
            'artist': t.artist,
            'artistId': t.artistId,
            'artistImage': t.artistImage,
            'image': t.image,
            'duration': t.duration,
            'deezerId': t.id,
            'previewUrl': t.previewUrl,
            'source': 'chart',
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('[Vibe] Chart fetch error: $e');
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> _searchDeezer(
      String query, int limit) async {
    try {
      final encoded = Uri.encodeComponent(query);
      final resp = await http.get(
        Uri.parse('$_deezerApi/search?q=$encoded&limit=$limit'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final tracks = data['data'] as List? ?? [];
        return tracks.map((r) {
          final t = SearchResult.fromDeezerTrack(r);
          return {
            'title': t.title,
            'artist': t.artist,
            'artistId': t.artistId,
            'artistImage': t.artistImage,
            'image': t.image,
            'duration': t.duration,
            'deezerId': t.id,
            'previewUrl': t.previewUrl,
            'source': 'discovery',
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('[Vibe] Deezer search error for "$query": $e');
    }
    return [];
  }

  // --- Algorithm 1: Your Mix (Top songs you know and love) ---
  static Future<List<Map<String, dynamic>>> _buildYourMix({
    required List<Map<String, dynamic>> history,
    required Set<String> recentlyPlayed,
    required Set<String> recommendLess,
    required List<Map<String, String>> userArtists,
  }) async {
    final playlist = <Map<String, dynamic>>[];
    final usedKeys = <String>{};

    if (history.isNotEmpty) {
      // Score every song in history: completed (+10), replayed (+20), skipped (-5)
      final scores = <String, int>{};
      final songMap = <String, Map<String, dynamic>>{};

      for (final h in history) {
        final title = (h['title'] ?? '').toString().trim();
        final artist = (h['artist'] ?? '').toString().trim();
        final key = '$title|$artist'.toLowerCase();
        if (key == '|') continue;

        scores[key] = (scores[key] ?? 0) +
            ((h['completed'] == true) ? 10 : 0) +
            ((h['replayed'] == true) ? 20 : 0) -
            ((h['skipped'] == true) ? 5 : 0);

        songMap.putIfAbsent(
            key,
            () => {
                  'title': title,
                  'artist': artist,
                  'image': h['image'] ?? '',
                  'artistId': h['artistId'] ?? '',
                  'artistImage': h['artistImage'] ?? '',
                  'duration': h['duration'] ?? '',
                  'deezerId': h['trackId'] ?? '',
                  'previewUrl': h['previewUrl'] ?? '',
                  'source': 'your_mix',
                });
      }

      final sortedEntries = scores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      for (final entry in sortedEntries) {
        if (playlist.length >= _totalTracks) break;
        final key = entry.key;
        if (recentlyPlayed.contains(key) ||
            recommendLess.contains(key) ||
            usedKeys.contains(key)) {
          continue;
        }
        final info = songMap[key];
        if (info != null) {
          playlist.add(info);
          usedKeys.add(key);
        }
      }
    }

    // Cold start / fill with top tracks from user's favorite & followed artists
    if (playlist.length < _totalTracks && userArtists.isNotEmpty) {
      final needed = _totalTracks - playlist.length;
      final artistTracks =
          await _getUserArtistTracks(userArtists, needed + 6, offset: 0);
      for (final track in artistTracks) {
        if (playlist.length >= _totalTracks) break;
        final key = '${track['title']}|${track['artist']}'.toLowerCase().trim();
        if (!recentlyPlayed.contains(key) &&
            !recommendLess.contains(key) &&
            usedKeys.add(key)) {
          playlist.add(track);
        }
      }
    }

    // If still under 20, fill with top chart tracks
    if (playlist.length < _totalTracks) {
      final charts = await _fetchChartTracks(30);
      for (final track in charts) {
        if (playlist.length >= _totalTracks) break;
        final key = '${track['title']}|${track['artist']}'.toLowerCase().trim();
        if (!recentlyPlayed.contains(key) &&
            !recommendLess.contains(key) &&
            usedKeys.add(key)) {
          playlist.add(track);
        }
      }
    }

    return _interleaveTracksByArtist(playlist);
  }

  // --- Algorithm 2: Discovery Mix (50% fresh discoveries + 50% catalog) ---
  static Future<List<Map<String, dynamic>>> _buildDiscoveryMix({
    required List<Map<String, dynamic>> history,
    required List<String> topGenres,
    required Set<String> recentlyPlayed,
    required Set<String> recommendLess,
    required List<Map<String, String>> userArtists,
    required Set<String> excludeKeys,
  }) async {
    final playlist = <Map<String, dynamic>>[];
    final usedKeys = <String>{...excludeKeys};
    final historyKeys = <String>{};

    for (final h in history) {
      final key = '${h['title']}|${h['artist']}'.toLowerCase().trim();
      if (key != '|') historyKeys.add(key);
    }

    const targetDiscovery = 10;
    const targetFamiliar = 10;

    // 1. First lead with NEW Discovery Tracks (Fresh music you haven't heard)
    final searchQueries = <String>[];
    for (final genre in topGenres) {
      if (genre.isNotEmpty) {
        searchQueries.add('$genre hits');
        searchQueries.add('$genre popular');
      }
    }

    for (var i = 0; i < min(5, userArtists.length); i++) {
      searchQueries.add('${userArtists[i]['name']} similar');
    }

    if (searchQueries.isEmpty) {
      searchQueries.addAll(['Pop hits', 'Indie discovery', 'R&B vibes']);
    }

    int discoveryCount = 0;
    for (final q in searchQueries) {
      if (discoveryCount >= targetDiscovery) break;
      final results = await _searchDeezer(q, 8);
      for (final t in results) {
        if (discoveryCount >= targetDiscovery) break;
        final key = '${t['title']}|${t['artist']}'.toLowerCase().trim();
        if (!historyKeys.contains(key) &&
            !recentlyPlayed.contains(key) &&
            !recommendLess.contains(key) &&
            !excludeKeys.contains(key) &&
            usedKeys.add(key)) {
          playlist.add(t);
          discoveryCount++;
        }
      }
    }

    // 2. Add Familiar/Catalog tracks (offset by 2 so they are different songs from Mix 1)
    if (playlist.length < _totalTracks && userArtists.isNotEmpty) {
      final needed = min(targetFamiliar, _totalTracks - playlist.length);
      final artistTracks =
          await _getUserArtistTracks(userArtists, needed + 6, offset: 2);
      for (final track in artistTracks) {
        if (playlist.length >= _totalTracks) break;
        final key = '${track['title']}|${track['artist']}'.toLowerCase().trim();
        if (!recentlyPlayed.contains(key) &&
            !recommendLess.contains(key) &&
            !excludeKeys.contains(key) &&
            usedKeys.add(key)) {
          playlist.add(track);
        }
      }
    }

    // 3. Fallback fill from unplayed history or chart tracks
    if (playlist.length < _totalTracks) {
      final charts = await _fetchChartTracks(35);
      // Shuffle charts for variety
      charts.shuffle(Random(_today().hashCode + 222));
      for (final track in charts) {
        if (playlist.length >= _totalTracks) break;
        final key = '${track['title']}|${track['artist']}'.toLowerCase().trim();
        if (!recentlyPlayed.contains(key) &&
            !recommendLess.contains(key) &&
            !excludeKeys.contains(key) &&
            usedKeys.add(key)) {
          playlist.add(track);
        }
      }
    }

    return _interleaveTracksByArtist(playlist);
  }

  // --- Algorithm 3: Your Radio (30% artist blend + 70% heavy rotation) ---
  static Future<List<Map<String, dynamic>>> _buildYourRadio({
    required List<Map<String, dynamic>> history,
    required Set<String> recentlyPlayed,
    required Set<String> recommendLess,
    required List<Map<String, String>> userArtists,
    required Set<String> excludeKeys,
  }) async {
    final playlist = <Map<String, dynamic>>[];
    final usedKeys = <String>{...excludeKeys};

    const targetArtistBlend = 8;
    const targetHistory = 12;

    // 1. 30% Blend from top followed and favorite artists (offset 4 for deep cuts)
    if (userArtists.isNotEmpty) {
      final artistTracks = await _getUserArtistTracks(
          userArtists, targetArtistBlend + 6,
          offset: 4);
      for (final track in artistTracks) {
        if (playlist.length >= targetArtistBlend) break;
        final key = '${track['title']}|${track['artist']}'.toLowerCase().trim();
        if (!recentlyPlayed.contains(key) &&
            !recommendLess.contains(key) &&
            !excludeKeys.contains(key) &&
            usedKeys.add(key)) {
          playlist.add(track);
        }
      }
    }

    // 2. 70% Most-played history songs (excluding songs already in Mix 1 or Mix 2)
    if (history.isNotEmpty) {
      final counts = <String, int>{};
      final songMap = <String, Map<String, dynamic>>{};

      for (final h in history) {
        final title = (h['title'] ?? '').toString().trim();
        final artist = (h['artist'] ?? '').toString().trim();
        final key = '$title|$artist'.toLowerCase();
        if (key == '|') continue;

        counts[key] = (counts[key] ?? 0) +
            5 +
            ((h['completed'] == true) ? 15 : 0) +
            ((h['replayed'] == true) ? 10 : 0);

        songMap.putIfAbsent(
            key,
            () => {
                  'title': title,
                  'artist': artist,
                  'image': h['image'] ?? '',
                  'artistId': h['artistId'] ?? '',
                  'artistImage': h['artistImage'] ?? '',
                  'duration': h['duration'] ?? '',
                  'deezerId': h['trackId'] ?? '',
                  'previewUrl': h['previewUrl'] ?? '',
                  'source': 'your_radio',
                });
      }

      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      int addedHistory = 0;
      for (final entry in sorted) {
        if (addedHistory >= targetHistory || playlist.length >= _totalTracks) {
          break;
        }
        final key = entry.key;
        if (recentlyPlayed.contains(key) ||
            recommendLess.contains(key) ||
            excludeKeys.contains(key) ||
            usedKeys.contains(key)) {
          continue;
        }
        final info = songMap[key];
        if (info != null) {
          playlist.add(info);
          usedKeys.add(key);
          addedHistory++;
        }
      }
    }

    // Fill with chart tracks if needed
    if (playlist.length < _totalTracks) {
      final charts = await _fetchChartTracks(40);
      charts.shuffle(Random(_today().hashCode + 333));
      for (final track in charts) {
        if (playlist.length >= _totalTracks) break;
        final key = '${track['title']}|${track['artist']}'.toLowerCase().trim();
        if (!recentlyPlayed.contains(key) &&
            !recommendLess.contains(key) &&
            !excludeKeys.contains(key) &&
            usedKeys.add(key)) {
          playlist.add(track);
        }
      }
    }

    return _interleaveTracksByArtist(playlist);
  }

  static Future<List<Map<String, dynamic>>> getDailyMixes(
      {bool force = false}) async {
    final today = _today();

    if (force) {
      clearDailyMixesCache();
    } else {
      // 1. Return from memory or disk cache if already loaded for today
      await _loadDailyMixesFromDisk();
      if (_dailyMixesCache.isNotEmpty && _dailyMixesDate == today) {
        final hasSongs = _dailyMixesCache.values
            .any((m) => (m['songs'] as List<dynamic>? ?? []).isNotEmpty);
        if (hasSongs) {
          return _dailyMixesToMapList();
        }
      }
    }

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return _dailyMixesToMapList();

      // 2. Check Supabase daily_playlists table for today's generated mixes
      if (_dailyMixesCache.isEmpty) {
        try {
          final existingRows = await Supabase.instance.client
              .from('daily_playlists')
              .select()
              .eq('user_id', user.id)
              .inFilter('genre', ['daily_mix_1', 'daily_mix_2', 'daily_mix_3'])
              .eq('playlist_date', today)
              .timeout(const Duration(seconds: 8));

          final rows = existingRows as List<dynamic>? ?? [];
          if (rows.length >= 3) {
            _dailyMixesCache.clear();
            for (final r in rows) {
              final g = (r['genre'] ?? '').toString();
              final songs = (r['songs'] as List<dynamic>? ?? [])
                  .where(TrackFilter.isAllowedMap)
                  .map((s) => Map<String, dynamic>.from(s as Map))
                  .toList();
              final num = int.tryParse(g.replaceAll('daily_mix_', '')) ?? 1;
              _dailyMixesCache[num.toString()] = {
                'number': num,
                'name': num == 1
                    ? 'Your Mix'
                    : num == 2
                        ? 'Discovery Mix'
                        : 'Your Radio',
                'description': num == 1
                    ? 'Songs you know and love'
                    : num == 2
                        ? 'Your favorites plus new finds'
                        : 'Your top artists and most-played songs',
                'songs': songs,
              };
            }
            _dailyMixesDate = today;
            await _saveDailyMixesToDisk();
            return _dailyMixesToMapList();
          }
        } catch (e) {
          debugPrint('[Vibe] Supabase daily mixes fetch error: $e');
        }
      }

      // 3. Generate 3 unique mixes on frontend using dedicated algorithms
      final history = await ListeningHistoryService.getHistory(days: 30);
      final userArtists = await _getUserFavoriteArtists();
      final recommendLess =
          await ListeningHistoryService.getAllRecommendLessKeys();

      // Recently played (last 3 days)
      final threeDaysAgo =
          DateTime.now().toUtc().subtract(const Duration(days: 3));
      final recentlyPlayed = <String>{};
      for (final h in history) {
        final createdAtStr = h['created_at']?.toString() ?? '';
        if (createdAtStr.isNotEmpty) {
          final dt = DateTime.tryParse(createdAtStr);
          if (dt != null && dt.isAfter(threeDaysAgo)) {
            final key = '${h['title']}|${h['artist']}'.toLowerCase().trim();
            if (key != '|') recentlyPlayed.add(key);
          }
        }
      }

      // User top genres from profile
      List<String> userGenres = [];
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('favorite_genres')
            .eq('id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 6));
        userGenres = (profile?['favorite_genres'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
      } catch (e) {
        debugPrint('[Vibe] Profile favorite_genres fetch error: $e');
      }
      if (userGenres.isEmpty) {
        userGenres = ['Pop', 'Hip Hop', 'R&B'];
      }

      // Mix 1: "Your Mix" (Personal favorites & heavy rotation)
      final mix1Songs = await _buildYourMix(
        history: history,
        recentlyPlayed: recentlyPlayed,
        recommendLess: recommendLess,
        userArtists: userArtists,
      );

      final mix1Keys = <String>{};
      for (final s in mix1Songs) {
        final key = '${s['title']}|${s['artist']}'.toLowerCase().trim();
        if (key != '|') mix1Keys.add(key);
      }

      // Mix 2: "Discovery Mix" (Brand new tracks first, zero overlap with Mix 1)
      final mix2Songs = await _buildDiscoveryMix(
        history: history,
        topGenres: userGenres,
        recentlyPlayed: recentlyPlayed,
        recommendLess: recommendLess,
        userArtists: userArtists,
        excludeKeys: mix1Keys,
      );

      final mix2Keys = <String>{...mix1Keys};
      for (final s in mix2Songs) {
        final key = '${s['title']}|${s['artist']}'.toLowerCase().trim();
        if (key != '|') mix2Keys.add(key);
      }

      // Mix 3: "Your Radio" (Artist variety & deep cuts, zero overlap with Mix 1 or Mix 2)
      final mix3Songs = await _buildYourRadio(
        history: history,
        recentlyPlayed: recentlyPlayed,
        recommendLess: recommendLess,
        userArtists: userArtists,
        excludeKeys: mix2Keys,
      );

      final newMixes = <String, Map<String, dynamic>>{
        '1': {
          'number': 1,
          'name': 'Your Mix',
          'description': 'Songs you know and love',
          'songs': mix1Songs,
        },
        '2': {
          'number': 2,
          'name': 'Discovery Mix',
          'description': 'Your favorites plus new finds',
          'songs': mix2Songs,
        },
        '3': {
          'number': 3,
          'name': 'Your Radio',
          'description': 'Your top artists and most-played songs',
          'songs': mix3Songs,
        },
      };

      _dailyMixesCache = newMixes;
      _dailyMixesDate = today;
      await _saveDailyMixesToDisk();

      // Save to Supabase in background
      for (var i = 1; i <= 3; i++) {
        final songs = newMixes[i.toString()]?['songs'] as List<dynamic>? ?? [];
        if (songs.isNotEmpty) {
          _savePlaylist('daily_mix_$i',
              songs.map((s) => Map<String, dynamic>.from(s as Map)).toList());
        }
      }

      return _dailyMixesToMapList();
    } catch (e) {
      debugPrint('[Vibe] Daily mixes generation error: $e');
    }
    return _dailyMixesToMapList();
  }

  static List<Map<String, dynamic>> _dailyMixesToMapList() {
    final list = _dailyMixesCache.values.map((mix) {
      final songs = (mix['songs'] as List<dynamic>? ?? [])
          .where(TrackFilter.isAllowedMap)
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
      return {
        ...mix,
        'songs': songs,
      };
    }).toList();
    list.sort((a, b) =>
        ((a['number'] as int?) ?? 0).compareTo((b['number'] as int?) ?? 0));
    return list;
  }

  static List<Map<String, dynamic>> getDailyMixSongs(int mixNumber) {
    final mix = _dailyMixesCache[mixNumber.toString()];
    final songs = mix?['songs'] as List<dynamic>? ?? [];
    return songs
        .where(TrackFilter.isAllowedMap)
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();
  }

  static Future<bool> get hasDailyMixesToday async {
    if (_dailyMixesCache.isNotEmpty && _dailyMixesDate == _today()) return true;
    await _loadDailyMixesFromDisk();
    return _dailyMixesCache.isNotEmpty && _dailyMixesDate == _today();
  }

  static bool get dailyMixesStale {
    if (_dailyMixesCache.isEmpty || _dailyMixesDate != _today()) return true;
    final hasSongs = _dailyMixesCache.values
        .any((m) => (m['songs'] as List<dynamic>? ?? []).isNotEmpty);
    return !hasSongs;
  }

  static void clearDailyMixesCache() {
    _dailyMixesCache.clear();
    _dailyMixesDate = null;
  }

  static List<Map<String, dynamic>> getDailyMixesFromCache() {
    return _dailyMixesToMapList();
  }
}
