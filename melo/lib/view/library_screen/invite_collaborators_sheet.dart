import 'package:flutter/material.dart';
import '../../services/profile_follow_service.dart';
import '../../services/playlist_service.dart';
import '../../services/cookie_service.dart';
import '../../widgets/cached_image.dart';

class InviteCollaboratorsSheet extends StatefulWidget {
  final String playlistId;
  final String playlistName;

  const InviteCollaboratorsSheet({
    super.key,
    required this.playlistId,
    required this.playlistName,
  });

  @override
  State<InviteCollaboratorsSheet> createState() =>
      _InviteCollaboratorsSheetState();
}

class _InviteCollaboratorsSheetState extends State<InviteCollaboratorsSheet> {
  final Set<String> _collaboratorUserIds = {};
  bool _loadingCollabs = true;
  String _searchQuery = '';
  final Set<String> _invitingIds = {};

  @override
  void initState() {
    super.initState();
    _loadExistingCollaborators();
  }

  Future<void> _loadExistingCollaborators() async {
    setState(() => _loadingCollabs = true);
    final collabs =
        await PlaylistService().fetchCollaborators(widget.playlistId);
    if (mounted) {
      setState(() {
        _collaboratorUserIds.clear();
        for (final c in collabs) {
          final uId = c['user_id']?.toString() ?? '';
          if (uId.isNotEmpty) _collaboratorUserIds.add(uId);
        }
        _loadingCollabs = false;
      });
    }
  }

  Future<void> _toggleInvite(UserProfileItem user) async {
    final isCurrentlyCollaborator = _collaboratorUserIds.contains(user.id);

    if (isCurrentlyCollaborator) {
      setState(() {
        _collaboratorUserIds.remove(user.id);
        _invitingIds.add(user.id);
      });
      await PlaylistService().removeCollaborator(widget.playlistId, user.id);
      if (mounted) {
        setState(() => _invitingIds.remove(user.id));
      }
    } else {
      setState(() {
        _collaboratorUserIds.add(user.id);
        _invitingIds.add(user.id);
      });
      final success = await PlaylistService()
          .inviteCollaborator(widget.playlistId, user.id);
      if (mounted) {
        setState(() {
          if (!success) _collaboratorUserIds.remove(user.id);
          _invitingIds.remove(user.id);
        });
        if (success) {
          CookieService.show(
            message: '${user.displayName} invited to collaborate!',
            icon: Icons.person_add_alt_1_rounded,
            iconColor: const Color(0xFF8A82FF),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final followService = ProfileFollowService();
    final friends = followService.mutualFriendsList.isNotEmpty
        ? followService.mutualFriendsList
        : followService.followingList;

    final filteredFriends = friends.where((f) {
      final q = _searchQuery.toLowerCase();
      return f.displayName.toLowerCase().contains(q) ||
          f.username.toLowerCase().contains(q);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Invite Collaborators',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Friends can add and reorder songs',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF514AED).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: const Color(0xFF514AED), width: 1),
                  ),
                  child: Text(
                    '${_collaboratorUserIds.length} Added',
                    style: const TextStyle(
                      color: Color(0xFF817BFF),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              style:
                  const TextStyle(color: Colors.white, fontFamily: 'Poppins'),
              decoration: InputDecoration(
                hintText: 'Search friends...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontFamily: 'Poppins',
                ),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.white38, size: 20),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loadingCollabs
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF514AED)),
                  )
                : filteredFriends.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline_rounded,
                              size: 48,
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Follow friends back to invite them!'
                                  : 'No friends found matching "$_searchQuery"',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 13,
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filteredFriends.length,
                        itemBuilder: (context, i) {
                          final friend = filteredFriends[i];
                          final isCollaborator =
                              _collaboratorUserIds.contains(friend.id);
                          final isInviting = _invitingIds.contains(friend.id);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF262626),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: friend.avatarUrl.isNotEmpty
                                        ? CachedImage(
                                            friend.avatarUrl,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            color: const Color(0xFF514AED),
                                            child: Center(
                                              child: Text(
                                                friend.displayName.isNotEmpty
                                                    ? friend.displayName[0]
                                                        .toUpperCase()
                                                    : '?',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'Poppins',
                                                ),
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        friend.displayName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'Poppins',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (friend.username.isNotEmpty)
                                        Text(
                                          '@${friend.username}',
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.4),
                                            fontSize: 12,
                                            fontFamily: 'Poppins',
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: isInviting
                                      ? null
                                      : () => _toggleInvite(friend),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isCollaborator
                                          ? const Color(0xFF333333)
                                          : const Color(0xFF514AED),
                                      borderRadius: BorderRadius.circular(10),
                                      border: isCollaborator
                                          ? Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.15))
                                          : null,
                                    ),
                                    child: isInviting
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isCollaborator) ...[
                                                const Icon(
                                                    Icons.check_circle_rounded,
                                                    size: 14,
                                                    color: Color(0xFF817BFF)),
                                                const SizedBox(width: 4),
                                              ],
                                              Text(
                                                isCollaborator
                                                    ? 'Invited'
                                                    : 'Invite',
                                                style: TextStyle(
                                                  color: isCollaborator
                                                      ? const Color(0xFF817BFF)
                                                      : Colors.white,
                                                  fontSize: 12,
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
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
