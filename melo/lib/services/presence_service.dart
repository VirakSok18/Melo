import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'playback_service.dart';
import 'profile_service.dart';
import 'search_service.dart';
import 'youtube_service.dart';
import 'cookie_service.dart';
import 'notification_service.dart';

class FriendPresence {
  final String userId;
  final String displayName;
  final String username;
  final String avatarUrl;
  final String songTitle;
  final String songArtist;
  final String songImage;
  final String trackId;
  final bool isPlaying;
  final int positionMs;
  final String listeningWithUserId;
  final DateTime updatedAt;
  final bool isOffline;
  final DateTime lastSeenLocal;

  FriendPresence({
    required this.userId,
    required this.displayName,
    required this.username,
    required this.avatarUrl,
    required this.songTitle,
    required this.songArtist,
    required this.songImage,
    required this.trackId,
    required this.isPlaying,
    required this.positionMs,
    this.listeningWithUserId = '',
    required this.updatedAt,
    this.isOffline = false,
    DateTime? lastSeenLocal,
  }) : lastSeenLocal = lastSeenLocal ?? DateTime.now();

  factory FriendPresence.fromMap(Map<String, dynamic> map,
      {DateTime? lastSeenLocal}) {
    final rawIsOnline = map['is_online'];
    final rawIsOffline = map['is_offline'];
    final isOfflineVal = (rawIsOffline == true) || (rawIsOnline == false);

    return FriendPresence(
      userId: map['user_id']?.toString() ?? '',
      displayName: map['display_name']?.toString() ?? '',
      username: map['username']?.toString() ?? '',
      avatarUrl: map['avatar_url']?.toString() ?? '',
      songTitle: map['song_title']?.toString() ?? '',
      songArtist: map['song_artist']?.toString() ?? '',
      songImage: map['song_image']?.toString() ?? '',
      trackId: map['track_id']?.toString() ?? '',
      isPlaying: map['is_playing'] == true,
      positionMs: (map['position_ms'] as num?)?.toInt() ?? 0,
      listeningWithUserId: map['listening_with_user_id']?.toString() ?? '',
      updatedAt:
          DateTime.tryParse(map['updated_at']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
      isOffline: isOfflineVal,
      lastSeenLocal: lastSeenLocal ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'display_name': displayName,
      'username': username,
      'avatar_url': avatarUrl,
      'song_title': songTitle,
      'song_artist': songArtist,
      'song_image': songImage,
      'track_id': trackId,
      'is_playing': isPlaying,
      'position_ms': positionMs,
      'listening_with_user_id': listeningWithUserId,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'is_offline': isOffline,
      'is_online': !isOffline,
    };
  }
}

class PresenceListener {
  final String userId;
  final String displayName;
  final String username;
  final String avatarUrl;
  final DateTime joinedAt;
  DateTime lastSeenAt;
  final bool isStillListening;

  PresenceListener({
    required this.userId,
    required this.displayName,
    required this.username,
    required this.avatarUrl,
    required this.joinedAt,
    required this.lastSeenAt,
    required this.isStillListening,
  });

  PresenceListener copyWith({
    String? displayName,
    String? username,
    String? avatarUrl,
    DateTime? lastSeenAt,
    bool? isStillListening,
  }) {
    return PresenceListener(
      userId: userId,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      joinedAt: joinedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      isStillListening: isStillListening ?? this.isStillListening,
    );
  }
}

class PresenceService extends ChangeNotifier {
  static final PresenceService _instance = PresenceService._internal();
  factory PresenceService() => _instance;

