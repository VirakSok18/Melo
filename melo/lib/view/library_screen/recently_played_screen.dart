import '../../widgets/cached_image.dart';
import 'package:flutter/material.dart';
import '../../services/listening_history_service.dart';
import '../../services/search_service.dart';
import '../../services/playback_service.dart';
import '../../services/youtube_service.dart';
import '../../services/premium_service.dart';
import '../../services/cookie_service.dart';
import '../../widgets/now_playing_badge.dart';
import '../../widgets/song_options_modal.dart';
import '../search_screen/mini_player.dart';

class RecentlyPlayedScreen extends StatefulWidget {
  const RecentlyPlayedScreen({super.key});

  @override
  State<RecentlyPlayedScreen> createState() => _RecentlyPlayedScreenState();
}

class _RecentlyPlayedScreenState extends State<RecentlyPlayedScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    ListeningHistoryService.onUpdate.addListener(_onHistoryUpdate);
    PlaybackService().addListener(_onPlaybackChanged);
  }

  @override
  void dispose() {
    ListeningHistoryService.onUpdate.removeListener(_onHistoryUpdate);
    PlaybackService().removeListener(_onPlaybackChanged);
    super.dispose();
  }

  void _onHistoryUpdate() => _loadHistory(force: true);

  void _onPlaybackChanged() {
    final current = PlaybackService().currentTrack;
    if (current == null) return;
    if (_history.isNotEmpty && _history.first['title'] == current.title) return;

    final existingIndex = _history.indexWhere(
      (s) => s['title'] == current.title && s['artist'] == current.artist,
    );

    final entry = <String, dynamic>{
      'trackId': current.id,
      'title': current.title,
      'artist': current.artist,
      'image': current.image,
      'genre': current.genre,
      'skipped': false,
      'completed': false,
      'replayed': false,
      'listenDuration': 0,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    setState(() {
      if (existingIndex >= 0) _history.removeAt(existingIndex);
      _history.insert(0, entry);
    });
  }

  Future<void> _loadHistory({bool force = false}) async {
    final history =
        await ListeningHistoryService.getHistory(days: 30, force: force);
    if (mounted) {
      setState(() {
        _history = List<Map<String, dynamic>>.from(history);
        _isLoading = false;
      });
      _prefetchAll(_history);
    }
  }

  void _prefetchAll(List<Map<String, dynamic>> songs) {
    final tracks = songs
        .map((s) => SearchResult(
              type: 'song',
              id: s['trackId'] ?? '',
              title: s['title'] ?? '',
              artist: s['artist'] ?? '',
              artistId: s['artistId'] ?? '',
              artistImage: s['artistImage'] ?? '',
              image: s['image'] ?? '',
              duration: '',
              nbFan: 0,
              previewUrl: '',
            ))
        .toList();
    YouTubeService.prefetchStreamUrls(tracks);
  }

  void _playTrack(int index) {
    if (index >= _history.length) return;
    final track = _history[index];
    final now = DateTime.now().toUtc().toIso8601String();
    final updated = Map<String, dynamic>.from(track)..['created_at'] = now;

    setState(() {
      _history.removeAt(index);
      _history.insert(0, updated);
    });

    final queue = _history
        .map((s) => SearchResult(
              type: 'song',
              id: s['trackId'] ?? '',
              title: s['title'] ?? '',
              artist: s['artist'] ?? '',
              artistId: s['artistId'] ?? '',
              artistImage: s['artistImage'] ?? '',
              image: s['image'] ?? '',
              duration: '',
              nbFan: 0,
              previewUrl: '',
            ))
        .toList();
    if (!PremiumService().checkAndConsumeTrackSwitch(
      context,
      newTitle: queue[0].title,
      newArtist: queue[0].artist,
      newId: queue[0].id,
    )) {
      return;
    }
    final playback = PlaybackService();
    playback.setQueue(queue, 0);
    playback.playTrack(queue[0], fromQueue: true);
  }

  String _getTimeOfDay(DateTime date) {
    final hour = date.hour;
    if (hour >= 5 && hour < 12) return 'Morning';
    if (hour >= 12 && hour < 17) return 'Afternoon';
    if (hour >= 17 && hour < 21) return 'Evening';
    return 'Night';
  }

  IconData _getTimeIcon(String time) {
    switch (time) {
      case 'Morning':
        return Icons.wb_sunny_outlined;
      case 'Afternoon':
        return Icons.wb_cloudy_outlined;
      case 'Evening':
        return Icons.wb_twilight_outlined;
      case 'Night':
        return Icons.nightlight_outlined;
      default:
        return Icons.schedule;
    }
  }

  String _getDayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final songDay = DateTime(date.year, date.month, date.day);

    if (!songDay.isBefore(today)) return 'Today';
    if (!songDay.isBefore(yesterday)) return 'Yesterday';
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String _timeAgo(String? createdAt) {
    if (createdAt == null || createdAt.isEmpty) return '';
    final date = DateTime.tryParse(createdAt);
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  Map<String, Map<String, List<Map<String, dynamic>>>> _groupByDayAndTime() {
    final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final song in _history) {
      final createdAt = song['created_at'] as String? ?? '';
      DateTime? date =
          createdAt.isNotEmpty ? DateTime.tryParse(createdAt) : null;
      if (date != null && date.isUtc) date = date.toLocal();

      final dayLabel = date != null ? _getDayLabel(date) : 'Earlier';
      final timeOfDay = date != null ? _getTimeOfDay(date) : 'Unknown';

      grouped.putIfAbsent(dayLabel, () => {});
      grouped[dayLabel]!.putIfAbsent(timeOfDay, () => []);
      grouped[dayLabel]![timeOfDay]!.add(song);
    }
    return grouped;
  }

  void _removeSongFromHistory(Map<String, dynamic> song) {
    final title = song['title'] as String? ?? '';
    final artist = song['artist'] as String? ?? '';
    final trackId = song['trackId'] as String? ?? '';

    setState(() {
      _history.removeWhere((s) {
        if (trackId.isNotEmpty && s['trackId'] == trackId) return true;
        return s['title'] == title && s['artist'] == artist;
      });
    });

    ListeningHistoryService.removeFromHistory(
      title: title,
      artist: artist,
      trackId: trackId,
    );

    CookieService.show(
      message: 'Removed from history',
      icon: Icons.delete_outline_rounded,
      iconColor: Colors.white70,
    );
  }

  void _showSongOptions(Map<String, dynamic> song) {
    final searchResult = SearchResult(
      type: 'song',
      id: song['trackId']?.toString() ?? '',
      title: song['title'] as String? ?? '',
      artist: song['artist'] as String? ?? '',
      artistId: song['artistId'] as String? ?? '',
      artistImage: song['artistImage'] as String? ?? '',
      image: song['image'] as String? ?? '',
      duration: song['duration'] as String? ?? '',
      nbFan: 0,
      previewUrl: '',
    );

    SongOptionsModal.show(
      context,
      searchResult,
      onRemoveFromHistory: () => _removeSongFromHistory(song),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final grouped = _groupByDayAndTime();

    return Scaffold(
      backgroundColor: const Color(0xFF191919),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, topPadding + 16, 16, 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Recently Played',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF514AED), strokeWidth: 2)),
                )
              else if (_history.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No listening history',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 14,
                          fontFamily: 'Poppins'),
                    ),
                  ),
                )
              else
                for (final dayEntry in grouped.entries) ...[
                  SliverToBoxAdapter(
                    child: _buildDayHeader(dayEntry.key, dayEntry.value),
                  ),
                  for (final timeEntry in dayEntry.value.entries) ...[
                    SliverToBoxAdapter(
                      child: _buildTimeHeader(
                          dayEntry.key, timeEntry.key, timeEntry.value),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            _buildSongTile(timeEntry.value[index]),
                        childCount: timeEntry.value.length,
                      ),
                    ),
                  ],
                ],
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
        ],
      ),
    );
  }

  Widget _buildDayHeader(
      String day, Map<String, List<Map<String, dynamic>>> timeGroups) {
    final totalCount =
        timeGroups.values.fold(0, (sum, list) => sum + list.length);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: const Color(0xFF514AED),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            day,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$totalCount songs',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeHeader(
      String day, String timeOfDay, List<Map<String, dynamic>> songs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF514AED).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(_getTimeIcon(timeOfDay),
                color: const Color(0xFF7A73FF), size: 14),
          ),
          const SizedBox(width: 8),
          Text(
            timeOfDay,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '•  ${songs.length}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 11.5,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongTile(Map<String, dynamic> song) {
    final image = song['image'] as String? ?? '';
    final title = song['title'] as String? ?? '';
    final artist = song['artist'] as String? ?? '';
    final trackId = song['trackId'] as String? ?? '';
    final createdAt =
        song['createdAt'] as String? ?? song['created_at'] as String? ?? '';

    return TrackHighlight(
      trackId: trackId,
      title: title,
      artist: artist,
      builder: (context, isCurrent) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          decoration: BoxDecoration(
            color: isCurrent
                ? const Color(0xFF514AED).withValues(alpha: 0.12)
                : const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCurrent
                  ? const Color(0xFF514AED)
                  : Colors.white.withValues(alpha: 0.04),
              width: isCurrent ? 1.5 : 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                final index = _history.indexOf(song);
                if (index >= 0) _playTrack(index);
              },
              onLongPress: () => _showSongOptions(song),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 46,
                            height: 46,
                            child: image.isNotEmpty
                                ? CachedImage(image,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _placeholder())
                                : _placeholder(),
                          ),
                        ),
                        if (isCurrent)
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Icon(Icons.equalizer_rounded,
                                  color: Color(0xFF7A73FF), size: 20),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: isCurrent
                                  ? const Color(0xFF7A73FF)
                                  : Colors.white,
                              fontSize: 13.5,
                              fontWeight:
                                  isCurrent ? FontWeight.w600 : FontWeight.w500,
                              fontFamily: 'Poppins',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            artist,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 11.5,
                              fontFamily: 'Poppins',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _timeAgo(createdAt),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _removeSongFromHistory(song),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withValues(alpha: 0.35),
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFF2A2A2A),
      child:
          const Icon(Icons.music_note_rounded, color: Colors.white24, size: 22),
    );
  }
}
