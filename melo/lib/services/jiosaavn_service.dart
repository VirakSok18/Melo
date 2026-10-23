import 'dart:convert';
import 'package:dart_des/dart_des.dart';
import 'package:http/http.dart' as http;

class JioSaavnService {
  static const String _desKey = '38586bea';
  static final Map<String, String> _cache = {};

  /// Resolves a direct CDN stream URL from JioSaavn on the client.
  /// 100% frontend with no backend and zero country/geo-restrictions.
  static Future<String?> getStreamUrl(String title, String artist) async {
    if (title.trim().isEmpty) return null;
    final cacheKey = '$title ${artist ?? ''}'.toLowerCase().trim();
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    final cleanedTitle = title
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll(RegExp(r'\[[^]]*\]'), '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final cleanedArtist = (artist ?? '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final query = (cleanedTitle.isNotEmpty && cleanedArtist.isNotEmpty)
        ? '$cleanedTitle $cleanedArtist'
        : '$title $artist'.trim();

    try {
      final encodedQuery = Uri.encodeComponent(query);
      final apiUrl =
          'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&cc=in&n=5&p=1&q=$encodedQuery';

      final resp = await http.get(Uri.parse(apiUrl), headers: {
        'Accept': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      }).timeout(const Duration(milliseconds: 1500));

      if (resp.statusCode != 200 || resp.body.isEmpty) return null;

      final data = jsonDecode(resp.body);
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return null;

      for (final item in results) {
        // 1. Direct media_preview_url (unencrypted, fast, zero geo-restrictions)
        final previewUrl = item['media_preview_url'] as String?;
        if (previewUrl != null && previewUrl.isNotEmpty) {
          final cleanUrl = previewUrl.replaceAll(r'\/', '/');
          final fullCdnUrl = cleanUrl
              .replaceAll('preview.saavncdn.com', 'aac.saavncdn.com')
              .replaceAll('_96_p.mp4', '_320.mp4')
              .replaceAll('_96_p.mp3', '_320.mp3');
          _cache[cacheKey] = fullCdnUrl;
          print('[JioSaavn] ⚡ Resolved stream for "$title": $fullCdnUrl');
          return fullCdnUrl;
        }

        // 2. Encrypted media url
        final encryptedUrl = item['encrypted_media_url'] as String?;
        if (encryptedUrl != null && encryptedUrl.isNotEmpty) {
          final decrypted = _decryptMediaUrl(encryptedUrl);
          if (decrypted != null && decrypted.isNotEmpty) {
            final highQualityUrl = decrypted
                .replaceAll('_96.mp4', '_320.mp4')
                .replaceAll('_160.mp4', '_320.mp4')
                .replaceAll('_96.mp3', '_320.mp3')
                .replaceAll('_160.mp3', '_320.mp3');
            _cache[cacheKey] = highQualityUrl;
            print('[JioSaavn] ⚡ Resolved stream for "$title": $highQualityUrl');
            return highQualityUrl;
          }
        }
      }
    } catch (e) {
      print('[JioSaavn] Search error for query "$query": $e');
    }
    return null;
  }

  static String? _decryptMediaUrl(String encryptedBase64) {
    try {
      final keyBytes = utf8.encode(_desKey);
      final encryptedBytes = base64.decode(encryptedBase64);
      final des = DES(
        key: keyBytes,
        mode: DESMode.ECB,
        paddingType: DESPaddingType.PKCS5,
      );
      final decryptedBytes = des.decrypt(encryptedBytes);
      if (decryptedBytes == null) return null;
      return utf8.decode(decryptedBytes);
    } catch (e) {
      print('[JioSaavn] Decrypt error: $e');
      return null;
    }
  }
}
