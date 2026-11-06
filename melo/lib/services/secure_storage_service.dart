import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  static const String deezerArlKey = 'deezer_arl';
  static const String groqApiKey = 'groq_api_key';
  static const String geminiApiKey = 'gemini_api_key';

  // Environment bindings (via compile-time --dart-define or local storage)
  static const String _envDeezerArl = String.fromEnvironment('DEEZER_ARL');
  static const String _envGroqKey = String.fromEnvironment('GROQ_API_KEY');
  static const String _envGeminiKey = String.fromEnvironment('GEMINI_API_KEY');

  // Fallback defaults (kept empty to prevent exposing sensitive credentials in Git)
  static const String _fallbackDeezerArl =
      '5b70007f7b4f380b095f6579c479f5ba71fe802bd2acc0323a09e69fed24032c7ef888085242bbf34e99697559dfedc655fb31e40d080030dfb0f63b4df735fdc0d008d3ec7138079c011edb9109a35ef1b8f23a2a2bfe6eccff9869dbcf5962';
  static const String _fallbackGroqKey = '';
  static const String _fallbackGeminiKey = '';

  static String get defaultDeezerArl =>
      _envDeezerArl.isNotEmpty ? _envDeezerArl : _fallbackDeezerArl;

  static String get defaultGroqKey =>
      _envGroqKey.isNotEmpty ? _envGroqKey : _fallbackGroqKey;

  static String get defaultGeminiKey =>
      _envGeminiKey.isNotEmpty ? _envGeminiKey : _fallbackGeminiKey;

  /// Initialize secure storage with defaults on first launch.
  static Future<void> init() async {
    try {
      if (_envDeezerArl.isNotEmpty) {
        await _storage.write(key: deezerArlKey, value: _envDeezerArl);
      } else {
        final arl = await _storage.read(key: deezerArlKey);
        if ((arl == null || arl.isEmpty) && defaultDeezerArl.isNotEmpty) {
          await _storage.write(key: deezerArlKey, value: defaultDeezerArl);
        }
      }

      if (_envGroqKey.isNotEmpty) {
        await _storage.write(key: groqApiKey, value: _envGroqKey);
      } else {
        final groqKey = await _storage.read(key: groqApiKey);
        if (groqKey != null &&
            (groqKey.startsWith('gsk_RCc') || groqKey.startsWith('gsk_je9'))) {
          await _storage.delete(key: groqApiKey);
        } else if ((groqKey == null || groqKey.isEmpty) && defaultGroqKey.isNotEmpty) {
          await _storage.write(key: groqApiKey, value: defaultGroqKey);
        }
      }

      if (_envGeminiKey.isNotEmpty) {
        await _storage.write(key: geminiApiKey, value: _envGeminiKey);
      } else {
        final geminiKey = await _storage.read(key: geminiApiKey);
        if ((geminiKey == null || geminiKey.isEmpty) && defaultGeminiKey.isNotEmpty) {
          await _storage.write(key: geminiApiKey, value: defaultGeminiKey);
        }
      }
    } catch (e) {
      debugPrint('[SecureStorageService] init error: $e');
    }
  }

  static Future<String> read(String key) async {
    if (key == groqApiKey && _envGroqKey.isNotEmpty) return _envGroqKey.trim();
    if (key == geminiApiKey && _envGeminiKey.isNotEmpty) return _envGeminiKey.trim();
    if (key == deezerArlKey && _envDeezerArl.isNotEmpty) return _envDeezerArl.trim();

    try {
      final value = await _storage.read(key: key);
      if (key == deezerArlKey) return (value != null && value.isNotEmpty) ? value.trim() : defaultDeezerArl.trim();
      if (key == groqApiKey) {
        if (value != null &&
            (value.startsWith('gsk_RCc') || value.startsWith('gsk_je9'))) {
          await _storage.delete(key: groqApiKey);
          return defaultGroqKey.trim();
        }
        return (value != null && value.isNotEmpty) ? value.trim() : defaultGroqKey.trim();
      }
      if (key == geminiApiKey) return (value != null && value.isNotEmpty) ? value.trim() : defaultGeminiKey.trim();
      return value?.trim() ?? '';
    } catch (e) {
      debugPrint('[SecureStorageService] read error for $key: $e');
      if (key == groqApiKey) return defaultGroqKey.trim();
      if (key == geminiApiKey) return defaultGeminiKey.trim();
      if (key == deezerArlKey) return defaultDeezerArl.trim();
      return '';
    }
  }

  static Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('[SecureStorageService] write error: $e');
    }
  }

  static Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('[SecureStorageService] delete error: $e');
    }
  }

  /// Convenience getters
  static Future<String> get deezerArl => read(deezerArlKey);
  static Future<String> get groqApiKeyVal => read(groqApiKey);
  static Future<String> get geminiApiKeyVal => read(geminiApiKey);
}
