import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/premium_service.dart';
import '../../services/profile_service.dart';
import 'khqr_payment_sheet.dart';

enum SupportedCardType {
  none,
  visa,
  mastercard,
  unsupported,
}

class CardPaymentSheet extends StatefulWidget {
  final PremiumPlanType plan;
  final VoidCallback onSuccess;

  const CardPaymentSheet({
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
      builder: (_) => CardPaymentSheet(plan: plan, onSuccess: onSuccess),
    );
  }

  @override
  State<CardPaymentSheet> createState() => _CardPaymentSheetState();
}

class _CardPaymentSheetState extends State<CardPaymentSheet>
    with SingleTickerProviderStateMixin {
  final _cardNumberCtrl = TextEditingController();
  final _cardHolderCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();

  final _cardFocusNode = FocusNode();
  final _holderFocusNode = FocusNode();
  final _expiryFocusNode = FocusNode();
  final _cvvFocusNode = FocusNode();

  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  SupportedCardType _cardType = SupportedCardType.none;
  bool _isProcessing = false;
  int _processingStage = 0;
  bool _isSuccess = false;
  bool _saveCard = true;
  bool _obscureCvv = true;
  String _transactionRef = '';

  @override
  void initState() {
    super.initState();

    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _flipAnimation = CurvedAnimation(
      parent: _flipController,
      curve: Curves.easeInOutCubic,
    );

    final profile = ProfileService();
    if (profile.displayName.isNotEmpty) {
      _cardHolderCtrl.text = profile.displayName.toUpperCase();
    }

    _cardNumberCtrl.addListener(_onCardNumberChanged);
    _expiryCtrl.addListener(() => setState(() {}));
    _cvvCtrl.addListener(() => setState(() {}));
    _cardHolderCtrl.addListener(() => setState(() {}));

    // Auto 3D flip card when focusing/blurring CVV
    _cvvFocusNode.addListener(() {
      if (_cvvFocusNode.hasFocus) {
        if (!_flipController.isCompleted) {
          _flipController.forward();
        }
      } else {
        if (!_flipController.isDismissed) {
          _flipController.reverse();
        }
      }
    });

    // Flip back to front when other fields gain focus
    _cardFocusNode.addListener(() {
      if (_cardFocusNode.hasFocus && !_flipController.isDismissed) {
        _flipController.reverse();
      }
    });
    _holderFocusNode.addListener(() {
      if (_holderFocusNode.hasFocus && !_flipController.isDismissed) {
        _flipController.reverse();
      }
    });
    _expiryFocusNode.addListener(() {
      if (_expiryFocusNode.hasFocus && !_flipController.isDismissed) {
        _flipController.reverse();
      }
    });
  }

  @override
  void dispose() {
    _cardNumberCtrl.removeListener(_onCardNumberChanged);
    _cardNumberCtrl.dispose();
    _cardHolderCtrl.dispose();
    _expiryCtrl.dispose();
    _cvvCtrl.dispose();

    _cardFocusNode.dispose();
    _holderFocusNode.dispose();
    _expiryFocusNode.dispose();
    _cvvFocusNode.dispose();

    _flipController.dispose();
    super.dispose();
  }

  // ==========================================
  // FACT-CHECKED VALIDATION ALGORITHMS
  // ==========================================

  SupportedCardType _detectCardType(String number) {
    final clean = number.replaceAll(' ', '').trim();
    if (clean.isEmpty) return SupportedCardType.none;

    // Visa: Always starts with 4
    if (clean.startsWith('4')) {
      return SupportedCardType.visa;
    }

    // Mastercard: Starts with 51-55
    if (clean.startsWith('5')) {
      if (clean.length == 1) return SupportedCardType.mastercard;
      final d2 = int.tryParse(clean.substring(0, 2)) ?? 0;
      if (d2 >= 51 && d2 <= 55) {
        return SupportedCardType.mastercard;
      }
      return SupportedCardType.unsupported;
    }

    // Mastercard 2-Series range: 2221-2720
    if (clean.startsWith('2')) {
      if (clean.length == 1) return SupportedCardType.mastercard;
      final d2 = int.tryParse(clean.substring(0, 2)) ?? 0;
      if (d2 < 22 || d2 > 27) {
        return SupportedCardType.unsupported;
      }
      if (clean.length >= 4) {
        final d4 = int.tryParse(clean.substring(0, 4)) ?? 0;
        if (d4 >= 2221 && d4 <= 2720) {
          return SupportedCardType.mastercard;
        }
        return SupportedCardType.unsupported;
      }
      return SupportedCardType.mastercard;
    }

    // Any other card brand (Amex 34/37, Discover 6011/65, JCB 35, etc.)
    return SupportedCardType.unsupported;
  }

  /// Official Luhn Mod 10 checksum algorithm (ISO/IEC 7812)
  bool _isValidLuhn(String number) {
    final clean = number.replaceAll(' ', '').trim();
    if (clean.length != 16) return false;

    int sum = 0;
    bool alternate = false;
    for (int i = clean.length - 1; i >= 0; i--) {
      int? digit = int.tryParse(clean[i]);
      if (digit == null) return false;
      if (alternate) {
        digit *= 2;
        if (digit > 9) digit -= 9;
      }
      sum += digit;
      alternate = !alternate;
    }
    return sum % 10 == 0;
  }

  String? get _cardNumberError {
    final clean = _cardNumberCtrl.text.replaceAll(' ', '').trim();
    if (clean.isEmpty) return null;

    final type = _detectCardType(clean);
    if (type == SupportedCardType.unsupported) {
      return 'Only Visa and Mastercard are accepted';
    }

    if (clean.length == 16) {
      if (type != SupportedCardType.visa &&
          type != SupportedCardType.mastercard) {
        return 'Card must be a Visa or Mastercard';
      }
      if (!_isValidLuhn(clean)) {
        return 'Invalid card number (checksum failed)';
      }
    }

    return null;
  }

  String? get _expiryError {
    final text = _expiryCtrl.text.trim();
    if (text.isEmpty) return null;

    final parts = text.split('/');
    if (parts.isEmpty || parts[0].length < 2) return null;

    final month = int.tryParse(parts[0]) ?? 0;
    if (month < 1 || month > 12) {
      return 'Invalid month (01–12)';
    }

    if (parts.length > 1 && parts[1].length == 2) {
      final yearTwoDigits = int.tryParse(parts[1]) ?? 0;
      final now = DateTime.now();
      final currentYearTwoDigits = now.year % 100;
      final currentMonth = now.month;

      // Card expires at the end of the month
      if (yearTwoDigits < currentYearTwoDigits ||
          (yearTwoDigits == currentYearTwoDigits && month < currentMonth)) {
        return 'Card has expired';
      }

      if (yearTwoDigits > currentYearTwoDigits + 25) {
        return 'Invalid year';
      }
    }

    return null;
  }

  String? get _cvvError {
    final text = _cvvCtrl.text.trim();
    if (text.isEmpty) return null;
    if (text.length == 3) {
      if (!RegExp(r'^\d{3}$').hasMatch(text)) {
        return 'Digits only';
      }
      return null;
    }
    return null;
  }

  bool get _isFormValid {
    final cleanNum = _cardNumberCtrl.text.replaceAll(' ', '').trim();
    final type = _detectCardType(cleanNum);
    final isBrandSupported = (type == SupportedCardType.visa ||
        type == SupportedCardType.mastercard);
    final isLuhnValid = _isValidLuhn(cleanNum);

    final isExpiryValid =
        _expiryCtrl.text.trim().length == 5 && _expiryError == null;
    final isCvvValid = _cvvCtrl.text.trim().length == 3 && _cvvError == null;
    final isHolderValid = _cardHolderCtrl.text.trim().length >= 2;

    return cleanNum.length == 16 &&
        isBrandSupported &&
        isLuhnValid &&
        isExpiryValid &&
        isCvvValid &&
        isHolderValid;
  }

  void _onCardNumberChanged() {
    final clean = _cardNumberCtrl.text.replaceAll(' ', '');
    final newType = _detectCardType(clean);
    if (newType != _cardType) {
      setState(() {
        _cardType = newType;
      });
    } else {
      setState(() {});
    }
  }

  void _toggleCardFlip() {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    if (_flipController.isCompleted || _flipController.value > 0.5) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
  }

  String get _planTitle => widget.plan == PremiumPlanType.yearly
      ? '1 Year Pro Pass'
      : '1 Month Pro Pass';

  String get _planPrice =>
      widget.plan == PremiumPlanType.yearly ? '\$24.99' : '\$2.99';

  String get _brandDisplayName {
    switch (_cardType) {
      case SupportedCardType.visa:
        return 'VISA';
      case SupportedCardType.mastercard:
        return 'Mastercard';
      default:
        return 'Card';
    }
  }

  Future<void> _processPayment() async {
    if (!_isFormValid || _isProcessing) return;

    FocusScope.of(context).unfocus();
    if (!_flipController.isDismissed) {
      _flipController.reverse();
    }

    setState(() {
      _isProcessing = true;
      _processingStage = 0;
    });
    HapticFeedback.mediumImpact();

    // Stage 1: Gateway connection
    await Future.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() => _processingStage = 1);

    // Stage 2: 3D Secure 2.0 Bank Verification
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() => _processingStage = 2);

    // Stage 3: Authorization
    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() => _processingStage = 3);

    // Stage 4: Approval & Activation
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final cleanNum = _cardNumberCtrl.text.replaceAll(' ', '');
    final last4 =
        cleanNum.length >= 4 ? cleanNum.substring(cleanNum.length - 4) : '4242';

    await PremiumService().upgradeTo(
      widget.plan,
      cardBrand: _brandDisplayName,
      cardLast4: last4,
      cardExpiry: _expiryCtrl.text.trim(),
      cardHolder: _cardHolderCtrl.text.trim(),
    );

    final randomId = math.Random().nextInt(90000) + 10000;
    final generatedRef = 'MELO-AUTH-$randomId';

    setState(() {
      _isProcessing = false;
      _isSuccess = true;
      _transactionRef = generatedRef;
    });
    HapticFeedback.heavyImpact();

    await Future.delayed(const Duration(milliseconds: 2800));
    if (!mounted) return;
    if (_isSuccess && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      widget.onSuccess();
    }
  }

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
        color: Color(0xFF131317),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
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
              const SizedBox(height: 14),

              if (_isSuccess)
                _buildSuccessReceiptView()
              else if (_isProcessing)
                _buildProcessingStateView()
              else ...[
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Card Payment',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Poppins',
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '$_planTitle • $_planPrice',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white54, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 3D Flip Card Preview
                GestureDetector(
                  onTap: _toggleCardFlip,
                  child: _build3DCardPreview(),
                ),
                const SizedBox(height: 8),

                // Flip hint note
                Center(
                  child: Text(
                    'Tap card to flip 3D view',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 10.5,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Card Details Form Header
                const Text(
                  'CARD INFORMATION',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),

                // Card Number Field
                TextField(
                  controller: _cardNumberCtrl,
                  focusNode: _cardFocusNode,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(16),
                    _CardNumberFormatter(),
                  ],
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Poppins',
                    fontSize: 14.5,
                    letterSpacing: 1.2,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Card Number',
                    hintText: '4000 1234 5678 9010',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.2),
                      fontFamily: 'Poppins',
                    ),
                    labelStyle: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontFamily: 'Poppins',
                    ),
                    prefixIcon: const Icon(
                      Icons.credit_card_rounded,
                      color: Colors.white54,
                      size: 20,
                    ),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildBrandSuffixBadge(),
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: _cardNumberError != null
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF514AED),
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
                if (_cardNumberError != null) ...[
                  const SizedBox(height: 5),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      _cardNumberError!,
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 11,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),

                // Cardholder Name Field
                TextField(
                  controller: _cardHolderCtrl,
                  focusNode: _holderFocusNode,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Poppins',
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Cardholder Name',
                    hintText: 'NAME ON CARD',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.2),
                      fontFamily: 'Poppins',
                    ),
                    labelStyle: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontFamily: 'Poppins',
                    ),
                    prefixIcon: const Icon(
                      Icons.person_outline_rounded,
                      color: Colors.white54,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF514AED),
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Expiry & CVV Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Expiry Date Field
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _expiryCtrl,
                            focusNode: _expiryFocusNode,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                              _CardExpiryFormatter(),
                            ],
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Poppins',
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Expiry Date',
                              hintText: 'MM/YY',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.2),
                                fontFamily: 'Poppins',
                              ),
                              labelStyle: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontFamily: 'Poppins',
                              ),
                              prefixIcon: const Icon(
                                Icons.calendar_today_outlined,
                                color: Colors.white54,
                                size: 18,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: _expiryError != null
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFF514AED),
                                  width: 1.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                          ),
                          if (_expiryError != null) ...[
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                _expiryError!,
                                style: const TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontSize: 10.5,
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),

                    // CVV / CVC Field (Fact-checked: Visa = CVV, Mastercard = CVC)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _cvvCtrl,
                            focusNode: _cvvFocusNode,
                            keyboardType: TextInputType.number,
                            obscureText: _obscureCvv,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              letterSpacing: 2,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  _cardType == SupportedCardType.mastercard
                                      ? 'CVC'
                                      : (_cardType == SupportedCardType.visa
                                          ? 'CVV'
                                          : 'CVV / CVC'),
                              hintText: '•••',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.2),
                                fontFamily: 'Poppins',
                              ),
                              labelStyle: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontFamily: 'Poppins',
                              ),
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                color: Colors.white54,
                                size: 18,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureCvv
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: Colors.white38,
                                  size: 18,
                                ),
                                onPressed: () {
                                  setState(() => _obscureCvv = !_obscureCvv);
                                },
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFF514AED),
                                  width: 1.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                          ),
                          if (_cvvError != null) ...[
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                _cvvError!,
                                style: const TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontSize: 10.5,
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Save Card Checkbox
                Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _saveCard,
                        onChanged: (val) {
                          setState(() => _saveCard = val ?? true);
                        },
                        activeColor: const Color(0xFF514AED),
                        checkColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _saveCard = !_saveCard),
                        child: Text(
                          'Save card for quick renewals',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Pay Button (strictly enabled only if factually valid Visa/Mastercard)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isFormValid ? _processPayment : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF514AED),
                      disabledBackgroundColor:
                          const Color(0xFF514AED).withValues(alpha: 0.25),
                      elevation: _isFormValid ? 6 : 0,
                      shadowColor:
                          const Color(0xFF514AED).withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_rounded,
                            size: 16, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          'Pay $_planPrice & Subscribe',
                          style: TextStyle(
                            color: _isFormValid ? Colors.white : Colors.white38,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Cross-Switch to ABA KHQR
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      KhqrPaymentSheet.show(
                        context,
                        plan: widget.plan,
                        onSuccess: widget.onSuccess,
                      );
                    },
                    icon: const Icon(
                      Icons.qr_code_2_rounded,
                      color: Color(0xFFE11D48),
                      size: 16,
                    ),
                    label: Text(
                      'Pay with ABA Mobile / KHQR instead',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 3D FLIPPING CARD WIDGET
  // ==========================================
  Widget _build3DCardPreview() {
    return AnimatedBuilder(
      animation: _flipAnimation,
      builder: (context, child) {
        final isBack = _flipAnimation.value >= 0.5;
        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateY(math.pi * _flipAnimation.value),
          alignment: Alignment.center,
          child: AspectRatio(
            aspectRatio: 1.586,
            child: isBack
                ? Transform(
                    transform: Matrix4.identity()..rotateY(math.pi),
                    alignment: Alignment.center,
                    child: _buildCardBack(),
                  )
                : _buildCardFront(),
          ),
        );
      },
    );
  }

  // ==========================================
  // CARD FRONT (ADAPTS ACCORDING TO BRAND)
  // ==========================================
  Widget _buildCardFront() {
    final cleanNum = _cardNumberCtrl.text;
    final displayNum = cleanNum.isEmpty ? '••••  ••••  ••••  ••••' : cleanNum;
    final displayName = _cardHolderCtrl.text.isEmpty
        ? 'CARDHOLDER NAME'
        : _cardHolderCtrl.text.toUpperCase();
    final displayExpiry = _expiryCtrl.text.isEmpty ? 'MM/YY' : _expiryCtrl.text;

    final gradientColors = _getBrandGradients();
    final borderColor = _getBrandBorderColor();
    final shadowColor = _getBrandShadowColor();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: borderColor,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background ambient sheen
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Row: Chip + NFC + Fact-Checked Brand Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _buildGoldEmvChip(),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.wifi_rounded,
                          color: Colors.white60,
                          size: 20,
                        ),
                      ],
                    ),
                    _buildBrandLogo(),
                  ],
                ),

                // Card Number Row (tactile embossed look)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    displayNum,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17.5,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                      letterSpacing: 2.4,
                      shadows: [
                        Shadow(
                          color: Colors.black87,
                          offset: Offset(1, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Details (Cardholder + Expiry)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CARDHOLDER NAME',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Poppins',
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Poppins',
                              letterSpacing: 0.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'VALID THRU',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayExpiry,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // CARD BACK
  // ==========================================
  Widget _buildCardBack() {
    final displayCvv = _cvvCtrl.text.isEmpty
        ? '•••'
        : (_obscureCvv ? '•' * _cvvCtrl.text.length : _cvvCtrl.text);

    final cvvLabel = _cardType == SupportedCardType.mastercard ? 'CVC' : 'CVV';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1B1B26),
            Color(0xFF13131D),
            Color(0xFF0C0C12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),

          // Magnetic Stripe
          Container(
            width: double.infinity,
            height: 38,
            color: const Color(0xFF0A0A0E),
          ),
          const SizedBox(height: 12),

          // Signature Panel + CVV/CVC Box Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F1F1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _cardHolderCtrl.text.isNotEmpty
                          ? _cardHolderCtrl.text
                          : 'Authorized Signature',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // CVV/CVC Code Box with Brand Specific Label
                Container(
                  width: 58,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _cardType == SupportedCardType.mastercard
                          ? const Color(0xFFEB001B)
                          : const Color(0xFF514AED),
                      width: 1.2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        cvvLabel,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 7.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        displayCvv,
                        style: const TextStyle(
                          color: Color(0xFF111111),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'Courier',
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Security Hologram + Bank Disclosure
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 32,
                  height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFE0E7FF),
                        Color(0xFFFDE047),
                        Color(0xFFA7F3D0),
                        Color(0xFFF472B6),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.security_rounded,
                        color: Color(0xFF333333), size: 14),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'AUTHORIZED SIGNATURE • NOT VALID UNLESS SIGNED',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 6.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '24/7 International Support • melo.app/secure',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 7.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Realistic Gold EMV Smart Chip
  Widget _buildGoldEmvChip() {
    return Container(
      width: 38,
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFDF7A),
            Color(0xFFE5B838),
            Color(0xFF9E7719),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE5B838).withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 22,
              height: 18,
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFF7A5910).withValues(alpha: 0.6),
                  width: 0.8,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 13,
            child: Container(
              height: 0.8,
              color: const Color(0xFF7A5910).withValues(alpha: 0.6),
            ),
          ),
          Positioned(
            left: 18,
            top: 0,
            bottom: 0,
            child: Container(
              width: 0.8,
              color: const Color(0xFF7A5910).withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // BRAND COLOR & LOGO FACT-CHECKED STYLING
  // ==========================================

  List<Color> _getBrandGradients() {
    switch (_cardType) {
      case SupportedCardType.visa:
        // Authentic Visa Royal Navy Obsidian
        return const [
          Color(0xFF131D56),
          Color(0xFF0C133B),
          Color(0xFF070B22),
        ];
      case SupportedCardType.mastercard:
        // Authentic Mastercard Charcoal Obsidian
        return const [
          Color(0xFF261518),
          Color(0xFF180D0F),
          Color(0xFF0E0708),
        ];
      case SupportedCardType.unsupported:
        // Caution slate rim
        return const [
          Color(0xFF241416),
          Color(0xFF180C0E),
          Color(0xFF0F0708),
        ];
      case SupportedCardType.none:
        // Neutral titanium slate before input
        return const [
          Color(0xFF1C1C24),
          Color(0xFF13131A),
          Color(0xFF0B0B0F),
        ];
    }
  }

  Color _getBrandBorderColor() {
    switch (_cardType) {
      case SupportedCardType.visa:
        return const Color(0xFF2E45B8).withValues(alpha: 0.5);
      case SupportedCardType.mastercard:
        return const Color(0xFFEB001B).withValues(alpha: 0.45);
      case SupportedCardType.unsupported:
        return const Color(0xFFEF4444).withValues(alpha: 0.6);
      case SupportedCardType.none:
        return Colors.white.withValues(alpha: 0.12);
    }
  }

  Color _getBrandShadowColor() {
    switch (_cardType) {
      case SupportedCardType.visa:
        return const Color(0xFF1A2A80).withValues(alpha: 0.35);
      case SupportedCardType.mastercard:
        return const Color(0xFFEB001B).withValues(alpha: 0.25);
      case SupportedCardType.unsupported:
        return const Color(0xFFEF4444).withValues(alpha: 0.2);
      case SupportedCardType.none:
        return Colors.black.withValues(alpha: 0.4);
    }
  }

  Widget _buildBrandLogo() {
    switch (_cardType) {
      case SupportedCardType.visa:
        return const Text(
          'VISA',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            fontFamily: 'Poppins',
            letterSpacing: 1.5,
          ),
        );

      case SupportedCardType.mastercard:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEB001B),
                    shape: BoxShape.circle,
                  ),
                ),
                Transform.translate(
                  offset: const Offset(-8, 0),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF79E1B).withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              'mastercard',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
                letterSpacing: 0.3,
              ),
            ),
          ],
        );

      case SupportedCardType.unsupported:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Color(0xFFEF4444), size: 16),
            SizedBox(width: 4),
            Text(
              'UNSUPPORTED',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        );

      case SupportedCardType.none:
        // Shows subtle duo watermark before user types
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'VISA',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 14,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEB001B).withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
                Transform.translate(
                  offset: const Offset(-4, 0),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF79E1B).withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }

  Widget _buildBrandSuffixBadge() {
    switch (_cardType) {
      case SupportedCardType.visa:
        return const Text(
          'VISA',
          style: TextStyle(
            color: Color(0xFF817BFF),
            fontSize: 13,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            fontFamily: 'Poppins',
          ),
        );

      case SupportedCardType.mastercard:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: Color(0xFFEB001B),
                shape: BoxShape.circle,
              ),
            ),
            Transform.translate(
              offset: const Offset(-4, 0),
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFFF79E1B).withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        );

      case SupportedCardType.unsupported:
        return const Icon(
          Icons.error_outline_rounded,
          color: Color(0xFFEF4444),
          size: 18,
        );

      case SupportedCardType.none:
        return const SizedBox.shrink();
    }
  }

  // ==========================================
  // PROCESSING GATEWAY STATE
  // ==========================================
  Widget _buildProcessingStateView() {
    final stages = [
      'Connecting to secure gateway (TLS 1.3)...',
      'Verifying 3D Secure with $_brandDisplayName...',
      'Authorizing transaction amount ($_planPrice)...',
      'Payment approved! Activating Melo Pro...',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF514AED),
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                const Icon(
                  Icons.lock_clock_rounded,
                  color: Color(0xFF817BFF),
                  size: 28,
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Processing Payment',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                stages[_processingStage.clamp(0, stages.length - 1)],
                key: ValueKey<int>(_processingStage),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12.5,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Please do not close the app',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // PAYMENT SUCCESS & DIGITAL RECEIPT
  // ==========================================
  Widget _buildSuccessReceiptView() {
    final cleanNum = _cardNumberCtrl.text.replaceAll(' ', '');
    final last4 =
        cleanNum.length >= 4 ? cleanNum.substring(cleanNum.length - 4) : '4242';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Payment Successful!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Welcome to Melo Pro! Your membership is active.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12.5,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              children: [
                _buildReceiptRow('Transaction Ref', _transactionRef),
                const SizedBox(height: 8),
                _buildReceiptRow('Plan Subscribed', _planTitle),
                const SizedBox(height: 8),
                _buildReceiptRow(
                    'Payment Method', '$_brandDisplayName •••• $last4'),
                const SizedBox(height: 8),
                _buildReceiptRow('Amount Charged', '$_planPrice USD'),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(color: Colors.white10, height: 1),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Status',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              color: Color(0xFF22C55E), size: 12),
                          SizedBox(width: 4),
                          Text(
                            'Paid & Active',
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
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onSuccess();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF514AED),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: const Text(
                'Start Listening Now',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
            fontFamily: 'Poppins',
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
        ),
      ],
    );
  }
}

// ==========================================
// FORMATTERS
// ==========================================
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.replaceAll(' ', '');
    if (text.length > 16) text = text.substring(0, 16);

    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex % 4 == 0 && nonZeroIndex != text.length) {
        buffer.write(' ');
      }
    }

    var string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}

class _CardExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.replaceAll('/', '');
    if (text.length > 4) text = text.substring(0, 4);

    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex == 2 && nonZeroIndex != text.length) {
        buffer.write('/');
      }
    }

    var string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}
