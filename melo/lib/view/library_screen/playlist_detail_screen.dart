import 'dart:async';
import 'package:image_cropper/image_cropper.dart';
import '../../widgets/cached_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/playlist_service.dart';
import '../../services/playback_service.dart';
import '../../services/search_service.dart';
import '../../services/download_service.dart';
import '../../services/premium_service.dart';
import '../../services/youtube_service.dart';
import '../../services/profile_service.dart';
import '../../services/background_prefetch_service.dart';
import '../../services/share_service.dart';
import '../../services/cookie_service.dart';
import '../../widgets/now_playing_badge.dart';
import '../../widgets/song_options_modal.dart';
import '../search_screen/mini_player.dart';
import 'add_songs_bottom_sheet.dart';
import 'invite_collaborators_sheet.dart';
import '../profile_screen/user_profile_screen.dart';
import '../profile_screen/profile_screen.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final String playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final PlaylistService _playlistService = PlaylistService();
  final ImagePicker _picker = ImagePicker();

  RealtimeChannel? _songsRealtimeChannel;
  RealtimeChannel? _collabsRealtimeChannel;
  RealtimeChannel? _playlistMetaRealtimeChannel;
  Timer? _songsRealtimeDebounce;
  List<Map<String, dynamic>> _collaborators = [];
  Map<String, dynamic>? _creatorProfile;

  // Static in-memory caches to prevent refetching/flicker on every open
  static final Map<String, Map<String, dynamic>> _creatorProfileCache = {};
  static final Map<String, List<Map<String, dynamic>>> _collaboratorsCache = {};

  UserPlaylist? get _playlist =>
      _playlistService.getPlaylist(widget.playlistId);

  bool get _isOwner {
    final playlist = _playlist;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (playlist == null || currentUserId.isEmpty) return false;
    if (playlist.userId.isEmpty) return false;
    return playlist.userId == currentUserId;
  }

  @override
  void initState() {
    super.initState();
    _playlistService.addListener(_onUpdate);
    DownloadService.onUpdate.addListener(_onUpdate);
    _initSynchronousProfileAndCollabs();
    _initPlaylistData();
    _subscribeToRealtime();
    _prefetchPlaylistSongs();
  }

  void _initSynchronousProfileAndCollabs() {
    // 1. Instant cached collaborators from memory
    final cachedCollabs = _collaboratorsCache[widget.playlistId];
    if (cachedCollabs != null && cachedCollabs.isNotEmpty) {
      _collaborators = List<Map<String, dynamic>>.from(cachedCollabs);
    }

    // 2. Instant creator profile from memory cache, playlist properties, or ProfileService
    final playlist = _playlist;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final creatorId = playlist?.userId ?? '';

    if (creatorId.isNotEmpty && _creatorProfileCache.containsKey(creatorId)) {
      _creatorProfile = _creatorProfileCache[creatorId];
    } else if (creatorId.isEmpty || creatorId == currentUserId) {
      final prof = ProfileService();
      if (prof.displayName.isNotEmpty || prof.username.isNotEmpty) {
        _creatorProfile = {
          'id': currentUserId,
          'display_name': prof.displayName,
          'username': prof.username,
          'avatar_url': prof.avatarUrl,
        };
        if (creatorId.isNotEmpty) {
          _creatorProfileCache[creatorId] = _creatorProfile!;
        }
      }
    } else if (playlist != null &&
        (playlist.creatorName.isNotEmpty ||
            playlist.creatorAvatar.isNotEmpty)) {
      _creatorProfile = {
        'id': creatorId,
        'display_name': playlist.creatorName,
        'username': '',
        'avatar_url': playlist.creatorAvatar,
      };
      _creatorProfileCache[creatorId] = _creatorProfile!;
    }
  }

  Future<void> _initPlaylistData() async {
    if (_playlist == null) {
      await _playlistService.fetchPlaylistById(widget.playlistId);
      _initSynchronousProfileAndCollabs();
      if (mounted) setState(() {});
    }
    await Future.wait([
      _playlistService.refreshPlaylistSongs(widget.playlistId),
      _playlistService.refreshPlaylistMeta(widget.playlistId),
      _loadCollaboratorData(),
    ]);
    if (mounted) setState(() {});
  }

  void _subscribeToRealtime() {
    // 1. Live real-time updates for adding/removing/reordering songs
    _songsRealtimeChannel?.unsubscribe();
    _songsRealtimeChannel = Supabase.instance.client
        .channel('playlist_songs_realtime:${widget.playlistId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'playlist_songs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'playlist_id',
            value: widget.playlistId,
          ),
          callback: (payload) {
            debugPrint(
                '[PlaylistDetail] Live songs change: ${payload.eventType}');
            if (_playlistService.isRecentlyReordered(widget.playlistId)) {
              return;
            }
            _songsRealtimeDebounce?.cancel();
            _songsRealtimeDebounce =
                Timer(const Duration(milliseconds: 600), () async {
              if (!mounted) return;
              if (_playlistService.isRecentlyReordered(widget.playlistId)) {
                return;
              }
              await _playlistService.refreshPlaylistSongs(widget.playlistId);
              if (mounted) setState(() {});
            });
          },
        )
        .subscribe();

    // 2. Live real-time updates for member/collaborator joins and leaves
    _collabsRealtimeChannel?.unsubscribe();
    _collabsRealtimeChannel = Supabase.instance.client
        .channel('playlist_collabs_realtime:${widget.playlistId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'playlist_collaborators',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'playlist_id',
            value: widget.playlistId,
          ),
          callback: (payload) async {
            debugPrint(
                '[PlaylistDetail] Live collabs change: ${payload.eventType}');
            await _loadCollaboratorData();
            if (mounted) setState(() {});
          },
        )
        .subscribe();

    // 3. Live real-time updates for playlist name and cover image changes
    _playlistMetaRealtimeChannel?.unsubscribe();
    _playlistMetaRealtimeChannel = Supabase.instance.client
        .channel('playlist_meta_realtime:${widget.playlistId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_playlists',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.playlistId,
          ),
          callback: (payload) async {
            debugPrint(
                '[PlaylistDetail] Live playlist meta change: ${payload.eventType}');
            await _playlistService.refreshPlaylistMeta(widget.playlistId);
            if (mounted) setState(() {});
          },
        )
        .subscribe();
  }

  Future<void> _loadCollaboratorData() async {
    final playlist = _playlist;
    if (playlist == null) return;

    try {
      final client = Supabase.instance.client;
      // Fetch creator profile if available
      if (playlist.userId.isNotEmpty) {
        // If not cached or explicitly refreshing, fetch from DB
        final creator = await client
            .from('profiles')
            .select('id, display_name, username, avatar_url')
            .eq('id', playlist.userId)
            .maybeSingle();
        if (mounted && creator != null) {
          _creatorProfileCache[playlist.userId] = creator;
          // Only trigger rebuild if data actually changed
          if (_creatorProfile?['avatar_url'] != creator['avatar_url'] ||
              _creatorProfile?['display_name'] != creator['display_name']) {
            setState(() => _creatorProfile = creator);
          } else {
            _creatorProfile = creator;
          }
        }
      } else {
        final prof = ProfileService();
        if (mounted && _creatorProfile == null) {
          final profileData = {
            'id': client.auth.currentUser?.id ?? '',
            'display_name': prof.displayName,
            'username': prof.username,
            'avatar_url': prof.avatarUrl,
          };
          setState(() {
            _creatorProfile = profileData;
          });
        }
      }

      // Fetch collaborators
      final collabs =
          await _playlistService.fetchCollaborators(widget.playlistId);
      if (mounted) {
        _collaboratorsCache[widget.playlistId] = collabs;
        setState(() => _collaborators = collabs);
      }
    } catch (e) {
      debugPrint('[PlaylistDetail] Load collaborator data error: $e');
    }
  }

  void _prefetchPlaylistSongs() {
    final playlist = _playlist;
    if (playlist == null || playlist.songs.isEmpty) return;
    final tracks = playlist.songs
        .map((s) => SearchResult(
              type: 'song',
              id: s.trackId,
              title: s.title,
              artist: s.artist,
              artistId: s.artistId,
              artistImage: s.artistImage,
              image: s.image,
              duration: s.duration,
              nbFan: 0,
              previewUrl: '',
            ))
        .toList();
    YouTubeService.prefetchStreamUrls(tracks);
    BackgroundPrefetchService.instance
        .enqueueTracks(tracks, tag: 'playlist_detail');
  }

  @override
  void dispose() {
    _songsRealtimeDebounce?.cancel();
    _songsRealtimeChannel?.unsubscribe();
    _collabsRealtimeChannel?.unsubscribe();
    _playlistMetaRealtimeChannel?.unsubscribe();
    _playlistService.removeListener(_onUpdate);
    DownloadService.onUpdate.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    _prefetchPlaylistSongs();
    if (mounted) setState(() {});
  }

  void _playAll() {
    final playlist = _playlist;
    if (playlist == null || playlist.songs.isEmpty) return;
    final queue = playlist.songs
        .map((s) => SearchResult(
              type: 'song',
              id: s.trackId,
              title: s.title,
              artist: s.artist,
              artistId: s.artistId,
              artistImage: s.artistImage,
              image: s.image,
              duration: s.duration,
              nbFan: 0,
              previewUrl: '',
            ))
        .toList();
    final playback = PlaybackService();
    playback.setQueue(
      queue,
      0,
      context: PlaybackContext(
        type: 'playlist',
        id: widget.playlistId,
        title: playlist.name,
        coverImage: playlist.coverImage,
      ),
    );
    playback.playTrack(queue.first, fromQueue: true);
  }

  void _shufflePlay() {
    final playlist = _playlist;
    if (playlist == null || playlist.songs.isEmpty) return;
    final shuffled = List<PlaylistSong>.from(playlist.songs)..shuffle();
    final queue = shuffled
        .map((s) => SearchResult(
              type: 'song',
              id: s.trackId,
              title: s.title,
              artist: s.artist,
              artistId: s.artistId,
              artistImage: s.artistImage,
              image: s.image,
              duration: s.duration,
              nbFan: 0,
              previewUrl: '',
            ))
        .toList();
    final playback = PlaybackService();
    playback.setQueue(
      queue,
      0,
      context: PlaybackContext(
        type: 'playlist',
        id: widget.playlistId,
        title: playlist.name,
        coverImage: playlist.coverImage,
      ),
    );
    playback.playTrack(queue.first, fromQueue: true);
  }

  void _playTrack(int index) {
    final playlist = _playlist;
    if (playlist == null || index >= playlist.songs.length) return;
    final queue = playlist.songs
        .map((s) => SearchResult(
              type: 'song',
              id: s.trackId,
              title: s.title,
              artist: s.artist,
              artistId: s.artistId,
              artistImage: s.artistImage,
              image: s.image,
              duration: s.duration,
              nbFan: 0,
              previewUrl: '',
            ))
        .toList();
    if (!PremiumService().checkAndConsumeTrackSwitch(
      context,
      newTitle: queue[index].title,
      newArtist: queue[index].artist,
      newId: queue[index].id,
    )) {
      return;
    }
    final playback = PlaybackService();
    playback.setQueue(
      queue,
      index,
      context: PlaybackContext(
        type: 'playlist',
        id: widget.playlistId,
        title: playlist.name,
        coverImage: playlist.coverImage,
      ),
    );
    playback.playTrack(queue[index], fromQueue: true);
  }

  void _openAddSongs() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddSongsBottomSheet(playlistId: widget.playlistId),
    );
  }

  void _openInviteCollaborators() {
    final playlist = _playlist;
    if (playlist == null || !_isOwner) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InviteCollaboratorsSheet(
        playlistId: playlist.id,
        playlistName: playlist.name,
      ),
    );
  }

  void _showPlaylistMenu() {
    final isOwner = _isOwner;
    final playlist = _playlist;
    final isCollab = playlist?.isCollaborative ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2A2A2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading:
                    const Icon(Icons.share_outlined, color: Color(0xFF514AED)),
                title: const Text(
                  'Share playlist',
                  style: TextStyle(color: Colors.white, fontFamily: 'Poppins'),
                ),
                subtitle: Text(
                  'Share link with friends on WhatsApp, Telegram, etc.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  if (playlist != null) {
                    ShareService.sharePlaylist(
                      playlistId: widget.playlistId,
                      title: playlist.name,
                    );
                  }
                },
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.download_rounded,
                    color: Color(0xFF514AED)),
                title: const Text(
                  'Download all songs',
                  style: TextStyle(color: Colors.white, fontFamily: 'Poppins'),
                ),
                subtitle: Text(
                  'Saved to this phone in the background',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _downloadAllSongs();
                },
              ),
              if (isOwner) ...[
                const Divider(color: Colors.white12, height: 1),
                ListTile(
                  leading:
                      const Icon(Icons.edit_rounded, color: Color(0xFF514AED)),
                  title: const Text(
                    'Edit playlist',
                    style:
                        TextStyle(color: Colors.white, fontFamily: 'Poppins'),
                  ),
                  subtitle: Text(
                    'Change playlist name and cover picture',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _editPlaylist();
                  },
                ),
                const Divider(color: Colors.white12, height: 1),
                ListTile(
                  leading: Icon(
                    playlist?.isPublic == true
                        ? Icons.lock_outline_rounded
                        : Icons.public_rounded,
                    color: const Color(0xFF514AED),
                  ),
                  title: Text(
                    playlist?.isPublic == true ? 'Make private' : 'Make public',
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Poppins'),
                  ),
                  subtitle: Text(
                    playlist?.isPublic == true
                        ? 'Hide from your public profile'
                        : 'Show on your public profile for others',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final newPub = !(playlist?.isPublic ?? true);
                    await _playlistService.togglePublic(
                        widget.playlistId, newPub);
                    if (mounted) {
                      setState(() {});
                      CookieService.show(
                        message: newPub
                            ? 'Playlist is now public on your profile'
                            : 'Playlist is now private',
                        icon:
                            newPub ? Icons.public_rounded : Icons.lock_rounded,
                        iconColor: const Color(0xFF8A82FF),
                      );
                    }
                  },
                ),
              ],
              if (isCollab) ...[
                const Divider(color: Colors.white12, height: 1),
                ListTile(
                  leading: const Icon(Icons.group_outlined,
                      color: Color(0xFF817BFF)),
                  title: const Text(
                    'View Collaborators',
                    style:
                        TextStyle(color: Colors.white, fontFamily: 'Poppins'),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showMembersSheet();
                  },
                ),
              ],
              const Divider(color: Colors.white12, height: 1),
              if (isOwner)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: Color(0xFFFF4D4D)),
                  title: const Text(
                    'Delete playlist',
                    style: TextStyle(
                        color: Color(0xFFFF4D4D), fontFamily: 'Poppins'),
                  ),
                  subtitle: Text(
                    'Permanently delete this playlist for everyone',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _confirmDeletePlaylist();
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.exit_to_app_rounded,
                      color: Color(0xFFFF4D4D)),
                  title: const Text(
                    'Leave Collab',
                    style: TextStyle(
                        color: Color(0xFFFF4D4D), fontFamily: 'Poppins'),
                  ),
                  subtitle: Text(
                    'Remove this playlist from your library',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _confirmLeaveCollab();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeletePlaylist() {
    final playlist = _playlist;
    if (playlist == null) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF18181D),
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Delete Playlist?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '"${playlist.name}" and its ${playlist.songs.length} songs will be removed for everyone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  fontFamily: 'Poppins',
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await _playlistService
                              .deletePlaylist(widget.playlistId);
                          if (mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        child: const Text(
                          'Delete',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmLeaveCollab() {
    final playlist = _playlist;
    if (playlist == null) return;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF18181D),
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Leave Collab?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'You will no longer collaborate on "${playlist.name}". You can be reinvited anytime.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  fontFamily: 'Poppins',
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          if (currentUserId.isNotEmpty) {
                            await _playlistService.removeCollaborator(
                                widget.playlistId, currentUserId);
                          }
                          await _playlistService
                              .deletePlaylist(widget.playlistId);
                          if (mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        child: const Text(
                          'Leave',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _downloadAllSongs() {
    if (!PremiumService().canDownloadOffline) {
      PremiumService.showUpsell(context, feature: 'Offline Music Downloads');
      return;
    }
    final playlist = _playlist;
    if (playlist == null || playlist.songs.isEmpty) return;

    final pending = playlist.songs
        .where((s) => !DownloadService.isDownloaded(s.trackId))
        .toList();
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('All songs already downloaded'),
        backgroundColor: Color(0xFF2A2A2A),
      ));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Downloading ${pending.length} songs in background'),
      backgroundColor: const Color(0xFF2A2A2A),
    ));

    // Fire-and-forget: downloads run one by one in the background. Each song
    // row updates itself via the download service's notifiers.
    () async {
      for (final song in pending) {
        if (!DownloadService.isDownloaded(song.trackId)) {
          await DownloadService.download(
            trackId: song.trackId,
            title: song.title,
            artist: song.artist,
            image: song.image,
            artistId: song.artistId,
            artistImage: song.artistImage,
          );
        }
      }
    }();
  }

  void _editPlaylist() {
    final playlist = _playlist;
    if (playlist == null || !_isOwner) return;

    final nameController = TextEditingController(text: playlist.name);
    String? coverPath = playlist.coverImage;
    String? error;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;
          final coverProvider = PlaylistService.coverImageProvider(coverPath);

          Future<void> pickImage() async {
            final source = await showModalBottomSheet<ImageSource>(
              context: context,
              backgroundColor: const Color(0xFF2A2A2A),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (menuCtx) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Change cover image',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        leading: const Icon(Icons.camera_alt,
                            color: Color(0xFF514AED)),
                        title: const Text('Camera',
                            style: TextStyle(
                                color: Colors.white, fontFamily: 'Poppins')),
                        onTap: () =>
                            Navigator.of(menuCtx).pop(ImageSource.camera),
                      ),
                      ListTile(
                        leading: const Icon(Icons.photo_library,
                            color: Color(0xFF514AED)),
                        title: const Text('Gallery',
                            style: TextStyle(
                                color: Colors.white, fontFamily: 'Poppins')),
                        onTap: () =>
                            Navigator.of(menuCtx).pop(ImageSource.gallery),
                      ),
                    ],
                  ),
                ),
              ),
            );

            if (source != null) {
              final image = await _picker.pickImage(
                  source: source,
                  maxWidth: 1024,
                  maxHeight: 1024,
                  imageQuality: 85);
              if (image == null) return;

              try {
                final CroppedFile? cropped = await ImageCropper().cropImage(
                  sourcePath: image.path,
                  aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
                  uiSettings: [
                    AndroidUiSettings(
                      toolbarTitle: 'Crop Cover',
                      toolbarColor: const Color(0xFF191919),
                      toolbarWidgetColor: Colors.white,
                      backgroundColor: const Color(0xFF191919),
                      activeControlsWidgetColor: const Color(0xFF514AED),
                      initAspectRatio: CropAspectRatioPreset.square,
                      lockAspectRatio: true,
                    ),
                    IOSUiSettings(
                      title: 'Crop Cover',
                      aspectRatioLockEnabled: true,
                      resetAspectRatioEnabled: false,
                    ),
                  ],
                );
                if (cropped != null) {
                  setSheetState(() => coverPath = cropped.path);
                }
              } catch (_) {
                setSheetState(() => coverPath = image.path);
              }
            }
          }

          Future<void> save() async {
            final newName = nameController.text.trim();
            if (newName.isEmpty) {
              setSheetState(() => error = 'Playlist name cannot be empty');
              return;
            }
            setSheetState(() {
              isSaving = true;
              error = null;
            });

            try {
              if (newName != playlist.name) {
                await _playlistService.renamePlaylist(
                    widget.playlistId, newName);
              }
              if (coverPath != playlist.coverImage) {
                await _playlistService.updateCoverImage(
                    widget.playlistId, coverPath);
              }
              if (context.mounted) {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Playlist updated successfully'),
                    backgroundColor: Color(0xFF514AED),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            } catch (e) {
              setSheetState(() {
                error = 'Failed to save changes. Please try again.';
                isSaving = false;
              });
            }
          }

          return Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: 24 + bottomInset,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Edit Playlist',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white70, size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: pickImage,
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: coverProvider == null
                                  ? const Color(0xFF514AED)
                                      .withValues(alpha: 0.15)
                                  : null,
                              image: coverProvider != null
                                  ? DecorationImage(
                                      image: coverProvider,
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                              border: Border.all(
                                color: coverProvider == null
                                    ? const Color(0xFF514AED)
                                        .withValues(alpha: 0.3)
                                    : Colors.transparent,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: coverProvider == null
                                ? const Center(
                                    child: Icon(
                                      Icons.queue_music_rounded,
                                      size: 48,
                                      color: Color(0xFF817BFF),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: pickImage,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: const Color(0xFF514AED),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: const Color(0xFF1E1E1E), width: 3),
                              ),
                              child: const Icon(Icons.camera_alt,
                                  color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      coverPath != null && coverPath!.isNotEmpty
                          ? 'Change Cover'
                          : 'Add Cover Image',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Playlist Name',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Poppins',
                      fontSize: 15,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter playlist title...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontFamily: 'Poppins',
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: Color(0xFF514AED), width: 1.5),
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => save(),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(
                        color: Color(0xFFFF4D4D),
                        fontSize: 12,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: isSaving ? null : save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF514AED),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'Save Changes',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Poppins',
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_playlist == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF191919),
        body:
            Center(child: CircularProgressIndicator(color: Color(0xFF514AED))),
      );
    }

    final playlist = _playlist!;
    final topPadding = MediaQuery.of(context).padding.top;
    final imageHeight = MediaQuery.of(context).size.width;
    final firstSongImage =
        playlist.songs.isNotEmpty && playlist.songs.first.image.isNotEmpty
            ? playlist.songs.first.image
            : null;
    final coverProvider =
        PlaylistService.coverImageProvider(playlist.coverImage) ??
            (firstSongImage != null
                ? PlaylistService.coverImageProvider(firstSongImage)
                : null);

    return Scaffold(
      backgroundColor: const Color(0xFF191919),
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: imageHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (coverProvider != null)
                            Image(
                              image: coverProvider,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFF514AED),
                                      Color(0xFF3A3599),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFF514AED),
                                    Color(0xFF3A3599),
                                  ],
                                ),
                              ),
                            ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.3),
                                  Colors.transparent,
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.8),
                                  const Color(0xFF191919),
                                ],
                                stops: const [0.0, 0.15, 0.5, 0.85, 1.0],
                              ),
                            ),
                          ),
                          Positioned(
                            top: topPadding + 12,
                            left: 16,
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.3),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: topPadding + 12,
                            right: 16,
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    ShareService.sharePlaylist(
                                      playlistId: widget.playlistId,
                                      title: playlist.name,
                                    );
                                  },
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color:
                                          Colors.black.withValues(alpha: 0.3),
                                    ),
                                    child: const Icon(
                                      Icons.share_outlined,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _showPlaylistMenu,
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color:
                                          Colors.black.withValues(alpha: 0.3),
                                    ),
                                    child: const Icon(
                                      Icons.more_vert,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            left: 20,
                            right: _isOwner ? 20 : 80,
                            bottom: _isOwner ? 80 : 20,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.15),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    '${playlist.songs.length} SONGS',
                                    style: const TextStyle(
                                      color: Color(0xFFA5A0FF),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  playlist.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Poppins',
                                    height: 1.2,
                                    shadows: [
                                      Shadow(
                                          color: Colors.black87,
                                          blurRadius: 8,
                                          offset: Offset(0, 1)),
                                    ],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (playlist.isCollaborative) ...[
                                  const SizedBox(height: 4),
                                  _buildCollaboratorsHeader(playlist),
                                ],
                              ],
                            ),
                          ),
                          Positioned(
                            right: 20,
                            bottom: 20,
                            child: ListenableBuilder(
                              listenable: PlaybackService(),
                              builder: (context, _) {
                                final playback = PlaybackService();
                                final currentTrack = playback.currentTrack;
                                final isThisPlaylistPlaying = currentTrack !=
                                        null &&
                                    playlist.songs.any(
                                        (s) => s.trackId == currentTrack.id);
                                return GestureDetector(
                                  onTap: () {
                                    if (isThisPlaylistPlaying) {
                                      PlaybackService().togglePlayPause();
                                    } else {
                                      _playAll();
                                    }
                                  },
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFF514AED),
                                    ),
                                    child: Icon(
                                      isThisPlaylistPlaying &&
                                              playback.isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (_isOwner)
                            Positioned(
                              left: 20,
                              bottom: 20,
                              child: GestureDetector(
                                onTap: _editPlaylist,
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withValues(alpha: 0.4),
                                  ),
                                  child: const Icon(
                                    Icons.edit_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildActionButtons(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              if (playlist.songs.isEmpty)
                SliverToBoxAdapter(
                  child: _buildEmptySongsView(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: playlist.songs.length,
                          buildDefaultDragHandles: false,
                          proxyDecorator: (Widget child, int index,
                              Animation<double> animation) {
                            return AnimatedBuilder(
                              animation: animation,
                              builder: (BuildContext context, Widget? child) {
                                final animValue = Curves.easeOutCubic
                                    .transform(animation.value);
                                final elevation = animValue * 12.0;
                                final scale = 1.0 + (animValue * 0.035);
                                return Transform.scale(
                                  scale: scale,
                                  child: Material(
                                    elevation: elevation,
                                    color: const Color(0xFF242424),
                                    shadowColor: const Color(0xFF514AED)
                                        .withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(12),
                                    child: child,
                                  ),
                                );
                              },
                              child: child,
                            );
                          },
                          onReorder: (int oldIndex, int newIndex) {
                            if (oldIndex < newIndex) {
                              newIndex -= 1;
                            }
                            if (oldIndex != newIndex &&
                                oldIndex >= 0 &&
                                newIndex >= 0) {
                              _playlistService.reorderSongs(
                                  widget.playlistId, oldIndex, newIndex);
                            }
                          },
                          itemBuilder: (context, index) {
                            final song = playlist.songs[index];
                            return _buildSongItem(song, index,
                                key: ValueKey(song.trackId));
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 120),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ListenableBuilder(
              listenable: PlaybackService(),
              builder: (context, _) {
                final playback = PlaybackService();
                final show =
                    playback.isVisible && playback.currentTrack != null;
                if (show) return const MiniPlayer();
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollaboratorsHeader(UserPlaylist playlist) {
    final creatorName = _creatorProfile?['display_name'] ??
        _creatorProfile?['username'] ??
        (ProfileService().displayName.isNotEmpty
            ? ProfileService().displayName
            : 'Creator');
    final creatorAvatar =
        _creatorProfile?['avatar_url'] as String? ?? ProfileService().avatarUrl;

    const double avatarSize = 22.0;
    const double overlapOffset = -7.0;

    // Collect avatar URLs: creator first, then other collaborators
    final List<String?> memberAvatars = [creatorAvatar];
    for (final c in _collaborators) {
      final p = c['profiles'] as Map<String, dynamic>?;
      memberAvatars.add(p?['avatar_url'] as String?);
    }

    // Show up to 3 avatars in the stack (e.g. Creator + up to 2 collaborators)
    const int maxVisibleAvatars = 3;
    final int totalCount = memberAvatars.length;
    final int visibleCount =
        totalCount > maxVisibleAvatars ? maxVisibleAvatars : totalCount;
    final int remainingCount = totalCount - visibleCount;

    return GestureDetector(
      onTap: _showMembersSheet,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF514AED).withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Overlapping avatar bubbles stack
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < visibleCount; i++) ...[
                  Transform.translate(
                    offset: Offset(i * overlapOffset, 0),
                    child: Container(
                      width: avatarSize,
                      height: avatarSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF514AED),
                        border: Border.all(
                          color: const Color(0xFF191919),
                          width: 1.5,
                        ),
                      ),
                      child: ClipOval(
                        child: (memberAvatars[i] != null &&
                                memberAvatars[i]!.isNotEmpty)
                            ? CachedImage(
                                memberAvatars[i]!,
                                width: avatarSize,
                                height: avatarSize,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person,
                                  size: 13,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.person,
                                size: 13,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ],
                // Overflow badge (+N) if more collaborators exist
                if (remainingCount > 0)
                  Transform.translate(
                    offset: Offset(visibleCount * overlapOffset, 0),
                    child: Container(
                      height: avatarSize,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF514AED),
                        borderRadius: BorderRadius.circular(avatarSize / 2),
                        border: Border.all(
                          color: const Color(0xFF191919),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '+$remainingCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(
              width: 8 +
                  (visibleCount - 1) * overlapOffset +
                  (remainingCount > 0 ? overlapOffset : 0),
            ),
            Text(
              'Created by $creatorName',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarWidget(String? avatarUrl, {double radius = 20}) {
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF333333),
        ),
        child: Icon(Icons.person, color: Colors.white, size: radius),
      );
    }
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF333333),
      ),
      child: ClipOval(
        child: CachedImage(
          avatarUrl,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          placeholder: Container(
            width: radius * 2,
            height: radius * 2,
            color: const Color(0xFF333333),
            child: Icon(Icons.person, color: Colors.white54, size: radius),
          ),
          errorBuilder: (_, __, ___) => Container(
            width: radius * 2,
            height: radius * 2,
            color: const Color(0xFF333333),
            child: Icon(Icons.person, color: Colors.white, size: radius),
          ),
        ),
      ),
    );
  }

  void _showMembersSheet() {
    final playlist = _playlist;
    if (playlist == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF222222),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final currentUserId =
              Supabase.instance.client.auth.currentUser?.id ?? '';
          final creatorName = _creatorProfile?['display_name'] ??
              _creatorProfile?['username'] ??
              (ProfileService().displayName.isNotEmpty
                  ? ProfileService().displayName
                  : 'Creator');
          final creatorUsername =
              _creatorProfile?['username'] ?? ProfileService().username;
          final creatorAvatar = _creatorProfile?['avatar_url'] as String? ??
              ProfileService().avatarUrl;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Collaborators',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      if (_isOwner)
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            _openInviteCollaborators();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF514AED),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.person_add_alt_1_rounded,
                                    size: 14, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'Invite',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Poppins',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Creator Row
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      Navigator.pop(ctx);
                      final creatorId = playlist.userId;
                      if (creatorId == currentUserId) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProfileScreen(),
                          ),
                        );
                      } else if (creatorId.isNotEmpty) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserProfileScreen(
                              userId: creatorId,
                              initialDisplayName: creatorName,
                              initialUsername: creatorUsername,
                              initialAvatarUrl: creatorAvatar,
                            ),
                          ),
                        );
                      }
                    },
                    leading: _buildAvatarWidget(creatorAvatar, radius: 20),
                    title: Text(
                      creatorName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    subtitle: Text(
                      creatorUsername.isNotEmpty
                          ? '@$creatorUsername'
                          : 'Owner',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF514AED).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Creator',
                        style: TextStyle(
                          color: Color(0xFF817BFF),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  // Collaborators List
                  if (_collaborators.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'No other collaborators yet. Invite friends to add songs together!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    )
                  else
                    ..._collaborators.map((c) {
                      final p = c['profiles'] as Map<String, dynamic>?;
                      final memberName =
                          p?['display_name'] ?? p?['username'] ?? 'Friend';
                      final memberUsername = p?['username'] ?? '';
                      final memberAvatar = p?['avatar_url'] as String?;
                      final memberUserId = c['user_id']?.toString() ?? '';

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () {
                          Navigator.pop(ctx);
                          if (memberUserId == currentUserId) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProfileScreen(),
                              ),
                            );
                          } else if (memberUserId.isNotEmpty) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UserProfileScreen(
                                  userId: memberUserId,
                                  initialDisplayName: memberName,
                                  initialUsername: memberUsername,
                                  initialAvatarUrl: memberAvatar ?? '',
                                ),
                              ),
                            );
                          }
                        },
                        leading: _buildAvatarWidget(memberAvatar, radius: 20),
                        title: Text(
                          memberName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        subtitle: Text(
                          memberUsername.isNotEmpty
                              ? '@$memberUsername'
                              : 'Editor',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        trailing: _isOwner && memberUserId != currentUserId
                            ? IconButton(
                                icon: const Icon(Icons.remove_circle_outline,
                                    color: Color(0xFFFF4D4D), size: 20),
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  await _playlistService.removeCollaborator(
                                      playlist.id, memberUserId);
                                  _loadCollaboratorData();
                                },
                              )
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Editor',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Poppins',
                                  ),
                                ),
                              ),
                      );
                    }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(21),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius:
                      const BorderRadius.horizontal(left: Radius.circular(21)),
                  onTap: _openAddSongs,
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          size: 17,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Add Songs',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: 1,
              height: 18,
              color: Colors.white.withValues(alpha: 0.12),
            ),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: _isOwner
                      ? BorderRadius.zero
                      : const BorderRadius.horizontal(
                          right: Radius.circular(21)),
                  onTap: _shufflePlay,
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shuffle_rounded,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Shuffle',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_isOwner) ...[
              Container(
                width: 1,
                height: 18,
                color: Colors.white.withValues(alpha: 0.12),
              ),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(21)),
                    onTap: _openInviteCollaborators,
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_add_alt_1_rounded,
                              size: 15, color: Color(0xFF817BFF)),
                          const SizedBox(width: 6),
                          Text(
                            'Invite',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
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
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySongsView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Center(
        child: Column(
          children: [
            const SizedBox(height: 40),
            Icon(Icons.music_note,
                color: Colors.white.withValues(alpha: 0.3), size: 48),
            const SizedBox(height: 12),
            Text(
              'No songs yet',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _openAddSongs,
              child: const Text(
                'Tap Add to get started',
                style: TextStyle(
                  color: Color(0xFF514AED),
                  fontSize: 13,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getSongAddedByName(PlaylistSong song) {
    // 1. If song.addedByName is present and not generic 'Friend' / 'Member', use it!
    final name = song.addedByName.trim();
    if (name.isNotEmpty &&
        name.toLowerCase() != 'friend' &&
        name.toLowerCase() != 'member') {
      return name;
    }

    // 2. Check creator profile
    final addedId = song.addedById.trim();
    if (addedId.isNotEmpty) {
      if (_creatorProfile != null && _creatorProfile!['id'] == addedId) {
        final cName = (_creatorProfile!['display_name'] ??
                _creatorProfile!['username'] ??
                '')
            .toString()
            .trim();
        if (cName.isNotEmpty) return cName;
      }

      // 3. Check collaborators profiles
      for (final c in _collaborators) {
        final p = c['profiles'] as Map<String, dynamic>?;
        if (c['user_id'] == addedId || (p != null && p['id'] == addedId)) {
          final mName =
              (p?['display_name'] ?? p?['username'] ?? '').toString().trim();
          if (mName.isNotEmpty && mName.toLowerCase() != 'friend') return mName;
        }
      }
    }

    // 4. If added by current user
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (addedId == currentUserId || addedId.isEmpty) {
      final prof = ProfileService();
      if (prof.displayName.trim().isNotEmpty) return prof.displayName.trim();
      if (prof.username.trim().isNotEmpty) return prof.username.trim();
    }

    // 5. Fallback to existing name or empty
    return (name.isNotEmpty && name.toLowerCase() != 'friend') ? name : '';
  }

  Widget _buildSongItem(PlaylistSong song, int index, {required Key key}) {
    final playlist = _playlist;
    final addedByName = _getSongAddedByName(song);
    final isLast = index == (playlist?.songs.length ?? 0) - 1;

    return Container(
      key: key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TrackHighlight(
            trackId: song.trackId,
            title: song.title,
            artist: song.artist,
            builder: (context, isCurrent) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _playTrack(index),
                  onLongPress: () {
                    final searchResult = SearchResult(
                      type: 'song',
                      id: song.trackId,
                      title: song.title,
                      artist: song.artist,
                      artistId: song.artistId,
                      artistImage: song.artistImage,
                      image: song.image,
                      duration: song.duration,
                      nbFan: 0,
                      previewUrl: '',
                    );
                    SongOptionsModal.show(context, searchResult);
                  },
                  splashColor: Colors.white.withValues(alpha: 0.08),
                  highlightColor: Colors.white.withValues(alpha: 0.04),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: isCurrent
                              ? NowPlayingBars(
                                  playing: PlaybackService().isPlaying)
                              : Text(
                                  '${index + 1}',
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
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 44,
                            height: 44,
                            color: const Color(0xFF2A2A2A),
                            child: song.image.isNotEmpty
                                ? CachedImage(
                                    song.image,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(Icons.music_note,
                                          color: Colors.white38, size: 20),
                                    ),
                                  )
                                : const Center(
                                    child: Icon(Icons.music_note,
                                        color: Colors.white38, size: 20),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      song.title,
                                      style: TextStyle(
                                        color: isCurrent
                                            ? const Color(0xFF514AED)
                                            : Colors.white,
                                        fontSize: 13.5,
                                        fontWeight: isCurrent
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        fontFamily: 'Poppins',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (DownloadService.isDownloaded(
                                      song.trackId)) ...[
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.check_circle,
                                      color: Color(0xFF514AED),
                                      size: 14,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      song.artist,
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.45),
                                        fontSize: 11.5,
                                        fontFamily: 'Poppins',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if ((playlist?.isCollaborative ?? false) &&
                                      addedByName.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '• $addedByName',
                                      style: TextStyle(
                                        color: const Color(0xFF817BFF)
                                            .withValues(alpha: 0.8),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'Poppins',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _playlistService.removeSong(
                                widget.playlistId, song.trackId);
                            CookieService.show(
                              message:
                                  'Removed from "${playlist?.name ?? 'playlist'}"',
                              icon: Icons.remove_circle_outline_rounded,
                              iconColor: Colors.white70,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.remove_circle_outline_rounded,
                              color: Colors.white.withValues(alpha: 0.35),
                              size: 20,
                            ),
                          ),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.only(
                                left: 4, right: 6, top: 6, bottom: 6),
                            child: Icon(
                              Icons.drag_handle_rounded,
                              color: Colors.white.withValues(alpha: 0.35),
                              size: 21,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          if (!isLast)
            Divider(
              height: 1,
              thickness: 1,
              color: Colors.white.withValues(alpha: 0.04),
              indent: 96,
              endIndent: 16,
            ),
        ],
      ),
    );
  }
}
