import 'package:flutter/material.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({super.key});

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
          'Terms & Conditions',
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
                    Icons.gavel_rounded,
                    color: Color(0xFF514AED),
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Terms of Service',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Please review the terms governing your use of Melo music streaming.',
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
              icon: Icons.verified_user_outlined,
              title: '1. Acceptance of Terms',
              body:
                  'By creating an account or accessing the Melo platform, you agree to comply with and be bound by these Terms and Conditions and our Data & Privacy Policy. If you do not agree with any part of these terms, please discontinue using the service.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              icon: Icons.person_outline_rounded,
              title: '2. User Accounts & Security',
              body:
                  '• You are responsible for safeguarding your login credentials and maintaining the security of your account.\n'
                  '• You agree not to share your account, impersonate others, or conduct unauthorized automated queries against our servers.\n'
                  '• We reserve the right to suspend or terminate accounts that violate community safety guidelines.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              icon: Icons.queue_music_rounded,
              title: '3. Content & Intellectual Property',
              body:
                  '• All music tracks, album art, lyrics, and metadata streamed via Melo are the property of their respective copyright holders, artists, and licensed distributors.\n'
                  '• Audio content is provided strictly for personal, non-commercial entertainment.\n'
                  '• Unauthorized commercial broadcasting, reproduction, or redistribution of stream files outside the Melo application is prohibited.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              icon: Icons.workspace_premium_outlined,
              title: '4. Subscriptions & Billing',
              body:
                  '• Melo Premium subscriptions unlock ad-free streaming, unlimited AI vibe generations, and offline downloads.\n'
                  '• Subscription fees are billed periodically (monthly or yearly). You may manage or cancel your renewal at any time through your Account Settings.\n'
                  '• Offline downloads are encrypted and accessible exclusively within the official Melo client.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              icon: Icons.handshake_outlined,
              title: '5. Collaborative Features',
              body:
                  '• When utilizing Listen Together or Collaborative Playlists, you agree to respect other users and refrain from adding abusive or unlawful content.\n'
                  '• Hosts reserve the right to remove collaborators or end shared listening rooms at any time.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              icon: Icons.update_rounded,
              title: '6. Modifications to Service',
              body:
                  'Melo reserves the right to periodically update, modify, or enhance features to improve service reliability and user experience. We will notify users of any substantial revisions to these terms.',
            ),
            const SizedBox(height: 36),

            // Footer note
            Center(
              child: Text(
                'Melo Music • Effective September 2026',
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
