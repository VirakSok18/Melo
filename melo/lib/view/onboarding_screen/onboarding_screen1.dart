import 'package:flutter/material.dart';

class OnboardingScreen1 extends StatefulWidget {
  const OnboardingScreen1({super.key});

  @override
  State<OnboardingScreen1> createState() => _OnboardingScreen1State();
}

class _OnboardingScreen1State extends State<OnboardingScreen1>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _slowController;

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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();
    _slowController = AnimationController(
      duration: const Duration(seconds: 12),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _slowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF191919),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 70,
              child: _buildAlbumGrid(),
            ),
            Expanded(
              flex: 30,
              child: _buildBottomContent(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumGrid() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 0, right: 0),
      child: Transform.translate(
        offset: const Offset(0, 0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildScrollingRow(row1Images, false),
              const SizedBox(height: 15),
              _buildScrollingRow(row2Images, true),
              const SizedBox(height: 15),
              _buildFadingScrollingRow(row3Images, false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScrollingRow(List<String> images, bool reverse) {
    final double imageWidth = 160;
    final double imageMargin = 5;
    final double singleSetWidth =
        (imageWidth + imageMargin * 2) * images.length;

    return ClipRect(
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
                      ...images.map((img) => _buildAlbumImage(img, imageWidth)),
                      ...images.map((img) => _buildAlbumImage(img, imageWidth)),
                      ...images.map((img) => _buildAlbumImage(img, imageWidth)),
                      ...images.map((img) => _buildAlbumImage(img, imageWidth)),
                      ...images.map((img) => _buildAlbumImage(img, imageWidth)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildScrollingRowSlow(List<String> images, bool reverse) {
    final double imageWidth = 160;
    final double imageMargin = 5;
    final double singleSetWidth =
        (imageWidth + imageMargin * 2) * images.length;

    return ClipRect(
      child: SizedBox(
        height: 160,
        width: MediaQuery.of(context).size.width,
        child: AnimatedBuilder(
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

            return Stack(
              children: [
                Positioned(
                  left: offset,
                  top: 0,
                  bottom: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...images.map((img) => _buildAlbumImage(img, imageWidth)),
                      ...images.map((img) => _buildAlbumImage(img, imageWidth)),
                      ...images.map((img) => _buildAlbumImage(img, imageWidth)),
                      ...images.map((img) => _buildAlbumImage(img, imageWidth)),
                      ...images.map((img) => _buildAlbumImage(img, imageWidth)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFadingScrollingRow(List<String> images, bool reverse) {
    final double imageWidth = 160;
    final double imageMargin = 5;
    final double singleSetWidth =
        (imageWidth + imageMargin * 2) * images.length;

    return ClipRect(
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
                      ...images.map((img) => _buildAlbumImage(img, imageWidth)),
                      ...images.map((img) => _buildAlbumImage(img, imageWidth)),
                      ...images.map((img) => _buildAlbumImage(img, imageWidth)),
                      ...images.map((img) => _buildAlbumImage(img, imageWidth)),
                      ...images.map((img) => _buildAlbumImage(img, imageWidth)),
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
      padding: const EdgeInsets.only(top: 10, left: 24, right: 24, bottom: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Tired of the same playlis',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Poppins',
                      ),
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
                        child: Icon(
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
            child: Text(
              'Just say your mood. We\'ll do the rest.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
            ),
          ),
          const SizedBox(height: 50),
          _buildGradientButton(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildGradientButton() {
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
        onPressed: () {},
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        child: Text(
          'Continue',
          style: TextStyle(
            color: const Color(0xFF191919),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
        ),
      ),
    );
  }
}
