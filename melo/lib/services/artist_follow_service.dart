import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ArtistFollowService extends ChangeNotifier {
  static final ArtistFollowService _instance = ArtistFollowService._internal();
  factory ArtistFollowService() => _instance;
  ArtistFollowService._internal();

  final Set<String> _followedIds = {};
  List<Map<String, dynamic>> _followedArtists = [];
  RealtimeChannel? _channel;
  bool _loaded = false;

  static const String _prefsKey = 'followed_artists_cache';
  static String _prefsKeyFor(String userId) => '${_prefsKey}_$userId';

  List<Map<String, dynamic>> get followedArtists =>
      List.unmodifiable(_followedArtists);
  Set<String> get followedIds => Set.unmodifiable(_followedIds);
  bool get loaded => _loaded;

  bool isFollowing(String artistId) => _followedIds.contains(artistId);

  /// Loads this user's followed artists from disk so a fresh offline start
  /// still shows them. Called from AuthGate right after login.
  Future<void> init() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _loaded) return;
    await _loadFromDisk(user.id);
  }

  Future<void> _loadFromDisk(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKeyFor(userId));
      if (raw == null) return;
      final list = jsonDecode(raw) as List<dynamic>;
      _followedArtists =
          list.map((a) => Map<String, dynamic>.from(a as Map)).toList();
      _followedIds.clear();
      for (final artist in _followedArtists) {
        final id = artist['artist_id'] ?? '';
        if (id.isNotEmpty) _followedIds.add(id);
      }
      _loaded = true;
      notifyListeners();
    } catch (e) {
      print('Followed artists disk load error: $e');
    }
  }

  Future<void> _saveToDisk() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKeyFor(user.id), jsonEncode(_followedArtists));
    } catch (e) {
      print('Followed artists disk save error: $e');
    }
  }

  Future<void> loadFollowedArtists() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final rows = await Supabase.instance.client
          .from('artist_follows')
          .select('artist_id, artist_name, artist_image')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10));

      _followedArtists = (rows as List)
          .map((r) => <String, dynamic>{
                'artist_id': r['artist_id']?.toString() ?? '',
                'artist_name': r['artist_name']?.toString() ?? '',
                'artist_image': r['artist_image']?.toString() ?? '',
              })
          .toList();
      _followedIds.clear();
      for (final artist in _followedArtists) {
        final id = artist['artist_id'] ?? '';
        if (id.isNotEmpty) _followedIds.add(id);
      }
      _loaded = true;
      await _saveToDisk();
      notifyListeners();
    } catch (e) {
      print('Load followed artists error: $e');
      // Offline — fall back to whatever was cached on disk.
      if (!_loaded) await _loadFromDisk(user.id);
    }
  }

  Future<void> followArtist({
    required String artistId,
    required String artistName,
    String artistImage = '',
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Optimistic update
    _followedIds.add(artistId);
    _followedArtists.insert(0, <String, dynamic>{
      'artist_id': artistId,
      'artist_name': artistName,
      'artist_image': artistImage,
    });
    _loaded = true;
    notifyListeners();

    try {
      await Supabase.instance.client.from('artist_follows').upsert({
        'user_id': user.id,
        'artist_id': artistId,
        'artist_name': artistName,
        'artist_image': artistImage,
      }, onConflict: 'user_id,artist_id');
      await _saveToDisk();
    } catch (e) {
      print('Follow artist error: $e');
      // Revert on failure
      _followedIds.remove(artistId);
      _followedArtists.removeWhere((a) => a['artist_id'] == artistId);
      notifyListeners();
    }
  }

  Future<void> unfollowArtist(String artistId) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Optimistic update
    _followedIds.remove(artistId);
    _followedArtists.removeWhere((a) => a['artist_id'] == artistId);
    notifyListeners();

    try {
      await Supabase.instance.client
          .from('artist_follows')
          .delete()
          .eq('user_id', user.id)
          .eq('artist_id', artistId)
          .timeout(const Duration(seconds: 10));
      await _saveToDisk();
    } catch (e) {
      print('Unfollow artist error: $e');
      // Revert on failure
      _followedIds.add(artistId);
      _followedArtists.add(<String, dynamic>{
        'artist_id': artistId,
        'artist_name': '',
        'artist_image': '',
      });
      notifyListeners();
    }
  }

  Future<void> updateArtistImage(String artistId, String newImage) async {
    if (artistId.isEmpty || newImage.isEmpty) return;
    var changed = false;
    for (final a in _followedArtists) {
      if (a['artist_id'] == artistId) {
        if (a['artist_image'] != newImage) {
          a['artist_image'] = newImage;
          changed = true;
        }
      }
    }
    if (changed) {
      notifyListeners();
      await _saveToDisk();
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        try {
          await Supabase.instance.client
              .from('artist_follows')
              .update({'artist_image': newImage})
              .eq('user_id', user.id)
              .eq('artist_id', artistId);
        } catch (_) {}
      }
    }
  }

  void subscribeToChanges() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _channel?.unsubscribe();

    _channel = Supabase.instance.client
        .channel('artist_follows:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'artist_follows',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            // Refresh the list on any change
            loadFollowedArtists();
          },
        )
        .subscribe();
  }

  void unsubscribe() {
    _channel?.unsubscribe();
    _channel = null;
  }

  void clearCache() {
    _followedIds.clear();
    _followedArtists.clear();
    _loaded = false;
    notifyListeners();
  }
}
