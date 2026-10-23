import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'artist_follow_service.dart';
import 'artist_service.dart';
import 'gemini_service.dart';
import 'groq_service.dart';
import 'listening_history_service.dart';
import 'search_service.dart';

class HeardHistoryFilter {
  final Set<String> trackIds = {};
  final Set<String> titleArtistKeys = {};
  final Set<String> cleanTitles = {};
  final Map<String, Set<String>> titleToArtists = {};
  final Map<String, int> artistCounts = {};

  static String cleanTitle(String title) {
    final cleaned = title
        .toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
        .replaceAll(RegExp(r'[-–—].*?$'), '')
        .replaceAll(RegExp(r'[^a-z0-9\s\u0080-\uffff]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isNotEmpty ? cleaned : title.toLowerCase().trim();
  }

  static String cleanArtist(String artist) {
    final cleaned = artist
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s\u0080-\uffff]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isNotEmpty ? cleaned : artist.toLowerCase().trim();
  }

  void add(String title, String artist, {String? trackId}) {
    final tId = trackId?.trim() ?? '';
    if (tId.isNotEmpty && tId != '0' && tId != 'null') {
      trackIds.add(tId);
    }
    final cTitle = cleanTitle(title);
    final cArtist = cleanArtist(artist);
    if (cTitle.isNotEmpty) {
      cleanTitles.add(cTitle);
      if (cArtist.isNotEmpty) {
        titleArtistKeys.add('$cTitle|$cArtist');
        titleToArtists.putIfAbsent(cTitle, () => {}).add(cArtist);
      }
    }
    final rawArtist = artist.trim();
    if (rawArtist.isNotEmpty) {
      artistCounts[rawArtist] = (artistCounts[rawArtist] ?? 0) + 1;
    }
  }

  List<String> get topHistoryArtists {
    final sorted = artistCounts.keys.toList()
      ..sort((a, b) => (artistCounts[b] ?? 0).compareTo(artistCounts[a] ?? 0));
    return sorted;
  }

  bool isHeard(
      {required String title, required String artist, String? trackId}) {
    final tId = trackId?.trim() ?? '';
    if (tId.isNotEmpty && trackIds.contains(tId)) return true;

    final cTitle = cleanTitle(title);
    final cArtist = cleanArtist(artist);
    if (cTitle.isEmpty) return false;

    // 1. Direct title + artist match
    if (cArtist.isNotEmpty && titleArtistKeys.contains('$cTitle|$cArtist')) {
      return true;
    }

    // 2. Title match: check known artists or distinctive title
    if (cleanTitles.contains(cTitle)) {
      if (cArtist.isEmpty) return true;
      final knownArtists = titleToArtists[cTitle];
      if (knownArtists == null || knownArtists.isEmpty) return true;
      if (knownArtists.any((a) => a.contains(cArtist) || cArtist.contains(a))) {
        return true;
      }
      if (cTitle.length >= 6) return true;
    }

    // 3. Substring match on same artist (e.g. "Song Title" vs "Song Title - Radio Edit")
    if (cArtist.isNotEmpty) {
      for (final ht in cleanTitles) {
        if (ht.length >= 4 && (cTitle.contains(ht) || ht.contains(cTitle))) {
          final knownArtists = titleToArtists[ht];
          if (knownArtists != null &&
              knownArtists
                  .any((a) => a.contains(cArtist) || cArtist.contains(a))) {
            return true;
          }
        }
      }
    }

    return false;
  }
}

class GeneratedPlaylist {
  final bool success;
  final String mood;
  final String title;
  final String description;
  final int size;
  final String source;
  final String? error;
  final List<Map<String, dynamic>> songs;

  GeneratedPlaylist({
    required this.success,
    required this.mood,
    this.title = '',
    this.description = '',
    required this.size,
    required this.source,
    this.error,
    required this.songs,
  });

  factory GeneratedPlaylist.fromJson(Map<String, dynamic> json) {
    return GeneratedPlaylist(
      success: json['success'] == true,
      mood: json['mood']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      size: json['size'] is int ? json['size'] as int : 0,
      source: json['source']?.toString() ?? 'ai',
      error: json['error']?.toString(),
      songs: (json['songs'] as List<dynamic>? ?? [])
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList(),
    );
  }
}

enum EmotionalValence {
  happy,
  sad,
  neutral,
}

class GenerateService {
  static const _deezerApi = 'https://api.deezer.com';

  static EmotionalValence detectEmotionalValence(
      String moodPrompt, PromptIntent? intent) {
    final combined =
        '${moodPrompt.toLowerCase()} ${intent?.summary.toLowerCase() ?? ''} ${intent?.moodDimension.toLowerCase() ?? ''}';

    final hasSadKeywords = RegExp(
      r'\b(sad|sadness|heartbreak|heartbroken|broken\s*heart|crying|cry|depress\w*|melanchol\w*|tearful|tears|grief|sorrow|mourn\w*|unhappy|lonely|loneliness|painful|grieving|downhearted|gloomy|breakup)\b',
      caseSensitive: false,
    ).hasMatch(combined);

    final hasHappyKeywords = RegExp(
      r'\b(happy|happiness|feel\s*good|good\s*mood|joyful|joy|cheerful|cheer\s*up|uplifting|positive|bright|sunshine|celebrat\w*|smile|smiling|ecstatic|hype|party|good\s*vibes)\b',
      caseSensitive: false,
    ).hasMatch(combined);

    if (hasSadKeywords && !hasHappyKeywords) return EmotionalValence.sad;
    if (hasHappyKeywords && !hasSadKeywords) return EmotionalValence.happy;
    return EmotionalValence.neutral;
  }

  static bool isCoverOrTributeTrack({
    required String artist,
    required String title,
    bool allowEnsembleOrCover = false,
    bool allowLive = false,
    bool allowInstrumental = false,
    bool allowRemix = false,
  }) {
    if (allowEnsembleOrCover) return false;
    final aLower = artist.toLowerCase().trim();
    final tLower = title.toLowerCase().trim();

    // 1. Unwanted cover / tribute / karaoke / sound-alike artists
    final badArtistRegex = RegExp(
      r'\b(ensemble|tribute(\s*band)?|karaoke|cover\s*band|cover\s*version|covers?|all\s*stars?|hit\s*crew|soundtrack\s*orchestra|music\s*box|lullaby|orchestral\s*version|the\s*singers|sing\s*along|karaoke\s*all\s*stars|kids\s*music|tribute\s*to)\b',
      caseSensitive: false,
    );
    if (badArtistRegex.hasMatch(aLower)) return true;

    // 2. Cover / Tribute / Karaoke title markers
    final badTitleRegex = RegExp(
      r'\b(karaoke(\s*version)?|tribute(\s*version)?|cover(\s*version)?|in\s*the\s*style\s*of|originally\s*performed\s*by|originally\s*by|made\s*famous\s*by|backing\s*track|piano\s*lullaby|music\s*box(\s*version)?|sing\s*along(\s*version)?|acoustic\s*cover|guitar\s*cover|piano\s*cover|violin\s*cover|drum\s*cover|remake|sound-?alike)\b',
      caseSensitive: false,
    );
    if (badTitleRegex.hasMatch(tLower)) return true;

    // 3. Concert / Live performances (unless user explicitly allowed live)
    if (!allowLive) {
      final liveRegex = RegExp(
        r'(\([^\)]*\blive\b[^\)]*\)|\[[^\]]*\blive\b[^\]]*\]|[-–—]\s*live\b|\b(live\s+(at|from|in|version|performance|tour|session|edit|acoustic|recording)|in\s+concert|concert\s+version|live\s+recording|recorded\s+live|en\s+vivo|tour\s+version)\b)',
        caseSensitive: false,
      );
      if (liveRegex.hasMatch(tLower)) return true;
    }

    // 4. Instrumental / No vocals (unless user explicitly allowed instrumental)
    if (!allowInstrumental) {
      final instrumentalRegex = RegExp(
        r'\b(instrumental(\s*version)?|karaoke\s*instrumental|minus\s*one|no\s*vocals?|backing\s*track|orchestral\s*version|piano\s*version|string\s*quartet|music\s*box)\b',
        caseSensitive: false,
      );
      if (instrumentalRegex.hasMatch(tLower)) return true;
    }

    // 5. Remix / Sped up / Slowed (unless user explicitly allowed remix)
    if (!allowRemix) {
      final remixRegex = RegExp(
        r'\b(remix|rework|rewerk|club\s*mix|dub\s*mix|extended\s*mix|speed\s*up|sped\s*up|nightcore|slowed(\s*and\s*reverb)?)\b',
        caseSensitive: false,
      );
      if (remixRegex.hasMatch(tLower)) return true;
    }

    // 6. Title with (Original Artist) where track artist is an amateur cover uploader
    final parentheticalMatches =
        RegExp(r'[\(\[]([^\)\]]+)[\)\]]').allMatches(tLower);
    for (final m in parentheticalMatches) {
      final inside = m.group(1)?.trim() ?? '';
      if (inside.isEmpty) continue;
      // Skip legitimate features, soundtracks, or common metadata
      if (RegExp(
        r'\b(feat|ft|with|prod|soundtrack|ost|from|version|theme|score|radio|original|bonus|mono|stereo|deluxe|remaster)\b',
        caseSensitive: false,
      ).hasMatch(inside)) {
        continue;
      }
      // If the parenthetical is a person/artist name (multi-word, >= 6 chars) and doesn't match track artist
      if (inside.contains(' ') &&
          inside.length >= 6 &&
          !aLower.contains(inside) &&
          !inside.contains(aLower)) {
        return true;
      }
    }

    return false;
  }

  static bool isTrackValenceMismatched({
    required String title,
    required String artist,
    required EmotionalValence requestedValence,
    bool allowAcoustic = false,
  }) {
    if (requestedValence == EmotionalValence.neutral) return false;

    final tLower = title.toLowerCase().trim();

    if (requestedValence == EmotionalValence.happy) {
      // 1. Sad / heartbroken / grief title keywords and specific well-known sad hits
      final sadTitleRegex = RegExp(
        r'\b(sad|sadness|lonel(y|iness)|tears?|crying|cry|heartbreak(ing)?|heartbroken|broken\s*heart|'
        r'scared\s*to\s*be\s*lonely|save\s*your\s*tears|sad\s*girls?|die\s*with\s*a\s*smile|'
        r'when\s*i\s*was\s*your\s*man|someone\s*like\s*you|someone\s*you\s*loved|glimpse\s*of\s*us|'
        r'drivers?\s*license|traitor|funeral|grief|pain(ful)?|hurts?|hurting|'
        r'depress(ed|ion|ing)|alone|hopeless|suicid\w*|mourn(ing)?|unhappy|miserable|'
        r'miss\s*you|leaving\s*me|left\s*me|say\s*something|skinny\s*love|drown(ing)?|'
        r'another\s*love|all\s*too\s*well|the\s*scientist|fix\s*you|hate\s*myself|'
        r'lose\s*you\s*to\s*love\s*me|call\s*out\s*my\s*name|dancing\s*with\s*your\s*ghost|'
        r'before\s*you\s*go|lovely|when\s*the\s*party.*over|bury\s*a\s*friend)\b',
        caseSensitive: false,
      );
      if (sadTitleRegex.hasMatch(tLower)) return true;

      // 2. Slow melancholy acoustic/stripped versions unless user explicitly asked for acoustic
      if (!allowAcoustic) {
        final slowMelancholyRegex = RegExp(
          r'\b(acoustic|stripped|slowed(\s*and\s*reverb)?|sad\s*version|orchestral\s*ballad)\b',
          caseSensitive: false,
        );
        if (slowMelancholyRegex.hasMatch(tLower)) return true;
      }
    }

    if (requestedValence == EmotionalValence.sad) {
      final happyPartyRegex = RegExp(
        r"\b(happy|happiness|celebrat\w*|party|dance\s*the\s*night|can'?t\s*stop\s*the\s*feeling|"
        r"uptown\s*funk|good\s*time|cheer\w*|joy\w*|euphori\w*|dynamite|holiday|congratulat\w*|"
        r"i\s*gotta\s*feeling|24k\s*magic|treasures?|levitating|sunshine|good\s*vibrations|"
        r"shake\s*it\s*off|shut\s*up\s*and\s*dance|best\s*day\s*of\s*my\s*life|firework)\b",
        caseSensitive: false,
      );
      if (happyPartyRegex.hasMatch(tLower)) return true;
    }

    return false;
  }

  static bool isExclusiveArtistsRequest(String prompt, int explicitCount) {
    if (explicitCount == 0) return false;
    final lower = prompt.toLowerCase().trim();

    // 1. Explicit exclusivity keywords: "only", "just", "exclusively", "discography", "all songs by", "100%", "pure", "solely", "all X artists only"
    final hasExclusivityKeywords = RegExp(
      r'\b(only|just|exclusively?|discography|all\s*songs\s*by|all\s*tracks\s*by|100%|nothing\s*but|pure|solely|entirely|all\s*\d+\s*artists?\s*only|all\s*of\s*them\s*only|តែ|សុទ្ធ)\b',
      caseSensitive: false,
    ).hasMatch(lower);
    if (hasExclusivityKeywords) return true;

    // 2. Check for refinement / adding keywords ("add extra artist", "add artist", "put in", "with", "include", "more by", "ថែម", "ដាក់")
    final hasRefineOrAddKeywords = RegExp(
      r'\b(add|add\s*extra|put\s*in|more\s*by|include|feature|with|alongside|some\s+more|ថែម|ដាក់)\b',
      caseSensitive: false,
    ).hasMatch(lower);
    if (hasRefineOrAddKeywords) return false;

    // 3. Check if there is an active mood, activity, or environment keyword
    final hasMoodOrActivity = RegExp(
      r'\b(happy|sad|chill|relax|study|gym|workout|party|energetic|hype|morning|night|drive|driving|coding|cooking|sunny|rainy|peaceful|sleep|vibe|mood|lo-?fi|upbeat|crying|depressed|heartbreak)\b',
      caseSensitive: false,
    ).hasMatch(lower);
    if (hasMoodOrActivity) return false;

    // 4. If prompt does not specify a mood/theme and just requested artists, treat as exclusive
    return true;
  }

  static Future<HeardHistoryFilter> _loadHeardHistory() async {
    final filter = HeardHistoryFilter();

    // 1. Memory / Disk cache from ListeningHistoryService (instant, has tracks played seconds ago!)
    try {
      final local = await ListeningHistoryService.getHistory();
      for (final item in local) {
        final title = (item['title'] ?? '').toString();
        final artist = (item['artist'] ?? '').toString();
        final trackId = (item['trackId'] ?? item['track_id'] ?? '').toString();
        filter.add(title, artist, trackId: trackId);
      }
    } catch (_) {}

    for (final item in ListeningHistoryService.cachedHistory) {
      final title = (item['title'] ?? '').toString();
      final artist = (item['artist'] ?? '').toString();
      final trackId = (item['trackId'] ?? item['track_id'] ?? '').toString();
      filter.add(title, artist, trackId: trackId);
    }

    // 2. Remote Supabase listening_history table
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final rows = await Supabase.instance.client
            .from('listening_history')
            .select('title, artist, track_id')
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(300)
            .timeout(const Duration(seconds: 4));

        for (final r in rows) {
          final title = (r['title'] ?? '').toString();
          final artist = (r['artist'] ?? '').toString();
          final trackId = (r['track_id'] ?? '').toString();
          filter.add(title, artist, trackId: trackId);
        }
      }
    } catch (_) {}

