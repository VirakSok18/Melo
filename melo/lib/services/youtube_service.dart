import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'search_service.dart';

class YouTubeService {
  static String get baseUrl => '${ApiConfig.baseUrlSync}/api/youtube';

  /// Backend download-then-serve endpoint. The backend runs yt-dlp to download
  /// the audio (the same reliable path offline mode uses) and serves the file
  /// with Range support. Unlike stream URLs, this never 403s — YouTube accepts
  /// the download itself, not a fragile extracted googlevideo URL.
  ///
  /// [durationSeconds] is the song's official length. The backend uses it to
  /// pick the video whose duration matches (with a "lyric" search) so we get
  /// the ORIGINAL version — not an MV/live/cover with intros that desync lyrics.
  static String getPlayUrl(String title, String artist,
      {int durationSeconds = 0, bool prefetch = false}) {
    final url =
        '$baseUrl/play?title=${Uri.encodeComponent(title)}&artist=${Uri.encodeComponent(artist)}&duration=$durationSeconds';
    return prefetch ? '$url&prefetch=true' : url;
  }

  /// Resolves a YouTube CDN stream URL (googlevideo.com) without downloading.
  /// Returns the URL string, or null if resolution fails.
  /// The URL is valid for ~6 hours and can be played directly by ExoPlayer.
  static Future<String?> resolveStreamUrl(String title, String artist,
      {int durationSeconds = 0}) async {
    if (!await ApiConfig.isReachable) return null;
    try {
      final base = await ApiConfig.baseUrl;
      final response = await http
          .post(
            Uri.parse('$base/api/youtube/stream'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'title': title,
              'artist': artist,
              'duration': durationSeconds.toString(),
            }),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['streamUrl'] != null) {
          String url = data['streamUrl'] as String;
          // If the backend returns a relative path (e.g. /api/deezer/play?trackId=...),
          // prepend the backend base URL so just_audio/ExoPlayer can reach it.
          if (url.startsWith('/')) {
            url = '${ApiConfig.baseUrlSync}$url';
          }
          return url;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// No-op: client-side playback manages streams directly.
  static void cancelPrefetch() {}

  /// Playback is handled entirely on the client (Deezer proxy, JioSaavn CDN, ClientStreamService).
  /// Backend audio prefetching and disk downloads are disabled.
  static Future<void> prefetchStreamUrls(List<SearchResult> songs,
      {int batchSize = 5,
      bool prefetchAll = false,
      int maxConcurrent = 5}) async {
    return;
  }

  static int durationInSeconds(String duration) {
    if (duration.isEmpty) return 0;
    final parts = duration.split(':');
    if (parts.length == 3) {
      return int.tryParse(parts[0])! * 3600 +
          int.tryParse(parts[1])! * 60 +
          int.tryParse(parts[2])!;
    }
    if (parts.length == 2) {
      return int.tryParse(parts[0])! * 60 + int.tryParse(parts[1])!;
    }
    return int.tryParse(duration) ?? 0;
  }
}
