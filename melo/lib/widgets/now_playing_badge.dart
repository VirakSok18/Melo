import 'dart:math';
import 'package:flutter/material.dart';
import '../services/playback_service.dart';

/// True if [trackId]/[title]/[artist] refers to the currently playing track.
bool isCurrentTrack({String? trackId, required String title, required String artist}) {
  final current = PlaybackService().currentTrack;
  if (current == null) return false;
  if (trackId != null && trackId.isNotEmpty && current.id.isNotEmpty) {
    if (current.id == trackId) return true;
  }
  return current.title == title && current.artist == artist;
}

/// Animated equalizer bars shown in track lists to indicate the
/// currently playing song. Uses an independent repeating controller so
/// it works anywhere without its parent ticking.
class NowPlayingBars extends StatefulWidget {
  final bool playing;
  final Color color;
  final double barWidth;
  final int bars;

  const NowPlayingBars({
    super.key,
    required this.playing,
    this.color = const Color(0xFF514AED),
    this.barWidth = 2.5,
    this.bars = 5,
  });

  @override
  State<NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<NowPlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(NowPlayingBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0.35;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: widget.bars * (widget.barWidth + 2),
            height: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(widget.bars, (i) {
                final seed = (i + 1) * 0.7;
                final raw = sin((_controller.value * 2 * pi) + seed);
                final height = widget.playing
                    ? (4.0 + (raw.abs() * 8.0))
                    : 3.5;
                return Container(
                  width: widget.barWidth,
                  height: height,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(1.2),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}

/// Wraps a track row and rebuilds when playback changes, exposing
/// [isCurrent] so the caller can style the row (highlight title, swap the
/// number for animated bars, etc).
class TrackHighlight extends StatelessWidget {
  final String? trackId;
  final String title;
  final String artist;
  final Widget Function(BuildContext context, bool isCurrent) builder;

  const TrackHighlight({
    super.key,
    this.trackId,
    required this.title,
    required this.artist,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlaybackService(),
      builder: (context, _) {
        final isCurrent = isCurrentTrack(
          trackId: trackId,
          title: title,
          artist: artist,
        );
        return builder(context, isCurrent);
      },
    );
  }
}
