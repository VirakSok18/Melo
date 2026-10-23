import 'dart:convert';
import 'package:http/http.dart' as http;
import 'secure_storage_service.dart';

class PromptIntent {
  final String
      intentType; // 'SITUATIONAL_VIBE', 'FRANCHISE_MEDIA', 'ARTIST_OR_SIMILARITY', 'PERSONALIZED_DISCOVERY', 'GENRE_ERA_CULTURE', 'EMOTIONAL_MOOD'
  final String summary;
  final String moodDimension;
  final String activityDimension;
  final String environmentDimension;
  final List<String> genres;
  final List<String> anchorArtists;
  final List<String> seedTracks;
  final List<String> catalogQueries;
  final bool usePersonalHistory;
  final bool unheardOnly;
  final bool needsFavoriteArtists;
  final bool needsTasteProfile;
  final bool needsListeningHistory;
  final bool excludeFollowedArtists;
  final List<String> excludedArtists;

  const PromptIntent({
    required this.intentType,
    required this.summary,
    this.moodDimension = '',
    this.activityDimension = '',
    this.environmentDimension = '',
    this.genres = const [],
    this.anchorArtists = const [],
    this.seedTracks = const [],
    this.catalogQueries = const [],
    this.usePersonalHistory = false,
    this.unheardOnly = false,
    this.needsFavoriteArtists = false,
    this.needsTasteProfile = false,
    this.needsListeningHistory = false,
    this.excludeFollowedArtists = false,
    this.excludedArtists = const [],
  });

  factory PromptIntent.fromJson(Map<String, dynamic> json, String rawPrompt) {
    final type = json['intent_type']?.toString().toUpperCase().trim() ??
        'SITUATIONAL_VIBE';
    final summary = json['summary']?.toString() ?? rawPrompt;
    final moodDim = json['mood_dimension']?.toString().trim() ?? '';
    final actDim = json['activity_dimension']?.toString().trim() ?? '';
    final envDim = json['environment_dimension']?.toString().trim() ?? '';
    final genres = (json['genres'] as List? ?? [])
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final anchorArtists = (json['anchor_artists'] as List? ?? [])
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final seedTracks = (json['seed_tracks'] as List? ?? [])
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final catalogQueries = (json['catalog_queries'] as List? ?? [])
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final useHistory = json['use_personal_history'] == true ||
        json['needs_listening_history'] == true;
    final unheard = json['unheard_only'] == true;
    final needsFav = json['needs_favorite_artists'] == true;
    final needsTaste = json['needs_taste_profile'] == true;
    final needsHistory = json['needs_listening_history'] == true;
    final excludeFollowed = json['exclude_followed_artists'] == true;
    final excluded = (json['excluded_artists'] as List? ?? [])
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return PromptIntent(
      intentType: type,
      summary: summary,
      moodDimension: moodDim,
      activityDimension: actDim,
      environmentDimension: envDim,
      genres: genres,
      anchorArtists: anchorArtists,
      seedTracks: seedTracks,
      catalogQueries: catalogQueries,
      usePersonalHistory: useHistory,
      unheardOnly: unheard,
      needsFavoriteArtists: needsFav,
      needsTasteProfile: needsTaste,
      needsListeningHistory: needsHistory,
      excludeFollowedArtists: excludeFollowed,
      excludedArtists: excluded,
    );
  }
}

class GroqService {
  static const _apiUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const _model = 'openai/gpt-oss-120b';

