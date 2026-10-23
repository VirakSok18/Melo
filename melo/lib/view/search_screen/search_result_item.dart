import '../../widgets/cached_image.dart';
import 'package:flutter/material.dart';
import '../../services/search_service.dart';
import '../../services/playback_service.dart';
import '../../services/recent_search_service.dart';
import '../../services/premium_service.dart';
import '../../widgets/now_playing_badge.dart' show TrackHighlight, NowPlayingBars;
import '../artist_screen/artist_screen.dart';
import '../album_screen/album_detail_screen.dart';
import '../../widgets/fade_page_route.dart';
import '../../widgets/song_options_modal.dart';

class SearchResultItem extends StatelessWidget {
  final SearchResult result;
  final List<SearchResult>? allResults;
  final bool recordRecentSearch;
  final int? trackNumber;
  final bool showTypeBadge;
  final String? customSubtitle;
  final PlaybackContext? playbackContext;
  final VoidCallback? onTap;

  const SearchResultItem({
    super.key,
    required this.result,
    this.allResults,
    this.recordRecentSearch = true,
    this.trackNumber,
    this.showTypeBadge = true,
    this.customSubtitle,
    this.playbackContext,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TrackHighlight(
      trackId: result.id,
      title: result.title,
      artist: result.artist,
      builder: (context, isCurrent) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _onTap(context),
            onLongPress: result.type == 'song'
                ? () => SongOptionsModal.show(context, result)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  if (trackNumber != null) ...[
                    SizedBox(
                      width: 24,
                      child: isCurrent
                          ? NowPlayingBars(playing: PlaybackService().isPlaying)
                          : Text(
                              '$trackNumber',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Poppins',
                              ),
                              textAlign: TextAlign.center,
                            ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _buildImage(),
                  const SizedBox(width: 12),
                  Expanded(child: _buildInfo(isCurrent)),
                  const SizedBox(width: 8),
                  _buildTrailing(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImage() {
    final bool isArtist = result.type == 'artist';

    return ClipRRect(
      borderRadius: BorderRadius.circular(isArtist ? 22 : 8),
      child: Container(
        width: 44,
        height: 44,
        color: const Color(0xFF2A2A2A),
        child: result.image.isNotEmpty
            ? CachedImage(
                result.image,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholder(),
              )
            : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Icon(
      result.type == 'artist'
          ? Icons.person
          : result.type == 'album'
              ? Icons.album
              : result.type == 'playlist'
                  ? Icons.playlist_play_rounded
                  : Icons.music_note,
      color: Colors.white38,
      size: 20,
    );
  }

  Widget _buildInfo(bool isCurrent) {
    final effectiveSubtitle = customSubtitle ?? _subtitle;
    final hasSubtitleRow = showTypeBadge || effectiveSubtitle.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          result.title,
          style: TextStyle(
            color: isCurrent ? const Color(0xFF514AED) : Colors.white,
            fontSize: 13.5,
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
            fontFamily: 'Poppins',
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (hasSubtitleRow) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              if (showTypeBadge) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF514AED).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    result.type.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF8B85FF),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ),
              ],
              if (effectiveSubtitle.isNotEmpty)
                Expanded(
                  child: Text(
                    effectiveSubtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11.5,
                      fontFamily: 'Poppins',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String get _subtitle {
    switch (result.type) {
      case 'song':
        return 'Song \u00b7 ${result.artist}';
      case 'artist':
        if (result.nbFan > 0) {
          final fans = result.nbFan >= 1000000
              ? '${(result.nbFan / 1000000).toStringAsFixed(1)}M'
              : result.nbFan >= 1000
                  ? '${(result.nbFan / 1000).toStringAsFixed(0)}K'
                  : '${result.nbFan}';
          return 'Artist \u00b7 $fans fans';
        }
        return 'Artist';
      case 'playlist':
        return 'Playlist \u00b7 ${result.artist.isNotEmpty ? result.artist : 'Melo'}';
      case 'album':
        return 'Album \u00b7 ${result.artist}';
      default:
        return result.artist;
    }
  }

  Widget _buildTrailing(BuildContext context) {
    if (result.type == 'song') {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => SongOptionsModal.show(context, result),
        child: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
          child: const Icon(
            Icons.more_horiz_rounded,
            color: Colors.white54,
            size: 20,
          ),
        ),
      );
    } else {
      return const Icon(
        Icons.chevron_right_rounded,
        color: Colors.white24,
        size: 20,
      );
    }
  }

  void _onTap(BuildContext context) {
    if (recordRecentSearch) {
      RecentSearchService.addItem(result);
    }
    if (onTap != null) {
      onTap!();
      return;
    }
    if (result.type == 'song') {
      if (!PremiumService().checkAndConsumeTrackSwitch(
        context,
        newTitle: result.title,
        newArtist: result.artist,
        newId: result.id,
      )) {
        return;
      }
      final playback = PlaybackService();
      if (allResults != null && allResults!.length > 1) {
        final idx = allResults!.indexWhere((t) =>
            (t.id.isNotEmpty && t.id == result.id) ||
            (t.title.toLowerCase().trim() == result.title.toLowerCase().trim() &&
                t.artist.toLowerCase().trim() ==
                    result.artist.toLowerCase().trim()));
        playback.setQueue(
          allResults!,
          idx >= 0 ? idx : 0,
          context: playbackContext,
        );
        playback.playTrack(result, fromQueue: true);
      } else {
        playback.playTrack(result);
      }
    } else if (result.type == 'artist') {
      Navigator.of(context, rootNavigator: true).push(
        FadePageRoute(
          page: ArtistScreen(
            artistId: result.id,
            artistName: result.title,
            artistImage: result.image,
            nbFan: result.nbFan,
          ),
        ),
      );
    } else if (result.type == 'album') {
      Navigator.of(context, rootNavigator: true).push(
        FadePageRoute(
          page: AlbumDetailScreen(
            albumId: result.id,
            albumTitle: result.title,
            albumImage: result.image,
            artistName: result.artist,
            artistId: '',
          ),
        ),
      );
    }
  }
}
