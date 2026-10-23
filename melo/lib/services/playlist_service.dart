import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_service.dart';
import 'notification_service.dart';

class PlaylistSong {
  final String trackId;
  final String title;
  final String artist;
  final String image;
  final String duration;
  final String artistId;
  final String artistImage;
  final String addedById;
  final String addedByName;
  final String addedByAvatar;

  PlaylistSong({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.image,
    this.duration = '',
    this.artistId = '',
    this.artistImage = '',
    this.addedById = '',
    this.addedByName = '',
    this.addedByAvatar = '',
  });

  Map<String, dynamic> toMap() => {
        'track_id': trackId,
        'title': title,
        'artist': artist,
        'image': image,
        'duration': duration,
        'artist_id': artistId,
        'artist_image': artistImage,
        'added_by_id': addedById,
        'added_by_name': addedByName,
        'added_by_avatar': addedByAvatar,
      };

  factory PlaylistSong.fromMap(Map<String, dynamic> json) => PlaylistSong(
        trackId: json['track_id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        artist: json['artist']?.toString() ?? '',
        image: json['image']?.toString() ?? '',
        duration: json['duration']?.toString() ?? '',
        artistId: json['artist_id']?.toString() ?? '',
        artistImage: json['artist_image']?.toString() ?? '',
        addedById: json['added_by_id']?.toString() ??
            json['user_id']?.toString() ??
            '',
        addedByName: json['added_by_name']?.toString() ?? '',
        addedByAvatar: json['added_by_avatar']?.toString() ?? '',
      );
}

class UserPlaylist {
  final String id;
  final String userId;
  String name;
  String? coverImage;
  bool isCollaborative;
  bool isPublic;
  List<PlaylistSong> songs;
  List<Map<String, dynamic>> collaborators;
  final DateTime createdAt;
  String creatorName;
  String creatorAvatar;

  UserPlaylist({
    required this.id,
    this.userId = '',
    required this.name,
    this.coverImage,
    this.isCollaborative = false,
    this.isPublic = true,
    required this.songs,
    this.collaborators = const [],
    required this.createdAt,
    this.creatorName = '',
    this.creatorAvatar = '',
  });

  /// If user has not set a custom cover, use the first song's image as the cover
  String? get effectiveCoverImage {
    if (coverImage != null && coverImage!.isNotEmpty) {
      return coverImage;
    }
    if (songs.isNotEmpty) {
      for (final song in songs) {
        if (song.image.isNotEmpty) {
          return song.image;
        }
      }
    }
    return null;
  }

  /// ImageProvider for the effective cover (custom cover or first song)
  ImageProvider? get effectiveCoverProvider {
    return PlaylistService.coverImageProvider(effectiveCoverImage);
  }
}

class PlaylistService extends ChangeNotifier {
  static final PlaylistService _instance = PlaylistService._internal();
  factory PlaylistService() => _instance;
  PlaylistService._internal();

  final _client = Supabase.instance.client;
  List<UserPlaylist> _playlists = [];
  List<UserPlaylist> _collabPlaylists = [];
  bool _loaded = false;
  RealtimeChannel? _collabInvitesChannel;
  RealtimeChannel? _playlistsRealtimeChannel;

  Set<String> _handledInviteIds = {};
  Set<String> _acceptedInviteIds = {};
  Set<String> _seenInviteIds = {};
  int _pendingInvitesCount = 0;
  int _unseenPendingInvitesCount = 0;

  List<UserPlaylist> get playlists => _playlists;
  List<UserPlaylist> get collabPlaylists => _collabPlaylists;
  List<UserPlaylist> get receivedInvites => _collabPlaylists
      .where((p) =>
          p.userId.isNotEmpty &&
          p.userId != _userId &&
          !_handledInviteIds.contains(p.id))
      .toList();
  int get receivedInvitesCount => _pendingInvitesCount;
  int get unreadInvitesCount => _unseenPendingInvitesCount;
  bool get loaded => _loaded;

  ValueNotifier<int> onUpdate = ValueNotifier(0);

  String get _userId => _client.auth.currentUser?.id ?? '';

  static const String _prefsKey = 'user_playlists_cache';
  static String _prefsKeyFor(String userId) => '${_prefsKey}_$userId';
  static String _handledInvitesKeyFor(String userId) =>
      'handled_collab_invites_$userId';
  static String _acceptedInvitesKeyFor(String userId) =>
      'accepted_collab_invites_$userId';
  static String _seenInvitesKeyFor(String userId) =>
      'seen_collab_invites_$userId';

  Future<void> init() async {
    final userId = _userId;
    if (userId.isEmpty || _loaded) return;
    await _loadFromDisk(userId);
    _subscribeToRealtime(userId);
  }

