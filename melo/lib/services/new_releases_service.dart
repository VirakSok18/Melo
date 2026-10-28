import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'artist_service.dart';

/// Frontend-only New Releases generator (no Spring backend needed).
///
/// Port of the backend's 3-tier algorithm, using Deezer endpoints that still
/// work as of Feb 2026 (/album/new and the charts/albums lists are dead):
///   Tier 1 — user's favorite artists → their newest album tracks
///   Tier 2 — "Because you like <genre>" → curated genre artists' newest tracks
///   Tier 3 — live Deezer chart fill
class NewReleasesService {
  static List<dynamic>? _cachedSongs;
  static String? _cacheDate;
  static const String _prefsKey = 'new_releases_cache';
  static const String _prefsDateKey = 'new_releases_cache_date';
  static const _deezerApi = 'https://api.deezer.com';

  /// asset/data/artists.json — genre → curated artists (with Deezer names)
  static Map<String, dynamic>? _genreArtistsJson;

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  static Future<void> _loadPrefsCache() async {
    if (_cachedSongs != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        _cachedSongs = jsonDecode(raw) as List<dynamic>;
        _cacheDate = prefs.getString(_prefsDateKey);
      }
    } catch (e) {
      print('New releases prefs load error: $e');
    }
  }

  static Future<void> _savePrefsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsDateKey, _today());
      await prefs.setString(_prefsKey, jsonEncode(_cachedSongs));
    } catch (e) {
      print('New releases prefs save error: $e');
    }
  }

  static Future<Map<String, dynamic>> _loadGenreArtists() async {
    if (_genreArtistsJson != null) return _genreArtistsJson!;
    final raw = await rootBundle.loadString('asset/data/artists.json');
    _genreArtistsJson = jsonDecode(raw) as Map<String, dynamic>;
    return _genreArtistsJson!;
  }

  static Future<List<dynamic>> getCachedReleases() async {
    if (_cachedSongs != null && _cachedSongs!.isNotEmpty) return _cachedSongs!;
    await _loadPrefsCache();
    return _cachedSongs ?? [];
  }

  static Future<List<dynamic>> fetchNewReleases({bool force = false}) async {
    // Always load prefs cache first so we have offline data immediately
    await _loadPrefsCache();

    if (!force) {
      if (_cachedSongs != null &&
          _cachedSongs!.isNotEmpty &&
          _cacheDate == _today()) {
        return _cachedSongs!;
      }
    }

    try {
      final generated = await _generate();

      // Never persist an empty result — a network blip would otherwise blank
      // the section for the rest of the day.
      if (generated.isNotEmpty) {
        _cachedSongs = generated;
        _cacheDate = _today();
        await _savePrefsCache();
        return _cachedSongs!;
      }
    } catch (e) {
      print('New releases fetch error (offline / network): $e');
    }
    return _cachedSongs ?? [];
  }

  // ------------------------------------------------------------------
  // Generation (mirrors backend NewReleasesService.generateReleases)
  // ------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> _generate() async {
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};

    // Parallel fetch: Fresh Finds drops + Profile favorite artists + genres
    final freshFindsFuture = _fetchFreshFindsList(5);
    final favArtistsFuture = _getFavoriteArtists();
    final favGenresFuture = _getFavoriteGenres();

    final outcomes = await Future.wait([
      freshFindsFuture,
      favArtistsFuture,
      favGenresFuture,
    ]);

    final freshFinds = outcomes[0] as List<Map<String, dynamic>>;
    final favArtists = outcomes[1] as List<Map<String, dynamic>>;
    final favGenres = outcomes[2] as List<String>;

    for (final track in freshFinds) {
      _pushUnique(result, seen, track);
    }

    // Tier 2: Fetch favorite/followed artists' newest releases IN PARALLEL
    final artistsToQuery = favArtists.take(5).where((a) {
      final name = a['name']?.toString() ?? '';
      return name.isNotEmpty && !seen.contains(name.toLowerCase());
    }).toList();

    if (artistsToQuery.isNotEmpty) {
      final artistTrackFutures = artistsToQuery
          .map((a) => _newestTracksByArtist(a['name']?.toString() ?? '', 2));
      final perArtistResults = await Future.wait(artistTrackFutures);

      final perArtist =
          perArtistResults.where((list) => list.isNotEmpty).toList();
      final maxLen = perArtist.fold<int>(
          0, (max, list) => list.length > max ? list.length : max);
      for (var i = 0; i < maxLen && result.length < 10; i++) {
        for (final list in perArtist) {
          if (result.length >= 10) break;
          if (i < list.length) _pushUnique(result, seen, list[i]);
        }
      }
    }

    // Tier 3: Curated artists in user's favorite genre (fetched concurrently)
    if (favGenres.isNotEmpty && result.length < 14) {
      try {
        final genreArtists = await _loadGenreArtists();
        final nodes = genreArtists[favGenres.first];
        if (nodes is List) {
          final genreArtistCandidates = <Map<String, dynamic>>[];
          for (final node in nodes) {
            final name = node['name']?.toString() ?? '';
            final id = node['id']?.toString() ?? '';
            if (name.isNotEmpty && !seen.contains(name.toLowerCase())) {
              genreArtistCandidates.add({'name': name, 'id': id});
              if (genreArtistCandidates.length >= 4) break;
            }
          }

          final genreFutures = genreArtistCandidates.map((cand) =>
              _newestTracksByArtist(cand['name']!, 2, knownId: cand['id']));
          final genreResults = await Future.wait(genreFutures);

          for (final tracks in genreResults) {
            for (final t in tracks) {
              if (result.length >= 14) break;
              _pushUnique(result, seen, t);
            }
            if (result.length >= 14) break;
          }
        }
      } catch (e) {
        print('[NewReleases] Genre releases failed: $e');
      }
    }

    // Tier 4: Global Fresh Chart Releases
    if (result.length < 14) {
      await _chartFill(result, seen, 14);
    }
    return result;
  }

  static void _pushUnique(List<Map<String, dynamic>> result, Set<String> seen,
      Map<String, dynamic> track) {
    final id = (track['id'] ?? track['trackId'] ?? track['deezerId'] ?? '')
        .toString()
        .trim();
    if (id.isEmpty || id == '0' || id == '-1' || id.toLowerCase() == 'null') {
      return;
    }
    final title = (track['title'] ?? '').toString().trim();
    if (title.isEmpty) return;

    final key = '$title|${track['artist']}'.toLowerCase();
    if (seen.add(key)) result.add(track);
  }

  // ------------------------------------------------------------------
  // Profile inputs (Supabase direct — same pattern as VibeService)
  // ------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> _getFavoriteArtists() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return [];
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('favorite_artists')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      final raw = profile?['favorite_artists'] as List<dynamic>? ?? [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map((a) => {'name': (a['name'] ?? '').toString()})
          .where((a) => (a['name'] as String).isNotEmpty)
          .toList();
    } catch (e) {
      print('[NewReleases] Failed to load favorite artists: $e');
      return [];
    }
  }

  static Future<List<String>> _getFavoriteGenres() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('profile_favorite_genres');
      if (cached != null && cached.isNotEmpty) {
        return (jsonDecode(cached) as List<dynamic>)
            .map((g) => g.toString())
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ------------------------------------------------------------------
  // Deezer calls (all verified working endpoints)
  // ------------------------------------------------------------------

  /// Newest tracks of an artist: resolve the real Deezer ID → albums sorted
  /// by release_date_desc → tracks of the newest album.
  static Future<List<Map<String, dynamic>>> _newestTracksByArtist(
      String artistName, int maxTracks,
      {String? knownId}) async {
    final tracks = <Map<String, dynamic>>[];
    try {
      String? artistId = knownId;
      String? artistImage;
      if (artistId == null || artistId.isEmpty) {
        final resolved = await ArtistService.resolveArtist(artistName);
        if (resolved == null) return tracks;
        artistId = resolved['id'];
        artistImage = resolved['image'];
      }

      final albumsResp = await http.get(
        Uri.parse(
            '$_deezerApi/artist/$artistId/albums?limit=5&sort=release_date_desc'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 4));

      if (albumsResp.statusCode != 200) return tracks;
      final albumsJson = jsonDecode(albumsResp.body);
      final albums = albumsJson['data'] as List? ?? [];
      if (albums.isEmpty) return tracks;

      final album = albums[0];
      final albumId = album['id'];
      final albumCover = album['cover_big'] ?? album['cover_medium'] ?? '';

      final tracksResp = await http.get(
        Uri.parse('$_deezerApi/album/$albumId/tracks?limit=$maxTracks'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 4));

      if (tracksResp.statusCode == 200) {
        final tracksJson = jsonDecode(tracksResp.body);
        for (final item in (tracksJson['data'] as List? ?? [])) {
          if (tracks.length >= maxTracks) break;
          final artistNode = item['artist'] as Map<String, dynamic>? ?? {};
          tracks.add({
            'id': item['id']?.toString() ?? '',
            'title': item['title'] ?? '',
            'artist': (artistNode['name'] ?? artistName).toString(),
            'artistId': artistId.toString(),
            'artistImage': artistImage ??
                artistNode['picture_big'] ??
                artistNode['picture_medium'] ??
                '',
            'image': albumCover,
            'duration': _formatDuration(item['duration']),
            'previewUrl': item['preview'] ?? '',
          });
        }
      }
    } catch (e) {
      print('[NewReleases] Newest tracks for "$artistName" failed: $e');
    }
    return tracks;
  }

  static Future<List<Map<String, dynamic>>> _fetchFreshFindsList(
      int limit) async {
    final list = <Map<String, dynamic>>[];
    try {
      final resp = await http.get(
        Uri.parse('$_deezerApi/playlist/13626132781/tracks?limit=20'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 4));

      if (resp.statusCode != 200) return list;
      final data = jsonDecode(resp.body);
      final tracks = data['data'] as List? ?? [];

      for (final t in tracks) {
        if (list.length >= limit) break;
        final artist = t['artist'] as Map<String, dynamic>? ?? {};
        final album = t['album'] as Map<String, dynamic>? ?? {};
        list.add({
          'id': t['id']?.toString() ?? '',
          'title': t['title'] ?? '',
          'artist': artist['name'] ?? '',
          'artistId': artist['id']?.toString() ?? '',
          'artistImage':
              artist['picture_big'] ?? artist['picture_medium'] ?? '',
          'image': album['cover_big'] ?? album['cover_medium'] ?? '',
          'duration': _formatDuration(t['duration']),
          'previewUrl': t['preview'] ?? '',
        });
      }
    } catch (e) {
      print('[NewReleases] Fresh finds fetch failed: $e');
    }
    return list;
  }

  static Future<void> _chartFill(
      List<Map<String, dynamic>> result, Set<String> seen, int target) async {
    try {
      final resp = await http.get(
        Uri.parse('$_deezerApi/chart/0/tracks?limit=${target * 2}'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body);
      for (final t in (data['data'] as List? ?? [])) {
        if (result.length >= target) break;
        final artist = t['artist'] as Map<String, dynamic>? ?? {};
        final album = t['album'] as Map<String, dynamic>? ?? {};
        _pushUnique(result, seen, {
          'id': t['id']?.toString() ?? '',
          'title': t['title'] ?? '',
          'artist': artist['name'] ?? '',
          'artistId': artist['id']?.toString() ?? '',
          'artistImage':
              artist['picture_big'] ?? artist['picture_medium'] ?? '',
          'image': album['cover_big'] ?? album['cover_medium'] ?? '',
          'duration': _formatDuration(t['duration']),
          'previewUrl': t['preview'] ?? '',
        });
      }
    } catch (e) {
      print('[NewReleases] Chart fill failed: $e');
    }
  }

  static String _formatDuration(dynamic seconds) {
    final s = int.tryParse('$seconds') ?? 0;
    final min = s ~/ 60;
    final sec = s % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  /// True when there is no list for TODAY — used by the home screen to decide
  /// whether a resume should regenerate (memory only; disk is checked inside
  /// fetchNewReleases anyway).
  static bool get isStale =>
      _cachedSongs == null || _cachedSongs!.isEmpty || _cacheDate != _today();

  static Future<void> clearCache() async {
    _cachedSongs = null;
    _cacheDate = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      await prefs.remove(_prefsDateKey);
    } catch (e) {
      print('New releases prefs clear error: $e');
    }
  }
}
