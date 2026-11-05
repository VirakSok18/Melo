import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'search_service.dart';
import 'download_service.dart';
import 'deezer_service.dart';
import '../widgets/cached_image.dart';

/// Invisible phone-side cache of played songs (Spotify-style). Every song the
/// user actually listens to (>45s or to completion) is silently saved to a
/// dedicated folder, so replaying it later — from any section or search — is
/// instant and works fully offline.
///
/// Features an automatic 1.5 GB LRU cap, atomic write protection against
/// app crashes / power loss, and deep temp file cleaning.
class AutoCacheService {
  static const int _maxSizeBytes = 1536 * 1024 * 1024; // 1.5 GB LRU cap

  static List<Map<String, dynamic>> _index = [];
  static Directory? _cacheDir;
  static Future<void> _downloadQueue = Future.value();
  static bool _isDownloading = false;

  static Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${appDir.path}/autocache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  static String? _userId() => Supabase.instance.client.auth.currentUser?.id;

  static Future<void> init() async {
    await _getCacheDir();
    final user = _userId();
    if (user != null) {
      await _loadIndex(user);
    }
    unawaited(cleanOrphanedAndCorruptFiles());
  }

  static Future<void> _loadIndex(String userId) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/autocache_$userId.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List<dynamic>;
        _index = list.map((s) => Map<String, dynamic>.from(s)).toList();
        _verifyLocalFiles();
        _scheduleIndexSave();
      }
    } catch (e) {
      print('AutoCache load error: $e');
    }
  }

  static Future<void> _saveIndex(String userId) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/autocache_$userId.json');
      await file.writeAsString(jsonEncode(_index));
    } catch (e) {
      print('AutoCache save error: $e');
    }
  }

  static void _scheduleIndexSave() {
    final user = _userId();
    if (user == null) return;
    _saveIndex(user);
  }

  static void _verifyLocalFiles() {
    final dir = _cacheDir;
    if (dir == null) return;
    final toRemove = <String>[];
    for (final entry in _index) {
      final trackId = entry['trackId'] as String? ?? '';
      if (trackId.isEmpty) {
        toRemove.add(trackId);
        continue;
      }
      final path = '${dir.path}/$trackId.mp3';
      final f = File(path);
      if (!f.existsSync() || f.lengthSync() < 300000) {
        toRemove.add(trackId);
        try {
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
    if (toRemove.isNotEmpty) {
      _index.removeWhere((s) => toRemove.contains(s['trackId']));
    }
  }

  static bool isAutoCached(String trackId) {
    if (trackId.isEmpty) return false;
    return _index.any((s) => s['trackId'] == trackId);
  }

  static String? getLocalPath(String trackId) {
    if (trackId.isEmpty) return null;
    if (!isAutoCached(trackId)) return null;
    final dir = _cacheDir;
    if (dir == null) return null;
    final path = '${dir.path}/$trackId.mp3';
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      // Audio tracks smaller than 300 KB are corrupted or interrupted downloads
      if (file.lengthSync() < 300000) {
        file.deleteSync();
        _index.removeWhere((s) => s['trackId'] == trackId);
        _scheduleIndexSave();
        return null;
      }
    } catch (_) {
      return null;
    }
    return path;
  }

  /// Explicitly evict a track from auto-cache and delete its file if corrupted or invalid
  static void evict(String trackId) {
    if (trackId.isEmpty) return;
    try {
      final dir = _cacheDir;
      if (dir != null) {
        final file = File('${dir.path}/$trackId.mp3');
        if (file.existsSync()) file.deleteSync();
      }
    } catch (_) {}
    _index.removeWhere((s) => s['trackId'] == trackId);
    _scheduleIndexSave();
  }

  static void markPlayed(String trackId) {
    if (!isAutoCached(trackId)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in _index) {
      if (entry['trackId'] == trackId) {
        entry['lastAccessed'] = now;
        break;
      }
    }
    _scheduleIndexSave();
  }

  /// Serialized, fire-and-forget background download.
  static Future<void> cacheTrack(SearchResult track) async {
    final user = _userId();
    if (user == null) return;
    if (track.id.isEmpty) return;
    if (DownloadService.isDownloaded(track.id)) return;
    if (isAutoCached(track.id)) {
      markPlayed(track.id);
      return;
    }

    final prev = _downloadQueue;
    final completer = Completer<void>();
    _downloadQueue = prev
        .then((_) => _performDownload(user, track))
        .whenComplete(() {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  static Future<void> _performDownload(String userId, SearchResult track) async {
    if (_isDownloading) return;
    _isDownloading = true;
    try {
      if (track.id.isEmpty) return;
      if (DownloadService.isDownloaded(track.id)) return;
      if (isAutoCached(track.id)) {
        markPlayed(track.id);
        return;
      }

      final dir = await _getCacheDir();
      final file = File('${dir.path}/${track.id}.mp3');
      if (await file.exists() && await file.length() >= 300000) {
        _index.insert(0, {
          'trackId': track.id,
          'title': track.title,
          'artist': track.artist,
          'image': track.image,
          'fileSize': await file.length(),
          'lastAccessed': DateTime.now().millisecondsSinceEpoch,
        });
        await _saveIndex(userId);
        _enforceSizeCap();
        return;
      }

      final resolvedId = int.tryParse(track.id) != null
          ? track.id
          : await DeezerService.searchTrackId(track.title, track.artist);
      if (resolvedId == null) return;

      final cdnUrl = await DeezerService.getCdnUrl(resolvedId);
      if (cdnUrl == null) return;

      final audio = await DeezerService.downloadAndDecrypt(
        cdnUrl: cdnUrl,
        trackId: resolvedId,
      );
      if (audio == null || audio.length < 300000) return;

      // Write atomically to .tmp file first to prevent corruption on sudden app close or battery death
      final tmpFile = File('${file.path}.tmp');
      await tmpFile.writeAsBytes(audio, flush: true);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      await tmpFile.rename(file.path);

      _index.insert(0, {
        'trackId': track.id,
        'title': track.title,
        'artist': track.artist,
        'image': track.image,
        'fileSize': audio.length,
        'lastAccessed': DateTime.now().millisecondsSinceEpoch,
      });
      await _saveIndex(userId);
      _enforceSizeCap();
    } catch (e) {
      print('AutoCache download error: $e');
    } finally {
      _isDownloading = false;
    }
  }

  static Future<void> _enforceSizeCap() async {
    int total = 0;
    for (final entry in _index) {
      total += (entry['fileSize'] as int?) ?? 0;
    }
    if (total <= _maxSizeBytes) return;

    final sorted = List<Map<String, dynamic>>.from(_index)
      ..sort((a, b) {
        final la = (a['lastAccessed'] as int?) ?? 0;
        final lb = (b['lastAccessed'] as int?) ?? 0;
        return la.compareTo(lb);
      });

    final dir = await _getCacheDir();
    for (final entry in sorted) {
      if (total <= _maxSizeBytes) break;
      final trackId = entry['trackId'] as String? ?? '';
      final size = (entry['fileSize'] as int?) ?? 0;
      final file = File('${dir.path}/$trackId.mp3');
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('AutoCache evict error: $e');
      }
      total -= size;
      _index.removeWhere((s) => s['trackId'] == trackId);
    }

    final user = _userId();
    if (user != null) {
      await _saveIndex(user);
    }
  }

  static int get totalSize {
    int total = 0;
    for (final entry in _index) {
      total += (entry['fileSize'] as int?) ?? 0;
    }
    return total;
  }

  static int get count => _index.length;

  /// Calculates total real disk space consumed across:
  /// 1. Autocached songs folder
  /// 2. Temporary audio files
  /// 3. Cached images folder
  static Future<int> calculateDiskUsage() async {
    int total = 0;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final autoCacheDir = Directory('${appDir.path}/autocache');
      if (await autoCacheDir.exists()) {
        await for (final entity in autoCacheDir.list(recursive: false)) {
          if (entity is File && !entity.path.endsWith('.json')) {
            total += await entity.length();
          }
        }
      }

      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(recursive: false)) {
          if (entity is File) {
            final name = entity.uri.pathSegments.last;
            if (name.startsWith('yt_') ||
                name.startsWith('deezer_') ||
                name.endsWith('.mp3') ||
                name.endsWith('.webm') ||
                name.endsWith('.tmp')) {
              total += await entity.length();
            }
          }
        }
      }

      total += await CachedImageStore.getDiskUsage();
    } catch (_) {}
    return total;
  }

  /// Automatically purges corrupted, partial (<300KB), or .tmp files from previous sessions
  static Future<void> cleanOrphanedAndCorruptFiles() async {
    try {
      final dir = await _getCacheDir();
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: false)) {
          if (entity is File) {
            final name = entity.uri.pathSegments.last;
            if (name.endsWith('.tmp')) {
              try {
                await entity.delete();
              } catch (_) {}
            } else if (name.endsWith('.mp3') && await entity.length() < 300000) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }
        }
      }

      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        final now = DateTime.now();
        await for (final entity in tempDir.list(recursive: false)) {
          if (entity is File) {
            final name = entity.uri.pathSegments.last;
            if (name.endsWith('.tmp')) {
              try {
                await entity.delete();
              } catch (_) {}
            } else if (name.startsWith('yt_') || name.startsWith('deezer_')) {
              try {
                final stat = await entity.stat();
                if (stat.size < 300000 || now.difference(stat.modified).inHours > 24) {
                  await entity.delete();
                }
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
  }

  /// Thoroughly purges all playback caches, temp files, and image caches from device
  static Future<void> clearCache() async {
    _index.clear();
    final user = _userId();
    if (user != null) {
      await _saveIndex(user);
    }

    try {
      // 1. Clear autocache audio files
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/autocache');
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          try {
            if (entity is File && !entity.path.endsWith('.json')) {
              await entity.delete();
            }
          } catch (e) {
            print('AutoCache clear file error: $e');
          }
        }
      }

      // 2. Clear temp audio files
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list()) {
          if (entity is File) {
            final name = entity.uri.pathSegments.last;
            if (name.startsWith('yt_') ||
                name.startsWith('deezer_') ||
                name.endsWith('.mp3') ||
                name.endsWith('.webm') ||
                name.endsWith('.tmp')) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }
        }
      }

      // 3. Clear image cache on disk
      await CachedImageStore.clearCache();

      // 4. Evict Flutter in-memory decoded image bitmaps to free RAM
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (e) {
      print('AutoCache clear dir error: $e');
    }
  }
}
