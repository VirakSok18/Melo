import '../../widgets/cached_image.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/download_service.dart';
import '../../services/search_service.dart';
import '../../services/playback_service.dart';
import '../../widgets/now_playing_badge.dart';
import '../../widgets/song_options_modal.dart';
import '../search_screen/mini_player.dart';

class DownloadedSongsScreen extends StatefulWidget {
  const DownloadedSongsScreen({super.key});

  @override
  State<DownloadedSongsScreen> createState() => _DownloadedSongsScreenState();
}

class _DownloadedSongsScreenState extends State<DownloadedSongsScreen> {
  List<Map<String, dynamic>> _songs = [];
  bool _isLoading = true;
  int _totalSize = 0;

  @override
  void initState() {
    super.initState();
    _songs = DownloadService.getAllSongsIncludingInProgress();
    _isLoading = false;
    _totalSize = DownloadService.getTotalSizeSync();
    _refreshFromNetwork();

    // Listen for download progress changes
    DownloadService.downloadCountNotifier.addListener(_onDownloadChanged);
    DownloadService.onUpdate.addListener(_onDownloadChanged);
  }

  @override
  void dispose() {
    DownloadService.downloadCountNotifier.removeListener(_onDownloadChanged);
    DownloadService.onUpdate.removeListener(_onDownloadChanged);
    super.dispose();
  }

  void _onDownloadChanged() {
    if (mounted) {
      setState(() {
        _songs = DownloadService.getAllSongsIncludingInProgress();
        _totalSize = DownloadService.getTotalSizeSync();
      });
    }
  }

  Future<void> _refreshFromNetwork() async {
    await DownloadService.getDownloadedSongs(force: true);
    if (mounted) {
      setState(() {
        _songs = DownloadService.getAllSongsIncludingInProgress();
        _totalSize = DownloadService.getTotalSizeSync();
      });
    }
  }

  void _playTrack(int index) {
    if (index >= _songs.length) return;
    final queue = _songs
        .map((s) => SearchResult(
              type: 'song',
              id: s['trackId'] ?? '',
              title: s['title'] ?? '',
              artist: s['artist'] ?? '',
              artistId: s['artistId'] ?? '',
              artistImage: s['artistImage'] ?? '',
              image: s['image'] ?? '',
              duration: '',
              nbFan: 0,
              previewUrl: '',
              filePath: DownloadService.getLocalPathSync(s['trackId'] ?? ''),
            ))
        .toList();
    final playback = PlaybackService();
    playback.setQueue(
      queue,
      index,
      context:
          const PlaybackContext(type: 'downloaded', title: 'Downloaded Songs'),
    );
    playback.playTrack(queue[index], fromQueue: true);
  }

  void _playAll() {
    if (_songs.isEmpty) return;
    _playTrack(0);
  }

