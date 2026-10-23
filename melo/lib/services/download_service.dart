import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lyrics_service.dart';
import 'deezer_service.dart';
import 'jiosaavn_service.dart';
import 'client_stream_service.dart';
import 'premium_service.dart';

class DownloadService {
  static List<Map<String, dynamic>> _cache = [];
  static bool _loaded = false;
  static Directory? _downloadDir;
  static final ValueNotifier<int> onUpdate = ValueNotifier<int>(0);

  // Download progress tracking: trackId -> progress (0.0 - 1.0)
  static final Map<String, double> _progress = {};
  static final ValueNotifier<String?> _downloadingTrackId =
      ValueNotifier<String?>(null);
  static final Map<String, ValueNotifier<double>> _trackProgressNotifiers = {};
  static final ValueNotifier<int> _downloadCountNotifier =
      ValueNotifier<int>(0);

  // Track the metadata of the song currently being downloaded
  static Map<String, dynamic>? _downloadingSongMeta;

  static int get count => _cache.length;
  static List<Map<String, dynamic>> get cachedDownloads =>
      List.unmodifiable(_cache);
  static String? get downloadingTrackId => _downloadingTrackId.value;
  static ValueNotifier<String?> get downloadingTrackIdNotifier =>
      _downloadingTrackId;
  static Map<String, dynamic>? get downloadingSongMeta => _downloadingSongMeta;
  static ValueNotifier<int> get downloadCountNotifier => _downloadCountNotifier;

  /// Returns all songs: completed downloads + the one currently downloading (if any)
  static List<Map<String, dynamic>> getAllSongsIncludingInProgress() {
    final all = List<Map<String, dynamic>>.from(_cache);
    final dlMeta = _downloadingSongMeta;
    final dlId = _downloadingTrackId.value;
    if (dlMeta != null && dlId != null) {
      // Don't add if already in completed list
      if (!all.any((s) => s['trackId'] == dlId)) {
        all.insert(0, {
          'trackId': dlId,
          'title': dlMeta['title'] ?? '',
          'artist': dlMeta['artist'] ?? '',
          'image': dlMeta['image'] ?? '',
          'artistId': dlMeta['artistId'] ?? '',
          'artistImage': dlMeta['artistImage'] ?? '',
          'fileSize': 0,
          'isDownloading': true,
        });
      }
    }
    return all;
  }

  static ValueNotifier<double> getProgressNotifier(String trackId) {
    if (!_trackProgressNotifiers.containsKey(trackId)) {
      _trackProgressNotifiers[trackId] = ValueNotifier<double>(0);
    }
    return _trackProgressNotifiers[trackId]!;
  }