  static const _deconstructSystemPrompt =
      r'''You are the world-class Music Intent & Semantic Deconstruction Engine for Melo.

MISSION:
Deconstruct the user's natural language music prompt into clear musical DNA, intent classification, authentic anchor artists, and precise catalog search queries.

MULTI-DIMENSIONAL TRIAD RULES (MOOD + ACTIVITY + ENVIRONMENT):
Users will freely combine any mix of:
- MOOD (Internal emotion / valence: nostalgic, confident, euphoric, heartbroken, peaceful, anxious, furious, hype, romantic, dreamy...)
- ACTIVITY (Action / Physical tempo: cooking, gym lifting, coding, studying, driving, meditating, gaming, running, reading, walking...)
- ENVIRONMENT (Setting / Acoustic texture: rainy coffeehouse, midnight neon highway, beach bonfire, dark bedroom, golden hour sunset, foggy forest, crowded train...)

When the user mixes 2 or 3 of these together:
1. HARMONIZE THE INTERSECTION: Do NOT drop any dimension. Synthesize the musical sonic world where all 3 coexist:
   - "Nostalgic (Mood) + Cooking (Activity) + Rainy Sunday (Environment)" -> Warm vinyl jazz, acoustic folk, Motown/bossa nova (Frank Sinatra, Norah Jones, Chet Baker, Stan Getz, Bill Withers).
   - "Confident (Mood) + Gym (Activity) + Dark Neon (Environment)" -> Dark phonk, hard trap, industrial bass (KORDHELL, Travis Scott, Ghostemane, DVRST).
   - "Peaceful (Mood) + Coding (Activity) + Rainy Café (Environment)" -> Ambient instrumental, lo-fi beats, neo-classical piano (Jinsang, Ludovico Einaudi, Chon, Idealism).
   - "Euphoric (Mood) + Road Trip (Activity) + Beach Sunset (Environment)" -> Nu-disco, indie surf-rock, French touch (Polo & Pan, Surfaces, Parcels, Daft Punk).
   - "Heartbroken (Mood) + Driving (Activity) + 2AM Rain (Environment)" -> Nocturnal indie ballad, atmospheric alternative R&B (The Weeknd, Joji, Frank Ocean, Phoebe Bridgers).
2. EXTRACT DIMENSIONS: Explicitly output "mood_dimension", "activity_dimension", and "environment_dimension" in JSON so the sonic identity is crystal clear.

INTENT CLASSIFICATION RULES:
1. SITUATIONAL_VIBE: Activities, times of day, or settings (e.g. "shower", "singing in the shower", "bath", "gym workout", "cooking dinner", "late night driving", "studying", "morning wake up"):
   - NEVER search for the literal situational or activity words in catalog_queries (e.g. NEVER search for songs titled "Shower", "Bath", "Gym", "Workout", "Cooking", "Drive", "Camping", "Morning"). Music catalog APIs will return cheap stock tracks or sound effects instead of real music.
   - ACTIVITY & SITUATION NUANCE:
     * Shower / Singing in the Shower / Bath -> Iconic sing-along anthems, high-energy joyful pop, unforgettable catchy choruses, feel-good throwback bangers (Pop, Dance-Pop, Disco-Pop, Motown, 2000s-2010s Pop Hits). People sing loudly in the shower! Provide 6-8 iconic sing-along powerhouse artists (e.g. Whitney Houston, Bruno Mars, Dua Lipa, Katy Perry, ABBA, Taylor Swift, Earth Wind & Fire, Carly Rae Jepsen, Maroon 5, Hall & Oates, Backstreet Boys, Kelly Clarkson). Seed tracks: "I Wanna Dance with Somebody" Whitney Houston, "Uptown Funk" Bruno Mars, "Don't Stop Believin'" Journey, "Dancing Queen" ABBA, "You Make My Dreams" Hall & Oates, "Call Me Maybe" Carly Rae Jepsen, "Since U Been Gone" Kelly Clarkson, "September" Earth Wind & Fire, "I Want It That Way" Backstreet Boys, "Levitating" Dua Lipa, "Firework" Katy Perry, "Hey Ya!" OutKast, "Can't Stop the Feeling!" Justin Timberlake, "Sugar" Maroon 5. NEVER output literal "shower" or "bath" keywords in catalog_queries.
     * Gym / Workout / Lifting -> Hard-hitting adrenaline, pumping beats (Phonk, Hard Trap, Bass House, Nu-Metal). Provide 6-8 anchor artists: KORDHELL, Travis Scott, Skrillex, Bring Me The Horizon, Kendrick Lamar, DMX, Fisher.
     * Cooking / Kitchen / Dinner -> Warm funk, neo-soul, upbeat groove pop, acoustic Motown, bossa nova (Leon Bridges, Tom Misch, Surfaces, Norah Jones, Cory Wong, Bill Withers, Parcels).
     * Studying / Reading / Coding / Focus -> Lo-fi beats, chillhop, ambient neo-classical piano, instrumental indie (Jinsang, Idealism, Ludovico Einaudi, Chon, Kudasaibeats). Zero distracting vocal shouting.
     * Morning / Waking Up -> Bright, warm, sunny, optimistic, coffeehouse feel-good (Sunny Indie Pop, Motown/Soul Funk, Upbeat Acoustic Pop, Feel-Good Neo-Soul). Provide 6-8 anchor artists: Surfaces, Bakar, Jack Johnson, Bruno Mars, Vance Joy, Remi Wolf, Rex Orange County, Leon Bridges. Seed tracks: "Sunday Best" Surfaces, "Put Your Records On" Ritt Momney, "Build Me Up Buttercup" The Foundations, "Daylight" Harry Styles, "Riptide" Vance Joy, "Lovely Day" Bill Withers, "Sunflower" Post Malone.
     * Late Night Drive -> Cinematic, nocturnal, atmospheric, midnight cruising (Synthwave, Nocturnal Alternative R&B, Midnight Dream Pop, Melodic Deep House). Provide 6-8 anchor artists: The Weeknd, Kavinsky, Frank Ocean, Joji, Beach House, Brent Faiyaz, M83, Steve Lacy. Seed tracks: "Blinding Lights" The Weeknd, "Nightcall" Kavinsky, "After Hours" The Weeknd, "Glimpse of Us" Joji, "Midnight City" M83, "Space Song" Beach House, "Ivy" Frank Ocean, "Redbone" Childish Gambino.
2. FRANCHISE_MEDIA: Video games, anime, movies, franchises (e.g. "valorant vibe", "naruto ost", "arcane", "cyberpunk", "gta").
   - Output official soundtrack artists, composers, and official publishers (e.g. Riot Games Music, Grabbitz, FLOW, Linked Horizon).
3. ARTIST_OR_SIMILARITY: Explicit artists, similar vibes, or "songs like [Track]" (e.g. "similar vibe to Wave to Earth", "songs like Starboy", "artists like keshi", "Tena and VannDa").
   - If user asks for "SIMILAR VIBE", "SONGS LIKE", or "MUSIC LIKE", extract the referenced artist PLUS 5-8 matching harmonic sonic neighbors (e.g. for Wave to Earth: keshi, slchld, The Poles, grentperez, HYBS, boy pablo, Dept, dosii).
   - If user asks strictly for ONE artist ONLY (e.g. "Wave to Earth only", "all songs by Wave to Earth"), anchor_artists must contain only that single artist.
4. PERSONALIZED_DISCOVERY: User explicitly asks for personal taste, favorite artists, or unheard music:
   - PRIORITY: If user mentions "my favorite artists", "my favorite artist", "artists I follow", "artists I love", "my artists":
     Set needs_favorite_artists = true, and classify intent_type as PERSONALIZED_DISCOVERY even if an emotional mood or genre is mentioned (e.g. "high energy from my favorite artists"). (Do NOT set needs_listening_history or needs_taste_profile unless also explicitly asked).
   - "based on my taste", "music I like", "my taste profile":
     Set needs_taste_profile = true.
   - "songs I haven't heard", "unheard", "never listened to", "new to me":
     Set unheard_only = true.
   - "my most listened songs", "on repeat", "heavy rotation":
     Set needs_listening_history = true.
   - "without my artists", "exclude my followed artists", "exclude [artist]":
     Set exclude_followed_artists = true, and put any named artists in excluded_artists.
   - CRITICAL: Never set any personal data flags for generic first-person requests such as "make me a pop playlist", "make me a study playlist", or "shower playlist". Conversational words like "me", "make me", "give me" do NOT mean personal history.
5. GENRE_ERA_CULTURE: Explicit genres, eras, or cultures (e.g. "80s synthpop", "90s boom bap", "classic 60s Khmer golden era").
6. EMOTIONAL_MOOD & ENERGY GRADIENTS: Emotional states or intensity levels (e.g. "energetic", "super energetic", "happy", "sad", "hype", "chill", "heartbroken", "feel good", "melancholy"):
   - CRITICAL: NEVER output literal mood or emotion words in catalog_queries (e.g. NEVER search for "happy", "energetic", "sad", "sad songs", "feel good", "heartbroken"). Music catalog APIs do NOT understand emotions in text search and will return cheap stock music titled "Energetic Workout" or "Sad Song".
   - ENERGY GRADIENTS & INTENSITY:
     * Super Energetic / Maximum Hype / Extreme -> High-BPM (130-155+ BPM), heavy drops, aggressive bass, peak adrenaline (Peak-Hour Festival EDM, Bass House, High-Octane Hip-Hop, Pop-Punk, Hard Dance). Provide 6-8 powerhouse hype artists (e.g. Skrillex, Fisher, Fred again.., Travis Scott, Peggy Gou, Kendrick Lamar, Martin Garrix, The Prodigy, Blink-182) and 8-12 high-BPM bangers (e.g. "Losing It" Fisher, "Turn On The Lights again.." Fred again.., "FE!N" Travis Scott, "Rumble" Skrillex, "Titanium" David Guetta, "HUMBLE." Kendrick Lamar, "All The Small Things" Blink-182, "Levels" Avicii, "Animals" Martin Garrix, "Can't Hold Us" Macklemore).
      * Standard Energetic / Happy / Feel-good -> Uplifting Dance Pop, Sunshine Pop, Funk Pop, Nu-Disco, Feel-Good Anthems (118-128 BPM). Provide 6-8 powerhouse feel-good anchor artists (e.g. Pharrell Williams, Surfaces, Bruno Mars, Dua Lipa, Justin Timberlake, Walk The Moon, Earth Wind & Fire, Calvin Harris, OneRepublic) and 8-12 iconic feel-good seed tracks (e.g. "Happy" Pharrell Williams, "Sunday Best" Surfaces, "Can't Stop the Feeling!" Justin Timberlake, "Levitating" Dua Lipa, "Uptown Funk" Mark Ronson, "24K Magic" Bruno Mars, "Shut Up and Dance" Walk the Moon, "September" Earth Wind & Fire, "Good Life" OneRepublic, "I Gotta Feeling" Black Eyed Peas, "Dance The Night" Dua Lipa, "Treasure" Bruno Mars). NEVER include dark heartbreak artists like The Weeknd, Joji, or Adele for happy prompts.
      * Sad / Heartbroken / Cry -> Piano Ballads, Melancholic Indie, Acoustic Pop, Heartbreak R&B. Provide 6-8 anchor artists (e.g. Adele, Olivia Rodrigo, Billie Eilish, Joji, Lewis Capaldi, Coldplay, Sam Smith) and 8-12 iconic sad seed tracks (e.g. "Someone Like You" Adele, "drivers license" Olivia Rodrigo, "Glimpse of Us" Joji, "Fix You" Coldplay, "lovely" Billie Eilish, "When I Was Your Man" Bruno Mars, "Someone You Loved" Lewis Capaldi, "traitor" Olivia Rodrigo, "The Scientist" Coldplay, "All I Want" Kodaline).
      * Chill / Relax / Calm -> Neo-Soul, R&B, Dream Pop, Acoustic Indie, Lo-Fi. Provide 6-8 anchor artists (e.g. Leon Bridges, Norah Jones, Mac Ayres, Daniel Caesar, keshi) and iconic chill tracks.
    - For catalog_queries: output ONLY specific artist queries (e.g. "artist:\"Dua Lipa\"") and specific iconic track names with artist (e.g. "\"Levitating\" Dua Lipa"), NEVER generic mood keywords.

OUTPUT FORMAT:
Output ONLY valid JSON:
{
  "needs_favorite_artists": false,
  "needs_taste_profile": false,
  "needs_listening_history": false,
  "unheard_only": false,
  "exclude_followed_artists": false,
  "excluded_artists": [],
  "intent_type": "SITUATIONAL_VIBE | FRANCHISE_MEDIA | ARTIST_OR_SIMILARITY | PERSONALIZED_DISCOVERY | GENRE_ERA_CULTURE | EMOTIONAL_MOOD",
  "mood_dimension": "Emotional state (e.g. Nostalgic, Confident, Melancholic, Euphoric)",
  "activity_dimension": "Activity (e.g. Cooking, Gym, Coding, Driving, Resting)",
  "environment_dimension": "Environment (e.g. Rainy café, Late night highway, Beach sunset)",
  "summary": "Brief explanation of the musical vibe",
  "genres": ["Genre1", "Genre2"],
  "anchor_artists": ["Artist1", "Artist2", "Artist3", "Artist4", "Artist5"],
  "seed_tracks": ["Track Title 1", "Track Title 2", "Track Title 3", "Track Title 4", "Track Title 5", "Track Title 6", "Track Title 7", "Track Title 8"],
  "catalog_queries": ["artist:\"Artist1\"", "artist:\"Artist2\"", "\"Track Title 1\" Artist1"]
}''';

