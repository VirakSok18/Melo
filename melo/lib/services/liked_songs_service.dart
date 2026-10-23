import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lyrics_service.dart';

class LikedSongsService extends ChangeNotifier {
  static final LikedSongsService _instance = LikedSongsService._internal();
  factory LikedSongsService() => _instance;
  LikedSongsService._internal();

  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _songs = [];
  Set<String> _likedTrackIds = {};
  Set<String> _likedKeys = {};
  bool _loaded = false;
  bool _diskLoaded = false;
  RealtimeChannel? _realtimeChannel;

  static final ValueNotifier<int> onUpdate = ValueNotifier<int>(0);

  static const String _prefsKey = 'liked_songs_cache';
  static String _prefsKeyFor(String userId) => '${_prefsKey}_$userId';

  int get songCount => _songs.length;
  List<Map<String, dynamic>> get songs => List.unmodifiable(_songs);

  // Static backward compatibility forwarders
  static int get count => _instance._songs.length;
  static int get cachedCount => _instance._songs.length;
  static List<Map<String, dynamic>> get cachedSongs => _instance.songs;
  static Future<void> init() => _instance.initialize();
  static Future<List<Map<String, dynamic>>> getLikedSongs({bool force = false}) =>
      _instance.loadLikedSongs(force: force);
  static Future<bool> likeSong({
    required String trackId,
    required String title,
    required String artist,
    String image = '',
    String artistId = '',
    String artistImage = '',
    Duration duration = Duration.zero,
  }) =>
      _instance.addLike(
        trackId: trackId,
        title: title,
        artist: artist,
        image: image,
        artistId: artistId,
        artistImage: artistImage,
        duration: duration,
      );
  static Future<bool> unlikeSong(String trackId, {String? title, String? artist}) =>
      _instance.removeLike(trackId, title: title, artist: artist);
  static bool isLiked(String trackId, {String? title, String? artist}) =>
      _instance.checkIsLiked(trackId, title: title, artist: artist);
  static void clearCache() => _instance.clear();

  String _cleanId(String id) {
    if (id.isEmpty) return '';
    if (id.startsWith('deezer:')) return id.substring(7);
    if (id.startsWith('spotify:')) return id.substring(8);
    if (id.startsWith('youtube:')) return id.substring(8);
    return id;
  }

  String _normalizeKey(String title, String artist) {
    return '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}';
  }

  void _rebuildIndexes() {
    _likedTrackIds = {};
    _likedKeys = {};
    for (final s in _cacheList) {
      final tid = s['trackId']?.toString() ?? '';
      if (tid.isNotEmpty) {
        _likedTrackIds.add(tid);
        final cid = _cleanId(tid);
        if (cid.isNotEmpty) _likedTrackIds.add(cid);
      }
      final title = s['title']?.toString() ?? '';
      final artist = s['artist']?.toString() ?? '';
      if (title.isNotEmpty) {
        _likedKeys.add(_normalizeKey(title, artist));
      }
    }
  }

  List<Map<String, dynamic>> get _cacheList => _songs;

