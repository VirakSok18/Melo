import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String deezerArlKey = 'deezer_arl';
  static const String groqApiKey = 'groq_api_key';
  static const String geminiApiKey = 'gemini_api_key';

  // Environment bindings (via compile-time --dart-define or local storage)
  static const String _envDeezerArl = String.fromEnvironment('DEEZER_ARL');
  static const String _envGroqKey = String.fromEnvironment('GROQ_API_KEY');
  static const String _envGeminiKey = String.fromEnvironment('GEMINI_API_KEY');

  // Fallback defaults (kept empty to prevent exposing sensitive credentials in Git)
  static const String _fallbackDeezerArl = '';
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
    final arl = await _storage.read(key: deezerArlKey);
    if ((arl == null || arl.isEmpty) && defaultDeezerArl.isNotEmpty) {
      await _storage.write(key: deezerArlKey, value: defaultDeezerArl);
    }

    final groqKey = await _storage.read(key: groqApiKey);
    if ((groqKey == null || groqKey.isEmpty) && defaultGroqKey.isNotEmpty) {
      await _storage.write(key: groqApiKey, value: defaultGroqKey);
    }

    final geminiKey = await _storage.read(key: geminiApiKey);
    if ((geminiKey == null || geminiKey.isEmpty) && defaultGeminiKey.isNotEmpty) {
      await _storage.write(key: geminiApiKey, value: defaultGeminiKey);
    }
  }

  static Future<String> read(String key) async {
    final value = await _storage.read(key: key);
    if (key == deezerArlKey) return value ?? defaultDeezerArl;
    if (key == groqApiKey) return value ?? defaultGroqKey;
    if (key == geminiApiKey) return value ?? defaultGeminiKey;
    return value ?? '';
  }

  static Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  static Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  /// Convenience getters
  static Future<String> get deezerArl => read(deezerArlKey);
  static Future<String> get groqApiKeyVal => read(groqApiKey);
  static Future<String> get geminiApiKeyVal => read(geminiApiKey);
}