  static const _moodSystemPrompt =
      'You are an elite, Grammy-caliber music curator, tastemaker, and sonic director with encyclopedic knowledge of all music eras (1960s to 2026), anime soundtracks, video games, genres, and cultural movements.\n\n'
      'MISSION:\n'
      'Given any user prompt (mood, situation, anime franchise, movie/game universe, or era), create the DEFINITIVE, culturally accurate playlist.\n\n'
      'CURATION STANDARDS:\n'
      '1. ANIME & FRANCHISE ACCURACY:\n'
      '   * When asked for anime/franchise songs (e.g. One Piece, Naruto, Naruto Shippuden, Attack on Titan, Demon Slayer, Bleach, Dragon Ball, JJK):\n'
      '     - List the genuine official chronological opening/theme songs.\n'
      '     - For Naruto & Naruto Shippuden, output real openings: "Rocks" (Hound Dog), "Haruka Kanata" (Asian Kung-Fu Generation), "Kanashimi wo Yasashisa ni" (little by little), "GO!!!" (FLOW), "Seishun Kyousoukyoku" (Sambomaster), "No Boy No Cry" (STANCE PUNKS), "Namikaze Satellite" (Snowkel), "Re:member" (FLOW), "Yura Yura" (Hearts Grow), "Hero\'s Come Back!!" (nobodyknows+), "Distance" (LONG SHOT PARTY), "Blue Bird" (Ikimonogakari), "CLOSER" (Joe Inoue), "Hotaru no Hikari" (Ikimonogakari), "Sign" (FLOW), "Toumei Datta Sekai" (Motohiro Hata), "Diver" (NICO Touches the Walls), "Lovers" (7!!), "newsong" (tacica), "Totsugeki Rock" (THE CRO-MAGNONS), "Moshimo" (Daisuke), "Niwaka Ame ni mo Makezu" (NICO Touches the Walls), "Tsuki no Juuryoku" (Daisuke), "Guren" (DOES), "Silhouette" (KANA-BOON), "Kaze" (Yamazaru), "LINE" (Sukima Switch), "Blood Circulator" (Asian Kung-Fu Generation), "Kara no Kokoro" (Anly).\n'
      '     - For One Piece, output real openings: "We Are!" (Hiroshi Kitadani), "Believe" (Folder5), "Hikari E" (The Babystars), "BON VOYAGE!" (Bon-Bon Blanco), "Kokoro no Chizu" (BOYSTYLE), "BRAND NEW WORLD" (D-51), "Jungle P" (5050), "Share The World" (TVXQ), "One day" (The ROOTLESS), "Fight Together" (Namie Amuro), "We Go!" (Hiroshi Kitadani), "Hands Up!" (Kota Shinzato), "Wake up!" (AAA), "Hard Knock Days" (GENERATIONS from EXILE TRIBE), "Hope" (Namie Amuro), "Super Powers" (V6), "OVER THE TOP" (Hiroshi Kitadani), "DREAMIN\' ON" (Da-iCE), "PAINT" (I Don\'t Like Mondays), "Peak" (SEKAI NO OWARI), "UUUUUS!" (Hiroshi Kitadani).\n'
      '2. NATURAL CONVERSATIONAL INTENT UNDERSTANDING:\n'
      '   * Users will speak naturally, casually, or colloquially (e.g., "songs like X", "vibe with this", "similar to X", "something like this", "same energy", "stuff like X", "make a playlist like this", Khmer text, or slang).\n'
      '   * NEVER require rigid formatting. Understand what the user wants whether they type one word, a casual sentence, or select multiple chips.\n'
      '   * If they reference a song or artist: identify the core genre, tempo, mood, and instrumentation, include the referenced track, and surround it with culturally authentic, high-quality songs that fit the exact vibe from any matching artists.\n'
      '   * If they ask for songs by ONLY one artist (e.g. "all songs from X", "only X", "X discography"): provide strictly that artist.\n'
      '3. VIBE FIDELITY & ATMOSPHERE: Every selected track must fit the exact sonic texture, mood, and energy level of the prompt.\n'
      '4. PURE STUDIO ORIGINALS: Strictly no cover bands, karaoke, or tribute artists.\n'
      '5. SEARCH ALIAS: Include a `search_alias` field for each song to assist streaming catalog matching.\n'
      '6. SONG REFERENCES: When reference tracks or chips are present, ALWAYS include them in the playlist alongside complementary tracks from matching artists.\n\n'
      'OUTPUT FORMAT:\n'
      'Output ONLY valid JSON:\n'
      '{\n'
      '  "title": "Evocative, stylish title for the playlist",\n'
      '  "description": "Short, poetic description capturing the mood",\n'
      '  "songs": [\n'
      '    {"title": "Exact Song Title", "artist": "Official Artist Name", "search_alias": "Song Title Artist Name"}\n'
      '  ]\n'
      '}';

