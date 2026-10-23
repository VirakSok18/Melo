import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/vibe_service.dart';
import '../../services/search_service.dart';
import '../../services/playback_service.dart';
import '../../services/youtube_service.dart';
import '../../services/background_prefetch_service.dart';
import '../../services/playlist_service.dart';
import '../../services/cookie_service.dart';
import '../../services/share_service.dart';
import '../../services/premium_service.dart';

import '../../widgets/skeleton_loader.dart';
import '../search_screen/mini_player.dart';
import '../search_screen/search_result_item.dart';
import '../library_screen/playlist_detail_screen.dart';

class VibePlaylistScreen extends StatefulWidget {
  final String genre;
  final Color cardColor;
  final List<Map<String, dynamic>>? initialTracks;
  final String? playlistName;

  const VibePlaylistScreen({
    super.key,
    required this.genre,
    required this.cardColor,
    this.initialTracks,
    this.playlistName,
  });

  @override
  State<VibePlaylistScreen> createState() => _VibePlaylistScreenState();
}

class _VibePlaylistScreenState extends State<VibePlaylistScreen> {
  List<Map<String, dynamic>> _tracks = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSaved = false;
  String? _savedPlaylistId;

  static bool _hasValidSongId(dynamic item) {
    if (item is! Map<String, dynamic>) return false;
    final rawId = (item['deezerId'] ?? item['id'] ?? item['trackId'] ?? '')
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

  @override
  void initState() {
    super.initState();
    if (widget.initialTracks != null && widget.initialTracks!.isNotEmpty) {
      _tracks = List<Map<String, dynamic>>.from(widget.initialTracks!)
          .where(_hasValidSongId)
          .toList();
      _isLoading = false;
      _checkIfAlreadySaved();
      _prefetchTracks();
    } else {
      _loadPlaylist();
    }
  }

  void _checkIfAlreadySaved() {
    if (_tracks.isEmpty) {
      _isSaved = false;
      _savedPlaylistId = null;
      return;
    }
    final name = widget.playlistName ?? '${widget.genre} for you';
    final playlists = PlaylistService().playlists;
    final matches = playlists.where((p) => p.name == name).toList();
    if (matches.isEmpty) {
      setState(() {
        _isSaved = false;
        _savedPlaylistId = null;
      });
      return;
    }

    // Check if any matched playlist in library actually contains the exact songs in this daily mix
    UserPlaylist? exactMatch;
    final currentTitles = _tracks
        .map((t) => (t['title'] ?? '').toString().toLowerCase().trim())
        .toSet();

    for (final p in matches) {
      if (p.songs.isEmpty && currentTitles.isEmpty) continue;
      final savedTitles =
          p.songs.map((s) => s.title.toLowerCase().trim()).toSet();
      // If at least 90% of songs match (essentially the same playlist), consider saved
      final intersection = currentTitles.intersection(savedTitles).length;
      if (currentTitles.isNotEmpty &&
          intersection / currentTitles.length >= 0.9) {
        exactMatch = p;
        break;
      }
    }

    if (mounted) {
      setState(() {
        _isSaved = exactMatch != null;
        _savedPlaylistId = exactMatch?.id;
      });
    } else {
      _isSaved = exactMatch != null;
      _savedPlaylistId = exactMatch?.id;
    }
  }

  void _shufflePlay() {
    final validTracks = _tracks.where(_hasValidSongId).toList();
    if (validTracks.isEmpty) return;
    final shuffled = List<Map<String, dynamic>>.from(validTracks)..shuffle();
    final queue = shuffled
        .map(_toSearchResult)
        .where((s) => s.id.isNotEmpty && s.id != '0')
        .toList();
    if (queue.isEmpty) return;

    final playback = PlaybackService();
    playback.setQueue(queue, 0);
    playback.playTrack(queue.first, fromQueue: true);
  }

  List<Map<String, dynamic>> _interleaveByArtist(
      List<Map<String, dynamic>> list) {
    if (list.length <= 2) return list;
    final byArtist = <String, List<Map<String, dynamic>>>{};
    for (final track in list) {
      final artist = (track['artist'] ?? '').toString().toLowerCase();
      byArtist.putIfAbsent(artist, () => []).add(track);
    }
    final artistKeys = byArtist.keys.toList();
    final result = <Map<String, dynamic>>[];
    bool added = true;
    int round = 0;
    while (added && result.length < list.length) {
      added = false;
      for (final key in artistKeys) {
        final artistTracks = byArtist[key]!;
        if (round < artistTracks.length) {
          result.add(artistTracks[round]);
          added = true;
        }
      }
      round++;
    }
    return result;
  }

  void _prefetchTracks() {
    final tracks = _tracks
        .where(_hasValidSongId)
        .map(_toSearchResult)
        .where((s) => s.id.isNotEmpty && s.id != '0')
        .toList();
    if (tracks.isNotEmpty) {
      YouTubeService.prefetchStreamUrls(tracks);
      BackgroundPrefetchService.instance
          .enqueueTracks(tracks, tag: 'vibe_playlist');
    }
  }

  Future<void> _loadPlaylist({bool force = false}) async {
    final tracks = await VibeService.getPlaylist(widget.genre, force: force);
    if (mounted) {
      final validTracks = tracks.where(_hasValidSongId).toList();
      final interleaved = _interleaveByArtist(validTracks);
      setState(() {
        _tracks = interleaved;
        _isLoading = false;
      });
      _checkIfAlreadySaved();
      _prefetchTracks();
    }
  }

  void _playTrack(int index) {
    final validTracks = _tracks.where(_hasValidSongId).toList();
    if (index >= validTracks.length) return;

    final queue = validTracks
        .map(_toSearchResult)
        .where((s) => s.id.isNotEmpty && s.id != '0')
        .toList();
    if (queue.isEmpty || index >= queue.length) return;

    if (!PremiumService().checkAndConsumeTrackSwitch(
      context,
      newTitle: queue[index].title,
      newArtist: queue[index].artist,
      newId: queue[index].id,
    )) {
      return;
    }

    final playback = PlaybackService();
    playback.setQueue(queue, index);
    playback.playTrack(queue[index], fromQueue: true);
  }

  void _playAll() {
    if (_tracks.isEmpty) return;
    _playTrack(0);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final imageHeight = screenSize.width;

    final coverImage = (_tracks.isNotEmpty &&
            (_tracks.first['image']?.toString().isNotEmpty ?? false))
        ? _tracks.first['image'].toString()
        : (widget.initialTracks != null &&
                widget.initialTracks!.isNotEmpty &&
                (widget.initialTracks!.first['image']?.toString().isNotEmpty ??
                    false))
            ? widget.initialTracks!.first['image'].toString()
            : null;

    final coverProvider = PlaylistService.coverImageProvider(coverImage);

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
                          if (coverProvider != null)
                            Image(
                              image: coverProvider,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: widget.cardColor),
                            )
                          else
                            Container(color: widget.cardColor),
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
                                    _isLoading
                                        ? 'LOADING...'
                                        : '${_tracks.length} SONGS',
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
                                  widget.playlistName ??
                                      '${widget.genre} for you',
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
                                          offset: Offset(0, 1)),
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
                                final isThisPlaylistPlaying =
                                    currentTrack != null &&
                                        _tracks.any((t) =>
                                            t['title']?.toString() ==
                                            currentTrack.title);
                                return GestureDetector(
                                  onTap: () {
                                    if (isThisPlaylistPlaying) {
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
                                      isThisPlaylistPlaying &&
                                              playback.isPlaying
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
                    const SizedBox(height: 16),
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

  Future<void> _saveToLibrary() async {
    if (_tracks.isEmpty) {
      CookieService.show(
        message: 'No songs to save',
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
      final name = widget.playlistName ?? '${widget.genre} for you';
      final coverImage =
          _tracks.isNotEmpty ? _tracks.first['image']?.toString() : null;

      final playlist = await PlaylistService().createPlaylist(
        name,
        coverImage: coverImage,
      );

      final songsToAdd = _tracks
          .map((s) => PlaylistSong(
                trackId: (s['deezerId'] ?? s['id'] ?? '').toString(),
                title: s['title']?.toString() ?? '',
                artist: s['artist']?.toString() ?? '',
                image: s['image']?.toString() ?? '',
                duration: s['duration']?.toString() ?? '',
                artistId: s['artistId']?.toString() ?? '',
                artistImage: s['artistImage']?.toString() ?? '',
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
          message: 'Saved to library!',
          icon: Icons.check_circle_rounded,
          iconColor: const Color(0xFF514AED),
        );
      }
    } catch (e) {
      debugPrint('[VibePlaylist] Save to library error: $e');
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

  void _sharePlaylist() {
    final title = widget.playlistName ?? '${widget.genre} for you';
    if (_savedPlaylistId != null) {
      ShareService.sharePlaylist(
        playlistId: _savedPlaylistId!,
        title: title,
      );
    } else {
      final text =
          '$title — ${_tracks.length} songs on Melo\n${ShareService.baseUrl}';
      Clipboard.setData(ClipboardData(text: text));
      CookieService.show(
        message: 'Playlist link copied to clipboard',
        icon: Icons.copy_rounded,
        iconColor: const Color(0xFF514AED),
      );
    }
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
              flex: 4,
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
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _isSaved ? 'In Library' : 'Add to Library',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _isSaved
                                  ? const Color(0xFF514AED)
                                  : Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
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
              flex: 3,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.zero,
                  onTap: _shufflePlay,
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shuffle_rounded,
                          size: 15,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Shuffle',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
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
            Container(
              width: 1,
              height: 18,
              color: Colors.white.withValues(alpha: 0.12),
            ),
            Expanded(
              flex: 3,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius:
                      const BorderRadius.horizontal(right: Radius.circular(21)),
                  onTap: _sharePlaylist,
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.share_outlined,
                          size: 15,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Share',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
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

  SearchResult _toSearchResult(Map<String, dynamic> track) {
    final rawId = (track['deezerId'] ?? track['id'] ?? track['trackId'] ?? '')
        .toString()
        .trim();
    return SearchResult(
      type: 'song',
      id: rawId,
      title: track['title']?.toString() ?? '',
      artist: track['artist']?.toString() ?? '',
      artistId: track['artistId']?.toString() ?? '',
      artistImage: track['artistImage']?.toString() ?? '',
      image: track['image']?.toString() ?? '',
      duration: track['duration']?.toString() ?? '',
      nbFan: 0,
      previewUrl:
          track['preview']?.toString() ?? track['previewUrl']?.toString() ?? '',
    );
  }

  Widget _buildSongsCard() {
    final searchTracks = _tracks.map((t) => _toSearchResult(t)).toList();
    final coverImage = (_tracks.isNotEmpty &&
            (_tracks.first['image']?.toString().isNotEmpty ?? false))
        ? _tracks.first['image'].toString()
        : null;

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
          return SearchResultItem(
            result: track,
            allResults: searchTracks,
            recordRecentSearch: false,
            trackNumber: i + 1,
            showTypeBadge: false,
            customSubtitle: track.artist,
            playbackContext: PlaybackContext(
              type: 'vibe',
              id: widget.genre,
              title: widget.playlistName ?? '${widget.genre} Vibe',
              coverImage: coverImage,
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