  void _subscribeToRealtime(String userId) {
    // 1. Listen for collaborator invites/removals
    _collabInvitesChannel?.unsubscribe();
    _collabInvitesChannel = _client
        .channel('playlist_collabs_realtime:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'playlist_collaborators',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) async {
            debugPrint(
                '[PlaylistService] Live collab change detected: ${payload.eventType}');
            if (payload.eventType == PostgresChangeEvent.insert) {
              final newRec = payload.newRecord;
              final role = newRec['role']?.toString() ?? '';
              final pId = newRec['playlist_id']?.toString() ?? '';
              if (role == 'pending' && pId.isNotEmpty) {
                try {
                  final pRow = await _client
                      .from('user_playlists')
                      .select('name, user_id')
                      .eq('id', pId)
                      .maybeSingle();
                  if (pRow != null) {
                    final pName = pRow['name']?.toString() ?? 'Playlist';
                    final ownerId = pRow['user_id']?.toString() ?? '';
                    String ownerName = 'A friend';
                    if (ownerId.isNotEmpty) {
                      final uRow = await _client
                          .from('profiles')
                          .select('display_name, username')
                          .eq('id', ownerId)
                          .maybeSingle();
                      if (uRow != null) {
                        final dName = uRow['display_name']?.toString() ?? '';
                        final uName = uRow['username']?.toString() ?? '';
                        ownerName = dName.isNotEmpty
                            ? dName
                            : (uName.isNotEmpty ? '@$uName' : 'A friend');
                      }
                    }
                    NotificationService().showPlaylistInviteNotification(
                      playlistId: pId,
                      playlistName: pName,
                      senderName: ownerName,
                    );
                  }
                } catch (e) {
                  debugPrint('[PlaylistService] Collab invite alert error: $e');
                }
              }
            }
            reloadPlaylists();
          },
        )
        .onBroadcast(
          event: 'collab_invite',
          callback: (payload) {
            final data = Map<String, dynamic>.from(payload);
            final targetUserId = data['target_user_id']?.toString() ?? '';
            final playlistId = data['playlist_id']?.toString() ?? '';
            final playlistName =
                data['playlist_name']?.toString() ?? 'a playlist';
            final senderName = data['sender_name']?.toString() ?? 'A friend';

            if (targetUserId == userId && playlistId.isNotEmpty) {
              NotificationService().showPlaylistInviteNotification(
                playlistId: playlistId,
                playlistName: playlistName,
                senderName: senderName,
              );
              reloadPlaylists();
            }
          },
        )
        .onBroadcast(
          event: 'collab_accepted',
          callback: (payload) {
            final data = Map<String, dynamic>.from(payload);
            final ownerId = data['owner_id']?.toString() ?? '';
            final acceptorName =
                data['acceptor_name']?.toString() ?? 'A friend';
            final playlistName =
                data['playlist_name']?.toString() ?? 'your playlist';
            final playlistId = data['playlist_id']?.toString() ?? '';

            if (ownerId == userId && playlistId.isNotEmpty) {
              NotificationService().showInviteAcceptedNotification(
                playlistId: playlistId,
                playlistName: playlistName,
                userName: acceptorName,
              );
              reloadPlaylists();
            }
          },
        )
        .subscribe();

    // 2. Listen for playlist metadata (name, cover image, collaborative status) updates
    _playlistsRealtimeChannel?.unsubscribe();
    _playlistsRealtimeChannel = _client
        .channel('user_playlists_global_realtime:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_playlists',
          callback: (payload) async {
            debugPrint(
                '[PlaylistService] Live user_playlists change: ${payload.eventType}');
            if (payload.eventType == PostgresChangeEvent.update) {
              final newRec = payload.newRecord;
              final pId = newRec['id']?.toString() ?? '';
              if (pId.isEmpty) return;
              final idx = _playlists.indexWhere((p) => p.id == pId);
              if (idx >= 0) {
                if (newRec.containsKey('name') && newRec['name'] != null) {
                  _playlists[idx].name = newRec['name'].toString();
                }
                if (newRec.containsKey('cover_image')) {
                  _playlists[idx].coverImage =
                      newRec['cover_image']?.toString();
                }
                if (newRec.containsKey('is_collaborative')) {
                  _playlists[idx].isCollaborative =
                      newRec['is_collaborative'] == true;
                }
                if (newRec.containsKey('is_public')) {
                  _playlists[idx].isPublic = newRec['is_public'] != false;
                }
                _collabPlaylists =
                    _playlists.where((p) => p.isCollaborative).toList();
                await _saveToDisk();
                onUpdate.value++;
                notifyListeners();
              } else {
                // If not in local cache, user may have just been invited or it's a new collab
                reloadPlaylists();
              }
            } else if (payload.eventType == PostgresChangeEvent.delete) {
              final oldRec = payload.oldRecord;
              final pId = oldRec['id']?.toString() ?? '';
              if (pId.isNotEmpty) {
                _playlists.removeWhere((p) => p.id == pId);
                _collabPlaylists.removeWhere((p) => p.id == pId);
                await _saveToDisk();
                onUpdate.value++;
                notifyListeners();
              }
            } else if (payload.eventType == PostgresChangeEvent.insert) {
              final newRec = payload.newRecord;
              final pId = newRec['id']?.toString() ?? '';
              if (pId.isNotEmpty && _playlists.any((p) => p.id == pId)) {
                // Already present in memory, ignore duplicate realtime insert
                return;
              }
              final creatorId = newRec['user_id']?.toString() ?? '';
              final isCollab = newRec['is_collaborative'] == true;
              if (creatorId == _userId || isCollab) {
                reloadPlaylists();
              }
            }
          },
        )
        .subscribe();
  }

  void _deduplicate() {
    final seen = <String>{};
    _playlists =
        _playlists.where((p) => p.id.isNotEmpty && seen.add(p.id)).toList();
    final seenCollab = <String>{};
    _collabPlaylists = _collabPlaylists
        .where((p) => p.id.isNotEmpty && seenCollab.add(p.id))
        .toList();
  }