  static const _models = [
    'qwen/qwen3.8-27b',
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
  ];

  static const _curatorSystemPrompt =
      'You are an elite music curator and sonic director for Melo.\n'
      'You are given:\n'
      '1. The user\'s theme, mood, or prompt (may be in Khmer, English, or mixed).\n'
      '2. A numbered list of REAL, VERIFIED candidate tracks with IDs [0, 1, 2, ...].\n\n'
      'YOUR JOB:\n'
      'Select and order the best candidate indices that fit the user\'s requested vibe.\n\n'
      'CRITICAL RULES:\n'
      '- PRIMARY ANCHORS: If the prompt contains "Artists: [Name]" or "Tracks: [Name]" (from user selected chips), ALWAYS prioritize and include those specific artists/tracks as the core of the playlist.\n'
      '- Return ONLY indices that exist in the candidate list. NEVER invent titles, artists, or new IDs.\n'
      '- Select up to the requested count of tracks.\n'
      '- Aim for ~30% well-known anchor tracks and ~70% good-but-less-obvious tracks from the pool.\n'
      '- EMOTIONAL VALENCE & MOOD FIDELITY (ZERO TOLERANCE):\n'
      '  * If prompt is for HAPPY / FEEL-GOOD / JOYFUL / CHEERFUL / UPBEAT: Every selected track MUST be positive, joyful, and uplifting in tone, tempo, and theme. STRICTLY DISCARD any sad songs, breakup ballads, heartbreak laments, or songs about crying or dying (e.g. reject "Die With A Smile", "Scared to Be Lonely", "Sad Girls", "Save Your Tears", "When I Was Your Man", "Someone Like You").\n'
      '  * If prompt is for SAD / HEARTBROKEN / CRYING / MELANCHOLY: Every selected track MUST be emotional, reflective, and touching. STRICTLY DISCARD upbeat party bangers, club anthems, and ecstatic dance tracks.\n'
      '- ORIGINAL ARTISTS ONLY: STRICTLY reject cover versions, student ensembles, karaoke, and tribute bands.\n'
      '- Output ONLY valid JSON in this exact structure with no extra text or markdown:\n'
      '{\n'
      '  "title": "Creative playlist title",\n'
      '  "description": "Short mood description",\n'
      '  "selected_indices": [0, 5, 12, ...]\n'
      '}';

