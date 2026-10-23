import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/premium_service.dart';
import 'card_payment_sheet.dart';
import 'khqr_payment_sheet.dart';

class PaymentMethodPickerSheet extends StatelessWidget {
  final PremiumPlanType plan;
  final VoidCallback onSuccess;

  const PaymentMethodPickerSheet({
    super.key,
    required this.plan,
    required this.onSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    required PremiumPlanType plan,
    required VoidCallback onSuccess,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          PaymentMethodPickerSheet(plan: plan, onSuccess: onSuccess),
    );
  }

  String get _planTitle =>
      plan == PremiumPlanType.yearly ? '1 Year Pro Pass' : '1 Month Pro Pass';

  String get _planPrice =>
      plan == PremiumPlanType.yearly ? '\$24.99' : '\$2.99';

  String get _planDuration =>
      plan == PremiumPlanType.yearly ? '365 Days' : '30 Days';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF151517),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Center Drag Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Payment Method',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white54,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Plan Summary Card - Clean, no icon, no gradient background
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E22),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _planTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _planDuration,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _planPrice,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Option 1: Credit / Debit Card
            _buildOptionTile(
              context: context,
              icon: Icons.credit_card_rounded,
              title: 'Credit / Debit Card',
              subtitle: 'Visa, Mastercard',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMiniBrandBadge('VISA'),
                  const SizedBox(width: 5),
                  _buildMastercardCircles(),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withValues(alpha: 0.3),
                    size: 13,
                  ),
                ],
              ),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop();
                CardPaymentSheet.show(
                  context,
                  plan: plan,
                  onSuccess: onSuccess,
                );
              },
            ),
            const SizedBox(height: 10),

            // Option 2: ABA KHQR
            _buildOptionTile(
              context: context,
              icon: Icons.qr_code_2_rounded,
              title: 'ABA KHQR',
              subtitle: 'Pay with ABA Mobile',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE11D48).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFFE11D48).withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: const Text(
                      'KHQR',
                      style: TextStyle(
                        color: Color(0xFFFF647C),
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins',
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withValues(alpha: 0.3),
                    size: 13,
                  ),
                ],
              ),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop();
                KhqrPaymentSheet.show(
                  context,
                  plan: plan,
                  onSuccess: onSuccess,
                );
              },
            ),
            const SizedBox(height: 18),

            // Clean, short security footer
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Secured 256-bit payment',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 11,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E22),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Clean icon box without gradient
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),

              // Title & Subtitle (short and crisp)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11.5,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),

              // Trailing
              trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniBrandBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          fontFamily: 'Poppins',
        ),
      ),
    );
  }

  Widget _buildMastercardCircles() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: const BoxDecoration(
            color: Color(0xFFEB001B),
            shape: BoxShape.circle,
          ),
        ),
        Transform.translate(
          offset: const Offset(-4, 0),
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: const Color(0xFFF79E1B).withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}