  static double getProgress(String trackId) => _progress[trackId] ?? 0;

  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      await _getDownloadDir();
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await _loadLocalCache(user.id);
      }
    } catch (e) {
      debugPrint('[DownloadService] init error: $e');
    }
  }

  static Future<Directory> _getDownloadDir() async {
    if (kIsWeb) throw UnsupportedError('Downloads are not supported on web');
    if (_downloadDir != null) return _downloadDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _downloadDir = Directory('${appDir.path}/downloads');
    if (!await _downloadDir!.exists()) {
      await _downloadDir!.create(recursive: true);
    }
    return _downloadDir!;
  }

  static Future<List<Map<String, dynamic>>> getDownloadedSongs(
      {bool force = false}) async {
    // Downloads live only on this phone — audio files plus a per-user metadata
    // cache file. No server, no Supabase.
    if (!force && _loaded) return _cache;
    final user = Supabase.instance.client.auth.currentUser;
    await _loadLocalCache(user?.id);
    return _cache;
  }

  static Future<void> _verifyLocalFiles() async {
    final dir = await _getDownloadDir();
    final toRemove = <Map<String, dynamic>>[];

    for (final song in _cache) {
      final trackId = song['trackId'] ?? '';
      final file = File('${dir.path}/$trackId.mp3');
      if (!await file.exists()) {
        toRemove.add(song);
      }
    }

    if (toRemove.isNotEmpty) {
      for (final song in toRemove) {
        _cache.removeWhere((s) => s['trackId'] == song['trackId']);
      }
    }
  }

  static Future<void> _saveLocalCache(String userId) async {
    try {
      final dir = await _getDownloadDir();
      final file = File('${dir.path}/cache_$userId.json');
      await file.writeAsString(jsonEncode(_cache));
    } catch (e) {
      print('Save local cache error: $e');
    }
  }

  static Future<void> _loadLocalCache(String? userId) async {
    try {
      final dir = await _getDownloadDir();
      final file = File('${dir.path}/cache_$userId.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List<dynamic>;
        _cache = list.map((s) => Map<String, dynamic>.from(s)).toList();
        await _verifyLocalFiles();
      }
      _loaded = true;
    } catch (e) {
      print('Load local cache error: $e');
    }
  }

  /// Returns true only if the track is in the CURRENT user's downloaded list.
  /// Files on disk from another account are never treated as downloaded.
  static bool isDownloaded(String trackId) {
    if (trackId.isEmpty) return false;
    return _cache.any((s) => s['trackId'] == trackId);
  }

  /// Returns the local mp3 path ONLY if this track belongs to the current
  /// user's download cache. Files from other accounts are ignored so a fresh
  /// login never plays the previous account's downloaded audio.
  static Future<String?> getLocalPath(String trackId) async {
    if (trackId.isEmpty) return null;
    if (!_cache.any((s) => s['trackId'] == trackId)) return null;
    final dir = await _getDownloadDir();
    final path = '${dir.path}/$trackId.mp3';
    final file = File(path);
    if (file.existsSync()) return path;
    return null;
  }

  static String? getLocalPathSync(String trackId) {
    if (trackId.isEmpty) return null;
    if (!_cache.any((s) => s['trackId'] == trackId)) return null;
    final dir = _downloadDir;
    if (dir == null) return null;
    final path = '${dir.path}/$trackId.mp3';
    return File(path).existsSync() ? path : null;
  }

  static int getTotalSizeSync() {
    int total = 0;
    for (final song in _cache) {
      total += (song['fileSize'] as int?) ?? 0;
    }
    return total;
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static Future<bool> download({
    required String trackId,
    required String title,
    required String artist,
    String image = '',
    String artistId = '',
    String artistImage = '',
    Duration duration = Duration.zero,
  }) async {
    try {
      if (!PremiumService().canDownloadOffline) return false;
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return false;

      if (isDownloaded(trackId)) return true;

      final dir = await _getDownloadDir();
      final existingFile = File('${dir.path}/$trackId.mp3');
      if (await existingFile.exists()) {
        // File exists on disk but not in cache — restore metadata
        _cache.insert(0, {
          'trackId': trackId,
          'title': title,
          'artist': artist,
          'image': image,
          'fileSize': await existingFile.length()
        });
        _loaded = true;
        await _saveLocalCache(user.id);
        onUpdate.value++;
        return true;
      }

      // Set downloading state
      _progress[trackId] = -1;
      _downloadingTrackId.value = trackId;
      _downloadingSongMeta = {
        'title': title,
        'artist': artist,
        'image': image,
        'artistId': artistId,
        'artistImage': artistImage
      };
      _downloadCountNotifier.value++;
      final progressNotifier = getProgressNotifier(trackId);
      progressNotifier.value = -1;
      onUpdate.value++;

      // Client-side download — 100% on the phone (zero backend).
      // Tier 1: Deezer CDN (Lossless 320/128kbps with Blowfish decryption)
      // Tier 2: JioSaavn CDN (320kbps CD Quality direct download)
      // Tier 3: ClientStream YouTube audio stream
      Uint8List? audioBytes;

      try {
        _progress[trackId] = 0.2;
        progressNotifier.value = 0.2;

        final resolvedId = int.tryParse(trackId) != null
            ? trackId
            : await DeezerService.searchTrackId(title, artist)
                .timeout(const Duration(seconds: 4));
        if (resolvedId != null) {
          _progress[trackId] = 0.4;
          progressNotifier.value = 0.4;

          final cdnUrl = await DeezerService.getCdnUrl(resolvedId)
              .timeout(const Duration(seconds: 4));
          if (cdnUrl != null) {
            _progress[trackId] = 0.6;
            progressNotifier.value = 0.6;

            final bytes = await DeezerService.downloadAndDecrypt(
              cdnUrl: cdnUrl,
              trackId: resolvedId,
            );
            if (bytes != null && bytes.isNotEmpty) {
              audioBytes = bytes;
            }
          }
        }
      } catch (deezerErr) {
        debugPrint(
            '[DownloadService] Deezer client download failed: $deezerErr, trying JioSaavn...');
      }

      // TIER 2: JioSaavn CDN Direct (Fast, 320kbps, unencrypted)
      if (audioBytes == null || audioBytes.isEmpty) {
        try {
          _progress[trackId] = 0.4;
          progressNotifier.value = 0.4;
          final jioStreamUrl = await JioSaavnService.getStreamUrl(title, artist)
              .timeout(const Duration(seconds: 3));
          if (jioStreamUrl != null && jioStreamUrl.isNotEmpty) {
            final resp = await http.get(
              Uri.parse(jioStreamUrl),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
              },
            ).timeout(const Duration(seconds: 10));
            if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
              audioBytes = resp.bodyBytes;
            }
          }
        } catch (jioErr) {
          debugPrint(
              '[DownloadService] JioSaavn download failed: $jioErr, trying on-device stream...');
        }
      }

      // TIER 3: On-Device YouTube Stream download
      if (audioBytes == null || audioBytes.isEmpty) {
        try {
          _progress[trackId] = 0.5;
          progressNotifier.value = 0.5;
          final audioStream =
              await ClientStreamService.getAudioStream(title, artist);
          if (audioStream != null) {
            final builder = BytesBuilder(copy: false);
            int received = 0;
            await for (final chunk in audioStream.byteStream) {
              builder.add(chunk);
              received += chunk.length;
              if (audioStream.size > 0) {
                final frac = 0.5 + (received / audioStream.size) * 0.4;
                _progress[trackId] = frac.clamp(0.5, 0.9);
                progressNotifier.value = frac.clamp(0.5, 0.9);
              }
            }
            final collected = builder.takeBytes();
            if (collected.isNotEmpty) {
              audioBytes = collected;
            }
          }
        } catch (streamErr) {
          debugPrint(
              '[DownloadService] On-device audio stream download failed: $streamErr');
        }
      }

      if (audioBytes == null || audioBytes.isEmpty) {
        throw Exception(
            'Unable to download track from any available client source');
      }

      _progress[trackId] = 0.95;
      progressNotifier.value = 0.95;

      // Save MP3 to local phone storage
      final file = File('${dir.path}/$trackId.mp3');
      await file.writeAsBytes(audioBytes);
      final fileSize = audioBytes.length;

      // Metadata stays on this phone only (per-user cache file)
      _cache.insert(0, {
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'image': image,
        'artistId': artistId,
        'artistImage': artistImage,
        'fileSize': fileSize,
      });
      _loaded = true;
      await _saveLocalCache(user.id);

      // Complete progress
      _progress[trackId] = 1.0;
      progressNotifier.value = 1.0;

      print('Downloaded: $title by $artist ($fileSize bytes)');

      // Clear downloading metadata
      _downloadingSongMeta = null;
      _downloadCountNotifier.value++;

      // Fetch and save lyrics in background
      _downloadLyricsInBackground(trackId, title, artist, duration);

      // Small delay then clear downloading state
      await Future.delayed(const Duration(milliseconds: 500));
      _progress.remove(trackId);
      _downloadingTrackId.value = null;
      onUpdate.value++;

      return true;
    } catch (e) {
      print('Download error: $e');
      _downloadingSongMeta = null;
      _downloadCountNotifier.value++;
      _progress.remove(trackId);
      _downloadingTrackId.value = null;
      final notifier = _trackProgressNotifiers[trackId];
      if (notifier != null) notifier.value = 0;
      onUpdate.value++;
    }
    return false;
  }

  static Future<bool> removeDownload(String trackId) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;

      final dir = await _getDownloadDir();
      final file = File('${dir.path}/$trackId.mp3');
      if (await file.exists()) {
        await file.delete();
      }

      _cache.removeWhere((s) => s['trackId'] == trackId);
      if (user != null) await _saveLocalCache(user.id);
      onUpdate.value++;

      return true;
    } catch (e) {
      print('Remove download error: $e');
    }
    return false;
  }

  /// Clears in-memory state AND deletes all downloaded audio files plus the
  /// per-user metadata cache from disk. Downloads are account-scoped on-device
  /// data, so they must not survive a logout (a re-logged-in account would
  /// otherwise see/play the previous account's songs).
  static Future<void> clearCache() async {
    _cache.clear();
    _loaded = false;
    _progress.clear();
    _downloadingSongMeta = null;
    _downloadingTrackId.value = null;
    _downloadCountNotifier.value = 0;
    _trackProgressNotifiers.clear();
    onUpdate.value++;
    if (kIsWeb) return;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/downloads');
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          try {
            await entity.delete(recursive: true);
          } catch (e) {
            print('Delete download artifact error: $e');
          }
        }
      }
    } catch (e) {
      print('Clear downloads dir error: $e');
    }
  }

  static void _downloadLyricsInBackground(
      String trackId, String title, String artist, Duration duration) async {
    try {
      // Check if already cached
      final existing = await LyricsService.loadFromCache(title, artist);
      if (existing != null) {
        // Still save LRC file for offline access by trackId
        await LyricsService.saveLrcFile(trackId, existing.toLrc());
        return;
      }

      final result = await LyricsService.fetchLyrics(
        artist: artist,
        title: title,
        duration: duration > Duration.zero
            ? duration
            : const Duration(minutes: 3, seconds: 30),
      );
      if (result != null) {
        await LyricsService.saveToCache(title, artist, result);
        await LyricsService.saveLrcFile(trackId, result.toLrc());
      }
    } catch (e) {
      print('Download lyrics fetch error: $e');
    }
  }
}
