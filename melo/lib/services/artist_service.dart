import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'search_service.dart';

class ArtistService {
  static const _apiBase = 'https://api.deezer.com';

  static final Map<String, _CacheEntry> _cache = {};
  static const Duration _cacheTtl = Duration(minutes: 30);

  static _CacheEntry? _getCached(String key) {
    final entry = _cache[key];
    if (entry != null && !entry.isExpired) return entry;
    _cache.remove(key);
    return null;
  }

  static void _setCache(String key, dynamic data) {
    _cache[key] = _CacheEntry(data);
  }

  static void clearCache() {
    _cache.clear();
  }

  static Future<Map<String, dynamic>?> getArtistInfo(String artistId) async {
    final cached = _getCached('artist_info_$artistId');
    if (cached != null) return cached.data;

    try {
      final resp = await http.get(
        Uri.parse('$_apiBase/artist/$artistId'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        _setCache('artist_info_$artistId', data);
        return data;
      }
    } catch (e) {
      debugPrint('[Artist] Info error for $artistId: $e');
    }
    return null;
  }

  static Future<List<SearchResult>> getArtistTopTracks(String artistId,
      {int limit = 10}) async {
    final cached = _getCached('artist_tracks_$artistId');
    if (cached != null) return List<SearchResult>.from(cached.data);

    try {
      final resp = await http.get(
        Uri.parse('$_apiBase/artist/$artistId/top?limit=$limit'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final tracks = (data['data'] as List? ?? [])
            .map((item) => SearchResult.fromDeezerTrack(item))
            .toList();
        if (tracks.length >= 5) {
          _setCache('artist_tracks_$artistId', tracks);
          return tracks;
        }
      }
    } catch (e) {
      debugPrint('[Artist] Top tracks error for $artistId: $e');
    }

    // Japanese Eve (69128312) has a known Deezer defect where /top returns only 1 track
    if (artistId == '69128312') {
      try {
        final eveTracks = await _fetchJapaneseEveTracks(limit: limit);
        if (eveTracks.isNotEmpty) {
          _setCache('artist_tracks_$artistId', eveTracks);
          return eveTracks;
        }
      } catch (e) {
        debugPrint('[Artist] Japanese Eve top tracks error: $e');
      }
    }

    // Fallback: If /top returns empty (e.g. artist is geo-blocked on Deezer),
    // fetch artist info and query Deezer search for the artist's tracks.
    // Filter by artist ID to avoid same-name collisions (e.g. "Eve" JP vs US).
    try {
      final info = await getArtistInfo(artistId);
      final name = info?['name']?.toString() ?? '';
      if (name.isNotEmpty) {
        final searchTracks = (await searchTracksByArtist(name, limit: limit))
            .where((t) => t.artistId.isEmpty || t.artistId == artistId)
            .toList();
        if (searchTracks.isNotEmpty) {
          _setCache('artist_tracks_$artistId', searchTracks);
          return searchTracks;
        }
      }
    } catch (e) {
      debugPrint('[Artist] Fallback top tracks error for $artistId: $e');
    }

    return [];
  }

  /// Extended top-tracks fetch (bigger limit, separate cache key) — used to
  /// top up artist pages where /top?limit=10 returns fewer than 10 songs.
  static Future<List<SearchResult>> getExtendedTopTracks(String artistId,
      {int limit = 30}) async {
    final cached = _getCached('artist_tracks_${artistId}_x$limit');
    if (cached != null) return List<SearchResult>.from(cached.data);

    if (artistId == '69128312') {
      try {
        final eveTracks = await _fetchJapaneseEveTracks(limit: limit);
        if (eveTracks.isNotEmpty) {
          _setCache('artist_tracks_${artistId}_x$limit', eveTracks);
          return eveTracks;
        }
      } catch (e) {
        debugPrint('[Artist] Extended Japanese Eve top tracks error: $e');
      }
    }

    try {
      final resp = await http.get(
        Uri.parse('$_apiBase/artist/$artistId/top?limit=$limit'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final tracks = (data['data'] as List? ?? [])
            .map((item) => SearchResult.fromDeezerTrack(item))
            .toList();
        _setCache('artist_tracks_${artistId}_x$limit', tracks);
        return tracks;
      }
    } catch (e) {
      debugPrint('[Artist] Extended top tracks error for $artistId: $e');
    }
    return [];
  }

  /// Find an artist's tracks via general search — fallback for topping up
  /// pages whose /top endpoint is sparse (small catalog or duplicate entry),
  /// or when an artist is geo-blocked on Deezer in regions like Cambodia.
  static Future<List<SearchResult>> searchTracksByArtist(String artistName,
      {int limit = 25}) async {
    if (artistName.trim().isEmpty) return [];

    String norm(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final target = norm(artistName);

    // 1. Try Deezer search
    try {
      final resp = await http.get(
        Uri.parse(
            '$_apiBase/search?q=${Uri.encodeComponent(artistName.trim())}&limit=$limit'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 4));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final isEve = target == 'eve' || target == 'いぶ';
        final list = (data['data'] as List? ?? [])
            .map((item) => SearchResult.fromDeezerTrack(item))
            .where((t) {
          if (norm(t.artist) != target) return false;
          if (isEve) {
            // Must never return American Eve (837) songs
            if (t.artistId == '837') return false;
            final tLower = t.title.toLowerCase();
            if (tLower.contains('blow ya mind') ||
                tLower.contains("who's that girl") ||
                tLower.contains('gangsta lovin') ||
                tLower.contains('what you need') ||
                tLower.contains('tambourine') ||
                tLower.contains('rich girl')) {
              return false;
            }
          }
          return true;
        }).toList();
        if (list.isNotEmpty) return list;
      }
    } catch (e) {
      debugPrint('[Artist] Track search error for $artistName: $e');
    }

    return [];
  }

  static Future<List<Map<String, dynamic>>> getArtistAlbums(
      String artistId) async {
    final cached = _getCached('artist_albums_$artistId');
    if (cached != null) return List<Map<String, dynamic>>.from(cached.data);

    try {
      final resp = await http.get(
        Uri.parse('$_apiBase/artist/$artistId/albums'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        // Normalize list items for the UI: cover_* → image, release_date → year.
        final albums = (data['data'] as List? ?? []).map((a) {
          if (a is Map<String, dynamic>) {
            final date = a['release_date']?.toString() ?? '';
            return <String, dynamic>{
              ...a,
              'image':
                  a['cover_big'] ?? a['cover_medium'] ?? a['cover_xl'] ?? '',
              'year': date.length >= 4 ? date.substring(0, 4) : '',
            };
          }
          return a;
        }).toList();
        _setCache('artist_albums_$artistId', albums);
        return List<Map<String, dynamic>>.from(albums);
      }
    } catch (e) {
      debugPrint('[Artist] Albums error for $artistId: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> getAlbumInfo(String albumId) async {
    final cached = _getCached('album_info_$albumId');
    if (cached != null) return cached.data;

    try {
      final resp = await http.get(
        Uri.parse('$_apiBase/album/$albumId'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map<String, dynamic>) {
          // UI reads camelCase keys — alias Deezer's snake_case fields.
          data['nbTracks'] = data['nb_tracks'];
          data['xlImage'] = data['cover_xl'];
          data['bigImage'] = data['cover_xl'] ?? data['cover_big'];
          data['image'] = data['cover_xl'] ?? data['cover_big'] ?? '';
        }
        _setCache('album_info_$albumId', data);
        return data;
      }
    } catch (e) {
      debugPrint('[Album] Info error for $albumId: $e');
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> getAlbumTracks(
      String albumId) async {
    final cached = _getCached('album_tracks_$albumId');
    if (cached != null) return List<Map<String, dynamic>>.from(cached.data);

    try {
      final resp = await http.get(
        Uri.parse('$_apiBase/album/$albumId/tracks'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        // Flatten each track: Deezer nests the artist as an object and uses a
        // raw seconds duration — the UI expects plain string fields.
        final tracks = (data['data'] as List? ?? []).map((item) {
          if (item is! Map<String, dynamic>) return item;
          final artistNode = item['artist'] as Map<String, dynamic>? ?? {};
          final secs = int.tryParse('${item['duration']}') ?? 0;
          return <String, dynamic>{
            ...item,
            'artist': artistNode['name']?.toString() ?? '',
            'artistId': artistNode['id']?.toString() ?? '',
            'artistImage':
                artistNode['picture_medium'] ?? artistNode['picture_big'] ?? '',
            'duration':
                '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
            'preview': item['preview'] ?? '',
          };
        }).toList();
        _setCache('album_tracks_$albumId', tracks);
        return List<Map<String, dynamic>>.from(tracks);
      }
    } catch (e) {
      debugPrint('[Album] Tracks error for $albumId: $e');
    }
    return [];
  }

  /// Search for artists on Deezer directly.
  static Future<List<SearchResult>> searchArtists(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final encoded = Uri.encodeComponent(query.trim());
      final resp = await http.get(
        Uri.parse('$_apiBase/search/artist?q=$encoded&limit=15'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final results = data['data'] as List? ?? [];
        final list =
            results.map((item) => SearchResult.fromDeezerArtist(item)).toList();

        final qLower = query.trim().toLowerCase();
        if (qLower == 'eve' || query.trim() == 'いぶ') {
          list.removeWhere((a) => a.id == '69128312' || a.id == '69127962');
          list.insert(
            0,
            SearchResult(
              type: 'artist',
              id: '69128312',
              title: 'Eve',
              artist: 'Eve',
              artistId: '69128312',
              artistImage:
                  'https://cdn-images.dzcdn.net/images/artist/d338715a1c099cecc59363cd8c68ae3d/1000x1000-000000-80-0-0.jpg',
              image:
                  'https://cdn-images.dzcdn.net/images/artist/d338715a1c099cecc59363cd8c68ae3d/1000x1000-000000-80-0-0.jpg',
              duration: '',
              nbFan: 69898,
              previewUrl: '',
            ),
          );
        }
        return list;
      }
    } catch (e) {
      debugPrint('[Artist] Search error: $e');
    }
    return [];
  }

  /// Resolve an artist NAME to its real Deezer entry.
  ///
  /// Since Feb 2026 Deezer's search ranking often puts duplicate/tribute
  /// entries (exact same name, tiny fan counts like 85) ahead of the real
  /// artist, so `limit=1` is unsafe. Among exact-name matches the real
  /// artist reliably has the most fans — pick that one.
  static Future<Map<String, dynamic>?> resolveArtist(String name) async {
    final query = name.trim();
    if (query.isEmpty) return null;

    String norm(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

    final target = norm(query);

    // Explicit disambiguation: Japanese singer-songwriter Eve (Jujutsu Kaisen, MHA, Chainsaw Man)
    if (target == 'eve' || query.trim() == 'いぶ') {
      return <String, dynamic>{
        'id': '69128312',
        'name': 'Eve',
        'image':
            'https://cdn-images.dzcdn.net/images/artist/d338715a1c099cecc59363cd8c68ae3d/1000x1000-000000-80-0-0.jpg',
        'nb_fan': 69898,
      };
    }

    try {
      final resp = await http.get(
        Uri.parse(
            '$_apiBase/search/artist?q=${Uri.encodeComponent(query)}&limit=10'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      final hits = data['data'] as List? ?? [];
      if (hits.isEmpty) return null;

      Map<String, dynamic>? best;
      var bestFans = -1;
      for (final h in hits) {
        if (norm((h['name'] ?? '').toString()) != target) continue;
        final fans = (h['nb_fan'] as num?)?.toInt() ?? 0;
        if (fans > bestFans) {
          bestFans = fans;
          best = <String, dynamic>{
            'id': h['id']?.toString() ?? '',
            'name': h['name']?.toString() ?? query,
            'image':
                (h['picture_big'] ?? h['picture_medium'] ?? '')?.toString() ??
                    '',
            'nb_fan': fans,
          };
        }
      }

      // No exact-name match — only fall back to Deezer's first hit if the name is closely related
      if (best == null && hits.isNotEmpty) {
        final firstHitName = norm((hits[0]['name'] ?? '').toString());
        if (firstHitName.contains(target) || target.contains(firstHitName)) {
          best = <String, dynamic>{
            'id': hits[0]['id']?.toString() ?? '',
            'name': hits[0]['name']?.toString() ?? query,
            'image': (hits[0]['picture_big'] ?? hits[0]['picture_medium'] ?? '')
                    ?.toString() ??
                '',
            'nb_fan': (hits[0]['nb_fan'] as num?)?.toInt() ?? 0,
          };
        }
      }
      return (best != null && (best['id'] as String).isNotEmpty) ? best : null;
    } catch (e) {
      debugPrint('[Artist] Resolve error for "$name": $e');
      return null;
    }
  }

  /// Search for artists on Deezer, returning raw maps for backward compatibility.
  static Future<List<Map<String, dynamic>>> searchArtistsAsMaps(
      String query) async {
    final results = await searchArtists(query);
    return results
        .map((r) => {
              'id': r.id,
              'type': r.type,
              'name': r.title,
              'picture_big': r.artistImage,
              'nb_fan': r.nbFan,
            })
        .toList();
  }

  /// Get curated artists for given genres from the local artists.json asset.
  /// Resolves each artist on Deezer using exact ID when available to guarantee
  /// the correct artist identity and image.
  static Future<List<Map<String, dynamic>>> getCuratedArtists(
      List<String> genres) async {
    try {
      final jsonStr = await rootBundle.loadString('asset/data/artists.json');
      final allData = jsonDecode(jsonStr) as Map<String, dynamic>;

      final seenNames = <String>{};
      final curated = <Map<String, dynamic>>[];
      for (final genre in genres.take(6)) {
        final genreArtists = allData[genre] as List<dynamic>? ?? [];
        for (final a in genreArtists) {
          final name = a['name']?.toString().trim() ?? '';
          if (name.isNotEmpty && seenNames.add(name.toLowerCase())) {
            curated.add({
              'id': a['id']?.toString() ?? '',
              'name': name,
              'image': a['image']?.toString() ?? '',
            });
          }
        }
      }

      // Resolve each artist on Deezer in parallel (batch of 5)
      final resolved = <Map<String, dynamic>>[];
      final seenIds = <String>{};
      for (var i = 0; i < curated.length; i += 5) {
        final batch = curated.sublist(
            i, (i + 5 > curated.length) ? curated.length : i + 5);
        final results = await Future.wait(batch.map((a) async {
          final aid = a['id']?.toString().trim() ?? '';
          final aImage = a['image']?.toString().trim() ?? '';
          final aName = a['name']?.toString().trim() ?? '';

          // 1. If we already have both a Deezer ID and a valid image URL, use it directly
          if (aid.isNotEmpty && aImage.isNotEmpty) {
            return <String, dynamic>{
              'id': aid,
              'name': aName,
              'image': aImage,
              'nb_fan': 0,
            };
          }

          // 2. If ID is valid but image is missing, fetch by ID directly (never misidentifies)
          if (aid.isNotEmpty) {
            try {
              final info = await getArtistInfo(aid);
              if (info != null) {
                final pic = (info['picture_big'] ??
                            info['picture_medium'] ??
                            info['picture'] ??
                            '')
                        ?.toString() ??
                    '';
                return <String, dynamic>{
                  'id': aid,
                  'name': info['name']?.toString() ?? aName,
                  'image': pic.isNotEmpty ? pic : aImage,
                  'nb_fan': (info['nb_fan'] as num?)?.toInt() ?? 0,
                };
              }
            } catch (_) {}
          }

          // 3. Fallback: only if ID was empty or info failed, resolve by name
          try {
            final hit = await resolveArtist(aName);
            if (hit != null) {
              return <String, dynamic>{
                'id': hit['id'],
                'name': hit['name'] ?? aName,
                'image':
                    hit['image'].toString().isNotEmpty ? hit['image'] : aImage,
                'nb_fan': hit['nb_fan'] ?? 0,
              };
            }
          } catch (_) {}

          return <String, dynamic>{
            'id': aid,
            'name': aName,
            'image': aImage,
            'nb_fan': 0,
          };
        }));
        for (final r in results) {
          final id = r['id']?.toString() ?? '';
          if (id.isNotEmpty && seenIds.add(id)) {
            resolved.add(r);
          }
        }
      }
      return resolved;
    } catch (e) {
      debugPrint('[Artist] getCuratedArtists error: $e');
      return [];
    }
  }

  /// Deezer's /artist/69128312/top endpoint has an indexing defect on Deezer's
  /// servers (only returns 1 song), even though Japanese Eve has 37 full albums
  /// and massive anime hits. Fetch his top albums to populate his hit songs catalog.
  static Future<List<SearchResult>> _fetchJapaneseEveTracks(
      {int limit = 20}) async {
    const eveAlbumIds = [
      '190575092', // Kaikai Kitan / Ao No Waltz (Jujutsu Kaisen, Josee)
      '413691027', // Bokurano (My Hero Academia)
      '298076772', // Kaizin
      '199101422', // Smile
      '199098832', // Otogi
    ];

    final tracks = <SearchResult>[];
    final seen = <String>{};

    for (final albId in eveAlbumIds) {
      if (tracks.length >= limit) break;
      try {
        final albumTracks = await getAlbumTracks(albId);
        for (final item in albumTracks) {
          if (tracks.length >= limit) break;
          final title = item['title']?.toString() ?? '';
          if (title.isEmpty) continue;
          final key = title.toLowerCase().trim();
          if (seen.add(key)) {
            final tId = item['id']?.toString() ?? '';
            final albCover = item['image']?.toString() ??
                'https://cdn-images.dzcdn.net/images/artist/d338715a1c099cecc59363cd8c68ae3d/500x500-000000-80-0-0.jpg';
            tracks.add(SearchResult(
              type: 'song',
              id: tId,
              title: title,
              artist: 'Eve',
              artistId: '69128312',
              artistImage:
                  'https://cdn-images.dzcdn.net/images/artist/d338715a1c099cecc59363cd8c68ae3d/500x500-000000-80-0-0.jpg',
              image: albCover,
              duration: item['duration']?.toString() ?? '',
              nbFan: 69898,
              previewUrl: item['preview']?.toString() ?? '',
              albumId: albId,
              albumTitle: item['album']?['title']?.toString() ?? '',
              albumCover: albCover,
            ));
          }
        }
      } catch (e) {
        debugPrint('[Artist] Eve album $albId fetch error: $e');
      }
    }
    return tracks;
  }
}

class _CacheEntry {
  final dynamic data;
  final DateTime createdAt;
  _CacheEntry(this.data) : createdAt = DateTime.now();
  bool get isExpired =>
      DateTime.now().difference(createdAt) > ArtistService._cacheTtl;
}
