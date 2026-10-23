import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/payment_service.dart';
import '../../services/premium_service.dart';
import '../../services/cookie_service.dart';
import 'card_payment_sheet.dart';

class KhqrPaymentSheet extends StatefulWidget {
  final PremiumPlanType plan;
  final VoidCallback onSuccess;

  const KhqrPaymentSheet({
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
      builder: (_) => KhqrPaymentSheet(plan: plan, onSuccess: onSuccess),
    );
  }

  @override
  State<KhqrPaymentSheet> createState() => _KhqrPaymentSheetState();
}

class _KhqrPaymentSheetState extends State<KhqrPaymentSheet>
    with WidgetsBindingObserver {
  late PremiumPlanType _currentPlan;
  KhqrPaymentData? _paymentData;
  bool _isLoading = true;
  bool _isSuccess = false;
  int _remainingSeconds = 130; // Exactly 130 seconds (2m 10s)
  int _checkCount = 0;
  static const int _maxChecks = 4; // Strict Carma cap: 20s, 45s, 80s, 130s
  DateTime? _lastCheckTime;
  Timer? _countdownTimer;
  final List<Timer> _scheduledTimers = [];

  static const MethodChannel _bankChannel =
      MethodChannel('com.example.melo/bank_launcher');

  @override
  void initState() {
    super.initState();
    _currentPlan = widget.plan;
    WidgetsBinding.instance.addObserver(this);
    _initPayment();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelAllTimers();
    super.dispose();
  }

  void _cancelAllTimers() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    for (final timer in _scheduledTimers) {
      timer.cancel();
    }
    _scheduledTimers.clear();
  }

  void _switchPlan(PremiumPlanType newPlan) {
    if (_currentPlan == newPlan || _isLoading) return;
    HapticFeedback.selectionClick();
    _cancelAllTimers();
    setState(() {
      _currentPlan = newPlan;
      _isLoading = true;
      _paymentData = null;
    });
    _initPayment();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When returning from ABA/Bakong app back to Melo, perform a check if cooldown elapsed
    if (state == AppLifecycleState.resumed &&
        _paymentData != null &&
        !_isSuccess &&
        _remainingSeconds > 0 &&
        _checkCount < _maxChecks) {
      final now = DateTime.now();
      if (_lastCheckTime == null ||
          now.difference(_lastCheckTime!).inSeconds >= 8) {
        _checkStatus(trigger: 'app_resumed');
      }
    }
  }

  Future<void> _initPayment() async {
    _cancelAllTimers();
    final user = Supabase.instance.client.auth.currentUser;
    final planStr =
        _currentPlan == PremiumPlanType.yearly ? 'yearly' : 'monthly';

    final data = await PaymentService.generateKhqr(
      planType: planStr,
      amount: _currentPlan == PremiumPlanType.yearly ? 24.99 : 2.99,
      userId: user?.id,
    );

    if (!mounted) return;

    if (data != null) {
      setState(() {
        _paymentData = data;
        _isLoading = false;
        _remainingSeconds = 130;
        _checkCount = 0;
        _lastCheckTime = null;
      });
      _startCountdown();
      _startCarmaSchedule();
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds <= 1) {
        timer.cancel();
        _cancelAllTimers();
        setState(() => _remainingSeconds = 0);
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  void _startCarmaSchedule() {
    // Cancel existing scheduled timers
    for (final timer in _scheduledTimers) {
      timer.cancel();
    }
    _scheduledTimers.clear();

    // Carma schedule: exactly 4 checkpoints at 20s, 45s, 80s, 130s
    const intervals = [20, 45, 80, 130];
    for (final sec in intervals) {
      final t = Timer(Duration(seconds: sec), () {
        if (!mounted || _isSuccess || _paymentData == null) return;
        _checkStatus(trigger: 'scheduled_${sec}s');
      });
      _scheduledTimers.add(t);
    }
  }

  Future<void> _checkStatus({String trigger = 'scheduled'}) async {
    if (_paymentData == null || _isSuccess || !mounted) return;
    if (_checkCount >= _maxChecks) {
      debugPrint('[KHQR] Max checks ($_maxChecks) reached. Skipping $trigger.');
      return;
    }

    _checkCount++;
    _lastCheckTime = DateTime.now();
    debugPrint(
        '[KHQR] Check $_checkCount/$_maxChecks ($trigger) for MD5: ${_paymentData!.md5}');

    final res = await PaymentService.checkPaymentStatus(_paymentData!.md5);
    if (!mounted) return;

    if (res['isSuccess'] == true) {
      _cancelAllTimers();
      _handlePaymentSuccess();
    } else if (_remainingSeconds <= 0 || _checkCount >= _maxChecks) {
      _countdownTimer?.cancel();
    }
  }

  Future<void> _handlePaymentSuccess() async {
    if (_isSuccess) return;
    HapticFeedback.heavyImpact();

    setState(() => _isSuccess = true);

    // Update locally & remotely in PremiumService
    await PremiumService().upgradeTo(
      _currentPlan,
      cardLast4: 'KHQR',
      cardBrand: 'Bakong',
      cardExpiry: '12/99',
      cardHolder: 'BAKONG KHQR',
    );

    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted) {
      Navigator.of(context).pop();
      widget.onSuccess();
    }
  }

  Future<void> _launchBankApp({
    required String bankName,
    required String packageName,
    List<String> packageNames = const [],
    required List<String> schemes,
  }) async {
    if (_remainingSeconds <= 0) {
      if (mounted) {
        CookieService.show(
          message: 'This KHQR has expired (130s). Tap "Generate New QR".',
          icon: Icons.timer_off_rounded,
          iconColor: Colors.amberAccent,
        );
      }
      return;
    }

    final rawQr = _paymentData?.qrString ?? '';

    // Always copy KHQR payload to clipboard first so user can paste or scan if needed
    if (rawQr.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: rawQr));
    }

    final allPackages = <String>{
      if (packageName.isNotEmpty) packageName,
      ...packageNames,
    }.toList();

    // Render high-res QR with solid white background & quiet zone (Required by ABA/bank image decoders)
    Uint8List? imageBytes;
    if (rawQr.isNotEmpty) {
      try {
        const double totalSize = 800.0;
        const double margin = 60.0; // Standard white quiet zone margin
        const double qrDrawSize = totalSize - (margin * 2);

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);

        // 1. Paint 100% opaque solid WHITE background (prevents transparent-black bug in ABA)
        final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
        canvas.drawRect(
            const Rect.fromLTWH(0, 0, totalSize, totalSize), bgPaint);

        // 2. Draw QR code centered with margin
        final painter = QrPainter(
          data: rawQr,
          version: QrVersions.auto,
          gapless: false,
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Color(0xFF000000),
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Color(0xFF000000),
          ),
        );

        canvas.save();
        canvas.translate(margin, margin);
        painter.paint(canvas, const Size(qrDrawSize, qrDrawSize));
        canvas.restore();

        final picture = recorder.endRecording();
        final image =
            await picture.toImage(totalSize.toInt(), totalSize.toInt());
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        imageBytes = byteData?.buffer.asUint8List();
      } catch (e) {
        debugPrint('Error generating QR image bytes: $e');
      }
    }

    bool launched = false;

    // 1. Try Native Android Platform Channel with Direct QR Image Intent (Solution 1)
    try {
      final result =
          await _bankChannel.invokeMethod<bool>('launchBankWithQrImage', {
        'packageName': packageName,
        'packageNames': allPackages,
        'qrData': rawQr,
        'schemes': schemes,
        'imageBytes': imageBytes,
      });
      launched = result == true;
    } catch (_) {
      launched = false;
    }

    // 2. Fallback to url_launcher if platform channel didn't succeed
    if (!launched) {
      for (final urlStr in schemes) {
        if (urlStr.isEmpty) continue;
        try {
          final uri = Uri.parse(urlStr);
          try {
            launched = await launchUrl(
              uri,
              mode: LaunchMode.externalNonBrowserApplication,
            );
          } catch (_) {
            launched = false;
          }

          if (!launched) {
            try {
              launched = await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
            } catch (_) {
              launched = false;
            }
          }

          if (launched) break;
        } catch (_) {}
      }
    }

    if (launched) {
      if (mounted) {
        CookieService.show(
          message: 'Opening $bankName...',
          icon: Icons.check_circle_outline_rounded,
          iconColor: const Color(0xFF10B981),
        );
      }
    } else {
      if (mounted && _paymentData != null) {
        CookieService.show(
          message:
              '$bankName app not detected on device. KHQR copied to clipboard!',
          icon: Icons.info_outline_rounded,
          iconColor: const Color(0xFF817BFF),
        );
      }
    }
  }

  String _formatTimer(int totalSecs) {
    final m = totalSecs ~/ 60;
    final s = totalSecs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isYearly = _currentPlan == PremiumPlanType.yearly;
    final priceStr = _paymentData != null
        ? '\$${_paymentData!.amount.toStringAsFixed(2)}'
        : (isYearly ? '\$24.99' : '\$2.99');
    final planName =
        isYearly ? 'Melo Premium (Yearly)' : 'Melo Premium (Monthly)';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131316),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top:
              BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        12,
        22,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
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

          if (_isSuccess) ...[
            const SizedBox(height: 30),
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Payment Successful!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Welcome to Melo Pro ($planName). Enjoy unlimited music!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 13.5,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 32),
          ] else if (_isLoading) ...[
            const SizedBox(height: 60),
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                color: Color(0xFFE11D48),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Generating Bakong KHQR...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 60),
          ] else if (_paymentData == null) ...[
            const SizedBox(height: 30),
            const Icon(Icons.error_outline_rounded,
                color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Unable to generate KHQR',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please check your network and try again.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() => _isLoading = true);
                _initPayment();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE11D48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(height: 20),
          ] else ...[
            // Header with Bakong / KHQR branding
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'KHQR Payment',
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
                      planName,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF221720),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFE11D48).withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _remainingSeconds > 0
                              ? const Color(0xFFE11D48)
                              : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _remainingSeconds > 0
                            ? _formatTimer(_remainingSeconds)
                            : 'Expired',
                        style: TextStyle(
                          color: _remainingSeconds > 0
                              ? const Color(0xFFFF647C)
                              : Colors.grey.shade400,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          fontFamily: 'Poppins',
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Plan Switcher (Allows seamless toggle between 1 Month & 1 Year)
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E24),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _switchPlan(PremiumPlanType.monthly),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 6.5),
                        decoration: BoxDecoration(
                          color: _currentPlan == PremiumPlanType.monthly
                              ? const Color(0xFF514AED)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: _currentPlan == PremiumPlanType.monthly
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF514AED)
                                        .withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '1 Month • \$2.99',
                          style: TextStyle(
                            color: _currentPlan == PremiumPlanType.monthly
                                ? Colors.white
                                : Colors.white60,
                            fontSize: 12,
                            fontWeight: _currentPlan == PremiumPlanType.monthly
                                ? FontWeight.bold
                                : FontWeight.w500,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _switchPlan(PremiumPlanType.yearly),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 6.5),
                        decoration: BoxDecoration(
                          color: _currentPlan == PremiumPlanType.yearly
                              ? const Color(0xFF514AED)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: _currentPlan == PremiumPlanType.yearly
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF514AED)
                                        .withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '1 Year • \$24.99',
                              style: TextStyle(
                                color: _currentPlan == PremiumPlanType.yearly
                                    ? Colors.white
                                    : Colors.white60,
                                fontSize: 12,
                                fontWeight:
                                    _currentPlan == PremiumPlanType.yearly
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                fontFamily: 'Poppins',
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Save 25%',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // High-End KHQR Merchant Stand Card
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                children: [
                  // Top KHQR Badge & Price Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE11D48),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'KHQR',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 1.2,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                      Text(
                        priceStr,
                        style: const TextStyle(
                          color: Color(0xFF111111),
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          fontFamily: 'Poppins',
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Center QR Code with subtle inner frame
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        QrImageView(
                          data: _paymentData!.qrString,
                          version: QrVersions.auto,
                          size: 195.0,
                          backgroundColor: Colors.white,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                        ),
                        if (_remainingSeconds == 0)
                          Container(
                            width: 195.0,
                            height: 195.0,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.86),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.timer_off_rounded,
                                  color: Color(0xFFFF647C),
                                  size: 34,
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'QR Expired',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    fontFamily: 'Poppins',
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Expired after 130s',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontSize: 11,
                                    fontFamily: 'Poppins',
                                  ),
                                ),
                                const SizedBox(height: 10),
                                GestureDetector(
                                  onTap: () {
                                    setState(() => _isLoading = true);
                                    _initPayment();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE11D48),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Text(
                                      'Generate New QR',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'Poppins',
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

                  // Subtle Divider
                  Divider(
                      color: Colors.black.withValues(alpha: 0.08), height: 1),
                  const SizedBox(height: 8),

                  // Merchant & Bill Details
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _paymentData!.merchantName,
                        style: const TextStyle(
                          color: Color(0xFF222222),
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      Text(
                        'Bill: ${_paymentData!.billNumber}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 1-Tap ABA Mobile App Launch Section Header
            Row(
              children: [
                Icon(
                  Icons.phone_android_rounded,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 6),
                Text(
                  'Tap to pay directly with mobile app:',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ABA Mobile Button Only
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  final rawQr = _paymentData!.qrString;
                  final encQr = Uri.encodeComponent(rawQr);
                  _launchBankApp(
                    bankName: 'ABA Mobile',
                    packageName: 'com.paygo24.ibank',
                    packageNames: const [
                      'com.paygo24.ibank',
                      'com.ababank.payway',
                      'com.openbank.aba',
                    ],
                    schemes: [
                      'abamobilebank://ababank.com?type=payway&qrcode=$encQr',
                      'abamobilebank://ababank.com?type=khqr&qrcode=$encQr',
                      'abamobilebank://ababank.com?data=$encQr',
                      'abamobilebank://ababank.com',
                      if (_paymentData!.abaDeepLink.isNotEmpty)
                        _paymentData!.abaDeepLink,
                      'aba://qr?data=$encQr',
                      'abamobilebank://qr?data=$encQr',
                      'abamobile://qr?data=$encQr',
                      'aba://pay?data=$encQr',
                      'abamobilebank://pay?data=$encQr',
                      'aba://qr?data=$rawQr',
                      'abamobilebank://qr?data=$rawQr',
                      'aba://scan',
                      'abamobilebank://scan',
                      'aba://open',
                      'abamobilebank://open',
                      'abamobilebank://',
                      'abamobile://',
                      'aba://',
                    ],
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1E2E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF0077B6).withValues(alpha: 0.55),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0077B6).withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF0077B6).withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.account_balance_rounded,
                            color: Color(0xFF00B4D8),
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pay with ABA Mobile',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Poppins',
                            ),
                          ),
                          Text(
                            'Tap to launch ABA and approve payment',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 13,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Copy QR Code Payload pill
            GestureDetector(
              onTap: () async {
                await Clipboard.setData(
                    ClipboardData(text: _paymentData!.qrString));
                if (context.mounted) {
                  CookieService.show(
                    message: 'KHQR string copied to clipboard!',
                    icon: Icons.copy_rounded,
                    iconColor: const Color(0xFF817BFF),
                  );
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.copy_rounded,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 13,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Copy QR Payload',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  _cancelAllTimers();
                  Navigator.of(context).pop();
                  CardPaymentSheet.show(
                    context,
                    plan: _currentPlan,
                    onSuccess: widget.onSuccess,
                  );
                },
                icon: const Icon(
                  Icons.credit_card_rounded,
                  color: Color(0xFF817BFF),
                  size: 17,
                ),
                label: Text(
                  'Prefer card? Pay with Credit / Debit Card instead',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