  void _shufflePlay() {
    if (_songs.isEmpty) return;
    final shuffled = List<Map<String, dynamic>>.from(_songs)..shuffle();
    final queue = shuffled
        .map((s) => SearchResult(
              type: 'song',
              id: s['trackId'] ?? '',
              title: s['title'] ?? '',
              artist: s['artist'] ?? '',
              artistId: s['artistId'] ?? '',
              artistImage: s['artistImage'] ?? '',
              image: s['image'] ?? '',
              duration: '',
              nbFan: 0,
              previewUrl: '',
              filePath: DownloadService.getLocalPathSync(s['trackId'] ?? ''),
            ))
        .toList();
    final playback = PlaybackService();
    playback.setQueue(
      queue,
      0,
      context:
          const PlaybackContext(type: 'downloaded', title: 'Downloaded Songs'),
    );
    playback.playTrack(queue.first, fromQueue: true);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
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
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xFF514AED),
                                  Color(0xFF3A3599),
                                ],
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
                            top: 0,
                            bottom: 0,
                            left: 16,
                            right: 16,
                            child: Align(
                              alignment: const Alignment(0, -0.15),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.download_rounded,
                                    color: Colors.white,
                                    size: 56,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Downloaded',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Poppins',
                                      shadows: [
                                        Shadow(
                                            color: Colors.black,
                                            blurRadius: 12,
                                            offset: Offset(0, 1)),
                                        Shadow(
                                            color: Colors.black,
                                            blurRadius: 12,
                                            offset: Offset(0, -1)),
                                        Shadow(
                                            color: Colors.black,
                                            blurRadius: 12,
                                            offset: Offset(1, 0)),
                                        Shadow(
                                            color: Colors.black,
                                            blurRadius: 12,
                                            offset: Offset(-1, 0)),
                                      ],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  _isLoading
                                      ? Container(
                                          width: 80,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        )
                                      : Text(
                                          '${_songs.length} songs · ${DownloadService.formatFileSize(_totalSize)}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'Poppins',
                                            shadows: [
                                              Shadow(
                                                  color: Colors.black,
                                                  blurRadius: 12,
                                                  offset: Offset(0, 1)),
                                              Shadow(
                                                  color: Colors.black,
                                                  blurRadius: 12,
                                                  offset: Offset(0, -1)),
                                              Shadow(
                                                  color: Colors.black,
                                                  blurRadius: 12,
                                                  offset: Offset(1, 0)),
                                              Shadow(
                                                  color: Colors.black,
                                                  blurRadius: 12,
                                                  offset: Offset(-1, 0)),
                                            ],
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                ],
                              ),
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
                                        _songs.any((s) =>
                                            s['title']?.toString() ==
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
                  borderRadius: BorderRadius.circular(21),
                  onTap: _shufflePlay,
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shuffle_rounded,
                          color: Colors.white.withValues(alpha: 0.8),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Shuffle',
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Songs',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFamily: 'Poppins',
            ),
          ),
          if (_isLoading)
            const Column(
              children: [
                _SkeletonTrackRow(),
                _SkeletonTrackRow(),
                _SkeletonTrackRow(),
                _SkeletonTrackRow(),
                _SkeletonTrackRow(),
              ],
            )
          else if (_songs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  'No downloaded songs yet',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 14,
                      fontFamily: 'Poppins'),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.only(top: 16),
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _songs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) => _buildTrackItem(index),
            ),
        ],
      ),
    );
  }

  Widget _buildTrackItem(int index) {
    final song = _songs[index];
    final title = song['title']?.toString() ?? '';
    final artist = song['artist']?.toString() ?? '';
    final image = song['image']?.toString() ?? '';
    final trackId = song['trackId']?.toString() ?? '';
    final isDownloading = song['isDownloading'] == true;

    return TrackHighlight(
      trackId: trackId,
      title: title,
      artist: artist,
      builder: (context, isCurrent) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isDownloading ? null : () => _playTrack(index),
            onLongPress: () => _showMoreOptions(song),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: isCurrent
                        ? NowPlayingBars(playing: PlaybackService().isPlaying)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 15,
                              fontFamily: 'Poppins',
                            ),
                            textAlign: TextAlign.center,
                          ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: image.isNotEmpty
                                ? CachedImage(
                                    image,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _buildPlaceholder(),
                                  )
                                : _buildPlaceholder(),
                          ),
                        ),
                        if (isDownloading)
                          ValueListenableBuilder<double>(
                            valueListenable:
                                DownloadService.getProgressNotifier(trackId),
                            builder: (context, progress, _) {
                              return SizedBox(
                                width: 44,
                                height: 44,
                                child: CustomPaint(
                                  painter: _DownloadArcPainter(
                                    progress: progress.clamp(0.0, 1.0),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
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
                            fontSize: 15,
                            fontWeight:
                                isCurrent ? FontWeight.w600 : FontWeight.normal,
                            fontFamily: 'Poppins',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          artist,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontFamily: 'Poppins',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showMoreOptions(song),
                    child: Icon(
                      Icons.more_vert,
                      color: Colors.white.withValues(alpha: 0.4),
                      size: 20,
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

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: Icon(
        Icons.music_note,
        color: Colors.white.withValues(alpha: 0.2),
        size: 24,
      ),
    );
  }

  void _showMoreOptions(Map<String, dynamic> song) {
    final searchResult = SearchResult(
      type: 'song',
      id: song['trackId']?.toString() ?? song['id']?.toString() ?? '',
      title: song['title'] as String? ?? '',
      artist: song['artist'] as String? ?? '',
      artistId: song['artistId'] as String? ?? '',
      artistImage: song['artistImage'] as String? ?? '',
      image: song['image'] as String? ?? '',
      duration: song['duration'] as String? ?? '',
      nbFan: 0,
      previewUrl: '',
    );
    SongOptionsModal.show(context, searchResult);
  }
}

class _SkeletonTrackRow extends StatelessWidget {
  const _SkeletonTrackRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 15,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 140,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 100,
                  height: 11,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadArcPainter extends CustomPainter {
  final double progress;

  _DownloadArcPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // If not started yet, full dark circle
    if (progress <= 0) {
      final darkPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
      canvas.drawCircle(center, radius, darkPaint);
      return;
    }

    // If done, nothing to draw
    if (progress >= 1.0) return;

    // Dark filled arc covering the REMAINING (unread) portion
    final darkPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final rect = Rect.fromCircle(center: center, radius: radius);
    const startAngle = -pi / 2; // top
    final sweepAngle =
        -2 * pi * (1.0 - progress); // negative = clockwise cut-away

    canvas.drawArc(rect, startAngle, sweepAngle, true, darkPaint);
  }

  @override
  bool shouldRepaint(covariant _DownloadArcPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
