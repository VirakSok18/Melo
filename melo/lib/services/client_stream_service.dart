import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class ClientAudioStream {
  final Stream<List<int>> byteStream;
  final int size;
  final String container;
  final String videoId;
  final String title;

  ClientAudioStream({
    required this.byteStream,
    required this.size,
    required this.container,
    required this.videoId,
    required this.title,
  });
}

/// 100% Client-Side fallback stream resolver.
/// Uses on-device YouTube extraction (youtube_explode_dart) to obtain direct
/// audio streams without server dependency or geo-restrictions.
class ClientStreamService {
  static final YoutubeExplode _yt = YoutubeExplode();
  static final Map<String, String> _cache = {};

  static const List<String> _badKeywords = [
    'cover',
    'karaoke',
    'instrumental',
    'acoustic cover',
    'piano cover',
    'guitar cover',
    'vocal cover',
    'drum cover',
    'bass cover',
    'remix',
    'mashup',
    'slowed',
    'reverb',
    'sped up',
    'speed up',
    'nightcore',
    'reaction',
    'tutorial',
    'lesson',
    'parody',
    'tier list',
    'interview',
    'podcast',
    'vlog',
    '1 hour',
    '10 hours',
    'loop',
    'full album',
    'compilation',
    'mix',
  ];

  static void clearCache() {
    _cache.clear();
  }

  /// Download audio stream directly on device to a local temp file for smooth, zero-error playback.
  static Future<String?> downloadAudioToTempFile(
    String title,
    String artist, {
    String? videoId,
  }) async {
    try {
      final audio = await getAudioStream(title, artist, videoId: videoId);
      if (audio == null) return null;

      final tempDir = await getTemporaryDirectory();
      final file =
          File('${tempDir.path}/yt_${audio.videoId}.${audio.container}');

      // If file already exists and is non-empty, use it immediately
      if (await file.exists() && await file.length() > 50000) {
        print(
            '[ClientStream] ⚡ Reusing local audio file: ${file.path} (${await file.length()} bytes)');
        return file.path;
      }

      final sink = file.openWrite();
      await sink.addStream(audio.byteStream);
      await sink.flush();
      await sink.close();

      if (await file.exists() && await file.length() > 0) {
        print(
            '[ClientStream] ⚡ Downloaded audio to file: ${file.path} (${await file.length()} bytes)');
        return file.path;
      }
    } catch (e) {
      print('[ClientStream] Error saving audio to temp file: $e');
    }
    return null;
  }

  /// Resolve a direct playable stream URL from YouTube on device
  static Future<String?> resolveStream(String title, String artist,
      {String? videoId}) async {
    try {
      final selectedVideo = await _findBestVideo(title, artist);
      if (selectedVideo == null) return null;
      final manifest = await _yt.videos.streamsClient
          .getManifest(selectedVideo.id)
          .timeout(const Duration(seconds: 4));
      final audioOnly = manifest.audioOnly.withHighestBitrate();
      return audioOnly.url.toString();
    } catch (_) {
      return null;
    }
  }

  /// Resolve an on-device byte stream with internal cipher decryption
  static Future<ClientAudioStream?> getAudioStream(
    String title,
    String artist, {
    String? videoId,
  }) async {
    if (title.trim().isEmpty && (videoId == null || videoId.isEmpty)) {
      return null;
    }

    try {
      String? targetVid = videoId;
      if (targetVid != null && targetVid.isNotEmpty) {
        targetVid =
            targetVid.startsWith('yt_') ? targetVid.substring(3) : targetVid;
      }

      Video? selectedVideo;

      if (targetVid != null && targetVid.isNotEmpty) {
        try {
          selectedVideo = await _yt.videos
              .get(targetVid)
              .timeout(const Duration(seconds: 4));
        } catch (_) {}
      }

      if (selectedVideo == null) {
        selectedVideo = await _findBestVideo(title, artist);
      }

      if (selectedVideo == null) return null;

      print(
          '[ClientStream] Selected candidate: "${selectedVideo.title}" by "${selectedVideo.author}"');

      final manifest = await _yt.videos.streamsClient
          .getManifest(selectedVideo.id)
          .timeout(const Duration(seconds: 5));

      final audioOnly = manifest.audioOnly.withHighestBitrate();
      final byteStream = _yt.videos.streamsClient.get(audioOnly);

      return ClientAudioStream(
        byteStream: byteStream,
        size: audioOnly.size.totalBytes,
        container: audioOnly.container.name,
        videoId: selectedVideo.id.value,
        title: selectedVideo.title,
      );
    } catch (e) {
      print(
          '[ClientStream] Error obtaining audio stream for "$title" by "$artist": $e');
      return null;
    }
  }

