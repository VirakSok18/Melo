import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auto_cache_service.dart';
import '../../services/cookie_service.dart';
import '../../widgets/fade_page_route.dart';
import '../onboarding_screen/data_management_screen.dart';
import '../onboarding_screen/terms_and_conditions_screen.dart';

class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  bool _appearOnline = true;
  bool _shareActivity = true;
  bool _autoPlaySimilar = true;
  int _cacheSizeBytes = 0;
  bool _isLoadingCache = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _appearOnline = prefs.getBool('pref_appear_online') ?? true;
      _shareActivity = prefs.getBool('pref_share_activity') ?? true;
      _autoPlaySimilar = prefs.getBool('pref_autoplay_similar') ?? true;
      _cacheSizeBytes = AutoCacheService.totalSize;
      _isLoadingCache = false;
    });
  }

  Future<void> _toggleAppearOnline(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_appear_online', val);
    setState(() => _appearOnline = val);
  }

  Future<void> _toggleShareActivity(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_share_activity', val);
    setState(() => _shareActivity = val);
  }

  Future<void> _toggleAutoPlaySimilar(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_autoplay_similar', val);
    setState(() => _autoPlaySimilar = val);
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _confirmClearCache() {
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
                'Clear Playback Cache',
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
                'This will remove temporarily cached songs on this device to free up storage. Your playlists and saved songs will remain intact.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  fontFamily: 'Poppins',
                  height: 1.45,
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
                          'Cancel',
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
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await AutoCacheService.clearCache();
                          setState(() {
                            _cacheSizeBytes = 0;
                          });
                          CookieService.show(
                            message: 'Playback cache cleared successfully',
                            icon: Icons.check_circle_outline_rounded,
                            iconColor: const Color(0xFF514AED),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        child: const Text(
                          'Clear',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'General Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // --- PRIVACY & SOCIAL ---
            _buildSectionHeader('Social & Privacy'),
            _buildSwitchTile(
              title: 'Appear Online',
              subtitle: 'Allow friends to see when you are active on Melo',
              value: _appearOnline,
              onChanged: _toggleAppearOnline,
              icon: Icons.circle_outlined,
            ),
            const SizedBox(height: 8),
            _buildSwitchTile(
              title: 'Share Listening Activity',
              subtitle: 'Show the track you are currently playing to friends',
              value: _shareActivity,
              onChanged: _toggleShareActivity,
              icon: Icons.headphones_outlined,
            ),
            const SizedBox(height: 24),

            // --- PLAYBACK ---
            _buildSectionHeader('Playback'),
            _buildSwitchTile(
              title: 'Auto play Similar Music',
              subtitle: 'Keep playing similar tracks when your playlist ends',
              value: _autoPlaySimilar,
              onChanged: _toggleAutoPlaySimilar,
              icon: Icons.queue_music_rounded,
            ),
            const SizedBox(height: 24),

            // --- STORAGE & DATA ---
            _buildSectionHeader('Storage & Data'),
            _buildActionTile(
              title: 'Clear Playback Cache',
              subtitle: _isLoadingCache
                  ? 'Calculating size...'
                  : 'Free up local cached music (${_formatBytes(_cacheSizeBytes)})',
              icon: Icons.cleaning_services_outlined,
              onTap: _confirmClearCache,
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatBytes(_cacheSizeBytes),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _buildActionTile(
              title: 'Data & Privacy Policy',
              subtitle: 'Read how your listening data is securely managed',
              icon: Icons.shield_outlined,
              onTap: () {
                Navigator.of(context).push(
                  FadePageRoute(page: const DataManagementScreen()),
                );
              },
              trailing: const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white38,
                size: 16,
              ),
            ),
            const SizedBox(height: 10),
            _buildActionTile(
              title: 'Terms & Conditions',
              subtitle: 'Read our full terms of service and usage policies',
              icon: Icons.gavel_rounded,
              onTap: () {
                Navigator.of(context).push(
                  FadePageRoute(page: const TermsAndConditionsScreen()),
                );
              },
              trailing: const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white38,
                size: 16,
              ),
            ),
            const SizedBox(height: 24),

            // --- ABOUT ---
            _buildSectionHeader('About'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161616),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'App Version',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  Text(
                    '1.0.2 (Release)',
                    style: TextStyle(
                      color: const Color(0xFF514AED),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          fontFamily: 'Poppins',
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF514AED), size: 22),
          const SizedBox(width: 14),
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
                    fontSize: 11,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            activeThumbColor: const Color(0xFF514AED),
            activeTrackColor: const Color(0xFF514AED).withValues(alpha: 0.3),
            inactiveThumbColor: Colors.white38,
            inactiveTrackColor: const Color(0xFF262626),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161616),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF514AED), size: 22),
            const SizedBox(width: 14),
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
                      fontSize: 11,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}
