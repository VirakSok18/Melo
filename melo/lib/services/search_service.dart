import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../utils/track_filter.dart';

class SearchResult {
  final String type;
  final String id;
  final String title;
  final String artist;
  final String artistId;
  final String artistImage;
  final String image;
  final String duration;
  final int nbFan;
  final String previewUrl;
  final int rank;
  final String genre;
  final String? filePath;
  final String albumId;
  final String albumTitle;
  final String albumCover;
  final bool isLyricsMatch;
  final String? matchedSnippet;

  SearchResult({
    required this.type,
    required this.id,
    required this.title,
    required this.artist,
    this.artistId = '',
    this.artistImage = '',
    required this.image,
    required this.duration,
    required this.nbFan,
    required this.previewUrl,
    this.rank = 0,
    this.genre = '',
    this.filePath,
    this.albumId = '',
    this.albumTitle = '',
    this.albumCover = '',
    this.isLyricsMatch = false,
    this.matchedSnippet,
  });

  SearchResult copyWith({
    String? type,
    String? id,
    String? title,
    String? artist,
    String? artistId,
    String? artistImage,
    String? image,
    String? duration,
    int? nbFan,
    String? previewUrl,
    int? rank,
    String? genre,
    String? filePath,
    String? albumId,
    String? albumTitle,
    String? albumCover,
    bool? isLyricsMatch,
    String? matchedSnippet,
  }) {
    return SearchResult(
      type: type ?? this.type,
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artistId: artistId ?? this.artistId,
      artistImage: artistImage ?? this.artistImage,
      image: image ?? this.image,
      duration: duration ?? this.duration,
      nbFan: nbFan ?? this.nbFan,
      previewUrl: previewUrl ?? this.previewUrl,
      rank: rank ?? this.rank,
      genre: genre ?? this.genre,
      filePath: filePath ?? this.filePath,
      albumId: albumId ?? this.albumId,
      albumTitle: albumTitle ?? this.albumTitle,
      albumCover: albumCover ?? this.albumCover,
      isLyricsMatch: isLyricsMatch ?? this.isLyricsMatch,
      matchedSnippet: matchedSnippet ?? this.matchedSnippet,
    );
  }

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      type: json['type'] ?? '',
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      artist: json['artist'] ?? '',
      artistId: json['artistId'] ?? '',
      artistImage: json['artistImage'] ?? '',
      image: json['image'] ?? '',
      duration: json['duration'] ?? '',
      nbFan: json['nbFan'] ?? 0,
      previewUrl: json['previewUrl'] ?? '',
      rank: json['rank'] ?? 0,
      genre: json['genre'] ?? '',
      albumId: json['albumId']?.toString() ?? '',
      albumTitle: json['albumTitle']?.toString() ?? '',
      albumCover: json['albumCover']?.toString() ?? '',
      filePath: json['filePath']?.toString(),
      isLyricsMatch: json['isLyricsMatch'] == true,
      matchedSnippet: json['matchedSnippet']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'id': id,
      'title': title,
      'artist': artist,
      'artistId': artistId,
      'artistImage': artistImage,
      'image': image,
      'duration': duration,
      'nbFan': nbFan,
      'previewUrl': previewUrl,
      'rank': rank,
      'genre': genre,
      'albumId': albumId,
      'albumTitle': albumTitle,
      'albumCover': albumCover,
      if (filePath != null) 'filePath': filePath,
      if (isLyricsMatch) 'isLyricsMatch': isLyricsMatch,
      if (matchedSnippet != null) 'matchedSnippet': matchedSnippet,
    };
  }

  /// Parse a Deezer API track object directly.
  factory SearchResult.fromDeezerTrack(
    Map<String, dynamic> track, {
    bool isLyricsMatch = false,
    String? matchedSnippet,
  }) {
    final artist = track['artist'] as Map<String, dynamic>? ?? {};
    final album = track['album'] as Map<String, dynamic>? ?? {};
    final durationSec = track['duration'] ?? 0;
    final min = durationSec ~/ 60;
    final sec = durationSec % 60;
    final aId = artist['id']?.toString() ?? '';
    final artistPic = artist['picture_xl'] ??
        artist['picture_big'] ??
        artist['picture_medium'] ??
        artist['picture'] ??
        (aId.isNotEmpty && RegExp(r'^\d+$').hasMatch(aId)
            ? 'https://api.deezer.com/artist/$aId/image?size=big'
            : '');

    return SearchResult(
      type: 'song',
      id: track['id'].toString(),
      title: track['title'] ?? '',
      artist: artist['name'] ?? '',
      artistId: aId,
      artistImage: artistPic.toString(),
      image:
          album['cover_big'] ?? album['cover_medium'] ?? album['cover'] ?? '',
      duration: '$min:${sec.toString().padLeft(2, '0')}',
      nbFan: (track['nb_fan'] as num?)?.toInt() ?? 0,
      previewUrl: track['preview'] ?? '',
      rank: (track['rank'] as num?)?.toInt() ?? 0,
      albumId: album['id']?.toString() ?? '',
      albumTitle: album['title']?.toString() ?? '',
      albumCover:
          album['cover_big'] ?? album['cover_medium'] ?? album['cover'] ?? '',
      isLyricsMatch: isLyricsMatch,
      matchedSnippet: matchedSnippet,
    );
  }

  /// Parse a Deezer API artist object.
  factory SearchResult.fromDeezerArtist(Map<String, dynamic> artist) {
    final id = artist['id']?.toString() ?? '';
    final pic = artist['picture_xl'] ??
        artist['picture_big'] ??
        artist['picture_medium'] ??
        artist['picture'] ??
        (id.isNotEmpty && RegExp(r'^\d+$').hasMatch(id)
            ? 'https://api.deezer.com/artist/$id/image?size=big'
            : '');

    return SearchResult(
      type: 'artist',
      id: id,
      title: artist['name'] ?? '',
      artist: artist['name'] ?? '',
      artistId: id,
      artistImage: pic.toString(),
      image: pic.toString(),
      duration: '',
      nbFan: (artist['nb_fan'] as num?)?.toInt() ?? 0,
      previewUrl: '',
    );
  }

  /// Parse a Deezer API album object.
  factory SearchResult.fromDeezerAlbum(Map<String, dynamic> album) {
    final artist = album['artist'] as Map<String, dynamic>? ?? {};
    return SearchResult(
      type: 'album',
      id: album['id'].toString(),
      title: album['title'] ?? '',
      artist: artist['name'] ?? '',
      artistId: artist['id']?.toString() ?? '',
      artistImage: '',
      image:
          album['cover_big'] ?? album['cover_medium'] ?? album['cover'] ?? '',
      duration: '',
      nbFan: album['nb_fan'] ?? 0,
      previewUrl: '',
    );
  }

  /// Parse an iTunes API track object.
  factory SearchResult.fromItunesTrack(Map<String, dynamic> track) {
    final millis = (track['trackTimeMillis'] as num?)?.toInt() ?? 0;
    final totalSec = millis ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    final rawArtwork = track['artworkUrl100']?.toString() ?? '';
    final hdArtwork = rawArtwork.replaceAll('100x100bb', '600x600bb');

    return SearchResult(
      type: 'song',
      id: 'itunes_${track['trackId']}',
      title: track['trackName']?.toString() ?? '',
      artist: track['artistName']?.toString() ?? '',
      artistId: track['artistId']?.toString() ?? '',
      artistImage: hdArtwork,
      image: hdArtwork,
      duration: '$min:${sec.toString().padLeft(2, '0')}',
      nbFan: 0,
      previewUrl: track['previewUrl']?.toString() ?? '',
      rank: 0,
    );
  }
}