  PresenceService._internal() {
    try {
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (data.session != null && !_isInitialized) {
          init();
        }
      });
    } catch (_) {}
  }

  RealtimeChannel? _channel;
  final Map<String, FriendPresence> _liveFriends = {};
  Timer? _heartbeatTimer;
  Timer? _pruneOfflineTimer;
  Timer? _reconnectTimer;
  DateTime? _lastPingTime;
  String? _listeningWithUserId;
  bool _isInitialized = false;
  bool _isChannelSubscribed = false;
  bool _isAppInForeground = true;

  // Live Host position tracking for millisecond Listen Together sync
  int? _lastHostPosMs;
  DateTime? _lastHostSyncTime;
  bool _isHostPlaying = false;
  int _idleBroadcastCounter = 0;

  /// Returns the estimated live millisecond position of the current host
  Duration? getExactCurrentHostPosition() {
    if (_listeningWithUserId == null || _listeningWithUserId!.isEmpty) {
      return null;
    }
    if (_lastHostPosMs == null || _lastHostSyncTime == null) {
      return null;
    }
    final elapsedMs = _isHostPlaying
        ? DateTime.now().difference(_lastHostSyncTime!).inMilliseconds
        : 0;
    final exactMs = (_lastHostPosMs! + elapsedMs).clamp(0, 3600000);
    return Duration(milliseconds: exactMs);
  }

  // Dedicated tracking for users listening along with you (or in the current session)
  final Map<String, PresenceListener> _sessionListeners = {};

  Map<String, FriendPresence> get liveFriends => Map.unmodifiable(_liveFriends);

  FriendPresence? getPresence(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    final norm = userId.trim().toLowerCase();
    final p = _liveFriends[norm] ?? _liveFriends[userId];
    if (p != null && !p.isOffline) return p;
    return null;
  }

  bool isUserOnline(String? userId) {
    final p = getPresence(userId);
    return p != null && !p.isOffline;
  }

  bool isFriendListeningToMe(String? friendUserId) {
    if (friendUserId == null || friendUserId.isEmpty) return false;
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null || myId.isEmpty) return false;
    final normMyId = myId.trim().toLowerCase();
    final normFriendId = friendUserId.trim().toLowerCase();

    // 1. Direct presence broadcast check
    final p = getPresence(friendUserId);
    if (p != null &&
        p.listeningWithUserId.trim().toLowerCase() == normMyId) {
      return true;
    }

    // 2. Active session listener list check
    for (final entry in _sessionListeners.entries) {
      if (entry.key.trim().toLowerCase() == normFriendId &&
          entry.value.isStillListening) {
        return true;
      }
    }

    return false;
  }

  List<FriendPresence> get activeList {
    final seen = <String>{};
    final list = <FriendPresence>[];
    for (final p in _liveFriends.values) {
      if (!p.isOffline && p.isPlaying && p.songTitle.isNotEmpty) {
        final norm = p.userId.trim().toLowerCase();
        if (seen.add(norm)) {
          list.add(p);
        }
      }
    }
    return list;
  }

  String? get listeningWithUserId => _listeningWithUserId;

  List<PresenceListener> get currentListeners =>
      _sessionListeners.values.where((l) => l.isStillListening).toList();

  List<PresenceListener> get pastListeners =>
      _sessionListeners.values.where((l) => !l.isStillListening).toList();

  int get currentListenersCount => currentListeners.length;

  void clearSessionListeners() {
    _sessionListeners.clear();
    notifyListeners();
  }

  void onAppForeground() {
    _isAppInForeground = true;
    debugPrint('[Presence] App foregrounded -> broadcasting online');
    broadcastNow();
    pingFriends();
  }

  void onAppBackground() {
    _isAppInForeground = false;
    final isPlaying = PlaybackService().isPlaying;
    if (isPlaying) {
      debugPrint('[Presence] App backgrounded with music playing -> keeping online');
      broadcastNow();
    } else {
      debugPrint('[Presence] App backgrounded without music -> broadcasting offline');
      broadcastOffline();
    }
  }

  void startListeningWith(
    String friendUserId, {
    String? friendDisplayName,
    int? initialPositionMs,
    bool isHostPlaying = true,
  }) {
    _listeningWithUserId = friendUserId;
    if (initialPositionMs != null) {
      _lastHostPosMs = initialPositionMs;
      _lastHostSyncTime = DateTime.now();
      _isHostPlaying = isHostPlaying;
    } else {
      final p = getPresence(friendUserId);
      if (p != null) {
        final elapsed = DateTime.now()
            .difference(p.updatedAt)
            .inMilliseconds
            .clamp(0, 3000);
        _lastHostPosMs = p.positionMs + (p.isPlaying ? elapsed : 0);
        _lastHostSyncTime = DateTime.now();
        _isHostPlaying = p.isPlaying;
      }
    }
    notifyListeners();

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final profile = ProfileService();
    final myName = profile.displayName.isNotEmpty
        ? profile.displayName
        : (user.userMetadata?['display_name'] ?? 'A friend');
    final myUsername = profile.username.isNotEmpty
        ? profile.username
        : (user.userMetadata?['username'] ?? '');
    final myAvatar = profile.avatarUrl.isNotEmpty
        ? profile.avatarUrl
        : (user.userMetadata?['avatar_url'] ?? '');

    try {
      _channel?.sendBroadcastMessage(
        event: 'listen_along_event',
        payload: {
          'target_user_id': friendUserId,
          'listener_id': user.id,
          'listener_name': myName,
          'listener_username': myUsername,
          'listener_avatar': myAvatar,
          'action': 'joined',
        },
      );
    } catch (e) {
      debugPrint('[Presence] Send join broadcast error: $e');
    }

    broadcastNow();

    if (friendDisplayName != null && friendDisplayName.isNotEmpty) {
      CookieService.show(
        message: 'Listening along with $friendDisplayName',
        icon: Icons.headphones_rounded,
        iconColor: const Color(0xFF514AED),
      );
    }
  }

  void stopListeningWith({bool showToast = false}) {
    final friendId = _listeningWithUserId;
    _listeningWithUserId = null;
    _lastHostPosMs = null;
    _lastHostSyncTime = null;
    _isHostPlaying = false;
    if (PlaybackService().audioPlayer.speed != 1.0) {
      PlaybackService().audioPlayer.setSpeed(1.0);
    }
    notifyListeners();

    if (friendId == null) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final profile = ProfileService();
      final myName = profile.displayName.isNotEmpty
          ? profile.displayName
          : (user.userMetadata?['display_name'] ?? 'A friend');
      final myUsername = profile.username.isNotEmpty
          ? profile.username
          : (user.userMetadata?['username'] ?? '');
      final myAvatar = profile.avatarUrl.isNotEmpty
          ? profile.avatarUrl
          : (user.userMetadata?['avatar_url'] ?? '');

      try {
        _channel?.sendBroadcastMessage(
          event: 'listen_along_event',
          payload: {
            'target_user_id': friendId,
            'listener_id': user.id,
            'listener_name': myName,
            'listener_username': myUsername,
            'listener_avatar': myAvatar,
            'action': 'left',
          },
        );
      } catch (e) {
        debugPrint('[Presence] Send leave broadcast error: $e');
      }
    }

    broadcastNow();

    if (showToast) {
      CookieService.show(
        message: 'Left listening session',
        icon: Icons.exit_to_app_rounded,
        iconColor: Colors.white70,
      );
    }
  }

  void handleManualPlaybackAction() {
    if (_listeningWithUserId != null && _listeningWithUserId!.isNotEmpty) {
      debugPrint(
          '[Presence] Manual playback action detected -> leaving Listen Along session');
      stopListeningWith(showToast: true);
    }
  }

  void init() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    if (_isInitialized && _channel != null) {
      pingFriends();
      broadcastNow();
      return;
    }

    _isInitialized = true;
    PlaybackService().removeListener(_onLocalPlaybackChanged);
    PlaybackService().addListener(_onLocalPlaybackChanged);
    PlaybackService().onManualPlaybackAction = handleManualPlaybackAction;
    PlaybackService().onGetSyncTargetPosition = getExactCurrentHostPosition;
    _connectPresenceChannel();
    _startPruningTimer();
  }

  void refreshPresence() {
    pingFriends();
    broadcastNow();
  }

  void _startPruningTimer() {
    _pruneOfflineTimer?.cancel();
    _pruneOfflineTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final now = DateTime.now();
      bool changed = false;
      final keysToRemove = <String>[];

      for (final entry in _liveFriends.entries) {
        final p = entry.value;
        // Playing music: allow up to 60s to avoid background drops
        // Idle online: allow up to 15s
        final thresholdSec = (p.isPlaying && p.songTitle.isNotEmpty) ? 60 : 15;
        if (now.difference(p.lastSeenLocal).inSeconds > thresholdSec) {
          keysToRemove.add(entry.key);
          changed = true;
        }
      }

      for (final k in keysToRemove) {
        _liveFriends.remove(k);
      }

      // Check session listeners
      for (final entry in _sessionListeners.entries) {
        if (entry.value.isStillListening) {
          if (now.difference(entry.value.lastSeenAt).inSeconds > 15) {
            _sessionListeners[entry.key] = entry.value.copyWith(
              isStillListening: false,
              lastSeenAt: now,
            );
            changed = true;
          }
        }
      }

      if (changed) {
        notifyListeners();
      }
    });
  }

  void _handleFriendUpdate(FriendPresence friend, String listeningWith) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || friend.userId.isEmpty || friend.userId == user.id) {
      return;
    }

    final normId = friend.userId.trim().toLowerCase();
    if (friend.isOffline) {
      _liveFriends.remove(normId);
      _liveFriends.remove(friend.userId);
      if (_sessionListeners.containsKey(friend.userId)) {
        final curr = _sessionListeners[friend.userId]!;
        if (curr.isStillListening) {
          _sessionListeners[friend.userId] = curr.copyWith(
            isStillListening: false,
            lastSeenAt: DateTime.now(),
          );
        }
      }
      notifyListeners();
      return;
    }

    // Update live state immediately
    _liveFriends[normId] = friend;
    _liveFriends[friend.userId] = friend;

    // Check if this friend is listening along with ME or with current session host
    final currentUserId = user.id.trim().toLowerCase();
    final normListeningWith = listeningWith.trim().toLowerCase();
    final isListeningToMe =
        normListeningWith.isNotEmpty && normListeningWith == currentUserId;
    final isListeningToHost = _listeningWithUserId != null &&
        _listeningWithUserId!.isNotEmpty &&
        normListeningWith == _listeningWithUserId!.trim().toLowerCase();

    if (isListeningToMe || isListeningToHost) {
      final existing = _sessionListeners[friend.userId];
      if (existing == null) {
        _sessionListeners[friend.userId] = PresenceListener(
          userId: friend.userId,
          displayName: friend.displayName.isNotEmpty
              ? friend.displayName
              : friend.username,
          username: friend.username,
          avatarUrl: friend.avatarUrl,
          joinedAt: DateTime.now(),
          lastSeenAt: DateTime.now(),
          isStillListening: true,
        );
      } else {
        _sessionListeners[friend.userId] = existing.copyWith(
          displayName: friend.displayName.isNotEmpty
              ? friend.displayName
              : existing.displayName,
          username: friend.username.isNotEmpty
              ? friend.username
              : existing.username,
          avatarUrl: friend.avatarUrl.isNotEmpty
              ? friend.avatarUrl
              : existing.avatarUrl,
          lastSeenAt: DateTime.now(),
          isStillListening: true,
        );
      }
    } else if (normListeningWith.isNotEmpty &&
        _sessionListeners.containsKey(friend.userId)) {
      final curr = _sessionListeners[friend.userId]!;
      if (curr.isStillListening) {
        _sessionListeners[friend.userId] = curr.copyWith(
          isStillListening: false,
          lastSeenAt: DateTime.now(),
        );
      }
    }

    if (friend.isPlaying && friend.songTitle.isNotEmpty) {
      // PREFETCH AUDIO STREAM IN BACKGROUND FOR INSTANT START
      YouTubeService.resolveStreamUrl(
        friend.songTitle,
        friend.songArtist,
      );
    }

    notifyListeners();

    // AUTO-SYNC / FOLLOW SESSION:
    if (_listeningWithUserId == friend.userId && friend.songTitle.isNotEmpty) {
      final playback = PlaybackService();
      final current = playback.currentTrack;

      final isSameTrack = current != null &&
          ((current.id.isNotEmpty &&
                  friend.trackId.isNotEmpty &&
                  current.id == friend.trackId) ||
              (current.title.toLowerCase().trim() ==
                      friend.songTitle.toLowerCase().trim() &&
                  (current.artist.isEmpty ||
                      friend.songArtist.isEmpty ||
                      current.artist.toLowerCase().trim() ==
                          friend.songArtist.toLowerCase().trim())));

      final elapsedSinceBroadcast = DateTime.now().difference(
        friend.updatedAt,
      );
      final transitMs = elapsedSinceBroadcast.inMilliseconds.clamp(0, 3000);
      final exactPositionMs =
          friend.positionMs + (friend.isPlaying ? transitMs : 0);

      _lastHostPosMs = exactPositionMs;
      _lastHostSyncTime = DateTime.now();
      _isHostPlaying = friend.isPlaying;

      final targetPosition = Duration(
        milliseconds: exactPositionMs.clamp(0, 3600000),
      );

      final hasSource = playback.audioPlayer.audioSource != null;
      if (!isSameTrack || !hasSource) {
        debugPrint(
          '[ListenTogether] Auto-following track change to: ${friend.songTitle} by ${friend.songArtist} (targetPos=${targetPosition.inSeconds}s)',
        );
        final newTrack = SearchResult(
          id: friend.trackId,
          title: friend.songTitle,
          artist: friend.songArtist,
          image: friend.songImage,
          type: 'song',
          duration: '',
          nbFan: 0,
          previewUrl: '',
        );
        playback.playTrack(
          newTrack,
          initialPosition: targetPosition,
          fromSync: true,
        );
      } else {
        if (playback.isLoading) {
          return;
        }

        // 1. Play / Pause state alignment
        if (friend.isPlaying && !playback.isPlaying) {
          playback.play(fromSync: true);
        } else if (!friend.isPlaying && playback.isPlaying) {
          playback.pause(fromSync: true);
        }

        // 2. High-precision laser alignment
        final myPosMs = playback.position.inMilliseconds;
        final drift = exactPositionMs - myPosMs;
        final absDrift = drift.abs();

        if (absDrift < 120) {
          // Perfectly locked within 120ms - maintain standard speed
          if (playback.audioPlayer.speed != 1.0) {
            playback.audioPlayer.setSpeed(1.0);
          }
        } else if (absDrift <= 600 && friend.isPlaying && playback.isPlaying) {
          // Seamless tempo glide (speeds up/slows down 6% to lock in without audible pops or seek clicks)
          if (drift > 0) {
            playback.audioPlayer.setSpeed(1.06);
          } else {
            playback.audioPlayer.setSpeed(0.94);
          }
        } else {
          // Large drift (> 600ms): Snap seek to live position
          if (playback.audioPlayer.speed != 1.0) {
            playback.audioPlayer.setSpeed(1.0);
          }
          playback.seek(targetPosition, fromSync: true).then((_) {
            if (friend.isPlaying && !playback.isPlaying) {
              playback.play(fromSync: true);
            } else if (!friend.isPlaying && playback.isPlaying) {
              playback.pause(fromSync: true);
            }
          });
        }
      }
    }
  }

  void _connectPresenceChannel() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _channel != null) return;

    _channel = Supabase.instance.client.channel('melo_presence_channel');


    // 2. Realtime Broadcast event for instant sub-second playback state sync
    _channel?.onBroadcast(
      event: 'playback_state',
      callback: (payload) {
        final data = Map<String, dynamic>.from(payload);
        final friend =
            FriendPresence.fromMap(data, lastSeenLocal: DateTime.now());
        final listeningWith = data['listening_with_user_id']?.toString() ?? '';
        _handleFriendUpdate(friend, listeningWith);
      },
    );

    // 3. Ping requests
    _channel?.onBroadcast(
      event: 'ping_presence',
      callback: (payload) {
        final senderId = payload['sender_id']?.toString() ?? '';
        final myId = Supabase.instance.client.auth.currentUser?.id;
        if (senderId.isNotEmpty && senderId == myId) return;
        broadcastNow();
      },
    );

    // 4. Listen for join/leave notifications in real-time
    _channel?.onBroadcast(
      event: 'listen_along_event',
      callback: (payload) {
        final data = Map<String, dynamic>.from(payload);
        final targetUserId = data['target_user_id']?.toString() ?? '';
        final listenerId = data['listener_id']?.toString() ?? '';
        final listenerName = data['listener_name']?.toString() ?? 'A friend';
        final listenerUsername = data['listener_username']?.toString() ?? '';
        final listenerAvatar = data['listener_avatar']?.toString() ?? '';
        final action = data['action']?.toString() ?? '';

        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        if (currentUserId == null || listenerId == currentUserId) return;

        final isHost = targetUserId == currentUserId;
        final isCoListener = _listeningWithUserId != null &&
            _listeningWithUserId == targetUserId;

        if (isHost || isCoListener) {
          if (action == 'joined') {
            final existing = _sessionListeners[listenerId];
            if (existing == null) {
              _sessionListeners[listenerId] = PresenceListener(
                userId: listenerId,
                displayName: listenerName,
                username: listenerUsername,
                avatarUrl: listenerAvatar,
                joinedAt: DateTime.now(),
                lastSeenAt: DateTime.now(),
                isStillListening: true,
              );
            } else {
              _sessionListeners[listenerId] = existing.copyWith(
                displayName: listenerName,
                username: listenerUsername.isNotEmpty
                    ? listenerUsername
                    : existing.username,
                avatarUrl: listenerAvatar.isNotEmpty
                    ? listenerAvatar
                    : existing.avatarUrl,
                lastSeenAt: DateTime.now(),
                isStillListening: true,
              );
            }
            notifyListeners();

            if (isHost) {
              NotificationService().showListenTogetherJoinedNotification(
                listenerId: listenerId,
                listenerName: listenerName,
                songTitle: PlaybackService().currentTrack?.title ?? '',
              );
              // Broadcast immediately so joining listener snaps to exact host position with zero delay
              broadcastNow();
            } else {
              CookieService.show(
                message: '$listenerName joined the listening session',
                icon: Icons.headphones_rounded,
                iconColor: const Color(0xFF514AED),
              );
            }
          } else if (action == 'left') {
            final existing = _sessionListeners[listenerId];
            if (existing != null) {
              _sessionListeners[listenerId] = existing.copyWith(
                isStillListening: false,
                lastSeenAt: DateTime.now(),
              );
            } else {
              _sessionListeners[listenerId] = PresenceListener(
                userId: listenerId,
                displayName: listenerName,
                username: listenerUsername,
                avatarUrl: listenerAvatar,
                joinedAt: DateTime.now(),
                lastSeenAt: DateTime.now(),
                isStillListening: false,
              );
            }
            notifyListeners();

            CookieService.show(
              message: isHost
                  ? '$listenerName left your listening session'
                  : '$listenerName left the listening session',
              icon: Icons.person_remove_rounded,
              iconColor: Colors.white70,
            );
          }
        }
      },
    );

    _channel?.subscribe((status, error) {
      debugPrint('[Presence] Channel status: $status, error: $error');
      if (status == RealtimeSubscribeStatus.subscribed) {
        _isChannelSubscribed = true;
        _reconnectTimer?.cancel();
        broadcastNow();
        pingFriends();
      } else {
        _isChannelSubscribed = false;
        if (_isInitialized &&
            (status == RealtimeSubscribeStatus.closed ||
                status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut)) {
          _scheduleReconnect();
        }
      }
    });

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      // 1-second high-frequency sync when session is active (listeners connected or user is listening along)
      final hasListeners = currentListenersCount > 0;
      final isListeningAlong =
          _listeningWithUserId != null && _listeningWithUserId!.isNotEmpty;
      if (hasListeners || isListeningAlong) {
        broadcastNow();
      } else if (_isAppInForeground || PlaybackService().isPlaying) {
        _idleBroadcastCounter = (_idleBroadcastCounter + 1) % 4;
        if (_idleBroadcastCounter == 0) {
          broadcastNow();
        }
      }
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (!_isInitialized || _isChannelSubscribed) return;
      debugPrint('[Presence] Auto-reconnecting presence channel...');
      _reconnectChannel();
    });
  }

  void _reconnectChannel() {
    try {
      _channel?.unsubscribe();
    } catch (_) {}
    _channel = null;
    _isChannelSubscribed = false;
    _connectPresenceChannel();
  }

  void _onLocalPlaybackChanged() {
    final isPlaying = PlaybackService().isPlaying;
    if (!_isAppInForeground && !isPlaying) {
      debugPrint('[Presence] Audio stopped in background -> broadcasting offline');
      broadcastOffline();
    } else {
      // Play, pause, song changed, or song dismissed -> broadcast immediately!
      broadcastNow();
    }
  }

  void pingFriends() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _channel == null || !_isChannelSubscribed) return;
    final now = DateTime.now();
    if (_lastPingTime != null &&
        now.difference(_lastPingTime!).inMilliseconds < 1500) {
      return;
    }
    _lastPingTime = now;
    try {
      _channel?.sendBroadcastMessage(
        event: 'ping_presence',
        payload: {'sender_id': user.id},
      );
      debugPrint('[Presence] Sent ping_presence broadcast');
    } catch (e) {
      debugPrint('[Presence] Send ping broadcast error: $e');
    }
  }

  void broadcastNow() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _channel == null || !_isChannelSubscribed) return;

    final playback = PlaybackService();
    final current = playback.currentTrack;
    final isPlaying =
        playback.isPlaying && current != null && !playback.isLoading;
    final profile = ProfileService();

    final dName = profile.displayName.isNotEmpty
        ? profile.displayName
        : (user.userMetadata?['display_name'] ?? 'Melo User');
    final uName = profile.username.isNotEmpty
        ? profile.username
        : (user.userMetadata?['username'] ?? '');
    final avatar = profile.avatarUrl.isNotEmpty
        ? profile.avatarUrl
        : (user.userMetadata?['avatar_url'] ?? '');

    final payload = {
      'user_id': user.id,
      'display_name': dName,
      'username': uName,
      'avatar_url': avatar,
      'song_title': current?.title ?? '',
      'song_artist': current?.artist ?? '',
      'song_image': current?.image ?? '',
      'track_id': current?.id ?? '',
      'is_playing': isPlaying,
      'is_offline': false,
      'is_online': true,
      'position_ms': playback.position.inMilliseconds,
      'listening_with_user_id': _listeningWithUserId ?? '',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      _channel?.sendBroadcastMessage(
        event: 'playback_state',
        payload: payload,
      );
      debugPrint(
        '[Presence] Broadcast: ${current?.title ?? "No song"} (playing=$isPlaying, online=true)',
      );
    } catch (e) {
      debugPrint('[Presence] Send broadcast error: $e');
    }
  }

  void broadcastOffline() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _channel == null || !_isChannelSubscribed) return;

    if (PlaybackService().isPlaying) {
      debugPrint(
          '[Presence] Skipping offline broadcast because audio is playing in background');
      return;
    }

    final payload = {
      'user_id': user.id,
      'is_offline': true,
      'is_online': false,
      'is_playing': false,
      'song_title': '',
      'listening_with_user_id': '',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      _channel?.sendBroadcastMessage(
        event: 'playback_state',
        payload: payload,
      );
      debugPrint('[Presence] Sent instant OFFLINE broadcast');
    } catch (_) {}
  }

  void disposeChannel() {
    _heartbeatTimer?.cancel();
    _pruneOfflineTimer?.cancel();
    _reconnectTimer?.cancel();
    PlaybackService().removeListener(_onLocalPlaybackChanged);
    _channel?.unsubscribe();
    _channel = null;
    _isChannelSubscribed = false;
    _isInitialized = false;
  }
}
