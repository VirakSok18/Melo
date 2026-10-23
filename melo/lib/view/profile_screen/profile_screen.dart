import 'package:flutter/material.dart';

import '../../widgets/cached_image.dart';
import '../../services/artist_follow_service.dart';
import '../../services/profile_follow_service.dart';
import '../../services/profile_service.dart';
import '../../services/auth_service.dart';
import '../../services/playlist_service.dart';
import '../artist_screen/artist_screen.dart';
import '../friends_screen/friends_screen.dart';
import '../library_screen/playlist_detail_screen.dart';
import '../search_screen/mini_player.dart';
import '../../services/playback_service.dart';
import '../../services/share_service.dart';
import '../../main.dart';
import '../../widgets/fade_page_route.dart';
import '../../services/premium_service.dart';
import 'edit_profile_bottom_sheet.dart';
import 'general_settings_screen.dart';
import 'payment_plan_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    ArtistFollowService().addListener(_onFollowsChanged);
    ProfileFollowService().addListener(_onFollowsChanged);
    ProfileService().addListener(_onProfileChanged);
    PlaylistService().addListener(_onProfileChanged);
    PremiumService().addListener(_onProfileChanged);
    // Load fresh data from Supabase — deferred so listeners don't fire
    // during the current build frame (avoids setState-during-build crash).
    ProfileService().load(forceRefresh: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ProfileFollowService().loadFollowData();
      PlaylistService().loadPlaylists();
    });
  }

  @override
  void dispose() {
    ArtistFollowService().removeListener(_onFollowsChanged);
    ProfileFollowService().removeListener(_onFollowsChanged);
    ProfileService().removeListener(_onProfileChanged);
    PlaylistService().removeListener(_onProfileChanged);
    PremiumService().removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onFollowsChanged() {
    if (mounted) setState(() {});
  }

  int get _followingCount =>
      ArtistFollowService().followedArtists.length +
      ProfileFollowService().followingList.length;

  void _onProfileChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return '$count';
  }

  void _showSettingsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(
                  Icons.edit_outlined,
                  color: Color(0xFF514AED),
                  size: 24,
                ),
                title: const Text(
                  'Edit Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
                subtitle: const Text(
                  'Change display name & avatar',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  EditProfileBottomSheet.show(context);
                },
              ),
              const Divider(color: Colors.white12, height: 16),
              ListTile(
                leading: const Icon(
                  Icons.credit_card_rounded,
                  color: Color(0xFF817BFF),
                  size: 24,
                ),
                title: const Text(
                  'Payment Plan',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
                subtitle: Text(
                  PremiumService().isPremium
                      ? '${PremiumService().planName} (Active)'
                      : 'Free Tier • Manage plan',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white38,
                  size: 16,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    FadePageRoute(page: const PaymentPlanScreen()),
                  );
                },
              ),
              const Divider(color: Colors.white12, height: 16),
              ListTile(
                leading: const Icon(
                  Icons.tune_rounded,
                  color: Colors.white70,
                  size: 24,
                ),
                title: const Text(
                  'General',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
                subtitle: const Text(
                  'Privacy, playback, cache and data',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white38,
                  size: 16,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    FadePageRoute(page: const GeneralSettingsScreen()),
                  );
                },
              ),
              const Divider(color: Colors.white12, height: 16),
              ListTile(
                leading: const Icon(
                  Icons.logout,
                  color: Colors.redAccent,
                  size: 24,
                ),
                title: const Text(
                  'Sign Out',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
                subtitle: const Text(
                  'Log out of your Melo account',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
                onTap: () {
                  _confirmSignOut(ctx);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext sheetContext) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (dialogCtx) => Dialog(
        backgroundColor: const Color(0xFF18181D),
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Log Out',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Are you sure you want to log out of your Melo account?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  fontFamily: 'Poppins',
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: TextButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(dialogCtx);
                          Navigator.pop(sheetContext);
                          // Launch user out immediately without delay or showing blank profile
                          Navigator.of(context, rootNavigator: true)
                              .pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const AuthGate()),
                            (route) => false,
                          );
                          // Clean up session and cache in background
                          AuthService().signOut();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        child: const Text(
                          'Log Out',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ProfileService();
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
                    _buildTopBar(),
                    const SizedBox(height: 32),
                    _buildProfileHeader(profile),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
              SliverToBoxAdapter(child: _buildArtistsHeader()),
              _buildArtistsSection(),
              SliverToBoxAdapter(child: _buildPlaylistsHeader()),
              _buildPlaylistsSection(),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
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

  Widget _buildPlaylistsHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Text(
        'Playlists',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFamily: 'Poppins',
        ),
      ),
    );
  }

  Widget _buildPlaylistsSection() {
    final playlists = PlaylistService().playlists;
    if (playlists.isEmpty) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 200,
          child: Center(
            child: Text(
              'No playlists yet',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 14,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ),
      );
    }
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 200,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: playlists.length,
          itemBuilder: (context, index) {
            final pl = playlists[index];
            final cover = pl.coverImage ?? '';
            return GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(playlistId: pl.id),
                ),
              ),
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
                        if (!pl.isPublic)
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Icon(Icons.lock_rounded,
                                  color: Colors.white70, size: 12),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pl.name,
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

  Widget _buildArtistsHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Text(
        'Artists',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFamily: 'Poppins',
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
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
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  final profile = ProfileService();
                  ShareService.shareProfile(
                    username: profile.username,
                    displayName: profile.displayName,
                  );
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.share_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _showSettingsMenu,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.settings_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(ProfileService profile) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _buildAvatar(profile),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildName(profile),
                const SizedBox(height: 4),
                _buildUsername(profile),
                const SizedBox(height: 16),
                _buildStats(profile),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(ProfileService profile) {
    return Container(
      width: 130,
      height: 130,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipOval(
        child: profile.avatarUrl.isNotEmpty
            ? CachedImage(
                profile.avatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholder(),
              )
            : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: const Icon(
        Icons.person,
        color: Colors.white38,
        size: 60,
      ),
    );
  }

  Widget _buildName(ProfileService profile) {
    final isPrem = PremiumService().isPremium;
    return Row(
      children: [
        Flexible(
          child: Text(
            profile.displayName.isNotEmpty
                ? profile.displayName
                : 'Your profile',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              fontFamily: 'Poppins',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isPrem) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF817BFF), Color(0xFF514AED)],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF514AED).withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium_rounded,
                    color: Colors.white, size: 12),
                SizedBox(width: 3),
                Text(
                  'PRO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Poppins',
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUsername(ProfileService profile) {
    return Text(
      profile.username.isNotEmpty ? '@${profile.username}' : '',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.6),
        fontSize: 12,
        fontFamily: 'Poppins',
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildStats(ProfileService profile) {
    return Row(
      children: [
        GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const FriendsScreen(initialIndex: 1), // Following tab
              ),
            );
          },
          behavior: HitTestBehavior.opaque,
          child: _buildStat(_formatCount(_followingCount), 'Following'),
        ),
        const SizedBox(width: 20),
        GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const FriendsScreen(initialIndex: 2), // Followers tab
              ),
            );
          },
          behavior: HitTestBehavior.opaque,
          child: _buildStat(_formatCount(profile.followers), 'Followers'),
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
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
            fontFamily: 'Poppins',
          ),
        ),
      ],
    );
  }

  Widget _buildArtistsSection() {
    final artists = ArtistFollowService().followedArtists;
    if (artists.isEmpty) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 140,
          child: Center(
            child: Text(
              'No artists',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 14,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: SizedBox(
        height: 140,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artist = artists[index];
            final name = artist['artist_name']?.toString() ?? '';
            final image = artist['artist_image']?.toString() ?? '';
            final artistId = artist['artist_id']?.toString() ?? '';
            return _buildArtistCard(artistId, name, image);
          },
        ),
      ),
    );
  }

  Widget _buildArtistCard(String artistId, String name, String image) {
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
        width: 90,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          children: [
            ClipOval(
              child: CachedImage(
                image,
                width: 85,
                height: 85,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 85,
                  height: 85,
                  color: const Color(0xFF2A2A2A),
                  child:
                      const Icon(Icons.person, color: Colors.white38, size: 32),
                ),
              ),
            ),
            const SizedBox(height: 8),
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
  }
}