class SearchService {
  static const _apiBase = 'https://api.deezer.com';
  static final Map<String, List<SearchResult>> _searchCache = {};

  static List<Map<String, String>> _khmerArtistsList = [];
  static bool _khmerArtistsLoaded = false;

  static Future<void> _ensureKhmerArtistsLoaded() async {
    if (_khmerArtistsLoaded) return;
    try {
      final str = await rootBundle.loadString('asset/data/khmer_artists.json');
      final data = jsonDecode(str) as Map<String, dynamic>;
      final list = <Map<String, String>>[];
      for (final val in data.values) {
        if (val is List) {
          for (final item in val) {
            if (item is Map) {
              list.add({
                'name': item['name']?.toString() ?? '',
                'khmer': item['khmer']?.toString() ?? '',
              });
            }
          }
        }
      }
      _khmerArtistsList = list;
      _khmerArtistsLoaded = true;
    } catch (_) {
      _khmerArtistsLoaded = true;
    }
  }

  static const Map<String, String> _knownKhmerDeezerArtistIds = {
    'vannda': '70151012',
    'suly pheng': '108107492',
    'sinn sisamouth': '5846489',
    'ros sereysothea': '5860073',
    'preap sovath': '113986772',
    'sokun nisa': '79109922',
    'kmeng khmer': '95515032',
    'g-devith': '11624634',
    'khem': '5857216',
    'reth suzana': '12808064',
    'chhay virakyuth': '13567757',
    'khemarak sereymun': '13567759',
    'meas soksophea': '13567761',
    'aok sokunkanha': '13567763',
    'heng pitu': '14800669',
    'tep boprek': '13567765',
    'pich sophea': '13567767',
    'manith': '108107482',
    'ny rattana': '13567771',
    'pen ron': '5860075',
    'yol aularong': '5860077',
    'noy vanneth': '5860079',
    'meng keo pichenda': '5860081',
    'him sivorn': '5860083',
    'touch sunnix': '5860085',
    'smallworld smallband': '11776994',
  };

