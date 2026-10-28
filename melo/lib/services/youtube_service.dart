import 'search_service.dart';

class YouTubeService {
  static String get baseUrl => '';

  static String getPlayUrl(String title, String artist,
      {int durationSeconds = 0, bool prefetch = false}) {
    return '';
  }

  /// Direct client-side playback is used via Deezer proxy, JioSaavn CDN, and ClientStreamService.
  static Future<String?> resolveStreamUrl(String title, String artist,
      {int durationSeconds = 0}) async {
    return null;
  }

  static void cancelPrefetch() {}

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
