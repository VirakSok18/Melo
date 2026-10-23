import '../../widgets/cached_image.dart';
import 'package:flutter/material.dart';
import '../../services/artist_service.dart';
import '../../services/search_service.dart';
import '../../services/playback_service.dart';
import '../../services/playlist_service.dart';
import '../../services/premium_service.dart';
import '../../services/download_service.dart';
import '../../services/share_service.dart';
import '../../services/cookie_service.dart';
import '../library_screen/playlist_detail_screen.dart';

import '../../widgets/skeleton_loader.dart';
import '../../services/youtube_service.dart';
import '../search_screen/mini_player.dart';
import '../search_screen/search_result_item.dart';

class AlbumDetailScreen extends StatefulWidget {
  final String albumId;
  final String albumTitle;
  final String albumImage;
  final String artistName;
  final String artistId;

  const AlbumDetailScreen({
    super.key,
    required this.albumId,
    required this.albumTitle,
    required this.albumImage,
    required this.artistName,
    required this.artistId,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  Map<String, dynamic>? _albumInfo;
  List<Map<String, dynamic>> _tracks = [];
  bool _isLoading = true;
  bool _isSaved = false;
  bool _isSaving = false;
  String? _savedPlaylistId;

  @override
  void initState() {
    super.initState();
    _loadAlbumData();
    _checkIfSaved();
  }

  void _checkIfSaved() {
    final title = widget.albumTitle;
    final playlist =
        PlaylistService().playlists.where((p) => p.name == title).firstOrNull;
    if (playlist != null) {
      _isSaved = true;
      _savedPlaylistId = playlist.id;
    }
  }

  String get _effectiveAlbumCover {
    if (widget.albumImage.trim().isNotEmpty) {
      return widget.albumImage.trim();
    }
    final infoCover = _albumInfo?['bigImage'] ??
        _albumInfo?['cover_big'] ??
        _albumInfo?['cover_medium'] ??
        _albumInfo?['image'] ??
        _albumInfo?['cover_xl'] ??
        _albumInfo?['xlImage'];
    if (infoCover != null && infoCover.toString().trim().isNotEmpty) {
      return infoCover.toString().trim();
    }
    return '';
  }

  List<SearchResult> _getSearchTracks() {
    final cover = _effectiveAlbumCover;
    return _tracks.map((t) {
      final trackId = (t['deezerId'] ?? t['id'] ?? '').toString();
      final title = t['title']?.toString() ?? '';
      final artist = (t['artist']?.toString() ?? '').isNotEmpty
          ? t['artist'].toString()
          : widget.artistName;
      final artistId = (t['artistId']?.toString() ?? '').isNotEmpty
          ? t['artistId'].toString()
          : widget.artistId;
      final dur = t['duration']?.toString() ?? '';
      final rank = (t['rank'] is num) ? (t['rank'] as num).toInt() : 0;

      return SearchResult(
        type: 'song',
        id: trackId,
        title: title,
        artist: artist,
        artistId: artistId,
        artistImage: t['artistImage']?.toString() ?? '',
        image: cover,
        duration: dur,
        nbFan: rank,
        previewUrl: t['preview']?.toString() ?? '',
      );
    }).toList();
  }

  Future<void> _loadAlbumData() async {
    final infoFuture = ArtistService.getAlbumInfo(widget.albumId);
    final tracksFuture = ArtistService.getAlbumTracks(widget.albumId);
    final results = await Future.wait([infoFuture, tracksFuture]);
    if (mounted) {
      setState(() {
        _albumInfo = results[0] as Map<String, dynamic>?;
        _tracks = results[1] as List<Map<String, dynamic>>;
        _isLoading = false;
      });
      YouTubeService.prefetchStreamUrls(_getSearchTracks());
    }
  }

  String _formatPlayCount(int count) {
    return count.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }

  void _playTrack(int index) {
    final queue = _getSearchTracks();
    if (index >= queue.length) return;
    if (!PremiumService().checkAndConsumeTrackSwitch(
      context,
      newTitle: queue[index].title,
      newArtist: queue[index].artist,
      newId: queue[index].id,
    )) {
      return;
    }
    final playback = PlaybackService();
    playback.setQueue(
      queue,
      index,
      context: PlaybackContext(
        type: 'album',
        id: widget.albumId,
        title: widget.albumTitle,
        coverImage: _effectiveAlbumCover,
        artistName: widget.artistName,
        artistId: widget.artistId,
      ),
    );
    playback.playTrack(queue[index], fromQueue: true);
  }

  void _playAll() {
    if (_tracks.isEmpty) return;
    _playTrack(0);
  }

  Future<void> _saveToLibrary() async {
    if (_tracks.isEmpty) {
      CookieService.show(
        message: 'No songs in album to save',
        icon: Icons.info_outline,
        iconColor: Colors.amber,
      );
      return;
    }

    if (_isSaved && _savedPlaylistId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlaylistDetailScreen(playlistId: _savedPlaylistId!),
        ),
      );
      return;
    }

    if (_isSaving) return;

    setState(() => _isSaving = true);
    try {
      final name = _albumInfo?['title'] ?? widget.albumTitle;
      final coverImage = _effectiveAlbumCover;

      final playlist = await PlaylistService().createPlaylist(
        name,
        coverImage: coverImage.isNotEmpty ? coverImage : null,
      );

      final songsToAdd = _tracks
          .map((s) => PlaylistSong(
                trackId: (s['deezerId'] ?? s['id'] ?? '').toString(),
                title: s['title']?.toString() ?? '',
                artist: s['artist']?.toString() ?? widget.artistName,
                image: _effectiveAlbumCover,
                duration: s['duration']?.toString() ?? '',
                artistId: widget.artistId,
                artistImage: '',
              ))
          .toList();

      await PlaylistService().addSongs(playlist.id, songsToAdd);

      if (mounted) {
        setState(() {
          _isSaved = true;
          _isSaving = false;
          _savedPlaylistId = playlist.id;
        });
        CookieService.show(
          message: 'Saved album to library!',
          icon: Icons.check_circle_rounded,
          iconColor: const Color(0xFF514AED),
        );
      }
    } catch (e) {
      debugPrint('[AlbumDetail] Save to library error: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        CookieService.show(
          message: 'Failed to save to library',
          icon: Icons.error_outline_rounded,
          iconColor: Colors.redAccent,
        );
      }
    }
  }

  void _shareAlbum() {
    final title = _albumInfo?['title'] ?? widget.albumTitle;
    ShareService.sharePlaylist(
      playlistId: widget.albumId,
      title: title,
      creatorName: widget.artistName,
    );
  }

  void _downloadAllSongs() {
    if (!PremiumService().canDownloadOffline) {
      PremiumService.showUpsell(context, feature: 'Offline Music Downloads');
      return;
    }
    if (_tracks.isEmpty) {
      CookieService.show(
        message: 'No songs to download',
        icon: Icons.info_outline,
        iconColor: Colors.amber,
      );
      return;
    }

    final undownloaded = _tracks.where((t) {
      final trackId = (t['deezerId'] ?? t['id'] ?? '').toString();
      return !DownloadService.isDownloaded(trackId);
    }).toList();

    if (undownloaded.isEmpty) {
      CookieService.show(
        message: 'All album songs are already downloaded',
        icon: Icons.check_circle_rounded,
        iconColor: const Color(0xFF514AED),
      );
      return;
    }

    CookieService.show(
      message: 'Downloading ${undownloaded.length} songs in background...',
      icon: Icons.downloading_rounded,
      iconColor: const Color(0xFF514AED),
    );

    for (final t in undownloaded) {
      final trackId = (t['deezerId'] ?? t['id'] ?? '').toString();
      final title = t['title']?.toString() ?? '';
      final artist = t['artist']?.toString() ?? widget.artistName;
      final image = _effectiveAlbumCover;
      final durStr = t['duration']?.toString() ?? '';

      Duration dur = Duration.zero;
      if (durStr.isNotEmpty) {
        final parts = durStr.split(':');
        if (parts.length == 2) {
          dur = Duration(
              minutes: int.tryParse(parts[0]) ?? 0,
              seconds: int.tryParse(parts[1]) ?? 0);
        }
      }

      DownloadService.download(
        trackId: trackId,
        title: title,
        artist: artist,
        image: image,
        artistId: widget.artistId,
        artistImage: '',
        duration: dur,
      );
    }
  }

  void _showOptionsMenu() {
    final title = _albumInfo?['title'] ?? widget.albumTitle;
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
                  'Share "$title"',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Poppins',
                  ),
                ),
                subtitle: Text(
                  'Share album link with friends',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _shareAlbum();
                },
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.download_rounded,
                    color: Color(0xFF514AED)),
                title: const Text(
                  'Download album',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Poppins',
                  ),
                ),
                subtitle: Text(
                  'Save all songs to this phone for offline playback',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _downloadAllSongs();
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
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final bigImage = _effectiveAlbumCover;
    final title = _albumInfo?['title'] ?? widget.albumTitle;
    final nbTracks = _albumInfo?['nbTracks'] ?? _tracks.length;
    final imageHeight = screenSize.width;

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
                    SizedBox(
                      width: double.infinity,
                      height: imageHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Hero(
                            tag: 'album_cover_${widget.albumId}',
                            flightShuttleBuilder: (flightContext, animation,
                                direction, fromContext, toContext) {
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
                                        borderRadiusTween.evaluate(curved) ??
                                            BorderRadius.zero,
                                    child: child,
                                  );
                                },
                                child: Container(
                                  color: const Color(0xFF2A2A2A),
                                  child: bigImage.toString().isNotEmpty
                                      ? CachedImage(
                                          bigImage.toString(),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                            Icons.album,
                                            color: Colors.white38,
                                            size: 60,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.album,
                                          color: Colors.white38,
                                          size: 60,
                                        ),
                                ),
                              );
                            },
                            child: ClipRRect(
                              child: bigImage.toString().isNotEmpty
                                  ? CachedImage(
                                      bigImage.toString(),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: const Color(0xFF2A2A2A),
                                        child: const Icon(Icons.album,
                                            color: Colors.white38, size: 60),
                                      ),
                                    )
                                  : Container(
                                      color: const Color(0xFF2A2A2A),
                                      child: const Icon(Icons.album,
                                          color: Colors.white38, size: 60),
                                    ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.3),
                                  Colors.transparent,
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.8),
                                  const Color(0xFF191919),
                                ],
                                stops: const [0.0, 0.15, 0.5, 0.85, 1.0],
                              ),
                            ),
                          ),
                          Positioned(
                            top: topPadding + 12,
                            left: 16,
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
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
                          ),
                          Positioned(
                            top: topPadding + 12,
                            right: 16,
                            child: GestureDetector(
                              onTap: _showOptionsMenu,
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
                          ),
                          Positioned(
                            left: 20,
                            right: 80,
                            bottom: 20,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.15),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    '$nbTracks SONGS',
                                    style: const TextStyle(
                                      color: Color(0xFFA5A0FF),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  title.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Poppins',
                                    height: 1.2,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black87,
                                        blurRadius: 8,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            right: 20,
                            bottom: 20,
                            child: ListenableBuilder(
                              listenable: PlaybackService(),
                              builder: (context, _) {
                                final playback = PlaybackService();
                                final currentTrack = playback.currentTrack;
                                final isThisAlbumPlaying = currentTrack !=
                                        null &&
                                    _tracks.any((t) =>
                                        t['id']?.toString() == currentTrack.id);
                                return GestureDetector(
                                  onTap: () {
                                    if (isThisAlbumPlaying) {
                                      PlaybackService().togglePlayPause();
                                    } else {
                                      _playAll();
                                    }
                                  },
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFF514AED),
                                    ),
                                    child: Icon(
                                      isThisAlbumPlaying && playback.isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildActionButtons(),
                    const SizedBox(height: 16),
                    _buildSongsSection(),
                    const SizedBox(height: 100),
                  ],
                ),
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

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(21),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius:
                      const BorderRadius.horizontal(left: Radius.circular(21)),
                  onTap: _isSaving ? null : _saveToLibrary,
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isSaving)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF514AED),
                            ),
                          )
                        else
                          Icon(
                            _isSaved
                                ? Icons.check_circle_rounded
                                : Icons.add_rounded,
                            color: _isSaved
                                ? const Color(0xFF514AED)
                                : Colors.white.withValues(alpha: 0.8),
                            size: 16,
                          ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _isSaved ? 'In Library' : 'Add to library',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _isSaved
                                  ? const Color(0xFF514AED)
                                  : Colors.white.withValues(alpha: 0.8),
                              fontSize: 12.5,
                              fontWeight:
                                  _isSaved ? FontWeight.w600 : FontWeight.w500,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: 1,
              height: 18,
              color: Colors.white.withValues(alpha: 0.12),
            ),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius:
                      const BorderRadius.horizontal(right: Radius.circular(21)),
                  onTap: _shareAlbum,
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.ios_share_rounded,
                          color: Colors.white.withValues(alpha: 0.8),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Share Album',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
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
        ),
      ),
    );
  }

  Widget _buildSongsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Songs',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
              ),
            ),
          ),
          if (_isLoading)
            _buildSkeletonCard()
          else if (_tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  'No tracks found',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 14,
                      fontFamily: 'Poppins'),
                ),
              ),
            )
          else
            _buildSongsCard(),
        ],
      ),
    );
  }

  Widget _buildSongsCard() {
    final searchTracks = _getSearchTracks();

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
        itemCount: searchTracks.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 1,
          color: Colors.white.withValues(alpha: 0.04),
          indent: 96,
          endIndent: 16,
        ),
        itemBuilder: (context, i) {
          final track = searchTracks[i];
          final hasFeature = track.artist.isNotEmpty &&
              track.artist.toLowerCase().trim() !=
                  widget.artistName.toLowerCase().trim();
          final playCountStr = track.nbFan > 0
              ? '${_formatPlayCount(track.nbFan)} plays'
              : (track.duration.isNotEmpty ? track.duration : '');
          final subtitle = hasFeature
              ? (playCountStr.isNotEmpty
                  ? '${track.artist} \u00b7 $playCountStr'
                  : track.artist)
              : playCountStr;

          return SearchResultItem(
            result: track,
            allResults: searchTracks,
            recordRecentSearch: false,
            trackNumber: i + 1,
            showTypeBadge: false,
            customSubtitle: subtitle,
            playbackContext: PlaybackContext(
              type: 'album',
              id: widget.albumId,
              title: widget.albumTitle,
              coverImage: _effectiveAlbumCover,
              artistName: widget.artistName,
              artistId: widget.artistId,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSkeletonCard({int count = 6}) {
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
}
