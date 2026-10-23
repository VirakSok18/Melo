import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/search_service.dart';
import '../services/lyrics_service.dart';
import '../services/recommendation_service.dart';
import '../services/listening_history_service.dart';
import '../services/download_service.dart';
import '../services/auto_cache_service.dart';
import '../services/deezer_service.dart';
import '../services/deezer_proxy.dart';
import '../services/jiosaavn_service.dart';
import '../services/client_stream_service.dart';
import '../services/youtube_service.dart';
import '../services/background_prefetch_service.dart';
import '../services/cookie_service.dart';
import '../services/ad_service.dart';
import '../utils/track_filter.dart';

enum MeloLoopMode {
  off, // Plays to end of playlist, then Smart Queue continues
  all, // Loops playlist back to song #1
  one, // Repeats the current single song
}

class PlaybackContext {
  final String type; // 'playlist', 'album', 'liked', 'downloaded', 'generated'
  final String id;
  final String title;
  final String? coverImage;
  final String? artistName;
  final String? artistId;
  final Map<String, dynamic>? extra;

  const PlaybackContext({
    required this.type,
    this.id = '',
    this.title = '',
    this.coverImage,
    this.artistName,
    this.artistId,
    this.extra,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'id': id,
      'title': title,
      if (coverImage != null) 'coverImage': coverImage,
      if (artistName != null) 'artistName': artistName,
      if (artistId != null) 'artistId': artistId,
      if (extra != null) 'extra': extra,
    };
  }

  factory PlaybackContext.fromJson(Map<String, dynamic> json) {
    return PlaybackContext(
      type: json['type'] ?? '',
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      coverImage: json['coverImage']?.toString(),
      artistName: json['artistName']?.toString(),
      artistId: json['artistId']?.toString(),
      extra: json['extra'] != null
          ? Map<String, dynamic>.from(json['extra'] as Map)
          : null,
    );
  }
}

class PlaybackService extends ChangeNotifier {
  static final PlaybackService _instance = PlaybackService._internal();
  factory PlaybackService() => _instance;
  PlaybackService._internal() {
    _restoreVolume();
    _restoreSpeed();
    _audioPlayer.playingStream.listen((playing) {
      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
      }
    });

