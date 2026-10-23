import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/api_config.dart';

enum UsernameStatus {
  idle,
  checking,
  available,
  taken,
  invalidFormat,
  tooShort,
}

class UsernameStep extends StatefulWidget {
  final VoidCallback onContinue;
  final ValueChanged<String> onUsernameChanged;
  final ValueChanged<String> onDisplayNameChanged;
  final String? initialUsername;
  final String? initialDisplayName;

  const UsernameStep({
    super.key,
    required this.onContinue,
    required this.onUsernameChanged,
    required this.onDisplayNameChanged,
    this.initialUsername,
    this.initialDisplayName,
  });

  @override
  State<UsernameStep> createState() => _UsernameStepState();
}

class _UsernameStepState extends State<UsernameStep> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  bool _isContinuing = false;
  String? _usernameError;
  String? _displayNameError;

  UsernameStatus _usernameStatus = UsernameStatus.idle;
  String? _checkedUsername;
  Timer? _debounceTimer;

  static String get _baseUrl => '${ApiConfig.baseUrlSync}/api/profile';

  @override
  void initState() {
    super.initState();
    if (widget.initialUsername != null && widget.initialUsername!.isNotEmpty) {
      _usernameController.text = widget.initialUsername!;
      _usernameStatus = UsernameStatus.available;
      _checkedUsername = widget.initialUsername!;
    }
    if (widget.initialDisplayName != null &&
        widget.initialDisplayName!.isNotEmpty) {
      _displayNameController.text = widget.initialDisplayName!;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _usernameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _onUsernameInputChanged(String value) {
    _debounceTimer?.cancel();
    final username = value.trim().toLowerCase();

    if (_usernameError != null) {
      setState(() => _usernameError = null);
    }

    if (username.isEmpty) {
      setState(() {
        _usernameStatus = UsernameStatus.idle;
        _checkedUsername = null;
      });
      return;
    }

    if (username.length < 3) {
      setState(() {
        _usernameStatus = UsernameStatus.tooShort;
        _checkedUsername = null;
      });
      return;
    }

    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      setState(() {
        _usernameStatus = UsernameStatus.invalidFormat;
        _checkedUsername = null;
      });
      return;
    }

    setState(() {
      _usernameStatus = UsernameStatus.checking;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _checkUsernameAvailability(username);
    });
  }

  Future<void> _checkUsernameAvailability(String username) async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      final res = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('username', username)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));

      if (!mounted) return;
      if (_usernameController.text.trim().toLowerCase() != username) return;

      final isAvailable =
          res == null || (currentUserId != null && res['id'] == currentUserId);

      setState(() {
        _checkedUsername = username;
        _usernameStatus =
            isAvailable ? UsernameStatus.available : UsernameStatus.taken;
      });
    } catch (e) {
      // Fallback to Spring Boot endpoint
      try {
        final response = await http
            .get(
              Uri.parse('$_baseUrl/check-username?username=$username'),
            )
            .timeout(const Duration(seconds: 4));

        if (!mounted) return;
        if (_usernameController.text.trim().toLowerCase() != username) return;

        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final isAvailable = json['available'] == true;

        setState(() {
          _checkedUsername = username;
          _usernameStatus =
              isAvailable ? UsernameStatus.available : UsernameStatus.taken;
        });
      } catch (_) {
        if (mounted &&
            _usernameController.text.trim().toLowerCase() == username) {
          setState(() {
            _usernameStatus = UsernameStatus.idle;
          });
        }
      }
    }
  }

  Future<void> _validateAndContinue() async {
    final username = _usernameController.text.trim().toLowerCase();
    final displayName = _displayNameController.text.trim();

    setState(() {
      _displayNameError = null;
      _usernameError = null;
    });

    bool hasError = false;

    if (displayName.isEmpty) {
      setState(() => _displayNameError = 'Please enter your display name');
      hasError = true;
    }

    if (username.isEmpty) {
      setState(() => _usernameError = 'Please enter a username');
      hasError = true;
    } else if (username.length < 3) {
      setState(() => _usernameError = 'Username must be at least 3 characters');
      hasError = true;
    } else if (!RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      setState(() =>
          _usernameError = 'Only lowercase letters, numbers, and underscores');
      hasError = true;
    }

    if (hasError) return;

    if (_usernameStatus == UsernameStatus.taken) {
      setState(() => _usernameError = 'Username is already taken');
      return;
    }

    if (_usernameStatus == UsernameStatus.available &&
        _checkedUsername == username) {
      FocusScope.of(context).unfocus();
      if (MediaQuery.of(context).viewInsets.bottom > 0) {
        await Future.delayed(const Duration(milliseconds: 180));
      }
      if (!mounted) return;
      widget.onUsernameChanged(username);
      widget.onDisplayNameChanged(displayName);
      widget.onContinue();
      return;
    }

    setState(() => _isContinuing = true);

    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      final res = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('username', username)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));

      final isAvailable =
          res == null || (currentUserId != null && res['id'] == currentUserId);

      if (!isAvailable) {
        setState(() {
          _usernameStatus = UsernameStatus.taken;
          _usernameError = 'Username is already taken';
          _isContinuing = false;
        });
        return;
      }

      if (!mounted) return;
      FocusScope.of(context).unfocus();
      if (MediaQuery.of(context).viewInsets.bottom > 0) {
        await Future.delayed(const Duration(milliseconds: 180));
      }
      if (!mounted) return;
      widget.onUsernameChanged(username);
      widget.onDisplayNameChanged(displayName);
      widget.onContinue();
    } catch (e) {
      debugPrint('Username check error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to check username. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isContinuing = false);
    }
  }

  Widget _buildUsernameStatus() {
    if (_usernameStatus == UsernameStatus.idle) {
      if (_usernameError != null) {
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              const Icon(Icons.cancel_rounded, color: Colors.red, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _usernameError!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    }

    IconData icon;
    Color color;
    String text;

    switch (_usernameStatus) {
      case UsernameStatus.checking:
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF514AED),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Checking availability...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontFamily: 'Poppins',
                ),
              ),
            ],
          ),
        );
      case UsernameStatus.available:
        icon = Icons.check_circle_rounded;
        color = const Color(0xFF22C55E);
        text = '@$_checkedUsername is available';
        break;
      case UsernameStatus.taken:
        icon = Icons.cancel_rounded;
        color = const Color(0xFFEF4444);
        text =
            '@${_usernameController.text.trim().toLowerCase()} is already taken';
        break;
      case UsernameStatus.tooShort:
        icon = Icons.info_outline_rounded;
        color = Colors.amber;
        text = 'Username must be at least 3 characters';
        break;
      case UsernameStatus.invalidFormat:
        icon = Icons.error_outline_rounded;
        color = const Color(0xFFEF4444);
        text = 'Only lowercase letters, numbers, and underscores';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSuccessBorder = _usernameStatus == UsernameStatus.available;
    final hasErrorBorder = _usernameStatus == UsernameStatus.taken ||
        _usernameStatus == UsernameStatus.invalidFormat ||
        _usernameError != null;

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottomInset > 0;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.symmetric(
            horizontal: 24,
            vertical: isKeyboardOpen ? 12 : 0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                height: isKeyboardOpen ? 24 : 80,
              ),
              const Text(
                'Username',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Set up your display name and unique username',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                  fontFamily: 'Poppins',
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                height: isKeyboardOpen ? 18 : 36,
              ),
              Text(
                'Display Name',
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
                    color: _displayNameError != null
                        ? Colors.red.withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: _displayNameController,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontFamily: 'Poppins',
                  ),
                  onChanged: (value) {
                    if (_displayNameError != null) {
                      setState(() => _displayNameError = null);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'e.g. Sok Virak',
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
              if (_displayNameError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _displayNameError!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                height: isKeyboardOpen ? 14 : 20,
              ),
              Text(
                'Username',
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
                    color: hasSuccessBorder
                        ? const Color(0xFF22C55E).withValues(alpha: 0.6)
                        : hasErrorBorder
                            ? Colors.red.withValues(alpha: 0.6)
                            : Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _validateAndContinue(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontFamily: 'Poppins',
                  ),
                  onChanged: _onUsernameInputChanged,
                  decoration: InputDecoration(
                    hintText: 'username',
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
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 18, right: 4),
                      child: Text(
                        '@',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 15,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 0, minHeight: 0),
                    suffixIcon: _usernameStatus == UsernameStatus.checking
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF514AED),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              _buildUsernameStatus(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                height: isKeyboardOpen ? 24 : 40,
              ),
              Container(
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
                  onPressed: _isContinuing ? null : _validateAndContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(27),
                    ),
                  ),
                  child: _isContinuing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Color(0xFF0D0D0D),
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Continue',
                          style: TextStyle(
                            color: Color(0xFF0D0D0D),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                        ),
                ),
              ),
              SizedBox(height: isKeyboardOpen ? 20 : 30),
            ],
          ),
        ),
      ),
    );
  }
}