  /// Pass 1: Intent & Musical Semantic Deconstruction
  static Future<PromptIntent?> deconstructPromptIntent(
    String prompt, {
    String userProfileContext = '',
  }) async {
    final apiKey = await SecureStorageService.groqApiKeyVal;
    if (apiKey.isEmpty || prompt.trim().isEmpty) return null;

    final userBuf = StringBuffer();
    userBuf.writeln('USER PROMPT: "$prompt"');
    if (userProfileContext.isNotEmpty) {
      userBuf.writeln(
          '\nUSER PROFILE / PREFERENCES (FOR REFERENCE):\n$userProfileContext');
    }
    userBuf.writeln(
        '\nDeconstruct this music prompt into structured JSON following your system prompt.');

    for (final model in _models) {
      try {
        final bodyMap = <String, dynamic>{
          'model': model,
          'messages': [
            {'role': 'system', 'content': _deconstructSystemPrompt},
            {'role': 'user', 'content': userBuf.toString()},
          ],
          'temperature': 0.2,
          'max_tokens': 1500,
        };
        if (!model.contains('openai')) {
          bodyMap['response_format'] = {'type': 'json_object'};
        }

        final resp = await http
            .post(
              Uri.parse(_apiUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $apiKey',
              },
              body: jsonEncode(bodyMap),
            )
            .timeout(const Duration(seconds: 15));

        if (resp.statusCode == 200) {
          final json = jsonDecode(resp.body);
          final rawContent = json['choices']?[0]?['message']?['content'];
          final content = rawContent?.toString().trim() ?? '';
          if (content.isEmpty) continue;
          final cleaned = content
              .replaceAll(RegExp(r'^```(json)?\s*'), '')
              .replaceAll(r'\s*```$', '');
          String jsonStr = cleaned;
          final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
          if (jsonMatch != null) {
            jsonStr = jsonMatch.group(0)!;
          }
          final root = jsonDecode(jsonStr) as Map<String, dynamic>;
          return PromptIntent.fromJson(root, prompt);
        }
      } catch (e) {
        print('[Groq] Intent deconstruction error with model $model: $e');
      }
    }
    return null;
  }

