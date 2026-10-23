import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'deep_link_service.dart';
import 'cookie_service.dart';
import '../view/profile_screen/user_profile_screen.dart';
import '../view/library_screen/playlist_detail_screen.dart';
import '../view/library_screen/playlist_invites_modal.dart';
import '../view/friends_screen/friends_screen.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  int _notificationIdCounter = 100;
  final Map<String, DateTime> _recentDedups = {};

  bool _isDuplicate(String key, {int cooldownSeconds = 6}) {
    final now = DateTime.now();
    final last = _recentDedups[key];
    if (last != null && now.difference(last).inSeconds < cooldownSeconds) {
      return true;
    }
    _recentDedups[key] = now;
    return false;
  }

  static const String channelId = 'melo_social_alerts';
  static const String channelName = 'Melo Social & Activity';
  static const String channelDescription =
      'Alerts for friend follows, playlist collaboration invites, and live listening sessions';

  /// Initialize native notification channels and handlers
  Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          handleNotificationTap(payload);
        }
      },
    );

    // Create the high-priority heads-up channel for Android
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );
    }

    _initialized = true;
    debugPrint('[NotificationService] Initialized successfully');
  }

  /// Request runtime permissions on Android 13+ (POST_NOTIFICATIONS)
  Future<bool> requestPermission() async {
    try {
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        debugPrint(
            '[NotificationService] Android notification permission granted: $granted');
        return granted ?? true;
      }
    } catch (e) {
      debugPrint('[NotificationService] Error requesting permission: $e');
    }
    return true;
  }

  /// Handle tap on a native notification banner
  void handleNotificationTap(String payload) {
    debugPrint('[NotificationService] User tapped notification: $payload');
    final nav = DeepLinkService().navigatorKey.currentState;
    if (nav == null) {
      // If navigator is not ready yet, retry in 500ms
      Future.delayed(const Duration(milliseconds: 500), () {
        handleNotificationTap(payload);
      });
      return;
    }

    if (payload.startsWith('user:')) {
      final userId = payload.substring('user:'.length);
      if (userId.isNotEmpty) {
        nav.push(
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(userId: userId),
          ),
        );
      }
    } else if (payload == 'invites') {
      nav.push(
        MaterialPageRoute(
          builder: (_) => const PlaylistInvitesModal(),
        ),
      );
    } else if (payload.startsWith('playlist:')) {
      final playlistId = payload.substring('playlist:'.length);
      if (playlistId.isNotEmpty) {
        nav.push(
          MaterialPageRoute(
            builder: (_) => PlaylistDetailScreen(playlistId: playlistId),
          ),
        );
      }
    } else if (payload == 'friends') {
      nav.push(
        MaterialPageRoute(
          builder: (_) => const FriendsScreen(),
        ),
      );
    }
  }

  int _nextId() {
    _notificationIdCounter++;
    if (_notificationIdCounter > 99999) _notificationIdCounter = 100;
    return _notificationIdCounter;
  }

  NotificationDetails _buildDetails({
    String? subText,
  }) {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      showWhen: true,
      color: const Color(0xFF514AED),
      icon: '@mipmap/ic_launcher',
      subText: subText,
      category: AndroidNotificationCategory.social,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    return NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );
  }

  /// 1. Follow Notification (Followed Back vs New Follower)
  Future<void> showFollowNotification({
    required String userId,
    required String name,
    required bool isMutual,
  }) async {
    if (_isDuplicate('follow:$userId')) return;

    final cleanName = name.trim().isNotEmpty ? name.trim() : 'Someone';
    final title = isMutual ? 'New Friend 🤝' : 'New Follower ✨';
    final body = isMutual
        ? '$cleanName followed you back! You are now friends.'
        : '$cleanName started following you.';

    try {
      await _localNotifications.show(
        id: _nextId(),
        title: title,
        body: body,
        notificationDetails:
            _buildDetails(subText: isMutual ? 'Friends' : 'Followers'),
        payload: 'user:$userId',
      );
    } catch (e) {
      debugPrint('[NotificationService] showFollowNotification error: $e');
    }

    // Also trigger in-app cookie banner
    CookieService.show(
      message: body,
      icon: isMutual ? Icons.people_alt_rounded : Icons.person_add_rounded,
      iconColor: const Color(0xFF514AED),
    );
  }

  /// 2. Playlist Collaboration Invite Received
  Future<void> showPlaylistInviteNotification({
    required String playlistId,
    required String playlistName,
    required String senderName,
  }) async {
    if (_isDuplicate('invite:$playlistId')) return;

    final cleanSender =
        senderName.trim().isNotEmpty ? senderName.trim() : 'A friend';
    final cleanPlaylist =
        playlistName.trim().isNotEmpty ? playlistName.trim() : 'a playlist';
    const title = 'Playlist Collab Invite 🎵';
    final body = '$cleanSender invited you to collaborate on "$cleanPlaylist"';

    try {
      await _localNotifications.show(
        id: _nextId(),
        title: title,
        body: body,
        notificationDetails: _buildDetails(subText: 'Collaborative Playlist'),
        payload: 'invites',
      );
    } catch (e) {
      debugPrint('[NotificationService] showPlaylistInvite error: $e');
    }

    CookieService.show(
      message: body,
      icon: Icons.library_music_rounded,
      iconColor: const Color(0xFF514AED),
    );
  }

  /// 3. Playlist Collaboration Invite Accepted
  Future<void> showInviteAcceptedNotification({
    required String playlistId,
    required String playlistName,
    required String userName,
  }) async {
    if (_isDuplicate('accept:$playlistId:$userName')) return;

    final cleanUser = userName.trim().isNotEmpty ? userName.trim() : 'A friend';
    final cleanPlaylist =
        playlistName.trim().isNotEmpty ? playlistName.trim() : 'your playlist';
    const title = 'Invite Accepted 🎉';
    final body = '$cleanUser accepted your invite to "$cleanPlaylist"';

    try {
      await _localNotifications.show(
        id: _nextId(),
        title: title,
        body: body,
        notificationDetails: _buildDetails(subText: 'Collaborative Playlist'),
        payload: 'playlist:$playlistId',
      );
    } catch (e) {
      debugPrint('[NotificationService] showInviteAccepted error: $e');
    }

    CookieService.show(
      message: body,
      icon: Icons.check_circle_rounded,
      iconColor: const Color(0xFF10B981),
    );
  }

  /// 4. Listen Together: Friend Joined Session
  Future<void> showListenTogetherJoinedNotification({
    required String listenerId,
    required String listenerName,
    required String songTitle,
  }) async {
    if (_isDuplicate('session:$listenerId')) return;
    final cleanName =
        listenerName.trim().isNotEmpty ? listenerName.trim() : 'A friend';
    const title = 'Listening Together 🎧';
    final body = songTitle.isNotEmpty
        ? '$cleanName joined your session listening to $songTitle'
        : '$cleanName joined your listening session';

    try {
      await _localNotifications.show(
        id: _nextId(),
        title: title,
        body: body,
        notificationDetails: _buildDetails(subText: 'Listen Together'),
        payload: 'session',
      );
    } catch (e) {
      debugPrint('[NotificationService] showListenTogetherJoined error: $e');
    }
  }

  /// Generic alert helper
  Future<void> showCustomNotification({
    required String title,
    required String body,
    String? payload,
    String? subText,
  }) async {
    try {
      await _localNotifications.show(
        id: _nextId(),
        title: title,
        body: body,
        notificationDetails: _buildDetails(subText: subText),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[NotificationService] showCustomNotification error: $e');
    }
  }
}
