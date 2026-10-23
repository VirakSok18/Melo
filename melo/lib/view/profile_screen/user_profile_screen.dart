import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/profile_follow_service.dart';
import '../../services/artist_follow_service.dart';
import '../../services/playback_service.dart';
import '../../widgets/cached_image.dart';
import '../friends_screen/friends_screen.dart';
import '../artist_screen/artist_screen.dart';
import '../library_screen/playlist_detail_screen.dart';
import '../search_screen/mini_player.dart';
import '../../services/cookie_service.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String initialDisplayName;
  final String initialUsername;
  final String initialAvatarUrl;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.initialDisplayName = '',
    this.initialUsername = '',
    this.initialAvatarUrl = '',
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late String _displayName;
  late String _username;
  late String _avatarUrl;
  int _followersCount = 0;
  int _followingCount = 0;
  List<Map<String, dynamic>> _publicPlaylists = [];
  List<Map<String, dynamic>> _followedArtists = [];
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _displayName = widget.initialDisplayName;
    _username = widget.initialUsername;
    _avatarUrl = widget.initialAvatarUrl;
    ProfileFollowService().addListener(_onFollowsChanged);
    ArtistFollowService().addListener(_onFollowsChanged);
    _loadUserProfile();
    _subscribeToLiveUpdates();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    ProfileFollowService().removeListener(_onFollowsChanged);
    ArtistFollowService().removeListener(_onFollowsChanged);
    super.dispose();
  }

  void _onFollowsChanged() {
    if (mounted) setState(() {});
  }

  void _subscribeToLiveUpdates() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = Supabase.instance.client
        .channel('user_profile_live:${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.userId,
          ),
          callback: (payload) {
            debugPrint(
                '[LiveProfile] Profile record updated: ${payload.newRecord}');
            final newRecord = payload.newRecord;
            if (newRecord.isNotEmpty && mounted) {
              setState(() {
                _displayName =
                    newRecord['display_name']?.toString() ?? _displayName;
                _username = newRecord['username']?.toString() ?? _username;
                _avatarUrl = newRecord['avatar_url']?.toString() ?? _avatarUrl;
              });
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_playlists',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.userId,
          ),
          callback: (payload) {
            debugPrint('[LiveProfile] User playlists updated, refreshing...');
            _loadUserProfile();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profile_follows',
          callback: (payload) {
            _loadUserProfile();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'artist_follows',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.userId,
          ),
          callback: (payload) {
            _loadUserProfile();
          },
        )
        .subscribe();
  }

  Future<void> _loadUserProfile() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final isMe = widget.userId == currentUserId;

    try {
      final playlistQuery = isMe
          ? Supabase.instance.client
              .from('user_playlists')
              .select('id, name, cover_image, is_public')
              .eq('user_id', widget.userId)
              .limit(10)
          : Supabase.instance.client
              .from('user_playlists')
              .select('id, name, cover_image, is_public')
              .eq('user_id', widget.userId)
              .eq('is_public', true)
              .limit(10);

      final results = await Future.wait<dynamic>([
        Supabase.instance.client
            .from('profiles')
            .select('display_name, username, avatar_url')
            .eq('id', widget.userId)
            .maybeSingle(),
        Supabase.instance.client
            .from('profile_follows')
            .select('follower_id')
            .eq('following_id', widget.userId),
        Supabase.instance.client
            .from('profile_follows')
            .select('following_id')
            .eq('follower_id', widget.userId),
        playlistQuery,
        Supabase.instance.client
            .from('artist_follows')
            .select('artist_id, artist_name, artist_image')
            .eq('user_id', widget.userId),
      ]);

      if (mounted) {
        final profile = results[0] as Map<String, dynamic>?;
        if (profile != null) {
          _displayName = profile['display_name']?.toString() ?? _displayName;
          _username = profile['username']?.toString() ?? _username;
          _avatarUrl = profile['avatar_url']?.toString() ?? _avatarUrl;
        }
        _followersCount = (results[1] as List?)?.length ?? 0;
        final peopleFollowing = (results[2] as List?)?.length ?? 0;
        _publicPlaylists =
            List<Map<String, dynamic>>.from(results[3] as List? ?? []);
        _followedArtists =
            List<Map<String, dynamic>>.from(results[4] as List? ?? []);
        // Following = people they follow + artists they follow (same as own profile)
        _followingCount = peopleFollowing + _followedArtists.length;
        setState(() {});
      }
    } catch (e) {
      debugPrint('Load User Profile error: $e');
      if (mounted) setState(() {});
    }
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }

  @override
  Widget build(BuildContext context) {
    final followService = ProfileFollowService();
    final isFollowing = followService.isFollowing(widget.userId);
    final isMutual = followService.isMutualFriend(widget.userId);

    return Scaffold(
      backgroundColor: const Color(0xFF191919),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 56),
                    _buildBackButton(),
                    const SizedBox(height: 24),
                    _buildProfileHeader(isFollowing, isMutual),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
              if (_followedArtists.isNotEmpty) ...[
                SliverToBoxAdapter(
                    child: _buildSectionHeader('Favorite Artists')),
                _buildArtistsSection(),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
              if (_publicPlaylists.isNotEmpty) ...[
                SliverToBoxAdapter(child: _buildSectionHeader('Playlists')),
                _buildPlaylistsSection(),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
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

  Widget _buildBackButton() {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
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
    );
  }

  bool get _isSelf {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    return currentUserId != null && currentUserId == widget.userId;
  }

  Widget _buildProfileHeader(bool isFollowing, bool isMutual) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: _avatarUrl.isNotEmpty
                      ? CachedImage(
                          _avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildPlaceholder(),
                        )
                      : _buildPlaceholder(),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName.isNotEmpty ? _displayName : 'User',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _username.isNotEmpty ? '@$_username' : '',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontFamily: 'Poppins',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const FriendsScreen(initialIndex: 1),
                              ),
                            );
                          },
                          behavior: HitTestBehavior.opaque,
                          child: _buildStat(
                              _formatCount(_followingCount), 'Following'),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const FriendsScreen(initialIndex: 2),
                              ),
                            );
                          },
                          behavior: HitTestBehavior.opaque,
                          child: _buildStat(
                              _formatCount(_followersCount), 'Followers'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_isSelf) ...[
            const SizedBox(height: 20),
            _buildActionButtons(isFollowing, isMutual),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isFollowing, bool isMutual) {
    if (_isSelf) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              final item = UserProfileItem(
                id: widget.userId,
                displayName: _displayName,
                username: _username,
                avatarUrl: _avatarUrl,
              );
              if (isFollowing) {
                ProfileFollowService().unfollowUser(widget.userId);
                setState(() =>
                    _followersCount = (_followersCount - 1).clamp(0, 999999));
                CookieService.show(
                  message:
                      'Unfollowed ${_displayName.isNotEmpty ? _displayName : 'user'}',
                  icon: Icons.person_remove_outlined,
                  iconColor: Colors.white70,
                );
              } else {
                ProfileFollowService().followUser(item);
                setState(() => _followersCount += 1);
                CookieService.show(
                  message:
                      'Following ${_displayName.isNotEmpty ? _displayName : 'user'}',
                  icon: Icons.person_add_rounded,
                  iconColor: const Color(0xFF514AED),
                );
              }
            },
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: isFollowing
                    ? Colors.white.withValues(alpha: 0.12)
                    : const Color(0xFF514AED),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isFollowing
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.transparent,
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isMutual
                          ? Icons.people
                          : isFollowing
                              ? Icons.check
                              : Icons.person_add,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isMutual
                          ? 'Friends'
                          : isFollowing
                              ? 'Following'
                              : 'Follow',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String value, String label) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            fontFamily: 'Poppins',
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: const Icon(Icons.person, color: Colors.white38, size: 48),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: 'Poppins',
        ),
      ),
    );
  }

  Widget _buildPlaylistsSection() {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 200,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: _publicPlaylists.length,
          itemBuilder: (context, index) {
            final pl = _publicPlaylists[index];
            final cover = pl['cover_image']?.toString() ?? '';
            return GestureDetector(
              onTap: () {
                final id = pl['id']?.toString() ?? '';
                if (id.isNotEmpty) {
                  Navigator.of(context)
                      .push(
                    MaterialPageRoute(
                      builder: (_) => PlaylistDetailScreen(playlistId: id),
                    ),
                  )
                      .then((_) {
                    if (mounted) _loadUserProfile();
                  });
                }
              },
              child: Container(
                width: 150,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: cover.isNotEmpty
                          ? CachedImage(cover,
                              width: 150, height: 150, fit: BoxFit.cover)
                          : Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                color: const Color(0xFF514AED),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.queue_music_rounded,
                                  color: Colors.white54, size: 40),
                            ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pl['name']?.toString() ?? 'Playlist',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
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
    );
  }

  Widget _buildArtistsSection() {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 130,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: _followedArtists.length,
          itemBuilder: (context, index) {
            final artist = _followedArtists[index];
            final name = artist['artist_name']?.toString() ?? '';
            final image = artist['artist_image']?.toString() ?? '';
            final artistId = artist['artist_id']?.toString() ?? '';

            return GestureDetector(
              onTap: () {
                if (artistId.isNotEmpty) {
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                      builder: (_) => ArtistScreen(
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
                width: 85,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  children: [
                    ClipOval(
                      child: CachedImage(
                        image,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 80,
                          height: 80,
                          color: const Color(0xFF2A2A2A),
                          child: const Icon(Icons.person,
                              color: Colors.white38, size: 30),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontFamily: 'Poppins',
                      ),
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
      ),
    );
  }
}
