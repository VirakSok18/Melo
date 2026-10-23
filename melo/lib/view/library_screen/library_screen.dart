import '../../widgets/cached_image.dart';
import 'package:flutter/material.dart';
import '../../services/liked_songs_service.dart';
import '../../services/listening_history_service.dart';
import '../../services/download_service.dart';
import '../../services/playback_service.dart';
import '../../services/search_service.dart';
import '../../services/playlist_service.dart';
import '../../services/background_prefetch_service.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/now_playing_badge.dart';
import 'liked_songs_screen.dart';
import 'downloaded_songs_screen.dart';
import 'recently_played_screen.dart';
import 'playlists_screen.dart';
import 'playlist_detail_screen.dart';
import 'collabs_screen.dart';
import 'playlist_invites_modal.dart';
import '../friends_screen/friends_screen.dart';
import '../../services/profile_follow_service.dart';
import '../../services/presence_service.dart';
import '../../services/premium_service.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _isLoading = true;
  bool _playlistsLoaded = false;
  bool _recentLoaded = false;
  int _likedCount = 0;
  int _recentCount = 0;
  int _downloadedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCounts();
    ListeningHistoryService.onUpdate.addListener(_onUpdate);
    LikedSongsService.onUpdate.addListener(_onUpdate);
    LikedSongsService().addListener(_onUpdate);
    DownloadService.onUpdate.addListener(_onUpdate);
    PlaybackService().addListener(_onUpdate);
    ProfileFollowService().addListener(_onUpdate);
    PresenceService().addListener(_onUpdate);
    PlaylistService().addListener(_onUpdate);
    PlaylistService().onUpdate.addListener(_onUpdate);
  }

  @override
  void dispose() {
    ListeningHistoryService.onUpdate.removeListener(_onUpdate);
    LikedSongsService.onUpdate.removeListener(_onUpdate);
    LikedSongsService().removeListener(_onUpdate);
    DownloadService.onUpdate.removeListener(_onUpdate);
    PlaybackService().removeListener(_onUpdate);
    ProfileFollowService().removeListener(_onUpdate);
    PresenceService().removeListener(_onUpdate);
    PlaylistService().removeListener(_onUpdate);
    PlaylistService().onUpdate.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) {
      setState(() {
        _likedCount = LikedSongsService.count;
        _downloadedCount = DownloadService.count;
        _recentCount = _getRecentCountForCurrentTimeOfDay();
      });
    }
  }

  Future<void> _loadCounts() async {
    // Read cached counts instantly
    if (mounted) {
      setState(() {
        _likedCount = LikedSongsService.count;
        _downloadedCount = DownloadService.count;
        _recentCount = _getRecentCountForCurrentTimeOfDay();
        _isLoading = false;
        _playlistsLoaded = PlaylistService().loaded;
        _recentLoaded = ListeningHistoryService.cachedHistory.isNotEmpty;
      });
    }
    // Load playlists and follow notifications
    PlaylistService().loadPlaylists().then((_) {
      if (mounted) setState(() => _playlistsLoaded = true);
    });
    ProfileFollowService().loadFollowData();
    // If cache was empty, fetch in background and update
    if (_likedCount == 0 || _recentCount == 0) {
      await Future.wait([
        LikedSongsService.getLikedSongs(),
        ListeningHistoryService.getHistory(),
        DownloadService.getDownloadedSongs(),
      ]);
      if (mounted) {
        setState(() {
          _likedCount = LikedSongsService.count;
          _downloadedCount = DownloadService.count;
          _recentCount = _getRecentCountForCurrentTimeOfDay();
          _recentLoaded = true;
        });
      }
    }

    // Slowly prefetch liked and recently played songs in background
    BackgroundPrefetchService.instance
        .enqueueTracks(LikedSongsService.cachedSongs, tag: 'library_liked');
    BackgroundPrefetchService.instance.enqueueTracks(
        ListeningHistoryService.cachedHistory,
        tag: 'library_history');
  }

  int _getRecentCountForCurrentTimeOfDay() {
    final history = ListeningHistoryService.cachedHistory;
    final now = DateTime.now();
    final hour = now.hour;

    String timeOfDay;
    if (hour >= 5 && hour < 12) {
      timeOfDay = 'Morning';
    } else if (hour >= 12 && hour < 17) {
      timeOfDay = 'Afternoon';
    } else if (hour >= 17 && hour < 21) {
      timeOfDay = 'Evening';
    } else {
      timeOfDay = 'Night';
    }

    final today = DateTime(now.year, now.month, now.day);
    int count = 0;
    final seen = <String>{};

    for (final song in history) {
      final title = song['title'] as String? ?? '';
      final artist = song['artist'] as String? ?? '';
      final key = '$title|$artist';

      final createdAt = song['created_at'] as String? ?? '';
      if (createdAt.isEmpty) continue;
      final date = DateTime.tryParse(createdAt);
      if (date == null) continue;
      final localDate = date.isUtc ? date.toLocal() : date;
      final localToday =
          DateTime(localDate.year, localDate.month, localDate.day);
      if (localToday.isBefore(today)) continue;

      final songHour = localDate.hour;
      String songTime;
      if (songHour >= 5 && songHour < 12) {
        songTime = 'Morning';
      } else if (songHour >= 12 && songHour < 17) {
        songTime = 'Afternoon';
      } else if (songHour >= 17 && songHour < 21) {
        songTime = 'Evening';
      } else {
        songTime = 'Night';
      }

      if (songTime == timeOfDay) {
        count++;
        seen.add(key);
      }
    }

    // Also count the currently playing track if it's not already counted
    final current = PlaybackService().currentTrack;
    if (current != null) {
      final key = '${current.title}|${current.artist}';
      if (!seen.contains(key)) {
        final songHour = now.hour;
        String songTime;
        if (songHour >= 5 && songHour < 12) {
          songTime = 'Morning';
        } else if (songHour >= 12 && songHour < 17) {
          songTime = 'Afternoon';
        } else if (songHour >= 17 && songHour < 21) {
          songTime = 'Evening';
        } else {
          songTime = 'Night';
        }
        if (songTime == timeOfDay) count++;
      }
    }

    return count;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setState(() {
      _likedCount = LikedSongsService.count;
      _recentCount = _getRecentCountForCurrentTimeOfDay();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF191919),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF514AED)),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Library',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        ListenableBuilder(
                          listenable: Listenable.merge([
                            PlaylistService().onUpdate,
                            ProfileFollowService(),
                          ]),
                          builder: (context, _) {
                            final unreadInvitesCount =
                                PlaylistService().unreadInvitesCount;
                            final unreadFollowersCount = ProfileFollowService()
                                .unreadFollowerNotificationsCount;
                            final hasNotifications = unreadInvitesCount > 0 ||
                                unreadFollowersCount > 0;
                            return GestureDetector(
                              onTap: () async {
                                await Future.wait([
                                  ProfileFollowService().markFollowersAsSeen(),
                                  PlaylistService().markInvitesAsSeen(),
                                ]);
                                if (!context.mounted) return;
                                await showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => const PlaylistInvitesModal(),
                                );
                                ProfileFollowService().markFollowersAsSeen();
                                PlaylistService().markInvitesAsSeen();
                              },
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF222222),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: hasNotifications
                                        ? const Color(0xFF514AED)
                                            .withValues(alpha: 0.6)
                                        : Colors.white.withValues(alpha: 0.1),
                                    width: 1.2,
                                  ),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Icon(
                                      Icons.notifications_outlined,
                                      color: hasNotifications
                                          ? Colors.white
                                          : Colors.white60,
                                      size: 22,
                                    ),
                                    if (hasNotifications)
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF514AED),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildGridCards(),
                    const SizedBox(height: 24),
                    _buildYourPlaylists(),
                    const SizedBox(height: 20),
                    _buildRecentPlayed(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildGridCards() {
    final cards = [
      _GridCardData(Icons.queue_music, 'Playlists',
          '${PlaylistService().playlists.length} playlists',
          onTap: () => Navigator.of(context, rootNavigator: true).push(
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 300),
                  reverseTransitionDuration: const Duration(milliseconds: 250),
                  pageBuilder: (_, __, ___) => const PlaylistsScreen(),
                  transitionsBuilder: (_, animation, __, child) {
                    final fade = CurvedAnimation(
                        parent: animation, curve: Curves.easeOut);
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                        parent: animation, curve: Curves.easeOutCubic));
                    return FadeTransition(
                      opacity: fade,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                ),
              )),
      _GridCardData(Icons.favorite, 'Liked Songs', '$_likedCount songs',
          filled: true,
          onTap: () => Navigator.of(context, rootNavigator: true).push(
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 300),
                  reverseTransitionDuration: const Duration(milliseconds: 250),
                  pageBuilder: (_, __, ___) => const LikedSongsScreen(),
                  transitionsBuilder: (_, animation, __, child) {
                    final fade = CurvedAnimation(
                        parent: animation, curve: Curves.easeOut);
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                        parent: animation, curve: Curves.easeOutCubic));
                    return FadeTransition(
                      opacity: fade,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                ),
              )),
      _GridCardData(Icons.download, 'Downloaded', '$_downloadedCount songs',
          onTap: () => Navigator.of(context, rootNavigator: true).push(
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 300),
                  reverseTransitionDuration: const Duration(milliseconds: 250),
                  pageBuilder: (_, __, ___) => const DownloadedSongsScreen(),
                  transitionsBuilder: (_, animation, __, child) {
                    final fade = CurvedAnimation(
                        parent: animation, curve: Curves.easeOut);
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                        parent: animation, curve: Curves.easeOutCubic));
                    return FadeTransition(
                      opacity: fade,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                ),
              )),
      _GridCardData(Icons.history, 'Recent', '$_recentCount songs',
          onTap: () => Navigator.of(context, rootNavigator: true).push(
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 300),
                  reverseTransitionDuration: const Duration(milliseconds: 250),
                  pageBuilder: (_, __, ___) => const RecentlyPlayedScreen(),
                  transitionsBuilder: (_, animation, __, child) {
                    final fade = CurvedAnimation(
                        parent: animation, curve: Curves.easeOut);
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                        parent: animation, curve: Curves.easeOutCubic));
                    return FadeTransition(
                      opacity: fade,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                ),
              )),
      _GridCardData(
          Icons.group_work,
          'Collabs',
          PlaylistService().collabPlaylists.isNotEmpty
              ? '${PlaylistService().collabPlaylists.length} active'
              : '0 playlists',
          onTap: () => Navigator.of(context, rootNavigator: true).push(
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 300),
                  reverseTransitionDuration: const Duration(milliseconds: 250),
                  pageBuilder: (_, __, ___) => const CollabsScreen(),
                  transitionsBuilder: (_, animation, __, child) {
                    final fade = CurvedAnimation(
                        parent: animation, curve: Curves.easeOut);
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                        parent: animation, curve: Curves.easeOutCubic));
                    return FadeTransition(
                      opacity: fade,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                ),
              )),
      _GridCardData(
          Icons.people,
          'Friends',
          PresenceService().activeList.isNotEmpty
              ? '${PresenceService().activeList.length} active now'
              : '${ProfileFollowService().mutualFriendsCount} friends',
          onTap: () => Navigator.of(context, rootNavigator: true).push(
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 300),
                  reverseTransitionDuration: const Duration(milliseconds: 250),
                  pageBuilder: (_, __, ___) => const FriendsScreen(),
                  transitionsBuilder: (_, animation, __, child) {
                    final fade = CurvedAnimation(
                        parent: animation, curve: Curves.easeOut);
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                        parent: animation, curve: Curves.easeOutCubic));
                    return FadeTransition(
                      opacity: fade,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                ),
              )),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.4,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        return _buildGridCard(card);
      },
    );
  }

  Widget _buildGridCard(_GridCardData card) {
    return Material(
      color: const Color(0xFF1F1F1F),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: card.onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.white.withValues(alpha: 0.08),
        highlightColor: Colors.white.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF514AED).withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Icon(
                    card.icon,
                    color: const Color(0xFF514AED),
                    size: 18,
                    fill: card.filled ? 1.0 : 0.0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      card.subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontFamily: 'Poppins',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.3),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildYourPlaylists() {
    final playlists = PlaylistService().playlists;

    // Show skeleton while playlists are loading
    if (!_playlistsLoaded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Your playlist',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 24,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SkeletonHomeSection(),
        ],
      );
    }

    if (playlists.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Your playlist',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      transitionDuration: const Duration(milliseconds: 300),
                      reverseTransitionDuration:
                          const Duration(milliseconds: 250),
                      pageBuilder: (_, __, ___) => const PlaylistsScreen(),
                      transitionsBuilder: (_, animation, __, child) {
                        final fade = CurvedAnimation(
                            parent: animation, curve: Curves.easeOut);
                        final slide = Tween<Offset>(
                          begin: const Offset(0.08, 0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                            parent: animation, curve: Curves.easeOutCubic));
                        return FadeTransition(
                          opacity: fade,
                          child: SlideTransition(position: slide, child: child),
                        );
                      },
                    ),
                  );
                },
                child: Icon(
                  Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 24,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: playlists.length > 6 ? 6 : playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final coverProvider = playlist.effectiveCoverProvider;
              final hasCover = coverProvider != null;
              return ListenableBuilder(
                listenable: PlaybackService(),
                builder: (context, _) {
                  final playback = PlaybackService();
                  final isPlayingThis =
                      playback.currentPlaylistId == playlist.id;

                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        PageRouteBuilder(
                          transitionDuration: const Duration(milliseconds: 300),
                          reverseTransitionDuration:
                              const Duration(milliseconds: 250),
                          pageBuilder: (_, __, ___) =>
                              PlaylistDetailScreen(playlistId: playlist.id),
                          transitionsBuilder: (_, animation, __, child) {
                            final fade = CurvedAnimation(
                                parent: animation, curve: Curves.easeOut);
                            final slide = Tween<Offset>(
                              begin: const Offset(0.08, 0),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                                parent: animation, curve: Curves.easeOutCubic));
                            return FadeTransition(
                              opacity: fade,
                              child: SlideTransition(
                                  position: slide, child: child),
                            );
                          },
                        ),
                      );
                    },
                    child: Container(
                      width: 150,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: hasCover ? null : const Color(0xFF514AED),
                              border: isPlayingThis
                                  ? Border.all(
                                      color: const Color(0xFF514AED),
                                      width: 2,
                                    )
                                  : null,
                              image: coverProvider != null
                                  ? DecorationImage(
                                      image: coverProvider,
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: Stack(
                              children: [
                                if (!hasCover)
                                  Center(
                                    child: Icon(
                                      Icons.queue_music,
                                      color:
                                          Colors.white.withValues(alpha: 0.5),
                                      size: 40,
                                    ),
                                  ),
                                if (isPlayingThis)
                                  Positioned(
                                    right: 8,
                                    bottom: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF514AED)
                                            .withValues(alpha: 0.9),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: NowPlayingBars(
                                        playing: playback.isPlaying,
                                        color: Colors.white,
                                        barWidth: 2,
                                        bars: 3,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            playlist.name,
                            style: TextStyle(
                              color: isPlayingThis
                                  ? const Color(0xFF817BFF)
                                  : Colors.white,
                              fontSize: 13,
                              fontWeight: isPlayingThis
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              fontFamily: 'Poppins',
                            ),
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
        ),
      ],
    );
  }

  Widget _buildRecentPlayed() {
    final history = ListeningHistoryService.cachedHistory;
    final currentTrack = PlaybackService().currentTrack;

    if (!_recentLoaded) {
      if (history.isEmpty && currentTrack == null) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recently played',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 24,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SkeletonHomeSection(),
        ],
      );
    }

    // Build recent list: currently playing track first, then history
    final seen = <String>{};
    final recent = <Map<String, dynamic>>[];

    if (currentTrack != null) {
      final key = '${currentTrack.title}|${currentTrack.artist}';
      seen.add(key);
      recent.add({
        'title': currentTrack.title,
        'artist': currentTrack.artist,
        'image': currentTrack.image,
        'trackId': currentTrack.id,
        'duration': currentTrack.duration,
      });
    }

    for (final song in history) {
      final key = '${song['title']}|${song['artist']}';
      if (!seen.contains(key)) {
        seen.add(key);
        recent.add(song);
      }
      if (recent.length >= 10) break;
    }

    if (recent.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recently played',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.of(context, rootNavigator: true).push(
                    PageRouteBuilder(
                      transitionDuration: const Duration(milliseconds: 300),
                      reverseTransitionDuration:
                          const Duration(milliseconds: 250),
                      pageBuilder: (_, __, ___) => const RecentlyPlayedScreen(),
                      transitionsBuilder: (_, animation, __, child) {
                        final fade = CurvedAnimation(
                            parent: animation, curve: Curves.easeOut);
                        final slide = Tween<Offset>(
                          begin: const Offset(0.08, 0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                            parent: animation, curve: Curves.easeOutCubic));
                        return FadeTransition(
                          opacity: fade,
                          child: SlideTransition(position: slide, child: child),
                        );
                      },
                    ),
                  );
                },
                child: Icon(
                  Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 24,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: recent.length,
            itemBuilder: (context, index) {
              final song = recent[index];
              final image = song['image']?.toString() ?? '';
              final title = song['title']?.toString() ?? '';
              final artist = song['artist']?.toString() ?? '';
              final trackId = song['trackId']?.toString() ?? '';

              return GestureDetector(
                onTap: () {
                  final track = SearchResult(
                    type: 'song',
                    id: trackId,
                    title: title,
                    artist: artist,
                    image: image,
                    duration: song['duration']?.toString() ?? '',
                    nbFan: 0,
                    previewUrl: '',
                  );
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
                child: Container(
                  width: 150,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: const Color(0xFF222222),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedImage(
                            image,
                            width: 150,
                            height: 150,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: const Color(0xFF222222),
                              child: const Icon(
                                Icons.music_note_rounded,
                                color: Colors.white24,
                                size: 40,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
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
                          fontFamily: 'Poppins',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GridCardData {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool filled;
  final VoidCallback? onTap;

  _GridCardData(this.icon, this.title, this.subtitle,
      {this.filled = false, this.onTap});
}
