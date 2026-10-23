import '../../widgets/cached_image.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../widgets/now_playing_badge.dart';
import '../../services/playback_service.dart';
import '../../services/presence_service.dart';
import '../../services/search_service.dart';
import '../../services/lyrics_service.dart';
import '../../services/liked_songs_service.dart';
import '../../services/premium_service.dart';
import '../../services/artist_service.dart';
import '../../services/cookie_service.dart';
import '../artist_screen/artist_screen.dart';
import '../library_screen/playlist_detail_screen.dart';
import '../library_screen/liked_songs_screen.dart';
import '../library_screen/downloaded_songs_screen.dart';
import '../generate_screen/generated_playlist_screen.dart';
import '../album_screen/album_detail_screen.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/song_options_modal.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with TickerProviderStateMixin {
  late AnimationController _spinController;
  late AnimationController _armController;
  late AnimationController _expandController;
  final ScrollController _lyricsScrollController = ScrollController();
  late AnimationController _queueController;
  bool _isAdded = false;
  bool _isScrubbing = false;
  bool _isCoverScrubbing = false;
  bool _isAdjustingVolume = false;
  bool _showVolumeIndicator = false;
  double _coverDragStartX = 0.0;
  double _coverDragStartProgress = 0.0;
  double _coverDragStartY = 0.0;
  double _coverDragStartVolume = 1.0;
  Timer? _volumeIndicatorTimer;
  double _scrubProgress = 0.0;
  double _prevScrubProgress = 0.0;
  bool _didScrubMove = false;
  Offset? _scrubStartPosition;
  int _lastLyricScrollIndex = -1;
  bool _hasInitialLyricsScrolled = false;
  double _dragStartY = 0;
  String? _lastTrackKey;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );

    _armController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _queueController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    final playback = PlaybackService();
    if (playback.isPlaying) {
      _spinController.repeat();
      _armController.forward();
    }

    _checkLikedStatus();
    LikedSongsService.onUpdate.addListener(_checkLikedStatus);
    LikedSongsService().addListener(_checkLikedStatus);
  }

  void _openQueue() {
    _queueController.animateTo(1.0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic);
  }

  void _closeQueue() {
    _queueController.animateTo(0.0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic);
  }

  void _toggleQueue() {
    if (_queueController.value > 0.5) {
      _closeQueue();
    } else {
      _openQueue();
    }
  }

  void _checkLikedStatus() {
    final playback = PlaybackService();
    final track = playback.currentTrack;
    if (track != null && mounted) {
      final isNowLiked = LikedSongsService.isLiked(
        track.id,
        title: track.title,
        artist: track.artist,
      );
      if (_isAdded != isNowLiked) {
        setState(() {
          _isAdded = isNowLiked;
        });
      }
    }
  }

  @override
  void dispose() {
    LikedSongsService.onUpdate.removeListener(_checkLikedStatus);
    LikedSongsService().removeListener(_checkLikedStatus);
    _spinController.dispose();
    _armController.dispose();
    _expandController.dispose();
    _queueController.dispose();
    _lyricsScrollController.dispose();
    _volumeIndicatorTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final playback = PlaybackService();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      resizeToAvoidBottomInset: false,
      body: ListenableBuilder(
        listenable: playback,
        builder: (context, _) {
          final track = playback.currentTrack;
          if (track == null) return const SizedBox.shrink();

          // Detect track change and reset UI state
          final trackKey = '${track.id}_${track.title}_${track.artist}';
          if (trackKey != _lastTrackKey) {
            _lastTrackKey = trackKey;
            _lastLyricScrollIndex = -1;
            _hasInitialLyricsScrolled = false;
            _scrubProgress = 0.0;
            _prevScrubProgress = 0.0;
            _isScrubbing = false;
            _isCoverScrubbing = false;
            _isAdjustingVolume = false;
            _showVolumeIndicator = false;
            _isAdded = LikedSongsService.isLiked(
              track.id,
              title: track.title,
              artist: track.artist,
            );
          }

          if (playback.isPlaying && !_spinController.isAnimating) {
            _spinController.repeat();
            _armController.forward();
          } else if (!playback.isPlaying && _spinController.isAnimating) {
            _spinController.stop();
            _armController.reverse();
          }

          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: MediaQuery.of(context).size.height * 0.45,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF1A1A2E).withValues(alpha: 0.6),
                        const Color(0xFF0D0D0D),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      GestureDetector(
                        onVerticalDragStart: (details) {
                          _dragStartY = details.globalPosition.dy;
                        },
                        onVerticalDragEnd: (details) {
                          if (_dragStartY < 120 &&
                              details.primaryVelocity != null &&
                              details.primaryVelocity! > 300) {
                            Navigator.of(context).pop();
                          }
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildTopBar(),
                            _buildListenAlongSessionPill(),
                            const SizedBox(height: 14),
                            _buildDiskSection(playback, track.image),
                            const SizedBox(height: 4),
                            _buildTrackInfo(track),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildLyricsSection(track, playback),
                      const SizedBox(height: 20),
                      _buildControls(playback),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
              _buildQueueBackdrop(),
              _buildQueueSheet(playback),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
          const Expanded(
            child: Text(
              'Now Playing',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                fontFamily: 'Poppins',
                letterSpacing: 0.5,
              ),
            ),
          ),
          GestureDetector(
            onTap: _showMoreOptions,
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                Icons.more_horiz,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreOptions() {
    final track = PlaybackService().currentTrack;
    if (track == null) return;
    SongOptionsModal.show(
      context,
      track,
      showPlaybackSpeed: true,
      followCurrentTrack: true,
    );
    /* showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141419),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Playback speed',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins')),
                const SizedBox(height: 4),
                const Text('Changes speed for this and future songs',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontFamily: 'Poppins')),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
                    final isSelected = playback.speed == speed;
                    final label = speed == 1.0
                        ? 'Normal'
                        : '${speed.toString().replaceAll('.0', '')}×';
                    return ChoiceChip(
                      label: Text(label),
                      selected: isSelected,
                      selectedColor: const Color(0xFF514AED),
                      backgroundColor: const Color(0xFF26262B),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontFamily: 'Poppins',
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                      onSelected: (_) async {
                        await playback.setSpeed(speed);
                        setSheetState(() {});
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.more_horiz_rounded,
                      color: Colors.white70),
                  title: const Text('Song options',
                      style: TextStyle(
                          color: Colors.white, fontFamily: 'Poppins')),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    SongOptionsModal.show(context, track);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ); */
  }

  Widget _buildDiskSection(PlaybackService playback, String imageUrl) {
    final screenSize = MediaQuery.of(context).size;
    final diskSize = screenSize.width * 0.65;
    final artSize = diskSize * 0.35;
    final ringSize = diskSize + 8;

    return SizedBox(
      width: diskSize + 40,
      height: diskSize + 50,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: StreamBuilder<Duration>(
              stream: PlaybackService().positionStream,
              builder: (context, snapshot) {
                final position = snapshot.data ?? PlaybackService().position;
                final duration = PlaybackService().duration;
                final progress = duration.inMilliseconds > 0
                    ? (position.inMilliseconds / duration.inMilliseconds)
                        .clamp(0.0, 1.0)
                    : 0.0;

                return AnimatedBuilder(
                  animation: _expandController,
                  builder: (context, _) {
                    final expand = _expandController.value;
                    final currentRingSize = ringSize + (expand * 30);

                    return CustomPaint(
                      size: Size(currentRingSize, currentRingSize),
                      painter: _ProgressRingPainter(
                        progress: _isScrubbing ? _scrubProgress : progress,
                        ringWidth: 28,
                        lineWidth: 4,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _spinController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _spinController.value * 2 * pi,
                  child: child,
                );
              },
              child: _buildDisk(diskSize, imageUrl, artSize),
            ),
          ),
          _buildArm(),
          AnimatedBuilder(
            animation: _expandController,
            builder: (context, child) {
              // The progress ring expands from its center while scrubbing.
              // Let the time label travel with the ring's lower edge.
              return Positioned(
                left: 0,
                right: 0,
                bottom: 30 - (_expandController.value * 15),
                child: child!,
              );
            },
            child: Center(
              child: _buildTimerText(),
            ),
          ),
          Positioned(
            left: -25,
            right: -25,
            top: -25,
            bottom: -25,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (details) => _onScrubStart(details, ringSize),
              onPointerMove: (details) => _onScrubUpdate(details, ringSize),
              onPointerUp: (details) => _onScrubEnd(),
              onPointerCancel: (details) => _onScrubEnd(),
            ),
          ),
          // Center song cover horizontal scrub detector
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _onCoverScrubStart,
              onHorizontalDragUpdate: _onCoverScrubUpdate,
              onHorizontalDragEnd: (_) => _onCoverScrubEnd(),
              onHorizontalDragCancel: _onCoverScrubEnd,
              onVerticalDragStart: _onVolumeDragStart,
              onVerticalDragUpdate: _onVolumeDragUpdate,
              onVerticalDragEnd: (_) => _onVolumeDragEnd(),
              onVerticalDragCancel: _onVolumeDragEnd,
              child: Container(
                width: artSize + 12,
                height: artSize + 12,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isCoverScrubbing)
                      Center(
                        child: Container(
                          width: artSize,
                          height: artSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.45),
                            border: Border.all(
                              color: const Color(0xFF6C63FF),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.swap_horiz_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    if (_showVolumeIndicator)
                      IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: _isAdjustingVolume ? 1 : 0,
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          child: AnimatedScale(
                            scale: _isAdjustingVolume ? 1 : 0.88,
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                            child: _buildVolumeIndicator(playback.volume),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerText() {
    return StreamBuilder<Duration>(
      stream: PlaybackService().positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? PlaybackService().position;
        final duration = PlaybackService().duration;
        final displayPosition = _isScrubbing
            ? Duration(
                milliseconds:
                    (duration.inMilliseconds * _scrubProgress).round())
            : position;

        return Text(
          _formatDuration(displayPosition),
          style: TextStyle(
            color: Colors.white.withValues(alpha: _isScrubbing ? 1.0 : 0.8),
            fontSize: _isScrubbing ? 16 : 14,
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        );
      },
    );
  }

  void _onScrubStart(PointerDownEvent details, double ringSize) {
    final playback = PlaybackService();
    if (playback.duration.inMilliseconds <= 0) return;

    final diskSize = ringSize - 8;
    final centerX = (diskSize + 40) / 2 + 25;
    final centerY = (diskSize + 50) / 2 + 25;
    final dx = details.localPosition.dx - centerX;
    final dy = details.localPosition.dy - centerY;
    final distance = sqrt(dx * dx + dy * dy);

    // Only allow scrubbing on the progress ring/knob zone (lineRadius is at diskSize/2 - 11).
    // Protect the vinyl record & album art center (inner radius < diskSize/2 - 32).
    final minRadius = (diskSize / 2) - 32;
    if (distance < minRadius) return;

    setState(() {
      _isScrubbing = true;
      _didScrubMove = false;
      _prevScrubProgress = _scrubProgress;
    });
    _scrubStartPosition = details.localPosition;
  }

  void _onScrubUpdate(PointerMoveEvent details, double ringSize) {
    if (!_isScrubbing) return;
    if (!_didScrubMove && _scrubStartPosition != null) {
      final dx = details.localPosition.dx - _scrubStartPosition!.dx;
      final dy = details.localPosition.dy - _scrubStartPosition!.dy;
      if (dx * dx + dy * dy > 16) {
        _didScrubMove = true;
        _expandController.forward();
      }
    }
    if (!_didScrubMove) return;
    _updateScrubFromOffset(details.localPosition, ringSize);
  }

  void _updateScrubFromOffset(Offset localPosition, double ringSize) {
    final diskSize = ringSize - 8;
    final centerX = (diskSize + 40) / 2 + 25;
    final centerY = (diskSize + 50) / 2 + 25;
    final center = Offset(centerX, centerY);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    var angle = atan2(dy, dx);

    const lineStart = 7 * pi / 12;
    const lineSweep = 11 * pi / 6;

    var relAngle = angle - lineStart;
    if (relAngle < 0) relAngle += 2 * pi;

    double normalized;
    if (relAngle > lineSweep) {
      normalized = _scrubProgress < 0.5 ? 0.0 : 1.0;
    } else {
      normalized = (relAngle / lineSweep).clamp(0.0, 1.0);
    }

    final delta = normalized - _scrubProgress;
    if (delta.abs() < 0.005) return;

    _prevScrubProgress = _scrubProgress;
    setState(() {
      _scrubProgress = normalized;
    });
  }

  void _onScrubEnd() {
    if (!_isScrubbing) return;
    if (_didScrubMove) {
      final playback = PlaybackService();
      final duration = playback.duration;
      final seekPosition = Duration(
          milliseconds: (duration.inMilliseconds * _scrubProgress).round());
      playback.seek(seekPosition).then((_) {
        // Instantly notify listening friends about the new seek position
        PresenceService().broadcastNow();
      });
    } else {
      setState(() {
        _scrubProgress = _prevScrubProgress;
      });
    }

    _expandController.reverse();
    setState(() {
      _isScrubbing = false;
      _didScrubMove = false;
    });
  }

  void _onCoverScrubStart(DragStartDetails details) {
    final playback = PlaybackService();
    if (playback.duration.inMilliseconds <= 0) return;

    final position = playback.position;
    final duration = playback.duration;
    final currentProgress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    _coverDragStartX = details.globalPosition.dx;
    _coverDragStartProgress = _isScrubbing ? _scrubProgress : currentProgress;
    _prevScrubProgress = _coverDragStartProgress;

    setState(() {
      _isScrubbing = true;
      _isCoverScrubbing = true;
      _didScrubMove = false;
      _scrubProgress = _coverDragStartProgress;
    });
    _expandController.forward();
  }

  void _onCoverScrubUpdate(DragUpdateDetails details) {
    if (!_isCoverScrubbing) return;
    final playback = PlaybackService();
    if (playback.duration.inMilliseconds <= 0) return;

    final dx = details.globalPosition.dx - _coverDragStartX;
    if (dx.abs() > 4) {
      _didScrubMove = true;
    }

    // Higher value = less sensitive, smoother and more precise dragging
    const sensitivity = 480.0;
    final deltaProgress = dx / sensitivity;
    final newProgress =
        (_coverDragStartProgress + deltaProgress).clamp(0.0, 1.0);

    if ((newProgress - _scrubProgress).abs() > 0.001) {
      setState(() {
        _scrubProgress = newProgress;
      });
    }
  }

  void _onCoverScrubEnd() {
    if (!_isCoverScrubbing) return;
    _expandController.reverse();

    if (_didScrubMove) {
      final playback = PlaybackService();
      final duration = playback.duration;
      final seekPosition = Duration(
          milliseconds: (duration.inMilliseconds * _scrubProgress).round());
      playback.seek(seekPosition).then((_) {
        PresenceService().broadcastNow();
      });
    } else {
      setState(() {
        _scrubProgress = _prevScrubProgress;
      });
    }

    setState(() {
      _isScrubbing = false;
      _isCoverScrubbing = false;
      _didScrubMove = false;
    });
  }

  void _onVolumeDragStart(DragStartDetails details) {
    _volumeIndicatorTimer?.cancel();
    _coverDragStartY = details.globalPosition.dy;
    _coverDragStartVolume = PlaybackService().volume;
    setState(() {
      _isAdjustingVolume = true;
      _showVolumeIndicator = true;
    });
  }

  void _onVolumeDragUpdate(DragUpdateDetails details) {
    if (!_isAdjustingVolume) return;

    // A full-height, deliberate swipe spans the player volume range. Up is
    // louder and down is quieter, matching the physical mental model.
    const swipeRange = 260.0;
    final delta = (_coverDragStartY - details.globalPosition.dy) / swipeRange;
    PlaybackService()
        .setVolume((_coverDragStartVolume + delta).clamp(0.0, 1.0));
  }

  void _onVolumeDragEnd() {
    if (!_isAdjustingVolume) return;
    _volumeIndicatorTimer?.cancel();
    _volumeIndicatorTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _isAdjustingVolume = false);
      // Keep the widget mounted until its opacity/scale animation finishes.
      _volumeIndicatorTimer = Timer(const Duration(milliseconds: 340), () {
        if (mounted) setState(() => _showVolumeIndicator = false);
      });
    });
  }

  Widget _buildVolumeIndicator(double volume) {
    final icon = volume == 0
        ? Icons.volume_off_rounded
        : volume < 0.45
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;

    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.68),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 27),
          const SizedBox(height: 8),
          SizedBox(
            width: 58,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: volume,
                minHeight: 4,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF8A84FF)),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${(volume * 100).round()}%',
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildDisk(double diskSize, String imageUrl, double artSize) {
    return Container(
      width: diskSize,
      height: diskSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            'asset/musicPlayer_assets/new_disk.png',
            width: diskSize,
            height: diskSize,
            fit: BoxFit.contain,
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: artSize,
                height: artSize,
                child: imageUrl.isNotEmpty
                    ? ClipOval(
                        child: CachedImage(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF8B0000),
                            ),
                            child: const Icon(Icons.music_note,
                                color: Colors.white38, size: 20),
                          ),
                        ),
                      )
                    : ClipOval(
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF8B0000),
                          ),
                          child: const Icon(Icons.music_note,
                              color: Colors.white38, size: 20),
                        ),
                      ),
              ),
              Container(
                width: artSize * 0.1,
                height: artSize * 0.1,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1A1A1A),
                  border: Border.all(
                    color: const Color(0xFF333333),
                    width: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildArm() {
    const double armWidth = 158;
    const double armHeight = 170;

    return Positioned(
      top: -8,
      right: -24,
      child: SizedBox(
        width: armWidth,
        height: armHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. Stationary Turntable Base (chassis mount, gimbal turret, arm rest)
            Image.asset(
              'asset/musicPlayer_assets/tonearm_base.png',
              width: armWidth,
              height: armHeight,
              fit: BoxFit.contain,
            ),
            // 2. Rotating Tonearm Wand (counterweight, bearing ring, dark chrome S-arm, cartridge)
            AnimatedBuilder(
              animation: _armController,
              builder: (context, _) {
                final animCurve = CurvedAnimation(
                  parent: _armController,
                  curve: Curves.easeInOutCubic,
                  reverseCurve: Curves.easeInOutCubic,
                );
                // Parked off-record on rest (0.30 rad) -> Playing on record (-0.08 rad)
                final angle = 0.30 + (animCurve.value * -0.38);

                return Transform.rotate(
                  angle: angle,
                  alignment: const FractionalOffset(0.757, 0.231),
                  child: Image.asset(
                    'asset/musicPlayer_assets/tonearm_wand.png',
                    width: armWidth,
                    height: armHeight,
                    fit: BoxFit.contain,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackInfo(SearchResult track) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        children: [
          GestureDetector(
            onTap: () async {
              String artistId = track.artistId;
              String artistImage = track.artistImage;
              if (artistId.isEmpty) {
                // First resolve artist directly by name
                final resolved =
                    await ArtistService.resolveArtist(track.artist);
                if (resolved != null &&
                    (resolved['id']?.toString() ?? '').isNotEmpty) {
                  artistId = resolved['id']!.toString();
                  artistImage = resolved['image']?.toString() ?? '';
                } else {
                  // Fall back to searching
                  final results = await SearchService.search(
                      '${track.title} ${track.artist}');
                  if (results.isNotEmpty) {
                    final songMatch = results
                        .where(
                          (r) =>
                              r.type == 'song' &&
                              r.artist.toLowerCase().trim() ==
                                  track.artist.toLowerCase().trim(),
                        )
                        .firstOrNull;
                    if (songMatch != null) {
                      artistId = songMatch.artistId;
                      artistImage = songMatch.artistImage;
                    }
                  }
                }
              }
              if (artistId.isEmpty) return;
              if (!mounted) return;
              Navigator.of(context).push(
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 400),
                  reverseTransitionDuration: const Duration(milliseconds: 350),
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      ArtistScreen(
                    artistId: artistId,
                    artistName: track.artist,
                    artistImage: artistImage,
                    nbFan: track.nbFan,
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
            child: Text(
              track.artist,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 16,
                fontFamily: 'Poppins',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 36,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      final track = PlaybackService().currentTrack;
                      if (track == null) return;

                      if (_isAdded) {
                        setState(() => _isAdded = false);
                        LikedSongsService.unlikeSong(
                          track.id,
                          title: track.title,
                          artist: track.artist,
                        );
                        CookieService.show(
                          message: 'Removed from Liked Songs',
                          icon: Icons.favorite_border_rounded,
                          iconColor: Colors.white60,
                        );
                      } else {
                        Duration trackDuration = Duration.zero;
                        try {
                          final parts = track.duration.split(':');
                          if (parts.length == 2) {
                            trackDuration = Duration(
                              minutes: int.parse(parts[0]),
                              seconds: int.parse(parts[1]),
                            );
                          }
                        } catch (_) {}

                        setState(() => _isAdded = true);
                        LikedSongsService.likeSong(
                          trackId: track.id,
                          title: track.title,
                          artist: track.artist,
                          image: track.image,
                          artistId: track.artistId,
                          artistImage: track.artistImage,
                          duration: trackDuration,
                        );
                        CookieService.show(
                          message: 'Added to Liked Songs',
                          icon: Icons.favorite_rounded,
                          iconColor: const Color(0xFF514AED),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        _isAdded ? Icons.favorite : Icons.favorite_border,
                        color:
                            _isAdded ? const Color(0xFF514AED) : Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _handleTitleTap(track),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.65,
                      ),
                      child: MarqueeText(
                        text: track.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleTitleTap(SearchResult track) async {
    final playback = PlaybackService();
    final ctx = playback.currentContext;

    if (ctx != null) {
      if (ctx.type == 'playlist' && ctx.id.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlaylistDetailScreen(playlistId: ctx.id),
          ),
        );
        return;
      } else if (ctx.type == 'generated') {
        final songs = (ctx.extra?['songs'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GeneratedPlaylistScreen(
              mood: ctx.id.isNotEmpty ? ctx.id : 'Playlist',
              songs: songs,
            ),
          ),
        );
        return;
      } else if (ctx.type == 'liked') {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const LikedSongsScreen(),
          ),
        );
        return;
      } else if (ctx.type == 'downloaded') {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const DownloadedSongsScreen(),
          ),
        );
        return;
      } else if (ctx.type == 'album' && ctx.id.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AlbumDetailScreen(
              albumId: ctx.id,
              albumTitle: ctx.title,
              albumImage: ctx.coverImage ?? track.image,
              artistName: ctx.artistName ?? track.artist,
              artistId: ctx.artistId ?? track.artistId,
            ),
          ),
        );
        return;
      } else if (ctx.type == 'artist' && ctx.id.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ArtistScreen(
              artistId: ctx.id,
              artistName: ctx.title.isNotEmpty ? ctx.title : track.artist,
              artistImage: ctx.coverImage ?? '',
              nbFan: 0,
            ),
          ),
        );
        return;
      }
    }

    // If song was NOT played from a playlist (e.g. played from search / recommendation):
    // Check if the song belongs to an album!
    String albumId = track.albumId;
    String albumTitle = track.albumTitle;
    String albumImage = track.albumCover;
    String artistName = track.artist;
    String artistId = track.artistId;

    if (albumId.isEmpty) {
      final info = await SearchService.getTrackAlbum(
          track.id, track.title, track.artist);
      if (info != null && (info['albumId'] ?? '').isNotEmpty) {
        albumId = info['albumId']!;
        albumTitle = info['albumTitle'] ?? '';
        albumImage = info['albumImage'] ?? track.image;
        if ((info['artistId'] ?? '').isNotEmpty) {
          artistId = info['artistId']!;
        }
        if ((info['artistName'] ?? '').isNotEmpty) {
          artistName = info['artistName']!;
        }
      }
    }

    // If song belongs to an album, launch it; if not, don't open anything.
    if (albumId.isNotEmpty && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AlbumDetailScreen(
            albumId: albumId,
            albumTitle: albumTitle.isNotEmpty ? albumTitle : track.title,
            albumImage: albumImage.isNotEmpty ? albumImage : track.image,
            artistName: artistName.isNotEmpty ? artistName : track.artist,
            artistId: artistId,
          ),
        ),
      );
    }
  }

  Widget _buildLyricsSection(SearchResult track, PlaybackService playback) {
    return GestureDetector(
      onTap: () {
        if (playback.currentLyrics != null &&
            playback.currentLyrics!.isNotEmpty) {
          _showFullLyrics(track, playback);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 150,
        child: StreamBuilder<Duration>(
          stream: playback.positionStream,
          builder: (context, snapshot) {
            final position = snapshot.data ?? Duration.zero;

            if (playback.lyricsLoading) {
              return Center(
                child: Text(
                  'Loading lyrics...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 18,
                    fontFamily: 'Poppins',
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            }

            if (playback.currentLyrics == null ||
                playback.currentLyrics!.isEmpty) {
              return Center(
                child: Text(
                  'Song has no lyrics',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 18,
                    fontFamily: 'Poppins',
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            }

            final lyrics = playback.currentLyrics!;
            final idx = LyricsService.currentLineIndex(lyrics, position);
            final lyricKeys = _lyricKeysFor(lyrics);

            // Auto-follow the current line immediately on load, and smoothly on line changes.
            if (!_hasInitialLyricsScrolled || idx != _lastLyricScrollIndex) {
              final isInitial = !_hasInitialLyricsScrolled;
              _lastLyricScrollIndex = idx;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _lyricsScrollToLine(lyrics, idx, immediate: isInitial);
                }
              });
              // When returning to Now Playing, the lyrics ListView may need
              // an extra layout pass before its full extent is available.
              // Re-center once more so it never waits for the next lyric line.
              if (isInitial) {
                Future.delayed(const Duration(milliseconds: 180), () {
                  if (!mounted || playback.currentLyrics != lyrics) return;
                  final currentIndex =
                      LyricsService.currentLineIndex(lyrics, playback.position);
                  _lyricsScrollToLine(lyrics, currentIndex, immediate: true);
                });
              }
            }

            return ClipRect(
              child: Stack(
                children: [
                  ListView.builder(
                    controller: _lyricsScrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: lyrics.length,
                    itemBuilder: (context, i) {
                      final isCurrent = i == idx;
                      final distance = (i - idx).abs();
                      final alpha = isCurrent
                          ? 1.0
                          : distance == 1
                              ? 0.6
                              : distance == 2
                                  ? 0.4
                                  : 0.25;

                      return Padding(
                        key: lyricKeys[i],
                        padding: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 20),
                        child: Text(
                          lyrics[i].text,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: alpha),
                            fontSize: isCurrent ? 15 : 12,
                            fontWeight:
                                isCurrent ? FontWeight.bold : FontWeight.normal,
                            fontFamily: 'Poppins',
                            fontStyle: FontStyle.italic,
                            height: 1.3,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 36,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            const Color(0xFF0D0D0D).withValues(alpha: 0.0),
                            const Color(0xFF0D0D0D).withValues(alpha: 0.06),
                            const Color(0xFF0D0D0D).withValues(alpha: 0.16),
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 36,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF0D0D0D).withValues(alpha: 0.0),
                            const Color(0xFF0D0D0D).withValues(alpha: 0.06),
                            const Color(0xFF0D0D0D).withValues(alpha: 0.16),
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // One GlobalKey per lyric line so the auto-scroll can measure real on-screen
  // positions instead of guessing heights (estimates drift and push the
  // current line off-center).
  List<GlobalKey> _lyricItemKeys = [];
  List<LyricLine>? _lyricKeysSource;

  List<GlobalKey> _lyricKeysFor(List<LyricLine> lyrics) {
    if (identical(_lyricKeysSource, lyrics) &&
        _lyricItemKeys.length == lyrics.length) {
      return _lyricItemKeys;
    }
    _lyricKeysSource = lyrics;
    _lyricItemKeys = List.generate(lyrics.length, (_) => GlobalKey());
    return _lyricItemKeys;
  }

  void _lyricsScrollToLine(List<LyricLine> lyrics, int index,
      {bool immediate = false}) {
    if (index < 0 || index >= lyrics.length) return;
    if (!_lyricsScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _lyricsScrollToLine(lyrics, index, immediate: immediate);
        }
      });
      return;
    }

    final maxScroll = _lyricsScrollController.position.maxScrollExtent;
    final viewportHeight = _lyricsScrollController.position.viewportDimension;

    // If maxScroll is not yet calculated (initial build), retry next frame.
    if (maxScroll <= 0.0 && index > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _lyricsScrollToLine(lyrics, index, immediate: immediate);
        }
      });
      return;
    }

    final keys = _lyricKeysFor(lyrics);
    double target;
    final ctx = keys[index].currentContext;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      final viewportBox =
          Scrollable.of(ctx).context.findRenderObject() as RenderBox?;
      if (box != null && viewportBox != null) {
        final itemCenter = box.localToGlobal(box.size.center(Offset.zero)).dy;
        final viewportCenter =
            viewportBox.localToGlobal(viewportBox.size.center(Offset.zero)).dy;
        target = _lyricsScrollController.offset + (itemCenter - viewportCenter);
      } else {
        target = _estimateLyricTarget(lyrics, index, viewportHeight);
      }
    } else {
      target = _estimateLyricTarget(lyrics, index, viewportHeight);
    }

    final clamped = target.clamp(0.0, maxScroll);
    _hasInitialLyricsScrolled = true;

    if (immediate) {
      _lyricsScrollController.jumpTo(clamped);
      // Ensure exact settlement once items are built:
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_lyricsScrollController.hasClients) return;
        final settledCtx = keys[index].currentContext;
        if (settledCtx != null) {
          final sBox = settledCtx.findRenderObject() as RenderBox?;
          final sViewport = Scrollable.of(settledCtx).context.findRenderObject()
              as RenderBox?;
          if (sBox != null && sViewport != null) {
            final iCenter =
                sBox.localToGlobal(sBox.size.center(Offset.zero)).dy;
            final vCenter =
                sViewport.localToGlobal(sViewport.size.center(Offset.zero)).dy;
            final fineTarget =
                _lyricsScrollController.offset + (iCenter - vCenter);
            _lyricsScrollController.jumpTo(fineTarget.clamp(
                0.0, _lyricsScrollController.position.maxScrollExtent));
          }
        }
      });
    } else {
      _lyricsScrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  double _estimateLyricTarget(
      List<LyricLine> lyrics, int index, double viewportHeight) {
    double offset = 0;
    for (var i = 0; i < index; i++) {
      offset += _estimateLyricItemHeight(lyrics[i].text, false);
    }
    offset += _estimateLyricItemHeight(lyrics[index].text, true) / 2;
    return offset - (viewportHeight / 2);
  }

  double _estimateLyricItemHeight(String text, bool isCurrent) {
    const double width = 300;
    final font = isCurrent ? 15.0 : 12.0;
    final maxChars = (width / (font * 0.55)).floor().clamp(10, 400);
    final lines = (text.length / maxChars).ceil().clamp(1, 2);
    return lines * font * 1.3 + 8;
  }

  void _showFullLyrics(SearchResult track, PlaybackService playback) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => _FullLyricsPage(
          playback: playback,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildControls(PlaybackService playback) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => playback.toggleShuffle(),
            child: Image.asset(
              'asset/musicPlayer_assets/shuffle.png',
              width: 22,
              height: 22,
              color:
                  playback.isShuffle ? const Color(0xFF514AED) : Colors.white38,
              colorBlendMode: BlendMode.srcIn,
            ),
          ),
          GestureDetector(
            onTap: () => playback.playPrevious(),
            child: Icon(
              Icons.skip_previous_rounded,
              color: playback.hasPrevious ? Colors.white : Colors.white30,
              size: 36,
            ),
          ),
          GestureDetector(
            onTap: () => playback.togglePlayPause(),
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF514AED),
              ),
              child: StreamBuilder<PlayerState>(
                stream: playback.playerStateStream,
                builder: (context, snapshot) {
                  final isPlaying = snapshot.data?.playing ?? false;
                  return Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
                  );
                },
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              if (!PremiumService().canSkipTrack) {
                PremiumService.showUpsell(
                  context,
                  reason:
                      "You've used all 6 skips for this hour. Upgrade for unlimited skips.",
                  feature: 'Skip Limit Reached',
                );
                return;
              }
              PremiumService().recordSkip();
              playback.playNext();
            },
            child: Icon(
              Icons.skip_next_rounded,
              color: playback.hasNext ? Colors.white : Colors.white30,
              size: 36,
            ),
          ),
          GestureDetector(
            onTap: () => playback.toggleRepeat(),
            child: _buildRepeatIcon(playback.loopMode),
          ),
        ],
      ),
    );
  }

  static Widget _buildRepeatIcon(MeloLoopMode mode) {
    final bool isAll = mode == MeloLoopMode.all;
    final bool isOne = mode == MeloLoopMode.one;
    final Color iconColor =
        (isAll || isOne) ? const Color(0xFF514AED) : Colors.white38;

    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            'asset/musicPlayer_assets/repeat.png',
            width: 22,
            height: 22,
            color: iconColor,
            colorBlendMode: BlendMode.srcIn,
          ),
          if (isOne)
            Positioned(
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF191919),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text(
                  '1',
                  style: TextStyle(
                    color: Color(0xFF514AED),
                    fontSize: 7.5,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Poppins',
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<({SearchResult track, int index})> _buildQueueList(
      PlaybackService playback) {
    final queue = playback.queue;
    final items = <({SearchResult track, int index})>[];
    for (var i = 0; i < queue.length; i++) {
      items.add((track: queue[i], index: i));
    }
    for (final t in playback.smartQueue) {
      if (!items.any((e) => e.track.id == t.id)) {
        items.add((track: t, index: -1));
      }
    }
    return items;
  }

  Widget _buildQueueBackdrop() {
    return AnimatedBuilder(
      animation: _queueController,
      builder: (context, _) {
        final t = _queueController.value;
        if (t <= 0.001) return const SizedBox.shrink();
        return Positioned.fill(
          child: GestureDetector(
            onTap: _closeQueue,
            behavior: HitTestBehavior.opaque,
            child: Container(
              color: Colors.black.withValues(alpha: 0.65 * t),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQueueSheet(PlaybackService playback) {
    final items = _buildQueueList(playback);
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    const minHeight = 48.0;
    final travelDistance = maxHeight - minHeight;

    return AnimatedBuilder(
      animation: _queueController,
      builder: (context, _) {
        final t = _queueController.value;
        final offsetY = (1.0 - t) * travelDistance;
        final isExpanded = t > 0.35;

        SearchResult? nextTrack;
        if (playback.queueIndex >= 0 &&
            playback.queueIndex + 1 < playback.queue.length) {
          nextTrack = playback.queue[playback.queueIndex + 1];
        } else if (playback.loopMode == MeloLoopMode.all &&
            playback.queue.isNotEmpty) {
          nextTrack = playback.queue.first;
        } else if (playback.smartQueue.isNotEmpty) {
          nextTrack = playback.smartQueue.first;
        } else if (items.length > 1) {
          final currentIdx =
              items.indexWhere((it) => it.index == playback.queueIndex);
          if (currentIdx >= 0 && currentIdx + 1 < items.length) {
            nextTrack = items[currentIdx + 1].track;
          }
        }

        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: maxHeight,
          child: Transform.translate(
            offset: Offset(0, offsetY),
            child: Container(
              height: maxHeight,
              decoration: BoxDecoration(
                color: const Color(0xFF141419),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1.0,
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                child: Column(
                  children: [
                    // Top drag header
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggleQueue,
                      onVerticalDragUpdate: (details) {
                        final delta = details.primaryDelta ?? 0;
                        if (travelDistance > 0) {
                          _queueController.value = (_queueController.value -
                                  (delta / travelDistance))
                              .clamp(0.0, 1.0);
                        }
                      },
                      onVerticalDragEnd: (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity < -250) {
                          _openQueue();
                        } else if (velocity > 250) {
                          _closeQueue();
                        } else if (_queueController.value > 0.3) {
                          _openQueue();
                        } else {
                          _closeQueue();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Clean drag handle
                            Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (!isExpanded)
                              // Centered Next Track Peek
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      'UP NEXT',
                                      style: TextStyle(
                                        color: Color(0xFF8A82FF),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'Poppins',
                                        letterSpacing: 0.8,
                                      ),
                                      textScaler: TextScaler.noScaling,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '•',
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.25),
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        nextTrack != null
                                            ? nextTrack.title
                                            : 'End of queue',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.85),
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: 'Poppins',
                                        ),
                                        textScaler: TextScaler.noScaling,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.keyboard_arrow_up_rounded,
                                      size: 18,
                                      color:
                                          Colors.white.withValues(alpha: 0.35),
                                    ),
                                  ],
                                ),
                              )
                            else
                              // Expanded header row
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 2, bottom: 2),
                                child: Row(
                                  children: [
                                    GestureDetector(
                                      onTap: _closeQueue,
                                      child: Container(
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white
                                              .withValues(alpha: 0.08),
                                        ),
                                        child: const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    const Expanded(
                                      child: Text(
                                        'Up Next',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Poppins',
                                        ),
                                        textScaler: TextScaler.noScaling,
                                      ),
                                    ),
                                    if (items.length > 1)
                                      GestureDetector(
                                        onTap: () {
                                          playback.clearUpcomingQueue();
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.08),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: const Text(
                                            'Clear',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              fontFamily: 'Poppins',
                                            ),
                                            textScaler: TextScaler.noScaling,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Expanded Queue List
                    Expanded(
                      child: items.isEmpty
                          ? Center(
                              child: Text(
                                'No songs in queue yet',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 13,
                                  fontFamily: 'Poppins',
                                ),
                                textScaler: TextScaler.noScaling,
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                              itemCount: items.length,
                              itemBuilder: (context, i) {
                                final item = items[i];
                                final isCurrent =
                                    item.index == playback.queueIndex;
                                return _QueueListTile(
                                  indexNumber: i + 1,
                                  track: item.track,
                                  isCurrent: isCurrent,
                                  isAutoplay: item.index < 0,
                                  onTap: () {
                                    if (isCurrent) return;
                                    if (!PremiumService().canSkipTrack) {
                                      PremiumService.showUpsell(
                                        context,
                                        reason:
                                            "You've used all 6 skips for this hour. Upgrade for unlimited skips.",
                                        feature: 'Skip Limit Reached',
                                      );
                                      return;
                                    }
                                    PremiumService().recordSkip();
                                    if (item.index >= 0) {
                                      playback.playQueueIndex(item.index);
                                    } else {
                                      playback.playQueueTrack(item.track);
                                    }
                                  },
                                  onRemove: item.index >= 0
                                      ? () =>
                                          playback.removeFromQueue(item.index)
                                      : null,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildListenAlongSessionPill() {
    return ListenableBuilder(
      listenable: PresenceService(),
      builder: (context, _) {
        final presence = PresenceService();
        final currentListeners = presence.currentListeners;
        final listeningWithId = presence.listeningWithUserId;
        final isHost = listeningWithId == null || listeningWithId.isEmpty;
        final hostFriend = listeningWithId != null
            ? presence.liveFriends[listeningWithId]
            : null;

        final bool hasSession =
            (!isHost && hostFriend != null) || currentListeners.isNotEmpty;
        if (!hasSession) return const SizedBox.shrink();

        const double avatarSize = 18.0;
        const double overlapOffset = -6.0;

        return GestureDetector(
          onTap: () => _showListenAlongSessionSheet(context),
          child: Container(
            margin: const EdgeInsets.only(top: 6, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1C38).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF514AED).withValues(alpha: 0.5),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF514AED).withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.headphones_rounded,
                  color: Color(0xFF817BFF),
                  size: 13,
                ),
                const SizedBox(width: 5),
                if (!isHost && hostFriend != null) ...[
                  Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF514AED),
                      border: Border.all(
                        color: const Color(0xFF191919),
                        width: 1.2,
                      ),
                    ),
                    child: ClipOval(
                      child: hostFriend.avatarUrl.isNotEmpty
                          ? CachedImage(
                              hostFriend.avatarUrl,
                              width: avatarSize,
                              height: avatarSize,
                              fit: BoxFit.cover,
                            )
                          : const Icon(
                              Icons.person,
                              size: 11,
                              color: Colors.white,
                            ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Listening with ${hostFriend.displayName.isNotEmpty ? hostFriend.displayName : hostFriend.username}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ] else
                  Text(
                    '${currentListeners.length} listening with you',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                    ),
                  ),
                if (currentListeners.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0;
                          i <
                              (currentListeners.length > 3
                                  ? 3
                                  : currentListeners.length);
                          i++)
                        Transform.translate(
                          offset: Offset(i * overlapOffset, 0),
                          child: Container(
                            width: avatarSize,
                            height: avatarSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF514AED),
                              border: Border.all(
                                color: const Color(0xFF191919),
                                width: 1.2,
                              ),
                            ),
                            child: ClipOval(
                              child: currentListeners[i].avatarUrl.isNotEmpty
                                  ? CachedImage(
                                      currentListeners[i].avatarUrl,
                                      width: avatarSize,
                                      height: avatarSize,
                                      fit: BoxFit.cover,
                                    )
                                  : const Icon(
                                      Icons.person,
                                      size: 11,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showListenAlongSessionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return ListenableBuilder(
          listenable: PresenceService(),
          builder: (context, _) {
            final presence = PresenceService();
            final currentListeners = presence.currentListeners;
            final listeningWithId = presence.listeningWithUserId;
            final isHost = listeningWithId == null || listeningWithId.isEmpty;
            final hostFriend = listeningWithId != null
                ? presence.liveFriends[listeningWithId]
                : null;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.headphones_rounded,
                              color: Color(0xFF514AED),
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Listen Along Session',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ],
                        ),
                        if (!isHost)
                          GestureDetector(
                            onTap: () {
                              presence.stopListeningWith();
                              Navigator.pop(ctx);
                              CookieService.show(
                                message: 'Left listening session',
                                icon: Icons.exit_to_app_rounded,
                                iconColor: Colors.white70,
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      Colors.redAccent.withValues(alpha: 0.3),
                                ),
                              ),
                              child: const Text(
                                'Leave',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isHost
                          ? 'Manage and see everyone tuned into your live music session.'
                          : 'You are synchronized with ${hostFriend?.displayName ?? 'Host'}.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (!isHost && hostFriend != null) ...[
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF514AED),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Session Host',
                            style: TextStyle(
                              color: Color(0xFF817BFF),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildListenerTile(
                        ctx,
                        userId: hostFriend.userId,
                        displayName: hostFriend.displayName,
                        username: hostFriend.username,
                        avatarUrl: hostFriend.avatarUrl,
                        isOnline: true,
                        statusText: 'Hosting Session',
                        statusColor: const Color(0xFF817BFF),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Still on (${currentListeners.length})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (currentListeners.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No friends currently listening along.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      )
                    else
                      ...currentListeners.map(
                        (l) => _buildListenerTile(
                          ctx,
                          userId: l.userId,
                          displayName: l.displayName,
                          username: l.username,
                          avatarUrl: l.avatarUrl,
                          isOnline: true,
                          statusText: 'Listening now',
                          statusColor: const Color(0xFF10B981),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildListenerTile(
    BuildContext ctx, {
    required String userId,
    required String displayName,
    required String username,
    required String avatarUrl,
    required bool isOnline,
    required String statusText,
    required Color statusColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          ClipOval(
            child: avatarUrl.isNotEmpty
                ? CachedImage(avatarUrl,
                    width: 38, height: 38, fit: BoxFit.cover)
                : Container(
                    width: 38,
                    height: 38,
                    color: const Color(0xFF333333),
                    child: const Icon(Icons.person,
                        color: Colors.white38, size: 20),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName.isNotEmpty
                      ? displayName
                      : (username.isNotEmpty ? username : 'Friend'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  username.isNotEmpty ? '@$username' : '',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueListTile extends StatelessWidget {
  final int indexNumber;
  final SearchResult track;
  final bool isCurrent;
  final bool isAutoplay;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _QueueListTile({
    required this.indexNumber,
    required this.track,
    required this.isCurrent,
    this.isAutoplay = false,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isCurrent
            ? const Color(0xFF514AED).withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: isCurrent
            ? Border.all(
                color: const Color(0xFF514AED).withValues(alpha: 0.4),
                width: 1.0,
              )
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Track index number
                SizedBox(
                  width: 22,
                  child: Text(
                    indexNumber.toString().padLeft(2, '0'),
                    style: TextStyle(
                      color: isCurrent
                          ? const Color(0xFF8A82FF)
                          : Colors.white.withValues(alpha: 0.3),
                      fontSize: 12,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                      fontFamily: 'Poppins',
                    ),
                    textScaler: TextScaler.noScaling,
                  ),
                ),
                const SizedBox(width: 8),

                // Album Art
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedImage(
                    track.image,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 44,
                      height: 44,
                      color: const Color(0xFF2A2A2A),
                      child: const Icon(Icons.music_note,
                          color: Colors.white38, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Title & Artist Column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent
                              ? const Color(0xFF8A82FF)
                              : Colors.white,
                          fontSize: 14,
                          fontWeight:
                              isCurrent ? FontWeight.bold : FontWeight.w500,
                          fontFamily: 'Poppins',
                        ),
                        textScaler: TextScaler.noScaling,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (isAutoplay) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF514AED)
                                    .withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'AUTOPLAY',
                                style: TextStyle(
                                  color: Color(0xFF8A82FF),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Poppins',
                                ),
                                textScaler: TextScaler.noScaling,
                              ),
                            ),
                          ],
                          Expanded(
                            child: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                                fontFamily: 'Poppins',
                              ),
                              textScaler: TextScaler.noScaling,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Playing Equalizer Animation or Remove Button
                if (isCurrent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF514AED).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: NowPlayingBars(
                      playing: PlaybackService().isPlaying,
                      color: const Color(0xFF8A82FF),
                    ),
                  )
                else if (onRemove != null)
                  GestureDetector(
                    onTap: onRemove,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
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
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double progress;
  final double ringWidth;
  final double lineWidth;

  _ProgressRingPainter(
      {required this.progress,
      required this.ringWidth,
      required this.lineWidth});

  static const double _startAngle = -pi / 2;
  static const double _sweepTotal = 2 * pi;
  static const double _lineStartAngle = 7 * pi / 12;
  static const double _lineSweepTotal = 11 * pi / 6;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = (size.width - 2) / 2;
    final innerRadius = outerRadius - ringWidth;
    final lineRadius = (outerRadius + innerRadius) / 2;

    final outerRect = Rect.fromCircle(center: center, radius: outerRadius);
    final innerRect = Rect.fromCircle(center: center, radius: innerRadius);

    canvas.save();
    final path = Path()
      ..addArc(outerRect, _startAngle, _sweepTotal)
      ..addArc(innerRect, _startAngle + _sweepTotal, -_sweepTotal);
    canvas.clipPath(path);

    final groovePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF2A2A2A),
          const Color(0xFF1A1A1A),
          const Color(0xFF222222),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius));

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      groovePaint,
    );
    canvas.restore();

    final outerStroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawArc(outerRect, _startAngle, _sweepTotal, false, outerStroke);

    final innerStroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawArc(innerRect, _startAngle, _sweepTotal, false, innerStroke);

    final lineRect = Rect.fromCircle(center: center, radius: lineRadius);

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        lineRect, _lineStartAngle, _lineSweepTotal, false, trackPaint);

    final gradientPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: const [
          Color(0xFF6C63FF),
          Color(0xFF8B83FF),
          Colors.white,
          Color(0xFF8B83FF),
          Color(0xFF6C63FF),
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(lineRect);

    final sweepAngle = _lineSweepTotal * progress;
    if (sweepAngle > 0) {
      canvas.drawArc(
          lineRect, _lineStartAngle, sweepAngle, false, gradientPaint);

      final knobAngle = _lineStartAngle + sweepAngle;
      final knobX = center.dx + lineRadius * cos(knobAngle);
      final knobY = center.dy + lineRadius * sin(knobAngle);

      final knobGlow = Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(Offset(knobX, knobY), 6, knobGlow);

      final knobPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(knobX, knobY), 6, knobPaint);
    }
  }

  @override
  bool shouldRepaint(_ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _FullLyricsPage extends StatefulWidget {
  final PlaybackService playback;

  const _FullLyricsPage({
    required this.playback,
  });

  @override
  State<_FullLyricsPage> createState() => _FullLyricsPageState();
}

class _FullLyricsPageState extends State<_FullLyricsPage> {
  final ScrollController _scrollController = ScrollController();
  int _lastHighlightIndex = -1;
  bool _hasInitialScrolled = false;
  String? _lastTrackKey;
  List<GlobalKey> _itemKeys = [];
  List<LyricLine>? _keysSource;

  List<GlobalKey> _keysFor(List<LyricLine> lyrics) {
    if (identical(_keysSource, lyrics) && _itemKeys.length == lyrics.length) {
      return _itemKeys;
    }
    _keysSource = lyrics;
    _itemKeys = List.generate(lyrics.length, (_) => GlobalKey());
    return _itemKeys;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLine(List<LyricLine> lyrics, int index) {
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToLine(lyrics, index);
      });
      return;
    }
    if (index == _lastHighlightIndex && _hasInitialScrolled) return;
    _lastHighlightIndex = index;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final viewportHeight = _scrollController.position.viewportDimension;

    if (maxScroll <= 0.0 && index > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToLine(lyrics, index);
      });
      return;
    }

    final keys = _keysFor(lyrics);
    double target;
    final ctx =
        (index >= 0 && index < keys.length) ? keys[index].currentContext : null;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      final viewportBox =
          Scrollable.of(ctx).context.findRenderObject() as RenderBox?;
      if (box != null && viewportBox != null) {
        final itemCenter = box.localToGlobal(box.size.center(Offset.zero)).dy;
        final viewportCenter =
            viewportBox.localToGlobal(viewportBox.size.center(Offset.zero)).dy;
        target = _scrollController.offset + (itemCenter - viewportCenter);
      } else {
        target = index * 44.0 - (viewportHeight / 2) + 22.0;
      }
    } else {
      target = index * 44.0 - (viewportHeight / 2) + 22.0;
    }

    final clamped = target.clamp(0.0, maxScroll);
    if (!_hasInitialScrolled) {
      _hasInitialScrolled = true;
      _scrollController.jumpTo(clamped);
    } else {
      _scrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.playback,
      builder: (context, _) {
        final track = widget.playback.currentTrack;
        if (track == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
          return const Scaffold(backgroundColor: Color(0xFF0D0D0D));
        }

        final trackKey = '${track.id}_${track.title}_${track.artist}';
        if (trackKey != _lastTrackKey) {
          _lastTrackKey = trackKey;
          _lastHighlightIndex = -1;
          _hasInitialScrolled = false;
        }

        final lyrics = widget.playback.currentLyrics;
        final isLoading = widget.playback.lyricsLoading;

        return Scaffold(
          backgroundColor: const Color(0xFF0D0D0D),
          body: GestureDetector(
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity != null &&
                  details.primaryVelocity! > 300) {
                Navigator.of(context).pop();
              }
            },
            child: SafeArea(
              child: Column(
                children: [
                  SizedBox(
                    height: 76,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            top: 0,
                            child: GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 13,
                                    fontFamily: 'Poppins',
                                  ),
                                ),
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Poppins',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: isLoading
                        ? Center(
                            child: Text(
                              'Loading lyrics...',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 16,
                                fontFamily: 'Poppins',
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                        : (lyrics == null || lyrics.isEmpty)
                            ? Center(
                                child: Text(
                                  'Song has no lyrics',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    fontSize: 16,
                                    fontFamily: 'Poppins',
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              )
                            : StreamBuilder<Duration>(
                                stream: widget.playback.positionStream,
                                builder: (context, snapshot) {
                                  final position =
                                      snapshot.data ?? widget.playback.position;
                                  final idx = LyricsService.currentLineIndex(
                                      lyrics, position);
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (mounted) _scrollToLine(lyrics, idx);
                                  });

                                  return ListView.builder(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 20),
                                    itemCount: lyrics.length,
                                    itemBuilder: (context, i) {
                                      final isCurrent = i == idx;
                                      final distance = (i - idx).abs();
                                      final alpha = isCurrent
                                          ? 1.0
                                          : distance == 1
                                              ? 0.6
                                              : distance == 2
                                                  ? 0.4
                                                  : 0.25;

                                      return GestureDetector(
                                        key: _keysFor(lyrics)[i],
                                        onTap: () {
                                          widget.playback.seek(lyrics[i].time);
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                          child: Text(
                                            lyrics[i].text,
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: alpha),
                                              fontSize: isCurrent ? 20 : 16,
                                              fontWeight: isCurrent
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              fontFamily: 'Poppins',
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: StreamBuilder<Duration>(
                      stream: widget.playback.positionStream,
                      builder: (context, snapshot) {
                        final position =
                            snapshot.data ?? widget.playback.position;
                        final duration = widget.playback.duration;
                        final progress = duration.inMilliseconds > 0
                            ? (position.inMilliseconds /
                                    duration.inMilliseconds)
                                .clamp(0.0, 1.0)
                            : 0.0;

                        return Column(
                          children: [
                            SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                activeTrackColor: const Color(0xFF6C63FF),
                                inactiveTrackColor:
                                    Colors.white.withValues(alpha: 0.15),
                                thumbColor: const Color(0xFF6C63FF),
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14),
                                overlayColor: const Color(0xFF6C63FF)
                                    .withValues(alpha: 0.2),
                              ),
                              child: Slider(
                                value: progress,
                                onChanged: (val) {
                                  final seekPos = Duration(
                                    milliseconds:
                                        (duration.inMilliseconds * val).round(),
                                  );
                                  widget.playback.seek(seekPos);
                                },
                              ),
                            ),
                            Text(
                              _formatDuration(position),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () => widget.playback.toggleShuffle(),
                          child: Image.asset(
                            'asset/musicPlayer_assets/shuffle.png',
                            width: 22,
                            height: 22,
                            color: widget.playback.isShuffle
                                ? const Color(0xFF514AED)
                                : Colors.white38,
                            colorBlendMode: BlendMode.srcIn,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => widget.playback.playPrevious(),
                          child: Icon(
                            Icons.skip_previous_rounded,
                            color: widget.playback.hasPrevious
                                ? Colors.white
                                : Colors.white30,
                            size: 36,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => widget.playback.togglePlayPause(),
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF514AED),
                            ),
                            child: StreamBuilder<PlayerState>(
                              stream: widget.playback.playerStateStream,
                              builder: (context, snapshot) {
                                final isPlaying =
                                    snapshot.data?.playing ?? false;
                                return Icon(
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 36,
                                );
                              },
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            if (!PremiumService().canSkipTrack) {
                              PremiumService.showUpsell(
                                context,
                                reason:
                                    "You've used all 6 skips for this hour. Upgrade for unlimited skips.",
                                feature: 'Skip Limit Reached',
                              );
                              return;
                            }
                            PremiumService().recordSkip();
                            widget.playback.playNext();
                          },
                          child: Icon(
                            Icons.skip_next_rounded,
                            color: widget.playback.hasNext
                                ? Colors.white
                                : Colors.white30,
                            size: 36,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => widget.playback.toggleRepeat(),
                          child: _NowPlayingScreenState._buildRepeatIcon(
                              widget.playback.loopMode),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 55),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}