  static List<SearchResult> _matchLocalKhmerArtists(String qLower) {
    if (_khmerArtistsList.isEmpty) return [];
    final matches = <SearchResult>[];
    for (final a in _khmerArtistsList) {
      final name = a['name'] ?? '';
      final khmer = a['khmer'] ?? '';
      final nameLower = name.toLowerCase();
      final khmerLower = khmer.toLowerCase();

      if (nameLower.contains(qLower) ||
          qLower.contains(nameLower) ||
          (khmerLower.isNotEmpty &&
              (khmerLower.contains(qLower) || qLower.contains(khmerLower)))) {
        final knownId = _knownKhmerDeezerArtistIds[nameLower];
        final id = knownId ?? 'khmer_${name.replaceAll(' ', '_')}';
        final pic = knownId != null
            ? 'https://api.deezer.com/artist/$knownId/image?size=big'
            : '';

        matches.add(SearchResult(
          type: 'artist',
          id: id,
          title: name,
          artist: name,
          artistId: id,
          artistImage: pic,
          image: pic,
          duration: '',
          nbFan: knownId != null ? 500000 : 100000,
          previewUrl: '',
        ));
      }
    }
    return matches;
  }

  static Future<List<SearchResult>> _searchItunesArtists(String query) async {
    try {
      final url = Uri.parse(
          'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&entity=musicArtist&limit=5');
      final resp = await http.get(url).timeout(const Duration(seconds: 3));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      final list = data['results'] as List?;
      if (list == null || list.isEmpty) return [];
      return list.map((item) {
        final name = item['artistName']?.toString() ?? '';
        final id = item['artistId']?.toString() ?? '';
        return SearchResult(
          type: 'artist',
          id: 'itunes_$id',
          title: name,
          artist: name,
          artistId: 'itunes_$id',
          artistImage: '',
          image: '',
          duration: '',
          nbFan: 50000,
          previewUrl: '',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static (String artist, String title) _parseVideoTitle(
      String rawTitle, String author) {
    var clean = rawTitle.replaceAll(
      RegExp(
        r'[\(\[\{].*?(?:lyrics?|lirik|terjemahan|karaoke|acoustic|official|video|audio|visualizer|remaster|hd|4k|mv|original\s*song|cover|parody|extended|subtitulado|legendado|español|spanish|english|sub).*?[\)\]\}]',
        caseSensitive: false,
      ),
      '',
    );
    clean = clean.replaceAll(RegExp(r'\|.*$'), '').trim();

    final parts = clean.split(' - ');
    if (parts.length >= 2) {
      var t = parts.sublist(1).join(' - ').trim();
      t = t.replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '').trim();
      return (parts[0].trim(), t);
    }
    var t = clean.trim();
    t = t.replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '').trim();
    return (author.trim(), t);
  }

  static Future<SearchResult?> _resolveDeezerTrack(
    String artist,
    String title, {
    String? snippet,
  }) async {
    if (title.trim().isEmpty) return null;

    final cleanArtist =
        artist.split(RegExp(r'[,&xX]|feat\.|ft\.')).first.trim();
    final cleanTitle = title
        .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '')
        .split(RegExp(r'[,&xX]|feat\.|ft\.'))
        .first
        .trim();

    if (cleanTitle.isEmpty) return null;

    // Queries MUST always include cleanTitle! Never query just the artist name alone.
    final queries = [
      if (cleanArtist.isNotEmpty) '$cleanTitle $cleanArtist',
      cleanTitle,
      if (artist.isNotEmpty) '$cleanTitle $artist',
      if (cleanArtist.isNotEmpty) '$cleanArtist $cleanTitle',
    ];

    for (final q in queries) {
      if (q.trim().isEmpty) continue;
      try {
        final url =
            Uri.parse('$_apiBase/search?q=${Uri.encodeComponent(q)}&limit=3');
        final resp = await http.get(url, headers: {
          'Accept': 'application/json'
        }).timeout(const Duration(seconds: 3));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final tracks = data['data'] as List?;
          if (tracks != null && tracks.isNotEmpty) {
            for (final item in tracks) {
              if (item is! Map<String, dynamic>) continue;
              if (item['readable'] == false) continue;

              final deezerTitle =
                  (item['title']?.toString() ?? '').toLowerCase().trim();
              final searchTitle = cleanTitle.toLowerCase().trim();

              // Validation: Deezer track title must match or share words with the video title
              bool matchesTitle = deezerTitle.contains(searchTitle) ||
                  searchTitle.contains(deezerTitle);
              if (!matchesTitle) {
                final sWords = searchTitle
                    .split(RegExp(r'\s+'))
                    .where((w) => w.length >= 3)
                    .toSet();
                final dWords = deezerTitle
                    .split(RegExp(r'\s+'))
                    .where((w) => w.length >= 3)
                    .toSet();
                matchesTitle = sWords.intersection(dWords).isNotEmpty;
              }

              if (matchesTitle) {
                return SearchResult.fromDeezerTrack(
                  item,
                  isLyricsMatch: true,
                  matchedSnippet: snippet,
                );
              }
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Resolve candidate songs matching lyric snippets using YouTube search + Deezer resolution.
  static Future<List<SearchResult>> _searchLyrics(String query) async {
    try {
      final yt = YoutubeExplode();
      final List<Video> searchResults;
      try {
        final res =
            await yt.search.search(query).timeout(const Duration(seconds: 4));
        searchResults = res.take(5).toList();
      } finally {
        yt.close();
      }

      if (searchResults.isEmpty) return [];

      final lyricMatches = <SearchResult>[];
      final seenIds = <String>{};
      final seenKeys = <String>{};

      for (final video in searchResults) {
        if (lyricMatches.length >= 3) break;

        final (parsedArtist, parsedTitle) =
            _parseVideoTitle(video.title, video.author);
        final dedupeKey =
            '${parsedArtist.toLowerCase()}_${parsedTitle.toLowerCase()}';
        if (seenKeys.contains(dedupeKey)) continue;
        seenKeys.add(dedupeKey);

        // 1. Try resolving against Deezer for official high-fidelity stream and album art
        SearchResult? matchedTrack;
        try {
          matchedTrack = await _resolveDeezerTrack(parsedArtist, parsedTitle,
              snippet: query);
        } catch (_) {}

        if (matchedTrack != null) {
          if (!seenIds.contains(matchedTrack.id)) {
            seenIds.add(matchedTrack.id);
            lyricMatches.add(matchedTrack);
          }
        } else {
          // 2. Fallback to YouTube-backed SearchResult (e.g. for Khmer / indie tracks)
          final durationSec = video.duration?.inSeconds ?? 0;
          final min = durationSec ~/ 60;
          final sec = durationSec % 60;
          final thumb = video.thumbnails.highResUrl.isNotEmpty
              ? video.thumbnails.highResUrl
              : video.thumbnails.mediumResUrl;

          final ytId = 'yt_${video.id.value}';
          if (!seenIds.contains(ytId)) {
            seenIds.add(ytId);
            lyricMatches.add(SearchResult(
              type: 'song',
              id: ytId,
              title: parsedTitle.isNotEmpty ? parsedTitle : video.title,
              artist: parsedArtist.isNotEmpty ? parsedArtist : video.author,
              artistId: '',
              artistImage: thumb,
              image: thumb,
              duration: durationSec > 0
                  ? '$min:${sec.toString().padLeft(2, '0')}'
                  : '',
              nbFan: 0,
              previewUrl: '',
              rank: 100,
              isLyricsMatch: true,
              matchedSnippet: query,
            ));
          }
        }
      }

      return lyricMatches;
    } catch (e) {
      debugPrint('[SearchService] _searchLyrics error: $e');
      return [];
    }
  }

  /// Combined search: songs + artists + albums, straight from Deezer's public
  /// search endpoints with Khmer, iTunes, and Lyrics fallbacks. Results are cached in-memory.
  static Future<List<SearchResult>> search(String query,
      {bool includeAlbums = true,
      int limitTracks = 25,
      int limitArtists = 15}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty || TrackFilter.isBlocked(query: cleanQuery)) return [];

    // Normalize common artist typos & aliases (e.g. "micheal" -> "michael", "weekend" -> "weeknd")
    var normalizedQuery = cleanQuery;
    final lower = cleanQuery.toLowerCase();
    if (lower.contains('micheal')) {
      normalizedQuery = cleanQuery.replaceAll(
          RegExp(r'micheal', caseSensitive: false), 'michael');
    } else if (lower.contains('weekend') && !lower.contains('vampire')) {
      normalizedQuery = cleanQuery.replaceAll(
          RegExp(r'weekend', caseSensitive: false), 'weeknd');
    }

    final cacheKey = '$cleanQuery|$normalizedQuery|$includeAlbums|$limitTracks';
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    await _ensureKhmerArtistsLoaded();
    final qLower = normalizedQuery.toLowerCase();
    final localArtists = _matchLocalKhmerArtists(qLower);

    // Multi-word queries (e.g. lyrics phrase "she said where you want to go") trigger lyrics search concurrently
    final words =
        cleanQuery.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final bool isMultiWordQuery =
        words.length >= 3 || (words.length >= 2 && cleanQuery.length >= 10);

    Future<List<SearchResult>>? lyricsFuture;
    if (isMultiWordQuery) {
      lyricsFuture = _searchLyrics(cleanQuery);
    }

    final encoded = Uri.encodeComponent(normalizedQuery);
    final futures = <Future<List<SearchResult>>>[
      _searchType(encoded, 'search', SearchResult.fromDeezerTrack, limitTracks),
      _searchType(encoded, 'search/artist', SearchResult.fromDeezerArtist,
          limitArtists),
    ];
    if (includeAlbums) {
      futures.add(_searchType(
          encoded, 'search/album', SearchResult.fromDeezerAlbum, 6));
    }

    final results = await Future.wait(futures);

    List<SearchResult> lyricsResults = [];
    if (lyricsFuture != null) {
      try {
        lyricsResults = await lyricsFuture;
      } catch (_) {}
    } else if (results[0].isEmpty && words.length >= 2) {
      // Fallback: If Deezer returned no tracks for a multi-word search, test lyrics
      try {
        lyricsResults = await _searchLyrics(cleanQuery);
      } catch (_) {}
    }

    final officialArtists = results[1];

    final rawArtists = <SearchResult>[];
    final seenArtistIds = <String>{};
    final seenArtistNames = <String>{};
    final isEveQuery = qLower == 'eve' || qLower == 'いぶ';

    void addArtistCandidate(SearchResult a) {
      final id = a.id.trim();
      final name = a.title.toLowerCase().trim();
      if (id.isEmpty && name.isEmpty) return;
      if (id.isNotEmpty && seenArtistIds.contains(id)) return;
      if (name.isNotEmpty && seenArtistNames.contains(name)) {
        // If Japanese Eve (69128312), replace duplicate or American Eve
        if (id == '69128312') {
          rawArtists.removeWhere((x) => x.id == '837' || x.id == '69127962');
          rawArtists.insert(0, a);
          seenArtistIds.add(id);
          return;
        }
        return;
      }

      if (id.isNotEmpty) seenArtistIds.add(id);
      if (name.isNotEmpty) seenArtistNames.add(name);
      rawArtists.add(a);
    }

    for (final a in localArtists) {
      addArtistCandidate(a);
    }
    for (final a in officialArtists) {
      addArtistCandidate(a);
    }

    if (isEveQuery) {
      rawArtists.removeWhere((a) => a.id == '69128312' || a.id == '69127962');
      rawArtists.insert(
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
          nbFan: 10000000,
          previewUrl: '',
        ),
      );
    }

    // ALWAYS extract artist profiles from the returned tracks as well
    for (final s in results[0]) {
      if (s.artist.isNotEmpty && s.artistId.isNotEmpty) {
        final aPic = s.artistImage.isNotEmpty
            ? s.artistImage
            : (RegExp(r'^\d+$').hasMatch(s.artistId)
                ? 'https://api.deezer.com/artist/${s.artistId}/image?size=big'
                : '');
        addArtistCandidate(SearchResult(
          type: 'artist',
          id: s.artistId,
          title: s.artist,
          artist: s.artist,
          artistId: s.artistId,
          artistImage: aPic,
          image: aPic,
          duration: '',
          nbFan: s.nbFan > 0 ? s.nbFan : 1000,
          previewUrl: '',
        ));
      }
    }

    if (rawArtists.isEmpty && lyricsResults.isEmpty) {
      final itunesArtists = await _searchItunesArtists(cleanQuery);
      for (final a in itunesArtists) {
        addArtistCandidate(a);
      }
    }

    // If lyrics matches are found, only keep artists whose name closely matches the query
    if (lyricsResults.isNotEmpty) {
      rawArtists.removeWhere((a) {
        final t = a.title.toLowerCase().trim();
        return t != qLower && !t.startsWith(qLower);
      });
    }

    // Sort artists by match relevance combined with popularity/fan base
    final artists = rawArtists
      ..sort((a, b) {
        final aTitle = a.title.toLowerCase();
        final bTitle = b.title.toLowerCase();

        int scoreArtist(String title, int fans) {
          int s = 0;
          final t = title.trim();
          if (t == qLower) {
            s += 1000000000;
          } else if (t.startsWith(qLower)) {
            s += 500000000;
          } else if (t.contains(qLower) || qLower.contains(t)) {
            s += 200000000;
          } else {
            // Check word matches
            final qWords = qLower
                .split(RegExp(r'\s+'))
                .where((w) => w.length >= 2)
                .toList();
            final titleWords =
                t.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();

            int matchedWords = 0;
            for (final qw in qWords) {
              if (titleWords.any(
                  (tw) => tw == qw || tw.startsWith(qw) || qw.startsWith(tw))) {
                matchedWords++;
              }
            }
            s += matchedWords * 50000000;
          }
          // Cap fan count effect so exact/partial text matches stay on top
          s += fans.clamp(0, 10000000);
          return s;
        }

        final aScore = scoreArtist(aTitle, a.nbFan);
        final bScore = scoreArtist(bTitle, b.nbFan);

        return bScore.compareTo(aScore);
      });
    final topArtists = artists;

    // Combine songs: lyrics matches at the very top, followed by Deezer search songs
    final allFoundSongs = <SearchResult>[];
    final seenSongIds = <String>{};
    final seenSongKeys = <String>{};

    for (final s in lyricsResults) {
      final id = s.id.trim();
      final key =
          '${s.title.toLowerCase().trim()}_${s.artist.toLowerCase().trim()}';
      if (id.isNotEmpty) seenSongIds.add(id);
      seenSongKeys.add(key);
      allFoundSongs.add(s);
    }

    for (final s in results[0]) {
      final id = s.id.trim();
      final key =
          '${s.title.toLowerCase().trim()}_${s.artist.toLowerCase().trim()}';
      if (id.isNotEmpty && seenSongIds.contains(id)) continue;
      if (seenSongKeys.contains(key)) continue;

      if (id.isNotEmpty) seenSongIds.add(id);
      seenSongKeys.add(key);
      allFoundSongs.add(s);
    }

    if (isEveQuery) {
      if (!allFoundSongs.any((s) =>
          s.artistId == '69128312' ||
          s.title.toLowerCase().contains('kaikai kitan'))) {
        allFoundSongs.add(SearchResult(
          type: 'song',
          id: '1143848452',
          title: 'Kaikai Kitan',
          artist: 'Eve',
          artistId: '69128312',
          artistImage:
              'https://cdn-images.dzcdn.net/images/artist/d338715a1c099cecc59363cd8c68ae3d/500x500-000000-80-0-0.jpg',
          image:
              'https://e-cdns-images.dzcdn.net/images/cover/b45eb8a184e9eb084ef704fe55b412be/500x500-000000-80-0-0.jpg',
          duration: '3:41',
          nbFan: 69898,
          previewUrl: '',
          rank: 999999,
        ));
      }
    }

    // Sort songs by match relevance and global popularity rank (lyrics matches & trending hits on top)
    final songs = allFoundSongs
      ..sort((a, b) {
        int scoreSong(SearchResult r) {
          int s = 0;
          if (r.isLyricsMatch) {
            s += 50000000; // Prioritize lyrics matches
          }
          final artist = r.artist.toLowerCase();
          final title = r.title.toLowerCase();
          if (artist == qLower || title == qLower) {
            s += 10000000;
          } else if (artist.startsWith(qLower) || title.startsWith(qLower)) {
            s += 5000000;
          } else if (artist.contains(qLower) || title.contains(qLower)) {
            s += 2000000;
          }
          if (isEveQuery) {
            if (r.artistId == '69128312') {
              s += 40000000; // Japanese Eve songs on top
            } else if (r.artistId == '837') {
              s -= 20000000; // De-prioritize US rap Eve songs
            }
          }
          // Global popularity rank from Deezer (0 - 1,000,000+)
          s += r.rank;
          return s;
        }

        final aScore = scoreSong(a);
        final bScore = scoreSong(b);

        return bScore.compareTo(aScore);
      });

    bool isAllowed(SearchResult r) {
      if (TrackFilter.isBlocked(artist: r.artist, title: r.title, id: r.id)) {
        return false;
      }
      if (r.id.isEmpty) return false;
      return true;
    }

    final filteredSongs = songs.where(isAllowed).toList();
    final filteredArtists = topArtists.where(isAllowed).toList();
    final filteredAlbums = includeAlbums && results.length > 2
        ? results[2].where(isAllowed).toList()
        : <SearchResult>[];

    final combined = [...filteredSongs, ...filteredArtists, ...filteredAlbums];
    if (combined.isNotEmpty) {
      _searchCache[cacheKey] = combined;
      if (_searchCache.length > 100) {
        _searchCache.remove(_searchCache.keys.first);
      }
    }
    return combined;
  }

  static Future<List<SearchResult>> _searchType(
    String encoded,
    String path,
    SearchResult Function(Map<String, dynamic>) fromJson,
    int limit,
  ) async {
    try {
      final resp = await http.get(
        Uri.parse('$_apiBase/$path?q=$encoded&limit=$limit'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 4));

      if (resp.statusCode != 200) return [];

      final data = jsonDecode(resp.body);
      final results = data['data'] as List?;
      if (results == null || results.isEmpty) return [];

      return results
          .whereType<Map<String, dynamic>>()
          .where((item) {
            if (path == 'search') {
              // Deezer sets readable: false on tracks that cannot be streamed
              if (item['readable'] == false) return false;
            }
            return true;
          })
          .map(fromJson)
          .toList();
    } catch (e) {
      debugPrint('[Search] $path error: $e');
      return [];
    }
  }

  /// Resolve album details for a track from Deezer
  static Future<Map<String, String>?> getTrackAlbum(
      String trackId, String title, String artist) async {
    try {
      final targetArt = artist.toLowerCase().trim();
      final targetTitle = title.toLowerCase().trim();

      // 1. If numeric Deezer track ID
      if (trackId.isNotEmpty && RegExp(r'^\d+$').hasMatch(trackId)) {
        final url = Uri.parse('$_apiBase/track/$trackId');
        final res = await http.get(url, headers: {
          'Accept': 'application/json'
        }).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          final album = data['album'] as Map<String, dynamic>?;
          final art = data['artist'] as Map<String, dynamic>?;
          if (album != null && album['id'] != null) {
            final candArt =
                (art?['name']?.toString() ?? '').toLowerCase().trim();
            final artMatches = targetArt.isEmpty ||
                candArt == targetArt ||
                candArt.contains(targetArt) ||
                targetArt.contains(candArt);
            if (artMatches) {
              return {
                'albumId': album['id'].toString(),
                'albumTitle': album['title']?.toString() ?? '',
                'albumImage': album['cover_big']?.toString() ??
                    album['cover_medium']?.toString() ??
                    album['cover']?.toString() ??
                    '',
                'artistId': art?['id']?.toString() ?? '',
                'artistName': art?['name']?.toString() ?? '',
              };
            }
          }
        }
      }

      // 2. Search track by title + artist
      final query = '$title $artist'.trim();
      if (query.isNotEmpty) {
        final searchUrl = Uri.parse(
            '$_apiBase/search?q=${Uri.encodeComponent(query)}&limit=10');
        final res = await http.get(searchUrl, headers: {
          'Accept': 'application/json'
        }).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          final list = data['data'] as List<dynamic>? ?? [];
          for (final item in list) {
            final t = item as Map<String, dynamic>;
            final album = t['album'] as Map<String, dynamic>?;
            final art = t['artist'] as Map<String, dynamic>?;
            if (album == null || album['id'] == null) continue;

            final candArt =
                (art?['name']?.toString() ?? '').toLowerCase().trim();
            final candTitle =
                (t['title']?.toString() ?? '').toLowerCase().trim();

            // Strict check: artist MUST match target artist
            final artMatches = targetArt.isEmpty ||
                candArt == targetArt ||
                candArt.contains(targetArt) ||
                targetArt.contains(candArt);
            if (!artMatches) continue;

            // Title must match or share significant text
            final titleMatches = targetTitle.isEmpty ||
                candTitle == targetTitle ||
                candTitle.contains(targetTitle) ||
                targetTitle.contains(candTitle);
            if (!titleMatches) continue;

            return {
              'albumId': album['id'].toString(),
              'albumTitle': album['title']?.toString() ?? '',
              'albumImage': album['cover_big']?.toString() ??
                  album['cover_medium']?.toString() ??
                  album['cover']?.toString() ??
                  '',
              'artistId': art?['id']?.toString() ?? '',
              'artistName': art?['name']?.toString() ?? '',
            };
          }
        }
      }
    } catch (e) {
      debugPrint('[SearchService] getTrackAlbum error: $e');
    }
    return null;
  }
}
