import '../../widgets/cached_image.dart';
import 'package:flutter/material.dart';
import '../../services/artist_service.dart';
import '../../services/artist_follow_service.dart';
import '../../services/search_service.dart';
import '../../services/playback_service.dart';
import '../../services/background_prefetch_service.dart';
import '../../services/share_service.dart';

import '../../widgets/skeleton_loader.dart';
import '../../services/youtube_service.dart';
import '../../services/cookie_service.dart';
import '../search_screen/mini_player.dart';
import '../search_screen/search_result_item.dart';
import '../album_screen/album_detail_screen.dart';

class ArtistScreen extends StatefulWidget {
  final String artistId;
  final String artistName;
  final String artistImage;
  final int nbFan;

  const ArtistScreen({
    super.key,
    required this.artistId,
    required this.artistName,
    required this.artistImage,
    required this.nbFan,
  });

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  List<SearchResult> _topTracks = [];
  List<Map<String, dynamic>> _albums = [];
  bool _isLoading = true;
  bool _isFollowing = false;
  int _selectedTab = 0;
  bool _isGridView = true;
  late int _nbFan;
  late String _effectiveArtistId;
  late String _artistImage;

  @override
  void initState() {
    super.initState();
    _effectiveArtistId = widget.artistId;
    _artistImage = widget.artistImage;
    _nbFan = widget.nbFan;
    _isFollowing = ArtistFollowService().isFollowing(widget.artistId);
    _loadArtistData();
  }

  Future<void> _loadArtistData() async {
    var artistId = widget.artistId;

    // Fetch the artist info first — if this ID turns out to be one of
    // Deezer's duplicate/tribute entries (tiny fan count since Feb 2026),
    // re-resolve the real artist by name before loading anything else.
    var info = await ArtistService.getArtistInfo(artistId);
    var infoFans = 0;
    if (info != null && info['nb_fan'] != null) {
      infoFans = (info['nb_fan'] as num).toInt();
    }

    if (infoFans < 1000) {
      try {
        final resolved = await ArtistService.resolveArtist(widget.artistName);
        final resolvedFans = (resolved?['nb_fan'] as num?)?.toInt() ?? 0;
        if (resolved != null &&
            (resolved['id'] as String).isNotEmpty &&
            resolved['id'] != artistId &&
            resolvedFans > infoFans) {
          artistId = resolved['id'] as String;
          final better = await ArtistService.getArtistInfo(artistId);
          if (better != null && better['nb_fan'] != null) {
            info = better;
            infoFans = (better['nb_fan'] as num).toInt();
          }
        }
      } catch (_) {}
    }

    // Extract official Deezer artist picture if available
    final realImage = (info?['picture_xl'] ??
                info?['picture_big'] ??
                info?['picture_medium'] ??
                info?['picture'] ??
                info?['image'])
            ?.toString() ??
        '';

    final results = await Future.wait([
      ArtistService.getArtistTopTracks(artistId),
      ArtistService.getArtistAlbums(artistId),
    ]);

    var topTracks = results[0] as List<SearchResult>;
    final albums = results[1] as List<Map<String, dynamic>>;

    // Build verified album cover map from the artist's official album catalog
    final albumCoverById = <String, String>{};
    final albumCoverByTitle = <String, String>{};
    for (final a in albums) {
      final aId = a['id']?.toString() ?? '';
      final aTitle = (a['title']?.toString() ?? '').toLowerCase().trim();
      final aCover = (a['image'] ?? a['cover_big'] ?? a['cover_medium'] ?? '')
              ?.toString() ??
          '';
      if (aId.isNotEmpty && aCover.isNotEmpty) {
        albumCoverById[aId] = aCover;
      }
      if (aTitle.isNotEmpty && aCover.isNotEmpty) {
        albumCoverByTitle[aTitle] = aCover;
      }
    }

    // Some artists' /top returns fewer than 10 songs (small catalog or one of
    // Deezer's duplicate entries). Top up from wider sources — but only ever
    // APPEND; tracks already shown are never replaced or reordered.
    // IMPORTANT: always check t.artistId == artistId so same-name artists
    // (e.g. Eve the JP singer vs Eve the US rapper) never bleed into each other.
    // IMPORTANT: always check t.artistId == artistId and artist name match.
    if (topTracks.length < 10) {
      final seen =
          topTracks.map((t) => '${t.title}|${t.artist}'.toLowerCase()).toSet();
      final normTarget = widget.artistName.toLowerCase().trim();

      void fill(Iterable<dynamic> extras) {
        for (final t in extras) {
          if (t is SearchResult) {
            if (topTracks.length >= 10) {
              break;
            }
            // Reject tracks from a different Deezer artist (same-name collision).
            if (artistId.isNotEmpty &&
                t.artistId.isNotEmpty &&
                t.artistId != artistId) {
              continue;
            }
            final tArtist = t.artist.toLowerCase().trim();
            if (normTarget.isNotEmpty &&
                tArtist.isNotEmpty &&
                tArtist != normTarget &&
                !tArtist.contains(normTarget) &&
                !normTarget.contains(tArtist)) {
              continue;
            }
            final key = '${t.title}|${t.artist}'.toLowerCase();
            if (seen.add(key)) {
              topTracks.add(t);
            }
          }
        }
      }

      if (artistId.isNotEmpty && topTracks.length < 10) {
        fill(await ArtistService.getExtendedTopTracks(artistId));
      }
      if (topTracks.length < 10) {
        fill(await ArtistService.searchTracksByArtist(widget.artistName));
      }
    }

    // Reconcile track album covers with verified artist albums catalog:
    topTracks = topTracks.map((t) {
      String? verifiedCover;
      if (t.albumId.isNotEmpty && albumCoverById.containsKey(t.albumId)) {
        verifiedCover = albumCoverById[t.albumId];
      } else if (t.albumTitle.isNotEmpty &&
          albumCoverByTitle.containsKey(t.albumTitle.toLowerCase().trim())) {
        verifiedCover = albumCoverByTitle[t.albumTitle.toLowerCase().trim()];
      }
      if (verifiedCover != null &&
          verifiedCover.isNotEmpty &&
          verifiedCover != t.image) {
        return t.copyWith(
          image: verifiedCover,
          albumCover: verifiedCover,
        );
      }
      return t;
    }).toList();

    if (mounted) {
      setState(() {
        _topTracks = topTracks;
        _albums = results[1] as List<Map<String, dynamic>>;
        _albums = albums;
        if (realImage.isNotEmpty) {
          _artistImage = realImage;
        }
        // Deezer returns nb_fan (the old code read 'nbFan', which never
        // exists in the raw response, so the count never refreshed).
        final rawFans = info?['nb_fan'];
        if (rawFans != null && (rawFans as num).toInt() > _nbFan) {
          _nbFan = rawFans.toInt();
        } else if (widget.nbFan > _nbFan) {
          _nbFan = widget.nbFan;
        }
        _effectiveArtistId = artistId;
        _isFollowing = ArtistFollowService().isFollowing(artistId);
        _isLoading = false;
      });
      YouTubeService.prefetchStreamUrls(topTracks);
      BackgroundPrefetchService.instance
          .enqueueTracks(topTracks, tag: 'artist_screen');
    }
  }

