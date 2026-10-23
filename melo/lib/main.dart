import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'config/api_config.dart';
import 'services/download_service.dart';
import 'services/listening_history_service.dart';
import 'services/liked_songs_service.dart';
import 'services/playlist_service.dart';
import 'services/artist_follow_service.dart';
import 'services/profile_follow_service.dart';
import 'services/presence_service.dart';
import 'services/auto_cache_service.dart';
import 'services/generated_history_service.dart';
import 'services/profile_service.dart';
import 'services/deezer_proxy.dart';
import 'services/deezer_service.dart';
import 'services/playback_service.dart';
import 'services/secure_storage_service.dart';
import 'services/deep_link_service.dart';
import 'services/notification_service.dart';
import 'services/cookie_service.dart';
import 'services/premium_service.dart';
import 'view/onboarding_screen/onboarding_screen.dart';
import 'view/home_screen/home_screen.dart';
import 'view/setup_flow_screen/setup_flow_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.melo.channel.audio',
    androidNotificationChannelName: 'Melo Audio Playback',
    androidNotificationOngoing: false,
    androidStopForegroundOnPause: false,
    androidShowNotificationBadge: true,
    androidNotificationIcon: 'mipmap/ic_launcher',
    notificationColor: const Color(0xFF514AED),
  );

  await SecureStorageService.init();

  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://your-project.supabase.co',
  );
  const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'your_supabase_anon_key_here',
  );

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  // Mount UI immediately so the splash screen opens in under 1 second
  runApp(const MyApp());

  // Run non-critical network probes and background state sync asynchronously
  unawaited(_runBackgroundInit());
}