    _audioPlayer.positionStream.listen((pos) {
      if (_isLoading) return;
      _positionController.add(pos);
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_isLoading) return;
        if (_lastCompletedGeneration == _playGeneration) return;
        _lastCompletedGeneration = _playGeneration;
        _logCompletion();
        // Song played to completion — ensure it's auto-cached (covers songs
        // shorter than the 45s timer, or a timer that never fired).
        final completedTrack = _currentTrack;
        if (completedTrack != null) {
          AutoCacheService.cacheTrack(completedTrack);
        }
        if (_loopMode == MeloLoopMode.one) {
          _logReplay();
          _audioPlayer.seek(Duration.zero);
          _audioPlayer.play();
          _isPlaying = true;
          _trackStartTime = DateTime.now();
          _hasBeenReplayed = true;
          notifyListeners();
        } else {
          _handleCompletionAndAdvance();
        }
      } else if (state.processingState == ProcessingState.idle &&
          !_isLoading &&
          _isPlaying) {
        // just_audio lands in idle on a source/network error mid-stream
        // (e.g. a YouTube URL that 403s halfway through). Keep the player
        // alive and advance to the next track instead of silently dying.
        debugPrint('Unexpected idle: stream error detected, skipping track');
        _handleSourceError();
      }
    });
  }

  final AudioPlayer _audioPlayer = AudioPlayer();

  // This is deliberately the player's gain, not the device/media volume. It
  // lets Melo offer a consistent in-app volume control without changing the
  // volume of notifications, calls, or other apps.
  static const String _prefPlaybackVolume = 'melo_playback_volume';
  static const String _prefPlaybackSpeed = 'melo_playback_speed';
  double _volume = 1.0;
  double _speed = 1.0;

  SearchResult? _currentTrack;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isVisible = false;
  MeloLoopMode _loopMode = MeloLoopMode.off;
  bool _isShuffle = false;
  List<LyricLine>? _currentLyrics;
  bool _lyricsLoading = false;
  String? _lyricsKey;
  List<SearchResult> _queue = [];
  int _queueIndex = -1;
  List<SearchResult>? _unshuffledQueue;
  List<SearchResult> _smartQueue = [];
  bool _smartQueueLoading = false;
  bool _pendingNext = false;
  bool _isQueueMode = false;
  int _playGeneration = 0;
  int _lastCompletedGeneration = -1;
  int _consecutiveSourceErrors = 0;
  Timer? _debouncePlayTimer;
  final Set<String> _playedTrackKeys = <String>{};

  DateTime? _trackStartTime;
  bool _hasBeenReplayed = false;

  String? _errorMessage;
  int _errorSeq = 0;
  PlaybackContext? _context;

  /// Callback when user manually triggers playback actions (pause, skip, seek, play new track)
  void Function()? onManualPlaybackAction;

  /// Optional callback to query the live millisecond position of the host for Listen Along sync
  Duration? Function()? onGetSyncTargetPosition;

  SearchResult? get currentTrack => _currentTrack;
  PlaybackContext? get currentContext => _context;
  String? get currentPlaylistId => (_currentTrack != null &&
          (_context?.type == 'playlist' || _context?.type == 'generated'))
      ? _context?.id
      : null;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get isVisible => _isVisible;
  List<LyricLine>? get currentLyrics => _currentLyrics;
  bool get lyricsLoading => _lyricsLoading;
  AudioPlayer get audioPlayer => _audioPlayer;
  List<SearchResult> get queue => _queue;
  int get queueIndex => _queueIndex;
  bool get hasNext =>
      _queueIndex < _queue.length - 1 ||
      _loopMode == MeloLoopMode.all ||
      _smartQueue.isNotEmpty ||
      (_loopMode == MeloLoopMode.off && _currentTrack != null) ||
      (_isQueueMode && _queue.isNotEmpty);
  bool get hasPrevious => _queueIndex > 0;
  List<SearchResult> get smartQueue => List.unmodifiable(_smartQueue);
  MeloLoopMode get loopMode => _loopMode;
  bool get isRepeat => _loopMode != MeloLoopMode.off;
  bool get isShuffle => _isShuffle;
  double get volume => _volume;
  double get speed => _speed;
  String? get errorMessage => _errorMessage;
  int get errorSeq => _errorSeq;

  void _setError(String message) {
    _errorSeq++;
    _errorMessage = message;
  }

  Duration? _pendingPosition;
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();

  Duration get position {
    if (_isLoading && _pendingPosition != null) {
      return _pendingPosition!;
    }
    return _audioPlayer.position;
  }

  Duration get duration {
    if (_isLoading) {
      final sec =
          _currentTrack != null ? _parseDuration(_currentTrack!.duration) : 0;
      if (sec > 0) return Duration(seconds: sec);
      return Duration.zero;
    }
    return _audioPlayer.duration ?? Duration.zero;
  }

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<PlayerState> get playerStateStream => _audioPlayer.playerStateStream;

  /// Sets Melo's audio gain only (0 = muted, 1 = full player volume).
  Future<void> setVolume(double value) async {
    final nextVolume = value.clamp(0.0, 1.0);
    if ((nextVolume - _volume).abs() < 0.001) return;
    _volume = nextVolume;
    await _audioPlayer.setVolume(_volume);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefPlaybackVolume, _volume);
    } catch (_) {
      // Volume still works for this session if preferences are unavailable.
    }
  }

  Future<void> _restoreVolume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _volume = (prefs.getDouble(_prefPlaybackVolume) ?? 1.0).clamp(0.0, 1.0);
      await _audioPlayer.setVolume(_volume);
      notifyListeners();
    } catch (_) {}
  }

  /// Changes the playback rate without changing pitch where the platform
  /// player supports it. The selected rate is retained for future tracks.
  Future<void> setSpeed(double value) async {
    const allowed = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    final nextSpeed = allowed.reduce((best, candidate) =>
        (candidate - value).abs() < (best - value).abs() ? candidate : best);
    if ((nextSpeed - _speed).abs() < 0.001) return;
    _speed = nextSpeed;
    await _audioPlayer.setSpeed(_speed);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefPlaybackSpeed, _speed);
    } catch (_) {}
  }

  Future<void> _restoreSpeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_prefPlaybackSpeed) ?? 1.0;
      await setSpeed(saved);
    } catch (_) {}
  }

  int _parseDuration(String duration) {
    if (duration.contains(':')) {
      final parts = duration.split(':');
      if (parts.length == 2) {
        return (int.tryParse(parts[0]) ?? 0) * 60 +
            (int.tryParse(parts[1]) ?? 0);
      } else if (parts.length == 3) {
        return (int.tryParse(parts[0]) ?? 0) * 3600 +
            (int.tryParse(parts[1]) ?? 0) * 60 +
            (int.tryParse(parts[2]) ?? 0);
      }
    }
    return int.tryParse(duration) ?? 0;
  }

  MediaItem _buildMediaItem(SearchResult track) {
    Uri? artUri;
    if (track.image.isNotEmpty) {
      artUri = Uri.tryParse(track.image);
    }
    final durSec = _parseDuration(track.duration);

    return MediaItem(
      id: track.id.isNotEmpty ? track.id : track.title,
      title: track.title,
      artist: track.artist.isNotEmpty ? track.artist : 'Unknown Artist',
      album: 'Melo',
      artUri: artUri,
      duration: durSec > 0 ? Duration(seconds: durSec) : null,
    );
  }

  Future<void> _setStreamUrl(String url, SearchResult track,
      {Duration? initialPosition}) {
    final mediaItem = _buildMediaItem(track);
    return _audioPlayer.setAudioSource(
      AudioSource.uri(
        Uri.parse(url),
        tag: mediaItem,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      ),
      initialPosition: initialPosition,
    );
  }

  static const String _prefLastTrack = 'melo_last_track';
  static const String _prefLastQueue = 'melo_last_queue';
  static const String _prefLastQueueIndex = 'melo_last_queue_index';
  static const String _prefLastContext = 'melo_last_context';

  Future<void> _savePlaybackState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_currentTrack != null) {
        await prefs.setString(
            _prefLastTrack, jsonEncode(_currentTrack!.toJson()));
      } else {
        await prefs.remove(_prefLastTrack);
      }
      if (_queue.isNotEmpty) {
        final queueJson = _queue.map((t) => t.toJson()).toList();
        await prefs.setString(_prefLastQueue, jsonEncode(queueJson));
        await prefs.setInt(_prefLastQueueIndex, _queueIndex);
      } else {
        await prefs.remove(_prefLastQueue);
        await prefs.remove(_prefLastQueueIndex);
      }
      if (_context != null) {
        await prefs.setString(_prefLastContext, jsonEncode(_context!.toJson()));
      } else {
        await prefs.remove(_prefLastContext);
      }
    } catch (e) {
      debugPrint('[PlaybackService] Error saving playback state: $e');
    }
  }

  Future<void> restoreLastPlaybackState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trackStr = prefs.getString(_prefLastTrack);
      if (trackStr != null && trackStr.isNotEmpty) {
        final trackMap = jsonDecode(trackStr) as Map<String, dynamic>;
        _currentTrack = SearchResult.fromJson(trackMap);
        _isVisible = true;
        _isPlaying = false;
        _isLoading = false;

        final queueStr = prefs.getString(_prefLastQueue);
        if (queueStr != null && queueStr.isNotEmpty) {
          final queueList = jsonDecode(queueStr) as List<dynamic>;
          _queue = queueList
              .map((item) =>
                  SearchResult.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList();
          _queueIndex = prefs.getInt(_prefLastQueueIndex) ?? 0;
          _isQueueMode = _queue.length > 1;
        }

        final contextStr = prefs.getString(_prefLastContext);
        if (contextStr != null && contextStr.isNotEmpty) {
          final ctxMap = jsonDecode(contextStr) as Map<String, dynamic>;
          _context = PlaybackContext.fromJson(ctxMap);
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint('[PlaybackService] Error restoring playback state: $e');
    }
  }

  void setQueue(List<SearchResult> tracks, int startIndex,
      {PlaybackContext? context, bool fromSync = false}) {
    if (!fromSync) {
      onManualPlaybackAction?.call();
    }
    _queue = List.from(tracks);
    _queueIndex = startIndex;
    _unshuffledQueue = null;
    _isQueueMode = tracks.length > 1;
    _context = context;
    if (tracks.length > 1) {
      _loopMode = MeloLoopMode.all;
    }
    _smartQueue.clear();
    _savePlaybackState();
    notifyListeners();
  }

  void setContext(PlaybackContext? ctx) {
    _context = ctx;
    _savePlaybackState();
    notifyListeners();
  }

  void clearQueue() {
    _queue = [];
    _queueIndex = -1;
    _context = null;
    _savePlaybackState();
    notifyListeners();
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    if (_isShuffle) {
      _unshuffledQueue = List<SearchResult>.from(_queue);
      shuffleQueue();
    } else if (_unshuffledQueue != null) {
      final currentTrack = _queue[_queueIndex];
      _queue = _unshuffledQueue!;
      _queueIndex =
          _unshuffledQueue!.indexWhere((t) => t.id == currentTrack.id);
      if (_queueIndex == -1) _queueIndex = 0;
      _unshuffledQueue = null;
    }
    notifyListeners();
  }

  void shuffleQueue() {
    if (_queue.isEmpty) return;
    final current = _queue[_queueIndex];
    final remaining = List<SearchResult>.from(_queue)..removeAt(_queueIndex);
    remaining.shuffle();
    _queue = [current, ...remaining];
    _queueIndex = 0;
    notifyListeners();
  }

  Future<void> _finalizeTrackPlayback(
    SearchResult track,
    int generation, {
    Duration? initialPosition,
    bool armAutoCache = true,
    bool fromSync = false,
  }) async {
    if (generation != _playGeneration) return;
    Duration? targetPos = _pendingPosition ?? initialPosition;
    if (fromSync && onGetSyncTargetPosition != null) {
      final liveHostPos = onGetSyncTargetPosition!();
      if (liveHostPos != null) {
        targetPos = liveHostPos;
        debugPrint(
            '[Playback] Synchronized post-buffer live snap to host: ${liveHostPos.inMilliseconds}ms');
      }
    }
    if (targetPos != null && targetPos > Duration.zero) {
      try {
        await _audioPlayer.seek(targetPos);
      } catch (_) {}
    }
    _pendingPosition = null;
    _isLoading = false;
    _audioPlayer.play();
    _isPlaying = true;
    _trackStartTime = DateTime.now();
    _hasBeenReplayed = false;
    _consecutiveSourceErrors = 0;
    _positionController.add(_audioPlayer.position);
    notifyListeners();
    _fetchLyricsForTrack(track);
    _prefetchNextInQueue();
    if (armAutoCache) {
      _armAutoCacheTimer(track, generation);
    }
    if (_smartQueue.isEmpty) {
      _fetchSmartQueue();
    }
  }

  Future<void> playTrack(
    SearchResult track, {
    bool fromQueue = false,
    Duration? initialPosition,
    PlaybackContext? context,
    bool fromSync = false,
  }) async {
    if (TrackFilter.isBlocked(artist: track.artist, title: track.title, id: track.id)) {
      debugPrint('[Playback] Track is blocked/unplayable: "${track.title}" by "${track.artist}" -> skipping');
      if (_queue.length > 1 && _queueIndex < _queue.length - 1) {
        playNext();
      } else {
        _isLoading = false;
        notifyListeners();
      }
      return;
    }

    if (!fromSync) {
      onManualPlaybackAction?.call();
    }
    if (context != null) {
      _context = context;
    } else if (!fromQueue) {
      _context = null;
    }

    // Log skip for previous track if it existed
    if (_currentTrack != null && _trackStartTime != null && !_hasBeenReplayed) {
      final elapsed = DateTime.now().difference(_trackStartTime!).inSeconds;
      final totalDuration = _parseDuration(_currentTrack!.duration);
      final playedPercent = totalDuration > 0 ? elapsed / totalDuration : 0.0;
      if (playedPercent < 0.3 && elapsed > 5) {
        _logSkip(_currentTrack!, elapsed);
      }
    }

    if (!fromQueue) {
      _isQueueMode = false;
      _loopMode = MeloLoopMode.off;
      _queue = [track];
      _queueIndex = 0;
      _unshuffledQueue = null;
      _smartQueue.clear();
      _savePlaybackState();
    }

    // Cancel any in-flight fetch for the previous track
    _debouncePlayTimer?.cancel();
    final generation = ++_playGeneration;
    _isLoading = true;
    _isVisible = true;
    _isPlaying = false;
    _pendingNext = false;
    _errorMessage = null;
    _currentTrack = track;
    _pendingPosition = initialPosition ?? Duration.zero;
    _positionController.add(_pendingPosition!);
    ListeningHistoryService.logEvent(
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      image: track.image,
      genre: track.genre,
      artistId: track.artistId,
      artistImage: track.artistImage,
      source: 'player',
    );
    final trackKey =
        '${track.title.toLowerCase()}|${track.artist.toLowerCase()}';
    _playedTrackKeys.add(trackKey);
    if (_playedTrackKeys.length > 100) {
      _playedTrackKeys.remove(_playedTrackKeys.first);
    }
    _currentLyrics = null;
    _lyricsLoading = true;
    _lyricsKey = null;
    _savePlaybackState();
    notifyListeners();

    if (!fromQueue) {
      _fetchSmartQueue();
    }

    // Pause previous stream only if actively playing to cancel loading without disrupting auto-next
    if (_audioPlayer.playing) {
      try {
        await _audioPlayer.pause();
      } catch (_) {}
    }

    try {
      // Check for local downloaded file first (offline playback)
      String? localPath;
      if (track.filePath != null) {
        final localFile = File(track.filePath!);
        if (await localFile.exists()) {
          localPath = track.filePath;
        }
      } else {
        final downloadedPath = await DownloadService.getLocalPath(track.id);
        if (downloadedPath != null) {
          localPath = downloadedPath;
        }
      }

      // Invisible auto-cache of previously played songs — instant, offline replay.
      localPath ??= AutoCacheService.getLocalPath(track.id);

      // No local copy — we'll try Deezer first (no backend needed), then
      // fall back to backend. Only show "offline" error if BOTH Deezer and
      // backend fail.

      final startPos = _pendingPosition ?? initialPosition;

      if (localPath != null) {
        // Play from local file (offline)
        if (generation != _playGeneration) return;
        // Refresh LRU recency for auto-cached songs (explicit downloads and
        // filePath tracks aren't in the auto-cache index, so no-op for those).
        AutoCacheService.markPlayed(track.id);
        final mediaItem = _buildMediaItem(track);
        try {
          await _audioPlayer
              .setAudioSource(
                AudioSource.file(localPath, tag: mediaItem),
                initialPosition: startPos,
              )
              .timeout(const Duration(seconds: 10));
          await _finalizeTrackPlayback(track, generation,
              initialPosition: startPos, armAutoCache: false, fromSync: fromSync);
          return;
        } catch (localErr) {
          debugPrint(
              '[Playback] Cached file error for "${track.title}": $localErr. Evicting and falling back to streaming.');
          AutoCacheService.evict(track.id);
          // Fall through to live streaming!
        }
      }

      // 100% FRONTEND PLAYBACK: Stream directly from Deezer via on-device proxy
      try {
        final proxy = DeezerProxy.instance;
        await proxy.ensureRunning();

        if (generation == _playGeneration) {
          final proxyUrl = proxy.streamUrl(track.id);
          final proxyUrlWithTitle =
              '$proxyUrl?title=${Uri.encodeComponent(track.title)}&artist=${Uri.encodeComponent(track.artist)}';
          debugPrint('[Playback] Playing Deezer via proxy: $proxyUrlWithTitle');
          await _setStreamUrl(proxyUrlWithTitle, track,
                  initialPosition: startPos)
              .timeout(const Duration(seconds: 15));
          await _finalizeTrackPlayback(track, generation,
              initialPosition: startPos, armAutoCache: true, fromSync: fromSync);
          return;
        }
      } catch (proxyError) {
        debugPrint('[Playback] Deezer proxy direct stream error: $proxyError');
      }

      // SECONDARY FRONTEND FALLBACK 1: JioSaavn direct CDN stream (320kbps CD Quality, zero IP locks, global)
      if (generation != _playGeneration) return;
      try {
        debugPrint(
            '[Playback] Trying JioSaavn CDN for "${track.title}" by "${track.artist}"');
        final jioStreamUrl =
            await JioSaavnService.getStreamUrl(track.title, track.artist);
        if (jioStreamUrl != null &&
            jioStreamUrl.isNotEmpty &&
            generation == _playGeneration) {
          await _setStreamUrl(jioStreamUrl, track, initialPosition: startPos)
              .timeout(const Duration(seconds: 10));
          await _finalizeTrackPlayback(track, generation,
              initialPosition: startPos, armAutoCache: true, fromSync: fromSync);
          return;
        }
      } catch (jioError) {
        debugPrint('[Playback] JioSaavn fallback error: $jioError');
      }

      // SECONDARY FRONTEND FALLBACK 2: On-device temp download (reliable, zero 403 errors)
      if (generation != _playGeneration) return;
      try {
        debugPrint(
            '[Playback] Trying on-device temp download for "${track.title}" by "${track.artist}"');
        final tempFilePath = await ClientStreamService.downloadAudioToTempFile(
            track.title, track.artist);
        if (tempFilePath != null && generation == _playGeneration) {
          final mediaItem = _buildMediaItem(track);
          await _audioPlayer
              .setAudioSource(
                AudioSource.file(tempFilePath, tag: mediaItem),
                initialPosition: startPos,
              )
              .timeout(const Duration(seconds: 10));
          await _finalizeTrackPlayback(track, generation,
              initialPosition: startPos, armAutoCache: true, fromSync: fromSync);
          return;
        }
      } catch (tempError) {
        debugPrint('[Playback] Client temp file download error: $tempError');
      }

      // SECONDARY FRONTEND FALLBACK 4: Resolve and decrypt directly via DeezerService to temp file
      if (generation != _playGeneration) return;
      try {
        debugPrint('[Playback] Falling back to direct DeezerService resolve');
        final resolved = await DeezerService.resolveTrack(
          title: track.title,
          artist: track.artist,
          trackId: track.id,
        );

        if (resolved != null && resolved.audioBytes.isNotEmpty) {
          final tempPath = await DeezerService.saveToTempFile(
              resolved.audioBytes,
              resolved.trackId.isNotEmpty ? resolved.trackId : track.id);
          if (tempPath != null && generation == _playGeneration) {
            final mediaItem = _buildMediaItem(track);
            await _audioPlayer
                .setAudioSource(
                  AudioSource.file(tempPath, tag: mediaItem),
                  initialPosition: startPos,
                )
                .timeout(const Duration(seconds: 10));
            await _finalizeTrackPlayback(track, generation,
                initialPosition: startPos, armAutoCache: true, fromSync: fromSync);
            return;
          }
        }
      } catch (directError) {
        debugPrint('[Playback] Direct Deezer resolve failed: $directError');
      }

      // BACKEND FALLBACK 5: Backend YouTube / stream resolver
      if (generation != _playGeneration) return;
      try {
        debugPrint('[Playback] Falling back to backend YouTube stream');
        final streamUrl = await YouTubeService.resolveStreamUrl(
          track.title,
          track.artist,
          durationSeconds: _parseDuration(track.duration),
        );
        if (streamUrl != null &&
            streamUrl.isNotEmpty &&
            generation == _playGeneration) {
          await _setStreamUrl(streamUrl, track, initialPosition: startPos)
              .timeout(const Duration(seconds: 15));
          await _finalizeTrackPlayback(track, generation,
              initialPosition: startPos, armAutoCache: true, fromSync: fromSync);
          return;
        }
      } catch (backendError) {
        debugPrint('[Playback] Backend YouTube stream error: $backendError');
      }

      await _handleSourceError();
    } catch (e) {
      if (generation != _playGeneration) return;
      final eStr = e.toString().toLowerCase();
      if (eStr.contains('abort') ||
          eStr.contains('interrupted') ||
          eStr.contains('cancelled')) {
        return; // Interrupted by a newer skip, ignore silently
      }
      debugPrint('[Playback] Playback error: $e');
      await _handleSourceError();
    }
  }

  /// Called when a track fails to play (URL fetch fail, stream 403, etc).
  /// Keeps the player UI open and auto-skips to the next queued song like a
  /// normal music app. Only closes the mini player when nothing is left to play.
  Future<void> _handleSourceError() async {
    _isPlaying = false;
    _isLoading = false;
    _pendingPosition = null;
    _consecutiveSourceErrors++;
    notifyListeners();

    final hasNext = (_queue.isNotEmpty && _queueIndex < _queue.length - 1) ||
        _smartQueue.isNotEmpty ||
        (_isQueueMode && _queue.isNotEmpty);

    if (hasNext && _consecutiveSourceErrors <= 3) {
      await playNext();
      return;
    }

    _consecutiveSourceErrors = 0;
    _isVisible = false;
    _setError("Couldn't play this song.");
    notifyListeners();
  }

  void _fetchLyricsForTrack(SearchResult track) {
    final key = '${track.title}|${track.artist}';
    if (key == _lyricsKey && _currentLyrics != null) return;
    _lyricsKey = key;
    _currentLyrics = null;
    _lyricsLoading = true;
    final generation = _playGeneration;
    notifyListeners();

    final parts = track.duration.split(':');
    final trackDuration = parts.length == 2
        ? Duration(minutes: int.parse(parts[0]), seconds: int.parse(parts[1]))
        : Duration(seconds: int.tryParse(track.duration) ?? 0);

    // Try to load from cache or LRC file first (instant, works offline)
    _loadCachedLyrics(track, trackDuration, generation);
  }

  void _loadCachedLyrics(
      SearchResult track, Duration trackDuration, int generation) async {
    // 1. Check lyrics cache (by title|artist)
    final cached = await LyricsService.loadFromCache(track.title, track.artist);
    if (generation != _playGeneration) return;
    if (cached != null) {
      _applyLyrics(cached, trackDuration, generation);
      return;
    }

    // 2. Check LRC file (by trackId — for downloaded songs)
    final lrcContent = await LyricsService.loadLrcFile(track.id);
    if (generation != _playGeneration) return;
    if (lrcContent != null && lrcContent.isNotEmpty) {
      final lines = LyricsService.parseLrcString(lrcContent);
      if (lines.isNotEmpty) {
        _currentLyrics = lines;
        _lyricsLoading = false;
        notifyListeners();
        return;
      }
    }

    // 3. Fetch from network
    _fetchFromNetwork(track, trackDuration, generation);
  }

  void _applyLyrics(
      LyricsResult result, Duration trackDuration, int generation) {
    if (generation != _playGeneration) return;

    final ytDuration = _audioPlayer.duration ?? Duration.zero;
    final durationDiffSec = (ytDuration - trackDuration).inSeconds;

    if (result.syncedLyrics != null && result.syncedLyrics!.isNotEmpty) {
      final lyrics = result.syncedLyrics!;
      final offset = Duration(seconds: durationDiffSec);

      if (offset.inSeconds.abs() > 0 && offset.inSeconds.abs() <= 5) {
        _currentLyrics = lyrics
            .map((l) => LyricLine(
                  time: l.time + offset,
                  text: l.text,
                ))
            .toList();
      } else {
        _currentLyrics = lyrics;
      }
    } else if (result.plainLyrics != null && result.plainLyrics!.isNotEmpty) {
      _currentLyrics = [
        LyricLine(time: Duration.zero, text: result.plainLyrics!)
      ];
    } else {
      _currentLyrics = null;
    }

    _lyricsLoading = false;
    notifyListeners();
  }

  void _fetchFromNetwork(
      SearchResult track, Duration trackDuration, int generation) {
    LyricsService.fetchLyrics(
      artist: track.artist,
      title: track.title,
      duration: trackDuration,
    ).then((result) {
      if (generation != _playGeneration) return;
      if (result == null) {
        _currentLyrics = null;
        _lyricsLoading = false;
        notifyListeners();
        return;
      }
      _applyLyrics(result, trackDuration, generation);
    });
  }

  void play({bool fromSync = false}) {
    if (!fromSync) {
      onManualPlaybackAction?.call();
    }
    _audioPlayer.play();
    _isPlaying = true;
    notifyListeners();
  }

  void pause({bool fromSync = false}) {
    if (!fromSync) {
      onManualPlaybackAction?.call();
    }
    _audioPlayer.pause();
    _isPlaying = false;
    notifyListeners();
  }

  void togglePlayPause() {
    if (_audioPlayer.playing) {
      pause();
    } else {
      if (_currentTrack != null && _audioPlayer.audioSource == null) {
        playTrack(_currentTrack!, fromQueue: true);
      } else {
        play();
      }
    }
  }

  void toggleRepeat() {
    switch (_loopMode) {
      case MeloLoopMode.off:
        _loopMode = MeloLoopMode.all;
        CookieService.show(
          message: 'Repeat Playlist',
          icon: Icons.repeat_rounded,
          iconColor: const Color(0xFF514AED),
        );
        break;
      case MeloLoopMode.all:
        _loopMode = MeloLoopMode.one;
        CookieService.show(
          message: 'Repeat Current Song',
          icon: Icons.repeat_one_rounded,
          iconColor: const Color(0xFF514AED),
        );
        break;
      case MeloLoopMode.one:
        _loopMode = MeloLoopMode.off;
        CookieService.show(
          message: 'Repeat Off',
          icon: Icons.repeat_rounded,
          iconColor: Colors.white60,
        );
        if (_smartQueue.isEmpty) {
          _fetchSmartQueue();
        }
        break;
    }
    notifyListeners();
  }

  Future<void> seek(Duration position, {bool fromSync = false}) async {
    if (!fromSync) {
      onManualPlaybackAction?.call();
    }
    _pendingPosition = position;
    _positionController.add(position);
    notifyListeners();
    try {
      await _audioPlayer.seek(position);
    } catch (_) {}
    if (!_isLoading) {
      _pendingPosition = null;
    }
  }

  Set<String> _collectExcludeKeys() {
    final keys = <String>{..._playedTrackKeys};
    for (final t in _queue) {
      keys.add('${t.title.toLowerCase()}|${t.artist.toLowerCase()}');
    }
    for (final t in _smartQueue) {
      keys.add('${t.title.toLowerCase()}|${t.artist.toLowerCase()}');
    }
    return keys;
  }

  void _fetchSmartQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('pref_autoplay_similar') == false) return;
    } catch (_) {}
    if (_currentTrack == null || _smartQueueLoading) return;
    if (_smartQueue.length >= 10) return; // Keep a healthy buffer of 15+ tracks
    _smartQueueLoading = true;
    final artist = (_isQueueMode && _queue.isNotEmpty)
        ? _queue.last.artist
        : _currentTrack!.artist;
    if (artist.isEmpty) {
      _smartQueueLoading = false;
      return;
    }
    final excludeKeys = _collectExcludeKeys();
    final lessKeys = await ListeningHistoryService.getAllRecommendLessKeys();
    excludeKeys.addAll(lessKeys);

    RecommendationService.getSmartQueue(artist,
            limit: 16, excludeKeys: excludeKeys)
        .then((tracks) {
      for (final t in tracks) {
        final key = '${t.title.toLowerCase()}|${t.artist.toLowerCase()}';
        if (!_smartQueue.any((sq) =>
            '${sq.title.toLowerCase()}|${sq.artist.toLowerCase()}' == key)) {
          _smartQueue.add(t);
        }
      }
      _smartQueueLoading = false;
      notifyListeners();
      // Gently prefetch CDN stream URLs in the background (only next 2 tracks to save network)
      BackgroundPrefetchService.instance
          .enqueueTracks(tracks.take(2).toList(), tag: 'smart_queue');
      // If user clicked next while loading, play now
      if (_pendingNext) {
        _pendingNext = false;
        playNext();
      }
    }).catchError((e) {
      debugPrint('[Playback] Smart queue error: $e');
      _smartQueueLoading = false;
    });
  }

  Future<void> _fetchSmartQueueAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('pref_autoplay_similar') == false) return;
    } catch (_) {}
    if (_currentTrack == null) return;
    _smartQueueLoading = true;
    notifyListeners();
    final artist = (_isQueueMode && _queue.isNotEmpty)
        ? _queue.last.artist
        : _currentTrack!.artist;
    if (artist.isEmpty) {
      _smartQueueLoading = false;
      notifyListeners();
      return;
    }
    final excludeKeys = _collectExcludeKeys();
    final lessKeys = await ListeningHistoryService.getAllRecommendLessKeys();
    excludeKeys.addAll(lessKeys);

    try {
      final tracks = await RecommendationService.getSmartQueue(artist,
          limit: 16, excludeKeys: excludeKeys);
      for (final t in tracks) {
        final key = '${t.title.toLowerCase()}|${t.artist.toLowerCase()}';
        if (!_smartQueue.any((sq) =>
            '${sq.title.toLowerCase()}|${sq.artist.toLowerCase()}' == key)) {
          _smartQueue.add(t);
        }
      }
      BackgroundPrefetchService.instance
          .enqueueTracks(tracks.take(2).toList(), tag: 'smart_queue');
    } catch (e) {
      debugPrint('[Playback] Smart queue async error: $e');
    } finally {
      _smartQueueLoading = false;
      notifyListeners();
    }
  }

  Future<void> _handleCompletionAndAdvance() async {
    try {
      final adService = AdService();
      if (adService.willShowAdNext) {
        // Only stop audio if a video ad will actually be presented in the foreground
        await _audioPlayer.stop();
        _isPlaying = false;
        notifyListeners();
        await adService.onSongCompleted();
      } else {
        adService.onSongCompleted();
      }
    } catch (e) {
      debugPrint('[PlaybackService] Ad break check error: $e');
    }
    // Seamlessly advance to next song without tearing down foreground audio session
    await playNext(fromSync: true);
  }

  Future<void> playNext({bool fromSync = false}) async {
    if (!fromSync) {
      onManualPlaybackAction?.call();
    }
    if (AdService().isAdShowing) {
      debugPrint(
          '[PlaybackService] playNext blocked because ad is currently showing');
      return;
    }
    if (_queue.isNotEmpty && _queueIndex < _queue.length - 1) {
      if (_isShuffle) {
        final remaining = _queue.length - _queueIndex - 1;
        if (remaining > 0) {
          final offset = Random().nextInt(remaining);
          final swapIndex = _queueIndex + 1 + offset;
          final track = _queue.removeAt(swapIndex);
          _queue.insert(_queueIndex + 1, track);
        }
      }
      _queueIndex++;
      await _playCurrentQueueTrack(fromSync: fromSync);
    } else if (_loopMode == MeloLoopMode.all && _queue.isNotEmpty) {
      // Loop entire playlist / queue back to start
      _queueIndex = 0;
      await _playCurrentQueueTrack(fromSync: fromSync);
    } else if (_smartQueue.isNotEmpty) {
      // Autoplay / Smart recommendations when repeat is off
      final track = _smartQueue.removeAt(0);
      _queue.add(track);
      _queueIndex = _queue.length - 1;
      await playTrack(track, fromQueue: true, fromSync: fromSync);
      if (_smartQueue.length < 6) {
        _fetchSmartQueue();
      }
    } else if (_smartQueueLoading) {
      _pendingNext = true;
    } else if (_loopMode == MeloLoopMode.off && _currentTrack != null) {
      // If smart queue is completely empty and autoplay is active, fetch 15 fresh songs now!
      await _fetchSmartQueueAsync();
      if (_smartQueue.isNotEmpty) {
        final track = _smartQueue.removeAt(0);
        _queue.add(track);
        _queueIndex = _queue.length - 1;
        await playTrack(track, fromQueue: true, fromSync: fromSync);
      } else if (_isQueueMode && _queue.isNotEmpty) {
        _queueIndex = 0;
        await _playCurrentQueueTrack(fromSync: fromSync);
      }
    } else if (_isQueueMode && _queue.isNotEmpty) {
      _queueIndex = 0;
      await _playCurrentQueueTrack(fromSync: fromSync);
    }
  }

  Future<void> playPrevious({bool fromSync = false}) async {
    if (!fromSync) {
      onManualPlaybackAction?.call();
    }
    if (_queue.isEmpty || _queueIndex <= 0) return;
    _queueIndex--;
    await _playCurrentQueueTrack(fromSync: fromSync);
  }

  Future<void> _playCurrentQueueTrack({bool fromSync = false}) async {
    if (_queueIndex < 0 || _queueIndex >= _queue.length) return;
    final track = _queue[_queueIndex];
    await playTrack(track, fromQueue: true, fromSync: fromSync);
  }

  /// Jumps straight to a specific track in the queue (used by the Now Playing
  /// "up next" strip) without touching shuffle/smart-queue state.
  Future<void> playQueueIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queueIndex = index;
    await _playCurrentQueueTrack();
  }

  /// Plays a smart-queue track picked from the queue panel. The panel shows
  /// queue songs + smart-queue songs as one flat list, so we adopt that same
  /// order as the real queue and jump to the tapped track inside it. That way
  /// auto-advance (and the next button) continue with the song that actually
  /// follows the tapped one — no reordering, no wrong "next".
  Future<void> playQueueTrack(SearchResult track) async {
    final flat = <SearchResult>[
      ..._queue,
      for (final t in _smartQueue)
        if (!_queue.any((q) => q.title == t.title && q.artist == t.artist)) t,
    ];
    final pos = flat
        .indexWhere((t) => t.title == track.title && t.artist == track.artist);
    if (pos < 0) {
      await playTrack(track, fromQueue: true);
      return;
    }
    _queue = flat;
    _queueIndex = pos;
    _smartQueue = [];
    await playTrack(track, fromQueue: true);
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    if (index < _queueIndex) {
      _queueIndex--;
    } else if (index == _queueIndex) {
      if (_queue.isEmpty) {
        stop();
      } else {
        if (_queueIndex >= _queue.length) _queueIndex = _queue.length - 1;
        _playCurrentQueueTrack();
      }
    }
    notifyListeners();
  }

  void clearUpcomingQueue() {
    if (_queue.isEmpty) return;
    if (_queueIndex >= 0 && _queueIndex < _queue.length) {
      final current = _queue[_queueIndex];
      _queue = [current];
      _queueIndex = 0;
    } else {
      _queue = [];
      _queueIndex = -1;
    }
    _smartQueue = [];
    notifyListeners();
  }

  /// Appends a track to the current playing queue. If nothing is playing or
  /// the queue is empty, begins playback of this track immediately.
  void addToQueue(SearchResult track) {
    if (_currentTrack == null || _queue.isEmpty) {
      setQueue([track], 0);
      playTrack(track, fromQueue: true);
    } else {
      _queue.add(track);
      _isQueueMode = true;
      BackgroundPrefetchService.instance
          .enqueueTracks([track], tag: 'user_queue');
      notifyListeners();
    }
  }

  /// After a track starts, gently prefetch the CDN stream for the NEXT queued
  /// song on the device so tapping next (or auto-advance) is instant.
  void _prefetchNextInQueue() {
    SearchResult? next;
    if (_isQueueMode &&
        _queue.isNotEmpty &&
        _queueIndex >= 0 &&
        _queueIndex + 1 < _queue.length) {
      next = _queue[_queueIndex + 1];
    } else if (!_isQueueMode && _smartQueue.isNotEmpty) {
      next = _smartQueue.first;
    }
    if (next != null) {
      BackgroundPrefetchService.instance
          .enqueueTracks([next], tag: 'next_in_queue');
    }
  }

  /// Auto-caches the current song on the phone after ~45s of continuous
  /// listening (so skipped songs are never cached). Guarded by the play
  /// generation, so skipping/changing tracks cancels the pending cache.
  /// The download runs silently in the background and finishes while the song
  /// is still playing, making an immediate replay instant and offline.
  void _armAutoCacheTimer(SearchResult track, int generation) {
    Future.delayed(const Duration(seconds: 45), () {
      if (generation != _playGeneration) return;
      if (_currentTrack == null || _currentTrack!.id != track.id) return;
      if (_isLoading || _isPlaying == false) return;
      AutoCacheService.cacheTrack(track);
    });
  }

  void stop() {
    _playGeneration++;
    _audioPlayer.stop();
    _currentTrack = null;
    _isPlaying = false;
    _isVisible = false;
    notifyListeners();
  }

  /// Fully resets the singleton so no state leaks to another account after
  /// sign-out/sign-in: stops audio, clears current track, queue, stream-URL
  /// cache and lyrics.
  void reset() {
    _playGeneration++;
    _audioPlayer.stop();
    _currentTrack = null;
    _isPlaying = false;
    _isLoading = false;
    _isVisible = false;
    _loopMode = MeloLoopMode.off;
    _isShuffle = false;
    _currentLyrics = null;
    _lyricsLoading = false;
    _lyricsKey = null;
    _queue = [];
    _queueIndex = -1;
    _unshuffledQueue = null;
    _smartQueue = [];
    _smartQueueLoading = false;
    _pendingNext = false;
    _isQueueMode = false;
    _trackStartTime = null;
    _hasBeenReplayed = false;
    _context = null;
    _savePlaybackState();
    notifyListeners();
  }

  void hide() {
    _isVisible = false;
    notifyListeners();
  }

  void show() {
    if (_currentTrack != null) {
      _isVisible = true;
      notifyListeners();
    }
  }

  void _logSkip(SearchResult track, int elapsedSeconds) {
    ListeningHistoryService.logEvent(
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      image: track.image,
      genre: track.genre,
      skipped: true,
      completed: false,
      replayed: false,
      listenDuration: elapsedSeconds,
      source: 'vibe',
      artistId: track.artistId,
      artistImage: track.artistImage,
    );
  }

  void _logCompletion() {
    if (_currentTrack == null || _trackStartTime == null) return;
    final elapsed = DateTime.now().difference(_trackStartTime!).inSeconds;
    final totalDuration = _parseDuration(_currentTrack!.duration);
    final playedPercent = totalDuration > 0 ? elapsed / totalDuration : 0.0;

    if (playedPercent >= 0.8) {
      ListeningHistoryService.logEvent(
        trackId: _currentTrack!.id,
        title: _currentTrack!.title,
        artist: _currentTrack!.artist,
        image: _currentTrack!.image,
        genre: _currentTrack!.genre,
        skipped: false,
        completed: true,
        replayed: _hasBeenReplayed,
        listenDuration: elapsed,
        source: 'vibe',
        artistId: _currentTrack!.artistId,
        artistImage: _currentTrack!.artistImage,
      );
    }
  }

  void _logReplay() {
    if (_currentTrack == null) return;
    _hasBeenReplayed = true;
    ListeningHistoryService.logEvent(
      trackId: _currentTrack!.id,
      title: _currentTrack!.title,
      artist: _currentTrack!.artist,
      image: _currentTrack!.image,
      genre: _currentTrack!.genre,
      skipped: false,
      completed: false,
      replayed: true,
      listenDuration: 0,
      source: 'vibe',
      artistId: _currentTrack!.artistId,
      artistImage: _currentTrack!.artistImage,
    );
  }

  @override
  void dispose() {
    _positionController.close();
    _audioPlayer.dispose();
    super.dispose();
  }
}
