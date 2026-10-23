import 'package:flutter/material.dart';
import 'cached_image.dart';
import '../services/search_service.dart';
import '../services/playback_service.dart';
import '../services/liked_songs_service.dart';
import '../services/playlist_service.dart';
import '../services/premium_service.dart';
import '../services/download_service.dart';
import '../services/cookie_service.dart';
import '../services/share_service.dart';
import '../services/listening_history_service.dart';
import '../view/library_screen/create_playlist_dialog.dart';

class SongOptionsModal {
  static void show(
    BuildContext context,
    SearchResult initialResult, {
    VoidCallback? onRemoveFromHistory,
    bool showPlaybackSpeed = false,
    bool followCurrentTrack = false,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141419),
      barrierColor: Colors.black.withValues(alpha: 0.65),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (bottomSheetContext) {
        return ListenableBuilder(
          listenable: Listenable.merge([
            PlaybackService(),
            LikedSongsService.onUpdate,
          ]),
          builder: (context, _) {
            // In Now Playing, keep this sheet in sync if autoplay or the user
            // changes the track while it remains open.
            final result = followCurrentTrack
                ? PlaybackService().currentTrack ?? initialResult
                : initialResult;
            final isLiked = LikedSongsService.isLiked(
              result.id,
              title: result.title,
              artist: result.artist,
            );
            final isDownloaded = DownloadService.isDownloaded(result.id);

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Header with image, title, and artist
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 48,
                            height: 48,
                            color: Colors.white.withValues(alpha: 0.06),
                            child: result.image.isNotEmpty
                                ? CachedImage(
                                    result.image,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.music_note,
                                      color: Colors.white38,
                                      size: 24,
                                    ),
                                  )
                                : const Icon(
                                    Icons.music_note,
                                    color: Colors.white38,
                                    size: 24,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                result.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Poppins',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textScaler: TextScaler.noScaling,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                result.artist,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 13,
                                  fontFamily: 'Poppins',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textScaler: TextScaler.noScaling,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(
                      color: Colors.white.withValues(alpha: 0.06),
                      height: 1,
                    ),
                    const SizedBox(height: 8),

                    if (showPlaybackSpeed && !followCurrentTrack)
                      ListenableBuilder(
                        listenable: PlaybackService(),
                        builder: (context, _) {
                          final playback = PlaybackService();
                          final speed = playback.speed;
                          final label = speed == 1.0
                              ? 'Normal'
                              : '${speed.toString().replaceAll('.0', '')}×';
                          return Container(
                            height: 46,
                            margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.045),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.speed_rounded,
                                    color: Colors.white70, size: 19),
                                const SizedBox(width: 8),
                                const Text('Speed',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'Poppins')),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 2,
                                      thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 5),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                              overlayRadius: 10),
                                    ),
                                    child: Slider(
                                      value: speed,
                                      min: 0.5,
                                      max: 2.0,
                                      divisions: 6,
                                      activeColor: const Color(0xFF514AED),
                                      inactiveColor: Colors.white24,
                                      onChanged: playback.setSpeed,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(label,
                                    style: const TextStyle(
                                        color: Color(0xFF9D98FF),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'Poppins')),
                              ],
                            ),
                          );
                        },
                      ),

                    // 1. Add to Queue
                    ListTile(
                      leading: const Icon(
                        Icons.queue_music_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      title: const Text(
                        'Add to Queue',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Poppins',
                        ),
                        textScaler: TextScaler.noScaling,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      onTap: () {
                        Navigator.pop(bottomSheetContext);
                        PlaybackService().addToQueue(result);
                        CookieService.show(
                          message: 'Added "${result.title}" to queue',
                          icon: Icons.queue_music_rounded,
                          iconColor: const Color(0xFF8A82FF),
                        );
                      },
                    ),

                    // 2. Add / Remove from Liked Songs
                    ListTile(
                      leading: Icon(
                        isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: isLiked ? const Color(0xFF514AED) : Colors.white,
                        size: 22,
                      ),
                      title: Text(
                        isLiked
                            ? 'Remove from Liked Songs'
                            : 'Add to Liked Songs',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Poppins',
                        ),
                        textScaler: TextScaler.noScaling,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      onTap: () async {
                        Navigator.pop(bottomSheetContext);
                        if (isLiked) {
                          await LikedSongsService.unlikeSong(
                            result.id,
                            title: result.title,
                            artist: result.artist,
                          );
                          CookieService.show(
                            message: 'Removed from Liked Songs',
                            icon: Icons.favorite_border_rounded,
                            iconColor: Colors.white60,
                          );
                        } else {
                          await LikedSongsService.likeSong(
                            trackId: result.id,
                            title: result.title,
                            artist: result.artist,
                            image: result.image,
                            artistId: result.artistId,
                            artistImage: result.artistImage,
                          );
                          CookieService.show(
                            message: 'Added to Liked Songs',
                            icon: Icons.favorite_rounded,
                            iconColor: const Color(0xFF514AED),
                          );
                        }
                      },
                    ),

                    // 3. Add to Playlist
                    ListTile(
                      leading: const Icon(
                        Icons.playlist_add_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      title: const Text(
                        'Add to Playlist',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Poppins',
                        ),
                        textScaler: TextScaler.noScaling,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      onTap: () {
                        Navigator.pop(bottomSheetContext);
                        _showAddToPlaylistSheet(context, result);
                      },
                    ),

                    // 4. Download / Remove Download
                    ListTile(
                      leading: Icon(
                        isDownloaded
                            ? Icons.download_done_rounded
                            : Icons.download_rounded,
                        color: isDownloaded
                            ? const Color(0xFF514AED)
                            : Colors.white,
                        size: 22,
                      ),
                      title: Text(
                        isDownloaded
                            ? 'Remove from Downloads'
                            : 'Download Song',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Poppins',
                        ),
                        textScaler: TextScaler.noScaling,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      onTap: () async {
                        Navigator.pop(bottomSheetContext);
                        if (!PremiumService().canDownloadOffline) {
                          PremiumService.showUpsell(context,
                              feature: 'Offline Music Downloads');
                          return;
                        }
                        if (isDownloaded) {
                          await DownloadService.removeDownload(result.id);
                          CookieService.show(
                            message: 'Removed "${result.title}" from downloads',
                            icon: Icons.delete_outline_rounded,
                            iconColor: Colors.white70,
                          );
                        } else {
                          DownloadService.download(
                            trackId: result.id,
                            title: result.title,
                            artist: result.artist,
                            image: result.image,
                            artistId: result.artistId,
                            artistImage: result.artistImage,
                          );
                          CookieService.show(
                            message: 'Downloading "${result.title}"...',
                            icon: Icons.download_rounded,
                            iconColor: const Color(0xFF8A82FF),
                          );
                        }
                      },
                    ),

                    // 5. Share Song
                    ListTile(
                      leading: const Icon(
                        Icons.share_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      title: const Text(
                        'Share Song',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Poppins',
                        ),
                        textScaler: TextScaler.noScaling,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      onTap: () {
                        Navigator.pop(bottomSheetContext);
                        ShareService.shareSong(
                          songId: result.id,
                          title: result.title,
                          artist: result.artist,
                        );
                      },
                    ),

                    if (showPlaybackSpeed && followCurrentTrack)
                      ListenableBuilder(
                        listenable: PlaybackService(),
                        builder: (context, _) {
                          final playback = PlaybackService();
                          final speed = playback.speed;
                          final label = speed == 1.0 ? 'Normal' : '$speed×';
                          return SizedBox(
                            height: 42,
                            child: Row(
                              children: [
                                const SizedBox(width: 8),
                                const Icon(Icons.speed_rounded,
                                    color: Colors.white70, size: 19),
                                const SizedBox(width: 10),
                                const Text('Speed',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'Poppins')),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 2,
                                      thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 5),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                              overlayRadius: 10),
                                    ),
                                    child: Slider(
                                      value: speed,
                                      min: 0.5,
                                      max: 2.0,
                                      divisions: 6,
                                      activeColor: const Color(0xFF514AED),
                                      inactiveColor: Colors.white24,
                                      onChanged: playback.setSpeed,
                                    ),
                                  ),
                                ),
                                Text(label,
                                    style: const TextStyle(
                                        color: Color(0xFF9D98FF),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'Poppins')),
                                const SizedBox(width: 8),
                              ],
                            ),
                          );
                        },
                      ),

                    // 6. Remove from History (if applicable)
                    if (onRemoveFromHistory != null)
                      ListTile(
                        leading: const Icon(
                          Icons.delete_outline_rounded,
                          color: Color(0xFFFF5252),
                          size: 22,
                        ),
                        title: const Text(
                          'Remove from History',
                          style: TextStyle(
                            color: Color(0xFFFF5252),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Poppins',
                          ),
                          textScaler: TextScaler.noScaling,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 0),
                        onTap: () {
                          Navigator.pop(bottomSheetContext);
                          onRemoveFromHistory();
                        },
                      ),

                    const SizedBox(height: 8),

                    // Taste Tuning Section
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.pop(bottomSheetContext);
                                ListeningHistoryService.recommendMore(
                                    '', result.title, result.artist);
                                CookieService.show(
                                  message:
                                      "We'll tune your taste with more like this",
                                  icon: Icons.thumb_up_rounded,
                                  iconColor: const Color(0xFF8A82FF),
                                );
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.thumb_up_alt_outlined,
                                        color: Colors.white, size: 16),
                                    SizedBox(width: 8),
                                    Text(
                                      'More like this',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'Poppins',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.pop(bottomSheetContext);
                                ListeningHistoryService.recommendLess(
                                    '', result.title, result.artist);
                                CookieService.show(
                                  message:
                                      "We'll tune your taste with less of this",
                                  icon: Icons.thumb_down_rounded,
                                  iconColor: Colors.white70,
                                );
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.thumb_down_alt_outlined,
                                        color: Colors.white70, size: 16),
                                    SizedBox(width: 8),
                                    Text(
                                      'Less of this',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'Poppins',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static void _showAddToPlaylistSheet(
      BuildContext context, SearchResult result) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141419),
      barrierColor: Colors.black.withValues(alpha: 0.65),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final playlists = PlaylistService().playlists;

            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.85,
              expand: false,
              builder: (_, scrollController) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Column(
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Add to Playlist',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                        textScaler: TextScaler.noScaling,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select a playlist for "${result.title}"',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontFamily: 'Poppins',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF514AED).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Color(0xFF8A82FF),
                            size: 24,
                          ),
                        ),
                        title: const Text(
                          'New Playlist',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                          textScaler: TextScaler.noScaling,
                        ),
                        subtitle: Text(
                          'Create and add to new playlist',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12,
                            fontFamily: 'Poppins',
                          ),
                          textScaler: TextScaler.noScaling,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          CreatePlaylistBottomSheet.show(
                            context: context,
                            onCreated: (name, coverPath, isPublic) async {
                              final song = PlaylistSong(
                                trackId: result.id,
                                title: result.title,
                                artist: result.artist,
                                image: result.image,
                                duration: result.duration,
                                artistId: result.artistId,
                                artistImage: result.artistImage,
                              );
                              final newPl =
                                  await PlaylistService().createPlaylist(
                                name,
                                coverImage: coverPath,
                                isPublic: isPublic,
                              );
                              await PlaylistService().addSong(newPl.id, song);
                              CookieService.show(
                                message: 'Added to "$name"',
                                icon: Icons.playlist_add_check_rounded,
                                iconColor: const Color(0xFF8A82FF),
                              );
                            },
                          );
                        },
                      ),
                      Divider(
                        color: Colors.white.withValues(alpha: 0.08),
                        height: 16,
                      ),
                      Expanded(
                        child: playlists.isEmpty
                            ? Center(
                                child: Text(
                                  'No playlists yet',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 14,
                                    fontFamily: 'Poppins',
                                  ),
                                  textScaler: TextScaler.noScaling,
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: playlists.length,
                                itemBuilder: (_, i) {
                                  final pl = playlists[i];
                                  final alreadyAdded = pl.songs
                                      .any((s) => s.trackId == result.id);
                                  final coverProvider =
                                      pl.effectiveCoverProvider;

                                  return ListTile(
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.06),
                                          image: coverProvider != null
                                              ? DecorationImage(
                                                  image: coverProvider,
                                                  fit: BoxFit.cover,
                                                )
                                              : null,
                                        ),
                                        child: coverProvider == null
                                            ? const Icon(
                                                Icons.queue_music,
                                                color: Colors.white38,
                                                size: 22,
                                              )
                                            : null,
                                      ),
                                    ),
                                    title: Text(
                                      pl.name,
                                      style: TextStyle(
                                        color: alreadyAdded
                                            ? Colors.white38
                                            : Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'Poppins',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textScaler: TextScaler.noScaling,
                                    ),
                                    subtitle: Text(
                                      alreadyAdded
                                          ? 'Already added'
                                          : '${pl.songs.length} ${pl.songs.length == 1 ? 'song' : 'songs'}',
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.35),
                                        fontSize: 12,
                                        fontFamily: 'Poppins',
                                      ),
                                      textScaler: TextScaler.noScaling,
                                    ),
                                    trailing: alreadyAdded
                                        ? const Icon(
                                            Icons.check_rounded,
                                            color: Color(0xFF514AED),
                                            size: 20,
                                          )
                                        : null,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 0),
                                    onTap: alreadyAdded
                                        ? null
                                        : () async {
                                            Navigator.pop(sheetContext);
                                            final song = PlaylistSong(
                                              trackId: result.id,
                                              title: result.title,
                                              artist: result.artist,
                                              image: result.image,
                                              duration: result.duration,
                                              artistId: result.artistId,
                                              artistImage: result.artistImage,
                                            );
                                            await PlaylistService()
                                                .addSong(pl.id, song);
                                            CookieService.show(
                                              message: 'Added to "${pl.name}"',
                                              icon: Icons
                                                  .playlist_add_check_rounded,
                                              iconColor:
                                                  const Color(0xFF8A82FF),
                                            );
                                          },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
