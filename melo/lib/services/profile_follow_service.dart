import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';
import 'profile_service.dart';

class UserProfileItem {
  final String id;
  final String displayName;
  final String username;
  final String avatarUrl;
  final int followersCount;
  final int followingCount;
  final DateTime? followedAt;

  UserProfileItem({
    required this.id,
    required this.displayName,
    required this.username,
    required this.avatarUrl,
    this.followersCount = 0,
    this.followingCount = 0,
    this.followedAt,
  });

  factory UserProfileItem.fromMap(Map<String, dynamic> map,
      {DateTime? followedAt}) {
    return UserProfileItem(
      id: map['id']?.toString() ?? '',
      displayName: map['display_name']?.toString() ?? '',
      username: map['username']?.toString() ?? '',
      avatarUrl: map['avatar_url']?.toString() ?? '',
      followersCount:
          map['followers_count'] is int ? map['followers_count'] : 0,
      followingCount:
          map['following_count'] is int ? map['following_count'] : 0,
      followedAt: followedAt,
    );
  }
}

class ProfileFollowService extends ChangeNotifier {
  static final ProfileFollowService _instance =
      ProfileFollowService._internal();
  factory ProfileFollowService() => _instance;
  ProfileFollowService._internal();

  final Set<String> _followingIds = {};
  final Set<String> _followerIds = {};

  List<UserProfileItem> _followingList = [];
  List<UserProfileItem> _followersList = [];
  List<UserProfileItem> _mutualFriendsList = [];

  final Set<String> _dismissedNotificationFollowerIds = {};
  final Set<String> _seenNotificationFollowerIds = {};
  DateTime? _lastSeenFollowersTimestamp;

  bool _loaded = false;
  bool _isLoading = false;
  String? _notificationPrefsUserId;

  bool get loaded => _loaded;
  bool get isLoading => _isLoading;
  Set<String> get followingIds => Set.unmodifiable(_followingIds);
  Set<String> get followerIds => Set.unmodifiable(_followerIds);
  List<UserProfileItem> get followingList => List.unmodifiable(_followingList);
  List<UserProfileItem> get followersList => List.unmodifiable(_followersList);
  List<UserProfileItem> get mutualFriendsList =>
      List.unmodifiable(_mutualFriendsList);

  /// Followers that have not been dismissed from the notification panel.
  List<UserProfileItem> get activeFollowerNotifications =>
      List.unmodifiable(_followersList
          .where((u) => !_dismissedNotificationFollowerIds.contains(u.id)));

  /// Followers that haven't been seen yet (triggers badge dot on bell)
  int get unreadFollowerNotificationsCount => _followersList.where((u) {
        if (_dismissedNotificationFollowerIds.contains(u.id)) return false;
        if (_lastSeenFollowersTimestamp != null) {
          if (u.followedAt != null) {
            return u.followedAt!.isAfter(_lastSeenFollowersTimestamp!);
          }
          return !_seenNotificationFollowerIds.contains(u.id);
        }
        return !_seenNotificationFollowerIds.contains(u.id);
      }).length;

  int get followingCount => _followingIds.length;
  int get followersCount => _followerIds.length;
  int get mutualFriendsCount => _mutualFriendsList.length;

  bool isFollowing(String userId) => _followingIds.contains(userId);
  bool isFollower(String userId) => _followerIds.contains(userId);
  bool isMutualFriend(String userId) =>
      _followingIds.contains(userId) && _followerIds.contains(userId);

  RealtimeChannel? _followChannel;

  static String _dismissedKey(String userId) =>
      'dismissed_follower_notifs_v2_$userId';
  static String _legacyDismissedKey(String userId) =>
      'dismissed_follower_notifs_$userId';
  static String _seenKey(String userId) => 'seen_follower_notifs_$userId';
  static String _seenTimestampKey(String userId) =>
      'seen_follower_notifs_time_$userId';