  /// RAG Curation: Selects and orders tracks from a verified candidate pool by index.
  static Future<Map<String, dynamic>> curateFromCandidatePool(
    String prompt,
    List<Map<String, dynamic>> candidatePool, {
    int targetCount = 20,
    String userContext = '',
  }) async {
    final apiKey = await SecureStorageService.groqApiKeyVal;
    if (apiKey.isEmpty || candidatePool.isEmpty) {
      return {'success': false};
    }

    // Cap candidate list to 60 so Groq prompt tokens stay low and never crash
    final limitedPool = candidatePool.take(60).toList();
    final poolBuf = StringBuffer();
    for (int i = 0; i < limitedPool.length; i++) {
      final c = limitedPool[i];
      final title = c['title'] ?? '';
      final artist = c['artist'] ?? '';
      poolBuf.writeln('[$i] "$title" - $artist');
    }

    final userBuf = StringBuffer();
    userBuf.writeln('THEME / PROMPT: "$prompt"');
    userBuf.writeln('REQUESTED COUNT: $targetCount tracks');
    if (userContext.isNotEmpty) {
      userBuf.writeln('USER CONTEXT:\n$userContext');
    }
    userBuf
        .writeln('\nCANDIDATE POOL (${limitedPool.length} verified tracks):');
    userBuf.writeln(poolBuf.toString());
    userBuf.writeln(
        'Select the best $targetCount indices from the candidate pool above in optimal playlist order.\n'
        'Return ONLY valid JSON matching: {"title": "...", "description": "...", "selected_indices": [index1, index2, ...]}');

    for (final model in _models) {
      try {
        final bodyMap = <String, dynamic>{
          'model': model,
          'messages': [
            {'role': 'system', 'content': _curatorSystemPrompt},
            {'role': 'user', 'content': userBuf.toString()},
          ],
          'temperature': 0.6,
          'max_tokens': 2000,
        };
        if (!model.contains('openai')) {
          bodyMap['response_format'] = {'type': 'json_object'};
        }

        final resp = await http
            .post(
              Uri.parse(_apiUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $apiKey',
              },
              body: jsonEncode(bodyMap),
            )
            .timeout(const Duration(seconds: 25));

        if (resp.statusCode == 200) {
          final json = jsonDecode(resp.body);
          final rawContent = json['choices']?[0]?['message']?['content'];
          final content = rawContent?.toString().trim() ?? '';
          if (content.isEmpty) {
            print('[Groq] Curator empty content from model $model');
            continue;
          }
          final cleaned = content
              .replaceAll(RegExp(r'^```(json)?\s*'), '')
              .replaceAll(r'\s*```$', '');
          String jsonStr = cleaned;
          final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
          if (jsonMatch != null) {
            jsonStr = jsonMatch.group(0)!;
          }
          final root = jsonDecode(jsonStr) as Map<String, dynamic>;

          final title = root['title']?.toString() ?? '';
          final description = root['description']?.toString() ?? '';
          final indicesRaw = root['selected_indices'] as List? ?? [];
          final indices = indicesRaw
              .map((e) => (e is num) ? e.toInt() : int.tryParse(e.toString()))
              .whereType<int>()
              .where((idx) => idx >= 0 && idx < candidatePool.length)
              .toList();

          if (indices.isNotEmpty) {
            return {
              'success': true,
              'title': title,
              'description': description,
              'selected_indices': indices,
            };
          }
        }
      } catch (e) {
        print('[Groq] Curator error with model $model: $e');
      }
    }
    return {'success': false};
  }

