import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GeneratedHistoryItem {
  final String id;
  final String mood;
  final String title;
  final String description;
  final List<Map<String, dynamic>> songs;
  final DateTime createdAt;
  final String sourceMode; // 'chat' or 'voice'
  final String? savedPlaylistId;

  GeneratedHistoryItem({
    required this.id,
    required this.mood,
    required this.title,
    required this.description,
    required this.songs,
    required this.createdAt,
    this.sourceMode = 'chat',
    this.savedPlaylistId,
  });

  int get daysLeft {
    final diff = 7 - DateTime.now().difference(createdAt).inDays;
    return diff > 0 ? diff : 0;
  }

  bool get isExpired => DateTime.now().difference(createdAt).inDays >= 7;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mood': mood,
      'title': title,
      'description': description,
      'songs': songs,
      'createdAt': createdAt.toIso8601String(),
      'sourceMode': sourceMode,
      'savedPlaylistId': savedPlaylistId,
    };
  }

  factory GeneratedHistoryItem.fromJson(Map<String, dynamic> json) {
    return GeneratedHistoryItem(
      id: json['id']?.toString() ?? '',
      mood: json['mood']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      songs: (json['songs'] as List<dynamic>? ?? [])
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      sourceMode: json['sourceMode']?.toString() ?? 'chat',
      savedPlaylistId: json['savedPlaylistId']?.toString(),
    );
  }
}

class ChatSession {
  final String id;
  final String title;
  final String lastMessage;
  final int messageCount;
  final List<Map<String, dynamic>> messages;
  final String accumulatedMood;
  final List<String> pendingArtistIds;
  final List<String> pendingTrackIds;
  final DateTime createdAt;

  ChatSession({
    required this.id,
    required this.title,
    required this.lastMessage,
    required this.messageCount,
    required this.messages,
    required this.accumulatedMood,
    required this.pendingArtistIds,
    required this.pendingTrackIds,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'lastMessage': lastMessage,
      'messageCount': messageCount,
      'messages': messages,
      'accumulatedMood': accumulatedMood,
      'pendingArtistIds': pendingArtistIds,
      'pendingTrackIds': pendingTrackIds,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      lastMessage: json['lastMessage']?.toString() ?? '',
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
      messages: (json['messages'] as List<dynamic>? ?? [])
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList(),
      accumulatedMood: json['accumulatedMood']?.toString() ?? '',
      pendingArtistIds: (json['pendingArtistIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      pendingTrackIds: (json['pendingTrackIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class GeneratedHistoryService {
  static List<GeneratedHistoryItem> _history = [];
  static List<ChatSession> _chatSessions = [];
  static bool _loaded = false;
  static final ValueNotifier<int> onUpdate = ValueNotifier<int>(0);

  static const String _prefPrefix = 'generated_playlist_history_';
  static const String _chatPrefPrefix = 'generator_chat_sessions_';
  static const int retentionDays = 7;

  static List<GeneratedHistoryItem> get history => List.unmodifiable(_history);
  static List<ChatSession> get chatSessions => List.unmodifiable(_chatSessions);

  static String _keyForUser() {
    final user = Supabase.instance.client.auth.currentUser;
    return '$_prefPrefix${user?.id ?? 'guest'}';
  }

  static String _chatKeyForUser() {
    final user = Supabase.instance.client.auth.currentUser;
    return '$_chatPrefPrefix${user?.id ?? 'guest'}';
  }

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load Playlists
      final raw = prefs.getString(_keyForUser());
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        final allItems = list
            .map((item) => GeneratedHistoryItem.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList();

        final now = DateTime.now();
        _history = allItems
            .where(
                (item) => now.difference(item.createdAt).inDays < retentionDays)
            .toList();

        if (_history.length != allItems.length) {
          await _saveToDisk();
        }
      } else {
        _history = [];
      }

      // Load Chat Sessions
      final chatRaw = prefs.getString(_chatKeyForUser());
      if (chatRaw != null && chatRaw.isNotEmpty) {
        final chatList = jsonDecode(chatRaw) as List<dynamic>;
        _chatSessions = chatList
            .map((item) =>
                ChatSession.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      } else {
        _chatSessions = [];
      }

      _loaded = true;
      onUpdate.value++;
    } catch (e) {
      debugPrint('[GeneratedHistoryService] Error loading history: $e');
      _history = [];
      _chatSessions = [];
    }
  }

  static Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_history.map((item) => item.toJson()).toList());
      await prefs.setString(_keyForUser(), raw);
    } catch (e) {
      debugPrint('[GeneratedHistoryService] Error saving history: $e');
    }
  }

  static Future<void> _saveChatSessionsToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          jsonEncode(_chatSessions.map((item) => item.toJson()).toList());
      await prefs.setString(_chatKeyForUser(), raw);
    } catch (e) {
      debugPrint('[GeneratedHistoryService] Error saving chat sessions: $e');
    }
  }

  static Future<String> addHistory({
    required String mood,
    required String title,
    required String description,
    required List<Map<String, dynamic>> songs,
    String sourceMode = 'chat',
  }) async {
    if (!_loaded) {
      await init();
    }
    final item = GeneratedHistoryItem(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      mood: mood,
      title: title.isNotEmpty ? title : mood,
      description: description,
      songs: List.from(songs),
      createdAt: DateTime.now(),
      sourceMode: sourceMode,
    );
    _history.insert(0, item);
    if (_history.length > 50) {
      _history = _history.sublist(0, 50);
    }
    await _saveToDisk();
    onUpdate.value++;
    return item.id;
  }

  static Future<void> markPlaylistSaved(
      String historyId, String playlistId) async {
    final index = _history.indexWhere((item) => item.id == historyId);
    if (index < 0) return;

    final item = _history[index];
    _history[index] = GeneratedHistoryItem(
      id: item.id,
      mood: item.mood,
      title: item.title,
      description: item.description,
      songs: item.songs,
      createdAt: item.createdAt,
      sourceMode: item.sourceMode,
      savedPlaylistId: playlistId,
    );
    await _saveToDisk();
    onUpdate.value++;
  }

  static Future<void> saveChatSession(ChatSession session) async {
    if (!_loaded) {
      await init();
    }
    _chatSessions.removeWhere((s) => s.id == session.id);
    _chatSessions.insert(0, session);
    if (_chatSessions.length > 40) {
      _chatSessions = _chatSessions.sublist(0, 40);
    }
    await _saveChatSessionsToDisk();
    onUpdate.value++;
  }

  static Future<void> deleteHistory(String id) async {
    _history.removeWhere((item) => item.id == id);
    await _saveToDisk();
    onUpdate.value++;
  }

  static Future<void> deleteChatSession(String id) async {
    _chatSessions.removeWhere((item) => item.id == id);
    await _saveChatSessionsToDisk();
    onUpdate.value++;
  }

  static Future<void> clearAll() async {
    _history.clear();
    await _saveToDisk();
    onUpdate.value++;
  }

  static Future<void> clearAllChatSessions() async {
    _chatSessions.clear();
    await _saveChatSessionsToDisk();
    onUpdate.value++;
  }
}
