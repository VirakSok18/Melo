import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../services/voice_normalizer.dart';

class CustomBottomNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isSearchActive;
  final VoidCallback onSearchTap;
  final VoidCallback onSearchClose;
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.isSearchActive,
    required this.onSearchTap,
    required this.onSearchClose,
    this.searchController,
    this.searchFocusNode,
  });

  @override
  State<CustomBottomNavBar> createState() => _CustomBottomNavBarState();
}

class _CustomBottomNavBarState extends State<CustomBottomNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..value = widget.isSearchActive ? 1.0 : 0.0;

  late final Animation<double> _tween = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeOutQuad,
  );

  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (_) {
          if (mounted) setState(() => _isListening = false);
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
      );
    } catch (_) {
      _speechAvailable = false;
    }
  }

  Future<void> _toggleVoiceSearch() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    if (!_speechAvailable) {
      await _initSpeech();
    }

    if (!_speechAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Speech recognition not available on this device'),
            backgroundColor: Color(0xFF191919),
          ),
        );
      }
      return;
    }

    // Ensure search is open and active
    if (!widget.isSearchActive) {
      widget.onSearchTap();
    }
    widget.searchFocusNode?.requestFocus();

    setState(() => _isListening = true);

    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          final text = VoiceNormalizer.normalize(result.recognizedWords);
          widget.searchController?.text = text;
          widget.searchController?.selection =
              TextSelection.collapsed(offset: text.length);

          if (result.finalResult) {
            _speech.stop();
            if (mounted) setState(() => _isListening = false);
          }
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.search,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _isListening = false);
    }
  }

  @override
  void didUpdateWidget(CustomBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSearchActive && !oldWidget.isSearchActive) {
      _controller.forward();
    } else if (!widget.isSearchActive && oldWidget.isSearchActive) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const Color _pillColor = Color(0xFF1F1F1F);
  static const Color _activeHighlight = Color(0xFF393939);
  static const Color _activeColor = Color(0xFF514AED);
  static const Color _inactiveColor = Colors.white54;

  static const BoxShadow _shadow = BoxShadow(
    color: Color(0x99000000),
    offset: Offset(0, 7),
    blurRadius: 14,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      child: AnimatedBuilder(
        animation: _tween,
        builder: (context, _) {
          final t = _tween.value;
          final screenWidth = MediaQuery.of(context).size.width - 32;
          const gap = 8.0;
          const circleSize = 54.0;
          final available = screenWidth - gap - circleSize * 2;

          final pillWidth = circleSize + (1.0 - t) * available;
          final searchWidth = circleSize + t * available;

          return SizedBox(
            height: 54,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left: Navigation pill morphs into back button
                SizedBox(
                  width: pillWidth,
                  height: 54,
                  child: _buildNavPill(t),
                ),
                const SizedBox(width: gap),
                // Right: Search circle morphs into full search bar
                SizedBox(
                  width: searchWidth,
                  height: 54,
                  child: _buildSearchPill(t),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavPill(double t) {
    final navOpacity = (1.0 - t * 2.2).clamp(0.0, 1.0);
    final backIconOpacity = ((t - 0.45) * 2.0).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth - 12;
        final sectionWidth = totalWidth / 3;
        final targetLeft = sectionWidth * widget.currentIndex + 6;

        return Container(
          height: 54,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _pillColor,
            borderRadius: BorderRadius.circular(27),
            boxShadow: const [_shadow],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (navOpacity > 0.0)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  left: targetLeft,
                  top: 4,
                  bottom: 4,
                  width: sectionWidth,
                  child: Opacity(
                    opacity: navOpacity,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _activeHighlight,
                        borderRadius: BorderRadius.circular(23),
                      ),
                    ),
                  ),
                ),
              if (navOpacity > 0.0)
                IgnorePointer(
                  ignoring: t > 0.3,
                  child: Opacity(
                    opacity: navOpacity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: SizedBox(
                        height: 54,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                                child: _buildNavItem(
                                    0,
                                    'asset/NavBarIcon/Home.png',
                                    'asset/NavBarIcon/home selected.png',
                                    'Home')),
                            Expanded(
                                child: _buildNavItem(
                                    1,
                                    'asset/NavBarIcon/Generator.png',
                                    'asset/NavBarIcon/generate selected.png',
                                    'Generate')),
                            Expanded(
                                child: _buildNavItem(
                                    2,
                                    'asset/NavBarIcon/Playlist.png',
                                    'asset/NavBarIcon/library selected.png',
                                    'Library')),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (backIconOpacity > 0.0)
                IgnorePointer(
                  ignoring: t < 0.5,
                  child: Opacity(
                    opacity: backIconOpacity,
                    child: GestureDetector(
                      onTap: () {
                        _controller.reverse();
                        widget.onSearchClose();
                      },
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox(
                        width: 54,
                        height: 54,
                        child: Center(
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white70,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchPill(double t) {
    final searchIconOpacity = (1.0 - t * 2.2).clamp(0.0, 1.0);
    final searchBarOpacity = ((t - 0.35) * 1.6).clamp(0.0, 1.0);

    return Container(
      height: 54,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _pillColor,
        borderRadius: BorderRadius.circular(27),
        boxShadow: const [_shadow],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (searchIconOpacity > 0.0)
            Opacity(
              opacity: searchIconOpacity,
              child: GestureDetector(
                onTap: widget.onSearchTap,
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: Image.asset(
                    'asset/NavBarIcon/Search.png',
                    width: 22,
                    height: 22,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          if (searchBarOpacity > 0.0)
            Opacity(
              opacity: searchBarOpacity,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: 14),
                  const Icon(Icons.search, color: Colors.white38, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: widget.searchController,
                      focusNode: widget.searchFocusNode,
                      textAlignVertical: TextAlignVertical.center,
                      strutStyle: const StrutStyle(
                        fontFamily: 'Poppins',
                        fontFamilyFallback: [
                          'Kantumruy Pro',
                          'Battambang',
                          'Noto Sans Khmer',
                          'Khmer OS Siemreap',
                          'Khmer OS',
                          'sans-serif',
                        ],
                        fontSize: 14,
                        height: 1.4,
                        forceStrutHeight: false,
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontFamily: 'Poppins',
                        fontFamilyFallback: [
                          'Kantumruy Pro',
                          'Battambang',
                          'Noto Sans Khmer',
                          'Khmer OS Siemreap',
                          'Khmer OS',
                          'sans-serif',
                        ],
                        height: 1.4,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'What do you want to listen to?',
                        hintStyle: TextStyle(
                          color: Colors.white38,
                          fontSize: 13.5,
                          fontFamily: 'Poppins',
                          fontFamilyFallback: [
                            'Kantumruy Pro',
                            'Battambang',
                            'Noto Sans Khmer',
                            'Khmer OS Siemreap',
                            'Khmer OS',
                            'sans-serif',
                          ],
                          height: 1.4,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _toggleVoiceSearch,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isListening
                            ? _activeColor.withValues(alpha: 0.25)
                            : Colors.transparent,
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? _activeColor : Colors.white60,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
      int index, String iconPath, String activeIconPath, String label) {
    final bool isActive = widget.currentIndex == index;

    return GestureDetector(
      onTap: () => widget.onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedOpacity(
                    opacity: isActive ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    child: Image.asset(
                      iconPath,
                      width: 22,
                      height: 22,
                      fit: BoxFit.contain,
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: isActive ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    child: Image.asset(
                      activeIconPath,
                      width: 22,
                      height: 22,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                color: isActive ? _activeColor : _inactiveColor,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
