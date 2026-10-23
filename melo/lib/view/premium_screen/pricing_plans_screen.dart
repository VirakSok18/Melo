import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/premium_service.dart';
import '../../services/cookie_service.dart';
import 'payment_method_picker_sheet.dart';

class PricingPlansScreen extends StatefulWidget {
  final int initialTabIndex; // 0 for Monthly, 1 for Yearly
  const PricingPlansScreen({super.key, this.initialTabIndex = 0});

  @override
  State<PricingPlansScreen> createState() => _PricingPlansScreenState();
}

class _PricingPlansScreenState extends State<PricingPlansScreen> {
  late int _selectedTab; // 0 = Monthly, 1 = Yearly
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTabIndex;
    _pageController = PageController(initialPage: _selectedTab);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabChanged(int index) {
    if (_selectedTab == index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedTab = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
  }

  void _handleSubscribe(PremiumPlanType plan) {
    HapticFeedback.mediumImpact();
    PaymentMethodPickerSheet.show(
      context,
      plan: plan,
      onSuccess: () {
        if (mounted) {
          setState(() {});
          CookieService.show(
            message:
                'Upgraded to ${plan == PremiumPlanType.yearly ? "Premium Yearly" : "Premium Monthly"}!',
            icon: Icons.workspace_premium_rounded,
            iconColor: const Color(0xFF817BFF),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final premiumService = PremiumService();

    return ListenableBuilder(
      listenable: premiumService,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF141414),
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Top Nav Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.06),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
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
                      // Top Toggle: Monthly | Annual
                      _buildTopToggle(),
                      const SizedBox(width: 44), // balance
                    ],
                  ),
                ),

                // Title & Tagline
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Column(
                    children: [
                      const Text(
                        'Choose Your Plan',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Poppins',
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Unlock unlimited songs, offline mode, & AI playlist generator',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12.5,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Page Carousel (Monthly first, then Annual)
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (page) {
                      setState(() {
                        _selectedTab = page;
                      });
                    },
                    children: [
                      _buildPlanCard(
                        plan: PremiumPlanType.monthly,
                        isCurrent:
                            premiumService.plan == PremiumPlanType.monthly,
                        title: '1 Month Pro Pass',
                        tag: '30 DAYS',
                        price: '\$2.99',
                        period: 'one-time',
                        subPrice: '\$2.99 • 30 days access',
                        description:
                            'Full premium music and AI perks with no auto-renewal.',
                        features: const [
                          _FeatureItem('AI Playlist Generator',
                              'Unlimited generations', true),
                          _FeatureItem(
                              'Hourly Skips', 'Unlimited skips anytime', true),
                          _FeatureItem('Offline Downloads',
                              'Unlimited song downloads', true),
                          _FeatureItem('Listen Along',
                              'Full real-time sync with friends', true),
                          _FeatureItem('Advertisements',
                              '100% Ad-Free (audio & banners)', true),
                          _FeatureItem('Synced Lyrics & Daily Vibe',
                              'Full lyrics & smart mixes included', true),
                        ],
                        gradientColors: const [
                          Color(0xFF4361EE),
                          Color(0xFF3A0CA3),
                          Color(0xFF1A1A2E),
                        ],
                      ),
                      _buildPlanCard(
                        plan: PremiumPlanType.yearly,
                        isCurrent:
                            premiumService.plan == PremiumPlanType.yearly,
                        title: '1 Year Pro Pass',
                        tag: 'SAVE 30%',
                        price: '\$24.99',
                        period: 'one-time',
                        subPrice: '\$24.99 • 365 days access',
                        description:
                            'Maximum savings with full access to all Melo features.',
                        features: const [
                          _FeatureItem('AI Playlist Generator',
                              'Unlimited generations', true),
                          _FeatureItem(
                              'Hourly Skips', 'Unlimited skips anytime', true),
                          _FeatureItem('Offline Downloads',
                              'Unlimited song downloads', true),
                          _FeatureItem('Listen Along',
                              'Full real-time sync with friends', true),
                          _FeatureItem('Advertisements',
                              '100% Ad-Free (audio & banners)', true),
                          _FeatureItem('Synced Lyrics & Daily Vibe',
                              'Full lyrics & smart mixes included', true),
                        ],
                        gradientColors: const [
                          Color(0xFF635BFF),
                          Color(0xFF3F37C9),
                          Color(0xFF1E1A3C),
                        ],
                      ),
                    ],
                  ),
                ),

                // Free Tier Comparison Link / Note
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Free tier includes 2 AI trials & 6 skips/hr. Terms apply.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopToggle() {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleItem(
            title: '1 Month',
            isSelected: _selectedTab == 0,
            onTap: () => _onTabChanged(0),
          ),
          _buildToggleItem(
            title: '1 Year',
            badge: 'Save 30%',
            isSelected: _selectedTab == 1,
            onTap: () => _onTabChanged(1),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleItem({
    required String title,
    String? badge,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF514AED) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF514AED).withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontFamily: 'Poppins',
              ),
            ),
            if (badge != null && isSelected) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required PremiumPlanType plan,
    required bool isCurrent,
    required String title,
    required String tag,
    required String price,
    required String period,
    required String subPrice,
    required String description,
    required List<_FeatureItem> features,
    required List<Color> gradientColors,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              gradientColors[0].withValues(alpha: 0.3),
              const Color(0xFF1E1E1E),
              const Color(0xFF181818),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: isCurrent
                ? const Color(0xFF22C55E)
                : gradientColors[0].withValues(alpha: 0.4),
            width: isCurrent ? 2 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: gradientColors[0].withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header tag & Active badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: gradientColors[0].withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: gradientColors[0].withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        color: const Color(0xFF817BFF),
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins',
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  if (isCurrent)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF22C55E),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              color: Color(0xFF22C55E), size: 12),
                          SizedBox(width: 4),
                          Text(
                            'Active Plan',
                            style: TextStyle(
                              color: Color(0xFF22C55E),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 8),

              // Price
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    price,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Poppins',
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    period,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
              Text(
                subPrice,
                style: const TextStyle(
                  color: Color(0xFF817BFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 12),

              Text(
                description,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12.5,
                  fontFamily: 'Poppins',
                  height: 1.4,
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(color: Colors.white12, height: 1),
              ),

              // Features List
              const Text(
                'WHAT\'S INCLUDED',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 12),
              ...features.map((f) => _buildFeatureRow(f)),

              const SizedBox(height: 24),

              // Action Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isCurrent ? null : () => _handleSubscribe(plan),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isCurrent
                        ? Colors.white.withValues(alpha: 0.1)
                        : const Color(0xFF514AED),
                    disabledBackgroundColor:
                        Colors.white.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    elevation: isCurrent ? 0 : 6,
                    shadowColor: const Color(0xFF514AED).withValues(alpha: 0.5),
                  ),
                  child: Text(
                    isCurrent
                        ? 'Current Active Plan'
                        : (plan == PremiumPlanType.yearly
                            ? 'Upgrade to Annual'
                            : 'Upgrade to Monthly'),
                    style: TextStyle(
                      color: isCurrent ? Colors.white54 : Colors.white,
                      fontSize: 15,
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
    );
  }

  Widget _buildFeatureRow(_FeatureItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_rounded,
              color: Color(0xFF22C55E),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
                Text(
                  item.subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontFamily: 'Poppins',
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

class _FeatureItem {
  final String title;
  final String subtitle;
  final bool included;
  const _FeatureItem(this.title, this.subtitle, this.included);
}
