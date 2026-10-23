import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../premium_screen/pricing_plans_screen.dart';
import '../../widgets/fade_page_route.dart';
import '../../services/playback_service.dart';

class AdPlayerScreen extends StatefulWidget {
  const AdPlayerScreen({super.key});

  static Future<bool?> show(BuildContext context) {
    return Navigator.of(context).push<bool>(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (context, _, __) => const AdPlayerScreen(),
        transitionsBuilder: (context, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<AdPlayerScreen> createState() => _AdPlayerScreenState();
}

class _AdPlayerScreenState extends State<AdPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  final ValueNotifier<int> _skipCountdownNotifier = ValueNotifier<int>(5);
  final ValueNotifier<bool> _canSkipNotifier = ValueNotifier<bool>(false);
  bool _hasFinished = false;
  Timer? _tickerTimer;

  @override
  void initState() {
    super.initState();
    try {
      PlaybackService().stop();
    } catch (_) {}
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      _controller = VideoPlayerController.asset(
        'asset/ads/melo_premium_ad.mp4',
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await _controller.initialize();
      await _controller.setVolume(1.0);
      await _controller.setLooping(false);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }

      await _controller.play();
      _startTimer();
      _controller.addListener(_videoListener);
    } catch (e) {
      debugPrint('[AdPlayer] Error loading ad video: $e');
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && !_hasFinished) {
          _onAdFinished();
        }
      });
    }
  }

  void _videoListener() {
    if (!_controller.value.isInitialized) return;
    final pos = _controller.value.position;
    final dur = _controller.value.duration;
    if (dur > Duration.zero &&
        pos >= dur &&
        pos > const Duration(seconds: 1) &&
        !_hasFinished) {
      _onAdFinished();
    }
  }

  void _startTimer() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _hasFinished) {
        timer.cancel();
        return;
      }
      if (_skipCountdownNotifier.value > 1) {
        _skipCountdownNotifier.value--;
      } else {
        _skipCountdownNotifier.value = 0;
        _canSkipNotifier.value = true;
        timer.cancel();
      }
    });
  }

  void _onAdFinished() {
    if (_hasFinished) return;
    _hasFinished = true;
    _tickerTimer?.cancel();
    try {
      _controller.removeListener(_videoListener);
      _controller.pause();
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  void _onSkipTapped() {
    if (!_canSkipNotifier.value) return;
    HapticFeedback.lightImpact();
    _onAdFinished();
  }

  void _onUpgradeTapped() {
    if (_hasFinished) return;
    _hasFinished = true;
    _tickerTimer?.cancel();
    try {
      _controller.removeListener(_videoListener);
      _controller.pause();
    } catch (_) {}
    Navigator.of(context).pop(false);
    Navigator.of(context).push(
      FadePageRoute(page: const PricingPlansScreen()),
    );
  }

  @override
  void dispose() {
    _hasFinished = true;
    _tickerTimer?.cancel();
    _skipCountdownNotifier.dispose();
    _canSkipNotifier.dispose();
    try {
      _controller.removeListener(_videoListener);
      _controller.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _canSkipNotifier,
      builder: (context, canSkip, _) {
        return PopScope(
          canPop: canSkip,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // Video Player with RepaintBoundary for GPU acceleration
                if (_isInitialized)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 90),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: RepaintBoundary(
                          child: VideoPlayer(_controller),
                        ),
                      ),
                    ),
                  )
                else
                  const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF514AED),
                    ),
                  ),

                // Top Bar: Skip Button / Countdown (Top-Right Only)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: ValueListenableBuilder<int>(
                        valueListenable: _skipCountdownNotifier,
                        builder: (context, countdown, _) {
                          final isUnlocked = countdown == 0;
                          return GestureDetector(
                            onTap: isUnlocked ? _onSkipTapped : null,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isUnlocked
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isUnlocked
                                      ? Colors.white.withValues(alpha: 0.5)
                                      : Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    isUnlocked
                                        ? 'Skip Ad'
                                        : 'Skip in ${countdown}s',
                                    style: TextStyle(
                                      color: isUnlocked
                                          ? Colors.white
                                          : Colors.white60,
                                      fontSize: 12.5,
                                      fontWeight: isUnlocked
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                  if (isUnlocked) ...[
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.skip_next_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // Bottom CTA Banner
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF141419).withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                const Color(0xFF514AED).withValues(alpha: 0.35),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.6),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Melo Premium',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                  Text(
                                    'Zero ads • \$2.99 / month',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.6),
                                      fontSize: 11.5,
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _onUpgradeTapped,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF514AED),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: const Text(
                                'Upgrade',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
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
              ],
            ),
          ),
        );
      },
    );
  }
}
