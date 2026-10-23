import 'package:flutter/material.dart';
import '../../services/premium_service.dart';
import 'card_payment_sheet.dart';

export 'card_payment_sheet.dart';

/// Legacy alias forwarding to the ultra-realistic CardPaymentSheet
class MockCheckoutSheet extends StatelessWidget {
  final PremiumPlanType plan;
  final VoidCallback onSuccess;

  const MockCheckoutSheet({
    super.key,
    required this.plan,
    required this.onSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    required PremiumPlanType plan,
    required VoidCallback onSuccess,
  }) {
    return CardPaymentSheet.show(context, plan: plan, onSuccess: onSuccess);
  }

  @override
  Widget build(BuildContext context) {
    return CardPaymentSheet(plan: plan, onSuccess: onSuccess);
  }
}