  Future<void> init() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    await _loadNotificationPrefs(user.id);
    await loadFollowData();
    _subscribeToFollowChanges(user.id);
  }

  Future<void> _loadNotificationPrefs(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> dismissed;
      if (prefs.containsKey(_dismissedKey(userId))) {
        dismissed = prefs.getStringList(_dismissedKey(userId)) ?? [];
      } else {
        // Discard legacy dismissed list which was corrupted by old followUser bug
        dismissed = [];
        await prefs.remove(_legacyDismissedKey(userId));
      }
      final seen = prefs.getStringList(_seenKey(userId)) ?? [];
      final rawTime = prefs.getString(_seenTimestampKey(userId));
      _dismissedNotificationFollowerIds
        ..clear()
        ..addAll(dismissed);
      _seenNotificationFollowerIds
        ..clear()
        ..addAll(seen);
      if (rawTime != null && rawTime.isNotEmpty) {
        _lastSeenFollowersTimestamp = DateTime.tryParse(rawTime);
      }
      _notificationPrefsUserId = userId;
    } catch (e) {
      debugPrint('[ProfileFollowService] Error loading notif prefs: $e');
    }
  }

  Future<void> _saveNotificationPrefs() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _dismissedKey(user.id), _dismissedNotificationFollowerIds.toList());
      await prefs.setStringList(
          _seenKey(user.id), _seenNotificationFollowerIds.toList());
      if (_lastSeenFollowersTimestamp != null) {
        await prefs.setString(_seenTimestampKey(user.id),
            _lastSeenFollowersTimestamp!.toIso8601String());
      }
    } catch (e) {
      debugPrint('[ProfileFollowService] Error saving notif prefs: $e');
    }
  }

  Future<void> markFollowersAsSeen() async {
    _lastSeenFollowersTimestamp = DateTime.now();
    for (final f in _followersList) {
      _seenNotificationFollowerIds.add(f.id);
    }
    for (final id in _followerIds) {
      _seenNotificationFollowerIds.add(id);
    }
    await _saveNotificationPrefs();
    notifyListeners();
  }

  Future<void> dismissFollowerNotification(String followerId) async {
    _dismissedNotificationFollowerIds.add(followerId);
    _seenNotificationFollowerIds.add(followerId);
    await _saveNotificationPrefs();
    notifyListeners();
  }

  Future<void> clearAllFollowerNotifications(List<String> followerIds) async {
    _lastSeenFollowersTimestamp = DateTime.now();
    _dismissedNotificationFollowerIds.addAll(followerIds);
    _seenNotificationFollowerIds.addAll(followerIds);
    await _saveNotificationPrefs();
    notifyListeners();
  }

  void _subscribeToFollowChanges(String userId) {
    _followChannel?.unsubscribe();
    _followChannel = Supabase.instance.client
        .channel('profile_follows_realtime:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profile_follows',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'following_id',
            value: userId,
          ),
          callback: (payload) async {
            debugPrint(
                '[Follows] Realtime incoming follow change detected: ${payload.eventType}, reloading...');
            final followerId = payload.newRecord['follower_id']?.toString();
            if (followerId != null &&
                followerId.isNotEmpty &&
                followerId != userId) {
              _dismissedNotificationFollowerIds.remove(followerId);
              _saveNotificationPrefs();

              if (payload.eventType == PostgresChangeEvent.insert) {
                final isMutual = isFollowing(followerId);
                String displayName = 'Someone';
                try {
                  final profile = await Supabase.instance.client
                      .from('profiles')
                      .select('display_name, username')
                      .eq('id', followerId)
                      .maybeSingle();
                  if (profile != null) {
                    final dName = profile['display_name']?.toString() ?? '';
                    final uName = profile['username']?.toString() ?? '';
                    displayName = dName.isNotEmpty
                        ? dName
                        : (uName.isNotEmpty ? '@$uName' : 'Someone');
                  }
                } catch (e) {
                  debugPrint('[Follows] Error fetching follower profile: $e');
                }

                NotificationService().showFollowNotification(
                  userId: followerId,
                  name: displayName,
                  isMutual: isMutual,
                );
              }
            }
            loadFollowData();
          },
        )
        .onBroadcast(
          event: 'follow_alert',
          callback: (payload) {
            final data = Map<String, dynamic>.from(payload);
            final targetUserId = data['target_user_id']?.toString() ?? '';
            final followerId = data['follower_id']?.toString() ?? '';
            final followerName = data['follower_name']?.toString() ?? 'Someone';
            final isMutual = data['is_mutual'] == true;

            if (targetUserId == userId &&
                followerId.isNotEmpty &&
                followerId != userId) {
              _dismissedNotificationFollowerIds.remove(followerId);
              _saveNotificationPrefs();

              NotificationService().showFollowNotification(
                userId: followerId,
                name: followerName,
                isMutual: isMutual,
              );
              loadFollowData();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profile_follows',
          callback: (payload) {
            debugPrint(
                '[Follows] Realtime general follow change detected, reloading...');
            loadFollowData();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (payload) {
            debugPrint(
                '[Follows] Realtime profile change detected, reloading data...');
            loadFollowData();
          },
        )
        .subscribe();
  }

  Future<void> loadFollowData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Library can load before the app's background initialization completes.
    // Restore persisted seen IDs first, otherwise old followers briefly (or
    // after a hot restart, permanently) look unread again.
    if (_notificationPrefsUserId != user.id) {
      await _loadNotificationPrefs(user.id);
    }

    _isLoading = true;
    notifyListeners();

    try {
      await _loadFollowDataDirect(user.id);
      _loaded = true;
    } catch (e) {
      debugPrint('[ProfileFollowService] Error loading follow data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadFollowDataDirect(String currentUserId) async {
    try {
      final followingResp = await Supabase.instance.client
          .from('profile_follows')
          .select('following_id, created_at')
          .eq('follower_id', currentUserId);

      final followersResp = await Supabase.instance.client
          .from('profile_follows')
          .select('follower_id, created_at')
          .eq('following_id', currentUserId);

      _followingIds.clear();
      final followingDates = <String, DateTime?>{};
      for (final r in followingResp as List) {
        final id = r['following_id']?.toString();
        if (id != null && id.isNotEmpty) {
          _followingIds.add(id);
          followingDates[id] =
              DateTime.tryParse(r['created_at']?.toString() ?? '');
        }
      }

      _followerIds.clear();
      final followerDates = <String, DateTime?>{};
      for (final r in followersResp as List) {
        final id = r['follower_id']?.toString();
        if (id != null && id.isNotEmpty) {
          _followerIds.add(id);
          followerDates[id] =
              DateTime.tryParse(r['created_at']?.toString() ?? '');
        }
      }

      final allUserIds = {..._followingIds, ..._followerIds}.toList();
      if (allUserIds.isNotEmpty) {
        final profileMap = <String, UserProfileItem>{};
        try {
          final profilesResp = await Supabase.instance.client
              .from('profiles')
              .select('id, display_name, username, avatar_url')
              .inFilter('id', allUserIds);
          for (final p in profilesResp as List) {
            final item = UserProfileItem.fromMap(p as Map<String, dynamic>);
            profileMap[item.id] = item;
          }
        } catch (profileError) {
          debugPrint(
              '[ProfileFollowService] Profile details unavailable: $profileError');
        }

        _followingList = _followingIds.map((id) {
          final item = profileMap[id];
          return UserProfileItem(
            id: id,
            displayName: item?.displayName ?? 'User',
            username: item?.username ?? '',
            avatarUrl: item?.avatarUrl ?? '',
            followedAt: followingDates[id],
          );
        }).toList();

        _followersList = _followerIds.map((id) {
          final item = profileMap[id];
          return UserProfileItem(
            id: id,
            displayName: item?.displayName ?? 'User',
            username: item?.username ?? '',
            avatarUrl: item?.avatarUrl ?? '',
            followedAt: followerDates[id],
          );
        }).toList();

        // Sort followers by latest first
        _followersList.sort((a, b) {
          if (a.followedAt == null && b.followedAt == null) return 0;
          if (a.followedAt == null) return 1;
          if (b.followedAt == null) return -1;
          return b.followedAt!.compareTo(a.followedAt!);
        });

        _mutualFriendsList =
            _followingList.where((u) => _followerIds.contains(u.id)).toList();
      } else {
        _followingList = [];
        _followersList = [];
        _mutualFriendsList = [];
      }
      _loaded = true;
    } catch (err) {
      debugPrint('[ProfileFollowService] Direct load follow data error: $err');
    }
  }

  Future<bool> followUser(UserProfileItem targetUser) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null || currentUser.id == targetUser.id) return false;

    // Optimistic Update
    _followingIds.add(targetUser.id);
    if (!_followingList.any((u) => u.id == targetUser.id)) {
      _followingList.insert(0, targetUser);
    }
    if (_followerIds.contains(targetUser.id) &&
        !_mutualFriendsList.any((u) => u.id == targetUser.id)) {
      _mutualFriendsList.insert(0, targetUser);
    }
    notifyListeners();

    try {
      await Supabase.instance.client.from('profile_follows').upsert({
        'follower_id': currentUser.id,
        'following_id': targetUser.id,
      }, onConflict: 'follower_id,following_id');

      // Instant broadcast alert to target user
      try {
        final profile = ProfileService();
        final myName = profile.displayName.isNotEmpty
            ? profile.displayName
            : (currentUser.userMetadata?['display_name'] ?? 'Someone');
        final isFollowBack = _followerIds.contains(targetUser.id);

        final alertChannel = Supabase.instance.client
            .channel('profile_follows_realtime:${targetUser.id}');
        await alertChannel.sendBroadcastMessage(
          event: 'follow_alert',
          payload: {
            'target_user_id': targetUser.id,
            'follower_id': currentUser.id,
            'follower_name': myName,
            'is_mutual': isFollowBack,
          },
        );
      } catch (e) {
        debugPrint('[ProfileFollowService] Broadcast follow alert error: $e');
      }

      return true;
    } catch (e) {
      debugPrint('[ProfileFollowService] Follow user error: $e');
      // Rollback
      _followingIds.remove(targetUser.id);
      _followingList.removeWhere((u) => u.id == targetUser.id);
      _mutualFriendsList.removeWhere((u) => u.id == targetUser.id);
      notifyListeners();
      return false;
    }
  }

  Future<bool> unfollowUser(String targetUserId) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return false;

    final removedUser = _followingList.firstWhere(
      (u) => u.id == targetUserId,
      orElse: () => UserProfileItem(
          id: targetUserId, displayName: '', username: '', avatarUrl: ''),
    );

    // Optimistic Update
    _followingIds.remove(targetUserId);
    _followingList.removeWhere((u) => u.id == targetUserId);
    _mutualFriendsList.removeWhere((u) => u.id == targetUserId);
    notifyListeners();

    try {
      await Supabase.instance.client
          .from('profile_follows')
          .delete()
          .eq('follower_id', currentUser.id)
          .eq('following_id', targetUserId);
      return true;
    } catch (e) {
      debugPrint('[ProfileFollowService] Unfollow user error: $e');
      // Rollback
      _followingIds.add(targetUserId);
      if (removedUser.displayName.isNotEmpty) {
        _followingList.insert(0, removedUser);
      }
      if (_followerIds.contains(targetUserId)) {
        _mutualFriendsList.insert(0, removedUser);
      }
      notifyListeners();
      return false;
    }
  }

  /// Search user profiles by query (display name or @username)
  Future<List<UserProfileItem>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final cleanQuery = query.trim().replaceAll('@', '');
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;

      final rows = await Supabase.instance.client
          .from('profiles')
          .select('id, display_name, username, avatar_url')
          .or('username.ilike.%$cleanQuery%,display_name.ilike.%$cleanQuery%')
          .limit(20);

      final List<UserProfileItem> list = [];
      for (final r in rows as List) {
        final item = UserProfileItem.fromMap(r as Map<String, dynamic>);
        if (item.id != currentUserId) {
          list.add(item);
        }
      }
      return list;
    } catch (e) {
      debugPrint('[ProfileFollowService] Search users error: $e');
      return [];
    }
  }
}
