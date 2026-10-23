import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AutocompleteService {
  static final Map<String, List<String>> _cache = {};

  /// Fetches fast autocomplete query suggestions using YouTube/Google Suggest.
  /// Sub-50ms latency, zero authentication required.
  static Future<List<String>> getSuggestions(String query) async {
    final clean = query.trim();
    if (clean.length < 2) return [];

    final cacheKey = clean.toLowerCase();
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    try {
      final uri = Uri.parse(
        'http://suggestqueries.google.com/complete/search?client=firefox&ds=yt&q=${Uri.encodeComponent(clean)}',
      );
      final response = await http.get(uri, headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      }).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List && decoded.length > 1 && decoded[1] is List) {
          final rawList = decoded[1] as List;
          final suggestions = rawList
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .take(6)
              .toList();

          _cache[cacheKey] = suggestions;
          if (_cache.length > 200) {
            _cache.remove(_cache.keys.first);
          }
          return suggestions;
        }
      }
    } catch (e) {
      debugPrint('[AutocompleteService] Error fetching suggestions: $e');
    }

    return [];
  }
}
