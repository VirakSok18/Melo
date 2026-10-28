import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService extends ChangeNotifier {
  static final ProfileService _instance = ProfileService._();
  factory ProfileService() => _instance;

  ProfileService._() {
    _loadFromDisk();
    _listenAuth();
  }

  String displayName = '';
  String username = '';
  String avatarUrl = '';
  int followers = 0;
  bool _loaded = false;
  RealtimeChannel? _realtimeChannel;
  StreamSubscription<AuthState>? _authSub;

  static const String _keyDisplayName = 'melo_profile_display_name';
  static const String _keyUsername = 'melo_profile_username';
  static const String _keyAvatarUrl = 'melo_profile_avatar_url';
  static const String _keyFollowers = 'melo_profile_followers';

  void _listenAuth() {
    try {
      _authSub?.cancel();
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        final event = data.event;
        if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.tokenRefreshed ||
            event == AuthChangeEvent.userUpdated) {
          load(forceRefresh: true);
          subscribeToRealtime();
        } else if (event == AuthChangeEvent.signedOut) {
          reset();
        }
      });
    } catch (e) {
      debugPrint('[ProfileService] Auth listener error: $e');
    }
  }

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedName = prefs.getString(_keyDisplayName) ?? prefs.getString('profile_display_name');
      final cachedUser = prefs.getString(_keyUsername);
      final cachedAvatar = prefs.getString(_keyAvatarUrl) ?? prefs.getString('profile_avatar_url');
      final cachedFollowers = prefs.getInt(_keyFollowers);

      if (cachedName != null && cachedName.isNotEmpty) {
        displayName = cachedName;
      }
      if (cachedUser != null && cachedUser.isNotEmpty) {
        username = cachedUser;
      }
      if (cachedAvatar != null && cachedAvatar.isNotEmpty) {
        avatarUrl = cachedAvatar;
      }
      if (cachedFollowers != null) {
        followers = cachedFollowers;
      }
      if (displayName.isNotEmpty || username.isNotEmpty) {
        _loaded = true;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDisplayName, displayName);
      await prefs.setString('profile_display_name', displayName);
      await prefs.setString(_keyUsername, username);
      await prefs.setString(_keyAvatarUrl, avatarUrl);
      await prefs.setString('profile_avatar_url', avatarUrl);
      await prefs.setInt(_keyFollowers, followers);
    } catch (_) {}
  }

  void notifyUpdate() {
    notifyListeners();
  }

  void reset() {
    displayName = '';
    username = '';
    avatarUrl = '';
    followers = 0;
    _loaded = false;
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    notifyListeners();
  }

  Future<void> init() async {
    await _loadFromDisk();
    await load(forceRefresh: true);
    subscribeToRealtime();
  }

  void subscribeToRealtime() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _realtimeChannel != null) return;

    try {
      _realtimeChannel = Supabase.instance.client
          .channel('public:profiles:${user.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'profiles',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: user.id,
            ),
            callback: (payload) {
              final newRecord = payload.newRecord;
              if (newRecord.isNotEmpty) {
                final newName = newRecord['display_name']?.toString();
                final newUser = newRecord['username']?.toString();
                final newAvatar = newRecord['avatar_url']?.toString();
                if (newName != null && newName.isNotEmpty) {
                  displayName = newName;
                }
                if (newUser != null && newUser.isNotEmpty) {
                  username = newUser;
                }
                if (newAvatar != null && newAvatar.isNotEmpty) {
                  avatarUrl = newAvatar;
                }
                notifyListeners();
                saveToDisk();
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[ProfileService] Realtime subscription error: $e');
    }
  }

  Future<void> load({bool forceRefresh = false}) async {
    if (_loaded && !forceRefresh) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Instant zero-latency seed from user metadata if available
    final metaName = user.userMetadata?['display_name']?.toString() ??
        user.userMetadata?['full_name']?.toString() ??
        user.userMetadata?['name']?.toString();
    final metaAvatar = user.userMetadata?['avatar_url']?.toString() ??
        user.userMetadata?['picture']?.toString();

    if (displayName.isEmpty && metaName != null && metaName.isNotEmpty) {
      displayName = metaName;
      notifyListeners();
    }
    if (avatarUrl.isEmpty && metaAvatar != null && metaAvatar.isNotEmpty) {
      avatarUrl = metaAvatar;
      notifyListeners();
    }

    try {
      // 1. Fetch user profile record
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('display_name, username, avatar_url')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));

      if (profile != null) {
        final fetchedName = profile['display_name']?.toString() ?? '';
        final fetchedUser = profile['username']?.toString() ?? '';
        final fetchedAvatar = profile['avatar_url']?.toString() ?? '';

        if (fetchedName.isNotEmpty) {
          displayName = fetchedName;
        } else if (fetchedUser.isNotEmpty) {
          displayName = fetchedUser;
        } else if (metaName != null && metaName.isNotEmpty) {
          displayName = metaName;
        }

        if (fetchedUser.isNotEmpty) username = fetchedUser;
        if (fetchedAvatar.isNotEmpty) {
          avatarUrl = fetchedAvatar;
        } else if (metaAvatar != null && metaAvatar.isNotEmpty) {
          avatarUrl = metaAvatar;
        }

        _loaded = true;
        notifyListeners();
        await saveToDisk();
      }

      // 2. Fetch follower count independently (failure never stalls name/avatar)
      try {
        final count = await Supabase.instance.client
            .from('profile_follows')
            .count()
            .eq('following_id', user.id)
            .timeout(const Duration(seconds: 3));
        followers = count;
        notifyListeners();
        await saveToDisk();
      } catch (_) {}
    } catch (e) {
      debugPrint('ProfileService load error: $e');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
