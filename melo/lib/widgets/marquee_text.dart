import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.center,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  final GlobalKey _textMeasureKey = GlobalKey();

  double _exactTextWidth = 0.0;
  double _textHeight = 0.0;

  static const double _gap = 40.0;
  static const double _startPadding = 0.0;
  static const double _startPause = 0.18; // ~2s pause at start
  static const double _endPause = 0.82; // ~2s pause at end

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
  }

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _controller.reset();
      _exactTextWidth = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _checkRenderedSize() {
    final ctx = _textMeasureKey.currentContext;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && box.size.width > 0) {
        final measured = box.size.width;
        if ((measured - _exactTextWidth).abs() > 0.5) {
          setState(() {
            _exactTextWidth = measured;
            _textHeight = box.size.height + 2;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        // Initial measurement
        if (_exactTextWidth <= 0) {
          final tp = TextPainter(
            text: TextSpan(text: widget.text, style: widget.style),
            maxLines: 1,
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout();
          _exactTextWidth = tp.width;
          _textHeight = tp.height + 2;
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _checkRenderedSize();
        });

        final shouldMarquee = availableWidth.isFinite &&
            availableWidth > 0 &&
            (_exactTextWidth + _startPadding) > availableWidth;

        if (!shouldMarquee) {
          if (_controller.isAnimating) {
            _controller.stop();
          }
          return Text(
            widget.text,
            key: _textMeasureKey,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: widget.textAlign,
          );
        }

        final singleSetWidth = _exactTextWidth + _gap;
        final scrollSeconds = (singleSetWidth / 35.0).clamp(5.0, 16.0);
        final totalSeconds = scrollSeconds / (_endPause - _startPause);
        final desiredDuration =
            Duration(milliseconds: (totalSeconds * 1000).round());

        if (_controller.duration != desiredDuration) {
          _controller.duration = desiredDuration;
        }
        if (!_controller.isAnimating) {
          _controller.repeat();
        }

        return SizedBox(
          width: availableWidth,
          height: _textHeight > 0 ? _textHeight : 24,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              double scrollAmount;
              if (t <= _startPause) {
                // Pause at start position
                scrollAmount = 0.0;
              } else if (t >= _endPause) {
                // Pause at end position (identical visual match to start)
                scrollAmount = singleSetWidth;
              } else {
                // Linear scroll between start and end
                final progress = (t - _startPause) / (_endPause - _startPause);
                scrollAmount = progress * singleSetWidth;
              }

              return ShaderMask(
                shaderCallback: (Rect bounds) {
                  return const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black,
                      Colors.black,
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.92, 1.0],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.dstIn,
                child: ClipRect(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: _startPadding - scrollAmount,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              key: _textMeasureKey,
                              child: Text(
                                widget.text,
                                style: widget.style,
                                maxLines: 1,
                              ),
                            ),
                            const SizedBox(width: _gap),
                            Text(
                              widget.text,
                              style: widget.style,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
