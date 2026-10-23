import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../view/library_screen/playlist_detail_screen.dart';
import '../view/profile_screen/user_profile_screen.dart';
import 'playback_service.dart';
import 'search_service.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  void init() {
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // Check initial launch link (cold start)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleUri(initialUri);
      }
    } catch (e) {
      debugPrint('[DeepLinkService] initial link error: $e');
    }

    // Listen to incoming links while app is open / in background
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) => _handleUri(uri),
      onError: (err) {
        debugPrint('[DeepLinkService] uri stream error: $err');
      },
    );
  }

  void _handleUri(Uri uri) {
    debugPrint('[DeepLinkService] Received deep link: $uri');

    String? playlistId;
    String? profileUsername;
    String? songId;

    if (uri.scheme == 'melo') {
      final host = uri.host.toLowerCase();
      final segments = uri.pathSegments;

      if (host == 'playlist' ||
          (segments.isNotEmpty && segments.first == 'playlist')) {
        playlistId = host == 'playlist'
            ? (segments.isNotEmpty ? segments.first : null)
            : (segments.length > 1 ? segments[1] : null);
      } else if (host == 'profile' ||
          (segments.isNotEmpty && segments.first == 'profile')) {
        profileUsername = host == 'profile'
            ? (segments.isNotEmpty ? segments.first : null)
            : (segments.length > 1 ? segments[1] : null);
      } else if (host == 'song' ||
          (segments.isNotEmpty && segments.first == 'song')) {
        songId = host == 'song'
            ? (segments.isNotEmpty ? segments.first : null)
            : (segments.length > 1 ? segments[1] : null);
      }
    } else if (uri.host.contains('melo.app')) {
      playlistId = uri.queryParameters['playlist'];
      profileUsername = uri.queryParameters['profile'];
      songId = uri.queryParameters['song'];
    }

    if (playlistId != null && playlistId.isNotEmpty) {
      _navigateToPlaylist(playlistId);
    } else if (profileUsername != null && profileUsername.isNotEmpty) {
      _navigateToProfile(profileUsername);
    } else if (songId != null && songId.isNotEmpty) {
      _playSong(songId);
    }
  }

  Future<void> _navigateToPlaylist(String playlistId) async {
    if (navigatorKey.currentState == null) {
      await Future.delayed(const Duration(milliseconds: 600));
    }

    try {
      final res = await Supabase.instance.client
          .from('user_playlists')
          .select()
          .eq('id', playlistId)
          .maybeSingle();

      if (res != null) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => PlaylistDetailScreen(playlistId: playlistId),
          ),
        );
      }
    } catch (e) {
      debugPrint('[DeepLinkService] load playlist error: $e');
    }
  }

  Future<void> _navigateToProfile(String username) async {
    if (navigatorKey.currentState == null) {
      await Future.delayed(const Duration(milliseconds: 600));
    }

    try {
      final clean = username.replaceAll('@', '');
      final res = await Supabase.instance.client
          .from('profiles')
          .select('id, display_name, username, avatar_url')
          .eq('username', clean)
          .maybeSingle();

      if (res != null) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(
              userId: res['id'] ?? '',
              initialDisplayName: res['display_name'] ?? '',
              initialUsername: res['username'] ?? '',
              initialAvatarUrl: res['avatar_url'],
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[DeepLinkService] load profile error: $e');
    }
  }

  Future<void> _playSong(String songId) async {
    try {
      final res = await http
          .get(Uri.parse('https://api.deezer.com/track/$songId'))
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final track = SearchResult.fromDeezerTrack(data);
        PlaybackService().playTrack(track);
        return;
      }
    } catch (e) {
      debugPrint('[DeepLinkService] fetch track $songId error: $e');
    }

    final track = SearchResult(
      type: 'song',
      id: songId,
      title: 'Shared song',
      artist: '',
      image: '',
      duration: '',
      nbFan: 0,
      previewUrl: '',
    );
    PlaybackService().playTrack(track);
  }

  void dispose() {
    _linkSubscription?.cancel();
  }
}
