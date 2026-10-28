import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/api_service.dart';
import '../../main.dart';

class OtpScreen extends StatefulWidget {
  final String email;
  final String password;

  const OtpScreen({super.key, required this.email, required this.password});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());
  bool _isLoading = false;
  int _resendSeconds = 60;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (_resendSeconds > 0) {
        setState(() => _resendSeconds--);
        return true;
      }
      return false;
    });
  }

  String get _otpCode {
    return _controllers.map((c) => c.text).join();
  }

  Future<void> _verifyOtp() async {
    final code = _otpCode;
    if (code.length != 6) {
      _showError('Please enter the complete 6-digit code');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final verifyRes = await ApiService.verifyOtp(widget.email, code);

      if (verifyRes['success'] != true) {
        _showError(verifyRes['message'] ?? 'Invalid verification code');
        return;
      }

      // Step 2: Account creation / sign in in Supabase
      try {
        final signUpRes = await Supabase.instance.client.auth.signUp(
          email: widget.email,
          password: widget.password,
        );

        if (signUpRes.user != null && mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AuthGate()),
          );
          return;
        }
      } catch (_) {
        // If already created, sign in directly with password
        await Supabase.instance.client.auth.signInWithPassword(
          email: widget.email,
          password: widget.password,
        );
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AuthGate()),
          );
          return;
        }
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AuthGate()),
        );
      }
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Verification failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    if (_resendSeconds > 0) return;

    try {
      final res = await ApiService.sendOtp(widget.email);
      if (res['success'] == true) {
        setState(() => _resendSeconds = 60);
        _startResendTimer();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verification code sent!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        _showError(res['message'] ?? 'Failed to resend code');
      }
    } catch (e) {
      _showError('Failed to resend code');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF191919),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Verification Code',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'We sent a code to your email. Enter\nit below to verify your account.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 40),
                _buildOtpFields(),
                const SizedBox(height: 40),
                _buildVerifyButton(),
                const SizedBox(height: 20),
                _buildResendButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOtpFields() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (index) {
        return Container(
          width: 50,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF514AED),
                Colors.white,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(1.5),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF191919),
                borderRadius: BorderRadius.circular(11),
              ),
              child: TextField(
                controller: _controllers[index],
                focusNode: _focusNodes[index],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (value) {
                  if (value.isNotEmpty && index < 5) {
                    _focusNodes[index + 1].requestFocus();
                  } else if (value.isEmpty && index > 0) {
                    _focusNodes[index - 1].requestFocus();
                  }

                  if (_otpCode.length == 6) {
                    _verifyOtp();
                  }
                },
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildVerifyButton() {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(27),
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
        onPressed: _isLoading ? null : _verifyOtp,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(27),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Color(0xFF0D0D0D),
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Verify OTP',
                style: TextStyle(
                  color: Color(0xFF0D0D0D),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
      ),
    );
  }

  Widget _buildResendButton() {
    return Center(
      child: GestureDetector(
        onTap: _resendSeconds > 0 ? null : _resendCode,
        child: Text(
          _resendSeconds > 0
              ? 'Resend code in ${_resendSeconds}s'
              : 'Resend code',
          style: TextStyle(
            color: _resendSeconds > 0
                ? Colors.white.withValues(alpha: 0.4)
                : const Color(0xFF514AED),
            fontSize: 14,
            fontFamily: 'Poppins',
          ),
        ),
      ),
    );
  }
}