Future<void> _runBackgroundInit() async {
  try {
    ApiConfig.refreshHost();
    ApiConfig.startAutoRefresh();
    DownloadService.init();
    ProfileService().init();
    ProfileFollowService().init();
    PremiumService().init();
    PresenceService().init();
    DeezerProxy.instance.ensureRunning();
    DeezerService.warmupAuth();
    PlaybackService().restoreLastPlaybackState();

    // Keep local session intact; do not sign out automatically on transient network/auth errors.
    // The user should only ever be signed out when they explicitly choose to.
  } catch (e) {
    debugPrint('[BackgroundInit] Error: $e');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initialize presence on app launch
    PresenceService().init();
    // Initialize notification service and request notification permissions
    NotificationService().init().then((_) {
      NotificationService().requestPermission();
    });
    // Initialize deep link listener for shared links
    DeepLinkService().init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DeepLinkService().dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App brought to foreground -> immediately broadcast online state!
      PresenceService().onAppForeground();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      // App closed or minimized -> check if music is playing; if not, go offline!
      PresenceService().onAppBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: DeepLinkService().navigatorKey,
      title: 'Melo',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _MeloScrollBehavior(),
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF514AED),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF191919),
        canvasColor: const Color(0xFF191919),
        useMaterial3: true,
      ),
      home: const AuthGate(),
      builder: (context, child) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            // Dismiss keyboard and unfocus any text field when tapping outside
            FocusManager.instance.primaryFocus?.unfocus();
          },
          child:
              _DownloadOverlayWrapper(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

/// Uses the same edge bounce across Android and iOS, and suppresses Android's
/// stretch/glow indicator. Individual non-scrollable inner lists keep their
/// explicit NeverScrollableScrollPhysics.
class _MeloScrollBehavior extends MaterialScrollBehavior {
  const _MeloScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class _DownloadOverlayWrapper extends StatefulWidget {
  final Widget child;
  const _DownloadOverlayWrapper({required this.child});

  @override
  State<_DownloadOverlayWrapper> createState() =>
      _DownloadOverlayWrapperState();
}

class _DownloadOverlayWrapperState extends State<_DownloadOverlayWrapper>
    with SingleTickerProviderStateMixin {
  bool _show = false;
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -1.2),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _anim,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  ));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _anim,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  String _currentMessage = '';
  IconData? _currentIcon;
  Color? _currentIconColor;
  int _lastPlaybackErrorSeq = -1;

  @override
  void initState() {
    super.initState();
    CookieService.instance.addListener(_onCookieChange);
    DownloadService.downloadingTrackIdNotifier.addListener(_onDownloadChange);
    PlaybackService().addListener(_onPlaybackError);
  }

  @override
  void dispose() {
    CookieService.instance.removeListener(_onCookieChange);
    DownloadService.downloadingTrackIdNotifier
        .removeListener(_onDownloadChange);
    PlaybackService().removeListener(_onPlaybackError);
    _anim.dispose();
    super.dispose();
  }

  void _onCookieChange() {
    final item = CookieService.instance.current;
    if (item != null) {
      setState(() {
        _currentMessage = item.message;
        _currentIcon = item.icon;
        _currentIconColor = item.iconColor;
        _show = true;
      });
      _anim.forward(from: 0.0);
    } else if (_show) {
      _dismiss();
    }
  }

  void _onDownloadChange() {
    if (DownloadService.downloadingTrackId != null) {
      CookieService.show(
        message: 'Downloading song...',
        icon: Icons.download_rounded,
        iconColor: const Color(0xFF8A82FF),
      );
    }
  }

  void _onPlaybackError() {
    final msg = PlaybackService().errorMessage;
    final seq = PlaybackService().errorSeq;
    if (msg == null || msg.isEmpty || seq == _lastPlaybackErrorSeq) return;
    _lastPlaybackErrorSeq = seq;
    CookieService.show(
      message: msg,
      icon: Icons.info_outline_rounded,
      iconColor: Colors.white70,
    );
  }

  void _dismiss() {
    _anim.reverse().then((_) {
      if (mounted) {
        setState(() => _show = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_show)
          Positioned(
            top: MediaQuery.of(context).padding.top + 28,
            left: 20,
            right: 20,
            child: SlideTransition(
              position: _slide,
              child: FadeTransition(
                opacity: _fade,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      CookieService.instance.dismiss();
                    },
                    onVerticalDragEnd: (details) {
                      if (details.primaryVelocity != null &&
                          details.primaryVelocity! < 0) {
                        CookieService.instance.dismiss();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16151D),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_currentIcon != null) ...[
                            Icon(
                              _currentIcon,
                              color:
                                  _currentIconColor ?? const Color(0xFF8A82FF),
                              size: 17,
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              _currentMessage,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.none,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textScaler: TextScaler.noScaling,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  static const _profileCacheKey = 'profile_setup_completed';

  static Future<void> markProfileComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AuthGate._profileCacheKey, true);
  }

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _profileCompleted;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _checkProfile();
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      // Only re-check profile if auth state really changes (e.g. signed in or signed out)
      if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.signedOut ||
          data.event == AuthChangeEvent.userUpdated) {
        _checkProfile();
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkProfile() async {
    final session = Supabase.instance.client.auth.currentSession;
    final user = Supabase.instance.client.auth.currentUser;
    if (session == null || user == null) {
      if (mounted) {
        setState(() {
          _profileCompleted = null;
        });
      }
      return;
    }

    final stopwatch = Stopwatch()..start();

    // Warm up presence service immediately in parallel with other services
    PresenceService().init();

    // Reload downloads and local services in parallel so all data is ready
    await Future.wait([
      DownloadService.init(),
      AutoCacheService.init(),
      ListeningHistoryService.init(),
      LikedSongsService.init(),
      PlaylistService().init(),
      ArtistFollowService().init(),
      ProfileFollowService().init(),
      GeneratedHistoryService.init(),
      PremiumService().init(),
    ]);
    PresenceService().init();
    NotificationService().init();

    final prefs = await SharedPreferences.getInstance();
    final cachedCompleted = prefs.getBool(AuthGate._profileCacheKey);

    // If cached as completed already, set it right away so the user is never bounced out
    if (cachedCompleted == true && _profileCompleted != true) {
      if (mounted) {
        setState(() {
          _profileCompleted = true;
        });
      }
    }

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('profile_setup_completed, username, favorite_artists')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));

      if (mounted) {
        final completed = profile?['profile_setup_completed'] == true;
        final hasUsername = profile?['username'] != null &&
            (profile?['username'] as String).isNotEmpty;
        final hasArtists = profile?['favorite_artists'] != null;
        final isFullyCompleted = completed && hasUsername && hasArtists;

        if (isFullyCompleted) {
          await prefs.setBool(AuthGate._profileCacheKey, true);
        } else if (profile != null) {
          // Only invalidate cache if we got a real non-null response confirming it was wiped
          await prefs.remove(AuthGate._profileCacheKey);
        }

        // Balanced ~350ms window: smooth startup while all caches settle nicely
        final elapsed = stopwatch.elapsedMilliseconds;
        if (elapsed < 350) {
          await Future.delayed(Duration(milliseconds: 350 - elapsed));
        }

        if (mounted) {
          setState(() {
            _profileCompleted = isFullyCompleted;
          });
        }
      }
    } catch (e) {
      debugPrint('Profile check error (offline or timeout): $e');
      if (mounted) {
        setState(() {
          // If offline or network error, trust cached status (default to true if user is logged in)
          _profileCompleted = cachedCompleted ?? true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      child = const OnboardingScreen(key: ValueKey('onboarding'));
    } else if (_profileCompleted == null) {
      child = const _MeloSplashScreen(key: ValueKey('splash'));
    } else if (_profileCompleted == false) {
      child = const SetupFlowScreen(key: ValueKey('setup_flow'));
    } else {
      child = const HomeScreen(key: ValueKey('home'));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }
}

class _MeloSplashScreen extends StatelessWidget {
  const _MeloSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF191919),
      body: Center(
        child: Image.asset(
          'asset/Logo/Logo.png',
          width: 140,
          height: 140,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
