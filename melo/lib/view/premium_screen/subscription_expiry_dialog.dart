import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/premium_service.dart';
import '../../services/cookie_service.dart';
import '../../widgets/fade_page_route.dart';
import 'pricing_plans_screen.dart';

class SubscriptionExpiryDialog {
  static const String _keyLastShownDate =
      'melo_sub_expiry_popup_last_shown_date';

  /// Checks whether to show the daily 1-2 day warning or expired dialog on app open.
  /// Shows only ONCE per calendar day.
  static Future<void> checkAndShow(
    BuildContext context, {
    bool force = false,
  }) async {
    return;
  }

  /// Minimal clean dialog when 1-2 days remain on user's subscription
  static void showExpiringSoonDialog(
    BuildContext context, {
    required int daysLeft,
    required DateTime expiryDate,
  }) {
    HapticFeedback.lightImpact();
    final dayLabel = daysLeft == 1 ? '1 day' : '$daysLeft days';
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final formattedDate =
        '${months[expiryDate.month - 1]} ${expiryDate.day}, ${expiryDate.year}';

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF18181D),
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Melo Pro Ends in $dayLabel',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your access expires on $formattedDate. Extend your plan to keep your premium perks.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  fontFamily: 'Poppins',
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        child: Text(
                          'Maybe Later',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          Navigator.of(context).push(
                            FadePageRoute(page: const PricingPlansScreen()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF514AED),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        child: const Text(
                          'Extend Plan',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Minimal clean dialog when subscription has expired
  static void showExpiredDialog(BuildContext context) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF18181D),
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Melo Pro Expired',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your pass has expired. Renew your plan to restore full access.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  fontFamily: 'Poppins',
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        child: Text(
                          'Close',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          Navigator.of(context).push(
                            FadePageRoute(page: const PricingPlansScreen()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF514AED),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        child: const Text(
                          'Renew Plan',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Debug bottom sheet to test all expiry popup states
  static void showDebugMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.bug_report_rounded,
                      color: Color(0xFF817BFF), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Subscription Expiry Debugger',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildDebugTile(
                icon: Icons.timer_outlined,
                title: 'Test 2 Days Left Popup',
                subtitle: 'Forces preview of 2 days remaining dialog',
                color: const Color(0xFF817BFF),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  final tomorrow2 = DateTime.now().add(const Duration(days: 2));
                  showExpiringSoonDialog(
                    context,
                    daysLeft: 2,
                    expiryDate: tomorrow2,
                  );
                },
              ),
              const SizedBox(height: 8),
              _buildDebugTile(
                icon: Icons.hourglass_bottom_rounded,
                title: 'Test 1 Day Left Popup',
                subtitle: 'Forces preview of 1 day remaining dialog',
                color: const Color(0xFF817BFF),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  final tomorrow = DateTime.now().add(const Duration(days: 1));
                  showExpiringSoonDialog(
                    context,
                    daysLeft: 1,
                    expiryDate: tomorrow,
                  );
                },
              ),
              const SizedBox(height: 8),
              _buildDebugTile(
                icon: Icons.lock_clock_rounded,
                title: 'Test Expired Today Popup',
                subtitle: 'Forces preview of subscription ended dialog',
                color: const Color(0xFF817BFF),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  showExpiredDialog(context);
                },
              ),
              const SizedBox(height: 8),
              _buildDebugTile(
                icon: Icons.refresh_rounded,
                title: "Reset Today's Shown Status",
                subtitle: 'Allows the daily popup to trigger again today',
                color: const Color(0xFF817BFF),
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove(_keyLastShownDate);
                  if (context.mounted) {
                    CookieService.show(
                      message:
                          'Daily popup flag reset! Will check on next app launch.',
                      icon: Icons.check_circle_rounded,
                      iconColor: const Color(0xFF817BFF),
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
              _buildDebugTile(
                icon: Icons.calendar_today_rounded,
                title: 'Set Real Expiry to Tomorrow (1 Day)',
                subtitle: 'Updates PremiumService nextBillingDate to +1 day',
                color: const Color(0xFF22C55E),
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  final tomorrow = DateTime.now().add(const Duration(days: 1));
                  await PremiumService().debugSetNextBillingDate(tomorrow);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove(_keyLastShownDate);
                  if (context.mounted) {
                    CookieService.show(
                      message: 'Subscription set to expire tomorrow!',
                      icon: Icons.check_circle_rounded,
                      iconColor: const Color(0xFF22C55E),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildDebugTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10.5,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.3),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
