import 'dart:convert';
import 'package:http/http.dart' as http;
import 'groq_service.dart';
import 'secure_storage_service.dart';

class GeminiService {
  static const _model = 'gemini-2.5-flash';
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  static const _deconstructInstruction =
      'You are the world-class Music Intent & Semantic Deconstruction Engine for Melo.\n'
      'Deconstruct the user\'s natural language music prompt into musical DNA, intent classification, authentic anchor artists, and precise catalog search queries.\n'
      'MULTI-DIMENSIONAL TRIAD (MOOD + ACTIVITY + ENVIRONMENT):\n'
      'Users will combine any mix of MOOD (happy, energetic, sad, chill, nostalgic, euphoric), ACTIVITY (morning routine, late night drive, gym workout, coding, cooking), and ENVIRONMENT/WEATHER (sunny day, rainy day, snowy, beach sunset, dark bedroom). Harmonize the intersection of all dimensions into an authentic sonic identity.\n'
      'INTENT RULES:\n'
      '1. SITUATIONAL_VIBE: Activities, times of day, weather, or settings. Context: Sunny Morning (Surfaces, Bakar, Jack Johnson, Bruno Mars; sunny indie/funk/acoustic), Late Night Drive (The Weeknd, Kavinsky, Frank Ocean, Joji; synthwave, nocturnal R&B), Gym/Workout (Phonk, hard trap, bass house), Rainy Day (Jinsang, Adele, Joji, Bon Iver). Never search literal situation words.\n'
      '2. FRANCHISE_MEDIA: Video games, anime, movies (Valorant, Naruto, Arcane). Output official soundtrack artists/composers and publishers.\n'
      '3. ARTIST_OR_SIMILARITY: Explicit artists or "songs like [Track]". Extract target artists and related sonic neighbors.\n'
      '4. PERSONALIZED_DISCOVERY: User asks for personal taste, favorite artists, or unheard music:\n'
      '   - "my favorite artists", "artists I follow", "my artists": needs_favorite_artists = true.\n'
      '   - "based on my taste", "music I like": needs_taste_profile = true.\n'
      '   - "songs I haven\'t heard", "unheard": unheard_only = true.\n'
      '   - "my most listened songs", "on repeat": needs_listening_history = true.\n'
      '   - "without my artists", "exclude my artists": exclude_followed_artists = true.\n'
      '   - Never set personal flags for generic requests ("make me a pop playlist", "workout"). Words like "me" do NOT mean personal history.\n'
      '5. GENRE_ERA_CULTURE: Explicit genres, eras (80s synthpop, 90s boom bap, 60s Khmer).\n'
      '6. EMOTIONAL_MOOD: Emotional states or energy levels. Intensity: Super Energetic/Maximum Hype (135-155+ BPM festival EDM, bass house, hype hip-hop: Skrillex, Fisher, Travis Scott, Fred again..), Standard Energetic / Happy (120-128 BPM: Pharrell Williams, Surfaces, Bruno Mars, Dua Lipa, Justin Timberlake, Walk The Moon, Earth Wind & Fire; sunny dance pop, funk, feel-good anthems), Sad/Heartbroken (Adele, Olivia Rodrigo, Joji, Coldplay), Chill/Relax (Leon Bridges, keshi, Norah Jones). NEVER output literal emotion words in catalog_queries. Translate to genres, 6-8 anchor artists, and 8-12 iconic seed tracks.\n'
      'Output ONLY valid JSON: {"needs_favorite_artists": false, "needs_taste_profile": false, "needs_listening_history": false, "unheard_only": false, "exclude_followed_artists": false, "excluded_artists": [], "intent_type": "...", "mood_dimension": "...", "activity_dimension": "...", "environment_dimension": "...", "summary": "...", "genres": [...], "anchor_artists": [...], "seed_tracks": [...], "catalog_queries": [...]}';

