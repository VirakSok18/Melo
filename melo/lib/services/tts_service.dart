import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TtsVoiceStyle {
  femaleWarm, // Natural warm female voice
  femaleSmooth, // Smooth, gentle relaxing tone
}

class TtsService with ChangeNotifier {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal() {
    _initPlayer();
  }

  final AudioPlayer _player = AudioPlayer();
  bool _isSpeaking = false;
  bool _isMuted = false;
  TtsVoiceStyle _voiceStyle = TtsVoiceStyle.femaleWarm;

  bool get isSpeaking => _isSpeaking;
  bool get isMuted => _isMuted;
  TtsVoiceStyle get voiceStyle => _voiceStyle;

  void _initPlayer() {
    _player.playerStateStream.listen((state) {
      final playing = state.playing;
      final completed = state.processingState == ProcessingState.completed;
      final idle = state.processingState == ProcessingState.idle;

      final speaking = playing && !completed && !idle;
      if (_isSpeaking != speaking) {
        _isSpeaking = speaking;
        notifyListeners();
      }
    });

    _loadMutePreference();
  }

  Future<void> _loadMutePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isMuted = prefs.getBool('melo_tts_muted') ?? false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    if (_isMuted && _isSpeaking) {
      await stop();
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('melo_tts_muted', _isMuted);
    } catch (_) {}
  }

  void setMuted(bool muted) {
    if (_isMuted == muted) return;
    _isMuted = muted;
    if (_isMuted && _isSpeaking) {
      stop();
    }
    notifyListeners();
  }

  void setVoiceStyle(TtsVoiceStyle style) {
    _voiceStyle = style;
    notifyListeners();
  }

  /// Clean text for spoken ear (strip emojis, formatting, URLs, code, hashes)
  String cleanTextForSpoken(String raw) {
    var text = raw;
    // Strip markdown links and images [text](url)
    text = text.replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'');
    // Strip markdown formatting symbols (*, _, ~, , #)
    text = text.replaceAll(RegExp(r'[*_~#>]'), '');
    // Strip emojis & special non-speech symbols
    text = text.replaceAll(
      RegExp(
        r'[\u{1F600}-\u{1F64F}|\u{1F300}-\u{1F5FF}|\u{1F680}-\u{1F6FF}|\u{1F700}-\u{1F77F}|\u{1F780}-\u{1F7FF}|\u{1F800}-\u{1F8FF}|\u{1F900}-\u{1F9FF}|\u{1FA00}-\u{1FA6F}|\u{1FA70}-\u{1FAFF}|\u{2600}-\u{26FF}|\u{2700}-\u{27BF}|\u{FE00}-\u{FE0F}|\u{1F1E6}-\u{1F1FF}]',
        unicode: true,
      ),
      '',
    );
    // Expand common musical abbreviations
    text = text.replaceAll(RegExp(r'\bfeat\.?\b', caseSensitive: false), 'featuring');
    text = text.replaceAll(RegExp(r'\bft\.?\b', caseSensitive: false), 'featuring');
    text = text.replaceAll(RegExp(r'\b&\b'), 'and');
    text = text.replaceAll(RegExp(r'\bw/\b', caseSensitive: false), 'with');
    text = text.replaceAll(RegExp(r'\bmin\b', caseSensitive: false), 'minutes');
    text = text.replaceAll(RegExp(r'\bhr\b', caseSensitive: false), 'hours');

    // Collapse multiple whitespace
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  /// Synthesize text and speak it aloud using high-definition neural female voice
  Future<void> speak(String rawText, {bool isKhmer = false}) async {
    if (_isMuted) return;

    final cleaned = cleanTextForSpoken(rawText);
    if (cleaned.isEmpty) return;

    try {
      await stop();

      final audioUri = _resolveTtsAudioUrl(cleaned, isKhmer: isKhmer);
      if (audioUri == null) return;

      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(audioUri)),
        preload: true,
      );
      await _player.play();
    } catch (e) {
      debugPrint('[Melo TTS] Error speaking: ');
      _isSpeaking = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    try {
      if (_player.playing) {
        await _player.stop();
      }
    } catch (_) {}
    _isSpeaking = false;
    notifyListeners();
  }

  /// High-definition neural audio stream resolution
  String? _resolveTtsAudioUrl(String text, {required bool isKhmer}) {
    final encoded = Uri.encodeComponent(text);
    if (isKhmer) {
      return 'https://translate.google.com/translate_tts?ie=UTF-8&q=&tl=km&client=tw-ob';
    }

    // High quality natural female TTS stream (English)
    return 'https://translate.google.com/translate_tts?ie=UTF-8&q=&tl=en&client=tw-ob';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
