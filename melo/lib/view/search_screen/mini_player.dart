import '../../widgets/cached_image.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/playback_service.dart';
import '../../services/presence_service.dart';
import '../../services/premium_service.dart';
import '../../widgets/marquee_text.dart';
import '../now_playing_screen/now_playing_screen.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> with TickerProviderStateMixin {
  late AnimationController _eqController;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _eqController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _eqController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlaybackService(),
      builder: (context, _) {
        final playback = PlaybackService();

        if (!playback.isVisible || playback.currentTrack == null) {
          return const SizedBox.shrink();
        }

        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              // Only allow swiping to the left (negative dx)
              _dragOffset = (_dragOffset + details.delta.dx).clamp(-120.0, 0.0);
            });
          },
          onHorizontalDragEnd: (details) {
            // Dismiss if dragged far enough left or flung left
            final shouldClose = _dragOffset < -60 ||
                (details.primaryVelocity != null &&
                    details.primaryVelocity! < -400);
            if (shouldClose) {
              // Detach from friend session so incoming broadcast does not immediately respawn playback
              PresenceService().stopListeningWith();
              PlaybackService().reset();
              _dragOffset = 0;
            } else {
              setState(() => _dragOffset = 0);
            }
          },
          child: Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 400),
                    reverseTransitionDuration:
                        const Duration(milliseconds: 350),
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const NowPlayingScreen(),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                      final slideAnimation = Tween<Offset>(
                        begin: const Offset(0, 1),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ));
                      final fadeAnimation = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeInOut,
                      );
                      return SlideTransition(
                        position: slideAnimation,
                        child: FadeTransition(
                          opacity: fadeAnimation,
                          child: child,
                        ),
                      );
                    },
                  ),
                );
              },
              child: Container(
                height: 56,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1F1F),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    _buildAlbumArt(playback),
                    const SizedBox(width: 10),
                    _buildTrackInfo(playback),
                    const SizedBox(width: 6),
                    _buildEqualizer(playback),
                    const SizedBox(width: 20),
                    _buildPrevButton(),
                    const SizedBox(width: 14),
                    _buildPlayPauseButton(playback),
                    const SizedBox(width: 14),
                    _buildNextButton(),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumArt(PlaybackService playback) {
    return StreamBuilder<Duration>(
      stream: playback.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? playback.position;
        final duration = playback.duration;
        final progress = duration.inMilliseconds > 0
            ? (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0)
            : 0.0;

        return SizedBox(
          width: 44,
          height: 44,
          child: CustomPaint(
            painter: _CircularProgressPainter(
              progress: progress,
              color: const Color(0xFF514AED),
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              strokeWidth: 3.5,
            ),
            child: Center(
              child: ClipOval(
                child: Container(
                  width: 38,
                  height: 38,
                  color: const Color(0xFF2A2A2A),
                  child: playback.currentTrack!.image.isNotEmpty
                      ? CachedImage(
                          playback.currentTrack!.image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.music_note,
                            color: Colors.white38,
                            size: 16,
                          ),
                        )
                      : const Icon(
                          Icons.music_note,
                          color: Colors.white38,
                          size: 16,
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrackInfo(PlaybackService playback) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarqueeText(
              text: playback.currentTrack!.title,
              textAlign: TextAlign.left,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'Playing',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEqualizer(PlaybackService playback) {
    return AnimatedBuilder(
      animation: _eqController,
      builder: (context, _) {
        return SizedBox(
          width: 24,
          height: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(5, (i) {
              final seed = (i + 1) * 0.7;
              final raw = sin((_eqController.value * 2 * pi) + seed);
              final height =
                  playback.isPlaying ? (4.0 + (raw.abs() * 12.0)) : 3.0;
              return Container(
                width: 2.5,
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: 0.8),
                decoration: BoxDecoration(
                  color: const Color(0xFF514AED),
                  borderRadius: BorderRadius.circular(1.2),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildPrevButton() {
    final playback = PlaybackService();
    return GestureDetector(
      onTap: () => playback.playPrevious(),
      child: Icon(
        Icons.skip_previous_rounded,
        color: playback.hasPrevious ? Colors.white54 : Colors.white24,
        size: 22,
      ),
    );
  }

  Widget _buildPlayPauseButton(PlaybackService playback) {
    return GestureDetector(
      onTap: () => playback.togglePlayPause(),
      child: Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          color: Color(0xFF514AED),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            playback.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildNextButton() {
    final playback = PlaybackService();
    return GestureDetector(
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
        color: playback.hasNext ? Colors.white54 : Colors.white24,
        size: 22,
      ),
    );
  }
}

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;

  _CircularProgressPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 2;

    canvas.drawCircle(center, radius, bgPaint);

    final outlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 1;

    final startAngle = -pi / 2;
    final sweepAngle = 2 * pi * progress;

    if (sweepAngle > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        outlinePaint,
      );
    }

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