  /// Generate a mood-based playlist from Groq AI.
  /// Returns {title, description, songs: [{title, artist}]}.
  static Future<Map<String, dynamic>> generateMoodPlaylist(
    String mood, {
    int size = 20,
    String tasteContext = '',
    String webContext = '',
  }) async {
    final apiKey = await SecureStorageService.groqApiKeyVal;

    final promptBuf = StringBuffer();
    promptBuf.write('Create a playlist for: "$mood"\n\n');
    promptBuf.write('Desired count: $size songs\n\n');
    if (tasteContext.isNotEmpty) promptBuf.write('$tasteContext\n');
    if (webContext.isNotEmpty) {
      promptBuf.write(
          'Web context (verified tracks for this theme):\n$webContext\n\n');
    }
    promptBuf.write(
        'Return ONLY valid JSON matching this exact structure with no extra keys:\n'
        '{\n'
        '  "title": "Playlist Title",\n'
        '  "description": "Playlist description",\n'
        '  "songs": [\n'
        '    {"title": "Song Title", "artist": "Artist Name", "search_alias": "Song Title Artist Name"}\n'
        '  ]\n'
        '}');

    for (final model in _models) {
      try {
        final bodyMap = <String, dynamic>{
          'model': model,
          'messages': [
            {'role': 'system', 'content': _moodSystemPrompt},
            {'role': 'user', 'content': promptBuf.toString()},
          ],
          'temperature': 0.7,
          'max_tokens': (size * 90 + 400).clamp(600, 4000),
        };
        if (!model.contains('openai')) {
          bodyMap['response_format'] = {'type': 'json_object'};
        }

        final resp = await http
            .post(
              Uri.parse(_apiUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $apiKey',
              },
              body: jsonEncode(bodyMap),
            )
            .timeout(const Duration(seconds: 30));

        if (resp.statusCode == 200) {
          final json = jsonDecode(resp.body);
          final content = json['choices'][0]['message']['content'] as String;
          final cleaned = content
              .trim()
              .replaceAll(RegExp(r'^```(json)?\s*'), '')
              .replaceAll(r'\s*```$', '');
          final root = jsonDecode(cleaned) as Map<String, dynamic>;

          final title = root['title']?.toString() ?? '';
          final description = root['description']?.toString() ?? '';
          final songsRaw = root['songs'] as List? ?? [];
          final songs = songsRaw
              .where((s) => s['title'] != null && s['artist'] != null)
              .take(size)
              .map((s) => {
                    'title': s['title'].toString().trim(),
                    'artist': s['artist'].toString().trim(),
                    'search_alias': s['search_alias']?.toString().trim() ?? '',
                  })
              .toList();

          if (songs.isNotEmpty) {
            return {
              'success': true,
              'title': title,
              'description': description,
              'songs': songs,
            };
          }
        } else {
          print(
              '[Groq] Model $model failed with status ${resp.statusCode}: ${resp.body}');
        }
      } catch (e) {
        print('[Groq] Error with model $model: $e');
      }
    }
    return {'success': false, 'songs': []};
  }

