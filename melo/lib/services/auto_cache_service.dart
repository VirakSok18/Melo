import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'search_service.dart';
import 'download_service.dart';
import 'deezer_service.dart';

/// Invisible phone-side cache of played songs (Spotify-style). Every song the
/// user actually listens to (>45s or to completion) is silently saved to a
/// dedicated folder, so replaying it later — from any section or search — is
/// instant and works fully offline. It never appears in the Downloads tab or
/// any other UI, and it is a separate system from explicit downloads: the
/// auto-cache pool has its own 5GB LRU cap, while explicit downloads are never
/// evicted automatically.
class AutoCacheService {
  static const int _maxSizeBytes = 5 * 1024 * 1024 * 1024; // 5 GB

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
      if (!File(path).existsSync()) {
        toRemove.add(trackId);
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
      if (file.lengthSync() < 50000) {
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

  /// Serialized, fire-and-forget background download. Cached songs are saved
  /// only to the auto-cache folder and never surface anywhere in the UI.
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
      if (await file.exists() && await file.length() > 0) {
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

      // Client-side Deezer download — no backend. Resolve the Deezer track ID
      // (search results already carry it; YouTube-sourced tracks get matched
      // by title/artist), then CDN URL → download → Blowfish decrypt.
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
      if (audio == null || audio.isEmpty) return;

      await file.writeAsBytes(audio);
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

  static Future<void> clearCache() async {
    _index.clear();
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/autocache');
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          try {
            await entity.delete(recursive: true);
          } catch (e) {
            print('AutoCache clear error: $e');
          }
        }
      }
    } catch (e) {
      print('AutoCache clear dir error: $e');
    }
  }
}