  static Future<Video?> _findBestVideo(String title, String artist) async {
    final normArtist = artist.toLowerCase().trim();
    final normTitle = title.toLowerCase().trim();

    List<Video> searchResults = [];
    try {
      final r1 = await _yt.search
          .search('$artist $title official audio'.trim())
          .timeout(const Duration(seconds: 4));
      searchResults.addAll(r1);
    } catch (_) {}

    if (searchResults.isEmpty) {
      try {
        final r2 = await _yt.search
            .search('$artist $title'.trim())
            .timeout(const Duration(seconds: 4));
        searchResults.addAll(r2);
      } catch (_) {}
    }

    if (searchResults.isEmpty) return null;

    Video? bestVideo;
    int bestScore = -999999;

    for (final v in searchResults) {
      final vTitle = v.title.toLowerCase();
      final vAuthor = v.author.toLowerCase();
      final duration = v.duration ?? Duration.zero;

      if (duration.inSeconds < 30 || duration.inSeconds > 480) {
        continue;
      }

      int score = 0;

      for (final bad in _badKeywords) {
        if (vTitle.contains(bad) && !normTitle.contains(bad)) {
          score -= 500;
        }
      }

      if (vAuthor.contains(' - topic') ||
          vAuthor == '$normArtist - topic' ||
          vAuthor.contains('topic')) {
        score += 400;
      }

      if (vAuthor.contains(normArtist) || normArtist.contains(vAuthor)) {
        score += 250;
      }

      if (vTitle.contains('official audio')) score += 150;
      if (vTitle.contains('official video') ||
          vTitle.contains('official music video')) {
        score += 120;
      }
      if (vTitle.contains('visualizer') || vTitle.contains('lyric video')) {
        score += 80;
      }

      if (vTitle.contains(normTitle)) score += 100;
      if (vTitle.contains(normArtist)) score += 80;

      final views = v.engagement.viewCount;
      if (views > 1000000) {
        score += 50;
      } else if (views > 100000) {
        score += 30;
      } else if (views < 1000) {
        score -= 50;
      }

      if (score > bestScore) {
        bestScore = score;
        bestVideo = v;
      }
    }

    return bestVideo ?? searchResults.first;
  }

  static Future<String?> getStreamUrl(String title, String artist,
      {String? videoId}) async {
    if (title.trim().isEmpty && (videoId == null || videoId.isEmpty)) {
      return null;
    }

    if (videoId != null && videoId.isNotEmpty) {
      final cleanVideoId =
          videoId.startsWith('yt_') ? videoId.substring(3) : videoId;
      final cachedUrl = _cache['vid_$cleanVideoId'];
      if (cachedUrl != null) return cachedUrl;

      try {
        final manifest = await _yt.videos.streamsClient
            .getManifest(cleanVideoId)
            .timeout(const Duration(seconds: 5));
        final audioOnly = manifest.audioOnly.withHighestBitrate();
        final streamUrl = audioOnly.url.toString();
        _cache['vid_$cleanVideoId'] = streamUrl;
        return streamUrl;
      } catch (e) {
        print('[ClientStream] Direct videoId resolution failed: $e');
      }
    }

    final cacheKey = '$title $artist'.toLowerCase().trim();
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    try {
      final bestVideo = await _findBestVideo(title, artist);
      if (bestVideo == null) return null;

      final manifest = await _yt.videos.streamsClient
          .getManifest(bestVideo.id)
          .timeout(const Duration(seconds: 5));

      final audioOnly = manifest.audioOnly.withHighestBitrate();
      final streamUrl = audioOnly.url.toString();

      _cache[cacheKey] = streamUrl;
      return streamUrl;
    } catch (e) {
      print('[ClientStream] Error resolving stream URL: $e');
      return null;
    }
  }
}
