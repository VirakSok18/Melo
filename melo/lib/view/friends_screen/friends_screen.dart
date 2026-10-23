import 'package:flutter/material.dart';
import '../../services/profile_follow_service.dart';
import '../../services/artist_follow_service.dart';
import '../../services/presence_service.dart';
import '../../services/playback_service.dart';
import '../../services/search_service.dart';
import '../../widgets/cached_image.dart';
import '../../services/cookie_service.dart';
import '../../services/premium_service.dart';
import '../profile_screen/user_profile_screen.dart';
import '../artist_screen/artist_screen.dart';
import '../search_screen/mini_player.dart';

class FriendsScreen extends StatefulWidget {
  final int initialIndex;
  const FriendsScreen({super.key, this.initialIndex = 0});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _followingFilter = 0; // 0 = All, 1 = People, 2 = Artists

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, 2),
    );
    ProfileFollowService().addListener(_onServiceUpdate);
    ArtistFollowService().addListener(_onServiceUpdate);
    PresenceService().addListener(_onServiceUpdate);
    PresenceService().init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ProfileFollowService().loadFollowData();
      ArtistFollowService().loadFollowedArtists();
      PresenceService().refreshPresence();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    ProfileFollowService().removeListener(_onServiceUpdate);
    ArtistFollowService().removeListener(_onServiceUpdate);
    PresenceService().removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final followService = ProfileFollowService();
    final artistService = ArtistFollowService();
    final mutualFriends = followService.mutualFriendsList;
    final following = followService.followingList;
    final followedArtists = artistService.followedArtists;
    final followers = followService.followersList;
    final totalFollowingCount = following.length + followedArtists.length;

    return Scaffold(
      backgroundColor: const Color(0xFF191919),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                _buildHeader(context),
                const SizedBox(height: 12),
                _buildTabBar(mutualFriends.length, totalFollowingCount,
                    followers.length),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildUserList(mutualFriends,
                          emptyText:
                              'No mutual friends yet.\nFollow each other back to become friends!'),
                      _buildFollowingTab(following, followedArtists),
                      _buildUserList(followers,
                          emptyText: 'You have no followers yet.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
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
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            'Friends & Activity',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(int mutualCount, int followingCount, int followersCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF262626),
          borderRadius: BorderRadius.circular(10),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: const Color(0xFF383838),
            borderRadius: BorderRadius.circular(8),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
          tabs: [
            Tab(text: 'Friends ($mutualCount)'),
            Tab(text: 'Following ($followingCount)'),
            Tab(text: 'Followers ($followersCount)'),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowingTab(
      List<UserProfileItem> users, List<Map<String, dynamic>> artists) {
    final totalCount = users.length + artists.length;
    if (totalCount == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'You are not following anyone yet.\nDiscover people and artists to follow!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 13,
              fontFamily: 'Poppins',
              height: 1.5,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        // Filter Chips Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              _buildFilterChip('All ($totalCount)', 0),
              const SizedBox(width: 8),
              _buildFilterChip('People (${users.length})', 1),
              const SizedBox(width: 8),
              _buildFilterChip('Artists (${artists.length})', 2),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _buildFilteredFollowingList(users, artists),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _followingFilter == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _followingFilter = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF514AED) : const Color(0xFF262626),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontFamily: 'Poppins',
          ),
        ),
      ),
    );
  }

  Widget _buildFilteredFollowingList(
      List<UserProfileItem> users, List<Map<String, dynamic>> artists) {
    if (_followingFilter == 1) {
      return _buildUserList(users,
          emptyText: 'You are not following any users yet.');
    }
    if (_followingFilter == 2) {
      return _buildArtistList(artists,
          emptyText: 'You are not following any artists yet.');
    }

    final combinedLength = users.length + artists.length;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: combinedLength,
      itemBuilder: (context, index) {
        if (index < users.length) {
          return _buildUserItem(users[index]);
        } else {
          final artistIndex = index - users.length;
          return _buildArtistItem(artists[artistIndex]);
        }
      },
    );
  }

  Widget _buildArtistList(List<Map<String, dynamic>> artists,
      {required String emptyText}) {
    if (artists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 13,
              fontFamily: 'Poppins',
              height: 1.5,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        return _buildArtistItem(artists[index]);
      },
    );
  }

  Widget _buildArtistItem(Map<String, dynamic> artist) {
    final artistId = artist['artist_id']?.toString() ?? '';
    final artistName = artist['artist_name']?.toString() ?? '';
    final artistImage = artist['artist_image']?.toString() ?? '';
    final isFollowing = ArtistFollowService().isFollowing(artistId);

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ArtistScreen(
              artistId: artistId,
              artistName: artistName,
              artistImage: artistImage,
              nbFan: 0,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        margin: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            ClipOval(
              child: artistImage.isNotEmpty
                  ? CachedImage(artistImage,
                      width: 48, height: 48, fit: BoxFit.cover)
                  : Container(
                      width: 48,
                      height: 48,
                      color: const Color(0xFF2A2A2A),
                      child: const Icon(Icons.music_note,
                          color: Colors.white38, size: 24),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artistName.isNotEmpty ? artistName : 'Artist',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Artist',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                if (isFollowing) {
                  ArtistFollowService().unfollowArtist(artistId);
                  CookieService.show(
                    message:
                        'Unfollowed ${artistName.isNotEmpty ? artistName : 'Artist'}',
                    icon: Icons.person_remove_outlined,
                    iconColor: Colors.white70,
                  );
                } else {
                  ArtistFollowService().followArtist(
                    artistId: artistId,
                    artistName: artistName,
                    artistImage: artistImage,
                  );
                  CookieService.show(
                    message:
                        'Following ${artistName.isNotEmpty ? artistName : 'Artist'}',
                    icon: Icons.check_circle_rounded,
                    iconColor: const Color(0xFF514AED),
                  );
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isFollowing
                      ? const Color(0xFF514AED)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        isFollowing ? const Color(0xFF514AED) : Colors.white38,
                    width: 1,
                  ),
                ),
                child: Text(
                  isFollowing ? 'Following' : 'Follow',
                  style: TextStyle(
                    color: isFollowing ? Colors.white : Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserList(List<UserProfileItem> users,
      {required String emptyText}) {
    if (users.isEmpty) {
      return RefreshIndicator(
        color: const Color(0xFF514AED),
        backgroundColor: const Color(0xFF262626),
        onRefresh: () async {
          PresenceService().refreshPresence();
          await ProfileFollowService().loadFollowData();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.4,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    emptyText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 13,
                      fontFamily: 'Poppins',
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF514AED),
      backgroundColor: const Color(0xFF262626),
      onRefresh: () async {
        PresenceService().refreshPresence();
        await ProfileFollowService().loadFollowData();
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: users.length,
        itemBuilder: (context, index) {
          return _buildUserItem(users[index]);
        },
      ),
    );
  }

  Widget _buildUserItem(UserProfileItem user) {
    final presence = PresenceService().getPresence(user.id);
    final isListeningToMe = PresenceService().isFriendListeningToMe(user.id);
    final isListeningAlongWithThem =
        PresenceService().listeningWithUserId == user.id;

    final isPlayingSong = presence != null &&
        !presence.isOffline &&
        presence.isPlaying &&
        presence.songTitle.isNotEmpty;
    final isOnline =
        (presence != null && !presence.isOffline) || isListeningToMe;

    final showPlayingIndicator = isListeningToMe || isPlayingSong;

    final String subtitleText;
    final Color subtitleColor;
    final FontWeight subtitleWeight;

    if (isListeningToMe) {
      subtitleText = 'Listening along with you';
      subtitleColor = const Color(0xFFB4ACFF);
      subtitleWeight = FontWeight.w600;
    } else if (isListeningAlongWithThem) {
      subtitleText = (presence != null && presence.songTitle.isNotEmpty)
          ? 'Listening to ${presence.songTitle}'
          : 'Listening along with ${user.displayName}';
      subtitleColor = const Color(0xFF9D97F7);
      subtitleWeight = FontWeight.w500;
    } else if (isPlayingSong) {
      subtitleText = 'Listening to ${presence.songTitle}';
      subtitleColor = const Color(0xFF9D97F7);
      subtitleWeight = FontWeight.normal;
    } else {
      subtitleText = user.username.isNotEmpty ? '@${user.username}' : '';
      subtitleColor = Colors.white.withValues(alpha: 0.5);
      subtitleWeight = FontWeight.normal;
    }

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(
              userId: user.id,
              initialDisplayName: user.displayName,
              initialUsername: user.username,
              initialAvatarUrl: user.avatarUrl,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        margin: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Stack(
              children: [
                ClipOval(
                  child: user.avatarUrl.isNotEmpty
                      ? CachedImage(user.avatarUrl,
                          width: 48, height: 48, fit: BoxFit.cover)
                      : Container(
                          width: 48,
                          height: 48,
                          color: const Color(0xFF2A2A2A),
                          child: const Icon(Icons.person,
                              color: Colors.white38, size: 26),
                        ),
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: showPlayingIndicator
                            ? const Color(0xFF514AED) // Melo purple when playing / with you
                            : const Color(0xFF10B981), // Green dot when online idle
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF191919),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.displayName.isNotEmpty
                              ? user.displayName
                              : 'User',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showPlayingIndicator) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.graphic_eq,
                            color: Color(0xFF514AED), size: 14),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitleText,
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 11,
                      fontWeight: subtitleWeight,
                      fontFamily: 'Poppins',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isListeningToMe) ...[
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF514AED).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF514AED).withValues(alpha: 0.45),
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.headphones_rounded,
                      color: Color(0xFF514AED),
                      size: 13,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'With you',
                      style: TextStyle(
                        color: Color(0xFFB4ACFF),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isListeningAlongWithThem) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {
                  PresenceService().stopListeningWith(showToast: true);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white24,
                      width: 1,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.headphones_rounded,
                        color: Color(0xFF514AED),
                        size: 13,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Listening',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (isPlayingSong) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {
                  if (!PremiumService().canSyncListenAlong) {
                    PremiumService.showUpsell(context,
                        feature: 'Listen Together Live Sync');
                    return;
                  }
                  final item = SearchResult(
                    id: presence.trackId,
                    title: presence.songTitle,
                    artist: presence.songArtist,
                    image: presence.songImage,
                    type: 'song',
                    duration: '',
                    nbFan: 0,
                    previewUrl: '',
                  );
                  final elapsedSinceBroadcast =
                      DateTime.now().difference(presence.updatedAt);
                  final transitMs =
                      elapsedSinceBroadcast.inMilliseconds.clamp(0, 3000);
                  final exactPositionMs = presence.positionMs +
                      (presence.isPlaying ? transitMs : 0);
                  final targetPosition = Duration(
                    milliseconds: exactPositionMs.clamp(0, 3600000),
                  );

                  PresenceService().startListeningWith(
                    presence.userId,
                    friendDisplayName: presence.displayName,
                    initialPositionMs: exactPositionMs,
                    isHostPlaying: presence.isPlaying,
                  );
                  PlaybackService().playTrack(
                    item,
                    initialPosition: targetPosition,
                    fromSync: true,
                  );
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 4,
                        offset: const Offset(0, 1.5),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.headphones_rounded,
                        color: Colors.black,
                        size: 13,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Listen Along',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
