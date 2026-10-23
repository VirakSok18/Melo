import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'artist_service.dart';
import 'search_service.dart';
import '../utils/track_filter.dart';

class RecommendationService {
  static const _deezerApi = 'https://api.deezer.com';

  static bool _isPlayableTrack(Map<String, dynamic> t) {
    if (t['readable'] == false) return false;
    if (!TrackFilter.isAllowedMap(t)) return false;
    final duration = (t['duration'] as num?)?.toInt() ?? 0;
    if (duration <= 10) return false;
    return true;
  }

  /// Get smart queue: related artists' top tracks and artist radio based on the currently playing artist,
  /// interleaved in round-robin order so songs from the same artist are spread out,
  /// and filtered against [excludeKeys] to prevent repeating songs already in queue or played.
  static Future<List<SearchResult>> getSmartQueue(String artistName,
      {int limit = 16, Set<String>? excludeKeys}) async {
    if (artistName.trim().isEmpty) return [];

    try {
      // 1. Find the artist on Deezer
      String mainArtistId;
      final normArtist = artistName.toLowerCase().trim();
      if (normArtist == 'eve' || normArtist == 'いぶ') {
        // Disambiguate to Japanese singer-songwriter Eve (Jujutsu Kaisen, MHA)
        mainArtistId = '69128312';
      } else {
        final searchResp = await http.get(
          Uri.parse(
              '$_deezerApi/search/artist?q=${Uri.encodeComponent(artistName)}&limit=1'),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 6));

        if (searchResp.statusCode != 200) return [];

        final searchData = jsonDecode(searchResp.body);
        final artists = searchData['data'] as List? ?? [];
        if (artists.isEmpty) return [];

        mainArtistId = artists[0]['id'].toString();
      }

      // 2. Fetch related artists, main artist top tracks, and artist radio concurrently
      final relatedFuture = http.get(
        Uri.parse('$_deezerApi/artist/$mainArtistId/related?limit=12'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 6));

      final Future<List<SearchResult>> mainTopFuture =
          (mainArtistId == '69128312')
              ? ArtistService.getArtistTopTracks('69128312', limit: 6)
              : http
                  .get(
                    Uri.parse('$_deezerApi/artist/$mainArtistId/top?limit=6'),
                    headers: {'Accept': 'application/json'},
                  )
                  .timeout(const Duration(seconds: 6))
                  .then((mainTopResp) {
                    if (mainTopResp.statusCode == 200) {
                      final topData = jsonDecode(mainTopResp.body);
                      return (topData['data'] as List? ?? [])
                          .whereType<Map<String, dynamic>>()
                          .where(_isPlayableTrack)
                          .map((t) => SearchResult.fromDeezerTrack(t))
                          .toList();
                    }
                    return <SearchResult>[];
                  })
                  .catchError((_) => <SearchResult>[]);

      final radioFuture = http.get(
        Uri.parse('$_deezerApi/artist/$mainArtistId/radio?limit=25'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 6));

      final responses = await Future.wait([relatedFuture, radioFuture]);
      final relatedResp = responses[0];
      final radioResp = responses[1];
      final topTracks = await mainTopFuture;

      final artistBuckets = <List<SearchResult>>[];
      final seenKeys = <String>{...?excludeKeys?.map((k) => k.toLowerCase())};

      // Add main artist top tracks as bucket 0
      final filteredTop = topTracks
          .where((t) => !seenKeys
              .contains('${t.title.toLowerCase()}|${t.artist.toLowerCase()}'))
          .toList();
      if (filteredTop.isNotEmpty) artistBuckets.add(filteredTop);

      // 3. Fetch top tracks from related artists in parallel
      if (relatedResp.statusCode == 200) {
        final relatedData = jsonDecode(relatedResp.body);
        final relatedArtists = (relatedData['data'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .where((r) {
          final name = (r['name'] ?? '').toString().toLowerCase().trim();
          return name.isNotEmpty &&
              name != 'sombr' &&
              !name.contains('sombr') &&
              !name.contains('stella lefty');
        }).toList();

        final relatedTracksFutures = relatedArtists.map((related) async {
          try {
            final topResp = await http.get(
              Uri.parse('$_deezerApi/artist/${related['id']}/top?limit=5'),
              headers: {'Accept': 'application/json'},
            ).timeout(const Duration(seconds: 6));

            if (topResp.statusCode == 200) {
              final topData = jsonDecode(topResp.body);
              return (topData['data'] as List? ?? [])
                  .whereType<Map<String, dynamic>>()
                  .where(_isPlayableTrack)
                  .map((t) => SearchResult.fromDeezerTrack(t))
                  .where((t) => !seenKeys.contains(
                      '${t.title.toLowerCase()}|${t.artist.toLowerCase()}'))
                  .toList();
            }
          } catch (e) {
            debugPrint(
                '[Rec] Top tracks error for related artist ${related['name']}: $e');
          }
          return <SearchResult>[];
        }).toList();

        final fetchedBuckets = await Future.wait(relatedTracksFutures);
        for (final bucket in fetchedBuckets) {
          if (bucket.isNotEmpty) {
            artistBuckets.add(bucket);
          }
        }
      }

      // 4. Round-Robin Interleave: Spread songs across different artists
      // (1st song of Artist 1, 1st song of Artist 2... then 2nd song of Artist 1...)
      final result = <SearchResult>[];
      int maxTracksPerArtist = 0;
      for (final bucket in artistBuckets) {
        if (bucket.length > maxTracksPerArtist) {
          maxTracksPerArtist = bucket.length;
        }
      }

      for (int trackIndex = 0; trackIndex < maxTracksPerArtist; trackIndex++) {
        for (final bucket in artistBuckets) {
          if (result.length >= limit) break;
          if (trackIndex < bucket.length) {
            final track = bucket[trackIndex];
            final key =
                '${track.title.toLowerCase()}|${track.artist.toLowerCase()}';
            if (!seenKeys.contains(key)) {
              seenKeys.add(key);
              result.add(track);
            }
          }
        }
        if (result.length >= limit) break;
      }

      // 5. Rich Radio Fallback: If we still need more tracks to reach limit, pull from Artist Radio
      if (result.length < limit && radioResp.statusCode == 200) {
        final radioData = jsonDecode(radioResp.body);
        final radioTracks = (radioData['data'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .where(_isPlayableTrack);
        for (final t in radioTracks) {
          if (result.length >= limit) break;
          final track = SearchResult.fromDeezerTrack(t);
          final key =
              '${track.title.toLowerCase()}|${track.artist.toLowerCase()}';
          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            result.add(track);
          }
        }
      }

      return result;
    } catch (e) {
      debugPrint('[Rec] Smart queue error for "$artistName": $e');
      return [];
    }
  }
}
