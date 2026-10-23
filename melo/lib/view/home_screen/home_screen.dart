import 'dart:io';
import '../../widgets/cached_image.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'custom_bottom_nav_bar.dart';
import '../search_screen/search_overlay.dart';
import '../search_screen/mini_player.dart';
import '../artist_screen/artist_screen.dart';
import '../vibe_screen/vibe_playlist_screen.dart';
import '../library_screen/library_screen.dart';
import '../profile_screen/profile_screen.dart';
import '../../services/playback_service.dart';
import '../../services/home_service.dart';
import '../../services/profile_service.dart';
import '../../services/artist_follow_service.dart';
import '../../services/search_service.dart';
import '../../services/youtube_service.dart';
import '../../services/artist_service.dart';

import '../../widgets/skeleton_loader.dart';
import '../../widgets/now_playing_badge.dart';
import '../../widgets/song_options_modal.dart';
import '../../widgets/fade_page_route.dart';
import '../../services/liked_songs_service.dart';
import '../../services/listening_history_service.dart';
import '../../services/vibe_service.dart';
import '../../services/new_releases_service.dart';
import '../../services/background_prefetch_service.dart';
import '../../services/premium_service.dart';
import '../../services/cookie_service.dart';
import '../generate_screen/generate_screen.dart';
import '../premium_screen/subscription_expiry_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _isSearchActive = false;
  bool _isBuilding = false;
  bool _isGenerateTextMode = false;
  String _greeting = '';
  String _displayName = '';
  String? _avatarUrl;
  bool _isLoading = true;

  Map<String, dynamic>? _homeData;
  List<String> _userGenres = [];
  List<dynamic> _newReleases = [];
  bool _isNewReleasesLoading = true;
  List<dynamic> _favoriteArtists = [];
  List<Map<String, dynamic>> _dailyMixes = [];
  bool _isDailyMixesLoading = true;
  bool _isTrendingLoading = true;
  int _trendingPage = 0;
  final Set<String> _resolvingArtistImages = {};

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Timer? _periodicRefreshTimer;
  Timer? _retryTimer;
  bool _isRetrying = false;
  String _currentCalendarDay =
      DateTime.now().toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfile();
    _loadHomeData();
    _loadNewReleases();
    _loadDailyMixes();
    _loadFollowedArtists();
    _scheduleRetryIfMissing();

    // Start background prefetch for user's library and history as soon as app opens
    LikedSongsService.getLikedSongs().then((songs) {
      BackgroundPrefetchService.instance
          .enqueueTracks(songs, tag: 'liked_songs');
    });
    ListeningHistoryService.getHistory().then((history) {
      BackgroundPrefetchService.instance.enqueueTracks(history, tag: 'history');
    });

    ArtistFollowService().addListener(_onFollowsChanged);
    ProfileService().addListener(_onProfileChanged);
    ListeningHistoryService.onUpdate.addListener(_onHistoryOrTasteUpdated);

    // Periodic live auto-refresh timer: checks every 30 seconds while the app is in foreground
    _periodicRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkAndRefreshStaleContent();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      SubscriptionExpiryDialog.checkAndShow(context);
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _periodicRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    ArtistFollowService().removeListener(_onFollowsChanged);
    ProfileService().removeListener(_onProfileChanged);
    ListeningHistoryService.onUpdate.removeListener(_onHistoryOrTasteUpdated);
    super.dispose();
  }

  bool get _hasMissingContent {
    final trending = (_homeData?['trendingNow'] as List<dynamic>? ?? [])
        .where(_hasValidSongId)
        .toList();
    final discoveries = (_homeData?['newDiscoveries'] as List<dynamic>? ?? [])
        .where(_hasValidSongId)
        .toList();
    return _homeData == null ||
        trending.isEmpty ||
        discoveries.isEmpty ||
        _dailyMixes.isEmpty ||
        _newReleases.isEmpty;
  }

  void _scheduleRetryIfMissing() {
    if (!_hasMissingContent) {
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }
    if (_retryTimer != null && _retryTimer!.isActive) return;

    _retryTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      if (!_hasMissingContent) {
        _retryTimer?.cancel();
        _retryTimer = null;
        return;
      }
      if (_isRetrying) return;
      _isRetrying = true;
      try {
        await _retryMissingSections();
      } finally {
        _isRetrying = false;
      }
    });
  }

  Future<void> _retryMissingSections() async {
    try {
      final lookup = await InternetAddress.lookup('dns.google')
          .timeout(const Duration(seconds: 3));
      if (lookup.isEmpty || lookup[0].rawAddress.isEmpty) return;
    } catch (_) {
      return;
    }

    debugPrint(
        '[HomeScreen] Internet connection detected! Retrying missing content...');

    final List<Future> tasks = [];

    final trending = (_homeData?['trendingNow'] as List<dynamic>? ?? [])
        .where(_hasValidSongId)
        .toList();
    if (_homeData == null || trending.isEmpty) {
      tasks.add(_loadHomeData(force: true));
    } else {
      final discoveries = (_homeData?['newDiscoveries'] as List<dynamic>? ?? [])
          .where(_hasValidSongId)
          .toList();
      if (discoveries.isEmpty) {
        tasks.add(_loadDiscoveriesOnly(force: true));
      }
    }

    if (_dailyMixes.isEmpty) {
      tasks.add(_loadDailyMixes(force: true));
    }

    if (_newReleases.isEmpty) {
      tasks.add(_loadNewReleases(force: true));
    }

    if (tasks.isNotEmpty) {
      await Future.wait(tasks);
    }

    if (mounted && !_hasMissingContent) {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  void _onHistoryOrTasteUpdated() {
    if (mounted) {
      _loadDiscoveriesOnly(force: true);
    }
  }

  void _onProfileChanged() {
    if (mounted) {
      final p = ProfileService();
      setState(() {
        if (p.displayName.isNotEmpty) _displayName = p.displayName;
        if (p.avatarUrl.isNotEmpty) _avatarUrl = p.avatarUrl;
      });
    }
  }

  /// Refreshes greeting and any sections whose daily/12h/30-min window has expired
  /// or which failed to load (empty), live on screen without requiring an app restart.
  Future<void> _checkAndRefreshStaleContent({bool force = false}) async {
    if (!mounted) return;

    // 1. Update live greeting (morning/afternoon/evening/night)
    final currentGreeting = _getGreeting();
    if (_greeting != currentGreeting) {
      setState(() => _greeting = currentGreeting);
    }

    _loadProfile();

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final isNewCalendarDay = _currentCalendarDay != today;
    if (isNewCalendarDay) {
      _currentCalendarDay = today;
    }

    // 2. DAILY SECTIONS: Your Vibe, Daily Mixes, New Releases (rotates after midnight 12:00 AM)
    if (force ||
        isNewCalendarDay ||
        VibeService.dailyMixesStale ||
        _dailyMixes.isEmpty) {
      debugPrint('[HomeScreen] Live midnight / daily refresh triggered');
      _loadDailyMixes(force: true);
      // Re-trigger your vibe genre rotation & prefetch
      if (_userGenres.isNotEmpty) {
        VibeService.preFetch(_userGenres.take(3).toList());
      }
    }

    if (force ||
        isNewCalendarDay ||
        NewReleasesService.isStale ||
        _newReleases.isEmpty) {
      _loadNewReleases(force: true);
    }

    // 3. 30-MINUTE DYNAMIC SECTION: New Discoveries
    final discoveries = (_homeData?['newDiscoveries'] as List<dynamic>? ?? [])
        .where(_hasValidSongId)
        .toList();
    if (force || HomeService.isDiscoveriesStale || discoveries.isEmpty) {
      debugPrint('[HomeScreen] Live 30-min New Discoveries refresh triggered');
      _loadDiscoveriesOnly(force: true);
    }

    // 4. 12-HOUR SECTION: Trending Now
    final trending = (_homeData?['trendingNow'] as List<dynamic>? ?? [])
        .where(_hasValidSongId)
        .toList();
    if (force || HomeService.isStale || trending.isEmpty) {
      _loadHomeData(force: true);
    }
  }

  Future<void> _loadDiscoveriesOnly({bool force = false}) async {
    final discoveries = await HomeService.fetchDiscoveriesOnly(force: force);
    if (mounted && discoveries != null && discoveries.isNotEmpty) {
      setState(() {
        if (_homeData != null) {
          _homeData = {
            ..._homeData!,
            'newDiscoveries': discoveries,
          };
        }
      });
      _prefetchHomeSongs();
    }
  }

  /// On app resume (e.g. user returns from background), automatically check
  /// if a new day or 12h cycle started, or if any content failed, and refresh immediately.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _checkAndRefreshStaleContent(force: _hasMissingContent);
    _scheduleRetryIfMissing();
  }

  void _onFollowsChanged() {
    if (mounted) {
      setState(() {});
      // Force a second rebuild after the current frame to ensure the
      // artists section picks up the latest data from ArtistFollowService.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _loadFollowedArtists() {
    final service = ArtistFollowService();
    if (!service.loaded) {
      service.loadFollowedArtists().then((_) {
        // If artist_follows is empty, migrate from favorite_artists
        if (service.followedArtists.isEmpty && _favoriteArtists.isNotEmpty) {
          _migrateFavoriteArtists();
        }
      });
    }
    service.subscribeToChanges();
  }

  void _migrateFavoriteArtists() {
    final service = ArtistFollowService();
    for (final artist in _favoriteArtists) {
      final id = artist['id']?.toString() ?? '';
      final name = artist['name']?.toString() ?? '';
      final image = artist['image']?.toString() ?? '';
      if (id.isNotEmpty && name.isNotEmpty) {
        service.followArtist(
            artistId: id, artistName: name, artistImage: image);
      }
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    if (hour >= 17 && hour < 21) return 'Good evening';
    return 'Good night';
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();

    // 1) Render the last cached profile immediately so the page never blocks
    //    on the network (critical for offline starts). The network refresh
    //    below then updates the header in the background.
    String cachedName = '';
    String? cachedAvatar;
    List<String> cachedGenres = [];
    List<dynamic> cachedArtists = [];
    try {
      final p = ProfileService();
      cachedName = p.displayName.isNotEmpty
          ? p.displayName
          : (prefs.getString('profile_display_name') ?? '');
      cachedAvatar = p.avatarUrl.isNotEmpty
          ? p.avatarUrl
          : prefs.getString('profile_avatar_url');
      cachedGenres =
          (jsonDecode(prefs.getString('profile_favorite_genres') ?? '[]')
                  as List)
              .map((e) => e.toString())
              .toList();
      cachedArtists =
          jsonDecode(prefs.getString('profile_favorite_artists') ?? '[]')
              as List;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _greeting = _getGreeting();
        _displayName = cachedName;
        _avatarUrl = cachedAvatar;
        _userGenres = cachedGenres;
        _favoriteArtists = cachedArtists;
        _isLoading = false;
      });
    }

    // 2) Refresh from the network in the background. Offline this fails fast
    //    (timeout) and the cached header stays on screen.
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('display_name, avatar_url, favorite_genres, favorite_artists')
          .eq('id', user.id)
          .single()
          .timeout(const Duration(seconds: 8));

      final genres = (profile['favorite_genres'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      final rawArtists = (profile['favorite_artists'] as List<dynamic>?) ?? [];
      final seenNames = <String>{};
      final artists = rawArtists.where((a) {
        final name = (a['name'] ?? '').toString().toLowerCase();
        if (name.isEmpty || seenNames.contains(name)) return false;
        seenNames.add(name);
        return true;
      }).toList();

      // Cache profile locally so the home header renders offline.
      try {
        await prefs.setString(
            'profile_display_name', profile['display_name'] ?? '');
        await prefs.setString(
            'profile_avatar_url', profile['avatar_url'] ?? '');
        await prefs.setString('profile_favorite_genres', jsonEncode(genres));
        await prefs.setString('profile_favorite_artists', jsonEncode(artists));
      } catch (e) {
        debugPrint('Profile cache save error: $e');
      }

      if (mounted) {
        setState(() {
          _greeting = _getGreeting();
          _displayName = profile['display_name'] ?? '';
          _avatarUrl = profile['avatar_url'];
          _userGenres = genres;
          _favoriteArtists = artists;
        });

        // Check if migration is needed after both profile and follows are loaded
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final followService = ArtistFollowService();
          if (followService.loaded &&
              followService.followedArtists.isEmpty &&
              _favoriteArtists.isNotEmpty) {
            _migrateFavoriteArtists();
          }
        });
      }
    } catch (e) {
      debugPrint('Profile load error: $e');
    }
  }

  static bool _hasValidSongId(dynamic item) {
    if (item is! Map<String, dynamic>) return false;
    final rawId = (item['id'] ?? item['trackId'] ?? item['deezerId'] ?? '')
        .toString()
        .trim();
    if (rawId.isEmpty ||
        rawId == '0' ||
        rawId == '-1' ||
        rawId.toLowerCase() == 'null') {
      return false;
    }
    final title = (item['title'] ?? '').toString().trim();
    return title.isNotEmpty;
  }

  Future<void> _loadHomeData({bool force = false}) async {
    if (mounted &&
        (_homeData == null ||
            ((_homeData!['trendingNow'] as List<dynamic>? ?? []).isEmpty))) {
      setState(() => _isTrendingLoading = true);
    }
    try {
      final data = await HomeService.fetchHomeData(force: force);
      if (mounted) {
        Map<String, dynamic>? cleanData = data;
        if (cleanData != null) {
          final trending = (cleanData['trendingNow'] as List<dynamic>? ?? [])
              .where(_hasValidSongId)
              .toList();
          final discoveries =
              (cleanData['newDiscoveries'] as List<dynamic>? ?? [])
                  .where(_hasValidSongId)
                  .toList();
          cleanData = {
            ...cleanData,
            'trendingNow': trending,
            'newDiscoveries': discoveries,
          };
        }
        setState(() {
          _homeData = cleanData;
          _isTrendingLoading = false;
        });
        // Pre-fetch vibe playlists in background
        final vibe = data?['yourVibe'] as Map<String, dynamic>?;
        final genreList = vibe?['genres'] as List<dynamic>? ?? [];
        if (genreList.isNotEmpty) {
          final genres = genreList.take(3).map((e) => e.toString()).toList();
          VibeService.preFetch(genres);
        }
        _prefetchHomeSongs();
      }
    } catch (_) {
      if (mounted) setState(() => _isTrendingLoading = false);
    } finally {
      if (mounted) _scheduleRetryIfMissing();
    }
  }

  Future<void> _loadNewReleases({bool force = false}) async {
    if (mounted && _newReleases.isEmpty) {
      setState(() => _isNewReleasesLoading = true);
    }
    try {
      final songs = await NewReleasesService.fetchNewReleases(force: force);
      if (mounted) {
        setState(() {
          _newReleases = songs.where(_hasValidSongId).toList();
          _isNewReleasesLoading = false;
        });
        _prefetchHomeSongs();
      }
    } catch (_) {
      if (mounted) setState(() => _isNewReleasesLoading = false);
    } finally {
      if (mounted) _scheduleRetryIfMissing();
    }
  }

  Future<void> _loadDailyMixes({bool force = false}) async {
    if (mounted && _dailyMixes.isEmpty) {
      setState(() => _isDailyMixesLoading = true);
    }
    try {
      // Load instantly from cache if available (same day)
      if (!force && await VibeService.hasDailyMixesToday) {
        if (mounted) {
          final cached = VibeService.getDailyMixesFromCache();
          final cleanCached = cached
              .map((mix) {
                final songs = (mix['songs'] as List<dynamic>? ?? [])
                    .where(_hasValidSongId)
                    .toList();
                return {
                  ...mix,
                  'songs': songs,
                };
              })
              .where((m) => (m['songs'] as List).isNotEmpty)
              .toList();

          if (cleanCached.isNotEmpty) {
            setState(() {
              _dailyMixes = cleanCached;
              _isDailyMixesLoading = false;
            });
            _prefetchHomeSongs();
            return;
          }
        }
      }
      // Otherwise fetch from backend
      final mixes = await VibeService.getDailyMixes(force: force);
      if (mounted) {
        final cleanMixes = mixes
            .map((mix) {
              final songs = (mix['songs'] as List<dynamic>? ?? [])
                  .where(_hasValidSongId)
                  .toList();
              return {
                ...mix,
                'songs': songs,
              };
            })
            .where((m) => (m['songs'] as List).isNotEmpty)
            .toList();

        setState(() {
          _dailyMixes = cleanMixes;
          _isDailyMixesLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isDailyMixesLoading = false);
    } finally {
      if (mounted) _scheduleRetryIfMissing();
    }
    _prefetchHomeSongs();
  }

  SearchResult _homeMapToSearchResult(Map<String, dynamic> t) {
    return _toSearchResult(t);
  }

  /// Fire-and-forget: prefetches stream URLs for every song visible on the
  /// home page (trending, new releases, new discoveries, daily mixes) so taps
  /// play instantly without waiting on yt-dlp extraction.
  void _prefetchHomeSongs() {
    final all = <SearchResult>[];

    final trending = _homeData?['trendingNow'] as List<dynamic>? ?? [];
    for (final t in trending) {
      if (t is Map<String, dynamic> && _hasValidSongId(t)) {
        all.add(_homeMapToSearchResult(t));
      }
    }

    final discoveries = _homeData?['newDiscoveries'] as List<dynamic>? ?? [];
    for (final t in discoveries) {
      if (t is Map<String, dynamic> && _hasValidSongId(t)) {
        all.add(_homeMapToSearchResult(t));
      }
    }

    for (final s in _newReleases) {
      if (s is Map<String, dynamic> && _hasValidSongId(s)) {
        all.add(_homeMapToSearchResult(s));
      }
    }

    for (final mix in _dailyMixes) {
      final songs = mix['songs'] as List<dynamic>? ?? [];
      for (final t in songs) {
        if (t is Map<String, dynamic> && _hasValidSongId(t)) {
          all.add(_homeMapToSearchResult(t));
        }
      }
    }

    if (all.isNotEmpty) {
      YouTubeService.prefetchStreamUrls(all);
      BackgroundPrefetchService.instance.enqueueTracks(all, tag: 'home_screen');
    }
  }

  Widget _buildAvatar() {
    const double size = 44;

    if (_avatarUrl != null && _avatarUrl!.startsWith('http')) {
      return ClipOval(
        child: CachedImage(
          _avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultAvatar(),
        ),
      );
    }

    if (_avatarUrl != null && _avatarUrl!.startsWith('asset/')) {
      return ClipOval(
        child: Image.asset(
          _avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultAvatar(),
        ),
      );
    }

    return _buildDefaultAvatar();
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF2A2A2A),
      ),
      child: const Icon(Icons.person, color: Colors.white38, size: 24),
    );
  }

  Widget _buildPageContent() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOutCubic,
        );
        final scale = Tween<double>(begin: 0.985, end: 1.0).animate(fade);

        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            child: child,
          ),
        );
      },
      child: _buildCurrentPage(),
    );
  }

  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case 0:
        return ColoredBox(
          key: const ValueKey('home'),
          color: const Color(0xFF191919),
          child: _buildHomeContent(),
        );
      case 1:
        return ColoredBox(
          key: const ValueKey('generate'),
          color: const Color(0xFF191919),
          child: GenerateScreen(
            onBuildingChanged: (building) {
              if (mounted) setState(() => _isBuilding = building);
            },
            onIsTextModeChanged: (isTextMode) {
              if (mounted) setState(() => _isGenerateTextMode = isTextMode);
            },
          ),
        );
      case 2:
        return const ColoredBox(
          key: ValueKey('library'),
          color: Color(0xFF191919),
          child: LibraryScreen(),
        );
      default:
        return ColoredBox(
          key: const ValueKey('home'),
          color: const Color(0xFF191919),
          child: _buildHomeContent(),
        );
    }
  }

  Widget _buildHomeContent() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 56),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _greeting,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 15,
                                fontFamily: 'Poppins',
                              ),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              ',',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [
                              Color(0xFF514AED),
                              Color(0xFFFFFFFF),
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ).createShader(bounds),
                          child: Text(
                            _displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context, rootNavigator: true).push(
                          FadePageRoute(page: const ProfileScreen()),
                        );
                      },
                      child: _buildAvatar(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: _buildYourVibeSection()),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
        SliverToBoxAdapter(child: _buildSectionHeader('New Releases', () {})),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(child: _buildNewlyReleasedSection()),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
        SliverToBoxAdapter(child: _buildSectionHeader('Trending now', () {})),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(child: _buildTrendingSection()),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
        SliverToBoxAdapter(child: _buildSectionHeader('Your Artists', () {})),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(child: _buildYourArtistsSection()),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
        SliverToBoxAdapter(child: _buildSectionHeader('Daily Mixes', () {})),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(child: _buildDailyMixesSection()),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
        SliverToBoxAdapter(
            child: _buildSectionHeader('New Discoveries', () {})),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(child: _buildNewDiscoveriesSection()),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _buildSectionHeader(String title, VoidCallback onSeeAll) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }

  // ===== SECTION 1: YOUR VIBE =====
  Widget _buildYourVibeSection() {
    final genreList = _userGenres.isNotEmpty
        ? _userGenres
        : (_homeData?['yourVibe'] as Map<String, dynamic>?)?['genres']
                as List<dynamic>? ??
            [];
    final songCount = (_homeData?['yourVibe']
            as Map<String, dynamic>?)?['songCount'] as int? ??
        20;

    // Rotate genres daily so the featured vibe changes each morning
    final dayOffset =
        DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays;
    final rotatedGenres = <String>[];
    if (genreList.isNotEmpty) {
      for (var i = 0; i < genreList.length; i++) {
        final idx = (i + dayOffset) % genreList.length;
        rotatedGenres.add(genreList[idx].toString());
      }
    } else {
      rotatedGenres.addAll(['Pop', 'Hip Hop', 'R&B']);
    }

    final displayGenres = rotatedGenres.length >= 3
        ? rotatedGenres.sublist(0, 3)
        : rotatedGenres.length >= 2
            ? rotatedGenres.sublist(0, 2)
            : [rotatedGenres.first];

    final cardData = [
      {
        'genre': displayGenres.isNotEmpty ? displayGenres[0] : 'Hip Hop',
        'color': const Color(0xFFFED67D),
        'asset': 'asset/YourVibe_assets/tinywow_image 98_90577001 1.png',
        'isLarge': false,
      },
      {
        'genre': displayGenres.length > 1 ? displayGenres[1] : 'Rock',
        'color': const Color(0xFF9054DC),
        'asset': 'asset/YourVibe_assets/Gold 3.png',
        'isLarge': false,
      },
      {
        'genre': displayGenres.length > 2 ? displayGenres[2] : 'Pop',
        'color': const Color(0xFF04A1FD),
        'asset': 'asset/YourVibe_assets/Mask group(2).png',
        'isLarge': true,
      },
    ];

    final startIndex = 1000 - (1000 % cardData.length) + 1;

    return SizedBox(
      height: 220,
      child: PageView.builder(
        controller:
            PageController(initialPage: startIndex, viewportFraction: 0.88),
        itemCount: null,
        itemBuilder: (context, index) {
          final card = cardData[index % cardData.length];
          return _buildVibeCard(
            genre: card['genre'] as String,
            songCount: songCount,
            bgColor: card['color'] as Color,
            assetPath: card['asset'] as String,
            isLargeImage: card['isLarge'] as bool,
          );
        },
      ),
    );
  }

  Widget _buildVibeCard({
    required String genre,
    required int songCount,
    required Color bgColor,
    required String assetPath,
    required bool isLargeImage,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        // Image width scales dynamically to never crowd the text column
        final imageWidth = isLargeImage
            ? (cardWidth * 0.62).clamp(190.0, 245.0)
            : (cardWidth * 0.48).clamp(120.0, 175.0);
        final textRightPadding = isLargeImage
            ? (cardWidth * 0.46).clamp(135.0, 170.0)
            : imageWidth * 0.82;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => _playVibePlaylist(genre, bgColor),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: bgColor.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // Vinyl / Artwork Image anchored flush to the bottom-right
                  Positioned(
                    right: isLargeImage ? 0 : 6,
                    top: isLargeImage ? 0 : 20,
                    bottom: 0,
                    width: imageWidth,
                    child: Image.asset(
                      assetPath,
                      fit: isLargeImage ? BoxFit.cover : BoxFit.contain,
                      alignment: isLargeImage
                          ? Alignment.centerRight
                          : Alignment.bottomRight,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                  ),
                  // Left Content Column with dedicated safe bounded space
                  Positioned(
                    left: 22,
                    top: 16,
                    bottom: 16,
                    right: textRightPadding,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$genre for you',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                            height: 1.15,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '$songCount songs',
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.6),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        const SizedBox(height: 14),
                        GestureDetector(
                          onTap: () => _startListeningVibe(genre, bgColor),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Listen Now',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Poppins',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _startListeningVibe(String genre, Color cardColor) async {
    // 1. Check if we have this mix cached or in _dailyMixes
    List<Map<String, dynamic>> tracks = [];
    final match = _dailyMixes
        .where((m) =>
            (m['genre'] ?? '').toString().toLowerCase() == genre.toLowerCase())
        .firstOrNull;
    if (match != null && match['songs'] != null) {
      final songsList = match['songs'] as List<dynamic>;
      tracks =
          songsList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      tracks = await VibeService.getPlaylist(genre);
    }

    final validTracks = tracks.where(_hasValidSongId).toList();

    if (validTracks.isEmpty) {
      if (mounted) _playVibePlaylist(genre, cardColor);
      return;
    }

    // Convert tracks to SearchResult queue
    final queue = validTracks.map(_toSearchResult).toList();

    final playback = PlaybackService();
    playback.setQueue(queue, 0);
    playback.playTrack(queue.first, fromQueue: true);

    CookieService.show(
      message: 'Playing $genre for you',
      icon: Icons.play_arrow_rounded,
    );
  }

  Future<void> _playVibePlaylist(String genre, Color cardColor) async {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondaryAnimation) =>
            VibePlaylistScreen(
          genre: genre,
          cardColor: cardColor,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fade =
              CurvedAnimation(parent: animation, curve: Curves.easeOut);
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
      ),
    );
  }

  // ===== SECTION 2: NEW RELEASES =====
  Widget _buildNewlyReleasedSection() {
    if (_isNewReleasesLoading) {
      return SizedBox(
        height: 200,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: 5,
          itemBuilder: (_, __) => const SkeletonNewReleaseCard(),
        ),
      );
    }

    final validReleases = _newReleases
        .where((item) => item is Map<String, dynamic> && _hasValidSongId(item))
        .map((item) => item as Map<String, dynamic>)
        .toList();

    if (validReleases.isEmpty) {
      return SizedBox(
        height: 90,
        child: Center(
          child: GestureDetector(
            onTap: () {
              setState(() => _isNewReleasesLoading = true);
              _loadNewReleases(force: true);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded,
                      color: Color(0xFF817BFF), size: 16),
                  SizedBox(width: 8),
                  Text(
                    'No new releases • Tap to retry',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: validReleases.length,
        itemBuilder: (context, index) {
          final song = validReleases[index];
          final image = song['image'] as String? ?? '';
          final title = song['title'] as String? ?? '';
          final artist = song['artist'] as String? ?? '';
          final track = _toSearchResult(song);

          return GestureDetector(
            onTap: () {
              if (!PremiumService().checkAndConsumeTrackSwitch(
                context,
                newTitle: track.title,
                newArtist: track.artist,
                newId: track.id,
              )) {
                return;
              }
              PlaybackService().playTrack(track);
            },
            onLongPress: () => SongOptionsModal.show(context, track),
            child: Container(
              width: 150,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedImage(
                          image,
                          width: 150,
                          height: 150,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 150,
                            height: 150,
                            color: const Color(0xFF2A2A2A),
                            child: const Icon(Icons.music_note,
                                color: Colors.white38, size: 40),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF514AED),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'NEW',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Poppins'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    artist,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontFamily: 'Poppins'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

// ===== SECTION 3: TRENDING NOW =====
  Widget _buildTrendingSection() {
    if (_homeData == null || _isTrendingLoading) {
      return Column(
        children: [
          for (var i = 0; i < 5; i++) const SkeletonTrendingRow(),
        ],
      );
    }

    final rawTracks = _homeData?['trendingNow'] as List<dynamic>? ?? [];
    final tracks = rawTracks
        .where((t) => t is Map<String, dynamic> && _hasValidSongId(t))
        .toList();

    if (tracks.isEmpty) {
      return SizedBox(
        height: 90,
        child: Center(
          child: GestureDetector(
            onTap: () {
              setState(() => _isTrendingLoading = true);
              _loadHomeData(force: true);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded,
                      color: Color(0xFF817BFF), size: 16),
                  SizedBox(width: 8),
                  Text(
                    'No trending tracks • Tap to retry',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // One card of 5 per page: 1-5, 6-10, 11-15, 16-20.
    final pageCount = (tracks.length / 5).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 48 * 5 + 16 * 5,
          child: PageView.builder(
            onPageChanged: (index) => setState(() => _trendingPage = index),
            itemCount: pageCount,
            itemBuilder: (context, page) {
              final start = page * 5;
              final end = (start + 5).clamp(0, tracks.length);
              final pageTracks = tracks.sublist(start, end);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    for (var i = 0; i < pageTracks.length; i++)
                      _buildTrendingRow(pageTracks[i] as Map<String, dynamic>,
                          position: start + i + 1),
                  ],
                ),
              );
            },
          ),
        ),
        // Page indicator dots, centered at the bottom.
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var page = 0; page < pageCount; page++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Container(
                    width: page == _trendingPage ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: page == _trendingPage
                          ? const Color(0xFF514AED)
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  SearchResult _toSearchResult(Map<String, dynamic> track) {
    final rawId = (track['id'] ?? track['trackId'] ?? track['deezerId'] ?? '')
        .toString()
        .trim();
    return SearchResult(
      type: 'song',
      id: rawId,
      title: track['title'] as String? ?? '',
      artist: track['artist'] as String? ?? '',
      artistId: track['artistId'] as String? ?? '',
      artistImage: track['artistImage'] as String? ?? '',
      image: track['image'] as String? ?? '',
      duration: track['duration'] as String? ?? '',
      nbFan: 0,
      previewUrl:
          track['preview'] as String? ?? track['previewUrl'] as String? ?? '',
    );
  }

  Widget _buildTrendingRow(Map<String, dynamic> track,
      {required int position}) {
    final title = track['title'] as String? ?? '';
    final artist = track['artist'] as String? ?? '';
    final image = track['image'] as String? ?? '';
    final searchResult = _toSearchResult(track);

    return TrackHighlight(
      trackId: searchResult.id,
      title: title,
      artist: artist,
      builder: (context, isCurrent) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _playTrendingTrack(track),
            onLongPress: () => SongOptionsModal.show(context, searchResult),
            splashColor: Colors.white.withValues(alpha: 0.08),
            highlightColor: Colors.white.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: isCurrent
                        ? NowPlayingBars(playing: PlaybackService().isPlaying)
                        : Text(
                            '$position',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Poppins'),
                            textAlign: TextAlign.center,
                          ),
                  ),
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedImage(
                      image,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 48,
                        height: 48,
                        color: const Color(0xFF2A2A2A),
                        child: const Icon(Icons.music_note,
                            color: Colors.white38, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: isCurrent
                                ? const Color(0xFF514AED)
                                : Colors.white,
                            fontSize: 14,
                            fontWeight:
                                isCurrent ? FontWeight.w600 : FontWeight.w500,
                            fontFamily: 'Poppins',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          artist,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                              fontFamily: 'Poppins'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => SongOptionsModal.show(context, searchResult),
                    child: Container(
                      alignment: Alignment.centerRight,
                      padding:
                          const EdgeInsets.only(left: 8, top: 4, bottom: 4),
                      child: const Icon(
                        Icons.more_horiz_rounded,
                        color: Colors.white54,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _playTrendingTrack(Map<String, dynamic> track) async {
    if (!_hasValidSongId(track)) return;
    final result = _toSearchResult(track);
    final playback = PlaybackService();
    final rawSongs = (_homeData?['trendingNow'] as List<dynamic>? ?? []);
    final songs = rawSongs
        .where((t) => t is Map<String, dynamic> && _hasValidSongId(t))
        .map((t) => _toSearchResult(t as Map<String, dynamic>))
        .toList();
    if (!PremiumService().checkAndConsumeTrackSwitch(
      context,
      newTitle: result.title,
      newArtist: result.artist,
      newId: result.id,
    )) {
      return;
    }
    final idx = songs.indexWhere((s) => s.id == result.id);
    playback.setQueue(songs, idx >= 0 ? idx : 0);
    playback.playTrack(result, fromQueue: idx >= 0);
  }

  // ===== SECTION 4: YOUR ARTISTS =====
  Widget _buildYourArtistsSection() {
    var followedArtists = ArtistFollowService().followedArtists;

    // Fallback: if artist_follows is empty, use favorite_artists from profile
    if (followedArtists.isEmpty && _favoriteArtists.isNotEmpty) {
      followedArtists = _favoriteArtists
          .map((a) => {
                'artist_id': a['id']?.toString() ?? '',
                'artist_name': a['name']?.toString() ?? '',
                'artist_image': a['image']?.toString() ?? '',
              })
          .toList();
    }

    if (!_isLoading &&
        !ArtistFollowService().loaded &&
        _favoriteArtists.isEmpty) {
      return SizedBox(
        height: 140,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: 5,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, __) => const SkeletonArtistCard(),
        ),
      );
    }

    if (!_isLoading && followedArtists.isEmpty) {
      return const SizedBox(
        height: 140,
        child: Center(
            child: Text('No artists',
                style:
                    TextStyle(color: Colors.white38, fontFamily: 'Poppins'))),
      );
    }

    final artists = followedArtists;

    return SizedBox(
      height: 140,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: artists.length,
        itemBuilder: (context, index) {
          final artist = artists[index];
          final name = artist['artist_name'] as String? ?? '';
          final image = artist['artist_image'] as String? ?? '';
          final artistId = artist['artist_id']?.toString() ?? '';

          if (image.isEmpty && artistId.isNotEmpty) {
            _resolveMissingArtistImage(artistId, name);
          }

          final itemKey =
              'home_artist_${artistId.isNotEmpty ? artistId : name}_$index';

          return GestureDetector(
            key: ValueKey(itemKey),
            onTap: () {
              if (artistId.isNotEmpty) {
                Navigator.of(context, rootNavigator: true).push(
                  FadePageRoute(
                    page: ArtistScreen(
                      artistId: artistId,
                      artistName: name,
                      artistImage: image,
                      nbFan: 0,
                    ),
                  ),
                );
              }
            },
            child: Container(
              width: 90,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                children: [
                  ClipOval(
                    child: CachedImage(
                      image,
                      key: ValueKey(
                          'cached_artist_${artistId.isNotEmpty ? artistId : name}_$image'),
                      width: 85,
                      height: 85,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 85,
                        height: 85,
                        color: const Color(0xFF2A2A2A),
                        child: const Icon(Icons.person,
                            color: Colors.white38, size: 32),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontFamily: 'Poppins'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _resolveMissingArtistImage(String artistId, String artistName) {
    if (artistId.isEmpty || _resolvingArtistImages.contains(artistId)) return;
    _resolvingArtistImages.add(artistId);
    ArtistService.getArtistInfo(artistId).then((info) {
      if (!mounted) return;
      final pic = (info?['picture_big'] ??
                  info?['picture_medium'] ??
                  info?['picture'] ??
                  '')
              ?.toString() ??
          '';
      if (pic.isNotEmpty) {
        ArtistFollowService().updateArtistImage(artistId, pic);
        if (mounted) setState(() {});
      }
    }).catchError((_) {});
  }

  // ===== SECTION 5: DAILY MIXES =====
  Widget _buildDailyMixesSection() {
    const primaryPurple = Color(0xFF514AED);
    const purpleGradient = [Color(0xFF635BFF), Color(0xFF514AED)];

    if (_dailyMixes.isEmpty && !_isDailyMixesLoading) {
      return SizedBox(
        height: 90,
        child: Center(
          child: GestureDetector(
            onTap: () {
              setState(() => _isDailyMixesLoading = true);
              _loadDailyMixes(force: true);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded,
                      color: Color(0xFF817BFF), size: 16),
                  SizedBox(width: 8),
                  Text(
                    'No daily mixes yet • Tap to retry',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final count = _isDailyMixesLoading ? 3 : _dailyMixes.length;

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: count,
        itemBuilder: (context, index) {
          final number = index + 1;

          if (_isDailyMixesLoading) {
            return Container(
              width: 260,
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF16161E),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF22222D),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 50,
                            height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFF22222D),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 90,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFF22222D),
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 70,
                            height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFF22222D),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final mix = _dailyMixes[index];
          final rawSongs = mix['songs'] as List<dynamic>? ?? [];
          final songs = rawSongs
              .where((s) => s is Map<String, dynamic> && _hasValidSongId(s))
              .map((s) => s as Map<String, dynamic>)
              .toList();
          final songCount = songs.length;

          final coverImages = <String>[];
          for (final s in songs) {
            final img = s['image'] as String? ?? '';
            if (img.isNotEmpty && !coverImages.contains(img)) {
              coverImages.add(img);
              if (coverImages.length >= 2) break;
            }
          }

          final topArtists = <String>[];
          for (final s in songs) {
            final art = s['artist'] as String? ?? '';
            if (art.isNotEmpty && !topArtists.contains(art)) {
              topArtists.add(art);
              if (topArtists.length >= 2) break;
            }
          }

          final mainCover = coverImages.isNotEmpty ? coverImages.first : '';
          final songTrackIds = songs
              .map((s) => _toSearchResult(s).id)
              .where((id) => id.isNotEmpty)
              .toSet();
          final songTitles = songs
              .map((s) => (s['title']?.toString() ?? '').toLowerCase().trim())
              .where((t) => t.isNotEmpty)
              .toSet();

          return ListenableBuilder(
            listenable: PlaybackService(),
            builder: (context, _) {
              final playback = PlaybackService();
              final current = playback.currentTrack;
              final isPlayingMix = current != null &&
                  playback.isPlaying &&
                  (songTrackIds.contains(current.id) ||
                      songTitles.contains(current.title.toLowerCase().trim()));

              return GestureDetector(
                onTap: () => _playDailyMix(mix),
                child: Container(
                  width: 260,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14141B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isPlayingMix
                          ? primaryPurple.withValues(alpha: 0.6)
                          : primaryPurple.withValues(alpha: 0.22),
                      width: isPlayingMix ? 1.4 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isPlayingMix
                            ? primaryPurple.withValues(alpha: 0.2)
                            : Colors.black.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      // Ambient Purple Glow in Corner
                      Positioned(
                        top: -30,
                        right: -30,
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                primaryPurple.withValues(
                                    alpha: isPlayingMix ? 0.35 : 0.2),
                                primaryPurple.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Compact Vinyl Record with Album Art Center Label
                            Container(
                              width: 82,
                              height: 82,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF0C0C10),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                  BoxShadow(
                                    color: primaryPurple.withValues(
                                        alpha: isPlayingMix ? 0.3 : 0.15),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Grooves ring
                                  Container(
                                    width: 70,
                                    height: 70,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.05),
                                        width: 1.0,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 58,
                                    height: 58,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.05),
                                        width: 1.0,
                                      ),
                                    ),
                                  ),
                                  // Circular Album Art Center Sticker
                                  ClipOval(
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF22222E),
                                      ),
                                      child: mainCover.isNotEmpty
                                          ? CachedImage(
                                              mainCover,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                decoration: const BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: purpleGradient,
                                                  ),
                                                ),
                                                child: const Icon(
                                                    Icons.music_note,
                                                    color: Colors.white,
                                                    size: 20),
                                              ),
                                            )
                                          : Container(
                                              decoration: const BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: purpleGradient,
                                                ),
                                              ),
                                              child: const Icon(
                                                  Icons.album_rounded,
                                                  color: Colors.white,
                                                  size: 22),
                                            ),
                                    ),
                                  ),
                                  // Spindle Hole
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF0C0C10),
                                      border: Border.all(
                                        color:
                                            Colors.white.withValues(alpha: 0.4),
                                        width: 1.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            // Mix Title, Artists & Status
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isPlayingMix
                                              ? primaryPurple.withValues(
                                                  alpha: 0.25)
                                              : primaryPurple.withValues(
                                                  alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color: isPlayingMix
                                                ? primaryPurple.withValues(
                                                    alpha: 0.7)
                                                : primaryPurple.withValues(
                                                    alpha: 0.4),
                                            width: 0.7,
                                          ),
                                        ),
                                        child: Text(
                                          'DAILY MIX $number',
                                          style: TextStyle(
                                            color: isPlayingMix
                                                ? Colors.white
                                                : const Color(0xFFA5A0FF),
                                            fontSize: 8,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.5,
                                            fontFamily: 'Poppins',
                                          ),
                                        ),
                                      ),
                                      if (isPlayingMix) ...[
                                        const SizedBox(width: 6),
                                        const NowPlayingBars(
                                          playing: true,
                                          color: Color(0xFFA5A0FF),
                                          barWidth: 2.0,
                                          bars: 3,
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    mix['name'] as String? ??
                                        'Daily Mix $number',
                                    style: TextStyle(
                                      color: isPlayingMix
                                          ? const Color(0xFFA5A0FF)
                                          : Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Poppins',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    topArtists.isNotEmpty
                                        ? topArtists.join(', ')
                                        : (mix['description'] as String? ??
                                            '$songCount Tracks'),
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.5),
                                      fontSize: 10.5,
                                      fontFamily: 'Poppins',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _playDailyMix(Map<String, dynamic> mix) async {
    final songs = (mix['songs'] as List<dynamic>? ?? []);
    final name = mix['name'] as String? ?? 'Daily Mix';
    final number = mix['number'] as int? ?? 1;

    final validSongs = songs
        .where((t) => t is Map<String, dynamic> && _hasValidSongId(t))
        .map((t) => Map<String, dynamic>.from(t as Map))
        .toList();

    if (validSongs.isEmpty) return;

    final purpleVariants = [
      const Color(0xFF514AED),
      const Color(0xFF635BFF),
      const Color(0xFF4338CA),
      const Color(0xFF7C3AED),
      const Color(0xFF4F46E5),
      const Color(0xFF581C87),
    ];

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondaryAnimation) =>
            VibePlaylistScreen(
          genre: 'Daily Mix',
          cardColor: purpleVariants[(number - 1) % purpleVariants.length],
          initialTracks: validSongs,
          playlistName: name,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fade =
              CurvedAnimation(parent: animation, curve: Curves.easeOut);
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
      ),
    );
  }

  // ===== SECTION 6: NEW DISCOVERIES =====
  Widget _buildNewDiscoveriesSection() {
    // Show skeleton while loading
    if (_isLoading || _homeData == null) {
      return const SkeletonHomeSection();
    }

    final rawTracks = _homeData?['newDiscoveries'] as List<dynamic>? ?? [];
    final tracks = rawTracks
        .where((t) => t is Map<String, dynamic> && _hasValidSongId(t))
        .map((t) => t as Map<String, dynamic>)
        .toList();

    if (tracks.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
            child: Text('No discoveries yet',
                style:
                    TextStyle(color: Colors.white38, fontFamily: 'Poppins'))),
      );
    }

    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          final image = track['image'] as String? ?? '';
          final title = track['title'] as String? ?? '';
          final artist = track['artist'] as String? ?? '';
          final searchResult = _toSearchResult(track);

          return TrackHighlight(
            trackId: searchResult.id,
            title: title,
            artist: artist,
            builder: (context, isCurrent) {
              return GestureDetector(
                onTap: () => _playDiscoveryTrack(track, tracks),
                onLongPress: () => SongOptionsModal.show(context, searchResult),
                child: Container(
                  width: 140,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedImage(
                          image,
                          width: 140,
                          height: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 140,
                            height: 140,
                            color: const Color(0xFF2A2A2A),
                            child: const Icon(Icons.music_note,
                                color: Colors.white38, size: 40),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        style: TextStyle(
                          color: isCurrent
                              ? const Color(0xFF514AED)
                              : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        artist,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                            fontFamily: 'Poppins'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _playDiscoveryTrack(
      Map<String, dynamic> track, List<dynamic> allTracks) async {
    if (!_hasValidSongId(track)) return;
    final validTracks = allTracks
        .where((t) => t is Map<String, dynamic> && _hasValidSongId(t))
        .map((t) => _toSearchResult(t as Map<String, dynamic>))
        .toList();
    if (validTracks.isEmpty) return;

    final targetResult = _toSearchResult(track);
    final result = validTracks.firstWhere(
      (s) => s.id == targetResult.id,
      orElse: () => validTracks.first,
    );

    if (!PremiumService().checkAndConsumeTrackSwitch(
      context,
      newTitle: result.title,
      newArtist: result.artist,
      newId: result.id,
    )) {
      return;
    }

    final playback = PlaybackService();
    final idx = validTracks.indexWhere((s) => s.id == result.id);
    playback.setQueue(validTracks, idx >= 0 ? idx : 0);
    playback.playTrack(result, fromQueue: idx >= 0);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF191919),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ShimmerSkeleton(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 120, height: 14, color: Colors.white),
                        const SizedBox(height: 8),
                        Container(width: 200, height: 24, color: Colors.white),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: SkeletonVibeCard(width: double.infinity, height: 180),
                ),
                const SizedBox(height: 30),
                const SkeletonHomeSection(),
                const SizedBox(height: 30),
                const SkeletonHomeSection(),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF191919),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          _buildPageContent(),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !_isSearchActive,
              child: AnimatedOpacity(
                opacity: _isSearchActive ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: SearchOverlay(
                  searchController: _searchController,
                  searchFocusNode: _searchFocusNode,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            // Generate text mode provides its own keyboard-aware input. Keep
            // the shared mini player beneath that keyboard only when in text mode and not searching.
            // In voice mode, search page, and other tabs, it pushes up with the keyboard.
            bottom: 66 +
                ((_currentIndex == 1 && _isGenerateTextMode && !_isSearchActive)
                    ? 0.0
                    : MediaQuery.of(context).viewInsets.bottom),
            child: ListenableBuilder(
              listenable: PlaybackService(),
              builder: (context, _) {
                final playback = PlaybackService();
                final show =
                    playback.isVisible && playback.currentTrack != null;
                if (show) return const MiniPlayer();
                return const SizedBox.shrink();
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            // Only suppress the navbar lift when strictly in Generate Text mode and not searching.
            bottom:
                ((_currentIndex == 1 && _isGenerateTextMode && !_isSearchActive)
                        ? 0.0
                        : MediaQuery.of(context).viewInsets.bottom) +
                    10,
            child: _isBuilding
                ? const SizedBox.shrink()
                : CustomBottomNavBar(
                    currentIndex: _currentIndex,
                    isSearchActive: _isSearchActive,
                    searchController: _searchController,
                    searchFocusNode: _searchFocusNode,
                    onTap: (index) {
                      setState(() {
                        _currentIndex = index;
                        _isSearchActive = false;
                      });
                    },
                    onSearchTap: () {
                      setState(() => _isSearchActive = true);
                    },
                    onSearchClose: () {
                      setState(() {
                        _isSearchActive = false;
                        _searchController.clear();
                      });
                      // Start the nav-bar morph in this frame, while the
                      // keyboard is independently animating away.
                      _searchFocusNode.unfocus();
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
