import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/search_service.dart';
import '../../services/generate_service.dart';
import '../../services/generated_history_service.dart';
import '../../services/home_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/fade_page_route.dart';
import '../../services/cookie_service.dart';
import '../../services/premium_service.dart';
import '../../services/playback_service.dart';
import '../../services/youtube_service.dart';
import '../../services/background_prefetch_service.dart';
import '../../services/voice_normalizer.dart';
import 'generated_playlist_screen.dart';
import 'generated_history_screen.dart';

enum _Phase { idle, listening, building }

enum _InputMode { voice, text }

class PromptChip {
  final String type; // 'artist' or 'song'
  final String id; // Deezer ID
  final String title; // Display name
  final String subtitle; // Artist name (for songs) or "Artist"
  final String image; // Thumbnail URL

  const PromptChip({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.image,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'image': image,
      };

  factory PromptChip.fromJson(Map<String, dynamic> json) => PromptChip(
        type: json['type']?.toString() ?? 'song',
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        subtitle: json['subtitle']?.toString() ?? '',
        image: json['image']?.toString() ?? '',
      );
}

class _ChatMessage {
  final String id;
  final bool isUser;
  final String text;
  final bool isLoading;
  final bool isConfirmation;
  final String? previewTitle;
  final String? previewDescription;
  final String? previewImage;
  final List<String> tags;
  final List<String> artistIds;
  final List<String> trackIds;
  final List<String> suggestionOptions;
  final List<PromptChip> chips;
  final DateTime timestamp;

  _ChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    this.isLoading = false,
    this.isConfirmation = false,
    this.previewTitle,
    this.previewDescription,
    this.previewImage,
    this.tags = const [],
    this.artistIds = const [],
    this.trackIds = const [],
    this.suggestionOptions = const [],
    this.chips = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'isUser': isUser,
      'text': text,
      'isLoading': isLoading,
      'isConfirmation': isConfirmation,
      'previewTitle': previewTitle,
      'previewDescription': previewDescription,
      'previewImage': previewImage,
      'tags': tags,
      'artistIds': artistIds,
      'trackIds': trackIds,
      'suggestionOptions': suggestionOptions,
      'chips': chips.map((c) => c.toJson()).toList(),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory _ChatMessage.fromJson(Map<String, dynamic> json) {
    return _ChatMessage(
      id: json['id']?.toString() ?? '',
      isUser: json['isUser'] == true,
      text: json['text']?.toString() ?? '',
      isLoading: json['isLoading'] == true,
      isConfirmation: json['isConfirmation'] == true,
      previewTitle: json['previewTitle']?.toString(),
      previewDescription: json['previewDescription']?.toString(),
      previewImage: json['previewImage']?.toString(),
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      artistIds: (json['artistIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      trackIds: (json['trackIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      suggestionOptions: (json['suggestionOptions'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      chips: (json['chips'] as List<dynamic>? ?? [])
          .map((e) => PromptChip.fromJson(e as Map<String, dynamic>))
          .toList(),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

const _accent = Color(0xFF514AED);

const _sampleSongs = [
  ['Blinding Lights', 'The Weeknd'],
  ['Billie Jean', 'Michael Jackson'],
  ['Beat It', 'Michael Jackson'],
  ['Thriller', 'Michael Jackson'],
  ['Smooth Criminal', 'Michael Jackson'],
  ['Uptown Funk', 'Mark Ronson'],
  ['Levitating', 'Dua Lipa'],
  ['Save Your Tears', 'The Weeknd'],
];

const _stageTitles = [
  'Analyzing Your Vibe',
  'Building Your Playlist',
  'Gathering Songs',
  'Finalizing Playlist',
];

const _stageSubtitles = [
  'We are understanding your mood and what you love to hear',
  'Matching the perfect songs to your vibe',
  'Finding fresh tracks that fit the moment',
  'Putting the finishing touches on your playlist',
];

class GenerateScreen extends StatefulWidget {
  final ValueChanged<bool>? onBuildingChanged;
  final ValueChanged<bool>? onIsTextModeChanged;

  const GenerateScreen({
    super.key,
    this.onBuildingChanged,
    this.onIsTextModeChanged,
  });

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen>
    with TickerProviderStateMixin {
  _Phase _phase = _Phase.idle;
  _InputMode _mode = _InputMode.voice;
  String _greeting = '';
  String _displayName = '';
  String _liveSpokenText = '';

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isChatListening = false;
  bool _useKhmer = false;

  late final AnimationController _buildAnim;
  late final AnimationController _pulse;
  late final AnimationController _dotsAnim;

  List<SearchResult> _suggestions = [];
  Timer? _debounce;
  int _searchGen = 0;
  bool _focused = false;

  final ScrollController _scrollController = ScrollController();
  final ScrollController _chatScrollController = ScrollController();

  bool _generating = false;

  final List<PromptChip> _selectedChips = [];
  final List<String> _explicitArtistIds = [];
  final List<String> _explicitTrackIds = [];

  String _accumulatedMood = '';
  List<String> _pendingArtistIds = [];
  List<String> _pendingTrackIds = [];

  String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();

  final List<_ChatMessage> _messages = [
    _ChatMessage(
      id: 'initial_ai_greeting',
      isUser: false,
      text:
          "Hey! Tell me how you're feeling, an artist you love, or what you're up to, and I'll craft the perfect playlist for you.",
    ),
  ];

  static const int _maxCharLimit = 200;
  static const int _maxChipLimit = 3;

  Future<void> _saveCurrentChatSession() async {
    final userMsgs = _messages.where((m) => m.isUser).toList();
    if (userMsgs.isEmpty) return;

    final firstPrompt = userMsgs.first.text.trim();
    final title = firstPrompt.length > 36
        ? '${firstPrompt.substring(0, 36)}...'
        : firstPrompt;
    final lastMsg = _messages
        .lastWhere((m) => !m.isLoading, orElse: () => _messages.last)
        .text
        .trim();

    final session = ChatSession(
      id: _sessionId,
      title: title.isNotEmpty ? title : 'New Chat',
      lastMessage: lastMsg,
      messageCount: _messages.length,
      messages: _messages.map((m) => m.toJson()).toList(),
      accumulatedMood: _accumulatedMood,
      pendingArtistIds: List.from(_pendingArtistIds),
      pendingTrackIds: List.from(_pendingTrackIds),
      createdAt: DateTime.now(),
    );

    await GeneratedHistoryService.saveChatSession(session);
  }

  Future<void> _startNewChat({bool saveCurrent = true}) async {
    if (saveCurrent && _messages.any((m) => m.isUser)) {
      await _saveCurrentChatSession();
    }
    if (!mounted) return;
    setState(() {
      _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      _messages.clear();
      _messages.add(
        _ChatMessage(
          id: 'initial_ai_greeting',
          isUser: false,
          text:
              "Hey! Tell me how you're feeling, an artist you love, or what you're up to, and I'll craft the perfect playlist for you.",
        ),
      );
      _selectedChips.clear();
      _explicitArtistIds.clear();
      _explicitTrackIds.clear();
      _accumulatedMood = '';
      _pendingArtistIds.clear();
      _pendingTrackIds.clear();
      _controller.clear();
    });
  }

  Future<void> _loadChatSession(ChatSession session) async {
    // If the active chat has user messages and is different from the session being loaded, save it first
    if (_sessionId != session.id && _messages.any((m) => m.isUser)) {
      await _saveCurrentChatSession();
    }
    if (!mounted) return;
    setState(() {
      _mode = _InputMode.text;
      _sessionId = session.id;
      _accumulatedMood = session.accumulatedMood;
      _pendingArtistIds = List.from(session.pendingArtistIds);
      _pendingTrackIds = List.from(session.pendingTrackIds);
      _messages.clear();
      _messages.addAll(session.messages.map((m) => _ChatMessage.fromJson(m)));
      _selectedChips.clear();
      _explicitArtistIds.clear();
      _explicitTrackIds.clear();
      _controller.clear();
    });
    widget.onIsTextModeChanged?.call(true);
    _scrollToBottom();
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF191919),
      statusBarIconBrightness: Brightness.light,
    ));
    _buildAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    );
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();
    _dotsAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    ProfileService().addListener(_onProfileChanged);
    _loadProfile();

    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  void _onProfileChanged() {
    if (!mounted) return;
    final name = ProfileService().displayName;
    if (name.isNotEmpty && name != _displayName) {
      setState(() => _displayName = name);
    }
  }

  @override
  void dispose() {
    ProfileService().removeListener(_onProfileChanged);
    _debounce?.cancel();
    _scrollController.dispose();
    _chatScrollController.dispose();
    _buildAnim.dispose();
    _pulse.dispose();
    _dotsAnim.dispose();
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    _speech.stop();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    if (hour >= 17 && hour < 21) return 'Good evening';
    return 'Good night';
  }

  List<SearchResult> _defaultSuggestions = [];

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final p = ProfileService();
    var name = p.displayName;
    if (name.isEmpty) {
      name = prefs.getString('profile_display_name') ??
          prefs.getString('melo_profile_display_name') ??
          '';
    }
    if (name.isEmpty) {
      final user = Supabase.instance.client.auth.currentUser;
      name = (user?.userMetadata?['display_name'] ??
              user?.userMetadata?['full_name'] ??
              user?.userMetadata?['name'] ??
              '')
          .toString();
    }
    if (mounted) {
      setState(() {
        _greeting = _getGreeting();
        _displayName = name;
      });
    }
    _loadDefaultSuggestions();

    // Refresh profile in background from Supabase
    ProfileService().load(forceRefresh: true).then((_) {
      if (mounted) {
        final updatedName = ProfileService().displayName;
        if (updatedName.isNotEmpty && updatedName != _displayName) {
          setState(() => _displayName = updatedName);
        }
      }
    });
  }

  Future<void> _loadDefaultSuggestions() async {
    try {
      final homeData = await HomeService.fetchHomeData();
      final trending = homeData?['trendingNow'] as List<dynamic>? ?? [];
      final List<SearchResult> list = [];
      for (final t in trending.take(8)) {
        if (t is Map<String, dynamic>) {
          list.add(SearchResult(
            type: 'song',
            id: t['id']?.toString() ?? t['trackId']?.toString() ?? '',
            title: t['title'] as String? ?? '',
            artist: t['artist'] as String? ?? '',
            artistId: t['artistId'] as String? ?? '',
            artistImage: t['artistImage'] as String? ?? '',
            image: t['image'] as String? ?? '',
            duration: t['duration'] as String? ?? '',
            nbFan: 0,
            previewUrl: t['preview'] as String? ?? '',
          ));
        }
      }
      if (list.isEmpty) {
        final fallback = await SearchService.search('Trending');
        if (mounted && fallback.isNotEmpty) {
          setState(() => _defaultSuggestions = fallback.take(8).toList());
          return;
        }
      }
      if (mounted && list.isNotEmpty) {
        setState(() => _defaultSuggestions = list);
      }
    } catch (_) {}
  }

  // ---- text input + suggestions ----

  void _onFocusChanged() {
    final focused = _focusNode.hasFocus;
    if (focused != _focused) {
      setState(() => _focused = focused);
      if (focused) {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted && _scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
            );
          }
        });
      }
    }
  }

