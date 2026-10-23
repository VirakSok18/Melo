import 'dart:async';
import 'dart:collection';
import 'deezer_service.dart';
import 'deezer_proxy.dart';
import 'jiosaavn_service.dart';
import 'search_service.dart';

/// Global, gentle background prefetch queue.
/// Resolves CDN stream URLs one by one in the background without hogging bandwidth
/// or competing with active playback.
class BackgroundPrefetchService {
  static final BackgroundPrefetchService instance =
      BackgroundPrefetchService._();
  BackgroundPrefetchService._();

  final Queue<_PrefetchTask> _queue = Queue<_PrefetchTask>();
  final Set<String> _enqueuedKeys = {};
  bool _isProcessing = false;

  /// Enqueue a list of tracks to be gently prefetched in the background.
  void enqueueTracks(List<dynamic> tracks, {String tag = 'general'}) {
    for (final item in tracks) {
      if (item is SearchResult) {
        _enqueueSingle(item.id, item.title, item.artist, tag: tag);
      } else if (item is Map<String, dynamic>) {
        final id = (item['deezerId'] ?? item['id'] ?? '').toString();
        final title = (item['title'] ?? '').toString();
        final artist = (item['artist'] ?? '').toString();
        _enqueueSingle(id, title, artist, tag: tag);
      }
    }
    _processQueue();
  }

  void _enqueueSingle(String trackId, String title, String artist,
      {required String tag}) {
    if (title.isEmpty) return;
    final key = trackId.isNotEmpty ? trackId : '$title|$artist'.toLowerCase();
    if (_enqueuedKeys.contains(key)) return;

    _enqueuedKeys.add(key);
    _queue.add(_PrefetchTask(
        trackId: trackId, title: title, artist: artist, tag: tag));
  }

  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    try {
      // Ensure local streaming proxy is warmed up
      await DeezerProxy.instance.ensureRunning();

      while (_queue.isNotEmpty) {
        final task = _queue.removeFirst();
        try {
          String? targetId = task.trackId;
          if (targetId.isEmpty ||
              int.tryParse(targetId) == null ||
              int.parse(targetId) <= 0) {
            targetId =
                await DeezerService.searchTrackId(task.title, task.artist);
          }

          if (targetId != null && targetId.isNotEmpty) {
            if (DeezerService.isCdnCached(targetId)) {
              // Already on disk / memory - instant 0ms, skip network
              continue;
            }

            // Warm up CDN URL in memory cache & persist to disk
            final url = await DeezerService.getCdnUrl(targetId);
            if (url != null) {
              print(
                  '[Prefetch] ⚡ Cached new Deezer CDN stream for "${task.title}" by ${task.artist} [${task.tag}] (${_queue.length} left)');
            } else {
              // Geo-blocked on Deezer, warm up JioSaavn stream
              final jioUrl =
                  await JioSaavnService.getStreamUrl(task.title, task.artist);
              if (jioUrl != null) {
                print(
                    '[Prefetch] ⚡ Cached JioSaavn CDN stream for "${task.title}" by ${task.artist} [${task.tag}] (${_queue.length} left)');
              }
            }
          } else {
            final jioUrl =
                await JioSaavnService.getStreamUrl(task.title, task.artist);
            if (jioUrl != null) {
              print(
                  '[Prefetch] ⚡ Cached JioSaavn CDN stream for "${task.title}" by ${task.artist} [${task.tag}] (${_queue.length} left)');
            }
          }
        } catch (_) {
          // Ignore background errors completely
        }

        // Gentle pause between background requests (150ms) to ensure zero impact on user interaction
        await Future.delayed(const Duration(milliseconds: 150));
      }
    } finally {
      _isProcessing = false;
    }
  }
}

class _PrefetchTask {
  final String trackId;
  final String title;
  final String artist;
  final String tag;

  _PrefetchTask({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.tag,
  });
}
