import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class LyricLine {
  final Duration time;
  final String text;

  LyricLine({required this.time, required this.text});

  Map<String, dynamic> toJson() => {
        'ms': time.inMilliseconds,
        'text': text,
      };

  factory LyricLine.fromJson(Map<String, dynamic> json) => LyricLine(
        time: Duration(milliseconds: json['ms'] as int),
        text: json['text'] as String,
      );
}

class LyricsResult {
  final List<LyricLine>? syncedLyrics;
  final String? plainLyrics;
  final double? officialDuration;

  LyricsResult({this.syncedLyrics, this.plainLyrics, this.officialDuration});

  Map<String, dynamic> toJson() => {
        if (syncedLyrics != null)
          'synced': syncedLyrics!.map((l) => l.toJson()).toList(),
        if (plainLyrics != null) 'plain': plainLyrics,
        if (officialDuration != null) 'duration': officialDuration,
      };

  factory LyricsResult.fromJson(Map<String, dynamic> json) => LyricsResult(
        syncedLyrics: json['synced'] != null
            ? (json['synced'] as List)
                .map((e) => LyricLine.fromJson(e))
                .toList()
            : null,
        plainLyrics: json['plain'] as String?,
        officialDuration: json['duration'] as double?,
      );

  String toLrc() {
    if (syncedLyrics == null || syncedLyrics!.isEmpty) return plainLyrics ?? '';
    final buf = StringBuffer();
    for (final line in syncedLyrics!) {
      final ms = line.time.inMilliseconds;
      final min = (ms ~/ 60000).toString().padLeft(2, '0');
      final sec = ((ms ~/ 1000) % 60).toString().padLeft(2, '0');
      final frac = ((ms ~/ 10) % 100).toString().padLeft(2, '0');
      buf.writeln('[$min:$sec.$frac]${line.text}');
    }
    return buf.toString();
  }
}

class LyricsService {
  static const _headers = {'User-Agent': 'Melo/1.0'};
  static Directory? _cacheDir;

