import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class ShareService {
  static const String baseUrl = String.fromEnvironment(
    'SHARE_BASE_URL',
    defaultValue: 'https://melo.app',
  );
  static const String _baseUrl = baseUrl;

  /// Shares a playlist link
  static Future<void> sharePlaylist({
    required String playlistId,
    required String title,
    String? creatorName,
  }) async {
    final url = '$_baseUrl/?playlist=$playlistId';
    final text = creatorName != null && creatorName.isNotEmpty
        ? 'Check out "$title" by $creatorName on Melo 🎵\n$url'
        : 'Check out "$title" on Melo 🎵\n$url';
    await _executeShare(text, title);
  }

  /// Shares a user profile link
  static Future<void> shareProfile({
    required String username,
    required String displayName,
  }) async {
    final cleanUsername = username.replaceAll('@', '');
    final url = '$_baseUrl/?profile=$cleanUsername';
    final text = 'Check out $displayName (@$cleanUsername) on Melo 🎵\n$url';
    await _executeShare(text, '$displayName on Melo');
  }

  /// Shares a song link
  static Future<void> shareSong({
    required String songId,
    required String title,
    required String artist,
  }) async {
    final url = '$_baseUrl/?song=$songId';
    final text = 'Listen to "$title" by $artist on Melo 🎵\n$url';
    await _executeShare(text, '$title - $artist');
  }

  /// Shares generic formatted text with fallback
  static Future<void> shareText({
    required String text,
    String subject = 'Melo',
  }) async {
    await _executeShare(text, subject);
  }

  static Future<void> _executeShare(String text, String subject) async {
    try {
      // ignore: deprecated_member_use
      await Share.share(text, subject: subject);
    } catch (_) {
      // Fallback: Copy link to clipboard if native share plugin is not compiled yet
      await Clipboard.setData(ClipboardData(text: text));
    }
  }
}
