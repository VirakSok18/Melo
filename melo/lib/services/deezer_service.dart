import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:blowfish/blowfish.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart' as hash;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

class _CdnCacheEntry {
  final String url;
  final DateTime cachedAt;
  _CdnCacheEntry(this.url, this.cachedAt);

  bool get isExpired => DateTime.now().difference(cachedAt).inMinutes >= 20;
}

class DeezerService {
  // --- Constants ---
  static String _arl = '';
  static const String _gwBase = 'https://www.deezer.com/ajax/gw-light.php';
  static const String _mediaBase = 'https://media.deezer.com/v1';
  static const String _apiBase = 'https://api.deezer.com';
  static const String _magicKey = 'g4el58wc0zvf9na1';
  static const int _blockSize = 2048;
  static final Uint8List _iv = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);
  static const _ua =
      'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  // --- Session state ---
  static String? _sessionId;
  static String? _apiToken;
  static String? _licenseToken;
  static DateTime? _sessionExpiresAt;

  // --- Caches (Memory + Disk Persistence) ---
  static final Map<String, String> _trackTokenCache = {};
  static final Map<String, _CdnCacheEntry> _cdnUrlCache = {};
  static final Map<String, String> _searchQueryCache = {};
  static final Map<String, Uint8List> _decryptedCache = {};
  static bool _diskLoaded = false;
  static const String _tokensPrefsKey = 'deezer_tokens_disk_cache';
  static const String _searchPrefsKey = 'deezer_search_disk_cache';

  /// Pre-authenticates Deezer on app launch so the very first song plays instantly
  static Future<void> warmupAuth() async {
    try {
      await _loadDiskCache();
      await _ensureAuthenticated();
    } catch (_) {}
  }

  /// Invalidate cached auth tokens so next request forces a fresh login handshake
  static void invalidateAuth() {
    _apiToken = null;
    _licenseToken = null;
    _sessionId = null;
    _sessionExpiresAt = null;
  }

  /// Load permanent track tokens and search matches from disk storage.
  /// CDN URLs are NEVER loaded from disk because edge media tokens expire quickly.
  static Future<void> _loadDiskCache() async {
    if (_diskLoaded) return;
    _diskLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();

      // Clean up legacy stale CDN disk cache from disk so expired URLs never poison playback
      await prefs.remove('deezer_cdn_disk_cache');
      await prefs.remove('deezer_cdn_disk_time');

      // 1. Load Search Matches (permanent)
      final searchJson = prefs.getString(_searchPrefsKey);
      if (searchJson != null && searchJson.isNotEmpty) {
        final decoded = jsonDecode(searchJson) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          if (v is String && v.isNotEmpty) _searchQueryCache[k] = v;
        });
      }

      // 2. Load Track Tokens (permanent - never changes for a song)
      final tokensJson = prefs.getString(_tokensPrefsKey);
      if (tokensJson != null && tokensJson.isNotEmpty) {
        final decoded = jsonDecode(tokensJson) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          if (v is String && v.isNotEmpty) _trackTokenCache[k] = v;
        });
      }
      print(
          '[Deezer] Restored ${_trackTokenCache.length} tokens & ${_searchQueryCache.length} search matches from disk cache');
    } catch (e) {
      debugPrint('[Deezer] Error loading disk cache: $e');
    }
  }

  static Future<void> _saveDiskCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokensPrefsKey, jsonEncode(_trackTokenCache));
      await prefs.setString(_searchPrefsKey, jsonEncode(_searchQueryCache));
      // CDN URLs are intentionally ephemeral in memory only
    } catch (_) {}
  }

  /// Check if a track's CDN URL is already in memory cache and not expired
  static bool isCdnCached(String trackId) {
    final entry = _cdnUrlCache[trackId];
    return entry != null && !entry.isExpired;
  }

  /// Evict a track's cached CDN URL so fresh tokens can be fetched
  static void evictCdnUrl(String trackId) {
    _cdnUrlCache.remove(trackId);
    _decryptedCache.remove(trackId);
  }

  // ===================== PUBLIC API =====================

  /// Full flow: auth → get CDN URL → download → decrypt → return audio bytes.
  /// This is the single entry point for Flutter to play a Deezer track.
  /// If [trackId] is provided, the search step is skipped entirely.
  static Future<DeezerResult?> resolveTrack({
    required String title,
    required String artist,
    String? trackId,
    int durationSeconds = 0,
  }) async {
    final effectiveId =
        (trackId != null && trackId.isNotEmpty) ? trackId : null;
    final cacheKey = (effectiveId ?? '$title $artist'.toLowerCase().trim());
    final cached = _decryptedCache[cacheKey];
    if (cached != null) {
      print(
          '[Deezer] Decrypted cache hit for "$cacheKey" (${cached.length} bytes)');
      return DeezerResult(audioBytes: cached, trackId: effectiveId ?? '');
    }

    final sw = Stopwatch()..start();

    // 1. Auth
    await _ensureAuthenticated();
    if (_apiToken == null || _licenseToken == null) {
      print('[Deezer] Auth failed');
      return null;
    }

    // 2. Resolve trackId — skip search if already known
    final resolvedId = effectiveId ?? await _searchTrack(title, artist);
    if (resolvedId == null) {
      print(
          '[Deezer] No track found for "$title" by "$artist" (${sw.elapsedMilliseconds}ms)');
      return null;
    }

    // 3. Get CDN URL
    final cdnUrl = await _getCdnUrl(resolvedId);
    if (cdnUrl == null) {
      print('[Deezer] CDN URL failed for trackId=$resolvedId');
      return null;
    }

    // 4. Download encrypted audio
    final resp = await http.get(
      Uri.parse(cdnUrl),
      headers: {'User-Agent': _ua},
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      print('[Deezer] CDN download failed: ${resp.statusCode}');
      return null;
    }

    final encrypted = resp.bodyBytes;
    print(
        '[Deezer] Downloaded ${encrypted.length} bytes (${sw.elapsedMilliseconds}ms)');

    // 5. Check if already plain MP3 (starts with FF E0/E1 sync word)
    Uint8List audioBytes;
    if (encrypted.length >= 2 &&
        encrypted[0] == 0xFF &&
        (encrypted[1] & 0xE0) == 0xE0) {
      audioBytes = encrypted;
    } else {
      // 6. Decrypt Blowfish-CBC-stripe (client-side, matches Java javax.crypto)
      audioBytes = _decryptBlowfishCbcStripe(encrypted, resolvedId);
    }

    _decryptedCache[cacheKey] = audioBytes;
    print(
        '[Deezer] Full resolve for "$cacheKey" done (${sw.elapsedMilliseconds}ms, ${audioBytes.length} bytes)');
    return DeezerResult(audioBytes: audioBytes, trackId: resolvedId);
  }

  static bool isDeezerCdnUrl(String url) => url.contains('dzcdn.net');

  /// Resolve and return just the CDN URL for a track (no download).
  /// Used by DeezerProxy for on-the-fly streaming decryption.
  static Future<String?> getCdnUrl(String trackId) async {
    await _loadDiskCache();
    final cached = _cdnUrlCache[trackId];
    if (cached != null && !cached.isExpired) return cached.url;
    _cdnUrlCache.remove(trackId);

    // Validate trackId — must be a positive integer
    if (int.tryParse(trackId) == null || int.parse(trackId) <= 0) {
      print('[Deezer] Invalid trackId for getCdnUrl: $trackId');
      return null;
    }

    await _ensureAuthenticated();
    if (_apiToken == null || _licenseToken == null) {
      print('[Deezer] Auth failed for getCdnUrl');
      return null;
    }

    final cdnUrl = await _getCdnUrl(trackId);
    if (cdnUrl != null && cdnUrl.isNotEmpty) {
      _cdnUrlCache[trackId] = _CdnCacheEntry(cdnUrl, DateTime.now());
    }
    return cdnUrl;
  }

  static Future<Uint8List?> downloadAndDecrypt({
    required String cdnUrl,
    required String trackId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(cdnUrl),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        print('[Deezer] CDN download failed: ${response.statusCode}');
        return null;
      }

      final encrypted = response.bodyBytes;
      print('[Deezer] Downloaded ${encrypted.length} bytes');

      if (encrypted.length >= 2 &&
          encrypted[0] == 0xFF &&
          (encrypted[1] & 0xE0) == 0xE0) {
        return encrypted;
      }

      return _decryptBlowfishCbcStripe(encrypted, trackId);
    } catch (e) {
      print('[Deezer] Download/decrypt error: $e');
      return null;
    }
  }

  static Future<String?> saveToTempFile(
      Uint8List audioBytes, String trackId) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/deezer_$trackId.mp3');
      await file.writeAsBytes(audioBytes);
      return file.path;
    } catch (e) {
      print('[Deezer] Failed to save temp file: $e');
      return null;
    }
  }

  // ===================== AUTH =====================

  static Future<void> _ensureAuthenticated({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _apiToken != null &&
        _licenseToken != null &&
        _sessionExpiresAt != null &&
        DateTime.now().isBefore(_sessionExpiresAt!)) {
      return;
    }

    if (forceRefresh) {
      invalidateAuth();
    }

    // Load ARL from secure storage on first auth
    if (_arl.isEmpty) {
      _arl = await SecureStorageService.deezerArl;
    }

    try {
      // Step 1: ping → session ID
      final pingResp = await http
          .post(
            Uri.parse('$_gwBase?method=deezer.ping&api_version=1.0&api_token='),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Cookie': 'arl=$_arl',
            },
            body: '',
          )
          .timeout(const Duration(seconds: 8));

      if (pingResp.statusCode != 200) {
        print('[Deezer] Ping failed: ${pingResp.statusCode}');
        return;
      }

      final pingData = jsonDecode(pingResp.body);
      _sessionId = pingData['results']?['SESSION'] as String?;
      if (_sessionId == null) {
        print('[Deezer] No SESSION in ping response');
        return;
      }

      // Step 2: getUserData → api_token + license_token
      final userResp = await http
          .post(
            Uri.parse(
                '$_gwBase?method=deezer.getUserData&input=3&api_version=1.0&api_token='),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Cookie': 'arl=$_arl; sid=$_sessionId',
            },
            body: '',
          )
          .timeout(const Duration(seconds: 8));

      if (userResp.statusCode != 200) {
        print('[Deezer] getUserData failed: ${userResp.statusCode}');
        return;
      }

      final userData = jsonDecode(userResp.body);
      final results = userData['results'];
      if (results == null) {
        print('[Deezer] No results in getUserData');
        return;
      }

      _apiToken = results['checkForm'] as String?;
      _licenseToken = results['USER']?['OPTIONS']?['license_token'] as String?;

      if (_apiToken != null && _licenseToken != null) {
        _sessionExpiresAt = DateTime.now().add(const Duration(minutes: 30));
        print('[Deezer] Auth OK (token=${_apiToken!.substring(0, 10)}...)');
      } else {
        print(
            '[Deezer] Auth incomplete: apiToken=$_apiToken, licenseToken=$_licenseToken');
      }
    } catch (e) {
      print('[Deezer] Auth error: $e');
    }
  }

  // ===================== SEARCH =====================

  /// Public wrapper — search Deezer and return the best-matching track ID.
  static Future<String?> searchTrackId(String title, String artist) =>
      _searchTrack(title, artist);

  static Future<String?> _searchTrack(String title, String artist) async {
    await _loadDiskCache();
    final searchKey = '$title|$artist'.toLowerCase().trim();
    final cachedId = _searchQueryCache[searchKey];
    if (cachedId != null && cachedId.isNotEmpty) {
      return cachedId;
    }

    try {
      final query = Uri.encodeComponent('$title $artist'.trim());
      final resp = await http.get(
        Uri.parse('$_apiBase/search?q=$query&limit=5'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      final results = data['data'] as List?;
      if (results == null || results.isEmpty) return null;

      final titleLower = title.toLowerCase().trim();
      final artistLower = artist.toLowerCase().trim();

      // Try matching title and artist
      for (final track in results) {
        final tTitle = (track['title'] ?? '').toString().toLowerCase().trim();
        final tArtist =
            (track['artist']?['name'] ?? '').toString().toLowerCase().trim();

        final titleMatch =
            tTitle.contains(titleLower) || titleLower.contains(tTitle);
        final artistMatch = artistLower.isEmpty ||
            tArtist.contains(artistLower) ||
            artistLower.contains(tArtist);

        if (titleMatch && artistMatch) {
          final id = track['id'].toString();
          print('[Deezer] Matched "$tTitle" by "$tArtist" (id=$id)');
          _searchQueryCache[searchKey] = id;
          _saveDiskCache();
          return id;
        }
      }

      print(
          '[Deezer] No verified artist match for "$title" by "$artist" on Deezer');
      return null;
    } catch (e) {
      print('[Deezer] Search failed: $e');
      return null;
    }
  }

  // ===================== CDN URL =====================

  static Future<String?> _getCdnUrl(String trackId,
      {bool isRetry = false}) async {
    final cached = _cdnUrlCache[trackId];
    if (cached != null && !cached.isExpired) return cached.url;

    try {
      final trackToken = await _getTrackToken(trackId);
      if (trackToken == null) return null;

      final body = jsonEncode({
        'license_token': _licenseToken,
        'media': [
          {
            'type': 'FULL',
            'formats': [
              {'cipher': 'BF_CBC_STRIPE', 'format': 'MP3_128'}
            ]
          }
        ],
        'track_tokens': [trackToken],
      });

      final resp = await http
          .post(
            Uri.parse('$_mediaBase/get_url'),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': _ua,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) {
        if (!isRetry && (resp.statusCode == 401 || resp.statusCode == 403)) {
          invalidateAuth();
          await _ensureAuthenticated(forceRefresh: true);
          return _getCdnUrl(trackId, isRetry: true);
        }
        return null;
      }

      final data = jsonDecode(resp.body);
      if (data['errors'] != null) {
        print('[Deezer] CDN URL API errors: ${data['errors']}');
        if (!isRetry) {
          invalidateAuth();
          await _ensureAuthenticated(forceRefresh: true);
          return _getCdnUrl(trackId, isRetry: true);
        }
        return null;
      }

      final dataList = data['data'] as List?;
      if (dataList == null || dataList.isEmpty) {
        print('[Deezer] CDN URL: empty data for trackId=$trackId');
        return null;
      }

      final sources = dataList[0]?['media']?[0]?['sources'] as List?;
      if (sources == null || sources.isEmpty) return null;

      final cdnUrl = sources[0]['url'] as String?;
      if (cdnUrl != null && cdnUrl.isNotEmpty) {
        _cdnUrlCache[trackId] = _CdnCacheEntry(cdnUrl, DateTime.now());
      }
      return cdnUrl;
    } catch (e) {
      print('[Deezer] CDN URL failed: $e');
      return null;
    }
  }

  static Future<String?> _getTrackToken(String trackId,
      {bool isRetry = false}) async {
    final cached = _trackTokenCache[trackId];
    if (cached != null) return cached;

    try {
      final resp = await http
          .post(
            Uri.parse(
                '$_gwBase?method=song.getListData&input=3&api_version=1.0&api_token=$_apiToken'),
            headers: {
              'Content-Type': 'application/json',
              'Cookie': 'arl=$_arl; sid=$_sessionId',
            },
            body: jsonEncode({
              'sng_ids': [int.parse(trackId)]
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      final error = data['error'];
      if (error != null && error is Map && error.isNotEmpty) {
        print('[Deezer] Track token API error: $error');
        invalidateAuth();
        if (!isRetry) {
          print('[Deezer] Auto-reauthenticating and retrying track token...');
          await _ensureAuthenticated(forceRefresh: true);
          if (_apiToken != null) {
            return _getTrackToken(trackId, isRetry: true);
          }
        }
        return null;
      }

      final trackDataList = data['results']?['data'] as List?;
      if (trackDataList == null || trackDataList.isEmpty) {
        print(
            '[Deezer] Track token: empty data list for trackId=$trackId, response keys: ${data.keys.toList()}');
        return null;
      }

      final trackData = trackDataList[0];
      if (trackData == null) return null;

      String? token = trackData['TRACK_TOKEN'] as String?;
      if (token == null || token.isEmpty) {
        token = trackData['FALLBACK']?['TRACK_TOKEN'] as String?;
      }

      if (token != null && token.isNotEmpty) {
        _trackTokenCache[trackId] = token;
        _saveDiskCache();
      }
      return token;
    } catch (e) {
      print('[Deezer] Track token failed: $e');
      return null;
    }
  }

  // ===================== DECRYPTION =====================

  static Uint8List _decryptBlowfishCbcStripe(
      Uint8List encrypted, String trackId) {
    final key = _calculateBfKey(trackId);
    final bf = newBlowfish(List<int>.from(key));
    final decrypted = Uint8List(encrypted.length);

    int offset = 0;
    int blockIndex = 0;

    while (offset < encrypted.length) {
      final remaining = encrypted.length - offset;
      final blockSize = remaining < _blockSize ? remaining : _blockSize;
      if (blockSize == 0) break;

      if (blockIndex % 3 == 0) {
        // Encrypted block — decrypt with Blowfish CBC, IV={0,1,2,3,4,5,6,7}
        final block =
            Uint8List.fromList(encrypted.sublist(offset, offset + blockSize));
        // CBC requires 8-byte aligned input; pad the last block if needed
        final paddedSize = ((blockSize + 7) ~/ 8) * 8;
        final padded = Uint8List(paddedSize);
        padded.setAll(0, block);
        final decryptedBlock = bf.decryptCBC(
          List<int>.from(padded),
          List<int>.from(_iv),
          applyPadding: false,
        );
        decrypted.setRange(
            offset, offset + blockSize, Uint8List.fromList(decryptedBlock));
      } else {
        // Plain block — copy as-is
        decrypted.setRange(offset, offset + blockSize,
            encrypted.sublist(offset, offset + blockSize));
      }

      offset += blockSize;
      blockIndex++;
    }

    return decrypted;
  }

  static Uint8List _calculateBfKey(String trackId) {
    final md5Digest = hash.md5.convert(utf8.encode(trackId));
    final md5Hex =
        md5Digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final key = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      final first = md5Hex.codeUnitAt(i);
      final second = md5Hex.codeUnitAt(i + 16);
      final magic = _magicKey.codeUnitAt(i);
      key[i] = (first ^ second ^ magic) & 0xFF;
    }
    return key;
  }
}

class DeezerResult {
  final Uint8List audioBytes;
  final String trackId;
  DeezerResult({required this.audioBytes, required this.trackId});
}
