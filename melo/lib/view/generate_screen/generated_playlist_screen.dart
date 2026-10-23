import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/search_service.dart';
import '../../services/playback_service.dart';
import '../../services/youtube_service.dart';
import '../../services/playlist_service.dart';
import '../../services/download_service.dart';
import '../../services/premium_service.dart';
import '../../services/background_prefetch_service.dart';
import '../../services/share_service.dart';
import '../../services/cookie_service.dart';
import '../../services/generated_history_service.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/now_playing_badge.dart';
import '../search_screen/mini_player.dart';

class GeneratedPlaylistScreen extends StatefulWidget {
  final String mood;
  final String title;
  final String description;
  final List<Map<String, dynamic>> songs;
  final bool streamsAlreadyPrefetching;
  final String? historyId;
  final String? savedPlaylistId;

  const GeneratedPlaylistScreen({
    super.key,
    required this.mood,
    this.title = '',
    this.description = '',
    required this.songs,
    this.streamsAlreadyPrefetching = false,
    this.historyId,
    this.savedPlaylistId,
  });

  @override
  State<GeneratedPlaylistScreen> createState() =>
      _GeneratedPlaylistScreenState();
}

class _GeneratedPlaylistScreenState extends State<GeneratedPlaylistScreen> {
  late List<Map<String, dynamic>> _songs;
  late String _title;
  String? _customCoverPath;
  bool _saved = false;
  bool _saving = false;

  final ImagePicker _picker = ImagePicker();
  static const Color _accent = Color(0xFF514AED);

  @override
  void initState() {
    super.initState();
    _savedPlaylistId = widget.savedPlaylistId;
    _saved = _savedPlaylistId != null && _savedPlaylistId!.isNotEmpty;
    _songs = List.of(widget.songs);
    _title =
        widget.title.isNotEmpty ? widget.title : '\u2018${widget.mood}\u2019';
    if (!widget.streamsAlreadyPrefetching) {
      _prefetchTracks();
    }
  }

  void _prefetchTracks() {
    final tracks = _songs
        .map((t) => SearchResult(
              type: 'song',
              id: t['deezerId']?.toString() ?? '',
              title: t['title']?.toString() ?? '',
              artist: t['artist']?.toString() ?? '',
              artistId: t['artistId']?.toString() ?? '',
              artistImage: t['artistImage']?.toString() ?? '',
              image: t['image']?.toString() ?? '',
              duration: t['duration']?.toString() ?? '',
              nbFan: 0,
              previewUrl: t['previewUrl']?.toString() ?? '',
            ))
        .toList();
    if (tracks.isNotEmpty) {
      YouTubeService.prefetchStreamUrls(tracks);
      BackgroundPrefetchService.instance
          .enqueueTracks(tracks, tag: 'generated_playlist');
    }
  }

  void _playTrack(int index) {
    if (index >= _songs.length) return;

    final queue = _songs
        .map((t) => SearchResult(
              type: 'song',
              id: (t['deezerId']?.toString() ?? '').isNotEmpty
                  ? t['deezerId'].toString()
                  : _songs.indexOf(t).toString(),
              title: t['title']?.toString() ?? '',
              artist: t['artist']?.toString() ?? '',
              artistId: t['artistId']?.toString() ?? '',
              artistImage: t['artistImage']?.toString() ?? '',
              image: t['image']?.toString() ?? '',
              duration: t['duration']?.toString() ?? '',
              nbFan: 0,
              previewUrl: t['previewUrl']?.toString() ?? '',
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
        type: 'generated',
        id: widget.mood,
        title: _title,
        coverImage: _customCoverPath,
        extra: {'songs': _songs, 'mood': widget.mood},
      ),
    );
    playback.playTrack(queue[index], fromQueue: true);
  }

  void _playAll() {
    if (_songs.isEmpty) return;
    _playTrack(0);
  }

  void _shufflePlay() {
    if (_songs.isEmpty) return;
    final shuffled = List<Map<String, dynamic>>.from(_songs)..shuffle();
    final queue = shuffled
        .map((t) => SearchResult(
              type: 'song',
              id: (t['deezerId']?.toString() ?? '').isNotEmpty
                  ? t['deezerId'].toString()
                  : _songs.indexOf(t).toString(),
              title: t['title']?.toString() ?? '',
              artist: t['artist']?.toString() ?? '',
              artistId: t['artistId']?.toString() ?? '',
              artistImage: t['artistImage']?.toString() ?? '',
              image: t['image']?.toString() ?? '',
              duration: t['duration']?.toString() ?? '',
              nbFan: 0,
              previewUrl: t['previewUrl']?.toString() ?? '',
            ))
        .toList();
    final playback = PlaybackService();
    playback.setQueue(
      queue,
      0,
      context: PlaybackContext(
        type: 'generated',
        id: widget.mood,
        title: _title,
        coverImage: _customCoverPath,
        extra: {'songs': _songs, 'mood': widget.mood},
      ),
    );
    playback.playTrack(queue.first, fromQueue: true);
  }