  Future<void> initialize() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    if (!_diskLoaded) {
      await _loadFromDisk(user.id);
    }
    subscribeToRealtime();
    _fetchFromNetwork(user.id);
  }

  void subscribeToRealtime() {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      if (_realtimeChannel != null) {
        _realtimeChannel?.unsubscribe();
        _realtimeChannel = null;
      }

      _realtimeChannel = _client
          .channel('liked_songs_realtime:${user.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'liked_songs',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: user.id,
            ),
            callback: (payload) {
              _handleRealtimePayload(payload);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[LikedSongsService] Realtime subscription error: $e');
    }
  }

  void _handleRealtimePayload(PostgresChangePayload payload) {
    debugPrint('[LikedSongsService] Live event: ${payload.eventType}');
    final user = _client.auth.currentUser;
    if (user == null) return;

    if (payload.eventType == PostgresChangeEvent.insert) {
      final rec = payload.newRecord;
      final trackId = rec['track_id']?.toString() ?? '';
      final title = rec['title']?.toString() ?? '';
      final artist = rec['artist']?.toString() ?? '';
      final clean = _cleanId(trackId);
      final key = _normalizeKey(title, artist);

      final alreadyInCache = (trackId.isNotEmpty && _likedTrackIds.contains(trackId)) ||
          (clean.isNotEmpty && _likedTrackIds.contains(clean)) ||
          (key.isNotEmpty && _likedKeys.contains(key));

      if (!alreadyInCache && trackId.isNotEmpty) {
        _songs.insert(0, {
          'id': rec['id']?.toString() ?? '',
          'trackId': trackId,
          'title': title,
          'artist': artist,
          'image': rec['image']?.toString() ?? '',
          'artistId': rec['artist_id']?.toString() ?? '',
          'artistImage': rec['artist_image']?.toString() ?? '',
        });
        _rebuildIndexes();
        _loaded = true;
        _saveToDisk();
        onUpdate.value++;
        notifyListeners();
      }
    } else if (payload.eventType == PostgresChangeEvent.delete) {
      final oldRec = payload.oldRecord;
      final trackId = oldRec['track_id']?.toString() ?? '';
      final dbId = oldRec['id']?.toString() ?? '';
      final title = oldRec['title']?.toString() ?? '';
      final artist = oldRec['artist']?.toString() ?? '';
      final clean = _cleanId(trackId);
      final key = (title.isNotEmpty && artist.isNotEmpty) ? _normalizeKey(title, artist) : '';

      final beforeCount = _songs.length;
      _songs.removeWhere((s) {
        final sId = s['id']?.toString() ?? '';
        final sTid = s['trackId']?.toString() ?? '';
        final sClean = _cleanId(sTid);
        final sKey = _normalizeKey(s['title']?.toString() ?? '', s['artist']?.toString() ?? '');

        if (dbId.isNotEmpty && sId == dbId) return true;
        if (trackId.isNotEmpty && sTid == trackId) return true;
        if (clean.isNotEmpty && sClean == clean) return true;
        if (key.isNotEmpty && sKey == key) return true;
        return false;
      });

      if (_songs.length != beforeCount) {
        _rebuildIndexes();
        _saveToDisk();
        onUpdate.value++;
        notifyListeners();
      }
    }
  }

  Future<void> _loadFromDisk(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKeyFor(userId));
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>;
        _songs = list.map((s) => Map<String, dynamic>.from(s)).toList();
        _rebuildIndexes();
        _loaded = true;
        notifyListeners();
      }
      _diskLoaded = true;
    } catch (e) {
      debugPrint('[LikedSongsService] Disk load error: $e');
    }
  }

  Future<void> _saveToDisk() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyFor(user.id), jsonEncode(_songs));
    } catch (e) {
      debugPrint('[LikedSongsService] Disk save error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> loadLikedSongs({bool force = false}) async {
    final user = _client.auth.currentUser;
    if (user == null) return _songs;

    subscribeToRealtime();

    if (!_diskLoaded) {
      await _loadFromDisk(user.id);
    }

    if (!force && _loaded && _songs.isNotEmpty) {
      return _songs;
    }

    _fetchFromNetwork(user.id);
    return _songs;
  }

  Future<void> _fetchFromNetwork(String userId) async {
    try {
      final rows = await _client
          .from('liked_songs')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 15));

      final List<Map<String, dynamic>> freshList = (rows as List)
          .map((r) => {
                'id': r['id']?.toString() ?? '',
                'trackId': r['track_id']?.toString() ?? '',
                'title': r['title']?.toString() ?? '',
                'artist': r['artist']?.toString() ?? '',
                'image': r['image']?.toString() ?? '',
                'artistId': r['artist_id']?.toString() ?? '',
                'artistImage': r['artist_image']?.toString() ?? '',
              })
          .toList();

      final existingKeys = _songs.map((s) => _normalizeKey(s['title'] ?? '', s['artist'] ?? '')).toSet();
      final existingIds = _songs.map((s) => s['trackId']?.toString() ?? '').toSet();

      // Merge remote items without ever overwriting newly added local songs
      for (final remote in freshList) {
        final rId = remote['trackId']?.toString() ?? '';
        final rKey = _normalizeKey(remote['title'] ?? '', remote['artist'] ?? '');
        if (!existingIds.contains(rId) && !existingKeys.contains(rKey)) {
          _songs.add(remote);
          existingIds.add(rId);
          existingKeys.add(rKey);
        }
      }

      _rebuildIndexes();
      _loaded = true;
      await _saveToDisk();

      onUpdate.value++;
      notifyListeners();
    } catch (e) {
      debugPrint('[LikedSongsService] Fetch error: $e');
    }
  }

  Future<bool> addLike({
    required String trackId,
    required String title,
    required String artist,
    String image = '',
    String artistId = '',
    String artistImage = '',
    Duration duration = Duration.zero,
  }) async {
    final user = _client.auth.currentUser;
    final userId = user?.id ?? '';

    // 1. Instant optimistic update (0ms UI feedback, just like PlaylistService)
    final cleanId = _cleanId(trackId);
    final key = _normalizeKey(title, artist);

    final isAlreadyLiked = (trackId.isNotEmpty && _likedTrackIds.contains(trackId)) ||
        (cleanId.isNotEmpty && _likedTrackIds.contains(cleanId)) ||
        (key.isNotEmpty && _likedKeys.contains(key));

    if (!isAlreadyLiked) {
      if (trackId.isNotEmpty) _likedTrackIds.add(trackId);
      if (cleanId.isNotEmpty) _likedTrackIds.add(cleanId);
      if (key.isNotEmpty) _likedKeys.add(key);

      _songs.insert(0, {
        'id': '',
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'image': image,
        'artistId': artistId,
        'artistImage': artistImage,
      });

      _loaded = true;
      await _saveToDisk();
      onUpdate.value++;
      notifyListeners();
    }

    // 2. Fetch lyrics in background
    _fetchLyricsInBackground(title, artist, duration);

    // 3. Persist to Supabase in background (identical to PlaylistService)
    if (userId.isNotEmpty) {
      try {
        await _client.from('liked_songs').insert({
          'user_id': userId,
          'track_id': trackId,
          'title': title,
          'artist': artist,
          'image': image,
          'artist_id': artistId,
          'artist_image': artistImage,
        }).timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('[LikedSongsService] Supabase insert warning: $e');
      }
    }
    return true;
  }

  void _fetchLyricsInBackground(String title, String artist, Duration duration) async {
    try {
      final existing = await LyricsService.loadFromCache(title, artist);
      if (existing != null) return;

      final result = await LyricsService.fetchLyrics(
        artist: artist,
        title: title,
        duration: duration > Duration.zero ? duration : const Duration(minutes: 3, seconds: 30),
      );
      if (result != null) {
        await LyricsService.saveToCache(title, artist, result);
      }
    } catch (e) {
      debugPrint('[LikedSongsService] Like lyrics fetch error: $e');
    }
  }

  Future<bool> removeLike(String trackId, {String? title, String? artist}) async {
    final user = _client.auth.currentUser;
    final userId = user?.id ?? '';

    // 1. Instant optimistic update
    final cleanId = _cleanId(trackId);
    final key = (title != null && artist != null && title.isNotEmpty)
        ? _normalizeKey(title, artist)
        : '';

    final beforeCount = _songs.length;
    _songs.removeWhere((s) {
      final sTrackId = s['trackId']?.toString() ?? '';
      final sClean = _cleanId(sTrackId);
      final sKey = _normalizeKey(s['title']?.toString() ?? '', s['artist']?.toString() ?? '');

      if (trackId.isNotEmpty && sTrackId == trackId) return true;
      if (cleanId.isNotEmpty && sClean == cleanId) return true;
      if (key.isNotEmpty && sKey == key) return true;
      return false;
    });

    if (trackId.isNotEmpty) _likedTrackIds.remove(trackId);
    if (cleanId.isNotEmpty) _likedTrackIds.remove(cleanId);
    if (key.isNotEmpty) _likedKeys.remove(key);

    if (_songs.length != beforeCount) {
      _rebuildIndexes();
      await _saveToDisk();
      onUpdate.value++;
      notifyListeners();
    }

    // 2. Persist delete to Supabase
    if (userId.isNotEmpty) {
      try {
        if (trackId.isNotEmpty) {
          await _client
              .from('liked_songs')
              .delete()
              .eq('user_id', userId)
              .eq('track_id', trackId)
              .timeout(const Duration(seconds: 10));
        }
        if (title != null && artist != null && title.isNotEmpty) {
          await _client
              .from('liked_songs')
              .delete()
              .eq('user_id', userId)
              .eq('title', title)
              .eq('artist', artist)
              .timeout(const Duration(seconds: 10));
        }
      } catch (e) {
        debugPrint('[LikedSongsService] Supabase delete warning: $e');
      }
    }
    return true;
  }

  bool checkIsLiked(String trackId, {String? title, String? artist}) {
    if (trackId.isNotEmpty) {
      if (_likedTrackIds.contains(trackId)) return true;
      final clean = _cleanId(trackId);
      if (clean.isNotEmpty && _likedTrackIds.contains(clean)) return true;
    }
    if (title != null && artist != null && title.trim().isNotEmpty) {
      final key = _normalizeKey(title, artist);
      if (_likedKeys.contains(key)) return true;
    }
    return false;
  }

  void clear() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    _songs.clear();
    _likedTrackIds.clear();
    _likedKeys.clear();
    _loaded = false;
    _diskLoaded = false;
    notifyListeners();
  }
}