  String _extractSearchQuery(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';

    // If multi-line, focus on the last active line being typed
    final lines = text.split('\n');
    var activeLine = lines.isNotEmpty ? lines.last.trim() : text;
    if (activeLine.isEmpty && lines.length > 1) {
      activeLine = lines[lines.length - 2].trim();
    }

    var q = activeLine;

    // Check if any already-selected chips are present in the query string and search the remainder
    for (final chip in _selectedChips) {
      if (q.toLowerCase().contains(chip.title.toLowerCase())) {
        final idx = q.toLowerCase().lastIndexOf(chip.title.toLowerCase());
        final endIdx = idx + chip.title.length;
        if (endIdx < q.length) {
          final remainder = q.substring(endIdx).trim();
          if (remainder.isNotEmpty) {
            q = remainder;
          }
        }
      }
    }

    // Split on conjunctions and commas to find the active clause being typed
    // Handles both inline delimiters ("artist A and artist B") and comma/plus
    final inlineConjunctions = RegExp(
      r'(?:\s+(?:and|&|\+|with|also|including|plus|featuring|feat|ft|then|or|ឬ|និង|ជាមួយ)\s+|,|\+)',
      caseSensitive: false,
    );
    if (q.contains(inlineConjunctions)) {
      final parts = q.split(inlineConjunctions);
      final lastPart = parts.last.trim();
      if (lastPart.length >= 2) {
        q = lastPart;
      }
    }

    // Comprehensive prefix patterns for music, mood, vibe, similarity, and inclusion requests
    final prefixPatterns = [
      // Leading inclusion or addition markers (e.g., "including michael jackson", "include wave to earth", "with taylor swift", "and the weeknd")
      RegExp(
          r'^(?:including|includes?|with|and|also|plus|feature|featuring|feat|ft\.?)\s+',
          caseSensitive: false),
      RegExp(
          r'^(?:can\s*you\s*)?(?:please\s*)?(?:make|give|create|build|find|play|put|search|include|add|have|put\s*in|throw\s*in|mix\s*in|feature)\s*(?:me\s*)?(?:a\s*playlist\s*(?:of|with|for)?|a|an|some|the)?\s*',
          caseSensitive: false),
      RegExp(
          r'^(?:add|put|include|throw\s*in|mix\s*in)?\s*(?:more|extra|some|another|other)?\s*(?:artists?|singers?|bands?|songs?\s*by|tracks?\s*by|music\s*by|songs?\s*from|tracks?\s*from|from|by)\s+',
          caseSensitive: false),
      RegExp(
          r'^(?:how\s*about|what\s*about|can\s*we\s*get|can\s*you\s*add|can\s*u\s*add)\s+',
          caseSensitive: false),
      RegExp(
          r'^(?:more|extra|some)\s+(?:songs?|tracks?|music)?\s*(?:by|from|of)?\s*',
          caseSensitive: false),
      RegExp(
          r'^(?:i\s*want|i\s*need|i\s*feel\s*like|i\s*like|looking\s*for)\s*(?:a\s*playlist\s*(?:of|with|for)?|to\s*listen\s*to|to\s*include|to\s*add|some|a|an)?\s*',
          caseSensitive: false),
      RegExp(
          r'^(?:similar\s*(?:vibes?|style|music|songs?|sound)?\s*(?:to|like)?)\s*',
          caseSensitive: false),
      RegExp(r'^(?:vibes?\s*(?:similar\s*to|like|to|with)?)\s*',
          caseSensitive: false),
      RegExp(r'^(?:music\s*(?:similar\s*to|like|by|from|with)?)\s*',
          caseSensitive: false),
      RegExp(
          r'^(?:songs?\s*(?:similar\s*to|by|like|from|of|with)?|tracks?\s*(?:similar\s*to|by|like|from|of|with)?)\s*',
          caseSensitive: false),
      RegExp(
          r'^(?:something\s*(?:like|similar\s*to|by|with)?|anything\s*(?:like|similar\s*to|by|with)?)\s*',
          caseSensitive: false),
      RegExp(
          r'^(?:chill|relaxing|upbeat|sad|happy|energetic|study|workout|gym|party|night|acoustic|lo-?fi|indie|pop|rock|hip-?hop|r&b|jazz|electronic)\s*(?:vibes?|music|songs?|playlist)?\s*(?:with|like|similar\s*to|by|from)?\s*',
          caseSensitive: false),
      RegExp(
          r'^(?:សុំ|ចង់បាន|ចង់ស្តាប់|ជួយធ្វើ|ធ្វើ|បង្កើត|រក|បើក|ចាក់|ដាក់|ថែម|ដាក់ថែម|សុំថែម|ស្រដៀង|ដូច|ស្ទីល)?\s*(?:តារាចម្រៀង|អ្នកចម្រៀង|artist|artists|បទ|ចម្រៀង|ផ្លេលីស|playlist|songs?|album|music|track|ពី|របស់)?\s*',
          caseSensitive: false),
    ];

    // Iteratively strip cascading prefixes (e.g. "make me a playlist" -> "including" -> "michael jackson")
    bool changed = true;
    while (changed) {
      changed = false;
      for (final pattern in prefixPatterns) {
        if (pattern.hasMatch(q)) {
          final newQ = q.replaceFirst(pattern, '').trim();
          if (newQ != q && newQ.isNotEmpty) {
            q = newQ;
            changed = true;
          }
        }
      }
    }

    // Strip common suffix filler words
    final suffixPatterns = [
      RegExp(
          r'\s+(?:songs?|tracks?|playlist|album|music|vibes?|only|style|ចម្រៀង|បទ|ផ្លេលីស|អាល់ប៊ុម)$',
          caseSensitive: false),
    ];

    for (final pattern in suffixPatterns) {
      q = q.replaceFirst(pattern, '').trim();
    }

    return q.isNotEmpty ? q : text;
  }

  void _onTextChanged() {
    setState(() {});
    final raw = _controller.text.trim();
    if (raw.isEmpty || _isRepeatedChars(raw)) {
      _debounce?.cancel();
      _searchGen++;
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = []);
      }
      return;
    }