  Future<void> _loadFromDisk(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKeyFor(userId));
      final handledList =
          prefs.getStringList(_handledInvitesKeyFor(userId)) ?? [];
      _handledInviteIds = handledList.toSet();
      final acceptedList =
          prefs.getStringList(_acceptedInvitesKeyFor(userId)) ?? [];
      _acceptedInviteIds = acceptedList.toSet();
      final seenList = prefs.getStringList(_seenInvitesKeyFor(userId)) ?? [];
      _seenInviteIds = seenList.toSet();

      if (raw == null) return;
      final list = jsonDecode(raw) as List<dynamic>;
      final Map<String, UserPlaylist> diskMap = {};
      for (final p in list) {
        final m = Map<String, dynamic>.from(p as Map);
        final id = m['id']?.toString() ?? '';
        if (id.isEmpty || diskMap.containsKey(id)) continue;
        final pUserId = m['user_id']?.toString() ?? userId;
        final isCollab = m['is_collaborative'] == true;
        final isPub = m['is_public'] != false;
        if (pUserId == userId || _acceptedInviteIds.contains(id) || isCollab) {
          diskMap[id] = UserPlaylist(
            id: id,
            userId: pUserId,
            name: m['name'] ?? '',
            coverImage: m['cover_image'],
            isCollaborative: isCollab,
            isPublic: isPub,
            songs: ((m['songs'] as List<dynamic>? ?? []))
                .map((s) =>
                    PlaylistSong.fromMap(Map<String, dynamic>.from(s as Map)))
                .toList(),
            createdAt:
                DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now(),
          );
        }
      }
      _playlists = diskMap.values.toList();
      _collabPlaylists = _playlists.where((p) => p.isCollaborative).toList();
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[PlaylistService] Playlists disk load error: $e');
    }
  }

  Future<void> _saveToDisk() async {
    final userId = _userId;
    if (userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKeyFor(userId),
        jsonEncode(_playlists
            .map((p) => {
                  'id': p.id,
                  'user_id': p.userId,
                  'name': p.name,
                  'cover_image': p.coverImage,
                  'is_collaborative': p.isCollaborative,
                  'is_public': p.isPublic,
                  'created_at': p.createdAt.toIso8601String(),
                  'songs': p.songs.map((s) => s.toMap()).toList(),
                })
            .toList()),
      );
      await prefs.setStringList(
        _handledInvitesKeyFor(userId),
        _handledInviteIds.toList(),
      );
      await prefs.setStringList(
        _acceptedInvitesKeyFor(userId),
        _acceptedInviteIds.toList(),
      );
      await prefs.setStringList(
        _seenInvitesKeyFor(userId),
        _seenInviteIds.toList(),
      );
    } catch (e) {
      debugPrint('[PlaylistService] Playlists disk save error: $e');
    }
  }

  bool isInviteAccepted(String playlistId) =>
      _acceptedInviteIds.contains(playlistId);

  bool isInviteHandled(String playlistId) =>
      _handledInviteIds.contains(playlistId) ||
      _acceptedInviteIds.contains(playlistId);

  Future<void> acceptInvite(String playlistId) async {
    _handledInviteIds.add(playlistId);
    _acceptedInviteIds.add(playlistId);
    _pendingInvitesCount = (_pendingInvitesCount - 1).clamp(0, 9999);

    if (_userId.isNotEmpty) {
      try {
        await _client
            .from('playlist_collaborators')
            .update({'role': 'editor'})
            .eq('playlist_id', playlistId)
            .eq('user_id', _userId);
      } catch (e) {
        debugPrint('[PlaylistService] acceptInvite DB sync error: $e');
      }

      // Broadcast invite accepted to playlist owner
      try {
        final p = getPlaylist(playlistId);
        final ownerId = p?.userId;
        final profile = ProfileService();
        final myName = profile.displayName.isNotEmpty
            ? profile.displayName
            : (_client.auth.currentUser?.userMetadata?['display_name'] ??
                'A friend');
        if (ownerId != null && ownerId.isNotEmpty && ownerId != _userId) {
          final alertChannel =
              _client.channel('playlist_collabs_realtime:$ownerId');
          await alertChannel.sendBroadcastMessage(
            event: 'collab_accepted',
            payload: {
              'owner_id': ownerId,
              'acceptor_id': _userId,
              'acceptor_name': myName,
              'playlist_id': playlistId,
              'playlist_name': p?.name ?? 'your playlist',
            },
          );
        }
      } catch (e) {
        debugPrint('[PlaylistService] Broadcast collab accepted error: $e');
      }
    }

    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx >= 0) {
      _playlists[idx].isCollaborative = true;
    }
    _collabPlaylists = _playlists.where((p) => p.isCollaborative).toList();
    await _saveToDisk();
    await reloadPlaylists();
    onUpdate.value++;
    notifyListeners();
  }

  Future<void> declineInvite(String playlistId) async {
    _handledInviteIds.add(playlistId);
    _acceptedInviteIds.remove(playlistId);
    _pendingInvitesCount = (_pendingInvitesCount - 1).clamp(0, 9999);
    final userId = _userId;
    if (userId.isNotEmpty) {
      await removeCollaborator(playlistId, userId);
    }
    _playlists.removeWhere((p) => p.id == playlistId);
    _collabPlaylists.removeWhere((p) => p.id == playlistId);
    await _saveToDisk();
    onUpdate.value++;
    notifyListeners();
  }

  Future<void> clearAllInvites(List<String> playlistIds) async {
    _handledInviteIds.addAll(playlistIds);
    await _saveToDisk();
    onUpdate.value++;
    notifyListeners();
  }

  Future<void> markInvitesAsSeen() async {
    final userId = _userId;
    if (userId.isEmpty) return;
    try {
      final collabRows = await _client
          .from('playlist_collaborators')
          .select('playlist_id, role')
          .eq('user_id', userId);
      for (final c in (collabRows as List)) {
        final pId = c['playlist_id']?.toString() ?? '';
        if (pId.isNotEmpty) {
          _seenInviteIds.add(pId);
        }
      }
      _unseenPendingInvitesCount = 0;
      await _saveToDisk();
      onUpdate.value++;
      notifyListeners();
    } catch (e) {
      debugPrint('[PlaylistService] markInvitesAsSeen error: $e');
    }
  }

  Future<UserPlaylist?> fetchPlaylistById(String playlistId) async {
    final existing = getPlaylist(playlistId);
    if (existing != null && existing.songs.isNotEmpty) {
      return existing;
    }

    try {
      final pData = await _client
          .from('user_playlists')
          .select()
          .eq('id', playlistId)
          .maybeSingle();

      if (pData == null) return existing;

      final songsData = await _client
          .from('playlist_songs')
          .select()
          .eq('playlist_id', playlistId)
          .order('position', ascending: true);

      final songs =
          (songsData as List).map((s) => PlaylistSong.fromMap(s)).toList();

      final playlist = UserPlaylist(
        id: playlistId,
        userId: pData['user_id']?.toString() ?? '',
        name: pData['name']?.toString() ?? 'Playlist',
        coverImage: pData['cover_image']?.toString(),
        isCollaborative: pData['is_collaborative'] == true,
        isPublic: pData['is_public'] != false,
        songs: songs,
        createdAt: DateTime.tryParse(pData['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );

      final idx = _playlists.indexWhere((p) => p.id == playlistId);
      if (idx >= 0) {
        _playlists[idx] = playlist;
      } else {
        _playlists.add(playlist);
      }

      if (playlist.isCollaborative &&
          !_collabPlaylists.any((p) => p.id == playlistId)) {
        _collabPlaylists.add(playlist);
      }

      await _saveToDisk();
      onUpdate.value++;
      notifyListeners();
      return playlist;
    } catch (e) {
      debugPrint('[PlaylistService] fetchPlaylistById error: $e');
      return existing;
    }
  }

  Future<void> loadPlaylists({bool forceRefresh = false}) async {
    if (_loaded && !forceRefresh) return;
    if (_userId.isEmpty) return;

    try {
      final data = await _client
          .from('user_playlists')
          .select()
          .eq('user_id', _userId)
          .order('created_at', ascending: false);

      final oldPlaylists = List<UserPlaylist>.from(_playlists);
      final Map<String, UserPlaylist> playlistMap = {};

      for (final p in data) {
        final pId = p['id']?.toString() ?? '';
        if (pId.isEmpty) continue;
        final oldIdx = oldPlaylists.indexWhere((item) => item.id == pId);
        final List<PlaylistSong> finalSongs;

        if (oldIdx >= 0 &&
            isRecentlyReordered(pId) &&
            oldPlaylists[oldIdx].songs.isNotEmpty) {
          finalSongs = oldPlaylists[oldIdx].songs;
        } else {
          final songsData = await _client
              .from('playlist_songs')
              .select()
              .eq('playlist_id', pId)
              .order('position', ascending: true);
          finalSongs =
              (songsData as List).map((s) => PlaylistSong.fromMap(s)).toList();
        }

        playlistMap[pId] = UserPlaylist(
          id: pId,
          userId: p['user_id'] ?? _userId,
          name: p['name'] ?? 'Playlist',
          coverImage: p['cover_image'],
          isCollaborative: p['is_collaborative'] == true,
          isPublic: p['is_public'] != false,
          songs: finalSongs,
          createdAt: DateTime.tryParse(p['created_at']?.toString() ?? '') ??
              DateTime.now(),
        );
      }

      // Also load playlists where user is an ACCEPTED collaborator
      try {
        final collabRows = await _client
            .from('playlist_collaborators')
            .select('playlist_id, role')
            .eq('user_id', _userId);

        final collabList = (collabRows as List);

        // Active accepted collaborator playlists (any role != 'pending')
        final acceptedIds = collabList
            .where((c) =>
                (c['role']?.toString() ?? 'editor').toLowerCase() != 'pending')
            .map((c) => c['playlist_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty && !playlistMap.containsKey(id))
            .toList();

        // Update pending invites count (unaccepted & unhandled)
        final pendingIds = collabList
            .where(
                (c) => (c['role']?.toString() ?? '').toLowerCase() == 'pending')
            .map((c) => c['playlist_id']?.toString() ?? '')
            .where((id) =>
                id.isNotEmpty &&
                !_acceptedInviteIds.contains(id) &&
                !_handledInviteIds.contains(id))
            .toList();

        _pendingInvitesCount = pendingIds.length;
        _unseenPendingInvitesCount =
            pendingIds.where((id) => !_seenInviteIds.contains(id)).length;

        if (acceptedIds.isNotEmpty) {
          final invitedPlaylistsData = await _client
              .from('user_playlists')
              .select()
              .inFilter('id', acceptedIds);

          for (final p in (invitedPlaylistsData as List)) {
            final pId = p['id']?.toString() ?? '';
            if (pId.isEmpty || playlistMap.containsKey(pId)) continue;
            final oldIdx = oldPlaylists.indexWhere((item) => item.id == pId);
            final List<PlaylistSong> finalSongs;

            if (oldIdx >= 0 &&
                isRecentlyReordered(pId) &&
                oldPlaylists[oldIdx].songs.isNotEmpty) {
              finalSongs = oldPlaylists[oldIdx].songs;
            } else {
              final songsData = await _client
                  .from('playlist_songs')
                  .select()
                  .eq('playlist_id', pId)
                  .order('position', ascending: true);
              finalSongs = (songsData as List)
                  .map((s) => PlaylistSong.fromMap(s))
                  .toList();
            }

            playlistMap[pId] = UserPlaylist(
              id: pId,
              userId: p['user_id'] ?? '',
              name: p['name'] ?? 'Collab Playlist',
              coverImage: p['cover_image'],
              isCollaborative: true,
              isPublic: p['is_public'] != false,
              songs: finalSongs,
              createdAt:
                  DateTime.tryParse(p['created_at'] ?? '') ?? DateTime.now(),
            );
          }
        }
      } catch (err) {
        debugPrint(
            '[PlaylistService] Load collaborator playlists warning: $err');
      }

      _playlists = playlistMap.values.toList();
      _collabPlaylists = _playlists.where((p) => p.isCollaborative).toList();
      _loaded = true;
      await _saveToDisk();
      notifyListeners();
    } catch (e) {
      debugPrint('[PlaylistService] Load playlists error: $e');
      if (_playlists.isEmpty) await _loadFromDisk(_userId);
    }
  }

  Future<void> reloadPlaylists() async {
    _loaded = false;
    await loadPlaylists(forceRefresh: true);
  }

  void clearCache() {
    _playlists = [];
    _collabPlaylists = [];
    _handledInviteIds.clear();
    _acceptedInviteIds.clear();
    _seenInviteIds.clear();
    _pendingInvitesCount = 0;
    _unseenPendingInvitesCount = 0;
    _loaded = false;
    _collabInvitesChannel?.unsubscribe();
    _collabInvitesChannel = null;
    _playlistsRealtimeChannel?.unsubscribe();
    _playlistsRealtimeChannel = null;
  }

  Future<UserPlaylist> createPlaylist(String name,
      {String? coverImage,
      bool isCollaborative = false,
      bool isPublic = true}) async {
    String? storedCover;
    if (coverImage != null &&
        !_isUrl(coverImage) &&
        !coverImage.startsWith('data:image/')) {
      try {
        storedCover =
            await _uploadCover(coverImage).timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('[PlaylistService] createPlaylist cover upload warning: $e');
      }
    } else {
      storedCover = coverImage;
    }

    String playlistId = DateTime.now().millisecondsSinceEpoch.toString();
    DateTime createdAt = DateTime.now();

    if (_userId.isNotEmpty) {
      try {
        final data = await _client
            .from('user_playlists')
            .insert({
              'user_id': _userId,
              'name': name,
              'cover_image': storedCover,
              'is_collaborative': isCollaborative,
              'is_public': isPublic,
            })
            .select()
            .single();

        playlistId = data['id']?.toString() ?? playlistId;
        createdAt = DateTime.tryParse(data['created_at']?.toString() ?? '') ??
            createdAt;
        debugPrint(
            '[PlaylistService] Created playlist in Supabase: $playlistId ($name)');
      } catch (e) {
        debugPrint('[PlaylistService] Create playlist Supabase ERROR: $e');
      }
    }

    final playlist = UserPlaylist(
      id: playlistId,
      userId: _userId,
      name: name,
      coverImage: storedCover,
      isCollaborative: isCollaborative,
      isPublic: isPublic,
      songs: [],
      createdAt: createdAt,
    );

    final existingIdx = _playlists.indexWhere((p) => p.id == playlistId);
    if (existingIdx >= 0) {
      _playlists[existingIdx] = playlist;
    } else {
      _playlists.insert(0, playlist);
    }
    _deduplicate();

    await _saveToDisk();
    onUpdate.value++;
    notifyListeners();
    return playlist;
  }

  Future<void> togglePublic(String playlistId, bool isPublic) async {
    try {
      await _client
          .from('user_playlists')
          .update({'is_public': isPublic})
          .eq('id', playlistId)
          .eq('user_id', _userId);

      final idx = _playlists.indexWhere((p) => p.id == playlistId);
      if (idx >= 0) {
        _playlists[idx].isPublic = isPublic;
        await _saveToDisk();
        onUpdate.value++;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[PlaylistService] togglePublic error: $e');
    }
  }

  Future<bool> inviteCollaborator(
      String playlistId, String targetUserId) async {
    try {
      debugPrint(
          '[PlaylistService] Inviting $targetUserId to playlist $playlistId...');
      await _client.from('playlist_collaborators').upsert({
        'playlist_id': playlistId,
        'user_id': targetUserId,
        'role': 'pending',
      });
      debugPrint(
          '[PlaylistService] Successfully inserted into playlist_collaborators with pending status');

      // Instant broadcast notification to target user
      try {
        final p = getPlaylist(playlistId);
        final profile = ProfileService();
        final myName = profile.displayName.isNotEmpty
            ? profile.displayName
            : (_client.auth.currentUser?.userMetadata?['display_name'] ??
                'A friend');
        final alertChannel =
            _client.channel('playlist_collabs_realtime:$targetUserId');
        await alertChannel.sendBroadcastMessage(
          event: 'collab_invite',
          payload: {
            'target_user_id': targetUserId,
            'sender_id': _userId,
            'sender_name': myName,
            'playlist_id': playlistId,
            'playlist_name': p?.name ?? 'a playlist',
          },
        );
      } catch (e) {
        debugPrint('[PlaylistService] Broadcast collab invite error: $e');
      }
    } catch (e) {
      debugPrint('[PlaylistService] Supabase invite ERROR: $e');
    }

    try {
      await toggleCollaborative(playlistId, true);
    } catch (_) {}

    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx >= 0) {
      _playlists[idx].isCollaborative = true;
      _collabPlaylists = _playlists.where((p) => p.isCollaborative).toList();
      await _saveToDisk();
      onUpdate.value++;
      notifyListeners();
    }
    return true;
  }

  Future<void> removeCollaborator(
      String playlistId, String targetUserId) async {
    try {
      await _client
          .from('playlist_collaborators')
          .delete()
          .eq('playlist_id', playlistId)
          .eq('user_id', targetUserId);
    } catch (e) {
      debugPrint('[PlaylistService] Remove collaborator error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchCollaborators(
      String playlistId) async {
    try {
      final rows = await _client
          .from('playlist_collaborators')
          .select('user_id, role, joined_at')
          .eq('playlist_id', playlistId);

      final list = List<Map<String, dynamic>>.from(rows);
      if (list.isEmpty) return [];

      final userIds = list.map((r) => r['user_id'].toString()).toSet().toList();
      final profiles = await _client
          .from('profiles')
          .select('id, display_name, username, avatar_url')
          .inFilter('id', userIds);

      final profileMap = {
        for (final p in profiles) p['id'].toString(): p,
      };

      return list.map((r) {
        final uid = r['user_id'].toString();
        final p = profileMap[uid];
        return {
          'user_id': uid,
          'role': r['role'] ?? 'editor',
          'joined_at': r['joined_at'],
          'profiles': p ??
              {
                'display_name': 'Friend',
                'username': '',
                'avatar_url': null,
              },
        };
      }).toList();
    } catch (e) {
      debugPrint('[PlaylistService] Fetch collaborators error: $e');
      return [];
    }
  }

  Future<void> toggleCollaborative(String playlistId, bool enable) async {
    try {
      await _client
          .from('user_playlists')
          .update({'is_collaborative': enable})
          .eq('id', playlistId)
          .eq('user_id', _userId);

      final idx = _playlists.indexWhere((p) => p.id == playlistId);
      if (idx >= 0) {
        _playlists[idx].isCollaborative = enable;
        _collabPlaylists = _playlists.where((p) => p.isCollaborative).toList();
        await _saveToDisk();
        onUpdate.value++;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[PlaylistService] Toggle collaborative error: $e');
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    // 1. Remove from in-memory state immediately
    _playlists.removeWhere((p) => p.id == playlistId);
    _collabPlaylists.removeWhere((p) => p.id == playlistId);

    // 2. Persist updated cache to disk
    await _saveToDisk();
    onUpdate.value++;
    notifyListeners();

    // 3. Remove from Supabase in background
    try {
      await _client.from('user_playlists').delete().eq('id', playlistId);
      await _client
          .from('playlist_collaborators')
          .delete()
          .eq('playlist_id', playlistId);
    } catch (e) {
      debugPrint('[PlaylistService] Supabase delete warning: $e');
    }
  }

  Future<void> renamePlaylist(String playlistId, String newName) async {
    try {
      await _client
          .from('user_playlists')
          .update({'name': newName}).eq('id', playlistId);
    } catch (e) {
      debugPrint('[PlaylistService] renamePlaylist Supabase error: $e');
    }
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx >= 0) {
      _playlists[idx].name = newName;
      _collabPlaylists = _playlists.where((p) => p.isCollaborative).toList();
      await _saveToDisk();
      onUpdate.value++;
      notifyListeners();
    }
  }

  Future<void> updateCoverImage(String playlistId, String? coverImage) async {
    String? storedCover;
    if (coverImage != null &&
        !_isUrl(coverImage) &&
        !coverImage.startsWith('data:image/')) {
      try {
        storedCover =
            await _uploadCover(coverImage).timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('[PlaylistService] updateCoverImage upload error: $e');
      }
    } else {
      storedCover = coverImage;
    }

    if (storedCover != null) {
      try {
        await _client
            .from('user_playlists')
            .update({'cover_image': storedCover}).eq('id', playlistId);
      } catch (e) {
        debugPrint('[PlaylistService] updateCoverImage Supabase error: $e');
      }
      final idx = _playlists.indexWhere((p) => p.id == playlistId);
      if (idx >= 0) {
        _playlists[idx].coverImage = storedCover;
        _collabPlaylists = _playlists.where((p) => p.isCollaborative).toList();
        await _saveToDisk();
        onUpdate.value++;
        notifyListeners();
      }
    }
  }

  Future<void> refreshPlaylistMeta(String playlistId) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) {
      await fetchPlaylistById(playlistId);
      return;
    }

    try {
      final row = await _client
          .from('user_playlists')
          .select('name, cover_image, is_collaborative')
          .eq('id', playlistId)
          .maybeSingle();
      if (row == null) return;

      if (idx < _playlists.length && _playlists[idx].id == playlistId) {
        _playlists[idx].name = row['name'] ?? _playlists[idx].name;
        _playlists[idx].coverImage =
            row['cover_image'] ?? _playlists[idx].coverImage;
        _playlists[idx].isCollaborative =
            row['is_collaborative'] ?? _playlists[idx].isCollaborative;
        _collabPlaylists = _playlists.where((p) => p.isCollaborative).toList();
        await _saveToDisk();
        onUpdate.value++;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[PlaylistService] Refresh playlist meta error: $e');
    }
  }

  Future<List<PlaylistSong>> refreshPlaylistSongs(String playlistId) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) {
      final fetched = await fetchPlaylistById(playlistId);
      return fetched?.songs ?? [];
    }

    if (isRecentlyReordered(playlistId) && _playlists[idx].songs.isNotEmpty) {
      debugPrint(
          '[PlaylistService] Skipping refreshPlaylistSongs overwrite due to recent local reorder');
      return _playlists[idx].songs;
    }

    try {
      final songsData = await _client
          .from('playlist_songs')
          .select()
          .eq('playlist_id', playlistId)
          .order('position', ascending: true);

      final updatedSongs =
          (songsData as List).map((s) => PlaylistSong.fromMap(s)).toList();

      if (idx < _playlists.length && _playlists[idx].id == playlistId) {
        _playlists[idx].songs = updatedSongs;
        _collabPlaylists = _playlists.where((p) => p.isCollaborative).toList();
        await _saveToDisk();
        onUpdate.value++;
        notifyListeners();
      }
      return updatedSongs;
    } catch (e) {
      debugPrint('[PlaylistService] Refresh playlist songs error: $e');
      return idx < _playlists.length ? _playlists[idx].songs : [];
    }
  }

  String _getCurrentUserName() {
    final profile = ProfileService();
    String name = profile.displayName.trim();
    if (name.isEmpty) name = profile.username.trim();

    final user = _client.auth.currentUser;
    if (name.isEmpty && user != null) {
      name = (user.userMetadata?['display_name'] ??
              user.userMetadata?['full_name'] ??
              user.userMetadata?['name'] ??
              user.userMetadata?['username'] ??
              user.userMetadata?['user_name'] ??
              '')
          .toString()
          .trim();
    }
    if (name.isEmpty && user?.email != null && user!.email!.isNotEmpty) {
      name = user.email!.split('@').first;
    }
    return name;
  }

  String _getCurrentUserAvatar() {
    final profile = ProfileService();
    String avatar = profile.avatarUrl.trim();
    final user = _client.auth.currentUser;
    if (avatar.isEmpty && user != null) {
      avatar = (user.userMetadata?['avatar_url'] ??
              user.userMetadata?['picture'] ??
              '')
          .toString()
          .trim();
    }
    return avatar;
  }

  Future<void> addSong(String playlistId, PlaylistSong song) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final playlist = _playlists[idx];
    if (playlist.songs.any((s) => s.trackId == song.trackId)) return;

    final addedByName = _getCurrentUserName();
    final addedByAvatar = _getCurrentUserAvatar();

    final position = playlist.songs.length;

    final newSong = PlaylistSong(
      trackId: song.trackId,
      title: song.title,
      artist: song.artist,
      image: song.image,
      duration: song.duration,
      artistId: song.artistId,
      artistImage: song.artistImage,
      addedById: _userId,
      addedByName: addedByName,
      addedByAvatar: addedByAvatar,
    );

    // 1. Optimistic local update
    playlist.songs.add(newSong);
    await _saveToDisk();
    onUpdate.value++;
    notifyListeners();

    // 2. Persist to Supabase
    try {
      await _client.from('playlist_songs').insert({
        'playlist_id': playlistId,
        'user_id': _userId,
        'track_id': song.trackId,
        'title': song.title,
        'artist': song.artist,
        'image': song.image,
        'duration': song.duration,
        'artist_id': song.artistId,
        'artist_image': song.artistImage,
        'added_by_id': _userId,
        'added_by_name': addedByName,
        'added_by_avatar': addedByAvatar,
        'position': position,
      });
    } catch (e) {
      debugPrint('[PlaylistService] Supabase addSong warning: $e');
    }
  }

  Future<void> addSongs(String playlistId, List<PlaylistSong> songs) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final playlist = _playlists[idx];
    final existingIds = playlist.songs.map((s) => s.trackId).toSet();
    final toAdd = songs.where((s) => !existingIds.contains(s.trackId)).toList();
    if (toAdd.isEmpty) return;

    final addedByName = _getCurrentUserName();
    final addedByAvatar = _getCurrentUserAvatar();

    int position = playlist.songs.length;
    final List<PlaylistSong> newSongs = [];
    final List<Map<String, dynamic>> rows = [];

    for (final song in toAdd) {
      newSongs.add(PlaylistSong(
        trackId: song.trackId,
        title: song.title,
        artist: song.artist,
        image: song.image,
        duration: song.duration,
        artistId: song.artistId,
        artistImage: song.artistImage,
        addedById: _userId,
        addedByName: addedByName,
        addedByAvatar: addedByAvatar,
      ));

      rows.add({
        'playlist_id': playlistId,
        'user_id': _userId,
        'track_id': song.trackId,
        'title': song.title,
        'artist': song.artist,
        'image': song.image,
        'duration': song.duration,
        'artist_id': song.artistId,
        'artist_image': song.artistImage,
        'added_by_id': _userId,
        'added_by_name': addedByName,
        'added_by_avatar': addedByAvatar,
        'position': position++,
      });
    }

    // 1. Optimistic local update
    playlist.songs.addAll(newSongs);
    await _saveToDisk();
    onUpdate.value++;
    notifyListeners();

    // 2. Persist to Supabase
    try {
      await _client.from('playlist_songs').insert(rows);
    } catch (e) {
      debugPrint('[PlaylistService] Supabase addSongs warning: $e');
    }
  }

  Future<void> removeSong(String playlistId, String trackId) async {
    // 1. Optimistic local removal
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx >= 0) {
      _playlists[idx].songs.removeWhere((s) => s.trackId == trackId);
      await _saveToDisk();
      onUpdate.value++;
      notifyListeners();
    }

    // 2. Persist to Supabase
    try {
      await _client
          .from('playlist_songs')
          .delete()
          .eq('playlist_id', playlistId)
          .eq('track_id', trackId);
    } catch (e) {
      debugPrint('[PlaylistService] Supabase removeSong warning: $e');
    }
  }

  final Map<String, DateTime> _lastReorderTimes = {};

  bool isRecentlyReordered(String playlistId) {
    final lastTime = _lastReorderTimes[playlistId];
    if (lastTime == null) return false;
    return DateTime.now().difference(lastTime) < const Duration(seconds: 4);
  }

  Future<void> reorderSongs(
      String playlistId, int oldIndex, int newIndex) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final playlist = _playlists[idx];
    if (oldIndex < 0 || oldIndex >= playlist.songs.length) return;
    if (newIndex < 0 || newIndex >= playlist.songs.length) return;

    final movedSong = playlist.songs.removeAt(oldIndex);
    playlist.songs.insert(newIndex, movedSong);

    _lastReorderTimes[playlistId] = DateTime.now();

    // 1. Save to disk immediately for instant persistent reorder
    await _saveToDisk();
    onUpdate.value++;
    notifyListeners();

    // 2. Persist new positions to Supabase in background
    try {
      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < playlist.songs.length; i++) {
        final s = playlist.songs[i];
        rows.add({
          'playlist_id': playlistId,
          'user_id': s.addedById.isNotEmpty ? s.addedById : _userId,
          'track_id': s.trackId,
          'title': s.title,
          'artist': s.artist,
          'image': s.image,
          'duration': s.duration,
          'position': i,
          'artist_id': s.artistId,
          'artist_image': s.artistImage,
          'added_by_id': s.addedById.isNotEmpty ? s.addedById : _userId,
          'added_by_name': s.addedByName,
          'added_by_avatar': s.addedByAvatar,
        });
      }
      // Attempt batch upsert with composite conflict key for atomic multi-row position update
      await _client.from('playlist_songs').upsert(
            rows,
            onConflict: 'playlist_id,track_id',
          );
    } catch (e) {
      debugPrint(
          '[PlaylistService] Reorder batch upsert warning: $e, falling back to individual updates');
      try {
        final updates = <Future>[];
        for (var i = 0; i < playlist.songs.length; i++) {
          final song = playlist.songs[i];
          updates.add(
            _client
                .from('playlist_songs')
                .update({'position': i})
                .eq('playlist_id', playlistId)
                .eq('track_id', song.trackId),
          );
        }
        await Future.wait(updates);
      } catch (err) {
        debugPrint(
            '[PlaylistService] Reorder Supabase sync fallback warning: $err');
      }
    }
  }

  bool hasSong(String playlistId, String trackId) {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    return playlist.songs.any((s) => s.trackId == trackId);
  }

  static bool _isUrl(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  static ImageProvider? coverImageProvider(String? coverImage) {
    if (coverImage == null || coverImage.isEmpty) return null;
    if (coverImage.startsWith('data:image/')) {
      try {
        final commaIdx = coverImage.indexOf(',');
        final base64String =
            commaIdx >= 0 ? coverImage.substring(commaIdx + 1) : coverImage;
        return MemoryImage(base64Decode(base64String));
      } catch (e) {
        debugPrint(
            '[PlaylistService] coverImageProvider base64 decode error: $e');
      }
    }
    if (_isUrl(coverImage)) {
      return NetworkImage(coverImage);
    }
    final file = File(coverImage);
    if (file.existsSync()) {
      return FileImage(file);
    }
    return null;
  }

  Future<String?> _uploadCover(String localPath) async {
    try {
      final file = File(localPath);
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      final ext = localPath.split('.').last.toLowerCase();
      final contentType = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };
      final playlistId = DateTime.now().microsecondsSinceEpoch.toString();
      final path = 'covers/${_userId}_$playlistId.$ext';

      try {
        await Supabase.instance.client.storage.from('avatars').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(upsert: true, contentType: contentType),
            );
        return Supabase.instance.client.storage
            .from('avatars')
            .getPublicUrl(path);
      } catch (storageError) {
        debugPrint(
            '[PlaylistService] Storage upload failed ($storageError), falling back to data URI');
        final base64Data = base64Encode(bytes);
        return 'data:$contentType;base64,$base64Data';
      }
    } catch (e) {
      debugPrint('[PlaylistService] Cover upload error: $e');
      return null;
    }
  }

  UserPlaylist? getPlaylist(String playlistId) {
    try {
      return _playlists.firstWhere((p) => p.id == playlistId);
    } catch (_) {
      return null;
    }
  }
}