  String _formatFans(int fans) {
    if (fans >= 1000000) {
      return '${(fans / 1000000).toStringAsFixed(1)}M';
    } else if (fans >= 1000) {
      return '${(fans / 1000).toStringAsFixed(0)}K';
    }
    return '$fans';
  }

  void _shareArtist() {
    ShareService.shareProfile(
      username: widget.artistName,
      displayName: widget.artistName,
    );
  }

  void _showArtistOptionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
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
              const SizedBox(height: 16),
              ListTile(
                leading:
                    const Icon(Icons.share_outlined, color: Color(0xFF514AED)),
                title: Text(
                  'Share ${widget.artistName}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Poppins',
                  ),
                ),
                subtitle: Text(
                  'Share artist link with friends',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _shareArtist();
                },
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: Icon(
                  _isFollowing
                      ? Icons.person_remove_outlined
                      : Icons.person_add_alt_1_rounded,
                  color: const Color(0xFF514AED),
                ),
                title: Text(
                  _isFollowing ? 'Unfollow artist' : 'Follow artist',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Poppins',
                  ),
                ),
                subtitle: Text(
                  _isFollowing
                      ? 'Stop seeing artist updates in your feed'
                      : 'Get updates and see this artist in your library',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  final targetId = _effectiveArtistId;
                  if (_isFollowing) {
                    setState(() => _isFollowing = false);
                    ArtistFollowService().unfollowArtist(targetId);
                    CookieService.show(
                      message: 'Unfollowed ${widget.artistName}',
                      icon: Icons.person_remove_outlined,
                      iconColor: Colors.white70,
                    );
                  } else {
                    setState(() => _isFollowing = true);
                    ArtistFollowService().followArtist(
                      artistId: targetId,
                      artistName: widget.artistName,
                      artistImage: _artistImage.isNotEmpty
                          ? _artistImage
                          : widget.artistImage,
                    );
                    CookieService.show(
                      message: 'Following ${widget.artistName}',
                      icon: Icons.check_circle_rounded,
                      iconColor: const Color(0xFF514AED),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
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
                    SizedBox(height: topPadding + 12),
                    _buildTopBar(),
                    const SizedBox(height: 24),
                    _buildArtistHeader(),
                    const SizedBox(height: 40),
                    _buildTabs(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              if (_isLoading)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverToBoxAdapter(
                    child: _buildSkeletonCard(count: 8),
                  ),
                )
              else if (_selectedTab == 0)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverToBoxAdapter(
                    child: _buildPopularSongsCard(),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: _buildAlbumTab(),
                ),
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
          GestureDetector(
            onTap: _showArtistOptionsMenu,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.more_vert_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtistHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _buildArtistImage(),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildArtistName(),
                const SizedBox(height: 4),
                _buildMonthlyListeners(),
                const SizedBox(height: 16),
                _buildActionButtons(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtistImage() {
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
        child: _artistImage.isNotEmpty
            ? CachedImage(
                _artistImage,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholderImage(),
              )
            : _buildPlaceholderImage(),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: const Icon(
        Icons.person,
        color: Colors.white38,
        size: 60,
      ),
    );
  }

  Widget _buildArtistName() {
    return Text(
      widget.artistName,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.bold,
        fontFamily: 'Poppins',
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildMonthlyListeners() {
    if (_isLoading) {
      return Container(
        width: 120,
        height: 14,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }
    final fansFormatted = _formatFans(_nbFan);
    return Text(
      _nbFan == 1
          ? '$fansFormatted monthly listener'
          : '$fansFormatted monthly listeners',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.6),
        fontSize: 12,
        fontFamily: 'Poppins',
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        _buildFollowButton(),
        const SizedBox(width: 16),
        _buildShuffleButton(),
        const SizedBox(width: 16),
        _buildPlayButton(),
      ],
    );
  }

  Widget _buildFollowButton() {
    return GestureDetector(
      onTap: () {
        final targetId = _effectiveArtistId;
        if (_isFollowing) {
          setState(() => _isFollowing = false);
          ArtistFollowService().unfollowArtist(targetId);
          CookieService.show(
            message: 'Unfollowed ${widget.artistName}',
            icon: Icons.person_remove_outlined,
            iconColor: Colors.white70,
          );
        } else {
          setState(() => _isFollowing = true);
          ArtistFollowService().followArtist(
            artistId: targetId,
            artistName: widget.artistName,
            artistImage:
                _artistImage.isNotEmpty ? _artistImage : widget.artistImage,
          );
          CookieService.show(
            message: 'Following ${widget.artistName}',
            icon: Icons.check_circle_rounded,
            iconColor: const Color(0xFF514AED),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: _isFollowing ? const Color(0xFF514AED) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isFollowing ? const Color(0xFF514AED) : Colors.white54,
            width: 1,
          ),
        ),
        child: Text(
          _isFollowing ? 'Following' : 'Follow',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFamily: 'Poppins',
          ),
        ),
      ),
    );
  }

  Widget _buildShuffleButton() {
    return GestureDetector(
      onTap: () {
        if (_topTracks.isNotEmpty) {
          final shuffled = List<SearchResult>.from(_topTracks)..shuffle();
          final playback = PlaybackService();
          playback.setQueue(shuffled, 0);
          playback.playTrack(shuffled.first, fromQueue: true);
        }
      },
      child: const Icon(
        Icons.shuffle,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  Widget _buildPlayButton() {
    return GestureDetector(
      onTap: () {
        if (_topTracks.isNotEmpty) {
          final playback = PlaybackService();
          playback.setQueue(_topTracks, 0);
          playback.playTrack(_topTracks.first, fromQueue: true);
        }
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Color(0xFF514AED),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() => _selectedTab = 0),
            child: Column(
              children: [
                Text(
                  'Popular',
                  style: TextStyle(
                    color: _selectedTab == 0
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.5),
                    fontSize: 15,
                    fontWeight:
                        _selectedTab == 0 ? FontWeight.bold : FontWeight.w500,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 2,
                  width: 40,
                  decoration: BoxDecoration(
                    color: _selectedTab == 0
                        ? const Color(0xFF514AED)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          GestureDetector(
            onTap: () => setState(() => _selectedTab = 1),
            child: Column(
              children: [
                Text(
                  'Album',
                  style: TextStyle(
                    color: _selectedTab == 1
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.5),
                    fontSize: 15,
                    fontWeight:
                        _selectedTab == 1 ? FontWeight.bold : FontWeight.w500,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 2,
                  width: 40,
                  decoration: BoxDecoration(
                    color: _selectedTab == 1
                        ? const Color(0xFF514AED)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _shareArtist,
            child: const Icon(
              Icons.ios_share_rounded,
              color: Colors.white54,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  String _formatPlayCount(int count) {
    return count.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }

  Widget _buildPopularSongsCard() {
    if (_topTracks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(
          child: Text(
            'No popular songs found',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 14,
              fontFamily: 'Poppins',
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _topTracks.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 1,
          color: Colors.white.withValues(alpha: 0.04),
          indent: 96,
          endIndent: 16,
        ),
        itemBuilder: (context, i) {
          final track = _topTracks[i];
          final subtitle = track.rank > 0
              ? '${_formatPlayCount(track.rank)} plays'
              : (track.duration.isNotEmpty ? track.duration : '');

          return SearchResultItem(
            result: track,
            allResults: _topTracks,
            recordRecentSearch: false,
            trackNumber: i + 1,
            showTypeBadge: false,
            customSubtitle: subtitle,
            playbackContext: PlaybackContext(
              type: 'artist',
              id: widget.artistId,
              title: widget.artistName,
              artistName: widget.artistName,
              artistId: widget.artistId,
              coverImage: widget.artistImage,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSkeletonCard({int count = 8}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: count,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 1,
          color: Colors.white.withValues(alpha: 0.04),
          indent: 96,
          endIndent: 16,
        ),
        itemBuilder: (_, __) => const SkeletonSearchResult(showNumber: true),
      ),
    );
  }

  Widget _buildAlbumTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _isGridView = !_isGridView),
                child: Icon(
                  _isGridView ? Icons.view_list : Icons.grid_view,
                  color: Colors.white54,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_albums.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  'No albums found',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 14,
                      fontFamily: 'Poppins'),
                ),
              ),
            )
          else if (_isGridView)
            _buildAlbumGrid()
          else
            _buildAlbumList(),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildAlbumList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _albums.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final album = _albums[index];
        return _buildAlbumCard(album, isGrid: false);
      },
    );
  }

  Widget _buildAlbumGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: 0.72,
      ),
      itemCount: _albums.length,
      itemBuilder: (context, index) {
        final album = _albums[index];
        return _buildAlbumCard(album, isGrid: true);
      },
    );
  }

  Widget _buildAlbumCard(Map<String, dynamic> album, {required bool isGrid}) {
    final title = album['title'] ?? '';
    final image = album['image'] ?? '';
    final year = album['year'] ?? '';
    final nbTracks = album['nbTracks'] ?? 0;

    return GestureDetector(
      onTap: () {
        Navigator.of(context, rootNavigator: true).push(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 400),
            reverseTransitionDuration: const Duration(milliseconds: 350),
            pageBuilder: (context, animation, secondaryAnimation) =>
                AlbumDetailScreen(
              albumId: album['id']?.toString() ?? '',
              albumTitle: title,
              albumImage: image,
              artistName: widget.artistName,
              artistId: widget.artistId,
            ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              final fadeAnimation = CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOutCubic,
              );
              return FadeTransition(
                opacity: fadeAnimation,
                child: child,
              );
            },
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Hero(
            tag: 'album_cover_${album['id']}',
            flightShuttleBuilder:
                (flightContext, animation, direction, fromContext, toContext) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOutCubic,
              );
              final borderRadiusTween = BorderRadiusTween(
                begin: direction == HeroFlightDirection.push
                    ? BorderRadius.circular(6)
                    : BorderRadius.zero,
                end: direction == HeroFlightDirection.push
                    ? BorderRadius.zero
                    : BorderRadius.circular(6),
              );
              return AnimatedBuilder(
                animation: curved,
                builder: (context, child) {
                  return ClipRRect(
                    borderRadius:
                        borderRadiusTween.evaluate(curved) ?? BorderRadius.zero,
                    child: child,
                  );
                },
                child: Container(
                  color: const Color(0xFF2A2A2A),
                  child: image.toString().isNotEmpty
                      ? CachedImage(
                          image.toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.album,
                            color: Colors.white38,
                            size: 40,
                          ),
                        )
                      : const Icon(
                          Icons.album,
                          color: Colors.white38,
                          size: 40,
                        ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: AspectRatio(
                aspectRatio: isGrid ? 1 : 16 / 9,
                child: Container(
                  color: const Color(0xFF2A2A2A),
                  child: image.toString().isNotEmpty
                      ? CachedImage(
                          image.toString(),
                          fit: BoxFit.cover,
                          alignment:
                              isGrid ? Alignment.center : Alignment.topCenter,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.album,
                            color: Colors.white38,
                            size: 40,
                          ),
                        )
                      : const Icon(
                          Icons.album,
                          color: Colors.white38,
                          size: 40,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: 'Poppins',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (year.toString().isNotEmpty) year.toString(),
              // Deezer's album LIST has no per-album track count — only show
              // it when actually known, never a bogus "0 songs".
              if ((album['nbTracks'] ?? 0) > 0) '$nbTracks songs',
            ].join(' \u00b7 '),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }
}
