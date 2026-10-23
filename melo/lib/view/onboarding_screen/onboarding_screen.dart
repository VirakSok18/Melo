import 'package:flutter/material.dart';
import '../sign_in_screen/sign_in_screen.dart';
import '../../widgets/fade_page_route.dart';
import 'data_management_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  int _currentPage = 0;

  late AnimationController _contentController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  late AnimationController _controller;
  late AnimationController _slowController;

  static const TextStyle _titleStyle = TextStyle(
    color: Color(0xE6FFFFFF),
    fontSize: 16,
    fontWeight: FontWeight.w900,
    fontFamily: 'Poppins',
  );

  static const TextStyle _subtitleStyle = TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.bold,
    fontFamily: 'Poppins',
  );

  static const TextStyle _privacyLabelStyle = TextStyle(
    color: Color(0x80FFFFFF),
    fontSize: 10,
    fontFamily: 'Poppins',
  );

  static const TextStyle _privacyLinkStyle = TextStyle(
    color: Colors.white,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    fontFamily: 'Poppins',
  );

  static const TextStyle _buttonTextStyle = TextStyle(
    color: Color(0xFF191919),
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontFamily: 'Poppins',
  );

  final List<String> row1Images = [
    'asset/onboarding_screen_1_assets/Rectangle 2.png',
    'asset/onboarding_screen_1_assets/Rectangle 4.png',
    'asset/onboarding_screen_1_assets/Rectangle 5.png',
  ];

  final List<String> row2Images = [
    'asset/onboarding_screen_1_assets/Rectangle 4-1.png',
    'asset/onboarding_screen_1_assets/Rectangle 4-2.png',
    'asset/onboarding_screen_1_assets/Rectangle 4-3.png',
  ];

  final List<String> row3Images = [
    'asset/onboarding_screen_1_assets/Rectangle 10.png',
    'asset/onboarding_screen_1_assets/Rectangle 11.png',
    'asset/onboarding_screen_1_assets/Rectangle 4-4.png',
  ];

  late final List<Widget> _row1ImageWidgets;
  late final List<Widget> _row2ImageWidgets;
  late final List<Widget> _row3ImageWidgets;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );
    _slowController = AnimationController(
      duration: const Duration(seconds: 12),
      vsync: this,
    );

    _row1ImageWidgets =
        row1Images.map((img) => _buildAlbumImage(img, 160)).toList();
    _row2ImageWidgets =
        row2Images.map((img) => _buildAlbumImage(img, 160)).toList();
    _row3ImageWidgets =
        row3Images.map((img) => _buildAlbumImage(img, 160)).toList();

    _contentController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.3, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.easeOutCubic),
    );

    _contentController.forward();
    _startScrollAnimations();
  }

  void _startScrollAnimations() {
    if (_currentPage == 0) {
      _controller.repeat();
      _slowController.repeat();
    }
  }

  void _stopScrollAnimations() {
    _controller.stop();
    _slowController.stop();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _controller.dispose();
    _slowController.dispose();
    super.dispose();
  }

  void _goToPage(int targetPage) {
    if (targetPage == _currentPage || targetPage < 0 || targetPage > 2) return;
    final isForward = targetPage > _currentPage;
    _stopScrollAnimations();
    _contentController.reverse().then((_) {
      if (!mounted) return;
      _slideAnimation = Tween<Offset>(
        begin: Offset(isForward ? 0.3 : -0.3, 0.0),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(parent: _contentController, curve: Curves.easeOutCubic),
      );
      setState(() {
        _currentPage = targetPage;
      });
      _contentController.forward();
      _startScrollAnimations();
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (details.primaryVelocity == null) return;
    if (details.primaryVelocity! < -200) {
      // Swiped left -> next page
      if (_currentPage < 2) {
        _goToPage(_currentPage + 1);
      }
    } else if (details.primaryVelocity! > 200) {
      // Swiped right -> previous page
      if (_currentPage > 0) {
        _goToPage(_currentPage - 1);
      }
    }
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _goToPage(_currentPage + 1);
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const SignInScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeInOut),
            );
            final slideAnimation = Tween<Offset>(
              begin: const Offset(0.0, 0.1),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
            return FadeTransition(
              opacity: fadeAnimation,
              child: SlideTransition(
                position: slideAnimation,
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF191919),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          child: Column(
            children: [
              Expanded(
                flex: 70,
                child: AnimatedBuilder(
                  animation: _contentController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _fadeAnimation.value,
                      child: Transform.translate(
                        offset: _slideAnimation.value * 30,
                        child: _buildTopContent(),
                      ),
                    );
                  },
                ),
              ),
              _buildPageIndicator(),
              Expanded(
                flex: 30,
                child: _buildBottomContent(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var page = 0; page < 3; page++)
            GestureDetector(
              onTap: () => _goToPage(page),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  width: page == _currentPage ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: page == _currentPage
                        ? const Color(0xFF514AED)
                        : Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopContent() {
    switch (_currentPage) {
      case 0:
        return _buildAlbumGrid();
      case 1:
        return _buildScreen2Image();
      case 2:
        return _buildScreen3Image();
      default:
        return _buildAlbumGrid();
    }
  }

  Widget _buildAlbumGrid() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 0, right: 0),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildScrollingRow(_row1ImageWidgets, false),
              const SizedBox(height: 15),
              _buildScrollingRow(_row2ImageWidgets, true),
              const SizedBox(height: 15),
              _buildFadingScrollingRow(_row3ImageWidgets, false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScreen2Image() {
    return OverflowBox(
      alignment: Alignment.topCenter,
      maxHeight: double.infinity,
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, 10),
          child: Transform.scale(
            scale: 1.18,
            alignment: Alignment.topCenter,
            child: Image.asset(
              'asset/onboarding_screen_2_assets/Mask group.png',
              width: MediaQuery.of(context).size.width,
              fit: BoxFit.fitWidth,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.phone_iphone,
                      color: Colors.white38,
                      size: 100,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScreen3Image() {
    return OverflowBox(
      alignment: Alignment.topCenter,
      maxHeight: double.infinity,
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.white,
              Colors.transparent,
              Colors.transparent,
            ],
            stops: [0.0, 0.70, 0.90, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: Transform.translate(
          offset: const Offset(0, 15),
          child: Transform.scale(
            scale: 1.10,
            alignment: Alignment.topCenter,
            child: Image.asset(
              'asset/onboarding_screen_3_assets/lady.png',
              width: MediaQuery.of(context).size.width,
              fit: BoxFit.fitWidth,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.headphones_rounded,
                      color: Colors.white38,
                      size: 100,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollingRow(List<Widget> images, bool reverse) {
    final double imageWidth = 160;
    final double imageMargin = 5;
    final double singleSetWidth =
        (imageWidth + imageMargin * 2) * images.length;

    return RepaintBoundary(
      child: ClipRect(
        child: SizedBox(
          height: 160,
          width: MediaQuery.of(context).size.width,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              double progress = _controller.value % 1.0;
              double scrollAmount = progress * singleSetWidth;
              double offset;

              if (reverse) {
                offset = -singleSetWidth + scrollAmount;
              } else {
                offset = -scrollAmount;
              }

              return Stack(
                children: [
                  Positioned(
                    left: offset,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...images,
                        ...images,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFadingScrollingRow(List<Widget> images, bool reverse) {
    final double imageWidth = 160;
    final double imageMargin = 5;
    final double singleSetWidth =
        (imageWidth + imageMargin * 2) * images.length;

    return RepaintBoundary(
      child: ClipRect(
        child: SizedBox(
          height: 160,
          width: MediaQuery.of(context).size.width,
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: _slowController,
                builder: (context, child) {
                  double progress = _slowController.value % 1.0;
                  double scrollAmount = progress * singleSetWidth;
                  double offset;

                  if (reverse) {
                    offset = -singleSetWidth + scrollAmount;
                  } else {
                    offset = -scrollAmount;
                  }

                  return Positioned(
                    left: offset,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...images,
                        ...images,
                      ],
                    ),
                  );
                },
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 100,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF191919).withValues(alpha: 0),
                        const Color(0xFF191919),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumImage(String assetPath, double size) {
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: const Color(0xFF2D2D44),
              child: const Icon(
                Icons.music_note,
                color: Colors.white38,
                size: 40,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 10, bottom: 10),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _contentController,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: _buildTitle(),
              );
            },
          ),
          const Spacer(),
          _buildGradientButton(),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    children: [
                      WidgetSpan(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Image.asset(
                            'asset/onboarding_screen_1_assets/Vector.png',
                            width: 10,
                            height: 10,
                          ),
                        ),
                      ),
                      const TextSpan(text: ' '),
                      const TextSpan(
                        text:
                            'Your listening history helps us build better playlists and personalize your experience. ',
                        style: _privacyLabelStyle,
                      ),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              FadePageRoute(page: const DataManagementScreen()),
                            );
                          },
                          child: ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [
                                Color(0xFF514AED),
                                Color(0xFFFFFFFF),
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ).createShader(bounds),
                            child: const Text(
                              'See how your data is managed.',
                              style: _privacyLinkStyle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    switch (_currentPage) {
      case 0:
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Tired of the same playlis',
                        style: _titleStyle,
                      ),
                      WidgetSpan(
                        child: ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [
                              Color(0xFF514AED),
                              Colors.white,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds),
                          child: const Icon(
                            Icons.music_note,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  Color(0xFF514AED),
                  Colors.white,
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ).createShader(bounds),
              child: const Text(
                'Just say your mood. We\'ll do the rest.',
                textAlign: TextAlign.center,
                style: _subtitleStyle,
              ),
            ),
          ],
        );
      case 1:
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Fresh music every day',
                  style: _titleStyle,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  Color(0xFF514AED),
                  Colors.white,
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ).createShader(bounds),
              child: const Text(
                'New songs picked just for you. single day.',
                textAlign: TextAlign.center,
                style: _subtitleStyle,
              ),
            ),
          ],
        );
      case 2:
        return Transform.translate(
          offset: const Offset(-70, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Listen ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF514AED), Colors.white],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ).createShader(bounds),
                    child: const Text(
                      'together',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF514AED), Colors.white],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ).createShader(bounds),
                    child: const Text(
                      'wherever ',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                  const Text(
                    'you are',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildGradientButton() {
    final bool isLastPage = _currentPage == 2;
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF514AED),
            Colors.white,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: ElevatedButton(
        onPressed: _nextPage,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isLastPage ? 'Get Started' : 'Continue',
              style: _buttonTextStyle,
            ),
            if (isLastPage) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.music_note,
                color: const Color(0xFF0D0D0D).withValues(alpha: 0.8),
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
