import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/playlist_service.dart';
import '../../services/profile_follow_service.dart';
import '../../services/cookie_service.dart';
import '../../widgets/cached_image.dart';
import '../profile_screen/user_profile_screen.dart';
import 'playlist_detail_screen.dart';

class PlaylistInvitesModal extends StatefulWidget {
  const PlaylistInvitesModal({super.key});

  @override
  State<PlaylistInvitesModal> createState() => _PlaylistInvitesModalState();
}

class _PlaylistInvitesModalState extends State<PlaylistInvitesModal> {
  final Set<String> _dismissedInviteIds = {};
  final Set<String> _actionInProgressIds = {};
  bool _isLoading = true;
  List<UserPlaylist> _liveInvitedPlaylists = [];

  @override
  void initState() {
    super.initState();
    ProfileFollowService().markFollowersAsSeen();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchLiveInvites();
        _fetchFollowersAndMarkSeen();
      }
    });
  }

  @override
  void dispose() {
    ProfileFollowService().markFollowersAsSeen();
    PlaylistService().markInvitesAsSeen();
    super.dispose();
  }

  Future<void> _fetchFollowersAndMarkSeen() async {
    await ProfileFollowService().loadFollowData();
    await ProfileFollowService().markFollowersAsSeen();
    await PlaylistService().markInvitesAsSeen();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchLiveInvites() async {
    final client = Supabase.instance.client;
    final currentUserId = client.auth.currentUser?.id ?? '';
    if (currentUserId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Fetch rows from playlist_collaborators for current user where role is 'pending'
      final collabRows = await client
          .from('playlist_collaborators')
          .select('playlist_id, role')
          .eq('user_id', currentUserId);

      final playlistIds = (collabRows as List)
          .where(
              (c) => (c['role']?.toString() ?? '').toLowerCase() == 'pending')
          .map((c) => c['playlist_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      if (playlistIds.isNotEmpty) {
        // 2. Fetch playlists where creator is NOT the current user
        final playlistsData = await client
            .from('user_playlists')
            .select()
            .inFilter('id', playlistIds);

        final List<UserPlaylist> list = [];
        for (final p in (playlistsData as List)) {
          final pUserId = p['user_id']?.toString() ?? '';
          if (pUserId == currentUserId) continue; // Skip own created playlists

          final pId = p['id']?.toString() ?? '';
          if (PlaylistService().isInviteHandled(pId) ||
              PlaylistService().isInviteAccepted(pId)) {
            continue;
          }

          final songsData = await client
              .from('playlist_songs')
              .select()
              .eq('playlist_id', pId)
              .order('position');

          list.add(UserPlaylist(
            id: pId,
            userId: pUserId,
            name: p['name'] ?? 'Collab Playlist',
            coverImage: p['cover_image'],
            isCollaborative: true,
            songs: (songsData as List)
                .map((s) => PlaylistSong.fromMap(s))
                .toList(),
            createdAt:
                DateTime.tryParse(p['created_at'] ?? '') ?? DateTime.now(),
          ));
        }

        if (mounted) {
          setState(() {
            _liveInvitedPlaylists = list;
            _isLoading = false;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('[PlaylistInvitesModal] Error fetching invites: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _acceptInvite(UserPlaylist playlist) async {
    setState(() {
      _actionInProgressIds.add(playlist.id);
      _dismissedInviteIds.add(playlist.id);
      _liveInvitedPlaylists.removeWhere((p) => p.id == playlist.id);
    });

    final ps = PlaylistService();
    if (!ps.playlists.any((p) => p.id == playlist.id)) {
      ps.playlists.add(playlist);
      ps.collabPlaylists.add(playlist);
    }
    await ps.acceptInvite(playlist.id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Joined "${playlist.name}"!'),
          backgroundColor: const Color(0xFF514AED),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
        ),
      );
    }
  }

  Future<void> _declineInvite(UserPlaylist playlist) async {
    setState(() {
      _actionInProgressIds.add(playlist.id);
      _dismissedInviteIds.add(playlist.id);
      _liveInvitedPlaylists.removeWhere((p) => p.id == playlist.id);
    });

    await PlaylistService().declineInvite(playlist.id);

    if (mounted) {
      setState(() {
        _actionInProgressIds.remove(playlist.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Declined invite to "${playlist.name}"'),
          backgroundColor: const Color(0xFF333333),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _clearAll(List<UserPlaylist> invites, List<UserProfileItem> followers) {
    final inviteIds = invites.map((p) => p.id).toList();
    final followerIds = followers.map((f) => f.id).toList();

    setState(() {
      _dismissedInviteIds.addAll(inviteIds);
      _liveInvitedPlaylists.removeWhere((p) => inviteIds.contains(p.id));
    });

    if (inviteIds.isNotEmpty) {
      PlaylistService().clearAllInvites(inviteIds);
    }
    if (followerIds.isNotEmpty) {
      ProfileFollowService().clearAllFollowerNotifications(followerIds);
    }
  }

  String _formatTimeAgo(DateTime? dateTime) {
    if (dateTime == null) return '';
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  @override
  Widget build(BuildContext context) {
    final playlistService = PlaylistService();
    final followService = ProfileFollowService();

    // In-memory invites from live fetch that are still pending and not handled/accepted
    final allInvites = <String, UserPlaylist>{};
    for (final p in _liveInvitedPlaylists) {
      if (!playlistService.isInviteHandled(p.id) &&
          !playlistService.isInviteAccepted(p.id)) {
        allInvites[p.id] = p;
      }
    }

    final displayInvites = allInvites.values
        .where((p) => !_dismissedInviteIds.contains(p.id))
        .toList();

    return ListenableBuilder(
      listenable: followService,
      builder: (context, _) {
        final activeFollowers = followService.activeFollowerNotifications;
        final totalCount = displayInvites.length + activeFollowers.length;

        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notifications_active_rounded,
                            color: Color(0xFF817BFF), size: 22),
                        const SizedBox(width: 10),
                        const Text(
                          'Notifications',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ],
                    ),
                    if (totalCount > 0)
                      GestureDetector(
                        onTap: () => _clearAll(displayInvites, activeFollowers),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Clear',
                            style: TextStyle(
                              color: Color(0xFF817BFF),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFF514AED)),
                      )
                    : totalCount == 0
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.notifications_none_rounded,
                                    size: 54,
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No Notifications',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'When you receive invites or new followers, they will appear right here.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.5),
                                      fontSize: 12,
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: [
                              // 1. Follow notifications
                              if (activeFollowers.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 4, bottom: 8, top: 4),
                                  child: Text(
                                    'NEW FOLLOWERS',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.45),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                ),
                                ...activeFollowers.map((follower) =>
                                    _buildFollowerItem(
                                        follower, followService)),
                                const SizedBox(height: 12),
                              ],

                              // 2. Collab invites
                              if (displayInvites.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 4, bottom: 8, top: 4),
                                  child: Text(
                                    'COLLABORATION INVITES',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.45),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                ),
                                ...displayInvites.map(
                                    (playlist) => _buildInviteItem(playlist)),
                                const SizedBox(height: 16),
                              ],
                            ],
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFollowerItem(
      UserProfileItem follower, ProfileFollowService followService) {
    final isFollowingBack = followService.isFollowing(follower.id);
    final timeAgo = _formatTimeAgo(follower.followedAt);

    return Dismissible(
      key: Key('follower_${follower.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        followService.dismissFollowerNotification(follower.id);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child:
            const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF262626),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => UserProfileScreen(
                      userId: follower.id,
                      initialDisplayName: follower.displayName,
                      initialUsername: follower.username,
                      initialAvatarUrl: follower.avatarUrl,
                    ),
                  ),
                );
              },
              child: ClipOval(
                child: follower.avatarUrl.isNotEmpty
                    ? CachedImage(
                        follower.avatarUrl,
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        placeholder: Container(
                          width: 46,
                          height: 46,
                          color: const Color(0xFF333333),
                        ),
                        errorBuilder: (_, __, ___) => Container(
                          width: 46,
                          height: 46,
                          color: const Color(0xFF333333),
                          child: const Icon(Icons.person,
                              color: Colors.white38, size: 22),
                        ),
                      )
                    : Container(
                        width: 46,
                        height: 46,
                        color: const Color(0xFF333333),
                        child: const Icon(Icons.person,
                            color: Colors.white38, size: 22),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UserProfileScreen(
                        userId: follower.id,
                        initialDisplayName: follower.displayName,
                        initialUsername: follower.username,
                        initialAvatarUrl: follower.avatarUrl,
                      ),
                    ),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: Colors.white,
                        ),
                        children: [
                          TextSpan(
                            text: follower.displayName.isNotEmpty
                                ? follower.displayName
                                : 'Someone',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: isFollowingBack
                                ? ' followed you back'
                                : ' started following you',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (follower.username.isNotEmpty) ...[
                          Text(
                            '@${follower.username}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                              fontFamily: 'Poppins',
                            ),
                          ),
                          if (timeAgo.isNotEmpty) ...[
                            Text(
                              ' • ',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                        if (timeAgo.isNotEmpty)
                          Text(
                            timeAgo,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                              fontFamily: 'Poppins',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                if (isFollowingBack) {
                  followService.unfollowUser(follower.id);
                  CookieService.show(
                    message:
                        'Unfollowed ${follower.displayName.isNotEmpty ? follower.displayName : 'user'}',
                    icon: Icons.person_remove_outlined,
                    iconColor: Colors.white70,
                  );
                } else {
                  followService.followUser(follower);
                  CookieService.show(
                    message:
                        'Followed ${follower.displayName.isNotEmpty ? follower.displayName : 'user'}',
                    icon: Icons.person_add_rounded,
                    iconColor: const Color(0xFF514AED),
                  );
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isFollowingBack
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFF514AED),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isFollowingBack
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Text(
                  isFollowingBack ? 'Following' : 'Follow Back',
                  style: TextStyle(
                    color: isFollowingBack ? Colors.white70 : Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Explicit remove button for this individual notification
            GestureDetector(
              onTap: () {
                followService.dismissFollowerNotification(follower.id);
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.close_rounded,
                  color: Colors.white.withValues(alpha: 0.35),
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteItem(UserPlaylist playlist) {
    final inProgress = _actionInProgressIds.contains(playlist.id);
    final coverProvider = playlist.effectiveCoverProvider;

    return Dismissible(
      key: Key('collab_${playlist.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        _declineInvite(playlist);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(18),
        ),
        child:
            const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF262626),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF514AED).withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: coverProvider != null
                        ? Image(image: coverProvider, fit: BoxFit.cover)
                        : Container(
                            color: const Color(0xFF514AED),
                            child: const Center(
                              child: Icon(Icons.group_work,
                                  color: Colors.white, size: 26),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF514AED)
                                  .withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Collab Invite',
                              style: TextStyle(
                                color: Color(0xFF817BFF),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${playlist.songs.length} tracks',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: inProgress ? null : () => _declineInvite(playlist),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.white.withValues(alpha: 0.35),
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: inProgress ? null : () => _declineInvite(playlist),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'Decline',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: inProgress ? null : () => _acceptInvite(playlist),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF514AED),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: inProgress
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Accept',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
