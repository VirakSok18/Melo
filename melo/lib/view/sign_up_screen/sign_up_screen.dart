import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import '../sign_in_screen/sign_in_screen.dart';
import '../../main.dart';
import '../otp_screen/otp_screen.dart';
import '../../widgets/fade_page_route.dart';
import '../onboarding_screen/terms_and_conditions_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreeTerms = false;
  bool _isLoading = false;
  bool _isNavigating = false;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null && mounted && !_isNavigating) {
        _isNavigating = true;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }

    if (!AuthService.isValidEmail(email)) {
      _showError('Please enter a valid email address');
      return;
    }

    if (password != confirmPassword) {
      _showError('Passwords do not match');
      return;
    }

    if (password.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }

    if (!_agreeTerms) {
      _showError('Please agree to the terms and conditions');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await ApiService.sendOtp(email);

      if (!mounted) return;

      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Verification code sent to $email!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OtpScreen(
              email: email,
              password: password,
            ),
          ),
        );
      } else {
        _showError(res['message'] ?? 'Failed to send verification code');
      }
    } catch (e) {
      _showError('Sign up failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signUpWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await AuthService().signInWithGoogle();

      debugPrint('Google Sign up successful!');

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      }
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Google sign up failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Sign up',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Join us. Your perfect playlist is waiting.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 40),
                _buildEmailField(),
                const SizedBox(height: 20),
                _buildPasswordField(),
                const SizedBox(height: 20),
                _buildConfirmPasswordField(),
                const SizedBox(height: 16),
                _buildAgreeTermsRow(),
                const SizedBox(height: 28),
                _buildSignUpButton(),
                const SizedBox(height: 24),
                _buildOrDivider(),
                const SizedBox(height: 24),
                _buildGoogleButton(),
                const SizedBox(height: 30),
                _buildSignInRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Email',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontFamily: 'Poppins',
            ),
            decoration: InputDecoration(
              hintText: 'users@gmail.com',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 15,
                fontFamily: 'Poppins',
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Password',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontFamily: 'Poppins',
            ),
            decoration: InputDecoration(
              hintText: '••••••••',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 15,
                fontFamily: 'Poppins',
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.white.withValues(alpha: 0.4),
                  size: 22,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Confirm Password',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: TextField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontFamily: 'Poppins',
            ),
            decoration: InputDecoration(
              hintText: '••••••••',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 15,
                fontFamily: 'Poppins',
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.white.withValues(alpha: 0.4),
                  size: 22,
                ),
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAgreeTermsRow() {
    return Row(
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _agreeTerms = !_agreeTerms;
            });
          },
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _agreeTerms
                    ? const Color(0xFF514AED)
                    : Colors.white.withValues(alpha: 0.3),
                width: 1.5,
              ),
              color: _agreeTerms ? const Color(0xFF514AED) : Colors.transparent,
            ),
            child: _agreeTerms
                ? const Icon(Icons.check, size: 10, color: Colors.white)
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Agree with ',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontFamily: 'Poppins',
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    FadePageRoute(page: const TermsAndConditionsScreen()),
                  );
                },
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [
                      Color(0xFF514AED),
                      Colors.white,
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ).createShader(bounds),
                  child: const Text(
                    'Term and Condition',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Poppins',
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSignUpButton() {
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
        onPressed: _isLoading ? null : _signUp,
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
                'Sign Up',
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

  Widget _buildOrDivider() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.15),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'or',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
              fontFamily: 'Poppins',
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleButton() {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: ElevatedButton(
        onPressed: _signUpWithGoogle,
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
            SizedBox(
              width: 24,
              child: Image.asset(
                'asset/socials/google.png',
                width: 22,
                height: 22,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.g_mobiledata,
                    color: Colors.white,
                    size: 24,
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Sign in with Google',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 15,
                fontWeight: FontWeight.w500,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignInRow() {
    return GestureDetector(
      onTap: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const SignInScreen()),
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Already have an account? ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
              fontFamily: 'Poppins',
            ),
          ),
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
              'Sign In',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