  static Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${appDir.path}/lyrics_cache_v2');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    // Clean up old legacy cache directory in background to purge corrupted lyrics
    try {
      final oldDir = Directory('${appDir.path}/lyrics_cache');
      if (await oldDir.exists()) {
        await oldDir.delete(recursive: true);
      }
    } catch (_) {}
    return _cacheDir!;
  }

  static String cleanTitle(String title) {
    var cleaned = title.trim();
    // Remove (feat. ...), [feat. ...], (ft. ...)
    cleaned = cleaned.replaceAll(
        RegExp(r'\s*[\(\[](feat\.?|ft\.?)\s+[^\)\]]+[\)\]]',
            caseSensitive: false),
        '');
    // Remove (Official Video), (Official Audio), [MV], (Lyric Video), etc.
    cleaned = cleaned.replaceAll(
        RegExp(
            r'\s*[\(\[](official\s+(video|audio|music\s+video|lyric\s+video|visualizer)|lyrics?|lyric\s+video|audio|mv|visualizer|remastered|live)[\)\]]',
            caseSensitive: false),
        '');
    // Remove trailing " - Official Video", " | Lyric Video", etc.
    cleaned = cleaned.replaceAll(
        RegExp(
            r'\s*[-|]\s*(official\s+video|official\s+audio|lyric\s+video|audio|lyrics?)\s*$',
            caseSensitive: false),
        '');
    return cleaned.trim().isEmpty ? title : cleaned.trim();
  }

  static String cleanArtist(String artist) {
    // If multi-artist string (e.g. "The Weeknd, Daft Punk" or "Coldplay ft. BTS"), extract primary artist
    final parts = artist.split(
        RegExp(r'[,&]|\s+(feat\.?|ft\.?|x|with)\s+', caseSensitive: false));
    if (parts.isNotEmpty && parts.first.trim().isNotEmpty) {
      return parts.first.trim();
    }
    return artist.trim();
  }

  static String _normalize(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u1780-\u17FF]'), '');
  }

  static bool _artistMatches(String expected, String candidate) {
    if (expected.trim().isEmpty || candidate.trim().isEmpty) return true;
    final expNorm = _normalize(expected);
    final candNorm = _normalize(candidate);

    if (expNorm == candNorm) return true;
    if (expNorm.contains(candNorm) || candNorm.contains(expNorm)) return true;

    // Check individual words / artist names (ignore common joiners)
    final expWords = expected
        .toLowerCase()
        .split(RegExp(r'[\s,&/\-_]+'))
        .where((w) =>
            w.length >= 3 &&
            w != 'feat' &&
            w != 'the' &&
            w != 'and' &&
            w != 'with')
        .map(_normalize)
        .where((w) => w.isNotEmpty)
        .toSet();

    final candWords = candidate
        .toLowerCase()
        .split(RegExp(r'[\s,&/\-_]+'))
        .where((w) =>
            w.length >= 3 &&
            w != 'feat' &&
            w != 'the' &&
            w != 'and' &&
            w != 'with')
        .map(_normalize)
        .where((w) => w.isNotEmpty)
        .toSet();

    return expWords.intersection(candWords).isNotEmpty;
  }

  static String _cacheKey(String title, String artist) {
    final cleanT = _normalize(cleanTitle(title));
    final cleanA = _normalize(cleanArtist(artist));
    return '${cleanT}_$cleanA';
  }

  static Future<void> saveToCache(
      String title, String artist, LyricsResult result) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/${_cacheKey(title, artist)}.json');
      await file.writeAsString(jsonEncode(result.toJson()));
    } catch (e) {
      debugPrint('Lyrics cache save error: $e');
    }
  }

  static Future<LyricsResult?> loadFromCache(
      String title, String artist) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/${_cacheKey(title, artist)}.json');
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        return LyricsResult.fromJson(json);
      }
    } catch (e) {
      debugPrint('Lyrics cache load error: $e');
    }
    return null;
  }

  static Future<bool> hasCachedLyrics(String title, String artist) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/${_cacheKey(title, artist)}.json');
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  static Future<void> saveLrcFile(String trackId, String lrcContent) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/$trackId.lrc');
      await file.writeAsString(lrcContent);
    } catch (e) {
      debugPrint('LRC file save error: $e');
    }
  }

  static Future<String?> loadLrcFile(String trackId) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/$trackId.lrc');
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      debugPrint('LRC file load error: $e');
    }
    return null;
  }

  static List<LyricLine> _parseLRC(String lrc) {
    final lines = <LyricLine>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');

    for (final line in lrc.split('\n')) {
      final match = regex.firstMatch(line.trim());
      if (match != null) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final msStr = match.group(3)!;
        final ms = msStr.length == 2 ? int.parse(msStr) * 10 : int.parse(msStr);
        final text = match.group(4)!.trim();
        if (text.isNotEmpty) {
          lines.add(LyricLine(
            time: Duration(minutes: min, seconds: sec, milliseconds: ms),
            text: text,
          ));
        }
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  static LyricsResult? _pickBestFromResults(
    List results,
    Duration duration,
    String expectedTitle,
    String expectedArtist,
  ) {
    String? bestSynced;
    String? bestPlain;
    double? bestDur;
    double bestScore = -1;

    final cleanExpected = cleanTitle(expectedTitle);
    final titleLower = cleanExpected.toLowerCase().trim();

    for (final item in results) {
      if (item is! Map) continue;

      // 1. Explicit instrumental track -> no lyrics
      if (item['instrumental'] == true) continue;

      final trackArtist = (item['artistName'] as String?) ?? '';

      // 2. Strict artist verification:
      // If the candidate artist has no match with expected artist, DISQUALIFY!
      // This stops Taylor Swift / Justin Bieber lyrics from showing on Suly Pheng / Khmer songs!
      if (!_artistMatches(expectedArtist, trackArtist)) {
        continue;
      }

      final synced = item['syncedLyrics'] as String?;
      final plain = item['plainLyrics'] as String?;
      final officialDur = (item['duration'] as num?)?.toDouble();
      final trackName = cleanTitle((item['trackName'] as String?) ?? '');

      if ((synced == null || synced.isEmpty) &&
          (plain == null || plain.isEmpty)) {
        continue;
      }

      double score = 0;

      // Artist match strength
      if (_normalize(trackArtist) == _normalize(expectedArtist)) {
        score += 50; // exact artist match
      } else {
        score += 25; // partial / collaborator match
      }

      // Title similarity (0-100)
      final trackLower = trackName.toLowerCase().trim();
      if (trackLower == titleLower) {
        score += 100; // exact match
      } else if (trackLower.contains(titleLower) ||
          titleLower.contains(trackLower)) {
        score += 80;
      } else {
        // Word overlap — keep all characters including Khmer
        final titleWords = titleLower
            .split(RegExp(r'\s+'))
            .where((w) => w.length > 1)
            .toSet();
        final trackWords = trackLower
            .split(RegExp(r'\s+'))
            .where((w) => w.length > 1)
            .toSet();
        int matches = titleWords.intersection(trackWords).length;
        int total = titleWords.union(trackWords).length;
        if (total > 0 && matches > 0) {
          score += (matches / total) * 60;
        } else {
          continue; // No title overlap at all
        }
      }

      // Duration match (0-50) (if known)
      if (officialDur != null && duration > Duration.zero) {
        final diff = (officialDur - duration.inSeconds).abs();
        if (diff <= 3) {
          score += 50;
        } else if (diff <= 8) {
          score += 35;
        } else if (diff <= 15) {
          score += 15;
        } else if (diff > 25) {
          continue; // More than 25s difference is a completely different version/remix
        } else {
          score -= 40;
        }
      } else if (duration == Duration.zero) {
        score += 20;
      }

      // Prefer synced lyrics
      if (synced != null && synced.isNotEmpty) {
        score += 30;
      }

      if (score > bestScore) {
        bestScore = score;
        bestSynced = synced;
        bestPlain = plain;
        bestDur = officialDur;
      }
    }

    // Require solid confidence (at least title + artist match)
    if (bestScore < 70) {
      return null;
    }

    if (bestSynced != null && bestSynced.isNotEmpty) {
      return LyricsResult(
        syncedLyrics: _parseLRC(bestSynced),
        plainLyrics: bestPlain,
        officialDuration: bestDur,
      );
    }

    if (bestPlain != null && bestPlain.isNotEmpty) {
      return LyricsResult(plainLyrics: bestPlain, officialDuration: bestDur);
    }

    return null;
  }

  static Future<LyricsResult?> fetchLyrics({
    required String artist,
    required String title,
    required Duration duration,
    bool saveCache = true,
  }) async {
    try {
      final cleanT = cleanTitle(title);
      final cleanA = cleanArtist(artist);

      // 0. Check cache first
      final cached = await loadFromCache(cleanT, cleanA);
      if (cached != null) return cached;
      final cachedRaw = await loadFromCache(title, artist);
      if (cachedRaw != null) return cachedRaw;

      // 1. Search with primary cleaned artist + cleaned title
      final searchUrl1 = Uri.parse(
        'https://lrclib.net/api/search?artist_name=${Uri.encodeComponent(cleanA)}'
        '&track_name=${Uri.encodeComponent(cleanT)}',
      );
      final searchRes1 = await http.get(searchUrl1, headers: _headers);
      if (searchRes1.statusCode == 200) {
        final results = jsonDecode(searchRes1.body) as List;
        final best = _pickBestFromResults(results, duration, cleanT, artist);
        if (best != null) {
          if (saveCache) await saveToCache(title, artist, best);
          return best;
        }
      }

      // 2. If primary artist differed from full artist, try full artist name
      if (cleanA.toLowerCase() != artist.toLowerCase().trim()) {
        final searchUrl2 = Uri.parse(
          'https://lrclib.net/api/search?artist_name=${Uri.encodeComponent(artist.trim())}'
          '&track_name=${Uri.encodeComponent(cleanT)}',
        );
        final searchRes2 = await http.get(searchUrl2, headers: _headers);
        if (searchRes2.statusCode == 200) {
          final results = jsonDecode(searchRes2.body) as List;
          final best = _pickBestFromResults(results, duration, cleanT, artist);
          if (best != null) {
            if (saveCache) await saveToCache(title, artist, best);
            return best;
          }
        }
      }

      // 3. Search by track name only, BUT strictly enforce artist matching in _pickBestFromResults!
      // This allows finding songs where LRCLIB has a slightly different artist spelling,
      // but strictly rejects songs by completely different artists (e.g. Taylor Swift vs Suly Pheng).
      final titleSearchUrl = Uri.parse(
        'https://lrclib.net/api/search?track_name=${Uri.encodeComponent(cleanT)}',
      );
      final titleSearchRes = await http.get(titleSearchUrl, headers: _headers);
      if (titleSearchRes.statusCode == 200) {
        final results = jsonDecode(titleSearchRes.body) as List;
        final best = _pickBestFromResults(results, duration, cleanT, artist);
        if (best != null) {
          if (saveCache) await saveToCache(title, artist, best);
          return best;
        }
      }

      // 4. Exact match with duration as last resort (with strict artist check)
      if (duration > Duration.zero) {
        final exactUrl = Uri.parse(
          'https://lrclib.net/api/get?artist_name=${Uri.encodeComponent(cleanA)}'
          '&track_name=${Uri.encodeComponent(cleanT)}'
          '&duration=${duration.inSeconds}',
        );
        final exactRes = await http.get(exactUrl, headers: _headers);
        if (exactRes.statusCode == 200) {
          final json = jsonDecode(exactRes.body);
          if (json is Map && json['instrumental'] != true) {
            final trackArtist = (json['artistName'] as String?) ?? '';
            final trackName = (json['trackName'] as String?) ?? '';

            if (_artistMatches(artist, trackArtist)) {
              final returnedLower = cleanTitle(trackName).toLowerCase().trim();
              final expectedLower = cleanT.toLowerCase().trim();

              if (returnedLower == expectedLower ||
                  returnedLower.contains(expectedLower) ||
                  expectedLower.contains(returnedLower)) {
                final synced = json['syncedLyrics'] as String?;
                final plain = json['plainLyrics'] as String?;
                final officialDur = (json['duration'] as num?)?.toDouble();

                if (synced != null && synced.isNotEmpty) {
                  final result = LyricsResult(
                    syncedLyrics: _parseLRC(synced),
                    plainLyrics: plain,
                    officialDuration: officialDur,
                  );
                  if (saveCache) await saveToCache(title, artist, result);
                  return result;
                }
                if (plain != null && plain.isNotEmpty) {
                  final result = LyricsResult(
                      plainLyrics: plain, officialDuration: officialDur);
                  if (saveCache) await saveToCache(title, artist, result);
                  return result;
                }
              }
            }
          }
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  static int currentLineIndex(List<LyricLine> lyrics, Duration position) {
    for (int i = lyrics.length - 1; i >= 0; i--) {
      if (position >= lyrics[i].time) return i;
    }
    return 0;
  }

  static List<LyricLine> parseLrcString(String lrc) {
    return _parseLRC(lrc);
  }
}
