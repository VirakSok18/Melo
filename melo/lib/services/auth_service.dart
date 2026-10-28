import 'dart:async';
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
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // Anti-spam cooldown timers (in milliseconds)
  DateTime? _lastSignUpAttempt;
  DateTime? _lastOtpResendAttempt;
  DateTime? _lastPasswordResetAttempt;

  static const Duration _cooldownDuration = Duration(seconds: 45);

  /// Validates email address format
  static bool isValidEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty || trimmed.length > 254) return false;
    final emailRegex =
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(trimmed);
  }

  /// Direct client-side sign up via Supabase Auth with security validation and rate-limiting
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();
    if (!isValidEmail(cleanEmail)) {
      throw const AuthException('Please enter a valid email address.');
    }
    if (password.length < 6) {
      throw const AuthException('Password must be at least 6 characters long.');
    }

    // Rate-limiting check to prevent spam abuse
    final now = DateTime.now();
    if (_lastSignUpAttempt != null &&
        now.difference(_lastSignUpAttempt!) < const Duration(seconds: 5)) {
      throw const AuthException(
          'Too many requests. Please wait a few seconds before trying again.');
    }
    _lastSignUpAttempt = now;

    return await _supabase.auth.signUp(
      email: cleanEmail,
      password: password,
    );
  }

  /// Verifies a 6-digit OTP code for sign-up directly via Supabase Auth
  Future<AuthResponse> verifySignUpOtp({
    required String email,
    required String token,
  }) async {
    final cleanEmail = email.trim();
    final cleanToken = token.trim();

    if (cleanToken.length != 6) {
      throw const AuthException('Please enter a valid 6-digit verification code.');
    }

    return await _supabase.auth.verifyOTP(
      email: cleanEmail,
      token: cleanToken,
      type: OtpType.signup,
    );
  }

  /// Resends sign-up OTP code with 45s cooldown security guard
  Future<void> resendSignUpOtp({
    required String email,
  }) async {
    final cleanEmail = email.trim();
    final now = DateTime.now();
    if (_lastOtpResendAttempt != null &&
        now.difference(_lastOtpResendAttempt!) < _cooldownDuration) {
      final remaining =
          _cooldownDuration.inSeconds - now.difference(_lastOtpResendAttempt!).inSeconds;
      throw AuthException(
          'Please wait $remaining seconds before requesting another code.');
    }
    _lastOtpResendAttempt = now;

    await _supabase.auth.resend(
      type: OtpType.signup,
      email: cleanEmail,
    );
  }

  /// Direct client-side sign in via Supabase Auth
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();
    if (!isValidEmail(cleanEmail)) {
      throw const AuthException('Please enter a valid email address.');
    }
    if (password.isEmpty) {
      throw const AuthException('Please enter your password.');
    }

    return await _supabase.auth.signInWithPassword(
      email: cleanEmail,
      password: password,
    );
  }

  /// Direct client-side Google Sign-In with Supabase Auth OAuth provider
  Future<AuthResponse> signInWithGoogle() async {
    const webClientId = String.fromEnvironment(
      'GOOGLE_WEB_CLIENT_ID',
      defaultValue:
          '583980575924-q4ellmg3de7hibrhpo04alpr4rf2nm2b.apps.googleusercontent.com',
    );

    final GoogleSignIn googleSignIn = GoogleSignIn(
      serverClientId: webClientId,
    );

    await googleSignIn.signOut();
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw const AuthException('Google sign in was cancelled');
    }

    final googleAuth = await googleUser.authentication;
    final accessToken = googleAuth.accessToken;
    final idToken = googleAuth.idToken;

    if (idToken == null) {
      throw const AuthException('Failed to get Google ID token from device.');
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

  /// Initiates password reset by sending an OTP directly via Supabase Auth
  Future<void> sendPasswordResetOtp(String email) async {
    final cleanEmail = email.trim();
    if (!isValidEmail(cleanEmail)) {
      throw const AuthException('Please enter a valid email address.');
    }

    final now = DateTime.now();
    if (_lastPasswordResetAttempt != null &&
        now.difference(_lastPasswordResetAttempt!) < _cooldownDuration) {
      final remaining =
          _cooldownDuration.inSeconds - now.difference(_lastPasswordResetAttempt!).inSeconds;
      throw AuthException(
          'Please wait $remaining seconds before requesting another reset code.');
    }
    _lastPasswordResetAttempt = now;

    await _supabase.auth.resetPasswordForEmail(cleanEmail);
  }

  /// Verifies password reset OTP code directly via Supabase Auth
  Future<AuthResponse> verifyPasswordResetOtp({
    required String email,
    required String token,
  }) async {
    final cleanEmail = email.trim();
    final cleanToken = token.trim();

    if (cleanToken.length != 6) {
      throw const AuthException('Please enter a valid 6-digit code.');
    }

    return await _supabase.auth.verifyOTP(
      email: cleanEmail,
      token: cleanToken,
      type: OtpType.recovery,
    );
  }

  /// Updates user password directly via Supabase Auth
  Future<UserResponse> updatePassword(String newPassword) async {
    if (newPassword.length < 6) {
      throw const AuthException('Password must be at least 6 characters long.');
    }

    return await _supabase.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  /// Signs out and purges local user caches
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
    await sendPasswordResetOtp(email);
  }
}
