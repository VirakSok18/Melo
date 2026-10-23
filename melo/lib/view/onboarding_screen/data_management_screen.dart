import 'package:flutter/material.dart';

class DataManagementScreen extends StatelessWidget {
  const DataManagementScreen({super.key});

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
          'Data & Privacy',
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            // Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF181818),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    color: Color(0xFF514AED),
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Privacy Matters',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Learn how Melo uses your listening data to curate music for you.',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontFamily: 'Poppins',
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            _buildSection(
              icon: Icons.headphones_outlined,
              title: '1. What We Collect',
              body:
                  'We only collect information essential to tailoring your musical experience:\n'
                  '• Profile Information: Your chosen display name, username, and avatar.\n'
                  '• Listening Habits: Songs you play, finish, replay, or skip, used strictly to refine your personal recommendations and daily mixes.\n'
                  '• Music Preferences: Followed artists, liked tracks, and custom playlists.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              icon: Icons.tune_rounded,
              title: '2. How We Use Your Data',
              body: 'Your activity is processed to:\n'
                  '• Generate mood-based playlists accurately via AI parsing.\n'
                  '• Power your real time Listen Together sessions with friends.\n'
                  '• Ensure instant offline playback through on-device caching.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              icon: Icons.lock_outline_rounded,
              title: '3. Data Protection & Storage',
              body:
                  'Your data is securely stored with Supabase database encryption. Audio streams and song previews are fetched directly via authorized music provider protocols without selling your personal information to any third parties.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              icon: Icons.delete_outline_rounded,
              title: '4. Your Rights & Control',
              body: 'You retain full control of your data:\n'
                  '• You can edit or remove your profile information at any time.\n'
                  '• You can clear your playback search and generation history inside the app.\n'
                  '• You can request account deletion by contacting support.',
            ),
            const SizedBox(height: 36),

            // Footer note
            Center(
              child: Text(
                'Melo Music • Version 1.0',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 12,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF514AED), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontFamily: 'Poppins',
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