    print(
        '[Generate] Loaded ${filter.cleanTitles.length} heard songs into filter.');
    return filter;
  }

  static int detectSongCountFromMood(String mood, int defaultSize) {
    final lower = mood.toLowerCase();

    // Khmer numerals conversion
    var normalized = lower
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

    // 1. Direct song / track count check (e.g. "15 songs", "give me 15 tracks", "10 songs i haven't listened to", "15 បទ", "10 ចម្រៀង")
    final countMatch = RegExp(
      r'(?:give\s*me|generate|find|make\s*(?:me)?\s*(?:a\s*playlist\s*of)?|around|about|only)?\s*(\d+)\s*(?:songs?|tracks?|musics?|pieces?|បទ|ចម្រៀង)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (countMatch != null) {
      final count = int.tryParse(countMatch.group(1) ?? '');
      if (count != null && count >= 1) {
        return count.clamp(3, 50);
      }
    }

    final countAfterMatch = RegExp(
      r'(?:songs?|tracks?|musics?|បទ|ចម្រៀង)\s*(?:ចំនួន|ប្រមាណ|about|around)?\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (countAfterMatch != null) {
      final count = int.tryParse(countAfterMatch.group(1) ?? '');
      if (count != null && count >= 1) {
        return count.clamp(3, 50);
      }
    }

    double totalMinutes = 0;

    // Check for "hours" / "ម៉ោង" (e.g., "2 hours", "2h", "២ ម៉ោង", "1 ម៉ោងកន្លះ", "half hour", "កន្លះម៉ោង")
    if (normalized.contains('កន្លះម៉ោង') ||
        normalized.contains('half hour') ||
        normalized.contains('half an hour')) {
      totalMinutes += 30;
    }

    final hourMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h|ម៉ោង)')
        .firstMatch(normalized);
    if (hourMatch != null) {
      final h = double.tryParse(hourMatch.group(1) ?? '') ?? 0;
      totalMinutes += h * 60;
    }

    // Check for "minutes" / "នាទី" (e.g., "45 mins", "30 minutes", "៣០ នាទី")
    final minMatch =
        RegExp(r'(\d+)\s*(?:minutes?|mins?|m|នាទី)').firstMatch(normalized);
    if (minMatch != null) {
      final m = double.tryParse(minMatch.group(1) ?? '') ?? 0;
      totalMinutes += m;
    }

    // If duration was specified in prompt, calculate track count (~3.2 minutes per song)
    if (totalMinutes > 0) {
      // Cap at 3 hours (180 minutes) to keep generation snappy & within streaming limits
      final clampedMinutes = totalMinutes.clamp(10, 180);
      final count = (clampedMinutes / 3.2).round();
      return count.clamp(5, 55); // Min 5 songs, Max 55 songs (~3 hours)
    }

    // Check if user asked for "all" / "every" songs from a franchise, anime, or series
    // (Ensure word boundaries so words like "ballad", "fall", or "of all time" don't trigger 35 songs)
    final bool asksComprehensive = RegExp(
      r'\b(all\s+songs|all\s+tracks|every\s+song|every\s+track|all\s+openings?|complete\s+(?:soundtrack|discography|catalog|ost)|discography)\b|\b(ទាំងអស់|ទាំងស្រុង)\b',
      caseSensitive: false,
    ).hasMatch(normalized);
    if (asksComprehensive) {
      return 35; // Deliver comprehensive franchise/artist catalog
    }

    return defaultSize;
  }

  static Future<GeneratedPlaylist> generate(
    String mood, {
    int? size,
    List<String>? artistIds,
    List<String>? trackIds,
    void Function(int stage)? onStageChanged,
  }) async {
    final requestedSize = size ?? detectSongCountFromMood(mood, 20);

    try {
      onStageChanged
          ?.call(0); // Stage 0: Understanding your mood / analyzing taste
      await Future.delayed(const Duration(milliseconds: 350));

      // Handle "Most Listened / On Repeat" request (e.g. "make me a playlist with my most listened to songs", "my top played", "on repeat")
      final isMostListened = RegExp(
        r'(most\s*listen|top\s*listen|listen\s*(?:to\s*)?the\s*most|most\s*played|top\s*played|most\s*heard|heavy\s*rotation|on\s*repeat|my\s*top\s*songs|my\s*favorite\s*songs|songs\s*i\s*love\s*most|បទដែលខ្ញុំស្តាប់ច្រើន|ស្តាប់ច្រើនជាងគេ)',
        caseSensitive: false,
      ).hasMatch(mood);

      if (isMostListened) {
        final res = await _generateMostListenedPlaylist(
          requestedSize,
          mood,
          onStageChanged: onStageChanged,
        );
        return _sanitizePlaylist(res);
      }

      // Handle Direct Artist Discovery ONLY when an actual artist is named (e.g. "songs I haven't listened to from wave to earth", "unheard tracks by Radiohead")
      final isDiscovery = RegExp(
        r'(haven.?t\s*listen|never\s*listen|never\s*heard|haven.?t\s*heard|unheard|not\s*in\s*my\s*history|discover|new\s*to\s*me|មិន\s*ដែល\s*ស្តាប់)',
        caseSensitive: false,
      ).hasMatch(mood);

      const nonArtistWords = {
        'songs',
        'song',
        'tracks',
        'track',
        'music',
        'stuff',
        'pieces',
        'piece',
        'hits',
        'tunes',
        'tune',
        'playlist',
        'playlists',
        'album',
        'albums',
        'my',
        'this',
        'these',
        'those',
        'them',
        'all',
        'any',
        'some',
        'new',
        'old',
        'recent',
        'random',
        'unheard',
        'listened',
        'heard',
        'mine',
        'favorites',
        'favourites',
        'artists',
        'artist',
        'genre',
        'genres',
        'something',
        'anything',
        'everything',
        'nothing',
        'someone',
        'anyone',
        'me',
        'us',
        'you',
        'good songs',
        'best songs',
        'top songs',
      };

      // Match ONLY "from <artist>" or "by <artist>" (never match "of <noun>")
      final fromArtistMatch = RegExp(
        r"(?:from|by)\s+([a-zA-Z0-9\s\.\'-]+?)(?:\s+that|\s+i\s|\s+which|\s*$|\.|\,)",
        caseSensitive: false,
      ).firstMatch(mood);

      String? validDiscoveryArtist;
      if (isDiscovery && fromArtistMatch != null) {
        final candidate = fromArtistMatch.group(1)?.trim() ?? '';
        final lowerCand = candidate.toLowerCase();
        if (candidate.length > 2 &&
            !nonArtistWords.contains(lowerCand) &&
            !lowerCand.endsWith(' songs') &&
            !lowerCand.endsWith(' tracks') &&
            !lowerCand.endsWith(' music') &&
            !lowerCand.startsWith('songs ') &&
            !lowerCand.startsWith('tracks ')) {
          validDiscoveryArtist = candidate;
        }
      }

      if (validDiscoveryArtist != null) {
        onStageChanged?.call(1);
        final disc = await _generateArtistDiscoveryPlaylist(
            validDiscoveryArtist, requestedSize, mood);
        if (disc != null && disc.songs.isNotEmpty) {
          onStageChanged?.call(2);
          await Future.delayed(const Duration(milliseconds: 200));
          onStageChanged?.call(3);
          await Future.delayed(const Duration(milliseconds: 150));
          return _sanitizePlaylist(disc);
        }
      }

      final lowerMood = mood.toLowerCase();
      final isKhmerMusicRequest = _isKhmerMusicRequest(mood);
      final hasSimilarity = RegExp(
        r'(similar|like|vibe\s*to|vibe\s*with|style\s*of|sound\s*like|mix|blend|radio|inspired|chill|relax|acoustic|pop|r&b|hip|rap|rock|indie|lo-?fi|ស្រដៀង|ដូច|ស្ទីល)',
        caseSensitive: false,
      ).hasMatch(lowerMood);

      final isStrictSingleArtistOnly = !hasSimilarity &&
          RegExp(r'(only|just\s+[a-zA-Z\u1780-\u17FF]+$|discography|all\s*songs\s*by|all\s*tracks\s*by|តែ|សុទ្ធ|បទ\s*[a-zA-Z\u1780-\u17FF]+\s*only)',
                  caseSensitive: false)
              .hasMatch(lowerMood);

      // Handle STRICT artist-only discography request (e.g. "Taylor Swift only", "Tena discography", "សុទ្ធ")
      if (isStrictSingleArtistOnly) {
        if (artistIds != null && artistIds.isNotEmpty) {
          onStageChanged?.call(1); // Stage 1: Finding the right songs
          final res = await _generateMultiArtistPlaylist(
              artistIds, requestedSize, mood);
          onStageChanged?.call(2); // Stage 2: Checking audio streamability
          await Future.delayed(const Duration(milliseconds: 300));
          onStageChanged?.call(3); // Stage 3: Putting it all together
          await Future.delayed(const Duration(milliseconds: 250));
          return _sanitizePlaylist(res);
        }

        final detectedArtists = await _detectArtistsInPrompt(mood);
        if (detectedArtists.isNotEmpty &&
            (artistIds == null || artistIds.isEmpty) &&
            (trackIds == null || trackIds.isEmpty)) {
          onStageChanged?.call(1);
          final res = await _generateMultiArtistPlaylist(
              detectedArtists, requestedSize, mood);
          onStageChanged?.call(2);
          await Future.delayed(const Duration(milliseconds: 300));
          onStageChanged?.call(3);
          await Future.delayed(const Duration(milliseconds: 250));
          return _sanitizePlaylist(res);
        }
      }

      // Detect Franchise / Gaming / Anime Universe (e.g. Valorant, League of Legends, Arcane, Naruto, One Piece, Attack on Titan, JJK, Cyberpunk)
      final franchisePlaylist =
          await _detectAndBuildFranchisePlaylist(mood, requestedSize);
      if (franchisePlaylist != null && franchisePlaylist.songs.isNotEmpty) {
        onStageChanged?.call(1);
        await Future.delayed(const Duration(milliseconds: 250));
        onStageChanged?.call(2);
        await Future.delayed(const Duration(milliseconds: 300));
        onStageChanged?.call(3);
        await Future.delayed(const Duration(milliseconds: 200));
        return _sanitizePlaylist(franchisePlaylist);
      }

      final isOldies = RegExp(
              r'(បទ[\s]*ចាស់|ចាស់[\s]*ចាស់|ចាស់ៗ|old\s*songs|older\s*songs|classics|golden\s*era|classic\s*khmer)',
              caseSensitive: false)
          .hasMatch(lowerMood);
      final isNewHits = RegExp(
              r'(បទ[\s]*ថ្មី|ថ្មី[\s]*ថ្មី|ថ្មីៗ|new\s*songs|newer\s*songs|latest\s*songs|trending\s*khmer)',
              caseSensitive: false)
          .hasMatch(lowerMood);

      if (isOldies) {
        onStageChanged?.call(1);
        final res = await _generateMultiArtistPlaylist(
          [
            'Sinn Sisamouth',
            'Ros Sereysothea',
            'Pen Ron',
            'Preap Sovath',
            'Noy Vanneth'
          ],
          requestedSize,
          mood,
        );
        onStageChanged?.call(2);
        await Future.delayed(const Duration(milliseconds: 300));
        onStageChanged?.call(3);
        await Future.delayed(const Duration(milliseconds: 250));
        return _sanitizePlaylist(res);
      } else if (isNewHits) {
        onStageChanged?.call(1);
        final res = await _generateMultiArtistPlaylist(
          ['VannDa', 'Tena', 'Suly Pheng', 'G-Devith', 'Reth Suzana'],
          requestedSize,
          mood,
        );
        onStageChanged?.call(2);
        await Future.delayed(const Duration(milliseconds: 300));
        onStageChanged?.call(3);
        await Future.delayed(const Duration(milliseconds: 250));
        return _sanitizePlaylist(res);
      }

      // Deezer's catalogue is incomplete for Cambodian music. A general Khmer
      // request must therefore use our verified Khmer artist path instead of
      // letting broad catalog searches leak unrelated international tracks.
      // The original prompt is retained for the playlist's mood/context.
      if (isKhmerMusicRequest) {
        onStageChanged?.call(1);
        final res = await _generateMultiArtistPlaylist(
          const [
            'VannDa',
            'Suly Pheng',
            'G-Devith',
            'Reth Suzana',
            'Preap Sovath',
            'Sokun Nisa',
            'Sinn Sisamouth',
            'Ros Sereysothea',
            'Khem',
            'Kmeng Khmer',
          ],
          requestedSize,
          mood,
        );
        onStageChanged?.call(2);
        await Future.delayed(const Duration(milliseconds: 250));
        onStageChanged?.call(3);
        return _sanitizePlaylist(res);
      }

      // Mood-based AI generation
      onStageChanged?.call(1);
      final res = await _generateMoodPlaylist(
        mood,
        requestedSize,
        artistIds: artistIds,
        trackIds: trackIds,
        onStageChanged: onStageChanged,
      );
      onStageChanged?.call(3);
      await Future.delayed(const Duration(milliseconds: 250));
      return _sanitizePlaylist(res);
    } catch (e) {
      return GeneratedPlaylist(
        success: false,
        mood: mood,
        size: 0,
        source: 'error',
        error: e.toString(),
        songs: [],
      );
    }
  }

  static GeneratedPlaylist _sanitizePlaylist(GeneratedPlaylist pl) {
    if (!pl.success || pl.songs.isEmpty) return pl;
    final valid = pl.songs.where((s) {
      final id = (s['deezerId'] ?? s['id'] ?? '').toString().trim();
      return id.isNotEmpty && id != '0' && id != 'null';
    }).toList();
    if (valid.length == pl.songs.length) return pl;
    return GeneratedPlaylist(
      success: valid.isNotEmpty,
      mood: pl.mood,
      title: pl.title,
      description: pl.description,
      size: valid.length,
      source: pl.source,
      error: pl.error,
      songs: valid,
    );
  }

  static bool _isKhmerMusicRequest(String mood) {
    final lower = mood.toLowerCase();
    return RegExp(r'[\u1780-\u17ff]').hasMatch(mood) ||
        RegExp(r'\b(khmer|cambodian|cambodia)\b').hasMatch(lower);
  }

  static Future<List<String>> _detectArtistsInPrompt(String mood) async {
    final lower = mood.toLowerCase();
    final matched = <String>[];

    // Check curated Khmer artists with Unicode normalization & regex matching
    final khmerMap = {
      // Tena (handles all Khmer vowel combinations: ថេណា, ថេនណា, ថេណា Cambodia)
      RegExp(r'(ថេ[នណ][ាា]?|tena)', caseSensitive: false): 'Tena',
      // VannDa (handles វណ្ណដា, វ៉ាន់ដា, វ៉ាន់ដា)
      RegExp(r'(វ[ណ្ណ័ាន់]+ដា|vannda)', caseSensitive: false): 'VannDa',
      // Preap Sovath
      RegExp(r'(ព្រាប\s*សុវត្ថិ|preap\s*sovath)', caseSensitive: false):
          'Preap Sovath',
      // Suly Pheng
      RegExp(r'(ស៊ូ[លី]+[\s]*ផេង|suly\s*pheng)', caseSensitive: false):
          'Suly Pheng',
      // G-Devith
      RegExp(r'(ជី[\s]*ដេវីត|g[\s-]*devith)', caseSensitive: false): 'G-Devith',
      // Sinn Sisamouth
      RegExp(r'(ស៊ីន[\s]*ស៊ីសាមុត|sinn\s*sisamouth)', caseSensitive: false):
          'Sinn Sisamouth',
      // Ros Sereysothea
      RegExp(r'(រស់[\s]*សេរីសុទ្ធា|ros\s*sereysothea)', caseSensitive: false):
          'Ros Sereysothea',
      // Chhay Virakyuth
      RegExp(r'(ឆាយ[\s]*វីរៈយុទ្ធ|chhay\s*virakyuth)', caseSensitive: false):
          'Chhay Virakyuth',
      // Sok Pisey (handles សុខ ពិសី, សុខពិសី, sok pisey)
      RegExp(r'(សុខ[\s]*ពិសី|sok\s*pisey)', caseSensitive: false): 'Sok Pisey',
      // Khemarak Sereymun (handles ខេមរៈ សិរីមន្ត, ខេមរះសេរីមន្ត, khemarak sereymun)
      RegExp(r'(ខេម[រៈរះ]*[\s]*សិ[រេ]ីមន្ត|khemarak\s*sereymun)',
          caseSensitive: false): 'Khemarak Sereymun',
      // Khem (handles standalone ខេម, khem)
      RegExp(r'(^|\s|បទ|ពី)ខេម(\s|$|និង|និង|&)|(^|\s)khem(\s|$)',
          caseSensitive: false): 'Khem',
      // Aok Sokunkanha
      RegExp(r'(ឱក[\s]*សុគន្ធកញ្ញា|aok\s*sokunkanha)', caseSensitive: false):
          'Aok Sokunkanha',
      // Sokun Nisa
      RegExp(r'(សុគន្ធ[\s]*និសា|sokun\s*nisa)', caseSensitive: false):
          'Sokun Nisa',
      // Meas Soksophea
      RegExp(r'(មាស[\s]*សុខសោភា|meas\s*soksophea)', caseSensitive: false):
          'Meas Soksophea',
      // Heng Pitu
      RegExp(r'(ហេង[\s]*ពិទូ|heng\s*pitu)', caseSensitive: false): 'Heng Pitu',
      // Reth Suzana
      RegExp(r'(រ៉េត[\s]*ស៊ូហ្សាណា|reth\s*suzana)', caseSensitive: false):
          'Reth Suzana',
      // Neay Jerm
      RegExp(r'(នាយចឺម|neay\s*jerm)', caseSensitive: false): 'Neay Jerm',
      // Manith
      RegExp(r'(ម៉ានិត|manith)', caseSensitive: false): 'Manith',
      // Tep Boprek
      RegExp(r'(ទេព[\s]*បូព្រឹក្ស|tep\s*boprek)', caseSensitive: false):
          'Tep Boprek',
      // Pich Sophea
      RegExp(r'(ពេជ្រ[\s]*សោភា|pich\s*sophea)', caseSensitive: false):
          'Pich Sophea',
      // Niko
      RegExp(r'(នីកូ|niko)', caseSensitive: false): 'Niko',
      // Chen
      RegExp(r'(ចេន|chen)', caseSensitive: false): 'Chen',
      // Kuma
      RegExp(r'(គូម៉ា|kuma)', caseSensitive: false): 'Kuma',
      // Ny Rattana
      RegExp(r'(នី[\s]*រតនា|ny\s*rattana)', caseSensitive: false): 'Ny Rattana',
      // Keo Veasna
      RegExp(r'(កែវ[\s]*វាសនា|keo\s*veasna)', caseSensitive: false):
          'Keo Veasna',
      // Pen Ron
      RegExp(r'(ប៉ែន[\s]*រ៉ន|pen\s*ron)', caseSensitive: false): 'Pen Ron',
      // Dengue Fever
      RegExp(r'(ដេងហ្គីហ្វីវើ|dengue\s*fever)', caseSensitive: false):
          'Dengue Fever',
      // Yol Aularong
      RegExp(r'(យ៉ុល[\s]*អូឡារ៉ុង|yol\s*aularong)', caseSensitive: false):
          'Yol Aularong',
      // Noy Vanneth
      RegExp(r'(ណយ[\s]*វ៉ាន់ណេត|noy\s*vanneth)', caseSensitive: false):
          'Noy Vanneth',
      // Meng Keo Pichenda
      RegExp(r'(ម៉េង[\s]*កែវពេជ្ជតា|meng\s*keo\s*pichenda)',
          caseSensitive: false): 'Meng Keo Pichenda',
      // Him Sivorn
      RegExp(r'(ហ៊ីម[\s]*ស៊ីវន|him\s*sivorn)', caseSensitive: false):
          'Him Sivorn',
      // Touch Sunnix
      RegExp(r'(ទូច[\s]*ស៊ុននិច|touch\s*sunnix)', caseSensitive: false):
          'Touch Sunnix',
      // Vuthea
      RegExp(r'(វុទ្ធា|vuthea)', caseSensitive: false): 'Vuthea',
      // RuthKo
      RegExp(r'(រូថកូ|ruthko)', caseSensitive: false): 'RuthKo',
      // Vanthan
      RegExp(r'(វណ្ណថាន|vanthan)', caseSensitive: false): 'Vanthan',
      // Kmeng Khmer
      RegExp(r'(ក្មេងខ្មែរ|kmeng\s*khmer)', caseSensitive: false):
          'Kmeng Khmer',
      // SmallWorld SmallBand
      RegExp(r'(ស្មលវើល|smallworld\s*smallband)', caseSensitive: false):
          'SmallWorld SmallBand',
      // Adda Angel
      RegExp(r'(អដ្ដា|adda\s*angel)', caseSensitive: false): 'Adda Angel',
      // Sovath Monivann
      RegExp(r'(សុវត្ថិ[\s]*មុនីវណ្ណ|sovath\s*monivann)', caseSensitive: false):
          'Sovath Monivann',
      // Eva
      RegExp(r'(អ៊ីវ៉ា|eva)', caseSensitive: false): 'Eva',
      // Bross La
      RegExp(r'(ប្រុសឡា|bross\s*la)', caseSensitive: false): 'Bross La',
      // Youki
      RegExp(r'(យូគី|youki)', caseSensitive: false): 'Youki',
      // Lowkey
      RegExp(r'(ឡូគី|lowkey)', caseSensitive: false): 'Lowkey',
      // Layo
      RegExp(r'(ឡាយ៉ូ|layo)', caseSensitive: false): 'Layo',
      // Kea
      RegExp(r'(គា|kea)', caseSensitive: false): 'Kea',
      // Polarix
      RegExp(r'(ប៉ូឡារិច|polarix)', caseSensitive: false): 'Polarix',
      // Songha
      RegExp(r'(សង្ហា|songha)', caseSensitive: false): 'Songha',
      // YuHai
      RegExp(r'(យូហៃ|yuhai)', caseSensitive: false): 'YuHai',
      // Sos Kamak
      RegExp(r'(សូស[\s]*កាម៉ាក់|sos\s*kamak)', caseSensitive: false):
          'Sos Kamak',
      // In Yeng
      RegExp(r'(អ៊ិន[\s]*យេង|in\s*yeng)', caseSensitive: false): 'In Yeng',
      // Eam Vanny
      RegExp(r'(អ៊ាម[\s]*វណ្ណី|eam\s*vanny)', caseSensitive: false):
          'Eam Vanny',
      // Houy Meas
      RegExp(r'(ហួយ[\s]*មាស|houy\s*meas)', caseSensitive: false): 'Houy Meas',
      // Chhouy Sopheap
      RegExp(r'(ឈួយ[\s]*សុភាព|chhouy\s*sopheap)', caseSensitive: false):
          'Chhouy Sopheap',
      // Meas Samon
      RegExp(r'(មាស[\s]*សាម៉ន|meas\s*samon)', caseSensitive: false):
          'Meas Samon',
      // Chhom Nimol
      RegExp(r'(ឆោម[\s]*និមល|chhom\s*nimol)', caseSensitive: false):
          'Chhom Nimol',
    };

    for (final entry in khmerMap.entries) {
      if (entry.key.hasMatch(lower) || entry.key.hasMatch(mood)) {
        if (!matched.contains(entry.value)) {
          matched.add(entry.value);
        }
      }
    }
    return matched;
  }

  static Future<GeneratedPlaylist?> _detectAndBuildFranchisePlaylist(
      String mood, int size) async {
    final lower = mood.toLowerCase();

    // Map franchise prompts to official publisher catalog queries
    final franchiseConfigs = <String, Map<String, dynamic>>{
      // VALORANT
      'valorant': {
        'keywords': ['valorant', 'val ', 'vct', 'champions 202', 'radiant'],
        'title': 'VALORANT: Official Anthems & Gaming Hype',
        'desc':
            'Official VALORANT Champions anthems, cinematic tracks, and high-energy clutch beats.',
        'artist_queries': [
          'VALORANT',
          'Riot Games Music',
          'Grabbitz',
          'Zedd',
          'Armani White',
          'eaJ',
          'Safia'
        ],
        'track_queries': [
          'Die For You Grabbitz',
          'Fire Again VALORANT',
          'Ticking Away VALORANT',
          'SUPERPOWER VALORANT',
          'Greater Than One VALORANT',
          'Visions VALORANT',
          'Can\'t Slow Me Down VALORANT',
          'SUPERHERO Armani White',
          'Ignite Zedd',
          'Warriors Imagine Dragons',
          'Legends Never Die Against The Current',
          'GODS NewJeans',
          'POP/STARS K/DA',
          'Enemy Imagine Dragons',
          'Rise The Glitch Mob',
          'Awaken Valerie Broussard',
          'Heavy Is The Crown Linkin Park',
          'Phoenix Cailin Russo',
          'THE BADDEST K/DA',
          'Giants True Damage',
        ],
      },
      // LEAGUE OF LEGENDS / ARCANE
      'league': {
        'keywords': [
          'league of legends',
          'lol ',
          'wild rift',
          'arcane',
          'k/da',
          'true damage',
          'pentakill',
          'summoner'
        ],
        'title': 'League of Legends & Arcane',
        'desc':
            'Official Worlds anthems, K/DA, True Damage, and Arcane soundtrack.',
        'artist_queries': [
          'League of Legends',
          'Riot Games Music',
          'K/DA',
          'True Damage',
          'Pentakill'
        ],
        'track_queries': [
          'Warriors Imagine Dragons',
          'Legends Never Die Against The Current',
          'POP/STARS K/DA',
          'Enemy Imagine Dragons',
          'Awaken Valerie Broussard',
          'Giants True Damage',
          'GODS NewJeans',
          'Heavy Is The Crown Linkin Park',
          'Phoenix Cailin Russo',
          'THE BADDEST K/DA',
          'More K/DA',
          'What Could Have Been Sting',
          'Playground Bea Miller',
          'Get Jinxed League of Legends',
          'Ignite Zedd',
          'Rise The Glitch Mob',
        ],
      },
      // NARUTO
      'naruto': {
        'keywords': ['naruto', 'shippuden', 'boruto', 'hokage', 'konoha'],
        'title': 'Naruto & Shippuden: The Iconic Openings',
        'desc':
            'Chronological official anime openings and legendary battle OSTs.',
        'artist_queries': [
          'FLOW',
          'Asian Kung-Fu Generation',
          'KANA-BOON',
          'Ikimonogakari',
          'NICO Touches the Walls',
          'Sambomaster'
        ],
        'track_queries': [
          'Blue Bird Ikimonogakari',
          'Silhouette KANA-BOON',
          'Sign FLOW',
          'GO FLOW',
          'Haruka Kanata Asian Kung-Fu Generation',
          'Hotaru no Hikari Ikimonogakari',
          'Diver NICO Touches the Walls',
          'Hero\'s Come Back nobodyknows',
          'Blood Circulator Asian Kung-Fu Generation',
          'Seishun Kyousoukyoku Sambomaster',
          'CLOSER Joe Inoue',
          'Toumei Datta Sekai Motohiro Hata',
          'Lovers 7!!',
          'Kara no Kokoro Anly',
        ],
      },
      // ONE PIECE
      'one_piece': {
        'keywords': [
          'one piece',
          'luffy',
          'straw hat',
          'wano',
          'gear 5',
          'egghead'
        ],
        'title': 'One Piece: The Complete Voyage',
        'desc':
            'Official openings from We Are! to the latest Grand Line and Egghead anthems.',
        'artist_queries': [
          'Hiroshi Kitadani',
          'Namie Amuro',
          'Da-iCE',
          'AAA',
          'Folder5',
          'GENERATIONS from EXILE TRIBE',
          'SEKAI NO OWARI',
          'V6',
          'I Don\'t Like Mondays',
        ],
        'track_queries': [
          'We Are Hiroshi Kitadani',
          'Believe Folder5',
          'Hikari E The Babystars',
          'BON VOYAGE Bon-Bon Blanco',
          'Kokoro no Chizu BOYSTYLE',
          'BRAND NEW WORLD D-51',
          'Crazy Rainbow Tackey & Tsubasa',
          'Jungle P 5050',
          'Share The World TVXQ',
          'Kaze wo Sagashite Hexagon',
          'One day The ROOTLESS',
          'Fight Together Namie Amuro',
          'We Go Hiroshi Kitadani',
          'Hands Up Kota Shinzato',
          'Wake up AAA',
          'Hard Knock Days GENERATIONS',
          'We Can Hiroshi Kitadani Kishidan',
          'Hope Namie Amuro',
          'Super Powers V6',
          'OVER THE TOP Hiroshi Kitadani',
          'DREAMIN ON Da-iCE',
          'PAINT I Don\'t Like Mondays',
          'Peak SEKAI NO OWARI',
          'UUUUUS Hiroshi Kitadani',
          'Asu e no Hikari Saika Hinata',
          'Bink\'s Sake Ado',
          'New Genesis Ado',
          'Watashi wa Saikyou Ado',
          'Backlight Ado',
          'Tot Musica Ado',
        ],
      },
      // ATTACK ON TITAN
      'aot': {
        'keywords': ['attack on titan', 'shingeki', 'aot', 'rumbling', 'eren'],
        'title': 'Attack on Titan: The Complete OST',
        'desc': 'Official anthems by Linked Horizon, SiM, and Hiroyuki Sawano.',
        'artist_queries': ['Linked Horizon', 'SiM', 'Hiroyuki Sawano'],
        'track_queries': [
          'Guren no Yumiya Linked Horizon',
          'The Rumbling SiM',
          'Shinzou wo Sasageyo Linked Horizon',
          'Red Swan YOSHIKI HYDE',
          'Boku no Sensou Shinsei Kamattechan',
          'UNDER THE TREE SiM',
          'Akatsuki no Requiem Linked Horizon',
        ],
      },
      // CYBERPUNK 2077 / EDGERUNNERS
      'cyberpunk': {
        'keywords': ['cyberpunk', 'edgerunners', 'night city'],
        'title': 'Cyberpunk 2077 & Edgerunners',
        'desc':
            'I Really Want to Stay at Your House and Night City radio hits.',
        'artist_queries': ['Rosa Walton', 'HEALTH', 'Marcin Przybylowicz'],
        'track_queries': [
          'I Really Want to Stay at Your House Rosa Walton',
          'Major Crimes Health',
          'Who\'s Ready for Tomorrow RAT BOY',
          'Night City Raito',
          'Never Fade Away Refused',
          'Chippin In Refused',
        ],
      },
      // JUJUTSU KAISEN
      'jjk': {
        'keywords': [
          'jujutsu kaisen',
          'jujutsu',
          'jjk',
          'sukuna',
          'gojo',
          'itadori',
          'megumi',
          'nobara',
          'shibuya incident',
          'hidden inventory',
        ],
        'title': 'Jujutsu Kaisen: The Complete OST',
        'desc':
            'Official anime openings and battle soundtracks by Eve, King Gnu, Tatsuya Kitani, and ALI.',
        'artist_queries': [
          'Eve',
          'King Gnu',
          'Tatsuya Kitani',
          'ALI',
          'Soushi Sakiyama',
          'Hitsujibungaku',
          'Who-ya Extended',
          'Cö shu Nie',
        ],
        'track_queries': [
          'Kaikai Kitan Eve',
          'SPECIALZ King Gnu',
          'Ao no Sumika Tatsuya Kitani',
          'Lost in Paradise ALI',
          'Akari Soushi Sakiyama',
          'VIVID VICE Who-ya Extended',
          'Give It Back Co shu Nie',
          'MORE THAN WORDS Hitsujibungaku',
          'Ichizu King Gnu',
          'Sakahagi King Gnu',
          'Bokurano Eve',
          'Fight Song Eve',
        ],
      },
    };

    Map<String, dynamic>? selectedConfig;
    for (final cfg in franchiseConfigs.values) {
      final kws = cfg['keywords'] as List<String>;
      if (kws.any((kw) => lower.contains(kw))) {
        selectedConfig = cfg;
        break;
      }
    }

    if (selectedConfig == null) return null;

    final candidateTracks = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addSong(SearchResult t) {
      if (t.id.isEmpty || t.title.isEmpty || t.artist.isEmpty) return;
      final key =
          '${t.title.toLowerCase().trim()}|${t.artist.toLowerCase().trim()}';
      if (seen.add(key)) {
        candidateTracks.add({
          'title': t.title,
          'artist': t.artist,
          'artistId': t.artistId,
          'artistImage': t.artistImage,
          'image': t.image,
          'duration': t.duration,
          'deezerId': t.id,
          'previewUrl': t.previewUrl,
          'source': 'franchise_curated',
        });
      }
    }

    // 1. Fetch specific track queries in parallel
    final trackQueries = selectedConfig['track_queries'] as List<String>? ?? [];
    final trackFutures = trackQueries.map((tq) async {
      try {
        final qEnc = Uri.encodeComponent(tq);
        final resp = await http.get(
          Uri.parse('$_deezerApi/search?q=$qEnc&limit=3'),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final items = (data['data'] as List? ?? [])
              .whereType<Map<String, dynamic>>()
              .where((t) => t['readable'] != false)
              .map((r) => SearchResult.fromDeezerTrack(r))
              .toList();
          return items;
        }
      } catch (_) {}
      return <SearchResult>[];
    });

    final trackResults = await Future.wait(trackFutures);
    for (int i = 0; i < trackResults.length; i++) {
      final list = trackResults[i];
      final targetQuery = i < trackQueries.length ? trackQueries[i].trim() : '';
      if (list.isNotEmpty && targetQuery.isNotEmpty) {
        final queryParts = targetQuery.split(' ');
        final expectedTitle = queryParts.first.toLowerCase();
        final expectedArtist = queryParts.length > 1
            ? queryParts.sublist(1).join(' ').toLowerCase()
            : '';

        // Strict filter: candidate artist MUST contain the expected artist name, OR title contains anime/game tag
        final matching = list.where((c) {
          final aLower = c.artist.toLowerCase();
          final tLower = c.title.toLowerCase();

          // Block notorious lookalikes when Japanese/Anime/Riot was requested
          if (aLower.contains('beyoncé') ||
              aLower.contains('beyonce') ||
              aLower.contains('daniel caesar')) {
            return expectedArtist.contains('beyonce') ||
                expectedArtist.contains('caesar');
          }

          if (c.artistId == '837' ||
              (aLower == 'eve' &&
                  (tLower.contains('blow ya mind') ||
                      tLower.contains("who's that girl") ||
                      tLower.contains('gangsta lovin') ||
                      tLower.contains('what you need') ||
                      tLower.contains('rich girl')))) {
            return false;
          }

          final artistMatches = expectedArtist.isNotEmpty &&
              (aLower.contains(expectedArtist) ||
                  expectedArtist.contains(aLower));
          final isExplicitSoundtrack = aLower.contains('anime') ||
              tLower.contains('opening') ||
              tLower.contains('one piece') ||
              tLower.contains('ost');

          return artistMatches || isExplicitSoundtrack;
        }).toList();

        if (matching.isNotEmpty) {
          final best = matching.firstWhere(
            (c) =>
                !c.title.toLowerCase().contains('cover') &&
                !c.artist.toLowerCase().contains('cover'),
            orElse: () => matching.first,
          );
          addSong(best);
        }
      }
    }

    // 2. If under requested size, pull top tracks from official artist profiles
    if (candidateTracks.length < size) {
      final artistQueries =
          selectedConfig['artist_queries'] as List<String>? ?? [];
      for (final aName in artistQueries) {
        if (candidateTracks.length >= size) break;
        try {
          String? aId;
          final aLower = aName.toLowerCase().trim();
          if (aLower == 'eve' || aLower == 'いぶ') {
            aId = '69128312';
          } else {
            final qEnc = Uri.encodeComponent(aName);
            final aResp = await http.get(
              Uri.parse('$_deezerApi/search/artist?q=$qEnc&limit=1'),
              headers: {'Accept': 'application/json'},
            ).timeout(const Duration(seconds: 3));
            if (aResp.statusCode == 200) {
              final aData = jsonDecode(aResp.body);
              final aList = aData['data'] as List? ?? [];
              if (aList.isNotEmpty) {
                aId = aList[0]['id']?.toString();
              }
            }
          }
          if (aId != null) {
            List<SearchResult> topList;
            if (aId == '69128312') {
              topList =
                  await ArtistService.getArtistTopTracks('69128312', limit: 15);
            } else {
              final topResp = await http.get(
                Uri.parse('$_deezerApi/artist/$aId/top?limit=15'),
                headers: {'Accept': 'application/json'},
              ).timeout(const Duration(seconds: 3));
              if (topResp.statusCode == 200) {
                final topData = jsonDecode(topResp.body);
                topList = (topData['data'] as List? ?? [])
                    .whereType<Map<String, dynamic>>()
                    .where((t) => t['readable'] != false)
                    .map((r) => SearchResult.fromDeezerTrack(r))
                    .toList();
              } else {
                topList = [];
              }
            }
            for (final item in topList) {
              if (candidateTracks.length >= size) break;
              addSong(item);
            }
          }
        } catch (_) {}
      }
    }

    // 3. If STILL under requested size, pull top tracks from official Riot Games & verified franchise publisher profiles
    if (candidateTracks.length < size) {
      final publisherQueries = selectedConfig['title']
                  .toString()
                  .toLowerCase()
                  .contains('valorant') ||
              selectedConfig['title']
                  .toString()
                  .toLowerCase()
                  .contains('league')
          ? ['Riot Games Music', 'League of Legends', 'K/DA', 'True Damage']
          : selectedConfig['artist_queries'] as List<String>? ?? [];

      for (final aName in publisherQueries) {
        if (candidateTracks.length >= size) break;
        try {
          final qEnc = Uri.encodeComponent(aName);
          final aResp = await http.get(
            Uri.parse('$_deezerApi/search/artist?q=$qEnc&limit=1'),
            headers: {'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 3));
          if (aResp.statusCode == 200) {
            final aData = jsonDecode(aResp.body);
            final aList = aData['data'] as List? ?? [];
            if (aList.isNotEmpty) {
              final aId = aList[0]['id']?.toString();
              if (aId != null) {
                final topResp = await http.get(
                  Uri.parse('$_deezerApi/artist/$aId/top?limit=20'),
                  headers: {'Accept': 'application/json'},
                ).timeout(const Duration(seconds: 3));
                if (topResp.statusCode == 200) {
                  final topData = jsonDecode(topResp.body);
                  final topList = (topData['data'] as List? ?? [])
                      .whereType<Map<String, dynamic>>()
                      .where((t) => t['readable'] != false)
                      .map((r) => SearchResult.fromDeezerTrack(r))
                      .where((t) =>
                          !t.title.toLowerCase().contains('brainrot') &&
                          !t.title.toLowerCase().contains('meme'));
                  for (final item in topList) {
                    if (candidateTracks.length >= size) break;
                    addSong(item);
                  }
                }
              }
            }
          }
        } catch (_) {}
      }
    }

    if (candidateTracks.isNotEmpty) {
      final finalSongs = candidateTracks.take(size).toList();
      final pl = GeneratedPlaylist(
        success: true,
        mood: mood,
        title: selectedConfig['title']?.toString() ?? 'Franchise Playlist',
        description: selectedConfig['desc']?.toString() ?? '',
        size: finalSongs.length,
        source: 'franchise_verified',
        songs: finalSongs,
      );
      _saveToSupabase(pl);
      return pl;
    }
    return null;
  }

  static Future<GeneratedPlaylist> _generateMostListenedPlaylist(
    int size,
    String mood, {
    void Function(int stage)? onStageChanged,
  }) async {
    onStageChanged?.call(0); // Stage 0: Analyzing your listening history
    await Future.delayed(const Duration(milliseconds: 300));

    final user = Supabase.instance.client.auth.currentUser;
    final scoreMap = <String, double>{};
    final trackDataMap = <String, Map<String, dynamic>>{};
    final artistPlayCount = <String, int>{};

    void processEntry(Map<String, dynamic> item) {
      final title = (item['title'] ?? '').toString().trim();
      final artist = (item['artist'] ?? '').toString().trim();
      if (title.isEmpty || artist.isEmpty) return;

      final trackId =
          (item['track_id'] ?? item['trackId'] ?? item['id'] ?? '').toString();
      final cTitle = HeardHistoryFilter.cleanTitle(title);
      final cArtist = HeardHistoryFilter.cleanArtist(artist);
      final key = '$cTitle|$cArtist';

      final bool skipped = item['skipped'] == true;
      final bool completed = item['completed'] == true;
      final bool replayed = item['replayed'] == true;
      final int duration = (item['listen_duration'] is int)
          ? item['listen_duration'] as int
          : (item['listenDuration'] is int)
              ? item['listenDuration'] as int
              : 0;

      double weight = 1.0;
      if (replayed) weight += 3.0;
      if (completed || duration > 60) weight += 2.0;
      if (skipped && duration < 30) weight -= 1.5;

      scoreMap[key] = (scoreMap[key] ?? 0.0) + weight;
      artistPlayCount[artist] = (artistPlayCount[artist] ?? 0) + 1;

      trackDataMap.putIfAbsent(
        key,
        () => {
          'title': title,
          'artist': artist,
          'artistId': (item['artist_id'] ?? item['artistId'] ?? '').toString(),
          'artistImage':
              (item['artist_image'] ?? item['artistImage'] ?? '').toString(),
          'image': (item['image'] ?? '').toString(),
          'duration': (item['duration'] ?? '').toString(),
          'deezerId': trackId,
          'previewUrl':
              (item['preview_url'] ?? item['previewUrl'] ?? '').toString(),
          'source': 'most_listened',
        },
      );
    }

    // 1. Local history cache (in-memory & disk)
    try {
      final local = await ListeningHistoryService.getHistory();
      for (final item in local) {
        processEntry(item);
      }
    } catch (_) {}

    for (final item in ListeningHistoryService.cachedHistory) {
      processEntry(item);
    }

    // 2. Remote Supabase listening_history table
    if (user != null) {
      try {
        final rows = await Supabase.instance.client
            .from('listening_history')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(500)
            .timeout(const Duration(seconds: 5));

        for (final r in rows) {
          processEntry(r);
        }
      } catch (_) {}
    }

    onStageChanged?.call(1); // Stage 1: Ranking your top tracks
    await Future.delayed(const Duration(milliseconds: 250));

    // Sort by score descending (only tracks with positive net score)
    final sortedKeys = scoreMap.keys
        .where((k) => (scoreMap[k] ?? 0) > 0)
        .toList()
      ..sort((a, b) => scoreMap[b]!.compareTo(scoreMap[a]!));

    final resultSongs = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final key in sortedKeys) {
      if (resultSongs.length >= size) break;
      final t = trackDataMap[key];
      if (t != null && seen.add(key)) {
        resultSongs.add(t);
      }
    }

    // 3. If under requested size, backfill with top tracks from user's most-played artists
    if (resultSongs.length < size && artistPlayCount.isNotEmpty) {
      onStageChanged?.call(2); // Stage 2: Discovering matching favorites
      final sortedArtists = artistPlayCount.keys.toList()
        ..sort((a, b) => artistPlayCount[b]!.compareTo(artistPlayCount[a]!));

      for (final aName in sortedArtists.take(5)) {
        if (resultSongs.length >= size) break;
        try {
          final qEnc = Uri.encodeComponent(aName);
          final aResp = await http.get(
            Uri.parse('$_deezerApi/search/artist?q=$qEnc&limit=1'),
            headers: {'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 3));
          if (aResp.statusCode == 200) {
            final aData = jsonDecode(aResp.body);
            final aList = aData['data'] as List? ?? [];
            if (aList.isNotEmpty) {
              final aId = aList[0]['id']?.toString();
              if (aId != null) {
                final topResp = await http.get(
                  Uri.parse('$_deezerApi/artist/$aId/top?limit=15'),
                  headers: {'Accept': 'application/json'},
                ).timeout(const Duration(seconds: 3));
                if (topResp.statusCode == 200) {
                  final topData = jsonDecode(topResp.body);
                  final items = (topData['data'] as List? ?? [])
                      .whereType<Map<String, dynamic>>()
                      .where((t) => t['readable'] != false)
                      .map((r) => SearchResult.fromDeezerTrack(r));
                  for (final item in items) {
                    if (resultSongs.length >= size) break;
                    final cKey =
                        '${HeardHistoryFilter.cleanTitle(item.title)}|${HeardHistoryFilter.cleanArtist(item.artist)}';
                    if (seen.add(cKey)) {
                      resultSongs.add({
                        'title': item.title,
                        'artist': item.artist,
                        'artistId': item.artistId,
                        'artistImage': item.artistImage,
                        'image': item.image,
                        'duration': item.duration,
                        'deezerId': item.id,
                        'previewUrl': item.previewUrl,
                        'source': 'artist_backfill',
                      });
                    }
                  }
                }
              }
            }
          }
        } catch (_) {}
      }
    }

    onStageChanged?.call(3); // Stage 3: Putting it all together
    await Future.delayed(const Duration(milliseconds: 200));

    if (resultSongs.isEmpty) {
      return GeneratedPlaylist(
        success: false,
        mood: mood,
        size: 0,
        source: 'no_history',
        error:
            "You haven't listened to enough songs yet! Play a few tracks, and Melo will automatically generate your On Repeat playlist.",
        songs: [],
      );
    }

    final pl = GeneratedPlaylist(
      success: true,
      mood: mood,
      title: 'Your Most Listened',
      description:
          'Your heavy rotation: the songs you replay and complete the most.',
      size: resultSongs.length,
      source: 'most_listened',
      songs: resultSongs,
    );
    _saveToSupabase(pl);
    return pl;
  }

  static Future<GeneratedPlaylist?> _generateArtistDiscoveryPlaylist(
      String artistName, int size, String mood) async {
    try {
      final heardFilter = await _loadHeardHistory();

      final qEnc = Uri.encodeComponent(artistName);
      final sResp = await http.get(
        Uri.parse('$_deezerApi/search/artist?q=$qEnc&limit=1'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 4));

      if (sResp.statusCode == 200) {
        final sData = jsonDecode(sResp.body);
        final sList = sData['data'] as List? ?? [];
        if (sList.isNotEmpty) {
          final aId = sList[0]['id']?.toString();
          final aName = sList[0]['name']?.toString() ?? artistName;
          if (aId != null) {
            final unplayed = <Map<String, dynamic>>[];
            final seenKeys = <String>{};

            // 1. Fetch artist top tracks
            final topResp = await http
                .get(Uri.parse('$_deezerApi/artist/$aId/top?limit=50'))
                .timeout(const Duration(seconds: 5));
            if (topResp.statusCode == 200) {
              final topData = jsonDecode(topResp.body);
              final topList = (topData['data'] as List? ?? [])
                  .whereType<Map<String, dynamic>>()
                  .where((t) => t['readable'] != false)
                  .toList();
              for (final item in topList) {
                final t = SearchResult.fromDeezerTrack(item);
                final tLower = t.title.toLowerCase().trim();
                final key = '$tLower|${t.artist.toLowerCase()}';
                final isHeard = heardFilter.isHeard(
                  title: t.title,
                  artist: t.artist,
                  trackId: t.id,
                );
                if (!isHeard && seenKeys.add(key)) {
                  unplayed.add({
                    'title': t.title,
                    'artist': aName,
                    'artistId': t.artistId,
                    'artistImage': t.artistImage,
                    'image': t.image,
                    'duration': t.duration,
                    'deezerId': t.id,
                    'previewUrl': t.previewUrl,
                    'source': 'discovery',
                  });
                }
              }
            }

            // 2. If under size, crawl albums
            if (unplayed.length < size) {
              try {
                final albResp = await http
                    .get(Uri.parse('$_deezerApi/artist/$aId/albums?limit=25'))
                    .timeout(const Duration(seconds: 5));
                if (albResp.statusCode == 200) {
                  final albData = jsonDecode(albResp.body);
                  final albums = albData['data'] as List? ?? [];
                  for (final alb in albums) {
                    if (unplayed.length >= size) break;
                    final albId = alb['id']?.toString();
                    if (albId != null) {
                      final trkResp = await http
                          .get(Uri.parse(
                              '$_deezerApi/album/$albId/tracks?limit=25'))
                          .timeout(const Duration(seconds: 4));
                      if (trkResp.statusCode == 200) {
                        final trkData = jsonDecode(trkResp.body);
                        final tracksList = (trkData['data'] as List? ?? [])
                            .whereType<Map<String, dynamic>>()
                            .where((t) => t['readable'] != false)
                            .toList();
                        for (final item in tracksList) {
                          if (unplayed.length >= size) break;
                          final t = SearchResult.fromDeezerTrack(item);
                          final tLower = t.title.toLowerCase().trim();
                          final key = '$tLower|${t.artist.toLowerCase()}';
                          final isHeard = heardFilter.isHeard(
                            title: t.title,
                            artist: t.artist,
                            trackId: t.id,
                          );
                          if (!isHeard && seenKeys.add(key)) {
                            unplayed.add({
                              'title': t.title,
                              'artist': aName,
                              'artistId': t.artistId,
                              'artistImage': t.artistImage,
                              'image': t.image.isNotEmpty
                                  ? t.image
                                  : (alb['cover_medium'] ?? alb['cover'] ?? ''),
                              'duration': t.duration,
                              'deezerId': t.id,
                              'previewUrl': t.previewUrl,
                              'source': 'discovery',
                            });
                          }
                        }
                      }
                    }
                  }
                }
              } catch (_) {}
            }

            if (unplayed.isNotEmpty) {
              final discPlaylist = GeneratedPlaylist(
                success: true,
                mood: mood,
                title: '$aName: Unheard Tracks',
                description:
                    'Fresh songs by $aName outside your listening history',
                size: unplayed.take(size).length,
                source: 'discovery',
                songs: unplayed.take(size).toList(),
              );
              _saveToSupabase(discPlaylist);
              return discPlaylist;
            }
          }
        }
      }
    } catch (e) {
      print('[Generate] Discovery playlist generation error: $e');
    }
    return null;
  }

  static Future<GeneratedPlaylist> _generateMultiArtistPlaylist(
      List<String> artistNames, int size, String mood) async {
    final songsPerArtist = (size / artistNames.length).ceil();
    final allTracks = <Map<String, dynamic>>[];
    final seen = <String>{};
    final resolvedNames = <String>[];

    // Pre-mapped Deezer artist IDs for known superstars to avoid name-collision
    final directArtistIds = {
      'Eve': '69128312',
      'いぶ': '69128312',
      'VannDa': '70151012',
      'Suly Pheng': '108107492',
      'Sinn Sisamouth': '5846489',
      'Ros Sereysothea': '5860073',
      'Preap Sovath': '113986772',
      'Sokun Nisa': '79109922',
      'Kmeng Khmer': '95515032',
      'G-Devith': '11624634',
      'Khem': '5857216',
      'Reth Suzana': '12808064',
      'Chhay Virakyuth': '13567757',
      'Khemarak Sereymun': '13567759',
      'Meas Soksophea': '13567761',
      'Aok Sokunkanha': '13567763',
      'Heng Pitu': '14800669',
      'Tep Boprek': '13567765',
      'Pich Sophea': '13567767',
      'Manith': '108107482',
      'Ny Rattana': '13567771',
      'Pen Ron': '5860075',
      'Yol Aularong': '5860077',
      'Noy Vanneth': '5860079',
      'Meng Keo Pichenda': '5860081',
      'Him Sivorn': '5860083',
      'Touch Sunnix': '5860085',
      'SmallWorld SmallBand': '11776994',
    };

    final lowerMood = mood.toLowerCase();
    final isOldies = RegExp(
            r'(បទ[\s]*ចាស់|ចាស់[\s]*ចាស់|ចាស់ៗ|old\s*songs|older\s*songs|classics|early)',
            caseSensitive: false)
        .hasMatch(lowerMood);
    final isNewHits = RegExp(
            r'(បទ[\s]*ថ្មី|ថ្មី[\s]*ថ្មី|ថ្មីៗ|new\s*songs|newer\s*songs|latest)',
            caseSensitive: false)
        .hasMatch(lowerMood);

    for (final rawName in artistNames) {
      try {
        String? aId;
        String name = rawName;

        // If rawName is already a numeric Deezer ID (passed directly from an artist chip)
        if (RegExp(r'^\d+$').hasMatch(rawName)) {
          aId = rawName;
          try {
            final aInfoResp = await http.get(
              Uri.parse('$_deezerApi/artist/$aId'),
              headers: {'Accept': 'application/json'},
            ).timeout(const Duration(seconds: 4));
            if (aInfoResp.statusCode == 200) {
              final aInfo = jsonDecode(aInfoResp.body);
              if (aInfo['name'] != null) {
                name = aInfo['name'].toString();
              }
            }
          } catch (_) {}
        } else {
          aId = directArtistIds[name];
          if (aId == null) {
            final query = Uri.encodeComponent(name);
            final aResp = await http.get(
              Uri.parse('$_deezerApi/search/artist?q=$query&limit=3'),
              headers: {'Accept': 'application/json'},
            ).timeout(const Duration(seconds: 6));

            if (aResp.statusCode == 200) {
              final aData = jsonDecode(aResp.body);
              final aList = aData['data'] as List? ?? [];
              if (aList.isNotEmpty) {
                aId = aList[0]['id']?.toString();
                if (aList[0]['name'] != null) {
                  name = aList[0]['name'].toString();
                }
              }
            }
          }
        }

        if (aId != null) {
          if (aId == '69128312') {
            final eveTop =
                await ArtistService.getArtistTopTracks('69128312', limit: 50);
            int addedForEve = 0;
            for (final t in eveTop) {
              if (addedForEve >= songsPerArtist) break;
              if (t.id.isEmpty || t.id == '0') continue;
              final key = '${t.title.toLowerCase()}|${t.artist.toLowerCase()}';
              if (seen.add(key)) {
                allTracks.add({
                  'title': t.title,
                  'artist': t.artist,
                  'artistId': t.artistId,
                  'artistImage': t.artistImage,
                  'image': t.image,
                  'duration': t.duration,
                  'deezerId': t.id,
                  'previewUrl': t.previewUrl,
                  'source': 'artist',
                });
                addedForEve++;
              }
            }
            continue;
          }

          final topResp = await http
              .get(
                Uri.parse('$_deezerApi/artist/$aId/top?limit=50'),
              )
              .timeout(const Duration(seconds: 6));

          if (topResp.statusCode == 200) {
            final topData = jsonDecode(topResp.body);
            var topList = (topData['data'] as List? ?? [])
                .whereType<Map<String, dynamic>>()
                .where((t) =>
                    t['readable'] != false &&
                    (t['id']?.toString() ?? '').isNotEmpty)
                .toList();

            // If user asked for older songs specifically, reverse to pick deeper/earlier releases
            if (isOldies && topList.length > songsPerArtist) {
              topList = topList.reversed.toList();
            }

            int addedForArtist = 0;
            for (final item in topList) {
              if (addedForArtist >= songsPerArtist) break;
              final t = SearchResult.fromDeezerTrack(item);
              if (t.id.isEmpty || t.id == '0') continue;
              final key = '${t.title.toLowerCase()}|${t.artist.toLowerCase()}';
              if (seen.add(key)) {
                allTracks.add({
                  'title': t.title,
                  'artist': t.artist,
                  'artistId': t.artistId,
                  'artistImage': t.artistImage,
                  'image': t.image,
                  'duration': t.duration,
                  'deezerId': t.id,
                  'previewUrl': t.previewUrl,
                  'source': 'artist',
                });
                addedForArtist++;
              }
            }

            // Also crawl ALL albums and EPs for this artist to collect every track
            if (allTracks
                    .where((t) =>
                        (t['artist'] ?? '').toString().toLowerCase().trim() ==
                        name.toLowerCase().trim())
                    .length <
                songsPerArtist) {
              try {
                final albResp = await http.get(
                  Uri.parse('$_deezerApi/artist/$aId/albums?limit=50'),
                  headers: {'Accept': 'application/json'},
                ).timeout(const Duration(seconds: 6));
                if (albResp.statusCode == 200) {
                  final albData = jsonDecode(albResp.body);
                  final albums = albData['data'] as List? ?? [];
                  for (final alb in albums) {
                    if (allTracks
                            .where((t) =>
                                (t['artist'] ?? '')
                                    .toString()
                                    .toLowerCase()
                                    .trim() ==
                                name.toLowerCase().trim())
                            .length >=
                        songsPerArtist) break;
                    final albId = alb['id']?.toString();
                    if (albId != null) {
                      final trkResp = await http.get(
                        Uri.parse('$_deezerApi/album/$albId/tracks?limit=50'),
                        headers: {'Accept': 'application/json'},
                      ).timeout(const Duration(seconds: 5));
                      if (trkResp.statusCode == 200) {
                        final trkData = jsonDecode(trkResp.body);
                        final tracksList = (trkData['data'] as List? ?? [])
                            .whereType<Map<String, dynamic>>()
                            .where((t) =>
                                t['readable'] != false &&
                                (t['id']?.toString() ?? '').isNotEmpty)
                            .toList();
                        for (final item in tracksList) {
                          if (allTracks
                                  .where((t) =>
                                      (t['artist'] ?? '')
                                          .toString()
                                          .toLowerCase()
                                          .trim() ==
                                      name.toLowerCase().trim())
                                  .length >=
                              songsPerArtist) break;
                          final t = SearchResult.fromDeezerTrack(item);
                          if (t.id.isEmpty || t.id == '0') continue;
                          final itemArtist = t.artist.toLowerCase().trim();
                          final targetArtist = name.toLowerCase().trim();
                          final isExact = itemArtist == targetArtist ||
                              itemArtist == '$targetArtist cambodia' ||
                              itemArtist.startsWith('$targetArtist feat') ||
                              itemArtist.startsWith('$targetArtist x ') ||
                              itemArtist.startsWith('$targetArtist & ');
                          if (isExact) {
                            final key =
                                '${t.title.toLowerCase()}|${t.artist.toLowerCase()}';
                            if (seen.add(key)) {
                              allTracks.add({
                                'title': t.title,
                                'artist': t.artist,
                                'artistId': t.artistId,
                                'artistImage': t.artistImage,
                                'image': t.image.isNotEmpty
                                    ? t.image
                                    : (alb['cover_medium'] ??
                                        alb['cover'] ??
                                        ''),
                                'duration': t.duration,
                                'deezerId': t.id,
                                'previewUrl': t.previewUrl,
                                'source': 'artist',
                              });
                            }
                          }
                        }
                      }
                    }
                  }
                }
              } catch (_) {}
            }
          }
        }

        // If artist top tracks yielded no items or fewer than requested, search for tracks specifically with artist:"Name"
        final countForArtist = allTracks
            .where((t) =>
                (t['artist'] ?? '').toString().toLowerCase().trim() ==
                name.toLowerCase().trim())
            .length;
        if (countForArtist < songsPerArtist) {
          final isCuratedKhmer = directArtistIds.containsKey(name);
          final queries = isCuratedKhmer
              ? ['artist:"$name"']
              : ['artist:"$name"', name, 'album:"$name"'];
          for (final qStr in queries) {
            if (allTracks
                    .where((t) =>
                        (t['artist'] ?? '').toString().toLowerCase().trim() ==
                        name.toLowerCase().trim())
                    .length >=
                songsPerArtist) break;
            final tQuery = Uri.encodeComponent(qStr);
            final tResp = await http.get(
              Uri.parse('$_deezerApi/search?q=$tQuery&limit=100'),
              headers: {'Accept': 'application/json'},
            ).timeout(const Duration(seconds: 6));
            if (tResp.statusCode == 200) {
              final tData = jsonDecode(tResp.body);
              var tList = (tData['data'] as List? ?? [])
                  .whereType<Map<String, dynamic>>()
                  .where((t) =>
                      t['readable'] != false &&
                      (t['id']?.toString() ?? '').isNotEmpty)
                  .toList();
              if (isOldies && tList.length > songsPerArtist) {
                tList = tList.reversed.toList();
              }
              for (final item in tList) {
                final t = SearchResult.fromDeezerTrack(item);
                if (t.id.isEmpty || t.id == '0') continue;
                final itemArtist = t.artist.toLowerCase().trim();
                final targetArtist = name.toLowerCase().trim();

                // Strict exact match: ensure artist matches target and if aId is known, verify artistId matches
                final artistIdMatches =
                    (aId == null || t.artistId.isEmpty || t.artistId == aId);
                final isExactMatch = artistIdMatches &&
                    (itemArtist == targetArtist ||
                        itemArtist == '$targetArtist cambodia' ||
                        itemArtist.startsWith('$targetArtist feat') ||
                        itemArtist.startsWith('$targetArtist x ') ||
                        itemArtist.startsWith('$targetArtist & ') ||
                        itemArtist.startsWith('$targetArtist,'));

                if (isExactMatch) {
                  final key =
                      '${t.title.toLowerCase()}|${t.artist.toLowerCase()}';
                  if (seen.add(key)) {
                    allTracks.add({
                      'title': t.title,
                      'artist': t.artist,
                      'artistId': t.artistId,
                      'artistImage': t.artistImage,
                      'image': t.image,
                      'duration': t.duration,
                      'deezerId': t.id,
                      'previewUrl': t.previewUrl,
                      'source': 'artist',
                    });
                    if (allTracks
                            .where((x) =>
                                (x['artist'] ?? '')
                                    .toString()
                                    .toLowerCase()
                                    .trim() ==
                                name.toLowerCase().trim())
                            .length >=
                        songsPerArtist) break;
                  }
                }
              }
            }
          }
        }

        if (name.isNotEmpty && !resolvedNames.contains(name)) {
          resolvedNames.add(name);
        }
      } catch (e) {
        print('[Generate] Multi-artist fetch error for $rawName: $e');
      }
    }

    // Backfill from other verified Khmer artists if under requested size
    if (allTracks.length < size && _isKhmerMusicRequest(mood)) {
      final fallbackKhmerArtists = directArtistIds.keys.toList()..shuffle();
      for (final fbArtist in fallbackKhmerArtists) {
        if (allTracks.length >= size) break;
        final fbId = directArtistIds[fbArtist];
        if (fbId == null) continue;
        try {
          final topResp = await http
              .get(Uri.parse('$_deezerApi/artist/$fbId/top?limit=10'))
              .timeout(const Duration(seconds: 4));
          if (topResp.statusCode == 200) {
            final topData = jsonDecode(topResp.body);
            final topList = (topData['data'] as List? ?? [])
                .whereType<Map<String, dynamic>>()
                .where((t) =>
                    t['readable'] != false &&
                    (t['id']?.toString() ?? '').isNotEmpty);
            for (final item in topList) {
              if (allTracks.length >= size) break;
              final t = SearchResult.fromDeezerTrack(item);
              if (t.id.isEmpty || t.id == '0') continue;
              final key = '${t.title.toLowerCase()}|${t.artist.toLowerCase()}';
              if (seen.add(key)) {
                allTracks.add({
                  'title': t.title,
                  'artist': t.artist,
                  'artistId': t.artistId,
                  'artistImage': t.artistImage,
                  'image': t.image,
                  'duration': t.duration,
                  'deezerId': t.id,
                  'previewUrl': t.previewUrl,
                  'source': 'khmer_backfill',
                });
              }
            }
          }
        } catch (_) {}
      }
    }
    // Smart interleave & randomize: prevent consecutive songs from the same artist
    final byArtist = <String, List<Map<String, dynamic>>>{};
    for (final t in allTracks) {
      final a = (t['artist'] ?? '').toString().toLowerCase();
      byArtist.putIfAbsent(a, () => []).add(t);
    }
    // Randomize internal song order per artist slightly while keeping top hits early
    for (final list in byArtist.values) {
      if (list.length > 2) {
        // Keep absolute #1 hit, shuffle the rest
        final top = list.first;
        final rest = list.sublist(1)..shuffle();
        list
          ..clear()
          ..add(top)
          ..addAll(rest);
      }
    }
    final interleaved = <Map<String, dynamic>>[];
    int round = 0;
    bool added = true;
    while (added && interleaved.length < size) {
      added = false;
      final artistKeys = byArtist.keys.toList()..shuffle();
      for (final k in artistKeys) {
        final list = byArtist[k]!;
        if (round < list.length && interleaved.length < size) {
          interleaved.add(list[round]);
          added = true;
        }
      }
      round++;
    }

    // If total interleaved tracks is still under requested size, fill remaining slots with top popular tracks from allTracks
    if (interleaved.length < size) {
      final remainingPool = List<Map<String, dynamic>>.from(allTracks)
        ..shuffle();
      for (final t in remainingPool) {
        if (interleaved.length >= size) break;
        final key = '${t['title'].toLowerCase()}|${t['artist'].toLowerCase()}';
        final alreadyIn = interleaved.any((x) =>
            '${x['title'].toLowerCase()}|${x['artist'].toLowerCase()}' == key);
        if (!alreadyIn) {
          interleaved.add(t);
        }
      }
    }

    final cleanNames = resolvedNames.isNotEmpty ? resolvedNames : artistNames;
    final title = cleanNames.join(' & ') + ' Playlist';
    final playlist = GeneratedPlaylist(
      success: interleaved.isNotEmpty,
      mood: mood,
      title: title,
      description: 'The best songs from ${cleanNames.join(' and ')}',
      size: interleaved.length,
      source: 'artist',
      songs: interleaved,
    );

    if (interleaved.isNotEmpty) {
      _saveToSupabase(playlist);
    }

    return playlist;
  }

  /// Retrieves the user's followed & favorite artists from local cache and Supabase
  static Future<List<String>> _loadUserFavoriteArtists() async {
    final artists = <String>{};
    // 1. In-memory & disk-cached followed artists from ArtistFollowService
    try {
      final followService = ArtistFollowService();
      if (!followService.loaded) {
        await followService.loadFollowedArtists();
      }
      for (final a in followService.followedArtists) {
        final name = (a['artist_name'] ?? a['name'] ?? '').toString().trim();
        if (name.isNotEmpty) artists.add(name);
      }
    } catch (_) {}

    // 2. Direct query to Supabase artist_follows table
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final rows = await Supabase.instance.client
            .from('artist_follows')
            .select('artist_name')
            .eq('user_id', user.id)
            .limit(100)
            .timeout(const Duration(seconds: 4));
        for (final r in rows) {
          final name = (r['artist_name'] ?? '').toString().trim();
          if (name.isNotEmpty) artists.add(name);
        }
      } catch (_) {}

      // 3. Profiles favorite_artists
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('favorite_artists')
            .eq('id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 4));
        if (profile != null) {
          final raw = profile['favorite_artists'] as List<dynamic>? ?? [];
          for (final a in raw) {
            final name = (a is Map ? a['name'] : a)?.toString().trim() ?? '';
            if (name.isNotEmpty) artists.add(name);
          }
        }
      } catch (_) {}
    }
    return artists.toList();
  }

  static Future<GeneratedPlaylist> _generateMoodPlaylist(String mood, int size,
      {List<String>? artistIds,
      List<String>? trackIds,
      void Function(int stage)? onStageChanged}) async {
    final lowerMood = mood.toLowerCase();
    final isLofiRequest = RegExp(r'\blo[\s-]?fi\b').hasMatch(lowerMood);
    final isAnimeOrJapanese = RegExp(
      r'(anime|japan|japanese|jpop|j-pop|jrock|j-rock|otaku|manga|jjk|jujutsu|opening|ending|ost|shibuya|tokyo|naruto|one piece|bleach|hero academia|chainsaw|anisong)',
      caseSensitive: false,
    ).hasMatch(lowerMood);

    final bool hasSpecificGenreOrTheme = isAnimeOrJapanese ||
        RegExp(
          r'\b(pop|rock|hip[\s-]?hop|rap|r&b|rnb|jazz|classical|metal|country|edm|dance|lo[\s-]?fi|blues|punk|gospel|folk|indie|acoustic|sad|sleep|study|gym|workout|80s|90s|70s|60s|2000s|2010s|oldies|retro|vintage|soundtrack|ost|khmer|cambodia|kpop|k-pop|kdrama|ballad)\b',
          caseSensitive: false,
        ).hasMatch(lowerMood);

    final requestedYear =
        RegExp(r'\b(20\d{2})\b').firstMatch(lowerMood)?.group(1);

    // Only treat as live global chart request if the prompt is explicitly asking
    // for mainstream global charts and does NOT specify a genre, theme, anime, artist, or era.
    final isLiveGlobalChartRequest = !hasSpecificGenreOrTheme &&
        (artistIds == null || artistIds.isEmpty) &&
        RegExp(
          r'\b(billboard|global\s+chart|top\s+50|charts?|chart\s*toppers?|today.?s\s+top\s+hits|top\s+hits\s+today|hits?\s+now|current\s+chart|trending\s+worldwide)\b',
          caseSensitive: false,
        ).hasMatch(lowerMood);

    // ----------------------------------------------------
    // PASS 1: SEMANTIC INTENT & MUSICAL DECONSTRUCTION
    // Transforms natural prompt (English/Khmer/slang) into structured musical DNA
    // ----------------------------------------------------
    onStageChanged
        ?.call(0); // Stage 0: Understanding your mood & analyzing intent

    final bool promptAsksFavoriteArtists = RegExp(
      r'(?:my\s*(?:fav(?:orite)?|followed|top|loved)?\s*(?:artists?|singers?|bands?)|(?:artists?|singers?|bands?)\s*(?:i|that\s*i)\s*(?:follow|like|love|listen\s*to)|my\s*favorites?)',
      caseSensitive: false,
    ).hasMatch(mood);

    final bool promptAsksUnheard = RegExp(
      r'(haven.?t\s*(?:listen|heard)|never\s*(?:listen|heard)|unheard|not\s*in\s*my\s*history|discover|new\s*to\s*me|not\s*heard|didn.?t\s*(?:listen|hear)|did\s*not\s*(?:listen|hear)|don.?t\s*know|doesn.?t\s*know|not\s*listened|i\s*don.?t\s*know|មិន\s*ដែល\s*ស្តាប់)',
      caseSensitive: false,
    ).hasMatch(mood);

    final bool promptAsksTaste = RegExp(
      r'\b(my\s*taste|based\s*on\s*my\s*taste|music\s*i\s*like|my\s*preferences|my\s*vibe\s*profile|ចំណូលចិត្តខ្ញុំ)\b',
      caseSensitive: false,
    ).hasMatch(mood);

    final bool promptExcludesFollowed = RegExp(
      r'(?:exclude|without|don.?t\s*include|no)\s+(?:my\s+)?(?:favorite|followed|fav)?\s*artists?',
      caseSensitive: false,
    ).hasMatch(mood);

    final user = Supabase.instance.client.auth.currentUser;
    // Pass 1: Parse intent from prompt text first without polluting AI with unrequested data
    PromptIntent? intent = await GroqService.deconstructPromptIntent(mood);
    intent ??= await GeminiService.deconstructPromptIntent(mood);
    final initialIntent = intent;

    // Determine precisely which personal data slices are needed (STRICTLY OPT-IN)
    final bool needsFavArtists =
        (promptAsksFavoriteArtists || intent?.needsFavoriteArtists == true) &&
            !promptExcludesFollowed;
    final bool isUnheardOnly = promptAsksUnheard ||
        initialIntent?.unheardOnly == true ||
        intent?.unheardOnly == true;
    final bool needsTaste =
        promptAsksTaste || intent?.needsTasteProfile == true;
    final bool excludeFollowed =
        promptExcludesFollowed || intent?.excludeFollowedArtists == true;

    final userFavoriteArtists = <String>[];
    String userContextForAi = '';

    // 1. Load favorite artists ONLY if the user explicitly asked for their favorite artists
    if (needsFavArtists) {
      final loaded = await _loadUserFavoriteArtists();
      userFavoriteArtists.addAll(loaded);
      if (userFavoriteArtists.isNotEmpty) {
        userContextForAi +=
            'USER FAVORITE ARTISTS: ${userFavoriteArtists.join(', ')}\n';
        print(
            '[Generate] Loaded ${userFavoriteArtists.length} user favorite artists: $userFavoriteArtists');
      }
    }

    // 2. Load listening history filter ONLY if user requested unheard/unplayed tracks
    final heardFilter =
        isUnheardOnly ? await _loadHeardHistory() : HeardHistoryFilter();

    // 3. Load taste profile ONLY if user explicitly requested their taste in the prompt
    final profileGenresList = <String>[];
    final userDislikedArtists = <String>{};

    if (needsTaste && user != null) {
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('favorite_genres')
            .eq('id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 4));
        if (profile != null) {
          final rawGenres =
              (profile['favorite_genres'] as List<dynamic>?) ?? [];
          for (final g in rawGenres) {
            final str = g?.toString().trim() ?? '';
            if (str.isNotEmpty) profileGenresList.add(str);
          }
          if (profileGenresList.isNotEmpty) {
            userContextForAi +=
                'PREFERRED GENRES: ${profileGenresList.join(', ')}\n';
          }
        }
        final tasteRows = await Supabase.instance.client
            .from('user_taste_profiles')
            .select('recommend_more, recommend_less')
            .eq('user_id', user.id)
            .limit(10)
            .timeout(const Duration(seconds: 4));
        if (tasteRows.isNotEmpty) {
          final more = <String>{};
          for (final row in tasteRows.whereType<Map>()) {
            final rMore = row['recommend_more'] as List?;
            final rLess = row['recommend_less'] as List?;
            if (rMore != null) {
              more.addAll(rMore
                  .map((e) => e.toString().trim())
                  .where((s) => s.isNotEmpty));
            }
            if (rLess != null) {
              userDislikedArtists.addAll(rLess
                  .map((e) => e.toString().trim())
                  .where((s) => s.isNotEmpty));
            }
          }
          if (more.isNotEmpty) {
            userContextForAi += 'USER FAVORITE ARTISTS TO WEAVE IN: ${more.take(6).join(', ')}\n';
          }
          if (userDislikedArtists.isNotEmpty) {
            userContextForAi += 'RECOMMEND LESS: ${userDislikedArtists.take(10).join(', ')}\n';
          }
        }
      } catch (_) {}
    }


    // If favorite artists were loaded, re-run intent deconstruction so the AI anchors them!
    if (needsFavArtists && userFavoriteArtists.isNotEmpty) {
      final personalizedIntent = await GroqService.deconstructPromptIntent(
        mood,
        userProfileContext: userContextForAi,
      );
      intent = personalizedIntent ?? intent;
    }

    print(
        '[Generate] Deconstructed intent: ${intent?.intentType ?? "FALLBACK"} | Summary: "${intent?.summary ?? mood}"');

    // Build taste context for curator (ONLY what was asked for)
    String tasteContext = userContextForAi.isEmpty
        ? ''
        : 'USER EXPLICIT CONTEXT:\n$userContextForAi\n';
    if (isUnheardOnly) {
      tasteContext +=
          '\nHARD CONSTRAINT: Select ONLY songs the user has NOT heard before from the candidate pool.\n';
    }

    // Excluded artists resolution
    final excludedArtistNames = <String>{};
    if (userDislikedArtists.isNotEmpty) {
      excludedArtistNames
          .addAll(userDislikedArtists.map((a) => a.toLowerCase().trim()));
    }
    if (excludeFollowed) {
      final userArtists = await _loadUserFavoriteArtists();
      excludedArtistNames
          .addAll(userArtists.map((a) => a.toLowerCase().trim()));
    }
    if (intent != null && intent.excludedArtists.isNotEmpty) {
      excludedArtistNames
          .addAll(intent.excludedArtists.map((a) => a.toLowerCase().trim()));
    }

    bool isArtistExcluded(String artistName) {
      if (artistName.isEmpty) return false;
      final clean = artistName.toLowerCase().trim();
      for (final ex in excludedArtistNames) {
        if (clean == ex || clean.contains(ex) || ex.contains(clean))
          return true;
      }
      return false;
    }

    final genWatch = Stopwatch()..start();
    onStageChanged
        ?.call(1); // Stage 1: Multi-Anchor Retrieval from Streaming Catalog

    // ----------------------------------------------------
    // PASS 2: MULTI-ANCHOR PARALLEL RETRIEVAL
    // Build 60-120 real streamable candidates using verified musical anchors
    // ----------------------------------------------------
    final detectedValence = detectEmotionalValence(mood, intent);
    final bool userAllowsAcoustic =
        RegExp(r'\b(acoustic|unplugged)\b', caseSensitive: false).hasMatch(mood);
    final bool userAllowsCover = RegExp(
            r'\b(cover|tribute|orchestra|ensemble)\b',
            caseSensitive: false)
        .hasMatch(mood);
    final bool userAllowsLive = RegExp(
            r'\b(live|concert|tour|recorded\s*live|en\s*vivo)\b',
            caseSensitive: false)
        .hasMatch(mood);
    final bool userAllowsInstrumental = RegExp(
            r'\b(instrumental|karaoke|backing\s*track|lofi|chillhop|beats|ambient|piano)\b',
            caseSensitive: false)
        .hasMatch(mood) || isLofiRequest;
    final bool userAllowsRemix = RegExp(
            r'\b(remix|remixes|club\s*mix|edm|techno|dance\s*mix)\b',
            caseSensitive: false)
        .hasMatch(mood);
    print(
        '[Generate] Detected emotional valence: $detectedValence | userAllowsAcoustic=$userAllowsAcoustic | userAllowsCover=$userAllowsCover | userAllowsLive=$userAllowsLive | userAllowsInstrumental=$userAllowsInstrumental | userAllowsRemix=$userAllowsRemix');

    final candidatePool = <Map<String, dynamic>>[];
    final seenKeys = <String>{};
    final seenCoreKeys = <String>{};
    var liveChartLoaded = false;

    void addCandidate(SearchResult t, {String source = 'semantic_candidate'}) {
      if (t.id.isEmpty || t.title.isEmpty || t.artist.isEmpty) return;
      if (isArtistExcluded(t.artist)) return;
      final tLower = t.title.toLowerCase().trim();
      final aLower = t.artist.toLowerCase().trim();
      final key = '$tLower|$aLower';

      // Block cover bands, tribute acts, student ensembles, karaoke, unwanted live/instrumentals/remixes
      if (isCoverOrTributeTrack(
        artist: t.artist,
        title: t.title,
        allowEnsembleOrCover: userAllowsCover,
        allowLive: userAllowsLive,
        allowInstrumental: userAllowsInstrumental,
        allowRemix: userAllowsRemix,
      )) {
        return;
      }

      // Strict emotional valence filtering (zero sad songs in happy playlists)
      if (isTrackValenceMismatched(
        title: t.title,
        artist: t.artist,
        requestedValence: detectedValence,
        allowAcoustic: userAllowsAcoustic,
      )) {
        return;
      }

      // Block American rapper Eve (837) from anime/Japanese requests
      if (isAnimeOrJapanese) {
        if (t.artistId == '837') return;
        if (aLower == 'eve') {
          if (tLower.contains('blow ya mind') ||
              tLower.contains("who's that girl") ||
              tLower.contains('gangsta lovin') ||
              tLower.contains('what you need') ||
              tLower.contains('tambourine') ||
              tLower.contains('rich girl')) {
            return;
          }
        }
      }

      // Core song deduplication: prevent different cuts/remixes/soundtracks of the exact same song
      // (e.g. "Happy", "Happy (Live)", "Happy (From Despicable Me 2)", "Happy - Remix")
      // from flooding the candidate pool.
      final cTitle = HeardHistoryFilter.cleanTitle(t.title);
      final cArtist = HeardHistoryFilter.cleanArtist(t.artist);
      final coreKey = '$cTitle|$cArtist';
      if (cTitle.isNotEmpty && seenCoreKeys.contains(coreKey)) {
        return;
      }

      // If user requested unheard only, strictly exclude already heard songs
      if (isUnheardOnly &&
          heardFilter.isHeard(
            title: t.title,
            artist: t.artist,
            trackId: t.id,
          )) {
        return;
      }

      if (seenKeys.add(key)) {
        if (cTitle.isNotEmpty) seenCoreKeys.add(coreKey);
        candidatePool.add({
          'title': t.title,
          'artist': t.artist,
          'artistId': t.artistId,
          'artistImage': t.artistImage,
          'image': t.image,
          'duration': t.duration,
          'deezerId': t.id,
          'previewUrl': t.previewUrl,
          'source': source,
        });
      }
    }

    // Seed pool from Deezer's live global chart ONLY if the prompt is specifically
    // a global mainstream chart request without a genre or theme.
    if (isLiveGlobalChartRequest) {
      try {
        final chartResponse = await http.get(
          Uri.parse('$_deezerApi/chart/0/tracks?limit=50'),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 5));
        if (chartResponse.statusCode == 200) {
          liveChartLoaded = true;
          final chartData = jsonDecode(chartResponse.body);
          final rawChartTracks = (chartData['data'] as List? ?? [])
              .whereType<Map<String, dynamic>>()
              .where((track) => track['readable'] != false)
              .toList();

          // A chart reflects what is popular today, but older songs can trend
          // again. For an explicit year ("popular songs in 2026"), verify the
          // album release date before allowing a chart track into the pool.
          final yearMatchedTracks = requestedYear == null
              ? rawChartTracks
              : (await Future.wait(rawChartTracks.map((track) async {
                  try {
                    final albumId =
                        (track['album'] as Map?)?['id']?.toString() ?? '';
                    if (albumId.isEmpty) return null;
                    final albumResponse = await http
                        .get(Uri.parse('$_deezerApi/album/$albumId'), headers: {
                      'Accept': 'application/json'
                    }).timeout(const Duration(seconds: 4));
                    if (albumResponse.statusCode != 200) return null;
                    final album = jsonDecode(albumResponse.body);
                    final releaseDate = album['release_date']?.toString() ?? '';
                    return releaseDate.startsWith(requestedYear) ? track : null;
                  } catch (_) {
                    return null;
                  }
                })))
                  .whereType<Map<String, dynamic>>()
                  .toList();

          for (final rawTrack in yearMatchedTracks) {
            final track = SearchResult.fromDeezerTrack(rawTrack);
            addCandidate(track, source: 'live_chart');
          }
        }
      } catch (_) {
        // Keep the normal catalog path available if the live chart is down.
      }
    }

    final explicitUserArtists = <String>{};
    final explicitUserArtistIds = <String>{};
    final anchorArtists = <String>{};
    final anchorArtistIds = <String>{};

    // 1. Explicit artist chips / artist IDs from UI
    if (artistIds != null && artistIds.isNotEmpty) {
      for (final id in artistIds) {
        final trimmed = id.trim();
        if (trimmed.isNotEmpty) {
          if (RegExp(r'^\d+$').hasMatch(trimmed)) {
            anchorArtistIds.add(trimmed);
            explicitUserArtistIds.add(trimmed);
          } else if (!isArtistExcluded(trimmed)) {
            anchorArtists.add(trimmed);
            explicitUserArtists.add(trimmed);
          }
        }
      }
    }

    // 2. Artists extracted from prompt header "Artists: X, Y" (handles multiple refined turns)
    final artistHeaderMatches =
        RegExp(r'Artists?:\s*([^|\.\n]+)', caseSensitive: false)
            .allMatches(mood);
    for (final match in artistHeaderMatches) {
      final rawNames = match.group(1) ?? '';
      for (final name in rawNames.split(',')) {
        final trimmed = name.trim();
        if (trimmed.isNotEmpty) {
          if (RegExp(r'^\d+$').hasMatch(trimmed)) {
            anchorArtistIds.add(trimmed);
            explicitUserArtistIds.add(trimmed);
          } else if (!isArtistExcluded(trimmed)) {
            anchorArtists.add(trimmed);
            explicitUserArtists.add(trimmed);
          }
        }
      }
    }

    // 3. Artists from AI intent analysis (ONLY if user did not specifically ask for their favorite artists)
    if (!needsFavArtists && intent != null && intent.anchorArtists.isNotEmpty) {
      for (final a in intent.anchorArtists) {
        final trimmed = a.trim();
        if (trimmed.isNotEmpty && !isArtistExcluded(trimmed)) {
          anchorArtists.add(trimmed);
          final aLower = trimmed.toLowerCase();
          if (aLower.length >= 3 && lowerMood.contains(aLower)) {
            explicitUserArtists.add(trimmed);
          }
        }
      }
    }

    // 4. In personalized requests where user explicitly asked for their favorite artists, inject them as the exclusive anchors!
    if (needsFavArtists && userFavoriteArtists.isNotEmpty) {
      anchorArtists.clear();
      // Keep explicit artist chips from UI if any
      if (artistIds != null) {
        for (final id in artistIds) {
          final trimmed = id.trim();
          if (trimmed.isNotEmpty &&
              !RegExp(r'^\d+$').hasMatch(trimmed) &&
              !isArtistExcluded(trimmed)) {
            anchorArtists.add(trimmed);
          }
        }
      }
      for (final a in userFavoriteArtists) {
        if (a.isNotEmpty && !isArtistExcluded(a)) {
          anchorArtists.add(a);
        }
      }
    }

    // 5. In unheard music discovery where no specific artist was named, anchor directly to the user's top history artists & followed artists
    if (isUnheardOnly &&
        (anchorArtists.isEmpty && anchorArtistIds.isEmpty ||
            intent?.intentType == 'PERSONALIZED_DISCOVERY')) {
      final historyArtists = heardFilter.topHistoryArtists;
      final followedArtists = await _loadUserFavoriteArtists();
      if (historyArtists.isNotEmpty || followedArtists.isNotEmpty) {
        anchorArtists.clear();
        for (final a in historyArtists.take(10)) {
          if (!isArtistExcluded(a)) {
            anchorArtists.add(a);
          }
        }
        for (final a in followedArtists.take(6)) {
          if (!isArtistExcluded(a)) {
            anchorArtists.add(a);
          }
        }
        print(
            '[Generate] Unheard discovery anchored to ${anchorArtists.length} user history & followed artists: $anchorArtists');
      }
    }

    final dedicatedAnchorTracks = <String, List<Map<String, dynamic>>>{};

    try {
      final searchQueries = <String>{};

      // An explicitly named genre is a requirement, not a loose mood. Deezer
      // search results for generic "playlist" wording can otherwise contain
      // pop or unrelated instrumental tracks.
      if (isLofiRequest) {
        searchQueries.addAll(const [
          'lofi hip hop',
          'lo-fi beats',
          'lofi study beats',
          'chillhop instrumental',
        ]);
      }
      if (isAnimeOrJapanese) {
        searchQueries.addAll(const [
          'Anime Hits',
          'Anime Openings',
          'Anime Essentials',
          'Anisong',
          'Popular Anime Songs',
        ]);
      }

      // 1. Add specific catalog queries from intent deconstruction (skip generic AI queries if user asked for their favorite artists or unheard discovery)
      if (!needsFavArtists &&
          !isUnheardOnly &&
          intent != null &&
          intent.catalogQueries.isNotEmpty) {
        for (final q in intent.catalogQueries) {
          final qLower = q.toLowerCase().trim();
          // Filter out raw emotion or activity phrases that cause Deezer to return low-quality literal title matches
          final isLiteralMoodOrActivity = RegExp(
            r'^(?:happy|energetic|sad|sad\s*songs?|feel\s*good|chill|mood|vibe|hype|depressing|upbeat|crying|shower|bath|showering|gym|workout|lifting|cooking|cook|dinner|study|studying|sleep|sleeping|drive|driving|run|running|clean|cleaning|game|gaming|relax|relaxing)\s*$',
            caseSensitive: false,
          ).hasMatch(qLower);
          if (!isLiteralMoodOrActivity) {
            searchQueries.add(q);
          }
        }
      }

      // 2. Add queries for all anchor artists
      for (final artist in anchorArtists) {
        if (!isArtistExcluded(artist)) {
          searchQueries.add(artist);
          searchQueries.add('"$artist"');
        }
      }

      // Search preferred genres ONLY if user explicitly asked for their taste profile
      if (needsTaste) {
        for (final g in profileGenresList) {
          if (g.isNotEmpty) searchQueries.add(g);
        }
      }

      // 3. Add seed tracks
      final seedTracks = intent?.seedTracks ?? [];
      final trackHeaderMatch =
          RegExp(r'Tracks?:\s*([^|\.\n]+)', caseSensitive: false)
              .firstMatch(mood);
      if (trackHeaderMatch != null) {
        final rawTracks = trackHeaderMatch.group(1) ?? '';
        for (final t in rawTracks.split(',')) {
          final trimmed = t.replaceAll('"', '').trim();
          if (trimmed.isNotEmpty) searchQueries.add(trimmed);
        }
      }
      for (final trk in seedTracks) {
        searchQueries.add(trk);
      }

      // 4. Add fallback search queries if intent pool was sparse
      if (searchQueries.isEmpty) {
        final cleanQuery = mood
            .replaceAll(
                RegExp(
                    r'(playlist|songs?|make\s*a|give\s*me|plz|please|ចម្រៀង|ផ្លេលីស)',
                    caseSensitive: false),
                '')
            .trim();
        final isLiteralActivity = RegExp(
          r'^(?:shower|bath|showering|gym|workout|lifting|cooking|cook|dinner|study|studying|sleep|sleeping|drive|driving|run|running)\s*$',
          caseSensitive: false,
        ).hasMatch(cleanQuery);
        if (!isLiteralActivity) {
          searchQueries.add(mood.trim());
          if (cleanQuery.isNotEmpty) searchQueries.add(cleanQuery);
        } else {
          if (RegExp(r'\b(shower|bath)\b', caseSensitive: false).hasMatch(cleanQuery)) {
            searchQueries.addAll(['pop hits', 'feel good pop', 'Whitney Houston', 'Bruno Mars']);
          } else if (RegExp(r'\b(gym|workout|lifting)\b', caseSensitive: false).hasMatch(cleanQuery)) {
            searchQueries.addAll(['workout hits', 'Travis Scott', 'high energy phonk']);
          } else if (RegExp(r'\b(study|studying)\b', caseSensitive: false).hasMatch(cleanQuery)) {
            searchQueries.addAll(['lofi study beats', 'ambient chill']);
          } else if (RegExp(r'\b(cooking|cook|dinner)\b', caseSensitive: false).hasMatch(cleanQuery)) {
            searchQueries.addAll(['feel good funk', 'Leon Bridges', 'Tom Misch']);
          }
        }
      }

      // 5. Fire parallel catalog searches
      final searchFutures = searchQueries.map((q) async {
        try {
          final qEnc = Uri.encodeComponent(q);
          final resp = await http.get(
            Uri.parse('$_deezerApi/search?q=$qEnc&limit=25'),
            headers: {'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 4));

          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body);
            final items = (data['data'] as List? ?? [])
                .whereType<Map<String, dynamic>>()
                .where((t) => t['readable'] != false)
                .map((r) => SearchResult.fromDeezerTrack(r))
                .toList();
            return items;
          }
        } catch (_) {}
        return <SearchResult>[];
      });

      final totalAnchorsCount = anchorArtists.length + anchorArtistIds.length;
      final bool fetchRelated = (totalAnchorsCount <= 1) || isUnheardOnly;

      final idTopFutures = anchorArtistIds.map((aId) async {
        final List<SearchResult> artistResults = [];
        try {
          final isExplicit = explicitUserArtistIds.contains(aId);
          final limit = isUnheardOnly ? 25 : (isExplicit ? 25 : 10);
          final topResp = await http.get(
            Uri.parse('$_deezerApi/artist/$aId/top?limit=$limit'),
            headers: {'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 4));
          if (topResp.statusCode == 200) {
            final topData = jsonDecode(topResp.body);
            final items = (topData['data'] as List? ?? [])
                .whereType<Map<String, dynamic>>()
                .where((t) => t['readable'] != false)
                .map((r) => SearchResult.fromDeezerTrack(r))
                .toList();
            artistResults.addAll(items);
            for (final item in items) {
              if (isUnheardOnly &&
                  heardFilter.isHeard(
                    title: item.title,
                    artist: item.artist,
                    trackId: item.id,
                  )) {
                continue;
              }
              if (isCoverOrTributeTrack(
                artist: item.artist,
                title: item.title,
                allowEnsembleOrCover: userAllowsCover,
                allowLive: userAllowsLive,
                allowInstrumental: userAllowsInstrumental,
                allowRemix: userAllowsRemix,
              )) {
                continue;
              }
              if (isTrackValenceMismatched(
                title: item.title,
                artist: item.artist,
                requestedValence: detectedValence,
                allowAcoustic: userAllowsAcoustic,
              )) {
                continue;
              }
              final cTitle = HeardHistoryFilter.cleanTitle(item.title);
              final cArtist = HeardHistoryFilter.cleanArtist(item.artist);
              final coreKey = '$cTitle|$cArtist';
              final existingList = dedicatedAnchorTracks[aId] ?? [];
              if (cTitle.isNotEmpty && existingList.any((e) =>
                  '${HeardHistoryFilter.cleanTitle((e['title'] ?? '').toString())}|${HeardHistoryFilter.cleanArtist((e['artist'] ?? '').toString())}' ==
                  coreKey)) {
                continue;
              }
              final trackMap = {
                'title': item.title,
                'artist': item.artist,
                'artistId': item.artistId,
                'artistImage': item.artistImage,
                'image': item.image,
                'duration': item.duration,
                'deezerId': item.id,
                'previewUrl': item.previewUrl,
                'source': 'semantic_candidate',
              };
              dedicatedAnchorTracks.putIfAbsent(aId, () => []).add(trackMap);
            }
          }
        } catch (_) {}
        return artistResults;
      });

      final orderedAnchorArtists = [
        ...explicitUserArtists,
        ...anchorArtists.where((a) => !explicitUserArtists.contains(a)),
      ];

      final artistTopFutures =
          orderedAnchorArtists.take(isUnheardOnly ? 15 : 10).map((aName) async {
        final List<SearchResult> artistResults = [];
        try {
          String? aId;
          final aLower = aName.toLowerCase().trim();
          if (aLower == 'eve' || aLower == 'いぶ') {
            aId = '69128312';
          } else {
            final qEnc = Uri.encodeComponent(aName);
            final aResp = await http.get(
              Uri.parse('$_deezerApi/search/artist?q=$qEnc&limit=1'),
              headers: {'Accept': 'application/json'},
            ).timeout(const Duration(seconds: 4));
            if (aResp.statusCode == 200) {
              final aData = jsonDecode(aResp.body);
              final aList = aData['data'] as List? ?? [];
              if (aList.isNotEmpty) {
                aId = aList[0]['id']?.toString();
              }
            }
          }
          if (aId != null) {
            // 1. Get top tracks from the anchor artist (more tracks if explicitly requested)
            final isExplicit = explicitUserArtists.contains(aName);
            final limit = isUnheardOnly ? 25 : (isExplicit ? 25 : 10);
            List<SearchResult> items;
            if (aId == '69128312') {
              items = await ArtistService.getArtistTopTracks('69128312',
                  limit: limit);
            } else {
              final topResp = await http.get(
                Uri.parse('$_deezerApi/artist/$aId/top?limit=$limit'),
                headers: {'Accept': 'application/json'},
              ).timeout(const Duration(seconds: 4));
              if (topResp.statusCode == 200) {
                final topData = jsonDecode(topResp.body);
                items = (topData['data'] as List? ?? [])
                    .whereType<Map<String, dynamic>>()
                    .where((t) => t['readable'] != false)
                    .map((r) => SearchResult.fromDeezerTrack(r))
                    .toList();
              } else {
                items = [];
              }
            }
            artistResults.addAll(items);
            for (final item in items) {
              if (isUnheardOnly &&
                  heardFilter.isHeard(
                    title: item.title,
                    artist: item.artist,
                    trackId: item.id,
                  )) {
                continue;
              }
              if (isCoverOrTributeTrack(
                artist: item.artist,
                title: item.title,
                allowEnsembleOrCover: userAllowsCover,
                allowLive: userAllowsLive,
                allowInstrumental: userAllowsInstrumental,
                allowRemix: userAllowsRemix,
              )) {
                continue;
              }
              if (isTrackValenceMismatched(
                title: item.title,
                artist: item.artist,
                requestedValence: detectedValence,
                allowAcoustic: userAllowsAcoustic,
              )) {
                continue;
              }
              final cTitle = HeardHistoryFilter.cleanTitle(item.title);
              final cArtist = HeardHistoryFilter.cleanArtist(item.artist);
              final coreKey = '$cTitle|$cArtist';
              final existingList = dedicatedAnchorTracks[aName] ?? [];
              if (cTitle.isNotEmpty && existingList.any((e) =>
                  '${HeardHistoryFilter.cleanTitle((e['title'] ?? '').toString())}|${HeardHistoryFilter.cleanArtist((e['artist'] ?? '').toString())}' ==
                  coreKey)) {
                continue;
              }
              final trackMap = {
                'title': item.title,
                'artist': item.artist,
                'artistId': item.artistId,
                'artistImage': item.artistImage,
                'image': item.image,
                'duration': item.duration,
                'deezerId': item.id,
                'previewUrl': item.previewUrl,
                'source': 'semantic_candidate',
              };
              dedicatedAnchorTracks.putIfAbsent(aName, () => []).add(trackMap);
            }

            // If artist's /top endpoint has fewer than 5 tracks, or if in unheard mode where top tracks are filtered,
            // search the general catalog for the artist to get their other real tracks (peach eyes, courage, etc.)
            // Never do loose search for Japanese Eve (to prevent pulling American Eve)
            if (aId != '69128312' &&
                (dedicatedAnchorTracks[aName]?.length ?? 0) <
                    (isUnheardOnly ? 15 : 5)) {
              try {
                final qEnc = Uri.encodeComponent(aName);
                final sResp = await http.get(
                  Uri.parse('$_deezerApi/search?q=$qEnc&limit=25'),
                  headers: {'Accept': 'application/json'},
                ).timeout(const Duration(seconds: 3));
                if (sResp.statusCode == 200) {
                  final sData = jsonDecode(sResp.body);
                  final sItems = (sData['data'] as List? ?? [])
                      .whereType<Map<String, dynamic>>()
                      .where((t) => t['readable'] != false)
                      .map((r) => SearchResult.fromDeezerTrack(r))
                      .where((r) {
                    final rName = r.artist
                        .toLowerCase()
                        .replaceAll(RegExp(r'[^a-z0-9]'), '');
                    final target = aName
                        .toLowerCase()
                        .replaceAll(RegExp(r'[^a-z0-9]'), '');
                    return rName.contains(target) || target.contains(rName);
                  }).toList();
                  artistResults.addAll(sItems);
                  for (final item in sItems) {
                    if (isUnheardOnly &&
                        heardFilter.isHeard(
                          title: item.title,
                          artist: item.artist,
                          trackId: item.id,
                        )) {
                      continue;
                    }
                    if (isCoverOrTributeTrack(
                      artist: item.artist,
                      title: item.title,
                      allowEnsembleOrCover: userAllowsCover,
                      allowLive: userAllowsLive,
                      allowInstrumental: userAllowsInstrumental,
                      allowRemix: userAllowsRemix,
                    )) {
                      continue;
                    }
                    if (isTrackValenceMismatched(
                      title: item.title,
                      artist: item.artist,
                      requestedValence: detectedValence,
                      allowAcoustic: userAllowsAcoustic,
                    )) {
                      continue;
                    }
                    final cTitle = HeardHistoryFilter.cleanTitle(item.title);
                    final cArtist = HeardHistoryFilter.cleanArtist(item.artist);
                    final coreKey = '$cTitle|$cArtist';
                    final list =
                        dedicatedAnchorTracks.putIfAbsent(aName, () => []);
                    if (cTitle.isNotEmpty && list.any((e) =>
                        '${HeardHistoryFilter.cleanTitle((e['title'] ?? '').toString())}|${HeardHistoryFilter.cleanArtist((e['artist'] ?? '').toString())}' ==
                        coreKey)) {
                      continue;
                    }
                    final trackMap = {
                      'title': item.title,
                      'artist': item.artist,
                      'artistId': item.artistId,
                      'artistImage': item.artistImage,
                      'image': item.image,
                      'duration': item.duration,
                      'deezerId': item.id,
                      'previewUrl': item.previewUrl,
                      'source': 'semantic_candidate',
                    };
                    list.add(trackMap);
                  }
                }
              } catch (_) {}
            }

            // 2. Fetch related companion artists ONLY if single artist request
            if (fetchRelated) {
              try {
                final relResp = await http.get(
                  Uri.parse('$_deezerApi/artist/$aId/related?limit=5'),
                  headers: {'Accept': 'application/json'},
                ).timeout(const Duration(seconds: 3));
                if (relResp.statusCode == 200) {
                  final relData = jsonDecode(relResp.body);
                  final relList = relData['data'] as List? ?? [];
                  for (final rel in relList.take(4)) {
                    final relId = rel['id']?.toString();
                    if (relId != null) {
                      final relTopResp = await http.get(
                        Uri.parse('$_deezerApi/artist/$relId/top?limit=5'),
                        headers: {'Accept': 'application/json'},
                      ).timeout(const Duration(seconds: 2));
                      if (relTopResp.statusCode == 200) {
                        final relTopData = jsonDecode(relTopResp.body);
                        final relTracks = (relTopData['data'] as List? ?? [])
                            .whereType<Map<String, dynamic>>()
                            .where((t) => t['readable'] != false)
                            .map((r) => SearchResult.fromDeezerTrack(r));
                        artistResults.addAll(relTracks);
                      }
                    }
                  }
                }
              } catch (_) {}
            }
          }
        } catch (_) {}
        return artistResults;
      });

      final allResults = await Future.wait(
          [...searchFutures, ...idTopFutures, ...artistTopFutures]);
      for (final list in allResults) {
        for (final item in list) {
          addCandidate(item);
        }
      }

      // Group candidate tracks into dedicated anchor bins for guaranteed balanced selection
      for (final track in candidatePool) {
        final tArtist = (track['artist'] ?? '').toString().toLowerCase().trim();
        final tArtistClean = tArtist.replaceAll(RegExp(r'[^a-z0-9]'), '');
        final tArtistId = (track['artistId'] ?? '').toString().trim();

        for (final aName in anchorArtists) {
          final aClean =
              aName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (aClean.isNotEmpty &&
              (tArtistClean.contains(aClean) ||
                  aClean.contains(tArtistClean))) {
            dedicatedAnchorTracks.putIfAbsent(aName, () => []).add(track);
          }
        }

        for (final aId in anchorArtistIds) {
          if (tArtistId == aId) {
            dedicatedAnchorTracks.putIfAbsent(aId, () => []).add(track);
          }
        }
      }

      // Also grab tracks from curated public playlists matching the genres/vibe/activity
      final genreKeywords = <String>{
        if (isAnimeOrJapanese) ...[
          'Anime Essentials',
          'Top Anime',
          'Anisong',
          'Anime Openings'
        ],
        if (isLofiRequest) ...['lofi hip hop', 'lo-fi beats'],
        if (RegExp(r'\b(shower|bath|showering)\b', caseSensitive: false).hasMatch(mood)) ...[
          'singing in the shower',
          'Songs to Sing in the Shower',
        ],
        if (RegExp(r'\b(gym|workout|lifting|fitness)\b', caseSensitive: false).hasMatch(mood)) ...[
          'Gym Workout',
          'Workout Mix',
        ],
        if (RegExp(r'\b(cooking|kitchen|dinner)\b', caseSensitive: false).hasMatch(mood)) ...[
          'Cooking Songs',
          'Dinner at Home',
        ],
        if (RegExp(r'\b(road\s*trip|driving|drive|car)\b', caseSensitive: false).hasMatch(mood)) ...[
          'roadtrip hits',
          'Driving Hits',
        ],
        if (RegExp(r'\b(party|pre\s*game|club)\b', caseSensitive: false).hasMatch(mood)) ...[
          'Party Hits',
          'Dance Party',
        ],
        if (RegExp(r'\b(sleep|sleeping|bedtime)\b', caseSensitive: false).hasMatch(mood)) ...[
          'Deep Sleep',
          'Sleep Meditation',
        ],
        if (RegExp(r'\b(morning|wake\s*up)\b', caseSensitive: false).hasMatch(mood)) ...[
          'Morning Motivation',
          'Wake Up Happy',
        ],
        ...?intent?.genres,
      }.toList();
      if (genreKeywords.isNotEmpty) {
        for (final g in genreKeywords.take(3)) {
          try {
            final qEnc = Uri.encodeComponent(g);
            final plResp = await http.get(
              Uri.parse('$_deezerApi/search/playlist?q=$qEnc&limit=2'),
              headers: {'Accept': 'application/json'},
            ).timeout(const Duration(seconds: 3));
            if (plResp.statusCode == 200) {
              final plData = jsonDecode(plResp.body);
              final plList = plData['data'] as List? ?? [];
              for (final pl in plList) {
                final tUrl = pl['tracklist']?.toString();
                if (tUrl != null) {
                  final tResp = await http.get(
                    Uri.parse('$tUrl?limit=20'),
                    headers: {'Accept': 'application/json'},
                  ).timeout(const Duration(seconds: 3));
                  if (tResp.statusCode == 200) {
                    final tData = jsonDecode(tResp.body);
                    final tItems = (tData['data'] as List? ?? [])
                        .whereType<Map<String, dynamic>>()
                        .where((t) => t['readable'] != false)
                        .map((r) => SearchResult.fromDeezerTrack(r));
                    for (final item in tItems) {
                      addCandidate(item);
                    }
                  }
                }
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      print('[Generate] Candidate pool retrieval error: $e');
    }

    print(
        '[Generate] Retrieved ${candidatePool.length} real candidate tracks in candidate pool.');

    // Cap candidate pool to at most 80 tracks so LLM context and prompt size remain fast and well within limits
    if (candidatePool.length > 80) {
      candidatePool.removeRange(80, candidatePool.length);
    }

    // For a pure global live chart request, do not let broad catalog candidates dilute
    // the real-time chart. Never run this if a specific genre, anime, or theme was requested.
    if (isLiveGlobalChartRequest &&
        liveChartLoaded &&
        !hasSpecificGenreOrTheme) {
      candidatePool.removeWhere((track) => track['source'] != 'live_chart');
    }
    if (requestedYear != null) {
      print(
          '[Generate] Kept ${candidatePool.length} currently charting tracks released in $requestedYear.');
    }
    if (requestedYear != null && liveChartLoaded && candidatePool.isEmpty) {
      return GeneratedPlaylist(
        success: false,
        mood: mood,
        size: 0,
        source: 'live_chart',
        error:
            'No currently charting tracks released in $requestedYear are available right now.',
        songs: [],
      );
    }

    // ----------------------------------------------------
    // PASS 3: CLOSED-SET LLM CURATION
    // LLM receives candidate pool and selects only valid indices
    // ----------------------------------------------------
    onStageChanged?.call(2); // Stage 2: Curation & Harmonic Ordering

    Map<String, dynamic> curationResult = {'success': false};
    if (candidatePool.isNotEmpty) {
      final explicitCount =
          explicitUserArtists.length + explicitUserArtistIds.length;

      final bool isExclusiveArtists = explicitCount >= 1 &&
          isExclusiveArtistsRequest(lowerMood, explicitCount);

      final isSingleArtistRequest = isExclusiveArtists && explicitCount == 1;

      final singleAnchorArtist = (intent?.anchorArtists.isNotEmpty == true &&
              (intent?.anchorArtists.length ?? 0) <= 1)
          ? intent!.anchorArtists.first.toLowerCase().trim()
          : '';

      final balancedPool = <Map<String, dynamic>>[];
      final countPerArtist = <String, int>{};

      final isOpenMoodOrVibe = !isExclusiveArtists &&
          (intent == null ||
              intent.intentType == 'SITUATIONAL_VIBE' ||
              intent.intentType == 'EMOTIONAL_MOOD' ||
              intent.intentType == 'GENRE_ERA_CULTURE' ||
              intent.intentType == 'PERSONALIZED_DISCOVERY');

      final int targetPerExplicit;
      final int maxPerArtist;

      if (isExclusiveArtists) {
        // EXCLUSIVE ARTISTS: 100% dedicated allocation to requested artists
        if (explicitCount == 1) {
          // 1 Artist (e.g. "Taylor Swift only") -> 100% single artist quota -> 15–20 songs
          targetPerExplicit = size;
          maxPerArtist = size;
        } else if (explicitCount == 2) {
          // 2 Artists (e.g. "Taylor Swift & Olivia Rodrigo") -> ~50% / 50% equal split -> 10 songs each
          targetPerExplicit = (size / 2).round();
          maxPerArtist = targetPerExplicit;
        } else if (explicitCount == 3) {
          // 3 Artists (e.g. "Taylor, Olivia & Billie Eilish") -> ~33% equal split -> 6–7 songs each (7 + 7 + 6 = 20)
          targetPerExplicit = (size / 3).ceil();
          maxPerArtist = targetPerExplicit;
        } else if (explicitCount == 4) {
          // 4 Artists -> ~25% equal split -> 5 songs each (5 + 5 + 5 + 5 = 20)
          targetPerExplicit = (size / 4).round();
          maxPerArtist = targetPerExplicit;
        } else {
          targetPerExplicit = (size / explicitCount).floor().clamp(2, size);
          maxPerArtist = targetPerExplicit + 1;
        }
      } else if (explicitCount >= 1) {
        // BLEND / REFINE / MOOD + ARTIST:
        // Enough amount of that artist that makes the playlist feel like it included that artist,
        // without consuming the whole playlist or destroying the mood!
        if (explicitCount == 1) {
          // 1 artist mentioned / refined -> ~25% (4–5 songs), leaves 15–16 for mood
          targetPerExplicit = (size * 0.25).round().clamp(4, 5);
          maxPerArtist = targetPerExplicit + 1; // 6
        } else if (explicitCount == 2) {
          // 2 artists mentioned / refined -> ~20% each (3–4 songs each = 8 total), leaves 12 for mood
          targetPerExplicit = (size * 0.20).round().clamp(3, 4);
          maxPerArtist = targetPerExplicit + 1; // 5
        } else if (explicitCount == 3) {
          // 3 artists mentioned / refined -> 3 songs each (9 total), leaves 11 for mood
          targetPerExplicit = 3;
          maxPerArtist = 4;
        } else if (explicitCount == 4) {
          // 4 artists mentioned / refined -> 2–3 songs each (10 total), leaves 10 for mood
          targetPerExplicit = 2;
          maxPerArtist = 3;
        } else {
          targetPerExplicit = 2;
          maxPerArtist = 2;
        }
      } else {
        targetPerExplicit = 0;
        maxPerArtist = isOpenMoodOrVibe ? 3 : 4;
      }

      print(
          '[Generate] Artist quota formula: isExclusive=$isExclusiveArtists | explicitCount=$explicitCount | targetPerArtist=$targetPerExplicit | maxPerArtist=$maxPerArtist');

      for (final track in candidatePool) {
        final artistKey =
            (track['artist'] ?? '').toString().toLowerCase().trim();
        final currentCount = countPerArtist[artistKey] ?? 0;
        if (currentCount < maxPerArtist) {
          balancedPool.add(track);
          countPerArtist[artistKey] = currentCount + 1;
        }
      }

      final poolToCurate =
          balancedPool.isNotEmpty ? balancedPool : candidatePool;
      // Keep the complete conversation in the curator prompt. The intent
      // summary is useful context, but must not replace later chat refinements.
      final genreConstraint = isLofiRequest
          ? '\n\nHARD GENRE REQUIREMENT: This is a lo-fi playlist. Select only lo-fi, lo-fi hip hop, chillhop, or instrumental beat tracks. Do not include pop, vocal R&B, mainstream rap, or unrelated songs just because they are popular.'
          : isAnimeOrJapanese
              ? '\n\nHARD GENRE REQUIREMENT: This is an anime music playlist. Select only authentic anime theme songs (openings, endings, OSTs) or Japanese tracks by anime artists. Do not include Western pop, hip-hop, rap, or unrelated global chart songs.'
              : isLiveGlobalChartRequest
                  ? '\n\nHARD FRESHNESS REQUIREMENT: Select only from the live current chart candidates. These are the songs currently popular now; do not substitute older catalog songs.'
                  : '';
      final explicitConstraint = explicitUserArtists.isNotEmpty
          ? (isExclusiveArtists
              ? '\n\nHARD ARTIST ALLOCATION REQUIREMENT: The user strictly requested ONLY these artists: ${explicitUserArtists.join(", ")}. Select ONLY tracks from these requested artists, distributed equally among them (~$targetPerExplicit songs each).'
              : '\n\nHARD ARTIST BLEND REQUIREMENT: The user requested to include: ${explicitUserArtists.join(", ")}. Blend in ~$targetPerExplicit songs from each of these requested artists, while filling the rest with tracks matching the requested theme.')
          : '';
      final valenceConstraint = detectedValence == EmotionalValence.happy
          ? '\n\nHARD EMOTIONAL VALENCE REQUIREMENT: This is a HAPPY / FEEL-GOOD / UPBEAT playlist. Select ONLY positive, joyful, cheerful, uplifting tracks. STRICTLY REJECT any sad songs, breakup ballads, crying songs, heartbreak tracks, or melancholic music. Zero sad songs allowed.'
          : detectedValence == EmotionalValence.sad
              ? '\n\nHARD EMOTIONAL VALENCE REQUIREMENT: This is a SAD / MELANCHOLIC / HEARTBROKEN playlist. Select ONLY emotional, touching ballads. STRICTLY REJECT party bangers, club anthems, and ecstatic dance tracks.'
              : '';
      final activityConstraint = RegExp(r'\b(shower|bath|showering)\b', caseSensitive: false).hasMatch(mood)
          ? '\n\nHARD ACTIVITY REQUIREMENT: This is a SHOWER / SINGING IN THE SHOWER playlist. Select ONLY upbeat, high-energy, infectious sing-along pop anthems, feel-good classics, and catchy vocal choruses that people love to belt out loudly in the shower. STRICTLY REJECT quiet ambient drone, sad ballads, mumble rap, or songs literally titled "Shower".'
          : RegExp(r'\b(gym|workout|lifting)\b', caseSensitive: false).hasMatch(mood)
              ? '\n\nHARD ACTIVITY REQUIREMENT: This is a GYM / WORKOUT playlist. Select ONLY intense, adrenaline-pumping, high-BPM tracks with aggressive bass and heavy drops. STRICTLY REJECT slow acoustic songs or quiet ballads.'
              : RegExp(r'\b(study|studying|homework|reading)\b', caseSensitive: false).hasMatch(mood)
                  ? '\n\nHARD ACTIVITY REQUIREMENT: This is a STUDY / FOCUS playlist. Select ONLY smooth lo-fi beats, gentle chillhop, or calm instrumental music without loud or distracting vocal shouting.'
                  : '';
      final promptForCurator = (intent != null
              ? '$mood\n\nInterpreted intent: ${intent.summary} (Genres: ${intent.genres.join(", ")})'
              : mood) +
          genreConstraint +
          explicitConstraint +
          valenceConstraint +
          activityConstraint;

      curationResult = await GroqService.curateFromCandidatePool(
        promptForCurator,
        poolToCurate,
        targetCount: size,
        userContext: tasteContext,
      );

      if (curationResult['success'] != true) {
        curationResult = await GeminiService.curateFromCandidatePool(
          promptForCurator,
          poolToCurate,
          targetCount: size,
          userContext: tasteContext,
        );
      }

      if (curationResult['success'] == true) {
        final selectedIndices =
            curationResult['selected_indices'] as List<int>? ?? [];
        final curatedSongs = <Map<String, dynamic>>[];
        final usedIndices = <int>{};
        final finalArtistCounts = <String, int>{};
        final seenCoreTitles = <String>{};
        final seenCuratedCoreKeys = <String>{};

        // 1. Guaranteed Balanced Explicit Artist Allocation:
        // ONLY if the user explicitly provided artists (via chips or in text)
        final explicitKeys = <String>[];
        for (final k in dedicatedAnchorTracks.keys) {
          if (explicitUserArtists.contains(k) ||
              explicitUserArtistIds.contains(k)) {
            explicitKeys.add(k);
          }
        }

        if (explicitKeys.isNotEmpty) {
          // If the user explicitly provided artists, allocate their full share first!
          for (int round = 0; round < targetPerExplicit; round++) {
            for (final key in explicitKeys) {
              if (curatedSongs.length >= size) break;
              final list = dedicatedAnchorTracks[key] ?? [];
              if (round < list.length) {
                final track = list[round];
                final trackTitle = (track['title'] ?? '').toString();
                final trackArtist = (track['artist'] ?? '').toString();
                final trackId =
                    (track['deezerId'] ?? track['id'] ?? '').toString();

                final cTitle = HeardHistoryFilter.cleanTitle(trackTitle);
                final cArtist = HeardHistoryFilter.cleanArtist(trackArtist);
                final coreKey = '$cTitle|$cArtist';

                if (cTitle.isNotEmpty) {
                  if (seenCuratedCoreKeys.contains(coreKey)) continue;
                  if (cTitle.length >= 3 && seenCoreTitles.contains(cTitle)) continue;
                }

                if (isUnheardOnly &&
                    heardFilter.isHeard(
                      title: trackTitle,
                      artist: trackArtist,
                      trackId: trackId,
                    )) {
                  continue;
                }
                if (isCoverOrTributeTrack(
                  artist: trackArtist,
                  title: trackTitle,
                  allowEnsembleOrCover: userAllowsCover,
                  allowLive: userAllowsLive,
                  allowInstrumental: userAllowsInstrumental,
                  allowRemix: userAllowsRemix,
                )) {
                  continue;
                }
                if (isTrackValenceMismatched(
                  title: trackTitle,
                  artist: trackArtist,
                  requestedValence: detectedValence,
                  allowAcoustic: userAllowsAcoustic,
                )) {
                  continue;
                }
                final trackKey =
                    '${trackTitle.toLowerCase()}|${trackArtist.toLowerCase()}';
                if (!curatedSongs.any((s) =>
                    '${(s['title'] ?? '').toString().toLowerCase()}|${(s['artist'] ?? '').toString().toLowerCase()}' ==
                    trackKey)) {
                  curatedSongs.add(track);
                  if (cTitle.isNotEmpty) {
                    seenCuratedCoreKeys.add(coreKey);
                    if (cTitle.length >= 3) seenCoreTitles.add(cTitle);
                  }
                  final aKey = trackArtist.toLowerCase().trim();
                  finalArtistCounts[aKey] = (finalArtistCounts[aKey] ?? 0) + 1;
                  final cIdx = candidatePool.indexOf(track);
                  if (cIdx != -1) usedIndices.add(cIdx);
                }
              }
            }
          }
        }

        // 2. Add LLM Curated Picks respecting per-artist balance limit & emotional valence
        for (final idx in selectedIndices) {
          if (idx >= 0 &&
              idx < poolToCurate.length &&
              curatedSongs.length < size) {
            final cand = poolToCurate[idx];
            final candTitle = (cand['title'] ?? '').toString();
            final candArtist =
                (cand['artist'] ?? '').toString().toLowerCase().trim();
            final candId = (cand['deezerId'] ?? cand['id'] ?? '').toString();

            final cTitle = HeardHistoryFilter.cleanTitle(candTitle);
            final cArtist = HeardHistoryFilter.cleanArtist(candArtist);
            final coreKey = '$cTitle|$cArtist';

            if (cTitle.isNotEmpty) {
              if (seenCuratedCoreKeys.contains(coreKey)) continue;
              if (cTitle.length >= 3 && seenCoreTitles.contains(cTitle)) continue;
            }

            if (isUnheardOnly &&
                heardFilter.isHeard(
                  title: candTitle,
                  artist: candArtist,
                  trackId: candId,
                )) {
              continue;
            }
            if (isCoverOrTributeTrack(
              artist: candArtist,
              title: candTitle,
              allowEnsembleOrCover: userAllowsCover,
              allowLive: userAllowsLive,
              allowInstrumental: userAllowsInstrumental,
              allowRemix: userAllowsRemix,
            )) {
              continue;
            }
            if (isTrackValenceMismatched(
              title: candTitle,
              artist: candArtist,
              requestedValence: detectedValence,
              allowAcoustic: userAllowsAcoustic,
            )) {
              continue;
            }
            final curCount = finalArtistCounts[candArtist] ?? 0;
            if (curCount >= maxPerArtist && !isSingleArtistRequest) {
              continue;
            }

            final candKey = '${candTitle.toLowerCase()}|$candArtist';
            if (!curatedSongs.any((s) =>
                '${(s['title'] ?? '').toString().toLowerCase()}|${(s['artist'] ?? '').toString().toLowerCase()}' ==
                candKey)) {
              curatedSongs.add(cand);
              if (cTitle.isNotEmpty) {
                seenCuratedCoreKeys.add(coreKey);
                if (cTitle.length >= 3) seenCoreTitles.add(cTitle);
              }
              usedIndices.add(idx);
              finalArtistCounts[candArtist] = curCount + 1;
            }
          }
        }

        // 3. Auto-backfill loop to guarantee full requested count WITHOUT letting one artist dominate
        if (curatedSongs.length < size) {
          for (int i = 0; i < poolToCurate.length; i++) {
            if (curatedSongs.length >= size) break;
            final candidate = poolToCurate[i];
            final candTitle = (candidate['title'] ?? '').toString();
            final candArtist =
                (candidate['artist'] ?? '').toString().toLowerCase().trim();
            final candId =
                (candidate['deezerId'] ?? candidate['id'] ?? '').toString();

            final cTitle = HeardHistoryFilter.cleanTitle(candTitle);
            final cArtist = HeardHistoryFilter.cleanArtist(candArtist);
            final coreKey = '$cTitle|$cArtist';

            if (cTitle.isNotEmpty) {
              if (seenCuratedCoreKeys.contains(coreKey)) continue;
              if (cTitle.length >= 3 && seenCoreTitles.contains(cTitle)) continue;
            }

            if (isUnheardOnly &&
                heardFilter.isHeard(
                  title: candTitle,
                  artist: candArtist,
                  trackId: candId,
                )) {
              continue;
            }
            if (isCoverOrTributeTrack(
              artist: candArtist,
              title: candTitle,
              allowEnsembleOrCover: userAllowsCover,
              allowLive: userAllowsLive,
              allowInstrumental: userAllowsInstrumental,
              allowRemix: userAllowsRemix,
            )) {
              continue;
            }
            if (isTrackValenceMismatched(
              title: candTitle,
              artist: candArtist,
              requestedValence: detectedValence,
              allowAcoustic: userAllowsAcoustic,
            )) {
              continue;
            }

            if (isSingleArtistRequest && singleAnchorArtist.isNotEmpty) {
              if (!candArtist.contains(singleAnchorArtist) &&
                  !singleAnchorArtist.contains(candArtist)) {
                continue;
              }
            }

            final curCount = finalArtistCounts[candArtist] ?? 0;
            if (!isSingleArtistRequest && curCount >= maxPerArtist) {
              continue;
            }

            if (usedIndices.add(i)) {
              final candKey = '${candTitle.toLowerCase()}|$candArtist';
              if (!curatedSongs.any((s) =>
                  '${(s['title'] ?? '').toString().toLowerCase()}|${(s['artist'] ?? '').toString().toLowerCase()}' ==
                  candKey)) {
                curatedSongs.add(candidate);
                if (cTitle.isNotEmpty) {
                  seenCuratedCoreKeys.add(coreKey);
                  if (cTitle.length >= 3) seenCoreTitles.add(cTitle);
                }
                finalArtistCounts[candArtist] = curCount + 1;
              }
            }
          }
        }

        // 4. If STILL under size, loosen the cap for remaining backfill
        if (curatedSongs.length < size) {
          for (int i = 0; i < poolToCurate.length; i++) {
            if (curatedSongs.length >= size) break;
            if (usedIndices.add(i)) {
              final candidate = poolToCurate[i];
              final candTitle = (candidate['title'] ?? '').toString();
              final candArtist =
                  (candidate['artist'] ?? '').toString().toLowerCase().trim();
              final candId =
                  (candidate['deezerId'] ?? candidate['id'] ?? '').toString();

              final cTitle = HeardHistoryFilter.cleanTitle(candTitle);
              final cArtist = HeardHistoryFilter.cleanArtist(candArtist);
              final coreKey = '$cTitle|$cArtist';

              if (cTitle.isNotEmpty) {
                if (seenCuratedCoreKeys.contains(coreKey)) continue;
                if (cTitle.length >= 3 && seenCoreTitles.contains(cTitle)) continue;
              }

              if (isUnheardOnly &&
                  heardFilter.isHeard(
                    title: candTitle,
                    artist: candArtist,
                    trackId: candId,
                  )) {
                continue;
              }
              if (isCoverOrTributeTrack(
                artist: candArtist,
                title: candTitle,
                allowEnsembleOrCover: userAllowsCover,
                allowLive: userAllowsLive,
                allowInstrumental: userAllowsInstrumental,
                allowRemix: userAllowsRemix,
              )) {
                continue;
              }
              if (isTrackValenceMismatched(
                title: candTitle,
                artist: candArtist,
                requestedValence: detectedValence,
                allowAcoustic: userAllowsAcoustic,
              )) {
                continue;
              }
              final candKey =
                  '${candTitle.toLowerCase()}|${candArtist.toLowerCase()}';
              if (!curatedSongs.any((s) =>
                  '${(s['title'] ?? '').toString().toLowerCase()}|${(s['artist'] ?? '').toString().toLowerCase()}' ==
                  candKey)) {
                curatedSongs.add(candidate);
                if (cTitle.isNotEmpty) {
                  seenCuratedCoreKeys.add(coreKey);
                  if (cTitle.length >= 3) seenCoreTitles.add(cTitle);
                }
                finalArtistCounts[candArtist] =
                    (finalArtistCounts[candArtist] ?? 0) + 1;
              }
            }
          }
        }

        if (curatedSongs.isNotEmpty) {
          // De-clump same-artist songs in the final curated sequence
          final byArtist = <String, List<Map<String, dynamic>>>{};
          for (final s in curatedSongs) {
            final a = (s['artist'] ?? '').toString().toLowerCase().trim();
            byArtist.putIfAbsent(a, () => []).add(s);
          }
          final shuffledList = <Map<String, dynamic>>[];
          int round = 0;
          bool added = true;
          while (added && shuffledList.length < curatedSongs.length) {
            added = false;
            final artistKeys = byArtist.keys.toList()..shuffle();
            for (final k in artistKeys) {
              final list = byArtist[k]!;
              if (round < list.length &&
                  shuffledList.length < curatedSongs.length) {
                shuffledList.add(list[round]);
                added = true;
              }
            }
            round++;
          }
          final finalSongsList =
              shuffledList.isNotEmpty ? shuffledList : curatedSongs;

          genWatch.stop();
          print(
              '[Generate] Semantic RAG Curation succeeded: ${finalSongsList.length}/$size songs delivered in ${(genWatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s');

          final playlist = GeneratedPlaylist(
            success: true,
            mood: mood,
            title: curationResult['title']?.toString() ?? 'Vibe Playlist',
            description: curationResult['description']?.toString() ?? '',
            size: finalSongsList.length,
            source: 'semantic_rag_ai',
            songs: finalSongsList,
          );

          _saveToSupabase(playlist);
          return playlist;
        }
      }
    }

    // ----------------------------------------------------
    // FALLBACK: If candidate pool was small/empty (e.g. unique niche query)
    // ----------------------------------------------------
    print(
        '[Generate] Candidate pool too small, falling back to direct AI generation...');
    final candidateCount = size + 8;
    Map<String, dynamic> result = await GroqService.generateMoodPlaylist(
      mood,
      size: candidateCount,
      tasteContext: tasteContext,
    );

    if (result['success'] != true) {
      result = await GeminiService.generatePlaylist(
        mood,
        size: candidateCount,
        tasteContext: tasteContext,
      );
    }

    if (result['success'] != true) {
      return GeneratedPlaylist(
        success: false,
        mood: mood,
        size: 0,
        source: 'ai_error',
        error: 'Playlist generation failed',
        songs: [],
      );
    }

    onStageChanged?.call(
        2); // Stage 2: Checking audio streamability & resolving tracks on streaming catalog
    final songsRaw = result['songs'] as List<dynamic>? ?? [];
    print(
        '[Generate] AI delivered ${songsRaw.length} songs. Resolving audio streams on streaming catalog...');

    final resolveWatch = Stopwatch()..start();

    // ----------------------------------------------------
    // HELPER: Fuzzy string similarity (token-set & Dice coefficient >= 0.80)
    // ----------------------------------------------------
    double stringSimilarity(String s1, String s2) {
      final a = s1.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ' ').trim();
      final b = s2.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ' ').trim();
      if (a == b) return 1.0;
      if (a.isEmpty || b.isEmpty) return 0.0;
      if (a.contains(b) || b.contains(a)) return 0.90;

      final setA = a.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
      final setB = b.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
      final intersection = setA.intersection(setB).length;
      final union = setA.union(setB).length;
      if (union == 0) return 0.0;
      return intersection / union;
    }

    // Fast parallel resolution in batches of 5 for blazing speed
    Future<Map<String, dynamic>?> resolveOneSong(dynamic song) async {
      final title = song['title']?.toString() ?? '';
      final artist = song['artist']?.toString() ?? '';
      final alias = song['search_alias']?.toString() ?? '';
      if (title.isEmpty || artist.isEmpty) return null;

      try {
        final cleanTitle =
            title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').trim();
        final searchTerms = <String>[
          '$cleanTitle $artist',
          'track:"$cleanTitle" artist:"$artist"',
          if (alias.isNotEmpty &&
              alias.toLowerCase() != cleanTitle.toLowerCase())
            alias,
        ];

        // Item 1: Run ALL search terms in parallel and merge into one candidate pool
        final termFutures = searchTerms.map((st) async {
          try {
            final query = Uri.encodeComponent(st);
            final resp = await http.get(
              Uri.parse('$_deezerApi/search?q=$query&limit=6'),
              headers: {'Accept': 'application/json'},
            ).timeout(const Duration(milliseconds: 3500));
            if (resp.statusCode == 200) {
              final data = jsonDecode(resp.body);
              return (data['data'] as List? ?? [])
                  .whereType<Map<String, dynamic>>()
                  .where((t) => t['readable'] != false)
                  .toList();
            }
          } catch (_) {}
          return <Map<String, dynamic>>[];
        });

        final resultsNested = await Future.wait(termFutures);
        final results = <Map<String, dynamic>>[];
        final seenTrackIds = <String>{};
        for (final batch in resultsNested) {
          for (final item in batch) {
            final id = item['id']?.toString() ?? '';
            if (id.isNotEmpty && seenTrackIds.add(id)) {
              results.add(item);
            }
          }
        }

        final validCandidates = <SearchResult>[];
        final coverCandidates = <SearchResult>[];

        for (final r in results) {
          final t = SearchResult.fromDeezerTrack(r);
          final titleLower = t.title.toLowerCase();
          final artistLower = t.artist.toLowerCase();

          final isCoverOrTribute = isCoverOrTributeTrack(
                artist: t.artist,
                title: t.title,
                allowEnsembleOrCover: userAllowsCover,
                allowLive: userAllowsLive,
                allowInstrumental: userAllowsInstrumental,
                allowRemix: userAllowsRemix,
              ) ||
              artistLower.contains('geek music') ||
              artistLower.contains('piano') ||
              artistLower.contains('lo-fi') ||
              artistLower.contains('lofi') ||
              titleLower.contains('piano version') ||
              titleLower.contains('instrumental');

          final isValenceMismatch = isTrackValenceMismatched(
            title: t.title,
            artist: t.artist,
            requestedValence: detectedValence,
            allowAcoustic: userAllowsAcoustic,
          );

          if (isValenceMismatch) continue;

          // Item 4: Real fuzzy similarity calculation for both title and artist
          final artistSim = stringSimilarity(t.artist, artist);
          final titleSim = stringSimilarity(cleanTitle, t.title);

          // Item 3: Studio originals only need high artist + title similarity, NO anime/franchise keywords required!
          final isStudioOriginal = (artistSim >= 0.70 ||
                  t.artist.toLowerCase() == artist.toLowerCase()) &&
              (titleSim >= 0.70 ||
                  t.title.toLowerCase().contains(cleanTitle.toLowerCase()));

          if (isStudioOriginal && !isCoverOrTribute) {
            validCandidates.add(t);
          } else if (titleSim >= 0.80 && !isCoverOrTribute) {
            // Tier 2: Valid alternative version of this exact song
            coverCandidates.add(t);
          }
        }

        SearchResult? bestMatch;
        if (validCandidates.isNotEmpty) {
          bestMatch = validCandidates.firstWhere(
            (c) =>
                !c.title.toLowerCase().contains('remix') &&
                !c.title.toLowerCase().contains('cover'),
            orElse: () => validCandidates.first,
          );
        } else if (userAllowsCover && coverCandidates.isNotEmpty) {
          bestMatch = coverCandidates.first;
        }

        if (bestMatch != null && bestMatch.id.isNotEmpty) {
          if (isUnheardOnly &&
              heardFilter.isHeard(
                title: bestMatch.title,
                artist: bestMatch.artist,
                trackId: bestMatch.id,
              )) {
            return null;
          }
          return {
            'title': bestMatch.title,
            'artist': bestMatch.artist,
            'artistId': bestMatch.artistId,
            'artistImage': bestMatch.artistImage,
            'image': bestMatch.image,
            'duration': bestMatch.duration,
            'deezerId': bestMatch.id,
            'previewUrl': bestMatch.previewUrl,
            'source': 'ai',
          };
        }
      } catch (e) {
        print('[Generate] Failed to resolve "$title" by "$artist": $e');
      }
      return null;
    }

    final resolved = <Map<String, dynamic>>[];
    final seen = <String>{};
    final seenResolvedCoreKeys = <String>{};
    final seenResolvedCoreTitles = <String>{};

    // Parallel batching in chunks of 15 for ultra-rapid resolution
    const chunkSize = 15;
    for (int i = 0; i < songsRaw.length; i += chunkSize) {
      if (resolved.length >= size) break;
      final chunk = songsRaw.skip(i).take(chunkSize).toList();
      final resolvedChunk =
          await Future.wait(chunk.map((s) => resolveOneSong(s)));
      for (final r in resolvedChunk) {
        if (r != null && resolved.length < size) {
          final rTitle = (r['title'] ?? '').toString();
          final rArtist = (r['artist'] ?? '').toString();
          final cTitle = HeardHistoryFilter.cleanTitle(rTitle);
          final cArtist = HeardHistoryFilter.cleanArtist(rArtist);
          final coreKey = '$cTitle|$cArtist';

          if (cTitle.isNotEmpty) {
            if (seenResolvedCoreKeys.contains(coreKey)) continue;
            if (cTitle.length >= 3 && seenResolvedCoreTitles.contains(cTitle)) continue;
          }

          final key =
              '${rTitle.toLowerCase()}|${rArtist.toLowerCase()}';
          if (seen.add(key)) {
            if (cTitle.isNotEmpty) {
              seenResolvedCoreKeys.add(coreKey);
              if (cTitle.length >= 3) seenResolvedCoreTitles.add(cTitle);
            }
            resolved.add(r);
          }
        }
      }
    }

    // Item 6: Fallback backfill loop if short of target count
    if (resolved.length < size) {
      try {
        final backfillQueries = <String>[];
        for (final a in anchorArtists) {
          backfillQueries.add('artist:"$a"');
        }
        if (intent?.genres.isNotEmpty == true) {
          for (final g in intent!.genres) {
            backfillQueries.add(g);
          }
        }
        final cleanMood = mood
            .replaceAll(
              RegExp(
                  r'(playlist|songs?|make\s*a|give\s*me|plz|please|haven.?t\s*listen|never\s*heard|unheard|discover|new\s*to\s*me)',
                  caseSensitive: false),
              '',
            )
            .trim();
        if (cleanMood.isNotEmpty) {
          backfillQueries.add(cleanMood);
        }
        if (backfillQueries.isEmpty) {
          backfillQueries.add('pop hits');
        }

        for (final bQuery in backfillQueries) {
          if (resolved.length >= size) break;
          final qEnc = Uri.encodeComponent(bQuery);
          final bResp = await http.get(
            Uri.parse('$_deezerApi/search?q=$qEnc&limit=25'),
            headers: {'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 3));
          if (bResp.statusCode == 200) {
            final bData = jsonDecode(bResp.body);
            final bList = (bData['data'] as List? ?? [])
                .whereType<Map<String, dynamic>>()
                .where((t) => t['readable'] != false)
                .map((r) => SearchResult.fromDeezerTrack(r));
            for (final bTrack in bList) {
              if (resolved.length >= size) break;
              if (isUnheardOnly &&
                  heardFilter.isHeard(
                    title: bTrack.title,
                    artist: bTrack.artist,
                    trackId: bTrack.id,
                  )) {
                continue;
              }
              if (isCoverOrTributeTrack(
                artist: bTrack.artist,
                title: bTrack.title,
                allowEnsembleOrCover: userAllowsCover,
                allowLive: userAllowsLive,
                allowInstrumental: userAllowsInstrumental,
                allowRemix: userAllowsRemix,
              )) {
                continue;
              }
              if (isTrackValenceMismatched(
                title: bTrack.title,
                artist: bTrack.artist,
                requestedValence: detectedValence,
                allowAcoustic: userAllowsAcoustic,
              )) {
                continue;
              }

              final cTitle = HeardHistoryFilter.cleanTitle(bTrack.title);
              final cArtist = HeardHistoryFilter.cleanArtist(bTrack.artist);
              final coreKey = '$cTitle|$cArtist';

              if (cTitle.isNotEmpty) {
                if (seenResolvedCoreKeys.contains(coreKey)) continue;
                if (cTitle.length >= 3 && seenResolvedCoreTitles.contains(cTitle)) continue;
              }

              final key =
                  '${bTrack.title.toLowerCase()}|${bTrack.artist.toLowerCase()}';
              if (seen.add(key)) {
                if (cTitle.isNotEmpty) {
                  seenResolvedCoreKeys.add(coreKey);
                  if (cTitle.length >= 3) seenResolvedCoreTitles.add(cTitle);
                }
                resolved.add({
                  'title': bTrack.title,
                  'artist': bTrack.artist,
                  'artistId': bTrack.artistId,
                  'artistImage': bTrack.artistImage,
                  'image': bTrack.image,
                  'duration': bTrack.duration,
                  'deezerId': bTrack.id,
                  'previewUrl': bTrack.previewUrl,
                  'source': 'ai_backfill',
                });
              }
            }
          }
        }
      } catch (_) {}
    }

    // Smart Shuffle / Interleave:
    // Prevent same-artist clumps (e.g. 4 songs by artist A in a row) by shuffling & interleaving artists,
    // while keeping chronological anime openings in sequence.
    final isChronologicalAnime = mood.toLowerCase().contains('opening') ||
        mood.toLowerCase().contains('naruto') ||
        mood.toLowerCase().contains('one piece') ||
        mood.toLowerCase().contains('chronological') ||
        mood.toLowerCase().contains('all openings');

    final finalSongs = <Map<String, dynamic>>[];
    if (isChronologicalAnime || resolved.length <= 3) {
      finalSongs.addAll(resolved);
    } else {
      // 1. If there's an explicit seed/referenced song, keep it as track 1
      final refSong = resolved.firstWhere(
        (s) =>
            s['source'] == 'chip' ||
            mood.toLowerCase().contains(s['title'].toString().toLowerCase()),
        orElse: () => <String, dynamic>{},
      );
      final remaining = List<Map<String, dynamic>>.from(resolved);
      if (refSong.isNotEmpty) {
        remaining.remove(refSong);
        finalSongs.add(refSong);
      }

      // 2. Group remaining by artist and shuffle each artist's track list
      final byArtist = <String, List<Map<String, dynamic>>>{};
      remaining.shuffle();
      for (final s in remaining) {
        final a = (s['artist'] ?? '').toString().toLowerCase();
        byArtist.putIfAbsent(a, () => []).add(s);
      }

      // 3. Interleave so consecutive songs are always by different artists
      int round = 0;
      bool added = true;
      while (added && finalSongs.length < resolved.length) {
        added = false;
        final artistKeys = byArtist.keys.toList()..shuffle();
        for (final k in artistKeys) {
          final list = byArtist[k]!;
          if (round < list.length && finalSongs.length < resolved.length) {
            finalSongs.add(list[round]);
            added = true;
          }
        }
        round++;
      }
    }

    resolveWatch.stop();
    genWatch.stop();
    print(
        '[Generate] Streaming Resolution completed in ${resolveWatch.elapsedMilliseconds}ms');
    print(
        '[Generate] TOTAL PLAYLIST PIPELINE TIME: ${(genWatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s (${finalSongs.length}/$size songs delivered)');

    final playlist = GeneratedPlaylist(
      success: finalSongs.isNotEmpty,
      mood: mood,
      title: result['title']?.toString() ?? 'Generated Playlist',
      description: result['description']?.toString() ?? '',
      size: finalSongs.length,
      source: 'ai',
      songs: finalSongs,
    );

    // Save to Supabase in background
    if (resolved.isNotEmpty) {
      _saveToSupabase(playlist);
    }

    return playlist;
  }

  static Future<void> _saveToSupabase(GeneratedPlaylist playlist) async {
    // Playlist saving to Supabase is handled via PlaylistService when user taps "Add to Library"
  }

  static Future<GeneratedPlaylist> _generateArtistPlaylist(
      List<String> artistIds, int size, String mood) async {
    final tracks = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final artistId in artistIds) {
      if (tracks.length >= size) break;
      String artistName = '';
      try {
        // 1. Fetch artist details
        final aResp = await http.get(
          Uri.parse('$_deezerApi/artist/$artistId'),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 6));
        if (aResp.statusCode == 200) {
          final aData = jsonDecode(aResp.body);
          artistName = aData['name']?.toString() ?? '';
        }

        // 2. Fetch top tracks
        List<SearchResult> topTracksList;
        if (artistId == '69128312') {
          topTracksList =
              await ArtistService.getArtistTopTracks('69128312', limit: 50);
        } else {
          final resp = await http.get(
            Uri.parse('$_deezerApi/artist/$artistId/top?limit=50'),
            headers: {'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 6));

          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body);
            topTracksList = (data['data'] as List? ?? [])
                .whereType<Map<String, dynamic>>()
                .where((t) => t['readable'] != false)
                .map((track) => SearchResult.fromDeezerTrack(track))
                .toList();
          } else {
            topTracksList = [];
          }
        }

        for (final t in topTracksList) {
          if (tracks.length >= size) break;
          final key = '${t.title.toLowerCase()}|${t.artist.toLowerCase()}';
          if (seen.add(key)) {
            tracks.add({
              'title': t.title,
              'artist': t.artist,
              'artistId': t.artistId,
              'artistImage': t.artistImage,
              'image': t.image,
              'duration': t.duration,
              'deezerId': t.id,
              'previewUrl': t.previewUrl,
              'source': 'artist',
            });
          }
        }

        // 3. If top tracks yielded fewer than requested, deep search across track catalog
        if (tracks.length < size && artistName.isNotEmpty) {
          final queries = [
            'artist:"$artistName"',
            artistName,
          ];
          for (final qStr in queries) {
            if (tracks.length >= size) break;
            final tQuery = Uri.encodeComponent(qStr);
            final tResp = await http.get(
              Uri.parse('$_deezerApi/search?q=$tQuery&limit=100'),
              headers: {'Accept': 'application/json'},
            ).timeout(const Duration(seconds: 6));
            if (tResp.statusCode == 200) {
              final tData = jsonDecode(tResp.body);
              final tList = (tData['data'] as List? ?? [])
                  .whereType<Map<String, dynamic>>()
                  .where((t) => t['readable'] != false)
                  .toList();
              for (final item in tList) {
                if (tracks.length >= size) break;
                final t = SearchResult.fromDeezerTrack(item);
                final itemArtist = t.artist.toLowerCase().trim();
                final targetArtist = artistName.toLowerCase().trim();
                if (itemArtist == targetArtist ||
                    itemArtist.contains(targetArtist)) {
                  if (artistId == '69128312') {
                    if (t.artistId == '837') continue;
                    final tLower = t.title.toLowerCase();
                    if (tLower.contains('blow ya mind') ||
                        tLower.contains("who's that girl") ||
                        tLower.contains('gangsta lovin') ||
                        tLower.contains('what you need') ||
                        tLower.contains('tambourine') ||
                        tLower.contains('rich girl')) {
                      continue;
                    }
                  } else if (t.artistId.isNotEmpty && t.artistId != artistId) {
                    continue;
                  }
                  final key =
                      '${t.title.toLowerCase()}|${t.artist.toLowerCase()}';
                  if (seen.add(key)) {
                    tracks.add({
                      'title': t.title,
                      'artist': t.artist,
                      'artistId': t.artistId,
                      'artistImage': t.artistImage,
                      'image': t.image,
                      'duration': t.duration,
                      'deezerId': t.id,
                      'previewUrl': t.previewUrl,
                      'source': 'artist',
                    });
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        print('[Generate] Artist fetch error for $artistId: $e');
      }
    }

    final playlist = GeneratedPlaylist(
      success: tracks.isNotEmpty,
      mood: mood,
      title: tracks.isNotEmpty
          ? '${tracks.first['artist']} Essentials'
          : 'Artist Playlist',
      description:
          'The best songs by ${tracks.isNotEmpty ? tracks.first['artist'] : 'artist'}',
      size: tracks.length,
      source: 'artist',
      songs: tracks,
    );

    if (tracks.isNotEmpty) {
      _saveToSupabase(playlist);
    }

    return playlist;
  }

  static Future<GeneratedPlaylist> _generateTrackPlaylist(
      List<String> trackIds, int size, String mood) async {
    final tracks = <Map<String, dynamic>>[];

    for (final trackId in trackIds) {
      if (tracks.length >= size) break;
      try {
        final resp = await http.get(
          Uri.parse('$_deezerApi/track/$trackId'),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 8));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final t = SearchResult.fromDeezerTrack(data);
          tracks.add({
            'title': t.title,
            'artist': t.artist,
            'artistId': t.artistId,
            'artistImage': t.artistImage,
            'image': t.image,
            'duration': t.duration,
            'deezerId': t.id,
            'previewUrl': t.previewUrl,
            'source': 'chip',
          });
        }
      } catch (e) {
        print('[Generate] Track fetch error for $trackId: $e');
      }
    }

    return GeneratedPlaylist(
      success: true,
      mood: mood,
      size: tracks.length,
      source: 'chip',
      songs: tracks,
    );
  }
}