  static const _systemInstruction =
      'You are an elite music director with access to real-time Google Search.\n'
      'Given any music theme, franchise, anime (e.g. One Piece, Naruto, Attack on Titan, Bleach), movie, World Cup, or artist:\n'
      '1. Complete chronological span up to CURRENT YEAR (2024-2026): Find all official opening and theme songs across every season and arc from opening 1 all the way up to the latest current arc.\n'
      '2. Canonical streaming names: For anime/Japanese tracks, output canonical official titles and artists.\n'
      '3. Search Alias: Provide a search_alias (e.g. "We Are One Piece", "Believe Folder5", "Fight Together Namie Amuro") for reliable catalog matching.\n'
      '4. Output ONLY valid JSON: {"title": "...", "description": "...", "songs": [{"title": "...", "artist": "...", "search_alias": "..."}]}';

  /// Generate a playlist using Google Gemini with Live Google Search Grounding.
  static Future<Map<String, dynamic>> generatePlaylist(
    String mood, {
    int size = 20,
    String tasteContext = '',
    String webContext = '',
  }) async {
    try {
      final apiKey = await SecureStorageService.geminiApiKeyVal;
      if (apiKey.isEmpty) {
        return {'success': false, 'error': 'No Gemini API key configured'};
      }

      final promptBuf = StringBuffer();
      promptBuf.write('Create a $size-song playlist for: "$mood"\n\n');
      if (tasteContext.isNotEmpty)
        promptBuf.write('User Taste Context:\n$tasteContext\n\n');
      if (webContext.isNotEmpty)
        promptBuf.write('Catalog Reference:\n$webContext\n\n');
      promptBuf.write(
          'Use Google Search to find the official canonical songs for "$mood".\n'
          'Return ONLY valid JSON matching this schema: {"title": "...", "description": "...", "songs": [{"title": "...", "artist": "...", "search_alias": "..."}]}');

      final url = '$_baseUrl/$_model:generateContent?key=$apiKey';
      final resp = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': _systemInstruction}
                ]
              },
              'contents': [
                {
                  'parts': [
                    {'text': promptBuf.toString()}
                  ]
                }
              ],
              'tools': [
                {'google_search': {}}
              ],
              'generationConfig': {
                'temperature': 0.2,
                'thinkingConfig': {'thinkingBudget': 0},
              }
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final candidates = data['candidates'] as List? ?? [];
        if (candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          final parts = content?['parts'] as List? ?? [];
          if (parts.isNotEmpty) {
            final rawText = parts[0]['text']?.toString() ?? '';

            // Extract JSON substring reliably from response
            String jsonStr = rawText.trim();
            final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
            if (jsonMatch != null) {
              jsonStr = jsonMatch.group(0)!;
            }

            final root = jsonDecode(jsonStr) as Map<String, dynamic>;
            final title = root['title']?.toString() ?? mood;
            final description = root['description']?.toString() ?? '';
            final songsRaw = root['songs'] as List? ?? [];
            final songs = songsRaw
                .whereType<Map<String, dynamic>>()
                .where((s) => s['title'] != null && s['artist'] != null)
                .take(size)
                .map((s) => {
                      'title': s['title'].toString().trim(),
                      'artist': s['artist'].toString().trim(),
                      'search_alias':
                          s['search_alias']?.toString().trim() ?? '',
                    })
                .toList();

            if (songs.isNotEmpty) {
              return {
                'success': true,
                'title': title,
                'description': description,
                'songs': songs,
                'source': 'gemini_google_search',
              };
            }
          }
        }
      } else {
        print('[Gemini] API error ${resp.statusCode}: ${resp.body}');
      }
    } catch (e, st) {
      print('[Gemini] Error generating with Google Search: $e\n$st');
    }

    return {'success': false, 'songs': []};
  }

  /// Curation fallback from candidate pool using Gemini
  static Future<Map<String, dynamic>> curateFromCandidatePool(
    String prompt,
    List<Map<String, dynamic>> candidatePool, {
    int targetCount = 20,
    String userContext = '',
  }) async {
    try {
      final apiKey = await SecureStorageService.geminiApiKeyVal;
      if (apiKey.isEmpty || candidatePool.isEmpty) {
        return {'success': false};
      }

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

      final url = '$_baseUrl/$_model:generateContent?key=$apiKey';
      final resp = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {
                    'text':
                        'You are an elite music curator for Melo. Select up to the requested number of track indices from the provided candidate list. Never invent titles, artists, or indices.\n'
                        'EMOTIONAL VALENCE & MOOD FIDELITY (ZERO TOLERANCE):\n'
                        '- If prompt is for HAPPY / FEEL-GOOD / JOYFUL / CHEERFUL / UPBEAT: Every selected track MUST be positive, joyful, and uplifting. STRICTLY REJECT any sad songs, breakup ballads, heartbreak laments, and songs about crying or dying (e.g. reject "Die With A Smile", "Scared to Be Lonely", "Sad Girls", "Save Your Tears", "When I Was Your Man", "Someone Like You").\n'
                        '- If prompt is for SAD / HEARTBROKEN / CRYING: Select only melancholic, emotional ballads. Strictly reject club bangers, party tracks, and ecstatic dance songs.\n'
                        '- STUDIO ORIGINALS ONLY: Strictly reject cover versions, student ensembles, karaoke, and tribute bands.\n'
                        'Return only JSON: {"title": "...", "description": "...", "selected_indices": [0, 1, ...]}'
                  }
                ]
              },
              'contents': [
                {
                  'parts': [
                    {'text': userBuf.toString()}
                  ]
                }
              ],
              'generationConfig': {
                'temperature': 0.3,
                'responseMimeType': 'application/json',
              }
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final candidates = data['candidates'] as List? ?? [];
        if (candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          final parts = content?['parts'] as List? ?? [];
          if (parts.isNotEmpty) {
            final rawText = parts[0]['text']?.toString() ?? '';
            String jsonStr = rawText.trim();
            final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
            if (jsonMatch != null) {
              jsonStr = jsonMatch.group(0)!;
            }

            final root = jsonDecode(jsonStr) as Map<String, dynamic>;
            final title = root['title']?.toString() ?? prompt;
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
        }
      }
    } catch (e) {
      print('[Gemini] Curator error: $e');
    }
    return {'success': false};
  }

  /// Pass 1: Intent & Musical Semantic Deconstruction Fallback via Gemini
  static Future<PromptIntent?> deconstructPromptIntent(
    String prompt, {
    String userProfileContext = '',
  }) async {
    try {
      final apiKey = await SecureStorageService.geminiApiKeyVal;
      if (apiKey.isEmpty || prompt.trim().isEmpty) return null;

      final promptBuf = StringBuffer();
      promptBuf.writeln('USER PROMPT: "$prompt"');
      if (userProfileContext.isNotEmpty) {
        promptBuf.writeln('\nUSER PROFILE CONTEXT:\n$userProfileContext');
      }
      promptBuf.writeln(
          '\nDeconstruct this music prompt into structured JSON according to instructions.');

      final url = '$_baseUrl/$_model:generateContent?key=$apiKey';
      final resp = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': _deconstructInstruction}
                ]
              },
              'contents': [
                {
                  'parts': [
                    {'text': promptBuf.toString()}
                  ]
                }
              ],
              'generationConfig': {
                'temperature': 0.2,
                'responseMimeType': 'application/json',
                'thinkingConfig': {'thinkingBudget': 0},
              }
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final candidates = data['candidates'] as List? ?? [];
        if (candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          final parts = content?['parts'] as List? ?? [];
          if (parts.isNotEmpty) {
            final rawText = parts[0]['text']?.toString() ?? '';
            String jsonStr = rawText.trim();
            final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
            if (jsonMatch != null) {
              jsonStr = jsonMatch.group(0)!;
            }
            final root = jsonDecode(jsonStr) as Map<String, dynamic>;
            return PromptIntent.fromJson(root, prompt);
          }
        }
      }
    } catch (e) {
      print('[Gemini] Deconstruct intent error: $e');
    }
    return null;
  }
}