  void _editPlaylist() {
    final nameController = TextEditingController(text: _title);
    String? coverPath = _customCoverPath ??
        (_songs.isNotEmpty ? _songs.first['image']?.toString() : null);
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
                              borderRadius: BorderRadius.circular(2))),
                      const SizedBox(height: 16),
                      const Text('Change cover image',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Poppins')),
                      const SizedBox(height: 16),
                      ListTile(
                          leading: const Icon(Icons.camera_alt,
                              color: Color(0xFF514AED)),
                          title: const Text('Camera',
                              style: TextStyle(
                                  color: Colors.white, fontFamily: 'Poppins')),
                          onTap: () =>
                              Navigator.of(menuCtx).pop(ImageSource.camera)),
                      ListTile(
                          leading: const Icon(Icons.photo_library,
                              color: Color(0xFF514AED)),
                          title: const Text('Gallery',
                              style: TextStyle(
                                  color: Colors.white, fontFamily: 'Poppins')),
                          onTap: () =>
                              Navigator.of(menuCtx).pop(ImageSource.gallery)),
                    ],
                  ),
                ),
              ),
            );
            if (source == null) return;
            final image = await _picker.pickImage(
                source: source,
                maxWidth: 1024,
                maxHeight: 1024,
                imageQuality: 85);
            if (image == null) return;
            try {
              final cropped = await ImageCropper().cropImage(
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
                      lockAspectRatio: true),
                  IOSUiSettings(
                      title: 'Crop Cover',
                      aspectRatioLockEnabled: true,
                      resetAspectRatioEnabled: false),
                ],
              );
              if (cropped != null) {
                setSheetState(() => coverPath = cropped.path);
              }
            } catch (_) {
              setSheetState(() => coverPath = image.path);
            }
          }

          void save() {
            final newName = nameController.text.trim();
            if (newName.isEmpty) {
              setSheetState(() => error = 'Playlist name cannot be empty');
              return;
            }
            setSheetState(() => isSaving = true);
            setState(() {
              _title = newName;
              _customCoverPath = coverPath;
            });
            Navigator.of(ctx).pop();
          }

          return Container(
            padding: EdgeInsets.only(
                left: 20, right: 20, top: 20, bottom: 24 + bottomInset),
            decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 18),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Edit Playlist',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Poppins')),
                        GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.close,
                                    color: Colors.white70, size: 18))),
                      ]),
                  const SizedBox(height: 24),
                  Center(
                      child: Stack(children: [
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
                                        image: coverProvider, fit: BoxFit.cover)
                                    : null,
                                border: Border.all(
                                    color: coverProvider == null
                                        ? const Color(0xFF514AED)
                                            .withValues(alpha: 0.3)
                                        : Colors.transparent,
                                    width: 2),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.4),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4))
                                ]),
                            child: coverProvider == null
                                ? const Center(
                                    child: Icon(Icons.queue_music_rounded,
                                        size: 48, color: Color(0xFF817BFF)))
                                : null)),
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
                                        color: const Color(0xFF1E1E1E),
                                        width: 3)),
                                child: const Icon(Icons.camera_alt,
                                    color: Colors.white, size: 16)))),
                  ])),
                  const SizedBox(height: 8),
                  Center(
                      child: Text(
                          coverPath != null && coverPath!.isNotEmpty
                              ? 'Change Cover'
                              : 'Add Cover Image',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                              fontFamily: 'Poppins'))),
                  const SizedBox(height: 24),
                  const Text('Playlist Name',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: nameController,
                      style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Poppins',
                          fontSize: 15),
                      decoration: InputDecoration(
                          hintText: 'Enter playlist title...',
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontFamily: 'Poppins',
                              fontSize: 14),
                          filled: true,
                          fillColor: const Color(0xFF2A2A2A),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: Color(0xFF514AED), width: 1.5))),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => save()),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!,
                        style: const TextStyle(
                            color: Color(0xFFFF4D4D),
                            fontSize: 12,
                            fontFamily: 'Poppins'))
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
                                  borderRadius: BorderRadius.circular(14))),
                          child: isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5))
                              : const Text('Save Changes',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Poppins')))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openAddSongsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddSongsModal(
        onSongSelected: (song) {
          final songMap = {
            'title': song.title,
            'artist': song.artist,
            'artistId': song.artistId,
            'artistImage': song.artistImage,
            'image': song.image,
            'duration': song.duration,
            'deezerId': song.id,
            'previewUrl': song.previewUrl,
            'source': 'manual_add',
          };
          setState(() {
            _songs.add(songMap);
          });
          _prefetchTracks();
          CookieService.show(
            message: 'Added "${song.title}" to playlist',
            icon: Icons.playlist_add_check_rounded,
            iconColor: const Color(0xFF8A82FF),
          );
        },
      ),
    );
  }

  String? _savedPlaylistId;

  Future<void> _addToLibrary() async {
    if (_saved) {
      CookieService.show(
        message: 'Playlist already in your library',
        icon: Icons.info_outline_rounded,
        iconColor: Colors.white70,
      );
      return;
    }
    if (_saving) return;

    // Optimistic instant feedback
    setState(() {
      _saved = true;
      _saving = true;
    });

    CookieService.show(
      message: 'Added to your library',
      icon: Icons.library_add_check_rounded,
      iconColor: const Color(0xFF8A82FF),
    );

    try {
      final service = PlaylistService();
      final firstCover =
          _songs.isNotEmpty ? _songs.first['image']?.toString() : null;

      final coverToSave = _customCoverPath ??
          ((firstCover != null && firstCover.isNotEmpty) ? firstCover : null);

      final playlist = await service.createPlaylist(
        _title.isNotEmpty ? _title : 'Generated: ${widget.mood}',
        coverImage: coverToSave,
      );

      _savedPlaylistId = playlist.id;

      final songsToAdd = _songs
          .map((song) => PlaylistSong(
                trackId: song['deezerId']?.toString() ??
                    song['title']?.toString() ??
                    '',
                title: song['title']?.toString() ?? '',
                artist: song['artist']?.toString() ?? '',
                image: song['image']?.toString() ?? '',
                duration: song['duration']?.toString() ?? '',
                artistId: song['artistId']?.toString() ?? '',
                artistImage: song['artistImage']?.toString() ?? '',
              ))
          .toList();

      await service.addSongs(playlist.id, songsToAdd);
      if (widget.historyId != null) {
        await GeneratedHistoryService.markPlaylistSaved(
            widget.historyId!, playlist.id);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saved = false);
        CookieService.show(
          message: 'Could not save playlist',
          icon: Icons.error_outline_rounded,
          iconColor: Colors.redAccent,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _share() {
    if (_savedPlaylistId != null) {
      ShareService.sharePlaylist(
        playlistId: _savedPlaylistId!,
        title: _title,
      );
    } else {
      final text =
          '$_title — ${_songs.length} songs on Melo\n${ShareService.baseUrl}';
      ShareService.shareText(
        text: text,
        subject: _title,
      );
    }
  }

  void _downloadAllSongs() {
    if (!PremiumService().canDownloadOffline) {
      PremiumService.showUpsell(context, feature: 'Offline Music Downloads');
      return;
    }
    if (_songs.isEmpty) return;
    final pending = _songs.where((s) {
      final id = s['deezerId']?.toString() ?? s['title']?.toString() ?? '';
      return !DownloadService.isDownloaded(id);
    }).toList();

    if (pending.isEmpty) {
      CookieService.show(
        message: 'All songs are already downloaded',
        icon: Icons.check_circle_rounded,
        iconColor: const Color(0xFF514AED),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Downloading ${pending.length} songs in background'),
      backgroundColor: const Color(0xFF2A2A2A),
    ));

    () async {
      for (final song in pending) {
        final id =
            song['deezerId']?.toString() ?? song['title']?.toString() ?? '';
        if (!DownloadService.isDownloaded(id)) {
          await DownloadService.download(
            trackId: id,
            title: song['title']?.toString() ?? '',
            artist: song['artist']?.toString() ?? '',
            image: song['image']?.toString() ?? '',
            artistId: song['artistId']?.toString() ?? '',
            artistImage: song['artistImage']?.toString() ?? '',
          );
        }
      }
    }();
  }

  void _showPlaylistMenu() {
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
              if (_saved) ...[
                ListTile(
                  leading: const Icon(Icons.share_outlined,
                      color: Color(0xFF514AED)),
                  title: const Text(
                    'Share playlist',
                    style:
                        TextStyle(color: Colors.white, fontFamily: 'Poppins'),
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
                    _share();
                  },
                ),
                const Divider(color: Colors.white12, height: 1),
              ],
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
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading:
                    const Icon(Icons.edit_rounded, color: Color(0xFF514AED)),
                title: const Text(
                  'Edit playlist',
                  style: TextStyle(color: Colors.white, fontFamily: 'Poppins'),
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
            ],
          ),
        ),
      ),
    );
  }

  void _handleBack() {
    if (_saved) {
      Navigator.of(context).pop();
      return;
    }
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (dialogContext) => Dialog(
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
                'Unsaved Playlist',
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
                'This playlist has not been saved. Add it to your library to keep it for later?',
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
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          Navigator.of(context).pop();
                        },
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        child: Text(
                          'Discard',
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
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _addToLibrary().then((_) {
                            if (mounted) Navigator.of(context).pop();
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        child: const Text(
                          'Save Playlist',
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

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final imageHeight = screenSize.width;

    return Scaffold(
      backgroundColor: const Color(0xFF191919),
      body: Stack(
        children: [
          CustomScrollView(
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
                          if (_customCoverPath != null)
                            Image.file(
                              File(_customCoverPath!),
                              fit: BoxFit.cover,
                            )
                          else if (_songs.isNotEmpty &&
                              (_songs.first['image'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                            CachedImage(
                              _songs.first['image'].toString(),
                              fit: BoxFit.cover,
                            )
                          else
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF514AED),
                                    Color(0xFF7C4DFF)
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
                                  Colors.black.withValues(alpha: 0.35),
                                  Colors.black.withValues(alpha: 0.2),
                                  Colors.black.withValues(alpha: 0.6),
                                  const Color(0xFF191919),
                                ],
                                stops: const [0.0, 0.3, 0.75, 1.0],
                              ),
                            ),
                          ),
                          Positioned(
                            top: topPadding + 12,
                            left: 16,
                            child: GestureDetector(
                              onTap: _handleBack,
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
                                if (_saved) ...[
                                  GestureDetector(
                                    onTap: _share,
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
                                ],
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
                            right: 20,
                            bottom: 80,
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
                                    '${_songs.length} SONGS',
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
                                  _title,
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
                              ],
                            ),
                          ),
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
                          Positioned(
                            right: 20,
                            bottom: 20,
                            child: ListenableBuilder(
                              listenable: PlaybackService(),
                              builder: (context, _) {
                                final playback = PlaybackService();
                                final currentTrack = playback.currentTrack;
                                final isThisPlaylistPlaying =
                                    currentTrack != null &&
                                        _songs.any((t) =>
                                            t['title']?.toString() ==
                                            currentTrack.title);
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
                                      color: _accent,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Color(0x66514AED),
                                          blurRadius: 16,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildActionButtons(),
                    const SizedBox(height: 14),
                    _buildSongsHeader(),
                    const SizedBox(height: 14),
                    _buildSongsSection(),
                    const SizedBox(height: 100),
                  ],
                ),
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
                  onTap: _addToLibrary,
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _saved
                              ? Icons.check_rounded
                              : Icons.bookmark_add_rounded,
                          color: _saved
                              ? const Color(0xFF514AED)
                              : Colors.white.withValues(alpha: 0.85),
                          size: 16,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _saved ? 'In Library' : 'Add to Library',
                          style: TextStyle(
                            color: _saved
                                ? const Color(0xFF514AED)
                                : Colors.white.withValues(alpha: 0.85),
                            fontSize: 12.5,
                            fontWeight:
                                _saved ? FontWeight.w600 : FontWeight.w500,
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
                  borderRadius:
                      const BorderRadius.horizontal(right: Radius.circular(21)),
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
          ],
        ),
      ),
    );
  }

  Widget _buildSongsHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Songs',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFamily: 'Poppins',
            ),
          ),
          GestureDetector(
            onTap: _openAddSongsSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _accent.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: _accent, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'Add Songs',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_songs.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Column(
                  children: [
                    const Text(
                      'No tracks in this playlist',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 14,
                          fontFamily: 'Poppins'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _openAddSongsSheet,
                      icon: const Icon(Icons.add_rounded, color: Colors.white),
                      label: const Text('Add Songs',
                          style: TextStyle(
                              color: Colors.white, fontFamily: 'Poppins')),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _songs.length,
                  buildDefaultDragHandles: false,
                  proxyDecorator:
                      (Widget child, int index, Animation<double> animation) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (BuildContext context, Widget? child) {
                        final animValue =
                            Curves.easeOutCubic.transform(animation.value);
                        final elevation = animValue * 12.0;
                        final scale = 1.0 + (animValue * 0.035);
                        return Transform.scale(
                          scale: scale,
                          child: Material(
                            elevation: elevation,
                            color: const Color(0xFF242424),
                            shadowColor:
                                const Color(0xFF514AED).withValues(alpha: 0.45),
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
                      setState(() {
                        final item = _songs.removeAt(oldIndex);
                        _songs.insert(newIndex, item);
                      });
                    }
                  },
                  itemBuilder: (context, index) => _buildTrackItem(index),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTrackItem(int index) {
    final track = _songs[index];
    final title = track['title']?.toString() ?? '';
    final artist = track['artist']?.toString() ?? '';
    final image = track['image']?.toString() ?? '';
    final trackId = track['deezerId']?.toString() ??
        '${track['title']}_${track['artist']}_$index';
    final isLast = index == _songs.length - 1;

    return Dismissible(
      key: ValueKey('dismiss_${trackId}_$index'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        setState(() {
          _songs.removeAt(index);
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Removed "$title"'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF262626),
        ));
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.8),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.white, size: 22),
      ),
      child: Container(
        key: ValueKey('item_${trackId}_$index'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TrackHighlight(
              trackId: trackId,
              title: title,
              artist: artist,
              builder: (context, isCurrent) {
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _playTrack(index),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
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
                                      color:
                                          Colors.white.withValues(alpha: 0.5),
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
                              child: image.isNotEmpty
                                  ? CachedImage(
                                      image,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Center(
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
                                Text(
                                  title,
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
                          const SizedBox(width: 4),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              setState(() {
                                _songs.removeAt(index);
                              });
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text('Removed "$title"'),
                                duration: const Duration(seconds: 2),
                                backgroundColor: const Color(0xFF262626),
                              ));
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
      ),
    );
  }
}

class _AddSongsModal extends StatefulWidget {
  final ValueChanged<SearchResult> onSongSelected;

  const _AddSongsModal({required this.onSongSelected});

  @override
  State<_AddSongsModal> createState() => _AddSongsModalState();
}

class _AddSongsModalState extends State<_AddSongsModal> {
  final TextEditingController _searchController = TextEditingController();
  List<SearchResult> _results = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  Future<void> _loadTrending() async {
    setState(() => _searching = true);
    try {
      final results = await SearchService.search('Trending Hits');
      if (mounted) {
        setState(() {
          _results = results.where((r) => r.type == 'song').toList();
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _performSearch(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      _loadTrending();
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await SearchService.search(query);
      if (mounted) {
        setState(() {
          _results = results.where((r) => r.type == 'song').toList();
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.85;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF141419),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1.0,
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 16, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Add Songs',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                        textScaler: TextScaler.noScaling,
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: _searchController,
                  onSubmitted: _performSearch,
                  textAlignVertical: TextAlignVertical.center,
                  strutStyle: const StrutStyle(
                    fontFamily: 'Poppins',
                    fontFamilyFallback: [
                      'Kantumruy Pro',
                      'Battambang',
                      'Noto Sans Khmer',
                      'Khmer OS Siemreap',
                      'Khmer OS',
                      'sans-serif',
                    ],
                    fontSize: 14,
                    height: 1.35,
                    forceStrutHeight: false,
                  ),
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
                    hintText: 'Search songs or artists...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
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
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: Colors.white.withValues(alpha: 0.45),
                      size: 20,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              _loadTrending();
                            },
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.white.withValues(alpha: 0.5),
                              size: 18,
                            ),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_searching)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                    color: Colors.white70,
                    strokeWidth: 2.5,
                  ),
                ),
              )
            else if (_results.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.music_off_rounded,
                        color: Colors.white.withValues(alpha: 0.2),
                        size: 40,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No songs found',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 14,
                          fontFamily: 'Poppins',
                        ),
                        textScaler: TextScaler.noScaling,
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemBuilder: (ctx, idx) {
                    final song = _results[idx];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () => widget.onSongSelected(song),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    color: Colors.white.withValues(alpha: 0.06),
                                    child: song.image.isNotEmpty
                                        ? CachedImage(
                                            song.image,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(
                                              Icons.music_note,
                                              color: Colors.white38,
                                              size: 20,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.music_note,
                                            color: Colors.white38,
                                            size: 20,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        song.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: 'Poppins',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textScaler: TextScaler.noScaling,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        song.artist,
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.5),
                                          fontSize: 12,
                                          fontFamily: 'Poppins',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textScaler: TextScaler.noScaling,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(alpha: 0.08),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.add_rounded,
                                    color: Colors.white70,
                                    size: 17,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