  /// Generate daily vibe playlists for multiple genres.
  /// Returns {genre: [{title, artist}]}.
  static Future<Map<String, List<Map<String, String>>>> generateVibePlaylists(
    List<String> genres, {
    Map<String, List<Map<String, Object>>> historyByGenre = const {},
    Map<String, List<String>> recommendMoreByGenre = const {},
    Map<String, List<String>> recommendLessByGenre = const {},
  }) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final apiKey = await SecureStorageService.groqApiKeyVal;

        final promptBuf = StringBuffer();
        promptBuf.write('Generate playlists of 20 songs for each genre: ');
        promptBuf.write(genres.join(', '));
        promptBuf.write('.\n\n');

        for (final genre in genres) {
          promptBuf.write('--- $genre ---\n');
          final history = historyByGenre[genre] ?? [];
          for (final entry in history) {
            final title = entry['title'] ?? '';
            final artist = entry['artist'] ?? '';
            final skipped = entry['skipped'] == true;
            final completed = entry['completed'] == true;
            final replayed = entry['replayed'] == true;
            promptBuf.write('- "$title" by $artist');
            if (skipped)
              promptBuf.write(' [SKIPPED]');
            else if (replayed)
              promptBuf.write(' [REPLAYED]');
            else if (completed) promptBuf.write(' [COMPLETED]');
            promptBuf.write('\n');
          }
          final more = recommendMoreByGenre[genre] ?? [];
          if (more.isNotEmpty)
            promptBuf.write('Wants MORE of: ${more.join(', ')}\n');
          final less = recommendLessByGenre[genre] ?? [];
          if (less.isNotEmpty)
            promptBuf.write('Wants LESS of: ${less.join(', ')}\n');
          promptBuf.write('\n');
        }

        promptBuf.write(
            'Return JSON: {"${genres.first}": [{"title": "...", "artist": "..."}, ...]');
        for (int i = 1; i < genres.length; i++) {
          promptBuf.write(
              ', "${genres[i]}": [{"title": "...", "artist": "..."}, ...]');
        }
        promptBuf.write('}');

        final resp = await http
            .post(
              Uri.parse(_apiUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $apiKey',
              },
              body: jsonEncode({
                'model': _model,
                'messages': [
                  {
                    'role': 'system',
                    'content':
                        'You are a music recommendation AI. Return ONLY a JSON object where each key is a genre '
                            'and each value is a JSON array of 20 objects with \'title\' and \'artist\' fields only. '
                            'No markdown, no explanation, just the JSON object.',
                  },
                  {'role': 'user', 'content': promptBuf.toString()},
                ],
                'temperature': 0.8,
                'max_tokens': 5000,
              }),
            )
            .timeout(const Duration(seconds: 60));

        if (resp.statusCode == 200) {
          final json = jsonDecode(resp.body);
          final content = json['choices'][0]['message']['content'] as String;
          final cleaned = content
              .trim()
              .replaceAll(RegExp(r'^```(json)?\s*'), '')
              .replaceAll(r'\s*```$', '');
          final root = jsonDecode(cleaned) as Map<String, dynamic>;

          final result = <String, List<Map<String, String>>>{};
          for (final genre in genres) {
            final songsRaw = root[genre] as List? ?? [];
            result[genre] = songsRaw
                .where((s) => s['title'] != null && s['artist'] != null)
                .take(20)
                .map((s) => {
                      'title': s['title'].toString(),
                      'artist': s['artist'].toString()
                    })
                .toList();
          }
          return result;
        }

        if (resp.statusCode == 429 && attempt == 1) {
          await Future.delayed(const Duration(seconds: 35));
          continue;
        }

        print('[Groq] Vibe generation failed: ${resp.statusCode}');
        return {};
      } catch (e) {
        print('[Groq] Vibe generation error: $e');
        if (attempt == 1) {
          await Future.delayed(const Duration(seconds: 35));
          continue;
        }
        return {};
      }
    }
    return {};
  }
}