    final query = _extractSearchQuery(raw);
    if (query.isEmpty || query.length < 2) {
      _debounce?.cancel();
      _searchGen++;
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = []);
      }
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) {
        _performSearch(query);
      }
    });
  }

  bool _isRepeatedChars(String s) {
    if (s.length < 4) return false;
    final first = s[0];
    int count = 0;
    for (final c in s.split('')) {
      if (c == first) count++;
    }
    return count / s.length > 0.8;
  }

  Future<void> _performSearch(String q) async {
    final gen = ++_searchGen;
    var results = await SearchService.search(q,
        includeAlbums: false, limitTracks: 20, limitArtists: 20);

    // If query has common typos/aliases (e.g. "weekend" -> "weeknd", "micheal" -> "michael")
    if (results.where((r) => r.type == 'artist').isEmpty) {
      final qLower = q.toLowerCase();
      String? altQuery;
      if (qLower.contains('micheal')) {
        altQuery =
            q.replaceAll(RegExp(r'micheal', caseSensitive: false), 'michael');
      } else if (qLower.contains('weekend')) {
        altQuery =
            q.replaceAll(RegExp(r'weekend', caseSensitive: false), 'weeknd');
      }
      if (altQuery != null) {
        final altResults = await SearchService.search(altQuery,
            includeAlbums: false, limitTracks: 20, limitArtists: 20);
        if (altResults.isNotEmpty) {
          results = altResults;
        }
      }
    }

    // If multi-word query produced no direct results, try searching the last 2 words
    if (results.isEmpty && q.contains(' ')) {
      final parts = q.split(RegExp(r'\s+'));
      if (parts.length > 2) {
        final lastTwo = parts.sublist(parts.length - 2).join(' ');
        results = await SearchService.search(lastTwo,
            includeAlbums: false, limitTracks: 20, limitArtists: 20);
      }
    }

    if (mounted && gen == _searchGen) {
      setState(() => _suggestions = results);
    }
  }

  void _onSuggestionTap(SearchResult item) {
    // Prevent duplicate selections
    if (_selectedChips.any((c) =>
        c.id == item.id ||
        (c.title.toLowerCase() == item.title.toLowerCase() &&
            c.type == item.type))) {
      CookieService.show(
        message: '"${item.title}" is already added',
        icon: Icons.check_circle_outline_rounded,
        iconColor: const Color(0xFF514AED),
      );
      setState(() => _suggestions = []);
      return;
    }

    if (_selectedChips.length >= _maxChipLimit) {
      CookieService.show(
        message: 'Maximum limit of $_maxChipLimit tags reached',
        icon: Icons.info_outline_rounded,
        iconColor: const Color(0xFF514AED),
      );
      setState(() => _suggestions = []);
      return;
    }

    final currentText = _controller.text;
    final query = _extractSearchQuery(currentText);

    final chip = PromptChip(
      type: item.type,
      id: item.id,
      title: item.title,
      subtitle: item.artist.isNotEmpty
          ? item.artist
          : (item.type == 'artist' ? 'Artist' : ''),
      image: item.image,
    );

    // Intelligently replace the matching token / query with the exact item title without wiping existing text
    String updatedText = currentText;
    final lowerCurrent = currentText.toLowerCase();
    final lowerTitle = item.title.toLowerCase();

    if (lowerCurrent.contains(lowerTitle)) {
      // Already mentioned in text, keep text as is
      updatedText = currentText;
    } else if (query.isNotEmpty && lowerCurrent.contains(query.toLowerCase())) {
      final lastIdx = lowerCurrent.lastIndexOf(query.toLowerCase());
      final endIdx = lastIdx + query.length;
      updatedText = currentText.substring(0, lastIdx) +
          item.title +
          currentText.substring(endIdx);
    } else {
      final words = currentText.trim().split(RegExp(r'\s+'));
      if (words.isNotEmpty && words.last.isNotEmpty) {
        final lastWord = words.last.toLowerCase();
        if (lastWord.length >= 2 && lowerTitle.startsWith(lastWord)) {
          final lastIdx = lowerCurrent.lastIndexOf(lastWord);
          final endIdx = lastIdx + lastWord.length;
          updatedText = currentText.substring(0, lastIdx) +
              item.title +
              currentText.substring(endIdx);
        } else if (currentText.trim().isNotEmpty) {
          updatedText = '${currentText.trim()} ${item.title}';
        } else {
          updatedText = item.title;
        }
      } else {
        updatedText = currentText.trim().isNotEmpty
            ? '${currentText.trim()} ${item.title}'
            : item.title;
      }
    }

    if (item.type == 'artist') {
      if (!_explicitArtistIds.contains(item.id)) {
        _explicitArtistIds.add(item.id);
      }
    } else if (item.type == 'song') {
      if (!_explicitTrackIds.contains(item.id)) {
        _explicitTrackIds.add(item.id);
      }
    }

    setState(() {
      _selectedChips.add(chip);
      _controller.text = updatedText;
      _controller.selection =
          TextSelection.collapsed(offset: updatedText.length);
      _suggestions = [];
    });
    _focusNode.requestFocus();
  }

  void _removeChip(PromptChip chip) {
    setState(() {
      _selectedChips.remove(chip);
      if (chip.type == 'artist') {
        _explicitArtistIds.remove(chip.id);
      } else if (chip.type == 'song') {
        _explicitTrackIds.remove(chip.id);
      }
    });
  }

  // ---- voice input ----

  Future<void> _startListening() async {
    if (_isListening) {
      await _stopListening();
      return;
    }

    if (!_speechAvailable) {
      try {
        _speechAvailable = await _speech.initialize(
          onError: (error) {
            if (mounted) {
              setState(() => _isListening = false);
              _stopListening();
            }
          },
        );
      } catch (_) {
        _speechAvailable = false;
      }
      if (!_speechAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Speech recognition not available — try typing your mood instead'),
            backgroundColor: Color(0xFF191919),
          ));
        }
        return;
      }
    }

    setState(() {
      _phase = _Phase.listening;
      _isListening = true;
      _liveSpokenText = '';
    });

    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          final normalized = _normalizeSpokenKhmer(result.recognizedWords);
          setState(() {
            _liveSpokenText = normalized;
            _controller.text = normalized;
            _controller.selection =
                TextSelection.collapsed(offset: normalized.length);
          });
          if (result.finalResult) {
            _stopListening();
            final violation = _checkSafetyPolicy(normalized);
            if (violation != null) {
              _showSafetyViolationDialog(violation);
            }
          }
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          localeId: _useKhmer ? 'km-KH' : null,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _phase = _Phase.idle;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_useKhmer
              ? 'Khmer speech not installed — add Khmer in Google voice settings'
              : 'Could not start speech recognition'),
          backgroundColor: const Color(0xFF191919),
        ));
      }
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (!mounted) return;
    setState(() {
      _isListening = false;
      _phase = _Phase.idle;
    });
  }

  Future<void> _startListeningForChatInput() async {
    if (_isChatListening) {
      await _stopListeningForChatInput();
      return;
    }

    if (!_speechAvailable) {
      try {
        _speechAvailable = await _speech.initialize(
          onError: (error) {
            if (mounted) {
              setState(() => _isChatListening = false);
            }
          },
        );
      } catch (_) {
        _speechAvailable = false;
      }
      if (!_speechAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Speech recognition not available — try typing your mood instead'),
            backgroundColor: Color(0xFF191919),
          ));
        }
        return;
      }
    }

    final initialText = _controller.text.trim();

    setState(() {
      _isChatListening = true;
    });

    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          final normalized = _normalizeSpokenKhmer(result.recognizedWords);
          final updated =
              initialText.isNotEmpty ? '$initialText $normalized' : normalized;
          setState(() {
            _controller.text = updated;
            _controller.selection =
                TextSelection.collapsed(offset: updated.length);
          });
          if (result.finalResult) {
            _stopListeningForChatInput();
          }
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          localeId: _useKhmer ? 'km-KH' : null,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _isChatListening = false);
      }
    }
  }

  Future<void> _stopListeningForChatInput() async {
    await _speech.stop();
    if (!mounted) return;
    setState(() {
      _isChatListening = false;
    });
  }

  String _normalizeSpokenKhmer(String raw) {
    return VoiceNormalizer.normalize(raw);
  }

  // ---- safety & policy validation ----

  Map<String, String>? _checkSafetyPolicy(String input) {
    final lower = input.toLowerCase();

    // Whitelist check: innocent musical titles/artists that contain "kill", "die", or "murder"
    final isKnownWhitelistedMusicTitle = RegExp(
      r'\b(kill\s*bill|the\s*killers?|killer\s*queen|die\s*for\s*you|die\s*young|live\s*and\s*let\s*die|born\s*to\s*die|till\s*i\s*collapse|murder\s*on\s*the\s*dancefloor|shoot\s*to\s*thrill)\b',
      caseSensitive: false,
    ).hasMatch(lower);

    // 1. Harm, Violence, Murder, Killing & Suicide
    if (!isKnownWhitelistedMusicTitle &&
        RegExp(
          r'(\bkill(ing|ed|s)?\b|\bmurder(ing|ed|s)?\b|\bassassinat(e|ing|ion)\b|\bmassacre\b|\bslaughter\b|\bgenocide\b|\bbehead(ing)?\b|\bshoot(ing)?\s+(someone|somebody|people|person|him|her|them|everyone|school|up\b)|\bschool\s+shooting\b|\bstab(bing)?\b|\btortur(e|ing)\b|\bkidnap(ping)?\b|\bpoison(ing)?\s+(someone|people|him|her)|\bsuicide\b|\bself\s*harm\b|\bhurt\s+(myself|someone|people|others)\b|\bhow\s+to\s+die\b|\bcut\s+my\s+(wrist|wrists)\b|\bhang\s+myself\b|\bbomb(ing|s)?\b|\bmake\s+a\s+bomb\b|\bbuild\s+a\s+bomb\b|\bdetonate\b|\bterroris(m|t)\b|\barson\b|\bburn\s+(someone|people|house\s+down)\b|សម្លាប់|ចង់ស្លាប់|ចង់សម្លាប់|បាញ់សម្លាប់|បាញ់មនុស្ស|បាញ់គេ|ចាក់សម្លាប់|កាប់សម្លាប់|កាប់មនុស្ស|បំផ្ទុះគ្រាប់|គ្រាប់បែក|ធ្វើបាបគេ|អត្តឃាត|ចងក|លោតទឹកសម្លាប់ខ្លួន|លោតសម្លាប់ខ្លួន)',
          caseSensitive: false,
        ).hasMatch(lower)) {
      return {
        'title': 'Safety Guideline',
        'reason':
            'Prompts involving violence, harm, weapons, or dangerous activities cannot be used to generate playlists.',
        'suggestion':
            'Try asking for energetic workout, dark ambient, calm, or mood-boosting music instead.'
      };
    }

    // 2. Explicit sexual content & pornography
    if (RegExp(
            r'(\bporn(o|ography)?\b|\bhentai\b|\bsex\s*video\b|\bnaked\b|\bnude(s)?\b|\bxxx\b|\bnsfw\b|\bsexually\s*explicit\b|\bgangbang\b|\bincest\b|\bpedophil(e|ia)\b|\brape\b|\braping\b|\bmolest(ing|ation)?\b|\bblowjob\b|\bhandjob\b|\bdick\s*pic\b|រួមភេទ|សិច|រំលោភ|ចាប់រំលោភ|អាសអាភាស|រូបស្រាត|ស្រាត)',
            caseSensitive: false)
        .hasMatch(lower)) {
      return {
        'title': 'Inappropriate Content',
        'reason':
            'Sexually explicit or adult-oriented prompts are not permitted on Melo.',
        'suggestion':
            'Try asking for romantic, sensual, or slow R&B love songs instead.'
      };
    }

    // 3. Hate speech, harassment, slurs
    if (RegExp(
            r'(\bnigger\b|\bnigga\b|\bfaggot\b|\bhate\s*speech\b|\bracist\b|\bracism\b|\bkill\s*all\s+(blacks?|whites?|asians?|jews?|muslims?)\b|\bwhite\s*supremacy\b|\bneo-?nazi\b|\bterrorist\b|\bchink\b|\bspic\b|\bkike\b|\bretard\b)',
            caseSensitive: false)
        .hasMatch(lower)) {
      return {
        'title': 'Community Guidelines',
        'reason':
            'Prompts containing hate speech, discrimination, or abusive terms are strictly prohibited.',
        'suggestion':
            'Please use friendly music requests or mood descriptions.'
      };
    }

    // 4. Code injection / system prompt tampering
    if (RegExp(
            r'(ignore\s*(all\s*)?previous\s*instructions|system\s*prompt|drop\s*table|<script>|select\s*\*\s*from|\bjailbreak\b|developer\s*mode|override\s*rule)',
            caseSensitive: false)
        .hasMatch(lower)) {
      return {
        'title': 'Invalid Request',
        'reason':
            'System instructions and code commands cannot be interpreted as a musical mood.',
        'suggestion': 'Try describing a musical vibe, artist name, or genre.'
      };
    }

    // 5. Dangerous substances & illegal drug transactions
    if (RegExp(
            r'(\bmake\s+meth\b|\bcook\s+meth\b|\bhow\s+to\s+make\s+(drugs|heroin|fentanyl|cocaine)\b|\bsell\s+(cocaine|meth|heroin|fentanyl)\b|\bbuy\s+(cocaine|meth|heroin|fentanyl)\b|ថ្នាំញៀន|ជួញដូរគ្រឿងញៀន)',
            caseSensitive: false)
        .hasMatch(lower)) {
      return {
        'title': 'Prohibited Content',
        'reason':
            'Prompts soliciting illegal substances or chemical manufacturing are not allowed.',
        'suggestion':
            'Try requesting upbeat electronic, hip hop, or party songs instead.'
      };
    }

    // 6. Excessive Duration Request (> 3 hours or > 60 songs)
    var numNormalized = lower
        .replaceAll('០', '0')
        .replaceAll('១', '1')
        .replaceAll('២', '2')
        .replaceAll('៣', '3')
        .replaceAll('៤', '4')
        .replaceAll('៥', '5')
        .replaceAll('៦', '6')
        .replaceAll('៧', '7')
        .replaceAll('៨', '8')
        .replaceAll('៩', '9');

    final hourMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h|ម៉ោង)')
        .firstMatch(numNormalized);
    if (hourMatch != null) {
      final h = double.tryParse(hourMatch.group(1) ?? '') ?? 0;
      if (h > 3) {
        return {
          'title': 'Playlist Length Limit',
          'reason':
              'Playlists are capped at a maximum of 3 hours (${(h).toInt()} hours requested) to ensure instant generation and audio streaming quality.',
          'suggestion':
              'Melo can generate up to 3 hours (around 55 songs) per playlist. Try asking for "3 hours" or shorter.'
        };
      }
    }

    final songCountMatch =
        RegExp(r'(\d+)\s*(?:songs?|tracks?|បទ)').firstMatch(numNormalized);
    if (songCountMatch != null) {
      final count = int.tryParse(songCountMatch.group(1) ?? '') ?? 0;
      final isYear = count >= 1900 && count <= 2100;
      if (count > 60 && !isYear) {
        return {
          'title': 'Track Count Limit',
          'reason':
              'The maximum playlist size is 60 songs ($count songs requested). Large batches cannot guarantee audio stream accuracy.',
          'suggestion':
              'Try requesting between 10 to 50 songs for the best listening experience.'
        };
      }
    }

    // 7. Gibberish / spam
    if (input.length > 10 && _isRepeatedChars(input)) {
      return {
        'title': 'Unrecognized Prompt',
        'reason': 'Your prompt appears to be repeated characters or spam.',
        'suggestion':
            'Type or speak a music mood like "chill night", "workout", or your favorite artist.'
      };
    }

    // 8. Non-musical technical / factual queries (e.g. "how to cook rice", "write python code")
    if (RegExp(r'^(what is|who is the president|write code|solve this|translate to|math|calculate|recipe|how to fix|how to cook|python|javascript|who won)',
                caseSensitive: false)
            .hasMatch(lower) &&
        !lower.contains('song') &&
        !lower.contains('music') &&
        !lower.contains('playlist') &&
        !lower.contains('បទ') &&
        !lower.contains('ចម្រៀង')) {
      return {
        'title': 'Music Requests Only',
        'reason':
            'Melo AI is a dedicated music curator and cannot answer general knowledge, coding, or recipe questions.',
        'suggestion':
            'Ask for a music mood, playlist vibe, or songs by your favorite artists!'
      };
    }

    return null;
  }

  void _showSafetyViolationDialog(Map<String, String> violation) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFF6C5CE7),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      violation['title'] ?? 'Notice',
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 15.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                violation['reason'] ?? 'This request cannot be generated.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              if (violation['suggestion'] != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF282828),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.lightbulb_outline_rounded,
                          color: Color(0xFF6C5CE7),
                          size: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          violation['suggestion']!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontFamily: 'Poppins',
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C5CE7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- generation ----

  String _sanitizeMood(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'[<>{};\\]'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    if (s.length > _maxCharLimit) s = s.substring(0, _maxCharLimit);
    return s;
  }

  Future<void> _startGenerate(
    String mood, {
    List<String>? artistIdsOverride,
    List<String>? trackIdsOverride,
    String sourceMode = 'chat',
  }) async {
    final sanitized = _sanitizeMood(mood);
    if (_generating ||
        (sanitized.isEmpty &&
            _selectedChips.isEmpty &&
            (artistIdsOverride == null || artistIdsOverride.isEmpty) &&
            (trackIdsOverride == null || trackIdsOverride.isEmpty))) {
      return;
    }

    // Check Premium AI generation allowance (2 free lifetime trials)
    if (!PremiumService().canGenerateAiPlaylist) {
      PremiumService.showUpsell(
        context,
        reason:
            'You have used your 2 free AI playlist trials. Upgrade to Melo Premium for unlimited AI generations!',
        feature: 'AI Playlist Generator',
      );
      return;
    }

    if (sanitized.isNotEmpty) {
      final violation = _checkSafetyPolicy(sanitized);
      if (violation != null) {
        _showSafetyViolationDialog(violation);
        return;
      }
    }

    final artistChips =
        _selectedChips.where((c) => c.type == 'artist').toList();
    final songChips = _selectedChips.where((c) => c.type == 'song').toList();

    final artistIds = artistIdsOverride ??
        [
          ...artistChips.map((c) => c.id),
          ..._explicitArtistIds,
        ];
    final trackIds = trackIdsOverride ??
        [
          ...songChips.map((c) => c.id),
          ..._explicitTrackIds,
        ];

    // Build the mood text the AI sees: include all chips explicitly
    String moodForAi = sanitized;
    if (_selectedChips.isNotEmpty) {
      final chipDetails = <String>[];
      if (artistChips.isNotEmpty) {
        chipDetails
            .add('Artists: ${artistChips.map((c) => c.title).join(', ')}');
      }
      if (songChips.isNotEmpty) {
        chipDetails.add(
            'Tracks: ${songChips.map((c) => '"${c.title}" by ${c.subtitle}').join(', ')}');
      }
      final chipHeader = chipDetails.join(' | ');
      moodForAi = sanitized.isEmpty ? chipHeader : '$chipHeader. $sanitized';
    }

    _generating = true;
    widget.onBuildingChanged?.call(true);
    FocusScope.of(context).unfocus();
    setState(() {
      _mood = moodForAi;
      _phase = _Phase.building;
      _suggestions = [];
      _selectedChips.clear();
      _explicitArtistIds.clear();
      _explicitTrackIds.clear();
    });

    _buildAnim.value = 0.0;

    // Linear progression across the 4 stages driven directly by pipeline events
    void updateStage(int stage) {
      if (!mounted) return;
      final targetProgress = ((stage + 1) * 0.23).clamp(0.0, 0.92);
      _buildAnim.animateTo(
        targetProgress,
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOutCubic,
      );
    }

    final bool promptExcludesFollowed = RegExp(
      r'(?:exclude|without|don.?t\s*include|no)\s+(?:my\s+)?(?:favorite|followed|fav)?\s*artists?',
      caseSensitive: false,
    ).hasMatch(moodForAi);
    final effectiveArtistIds = promptExcludesFollowed ? <String>[] : artistIds;

    final result = await GenerateService.generate(
      _mood,
      artistIds: effectiveArtistIds,
      trackIds: trackIds,
      onStageChanged: updateStage,
    );

    if (mounted) {
      _buildAnim.stop();
      await _buildAnim.animateTo(1.0,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
    _generating = false;
    widget.onBuildingChanged?.call(false);
    if (!mounted) return;

    if (result.success && result.songs.isNotEmpty) {
      if (!PremiumService().isPremium) {
        PremiumService().recordAiGeneration();
      }

      final historyId = await GeneratedHistoryService.addHistory(
        mood: result.mood,
        title: result.title,
        description: result.description,
        songs: result.songs,
        sourceMode: sourceMode,
      );
      if (!mounted) return;

      // Start warming streams while the completion animation and page
      // transition are still on-screen. Previously this began in the next
      // page's initState, leaving the first tap to wait for cache warm-up.
      _prefetchGeneratedTracks(result.songs);

      // Check if user requested a long duration (e.g., 2 hours / 35+ songs) but artist only has fewer available
      final requestedCount =
          GenerateService.detectSongCountFromMood(moodForAi, 20);
      final isUnderfulfilled =
          requestedCount > 20 && result.songs.length < (requestedCount * 0.75);

      Navigator.of(context, rootNavigator: true)
          .push(_ZoomFadePageRoute(
        page: GeneratedPlaylistScreen(
          mood: result.mood,
          title: result.title,
          description: result.description,
          songs: result.songs,
          streamsAlreadyPrefetching: true,
          historyId: historyId,
        ),
      ))
          .whenComplete(() {
        if (mounted) {
          setState(() {
            _phase = _Phase.idle;
            _buildAnim.reset();
            _controller.clear();
            _mood = '';
          });
        }
      });

      if (isUnderfulfilled && mounted) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: const Color(0xFF222222),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              content: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: Color(0xFF6C5CE7), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'All ${result.songs.length} available songs from this artist were delivered.',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontFamily: 'Poppins'),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 4),
            ));
          }
        });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(result.error ?? 'Could not generate a playlist right now'),
          backgroundColor: const Color(0xFF191919),
        ));
        setState(() {
          _phase = _Phase.idle;
          _buildAnim.reset();
        });
      }
    }
  }

  void _prefetchGeneratedTracks(List<Map<String, dynamic>> songs) {
    final tracks = songs
        .map((song) => SearchResult(
              type: 'song',
              id: song['deezerId']?.toString() ?? '',
              title: song['title']?.toString() ?? '',
              artist: song['artist']?.toString() ?? '',
              artistId: song['artistId']?.toString() ?? '',
              artistImage: song['artistImage']?.toString() ?? '',
              image: song['image']?.toString() ?? '',
              duration: song['duration']?.toString() ?? '',
              nbFan: 0,
              previewUrl: song['previewUrl']?.toString() ?? '',
            ))
        .where((track) => track.title.isNotEmpty)
        .toList();
    if (tracks.isEmpty) return;

    // Prioritize the first five likely taps. The remaining streams continue
    // through the gentle CDN queue without competing with playback.
    YouTubeService.prefetchStreamUrls(tracks, batchSize: 5, maxConcurrent: 5);
    BackgroundPrefetchService.instance
        .enqueueTracks(tracks, tag: 'generation_complete');
  }

  String _mood = '';

  Future<List<PromptChip>> _autoDetectArtistsFromText(String text) async {
    final lower = text.toLowerCase().trim();
    if (lower.isEmpty) return [];

    // Strip conversational prefixes
    var cleaned = text.replaceAll(
      RegExp(
        r'^(?:can\s*you\s*)?(?:please\s*)?(?:add|include|put|throw\s*in|mix\s*in|give\s*me|more)?\s*(?:extra|more|some|another)?\s*(?:artists?|singers?|bands?|songs?\s*by|tracks?\s*by|music\s*by|songs?\s*from|tracks?\s*from|from|by)?\s*',
        caseSensitive: false,
      ),
      '',
    ).trim();

    cleaned = cleaned.replaceAll(
      RegExp(r'\s+(?:too|please|plz|as\s*well|also|only|songs?|playlist)$',
          caseSensitive: false),
      '',
    ).trim();

    if (cleaned.isEmpty) return [];

    // Split on delimiters (and, &, +, comma, or Khmer)
    final delimiter = RegExp(
        r'\s+(?:and|&|\+|with|also|plus|featuring|feat|ft|ឬ|និង|ជាមួយ)\s+|,|\+');
    final rawCandidates = cleaned
        .split(delimiter)
        .map((c) => c.trim())
        .where((c) => c.length >= 2 && c.length <= 40)
        .toList();
    if (rawCandidates.isEmpty) return [];

    final chips = <PromptChip>[];
    for (final candidate in rawCandidates.take(4)) {
      // 1. Check existing autocomplete suggestions first
      final existingSuggestion = _suggestions.cast<SearchResult?>().firstWhere(
            (s) =>
                s != null &&
                s.type == 'artist' &&
                (s.title.toLowerCase().contains(candidate.toLowerCase()) ||
                    candidate.toLowerCase().contains(s.title.toLowerCase())),
            orElse: () => null,
          );
      if (existingSuggestion != null) {
        chips.add(PromptChip(
          type: 'artist',
          id: existingSuggestion.id,
          title: existingSuggestion.title,
          subtitle: 'Artist',
          image: existingSuggestion.image,
        ));
        continue;
      }

      // 2. Fast artist search lookup
      try {
        final results = await SearchService.search(candidate,
                includeAlbums: false, limitTracks: 0, limitArtists: 4)
            .timeout(const Duration(milliseconds: 1500));
        final artistMatch = results.where((r) => r.type == 'artist').firstOrNull;
        if (artistMatch != null) {
          final tLower = artistMatch.title.toLowerCase().trim();
          final cLower = candidate.toLowerCase().trim();
          if (tLower.contains(cLower) ||
              cLower.contains(tLower) ||
              cLower.length >= 3) {
            chips.add(PromptChip(
              type: 'artist',
              id: artistMatch.id,
              title: artistMatch.title,
              subtitle: 'Artist',
              image: artistMatch.image,
            ));
          }
        }
      } catch (_) {}
    }
    return chips;
  }

  void _handleUserPrompt(String rawText) async {
    final sanitized = _sanitizeMood(rawText);
    if (sanitized.isEmpty && _selectedChips.isEmpty) return;

    // 1. Check if user is confirming a pending playlist in conversation
    final isConfirmIntent = RegExp(
      r'^(yes|yeah|yep|yup|sure|ok|okay|confirm|generate|do it|make it|let\x27s do it|go ahead|play|create|sounds good|looks good|perfect|បាទ|ចាស|ធ្វើ|ធ្វើមក|យល់ព្រម|បង្កើត|yes please|go)$',
      caseSensitive: false,
    ).hasMatch(sanitized.toLowerCase());

    if (isConfirmIntent && _accumulatedMood.isNotEmpty) {
      setState(() {
        _controller.clear();
        _selectedChips.clear();
        _suggestions = [];
        _messages.add(_ChatMessage(
          id: 'user_${DateTime.now().millisecondsSinceEpoch}',
          isUser: true,
          text: rawText,
        ));
        _messages.add(_ChatMessage(
          id: 'ai_ack_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          text: "Awesome! Crafting your personalized playlist now 🎶...",
          isLoading: true,
        ));
      });
      _scrollToBottom();
      _startGenerate(
        _accumulatedMood,
        artistIdsOverride: _pendingArtistIds,
        trackIdsOverride: _pendingTrackIds,
        sourceMode: 'chat',
      );
      return;
    }

    // 2. Policy and safety check
    if (sanitized.isNotEmpty) {
      final violation = _checkSafetyPolicy(sanitized);
      if (violation != null) {
        setState(() {
          _controller.clear();
          _selectedChips.clear();
          _suggestions = [];
          _messages.add(_ChatMessage(
            id: 'user_${DateTime.now().millisecondsSinceEpoch}',
            isUser: true,
            text: rawText,
          ));
          _messages.add(_ChatMessage(
            id: 'ai_refusal_${DateTime.now().millisecondsSinceEpoch}',
            isUser: false,
            text:
                "I can't generate a playlist for that request. ${violation['reason'] ?? ''}\n\n💡 ${violation['suggestion'] ?? ''}",
          ));
        });
        _scrollToBottom();
        _showSafetyViolationDialog(violation);
        return;
      }
    }

    final activeChips = List<PromptChip>.from(_selectedChips);

    // If user did not manually tap chips, auto-detect mentioned artists from their message
    if (activeChips.isEmpty && rawText.isNotEmpty) {
      final detected = await _autoDetectArtistsFromText(rawText);
      if (detected.isNotEmpty) {
        activeChips.addAll(detected);
      }
    }

    final artistChips =
        activeChips.where((c) => c.type == 'artist').toList();
    final songChips = activeChips.where((c) => c.type == 'song').toList();

    final newArtistIds = [
      ...artistChips.map((c) => c.id),
      ..._explicitArtistIds,
    ];
    final newTrackIds = [
      ...songChips.map((c) => c.id),
      ..._explicitTrackIds,
    ];

    String promptSegment = sanitized;
    final tags = <String>[];
    if (activeChips.isNotEmpty) {
      final chipDetails = <String>[];
      if (artistChips.isNotEmpty) {
        final names = artistChips.map((c) => c.title).toList();
        tags.addAll(names);
        chipDetails.add('Artists: ${names.join(', ')}');
      }
      if (songChips.isNotEmpty) {
        final songNames = songChips.map((c) => c.title).toList();
        tags.addAll(songNames);
        chipDetails.add(
            'Tracks: ${songChips.map((c) => '"${c.title}" by ${c.subtitle}').join(', ')}');
      }
      final chipHeader = chipDetails.join(' | ');
      promptSegment =
          sanitized.isEmpty ? chipHeader : '$chipHeader. $sanitized';
    }

    // Accumulate conversation context or start fresh
    if (_accumulatedMood.isEmpty) {
      _accumulatedMood = 'Original request:\n$promptSegment';
    } else {
      // Keep the complete chat request, but make recency unambiguous for the
      // generation model: a new instruction is an update, not a suggestion.
      _accumulatedMood = '$_accumulatedMood\n\n'
          'Latest refinement (highest priority — update the playlist to satisfy this):\n'
          '$promptSegment';
    }

    final bool refinementExcludesFollowed = RegExp(
      r'(?:exclude|without|don.?t\s*include|no)\s+(?:my\s+)?(?:favorite|followed|fav)?\s*artists?',
      caseSensitive: false,
    ).hasMatch(rawText);
    if (refinementExcludesFollowed) {
      _pendingArtistIds.clear();
    } else {
      _pendingArtistIds = [
        ..._pendingArtistIds,
        ...newArtistIds.where((id) => !_pendingArtistIds.contains(id)),
      ];
    }
    _pendingTrackIds = [
      ..._pendingTrackIds,
      ...newTrackIds.where((id) => !_pendingTrackIds.contains(id)),
    ];

    String? previewArt;
    if (activeChips.isNotEmpty) {
      previewArt = activeChips.first.image;
    }

    final userMsgText = rawText.isNotEmpty ? rawText : tags.join(', ');
    final aiDialogue =
        _generateConversationalAiReply(userMsgText, _accumulatedMood);
    final previewTitle = _derivePreviewTitle(_accumulatedMood);
    final previewDesc = _derivePreviewDescription(_accumulatedMood);
    final quickSuggestions = _deriveQuickSuggestions(_accumulatedMood,
        chips: List.from(activeChips));

    final capturedChips = List<PromptChip>.from(activeChips);

    setState(() {
      _controller.clear();
      _selectedChips.clear();
      _explicitArtistIds.clear();
      _explicitTrackIds.clear();
      _suggestions = [];

      _messages.add(_ChatMessage(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        isUser: true,
        text: userMsgText,
        chips: capturedChips,
      ));

      _messages.add(_ChatMessage(
        id: 'ai_reply_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: aiDialogue,
      ));

      _messages.add(_ChatMessage(
        id: 'preview_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: _accumulatedMood,
        isConfirmation: true,
        previewTitle: previewTitle,
        previewDescription: previewDesc,
        previewImage: previewArt,
        tags: tags,
        chips: capturedChips,
        artistIds: _pendingArtistIds,
        trackIds: _pendingTrackIds,
        suggestionOptions: quickSuggestions,
      ));
    });

    _scrollToBottom();
    _saveCurrentChatSession();
  }

  String _generateConversationalAiReply(String userPrompt, String fullMood) {
    final lower = userPrompt.toLowerCase();

    if (lower.contains('khmer') ||
        lower.contains('ខ្មែរ') ||
        lower.contains('vannda') ||
        lower.contains('suly') ||
        lower.contains('tena')) {
      return "Got it! I'll keep this Khmer playlist faithful to the mood, situation, and any artist details you've given me. Would you like me to generate it now?";
    }
    if (lower.contains('chill') ||
        lower.contains('relax') ||
        lower.contains('study') ||
        lower.contains('sleep') ||
        lower.contains('calm') ||
        lower.contains('coffee')) {
      return "That sounds soothing! I've prepared a mellow, smooth playlist with relaxing beats and calm melodies. Shall I go ahead and make this for you?";
    }
    if (lower.contains('party') ||
        lower.contains('dance') ||
        lower.contains('workout') ||
        lower.contains('gym') ||
        lower.contains('upbeat') ||
        lower.contains('energy') ||
        lower.contains('hype')) {
      return "Love the energy! I've tuned this mix for maximum hype with fast-paced tempos and dynamic beats. Ready to generate this playlist?";
    }
    if (lower.contains('sad') ||
        lower.contains('lonely') ||
        lower.contains('heartbreak') ||
        lower.contains('cry') ||
        lower.contains('melancholy') ||
        lower.contains('broken')) {
      return "I feel you. I've gathered deep, heartfelt emotional tracks with touching vocals and acoustic warmth. Would you like me to generate this for you?";
    }
    if (lower.contains('rock') ||
        lower.contains('metal') ||
        lower.contains('guitar') ||
        lower.contains('band')) {
      return "Awesome! I've packed this with driving guitars, energetic drums, and raw anthems. Ready to create this mix?";
    }
    if (lower.contains('jazz') ||
        lower.contains('r&b') ||
        lower.contains('soul') ||
        lower.contains('lo-fi') ||
        lower.contains('lofi')) {
      return "Smooth choice. I've blended rich chords, velvet vocals, and soulful rhythms into this vibe. Shall we build this playlist?";
    }

    return "Sounds great! I've shaped a personalized 20-song playlist around that vibe. Would you like to confirm and generate it now, or add any other artists or styles?";
  }

  String _derivePreviewDescription(String fullMood) {
    // Check if prompt has explicit artists
    final artistMatches =
        RegExp(r'Artists?:\s*([^|\.\n]+)', caseSensitive: false)
            .allMatches(fullMood);
    final artistNames = <String>[];
    for (final m in artistMatches) {
      final names = m.group(1)?.split(',') ?? [];
      for (final n in names) {
        final t = n.trim();
        if (t.isNotEmpty && !artistNames.contains(t)) artistNames.add(t);
      }
    }

    if (artistNames.isNotEmpty) {
      if (artistNames.length == 1) {
        return 'An authentic selection featuring top tracks from ${artistNames[0]} with matching vibes.';
      } else if (artistNames.length == 2) {
        return 'An equal blend featuring iconic tracks from ${artistNames[0]} and ${artistNames[1]}.';
      } else {
        return 'A hand-crafted blend featuring ${artistNames.take(3).join(", ")} and complementary tracks.';
      }
    }

    final lower = fullMood.toLowerCase();
    if (lower.contains('study') ||
        lower.contains('focus') ||
        lower.contains('homework')) {
      return 'Calm instrumental & lo-fi beats designed for deep focus and study.';
    }
    if (lower.contains('chill') ||
        lower.contains('relax') ||
        lower.contains('calm') ||
        lower.contains('coffee')) {
      return 'Mellow rhythms and soothing melodies to help you unwind.';
    }
    if (lower.contains('party') ||
        lower.contains('dance') ||
        lower.contains('club') ||
        lower.contains('edm')) {
      return 'High-energy dance anthems and upbeat bangers for party mode.';
    }
    if (lower.contains('workout') ||
        lower.contains('gym') ||
        lower.contains('fitness') ||
        lower.contains('pump')) {
      return 'Fast-paced, heavy-hitting tracks to keep your adrenaline high.';
    }
    if (lower.contains('sad') ||
        lower.contains('heartbreak') ||
        lower.contains('lonely') ||
        lower.contains('cry')) {
      return 'Deep emotional songs with heartfelt vocals and acoustic warmth.';
    }
    if (lower.contains('rock') ||
        lower.contains('metal') ||
        lower.contains('guitar')) {
      return 'Driving guitars, punchy drums, and iconic rock anthems.';
    }
    if (lower.contains('khmer') ||
        lower.contains('ខ្មែរ') ||
        lower.contains('vannda') ||
        lower.contains('suly') ||
        lower.contains('tena')) {
      return 'Top hits and fresh modern rhythms from beloved Khmer artists.';
    }
    if (lower.contains('rap') ||
        lower.contains('hip hop') ||
        lower.contains('hip-hop')) {
      return 'Smooth rhymes, crisp 808s, and timeless hip hop flows.';
    }
    if (lower.contains('jazz') ||
        lower.contains('r&b') ||
        lower.contains('soul')) {
      return 'Velvet vocals, rich chords, and late-night soulful vibes.';
    }

    var clean = fullMood
        .replaceAll(
            RegExp(r'^(?:Artists?|Tracks?):\s*', caseSensitive: false), '')
        .trim();
    if (clean.length > 70) clean = '${clean.substring(0, 67)}...';
    return clean.isNotEmpty
        ? 'A hand-picked blend of songs matching $clean.'
        : 'A hand-picked selection of tracks curated for your vibe.';
  }

  List<String> _deriveQuickSuggestions(String fullMood,
      {List<PromptChip> chips = const []}) {
    final lower = fullMood.toLowerCase();

    // Check if user specified a prominent artist in the tags or prompt
    String? artistName;
    if (chips.any((c) => c.type == 'artist')) {
      artistName = chips.firstWhere((c) => c.type == 'artist').title;
    }
    if (artistName == null || artistName.isEmpty) {
      final m = RegExp(r'Artists?:\s*([^,\n|.]+)', caseSensitive: false)
          .firstMatch(fullMood);
      if (m != null) {
        artistName = m.group(1)?.trim();
      }
    }

    if (artistName != null && artistName.isNotEmpty) {
      if (lower.contains('michael jackson')) {
        return [
          'More 80s Pop & Funk',
          'Add Bruno Mars & The Weeknd',
          'Add Thriller era hits'
        ];
      }
      if (lower.contains('kanye')) {
        return [
          'Add Travis Scott & Kid Cudi',
          'Late Registration vibe',
          'More soulful hip hop'
        ];
      }
      if (lower.contains('weeknd')) {
        return [
          'Add Synthwave & R&B',
          'Add Daft Punk & Dua Lipa',
          'After Hours dark vibe'
        ];
      }
      return [
        'More $artistName top hits',
        'Similar artists to $artistName',
        'Add acoustic version'
      ];
    }

    // Specific genre and mood detections
    if (lower.contains('khmer') ||
        lower.contains('ខ្មែរ') ||
        lower.contains('vannda') ||
        lower.contains('suly') ||
        lower.contains('tena')) {
      return [
        'Add VannDa & Suly Pheng',
        'Add classic Khmer hits',
        'More upbeat Khmer hip-hop'
      ];
    }
    if (lower.contains('chill') ||
        lower.contains('relax') ||
        lower.contains('study') ||
        lower.contains('sleep') ||
        lower.contains('calm') ||
        lower.contains('coffee')) {
      return [
        'Add Lo-Fi beats',
        'Acoustic guitar focus',
        'Soft piano background'
      ];
    }
    if (lower.contains('party') ||
        lower.contains('dance') ||
        lower.contains('club') ||
        lower.contains('edm') ||
        lower.contains('rave')) {
      return [
        'High-tempo EDM bangers',
        'Add 2010s dance anthems',
        'More bass drops'
      ];
    }
    if (lower.contains('workout') ||
        lower.contains('gym') ||
        lower.contains('fitness') ||
        lower.contains('pump') ||
        lower.contains('running')) {
      return [
        'Hard-hitting Trap & Rap',
        'High BPM phonk beats',
        'Add rock workout anthems'
      ];
    }
    if (lower.contains('sad') ||
        lower.contains('lonely') ||
        lower.contains('heartbreak') ||
        lower.contains('cry') ||
        lower.contains('melancholy')) {
      return [
        'Deep emotional lyrics',
        'Add acoustic ballads',
        'Slow ambient indie'
      ];
    }
    if (lower.contains('rock') ||
        lower.contains('metal') ||
        lower.contains('punk') ||
        lower.contains('guitar')) {
      return [
        'Add Classic Rock legends',
        'Modern Alternative Rock',
        'Heavy guitar solos'
      ];
    }
    if (lower.contains('rap') ||
        lower.contains('hip hop') ||
        lower.contains('hip-hop') ||
        lower.contains('trap')) {
      return [
        'Add 90s Golden Era Rap',
        'Modern Melodic Trap',
        'Smooth R&B crossover'
      ];
    }
    if (lower.contains('jazz') ||
        lower.contains('soul') ||
        lower.contains('blues') ||
        lower.contains('r&b')) {
      return [
        'Late night smooth jazz',
        'Classic Neo-Soul',
        'Vintage vinyl warmth'
      ];
    }
    if (lower.contains('k-pop') || lower.contains('kpop')) {
      return ['Add BTS & BLACKPINK', 'Upbeat dance K-Pop', 'Chill Korean R&B'];
    }

    // Dynamic fallback based on prompt words
    return [
      'More upbeat tempo',
      'Mellow & chill focus',
      'Add top trending hits'
    ];
  }

  String _derivePreviewTitle(String prompt) {
    var raw = prompt.trim();
    if (raw.isEmpty) return 'Personalized Mix';

    // Check if prompt has explicit artists
    final artistMatches =
        RegExp(r'Artists?:\s*([^|\.\n]+)', caseSensitive: false)
            .allMatches(raw);
    final artistNames = <String>[];
    for (final m in artistMatches) {
      final names = m.group(1)?.split(',') ?? [];
      for (final n in names) {
        final t = n.trim();
        if (t.isNotEmpty && !artistNames.contains(t)) artistNames.add(t);
      }
    }

    if (artistNames.isNotEmpty) {
      if (artistNames.length == 1) {
        return '${artistNames[0]} Mix';
      } else if (artistNames.length == 2) {
        return '${artistNames[0]} & ${artistNames[1]} Mix';
      } else {
        return '${artistNames[0]}, ${artistNames[1]} & More';
      }
    }

    // If accumulated chat conversation, take the latest refinement if present
    var clean = raw;
    final refinementMatch =
        RegExp(r'Latest refinement[^\n]*\n+([\s\S]+)$').firstMatch(clean);
    if (refinementMatch != null) {
      clean = refinementMatch.group(1)?.trim() ?? clean;
    } else {
      final origMatch =
          RegExp(r'Original request:\s*\n+([\s\S]+)$').firstMatch(clean);
      if (origMatch != null) {
        clean = origMatch.group(1)?.trim() ?? clean;
      }
    }

    // Remove technical prefix markers like "Artists:" or "Tracks:" or "refined with:"
    clean = clean.replaceAll(
        RegExp(r'^(?:Artists?|Tracks?):\s*', caseSensitive: false), '');
    clean = clean.replaceAll(
        RegExp(r',?\s*refined with:\s*', caseSensitive: false), ' & ');
    clean = clean.replaceAll(
        RegExp(r'\s*\|\s*Tracks?:\s*.*', caseSensitive: false), '');
    clean = clean.replaceAll(
        RegExp(r'\s*\|\s*Artists?:\s*', caseSensitive: false), ' & ');

    // Strip common prompt prefixes
    clean = clean
        .replaceAll(
          RegExp(
              r'^(?:hey\s*)?(?:can\s*you|can\s*u|please)?\s*(?:make|give|create|build|find|play|add|include)\s*(?:me\s*)?(?:a\s*)?(?:playlist\s*(?:for|of|with)?\s*)?',
              caseSensitive: false),
          '',
        )
        .trim();
    if (clean.isEmpty) return 'Personalized Mix';
    clean = clean[0].toUpperCase() + clean.substring(1);
    if (!clean.toLowerCase().contains('playlist') &&
        !clean.toLowerCase().contains('mix') &&
        !clean.toLowerCase().contains('vibe')) {
      clean = '$clean Mix';
    }
    if (clean.length > 32) {
      return '${clean.substring(0, 29)}...';
    }
    return clean;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF191919),
      child: SafeArea(
        bottom: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _phase == _Phase.building
              ? _buildBuildingView()
              : _buildIdleView(),
        ),
      ),
    );
  }

  Widget _buildIdleView() {
    return ListenableBuilder(
      listenable: PlaybackService(),
      builder: (context, _) {
        final playback = PlaybackService();
        final hasMiniPlayer =
            playback.isVisible && playback.currentTrack != null;

        return Stack(
          children: [
            Column(
              key: const ValueKey('generate_idle_column'),
              children: [
                _buildTopBar(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.03),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: _mode == _InputMode.voice
                        ? _buildVoiceModeView(hasMiniPlayer: hasMiniPlayer)
                        : _buildChatView(hasMiniPlayer: hasMiniPlayer),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          const SizedBox(width: 38),
          Expanded(
            child: Center(
              child: Container(
                height: 38,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF242428),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildModeTab(
                      mode: _InputMode.voice,
                      icon: Icons.graphic_eq_rounded,
                      label: 'Voice Mode',
                    ),
                    const SizedBox(width: 4),
                    _buildModeTab(
                      mode: _InputMode.text,
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'Text Mode',
                    ),
                  ],
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              if (_messages.any((m) => m.isUser)) {
                await _saveCurrentChatSession();
              }
              if (!mounted) return;
              Navigator.of(context, rootNavigator: true).push(
                FadePageRoute(
                  page: GeneratedHistoryScreen(
                    onRestoreSession: _loadChatSession,
                  ),
                ),
              );
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.more_horiz_rounded,
                color: Colors.white.withValues(alpha: 0.75),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab({
    required _InputMode mode,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _mode == mode;
    return GestureDetector(
      onTap: () {
        if (_mode == mode) return;
        if (_isListening) _stopListening();
        setState(() {
          _mode = mode;
          if (mode == _InputMode.text) {
            Future.delayed(const Duration(milliseconds: 150), () {
              if (mounted) _scrollToBottom();
            });
          } else {
            _focusNode.unfocus();
          }
        });
        widget.onIsTextModeChanged?.call(mode == _InputMode.text);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF333338) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? const Color(0xFF6C5CE7) : Colors.white54,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= CHAT VIEW =================

  Widget _buildChatView({required bool hasMiniPlayer}) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottomInset > 0;
    // When keyboard is open, push above keyboard + 8; when closed, sit cleanly above custom bottom nav bar (78px) or mini player (134px)
    final defaultBottomPadding = hasMiniPlayer ? 134.0 : 78.0;
    final bottomBarPadding =
        isKeyboardOpen ? bottomInset + 8 : defaultBottomPadding;

    final hasSuggestions = _suggestions.isNotEmpty;
    final hasUserMessages = _messages.any((m) => m.isUser);

    return Stack(
      children: [
        Column(
          key: const ValueKey('generate_chat_view'),
          children: [
            Expanded(
              child: ListView.builder(
                controller: _chatScrollController,
                physics: const BouncingScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.manual,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _buildChatMessageItem(msg);
                },
              ),
            ),
            _buildBottomChatInputBar(bottomInset: bottomBarPadding),
          ],
        ),
        if (!hasSuggestions && hasUserMessages && !isKeyboardOpen)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            right: 16,
            bottom: bottomBarPadding + 64,
            child: GestureDetector(
              onTap: () => _startNewChat(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF282830),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_rounded,
                      color: _accent,
                      size: 17,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'New Chat',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChatMessageItem(_ChatMessage msg) {
    if (msg.isConfirmation) {
      return _buildConfirmationCard(msg);
    }

    if (msg.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14, left: 48),
        child: Align(
          alignment: Alignment.centerRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (msg.chips.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 6,
                    children: msg.chips.map((chip) {
                      final isArtist = chip.type == 'artist';
                      return Container(
                        padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF24242C),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _accent.withValues(alpha: 0.6),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (chip.image.isNotEmpty)
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(isArtist ? 10 : 4),
                                child: CachedImage(
                                  chip.image,
                                  width: 20,
                                  height: 20,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: _accent.withValues(alpha: 0.3),
                                  shape: isArtist
                                      ? BoxShape.circle
                                      : BoxShape.rectangle,
                                  borderRadius: isArtist
                                      ? null
                                      : BorderRadius.circular(4),
                                ),
                                child: Icon(
                                  isArtist
                                      ? Icons.person_rounded
                                      : Icons.music_note_rounded,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                chip.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Poppins',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (chip.subtitle.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Text(
                                isArtist ? '• Artist' : '• ${chip.subtitle}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 10.5,
                                  fontFamily: 'Poppins',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF514AED), Color(0xFF6C5CE7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF514AED).withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  msg.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Poppins',
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // AI Message Bubble (Left aligned)
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, right: 48),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF242428),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomRight: Radius.circular(18),
              bottomLeft: Radius.circular(4),
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                msg.text,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  fontFamily: 'Poppins',
                  height: 1.4,
                ),
              ),
              if (msg.isLoading) ...[
                const SizedBox(height: 10),
                _buildAnimatedDots(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedDots() {
    return AnimatedBuilder(
      animation: _dotsAnim,
      builder: (context, _) {
        final val = _dotsAnim.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final shift = ((val - (i * 0.22)) % 1.0);
            final opacity =
                (shift < 0.5 ? shift * 2 : (1.0 - shift) * 2).clamp(0.2, 1.0);
            return Container(
              margin: const EdgeInsets.only(right: 6),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFF6C5CE7).withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildPlaylistCollageCover({String? imageUrl}) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: CachedImage(
          imageUrl,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
        ),
      );
    }

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E244D), Color(0xFF1E1B2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.22),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.music_note_rounded,
            color: Color(0xFF9D97FF),
            size: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmationCard(_ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, right: 32),
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0xFF382EC5), Color(0xFF1B1B22), Color(0xFF141418)],
            stops: [0.0, 0.45, 1.0],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF382EC5).withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Section: Artwork + Title + Play button
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildPlaylistCollageCover(imageUrl: msg.previewImage),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          msg.previewTitle ?? 'Personalized Mix',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '20 songs · Melo AI',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 11,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Middle Section: Short playlist vibe description
            if (msg.previewDescription != null &&
                msg.previewDescription!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 9, horizontal: 11),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    msg.previewDescription!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      fontFamily: 'Poppins',
                      height: 1.35,
                    ),
                  ),
                ),
              ),

            if (msg.chips.isNotEmpty || msg.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ...msg.chips.map((c) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF514AED)
                                .withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF514AED)
                                  .withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (c.image.isNotEmpty) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    c.image,
                                    width: 14,
                                    height: 14,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.person,
                                        size: 14,
                                        color: Colors.white70),
                                  ),
                                ),
                                const SizedBox(width: 5),
                              ] else ...[
                                Icon(
                                  c.type == 'artist'
                                      ? Icons.person_rounded
                                      : Icons.music_note_rounded,
                                  size: 12,
                                  color: const Color(0xFF9D97FF),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                c.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ],
                          ),
                        )),
                    ...msg.tags
                        .where((t) => !msg.chips.any((c) => c.title == t))
                        .map((t) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                t,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            )),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Action row: Generate button
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: GestureDetector(
                onTap: () {
                  _startGenerate(
                    msg.text,
                    artistIdsOverride: msg.artistIds,
                    trackIdsOverride: msg.trackIds,
                    sourceMode: 'chat',
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF514AED), Color(0xFF6C5CE7)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF514AED).withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Generate Playlist',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (msg.suggestionOptions.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: msg.suggestionOptions.map((opt) {
                    return GestureDetector(
                      onTap: () => _handleUserPrompt(opt),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          opt,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w400,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomChatInputBar({required double bottomInset}) {
    final hasSuggestions = _suggestions.isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 4, 16, bottomInset),
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasSuggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildSuggestionsOverlay(),
            ),
          _buildSelectedChips(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF242428),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: _focused
                    ? _accent.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: 3,
                    minLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontFamily: 'Poppins',
                      fontFamilyFallback: [
                        'Kantumruy Pro',
                        'Battambang',
                        'Noto Sans Khmer',
                        'Khmer OS Siemreap',
                        'Khmer OS',
                        'sans-serif',
                      ],
                      height: 1.35,
                    ),
                    decoration: InputDecoration(
                      hintText: 'What do you want to listen to ?',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.38),
                        fontSize: 13.5,
                        fontFamily: 'Poppins',
                        fontFamilyFallback: const [
                          'Kantumruy Pro',
                          'Battambang',
                          'Noto Sans Khmer',
                          'Khmer OS Siemreap',
                          'Khmer OS',
                          'sans-serif',
                        ],
                        height: 1.35,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (text) {
                      _handleUserPrompt(text);
                    },
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {
                    if (_isChatListening) {
                      _stopListeningForChatInput();
                      return;
                    }
                    final text = _controller.text.trim();
                    if (text.isNotEmpty || _selectedChips.isNotEmpty) {
                      _handleUserPrompt(text);
                    } else {
                      _startListeningForChatInput();
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          _isChatListening ? const Color(0xFFE53935) : _accent,
                    ),
                    child: Icon(
                      _isChatListening
                          ? Icons.stop_rounded
                          : (_controller.text.trim().isNotEmpty
                              ? Icons.send_rounded
                              : Icons.mic_rounded),
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsOverlay() {
    return _buildSuggestions();
  }

  // ================= VOICE MODE VIEW =================

  Widget _buildVoiceModeView({required bool hasMiniPlayer}) {
    final listening = _phase == _Phase.listening;
    final hasText = _liveSpokenText.isNotEmpty;
    final bottomPadding = hasMiniPlayer ? 144.0 : 88.0;

    return Column(
      key: const ValueKey('generate_voice_view'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _buildGreeting(),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(24, 0, 24, bottomPadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMicArea(listening, hasMiniPlayer: hasMiniPlayer),
                  const SizedBox(height: 16),
                  AnimatedOpacity(
                    opacity: (listening || hasText) ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF222226),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: listening
                              ? _accent.withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.1),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (listening) ...[
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF00E676),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: Text(
                                  hasText
                                      ? '"$_liveSpokenText"'
                                      : 'Listening...',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: hasText
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.5),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    fontStyle: FontStyle.italic,
                                    fontFamily: 'Poppins',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (hasText && !listening) ...[
                            () {
                              final violation = _checkSafetyPolicy(_liveSpokenText);
                              if (violation != null) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF5252)
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFFFF5252)
                                              .withValues(alpha: 0.35),
                                          width: 1,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(Icons.shield_outlined,
                                                  color: Color(0xFFFF5252),
                                                  size: 16),
                                              const SizedBox(width: 6),
                                              Text(
                                                violation['title'] ??
                                                    'Safety Guideline',
                                                style: const TextStyle(
                                                  color: Color(0xFFFF5252),
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                  fontFamily: 'Poppins',
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            violation['reason'] ??
                                                'This request cannot be generated.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.8),
                                              fontSize: 11.5,
                                              fontFamily: 'Poppins',
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _liveSpokenText = '';
                                          _controller.clear();
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8.5),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: 0.15),
                                            width: 1,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.refresh_rounded,
                                                color: Colors.white, size: 14),
                                            SizedBox(width: 6),
                                            Text(
                                              'Try Another Request',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600,
                                                fontFamily: 'Poppins',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 10),
                                  Text(
                                    _derivePreviewDescription(_liveSpokenText),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.75),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      fontFamily: 'Poppins',
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      GestureDetector(
                                        onTap: () {
                                          if (_liveSpokenText.trim().isNotEmpty) {
                                            _startGenerate(
                                              _liveSpokenText.trim(),
                                              sourceMode: 'voice',
                                            );
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 8.5),
                                          decoration: BoxDecoration(
                                            color: _accent,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            boxShadow: [
                                              BoxShadow(
                                                color: _accent.withValues(alpha: 0.4),
                                                blurRadius: 10,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Generate Playlist',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                  fontFamily: 'Poppins',
                                                ),
                                              ),
                                              SizedBox(width: 6),
                                              Icon(Icons.auto_awesome_rounded,
                                                  color: Colors.white, size: 14),
                                            ],
                                          ),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () {
                                          if (_liveSpokenText.trim().isNotEmpty) {
                                            final prompt = _liveSpokenText.trim();
                                            if (_isListening) _stopListening();
                                            setState(() {
                                              _mode = _InputMode.text;
                                              _liveSpokenText = '';
                                              _controller.text = prompt;
                                              _controller.selection =
                                                  TextSelection.collapsed(
                                                      offset: prompt.length);
                                            });
                                            widget.onIsTextModeChanged?.call(true);
                                            _focusNode.requestFocus();
                                            _scrollToBottom();
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 8.5),
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.08),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.15),
                                              width: 1,
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Chat & Refine',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w500,
                                                  fontFamily: 'Poppins',
                                                ),
                                              ),
                                              SizedBox(width: 5),
                                              Icon(
                                                  Icons
                                                      .chat_bubble_outline_rounded,
                                                  color: Colors.white70,
                                                  size: 13),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            }(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGreeting() {
    final p = ProfileService();
    final user = Supabase.instance.client.auth.currentUser;
    final name = _displayName.isNotEmpty
        ? _displayName
        : (p.displayName.isNotEmpty
            ? p.displayName
            : (p.username.isNotEmpty
                ? p.username
                : (user?.userMetadata?['display_name'] ??
                    user?.userMetadata?['full_name'] ??
                    user?.userMetadata?['name'] ??
                    'Music Lover')));

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$_greeting,',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 2),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  Color(0xFF514AED),
                  Color(0xFFFFFFFF),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ).createShader(bounds),
              child: Text(
                name.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMicArea(bool listening, {bool hasMiniPlayer = false}) {
    final areaSize = hasMiniPlayer ? 270.0 : 310.0;
    final btnSize = hasMiniPlayer ? 180.0 : 210.0;
    final sizeFactor = hasMiniPlayer ? 0.85 : 1.0;

    return Column(
      key: const ValueKey('generate_mic_area'),
      children: [
        SizedBox(
          width: areaSize,
          height: areaSize,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  for (var i = 0; i < 3; i++)
                    _buildRipple(
                      base: (i / 3) + _pulse.value,
                      listening: listening,
                      sizeFactor: sizeFactor,
                    ),
                  GestureDetector(
                    onTap: _startListening,
                    child: Container(
                      width: btnSize,
                      height: btnSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _accent,
                            Color(0xFF8B5CF6),
                            Color(0xFF6D28D9)
                          ],
                        ),
                        boxShadow: listening
                            ? [
                                BoxShadow(
                                  color: _accent.withValues(alpha: 0.7),
                                  blurRadius: 50,
                                  spreadRadius: 10,
                                ),
                                BoxShadow(
                                  color: const Color(0xFF8B5CF6)
                                      .withValues(alpha: 0.5),
                                  blurRadius: 30,
                                  spreadRadius: 4,
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: _accent.withValues(alpha: 0.35),
                                  blurRadius: 30,
                                  spreadRadius: 4,
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                      ),
                      child: Center(
                        child: listening
                            ? const Icon(
                                Icons.stop_rounded,
                                color: Colors.white,
                                size: 68,
                              )
                            : _buildSoundWaveIcon(btnSize: btnSize),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 2),
        Text(
          listening ? 'Listening... tap when done' : 'Push to talk',
          style: TextStyle(
            color: listening ? _accent : Colors.white.withValues(alpha: 0.85),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          listening
              ? 'Say your mood, favorite artist, or genre'
              : 'Tap to speak your mood or music request',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 12,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 12),
        _buildKhmerToggle(),
      ],
    );
  }

  Widget _buildSoundWaveIcon({required double btnSize}) {
    final waveHeight =
        btnSize * 0.38; // Clean, balanced size (~79px on 208px bubble)
    // 7-bar wave profile with clean center emphasis
    final heights = [0.38, 0.65, 0.90, 1.0, 0.90, 0.65, 0.38];

    return SizedBox(
      height: waveHeight,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          // Exactly 1 full periodic revolution so t=0 and t=2*pi meet perfectly with 0 snap
          final t = _pulse.value * 2 * math.pi;
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(heights.length, (i) {
              final baseH = heights[i];
              // Integer multipliers (1x and 2x) guarantee perfectly seamless infinite looping
              final primaryWave = math.sin(t * 1.0 + (i * 0.85));
              final secondaryWave = math.cos(t * 2.0 - (i * 0.45)) * 0.18;
              final wave =
                  (0.5 + 0.5 * primaryWave + secondaryWave).clamp(0.0, 1.0);

              final currentHeight =
                  (waveHeight * (baseH * 0.45 + wave * 0.55 * baseH))
                      .clamp(waveHeight * 0.22, waveHeight);

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2.8),
                width: 5.5,
                height: currentHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: _accent.withValues(alpha: 0.3),
                      blurRadius: 14,
                      spreadRadius: 1.5,
                    ),
                  ],
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildKhmerToggle() {
    return GestureDetector(
      onTap: () {
        if (_isListening) return;
        setState(() => _useKhmer = !_useKhmer);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: _useKhmer
              ? _accent.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _useKhmer ? _accent : Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language_rounded,
              size: 14,
              color: _useKhmer ? _accent : Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 6),
            Text(
              _useKhmer ? 'Khmer (ភាសាខ្មែរ)' : 'Khmer voice',
              style: TextStyle(
                color:
                    _useKhmer ? _accent : Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              _useKhmer
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 14,
              color: _useKhmer ? _accent : Colors.white.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRipple(
      {required double base,
      required bool listening,
      double sizeFactor = 1.0}) {
    final t = base % 1.0;
    final size =
        (listening ? (140.0 + t * 180.0) : (120.0 + t * 200.0)) * sizeFactor;
    final opacity = (1.0 - t) * (listening ? 0.9 : 0.65);
    final fillOpacity = (1.0 - t) * (listening ? 0.5 : 0.3);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            _accent.withValues(alpha: fillOpacity),
            _accent.withValues(alpha: fillOpacity * 0.3),
            _accent.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
        border: Border.all(
          color: _accent.withValues(alpha: opacity),
          width: 3,
        ),
      ),
    );
  }

  Widget _buildSelectedChips() {
    if (_selectedChips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _selectedChips.map((chip) {
            final isArtist = chip.type == 'artist';
            return Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2B3E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _accent.withValues(alpha: 0.7),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (chip.image.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedImage(
                        chip.image,
                        width: 20,
                        height: 20,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isArtist
                            ? Icons.person_rounded
                            : Icons.music_note_rounded,
                        color: _accent,
                        size: 12,
                      ),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    chip.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  if (chip.subtitle.isNotEmpty && !isArtist) ...[
                    const SizedBox(width: 4),
                    Text(
                      '• ${chip.subtitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10.5,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _removeChip(chip),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 11,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    final rawList =
        _suggestions.isNotEmpty ? _suggestions : _defaultSuggestions;
    if (rawList.isEmpty) return const SizedBox.shrink();

    bool isAllowed(SearchResult s) {
      final a = s.artist.toLowerCase().trim();
      final t = s.title.toLowerCase().trim();
      if (a == 'sombr' || a.contains('sombr') || a.contains('stella lefty')) {
        return false;
      }
      if (s.type == 'artist' &&
          (t == 'sombr' || t.contains('sombr') || t.contains('stella lefty'))) {
        return false;
      }
      if (s.id.isEmpty) return false;

      // Exclude items already added as selected chips
      if (_selectedChips.any((c) =>
          c.id == s.id ||
          (c.title.toLowerCase().trim() == s.title.toLowerCase().trim() &&
              c.type == s.type))) {
        return false;
      }

      return true;
    }

    final list = rawList.where(isAllowed).toList();
    if (list.isEmpty) return const SizedBox.shrink();

    final artists = list.where((s) => s.type == 'artist').toList();
    final songs = list.where((s) => s.type == 'song').toList();

    if (artists.isEmpty && songs.isEmpty) return const SizedBox.shrink();

    final isDefault = _suggestions.isEmpty && _controller.text.trim().isEmpty;
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Container(
      constraints: BoxConstraints(
        maxHeight: isKeyboardOpen ? 200 : 260,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, 10),
            spreadRadius: 2,
          ),
        ],
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (artists.isNotEmpty)
              _SuggestionSection(
                label: isDefault ? 'Recommended Artist' : 'Artist',
                items: artists,
                visibleCount: artists.length >= 2 ? 2 : 1,
                onTap: _onSuggestionTap,
              ),
            if (songs.isNotEmpty)
              _SuggestionSection(
                label: isDefault ? 'Trending Now' : 'Songs',
                items: songs,
                visibleCount: isKeyboardOpen || artists.isNotEmpty
                    ? (songs.length >= 2 ? 2 : 1)
                    : (songs.length >= 3 ? 3 : (songs.length >= 2 ? 2 : 1)),
                onTap: _onSuggestionTap,
              ),
          ],
        ),
      ),
    );
  }

  // ================= BUILDING VIEW =================

  Widget _buildBuildingView() {
    return AnimatedBuilder(
      animation: _buildAnim,
      builder: (context, _) {
        final t = _buildAnim.value;
        final stage = (t * 4).floor().clamp(0, 3);

        return Column(
          key: const ValueKey('building'),
          children: [
            Expanded(
              flex: 70,
              child: Align(
                alignment: Alignment.topCenter,
                child: Transform.translate(
                  offset: const Offset(0, 160),
                  child: ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: const [
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.6, 0.8, 1.0],
                      ).createShader(bounds);
                    },
                    blendMode: BlendMode.dstIn,
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.65,
                      child: _buildPhoneMockup(t),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 30,
              child: Padding(
                padding: const EdgeInsets.only(left: 24, right: 24, bottom: 10),
                child: Column(
                  children: [
                    _buildStageDots(stage),
                    const SizedBox(height: 20),
                    _buildStageText(stage),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Text(
                        'We only use your listening habits to personalize this playlist. '
                        'It is never shared.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 10,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStageDots(int stage) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final active = i == stage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: active ? 26 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? _accent : Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _buildPhoneMockup(double t) {
    final phoneWidth = MediaQuery.of(context).size.width * 0.65;
    final headerT = ((t - 0.0) / 0.22).clamp(0.0, 1.0);
    final actionsT = ((t - 0.22) / 0.18).clamp(0.0, 1.0);

    return SizedBox(
      width: phoneWidth,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Image.asset(
            'asset/Generate_assets/Pill=False, Color=Blue.png',
            width: phoneWidth,
            fit: BoxFit.fitWidth,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: phoneWidth,
                height: phoneWidth * 1.85,
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1F1F),
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12), width: 1.5),
                ),
              );
            },
          ),
          Padding(
            padding: EdgeInsets.only(top: phoneWidth * 0.1),
            child: SizedBox(
              width: phoneWidth * 0.88,
              height: phoneWidth * 1.5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _fadeSlide(headerT, _buildPhoneHeader(phoneWidth)),
                    _fadeSlide(actionsT, _buildPhoneActions(phoneWidth)),
                    Expanded(child: _buildPhoneSongs(t)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneHeader(double phoneWidth) {
    return Container(
      height: 92,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_accent, Color(0xFF7C4DFF)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Generated from your vibe',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 10,
              fontWeight: FontWeight.w500,
              fontFamily: 'Poppins',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Container(
            width: phoneWidth * 0.35,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(height: 3),
          Container(
            width: 34,
            height: 7,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneActions(double phoneWidth) {
    return Container(
      height: 32,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add,
                    color: Colors.white.withValues(alpha: 0.7), size: 10),
                const SizedBox(width: 3),
                Text(
                  'add to library',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 7,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 14,
            color: Colors.white.withValues(alpha: 0.15),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.ios_share_rounded,
                    color: Colors.white.withValues(alpha: 0.7), size: 10),
                const SizedBox(width: 3),
                Text(
                  'Share Album',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 7,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneSongs(double t) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _sampleSongs.length,
      itemBuilder: (context, i) {
        final rowStart = (0.15 + i * 0.09).clamp(0.0, 1.0);
        final rowEnd = (rowStart + 0.50).clamp(0.0, 1.0);
        final rowT = t < rowStart
            ? 0.0
            : ((t - rowStart) / (rowEnd - rowStart)).clamp(0.0, 1.0);
        return _bounceSlide(rowT, _buildSampleRow(i));
      },
    );
  }

  Widget _bounceSlide(double t, Widget child) {
    if (t <= 0) return const SizedBox.shrink();
    final clamped = t.clamp(0.0, 1.0);
    final bounceT = Curves.easeOutBack.transform(clamped);
    return Opacity(
      opacity: (clamped * 2).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, (1 - bounceT) * 8),
        child: child,
      ),
    );
  }

  Widget _buildSampleRow(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  width: double.infinity * 0.6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageText(int stage) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Column(
        key: ValueKey(stage),
        children: [
          Text(
            _stageTitles[stage],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _stageSubtitles[stage],
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fadeSlide(double t, Widget child) {
    if (t <= 0) return const SizedBox.shrink();
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, (1 - t.clamp(0.0, 1.0)) * 14),
        child: child,
      ),
    );
  }
}

class _SuggestionSection extends StatefulWidget {
  const _SuggestionSection({
    required this.label,
    required this.items,
    required this.visibleCount,
    required this.onTap,
  });

  final String label;
  final List<SearchResult> items;
  final int visibleCount;
  final void Function(SearchResult) onTap;

  @override
  State<_SuggestionSection> createState() => _SuggestionSectionState();
}

class _SuggestionSectionState extends State<_SuggestionSection> {
  static const double _itemHeight = 44.0;
  late final ScrollController _controller = ScrollController();

  bool get _scrollable => widget.items.length > widget.visibleCount;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(widget.label),
        SizedBox(
          height: _itemHeight * widget.visibleCount,
          child: Stack(
            children: [
              Positioned.fill(
                child: ListView.builder(
                  controller: _controller,
                  padding: const EdgeInsets.only(bottom: 2),
                  itemCount: widget.items.length,
                  itemBuilder: (context, i) => _buildTile(widget.items[i]),
                ),
              ),
              if (_scrollable)
                Positioned(
                  right: 3,
                  top: 0,
                  bottom: 0,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final pos = _controller.hasClients &&
                              _controller.position.hasContentDimensions
                          ? _controller.position
                          : null;
                      final max = pos?.maxScrollExtent ?? 0.0;
                      final offset = pos?.pixels ?? 0.0;
                      final fraction =
                          max > 0 ? (offset / max).clamp(0.0, 1.0) : 0.0;
                      return Align(
                        alignment: Alignment(0, -1 + fraction * 2),
                        child: Container(
                          width: 2,
                          height: 18,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          fontFamily: 'Poppins',
        ),
      ),
    );
  }

  Widget _buildTile(SearchResult item) {
    final image = item.type == 'artist' ? item.artistImage : item.image;
    return InkWell(
      onTap: () => widget.onTap(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4.5),
        child: Row(
          children: [
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(item.type == 'artist' ? 16 : 6),
              child: image.isNotEmpty
                  ? CachedImage(
                      image,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 32,
                      height: 32,
                      color: const Color(0xFF2A2A2A),
                      child: Icon(
                        item.type == 'artist'
                            ? Icons.person_rounded
                            : Icons.music_note_rounded,
                        color: Colors.white38,
                        size: 16,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Poppins',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    item.type == 'artist' ? 'Artist' : item.artist,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 10.5,
                      fontFamily: 'Poppins',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomFadePageRoute<T> extends PageRouteBuilder<T> {
  _ZoomFadePageRoute({required Widget page})
      : super(
          transitionDuration: const Duration(milliseconds: 650),
          reverseTransitionDuration: const Duration(milliseconds: 350),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, animation, __, child) {
            final curve =
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curve,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.72, end: 1.0).animate(curve),
                child: child,
              ),
            );
          },
        );
}
