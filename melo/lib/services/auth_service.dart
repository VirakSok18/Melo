import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_service.dart';
import 'new_releases_service.dart';
import 'vibe_service.dart';
import 'artist_service.dart';
import 'artist_follow_service.dart';
import 'recent_search_service.dart';
import 'download_service.dart';
import 'playback_service.dart';
import 'liked_songs_service.dart';
import 'playlist_service.dart';
import 'listening_history_service.dart';
import 'auto_cache_service.dart';
import 'profile_service.dart';
import 'premium_service.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signUp(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signInWithGoogle() async {
    const webClientId = String.fromEnvironment(
      'GOOGLE_WEB_CLIENT_ID',
      defaultValue: 'your_google_web_client_id_here',
    );

    final GoogleSignIn googleSignIn = GoogleSignIn(
      serverClientId: webClientId,
    );

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google sign in was cancelled');
    }

    final googleAuth = await googleUser.authentication;
    final accessToken = googleAuth.accessToken;
    final idToken = googleAuth.idToken;

    if (accessToken == null || idToken == null) {
      throw Exception('Failed to get Google tokens');
    }

    return await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  Future<void> signInWithFacebook() async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.facebook,
      redirectTo: 'io.supabase.melo://login-callback/',
    );
  }

  Future<void> signOut() async {
    // Reset in-memory services immediately
    PlaybackService().reset();
    ArtistService.clearCache();
    ArtistFollowService().clearCache();
    ArtistFollowService().unsubscribe();
    LikedSongsService.clearCache();
    PlaylistService().clearCache();
    ProfileService().reset();

    // Reset all disk-scoped state in parallel
    try {
      await Future.wait([
        DownloadService.clearCache(),
        AutoCacheService.clearCache(),
        HomeService.clearDiskCache(),
        NewReleasesService.clearCache(),
        VibeService.clearDiskCache(),
        ListeningHistoryService.clearCache(),
        RecentSearchService.clearAll(),
        PremiumService().clearLocalState(),
        SharedPreferences.getInstance().then((prefs) async {
          await prefs.remove('profile_setup_completed');
          await prefs.remove('profile_display_name');
          await prefs.remove('melo_profile_display_name');
          await prefs.remove('melo_profile_username');
          await prefs.remove('profile_avatar_url');
          await prefs.remove('melo_profile_avatar_url');
          await prefs.remove('melo_profile_followers');
          await prefs.remove('profile_favorite_genres');
          await prefs.remove('profile_favorite_artists');
        }),
        _supabase.auth.signOut(),
      ]);
    } catch (e) {
      debugPrint('Sign out error: $e');
    }
  }

  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }
}
