import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/playlist_service.dart';
import '../../services/playback_service.dart';
import '../../services/cookie_service.dart';
import '../../widgets/now_playing_badge.dart';
import '../search_screen/mini_player.dart';
import 'playlist_detail_screen.dart';
import 'create_playlist_dialog.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  final PlaylistService _playlistService = PlaylistService();
  final Set<String> _selectedPlaylistIds = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _playlistService.loadPlaylists(forceRefresh: true);
    _playlistService.addListener(_onUpdate);
    _playlistService.onUpdate.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _playlistService.removeListener(_onUpdate);
    _playlistService.onUpdate.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  void _enterSelectionMode(String initialPlaylistId) {
    HapticFeedback.mediumImpact();
    setState(() {
      _isSelectionMode = true;
      _selectedPlaylistIds.add(initialPlaylistId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedPlaylistIds.clear();
    });
  }

  void _toggleSelection(String playlistId) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedPlaylistIds.contains(playlistId)) {
        _selectedPlaylistIds.remove(playlistId);
        if (_selectedPlaylistIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedPlaylistIds.add(playlistId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      final allIds = _playlistService.playlists.map((p) => p.id).toSet();
      if (_selectedPlaylistIds.length == allIds.length) {
        _selectedPlaylistIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedPlaylistIds.addAll(allIds);
      }
    });
  }

  void _createPlaylist() {
    CreatePlaylistBottomSheet.show(
      context: context,
      onCreated: (name, coverImage, isPublic) async {
        final playlist = await _playlistService.createPlaylist(name,
            coverImage: coverImage, isPublic: isPublic);
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
            ),
          );
        }
      },
    );
  }

  void _confirmDeleteSelected() {
    if (_selectedPlaylistIds.isEmpty) return;

    final count = _selectedPlaylistIds.length;
    final isSingle = count == 1;
    final firstPlaylist = isSingle
        ? _playlistService.playlists
            .where((p) => p.id == _selectedPlaylistIds.first)
            .firstOrNull
        : null;

    final title = isSingle && firstPlaylist != null
        ? 'Delete "${firstPlaylist.name}"?'
        : 'Delete $count playlists?';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This action cannot be undone. All songs in the selected ${isSingle ? "playlist" : "playlists"} will be removed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.of(ctx).pop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        final idsToDelete =
                            Set<String>.from(_selectedPlaylistIds);
                        _exitSelectionMode();

                        for (final id in idsToDelete) {
                          await _playlistService.deletePlaylist(id);
                        }

                        CookieService.show(
                          message: isSingle
                              ? 'Playlist deleted'
                              : 'Deleted $count playlists',
                          icon: Icons.delete_outline_rounded,
                          iconColor: Colors.white70,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE53935)
                                  .withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Delete',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
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
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final playlists = _playlistService.playlists;

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF191919),
        body: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, topPadding + 16, 20, 0),
                    child: _isSelectionMode
                        ? _buildSelectionHeader(playlists.length)
                        : _buildNormalHeader(),
                  ),
                ),
                if (playlists.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.queue_music,
                              color: Colors.white.withValues(alpha: 0.3),
                              size: 64),
                          const SizedBox(height: 16),
                          Text(
                            'No playlists yet',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 16,
                              fontFamily: 'Poppins',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap + New to create one',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 13,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      24,
                      20,
                      _isSelectionMode ? 120 : 100,
                    ),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.82,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final playlist = playlists[index];
                          return _buildPlaylistCard(playlist);
                        },
                        childCount: playlists.length,
                      ),
                    ),
                  ),
              ],
            ),
            if (_isSelectionMode)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomActionBar(),
              )
            else
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MiniPlayer(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNormalHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
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
        const Text(
          'Playlists',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
        ),
        GestureDetector(
          onTap: _createPlaylist,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF514AED),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text(
                  'New',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionHeader(int totalPlaylists) {
    final count = _selectedPlaylistIds.length;
    final isAllSelected = count == totalPlaylists && totalPlaylists > 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: _exitSelectionMode,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.3),
            ),
            child: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
        Text(
          '$count selected',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
        ),
        GestureDetector(
          onTap: _selectAll,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isAllSelected
                  ? const Color(0xFF514AED)
                  : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isAllSelected ? 'Deselect All' : 'Select All',
              style: TextStyle(
                color: isAllSelected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionBar() {
    final count = _selectedPlaylistIds.length;
    final hasSelection = count > 0;

    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        10,
        24,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF191919).withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Cancel button
          GestureDetector(
            onTap: _exitSelectionMode,
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(19),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: const Center(
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ),
          ),
          // Delete button
          GestureDetector(
            onTap: hasSelection ? _confirmDeleteSelected : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                color: hasSelection
                    ? const Color(0xFFE53935)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(19),
                boxShadow: hasSelection
                    ? [
                        BoxShadow(
                          color:
                              const Color(0xFFE53935).withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    color: hasSelection ? Colors.white : Colors.white24,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    hasSelection ? 'Delete ($count)' : 'Delete',
                    style: TextStyle(
                      color: hasSelection ? Colors.white : Colors.white24,
                      fontSize: 13,
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

  Widget _buildPlaylistCard(UserPlaylist playlist) {
    final coverProvider = playlist.effectiveCoverProvider;
    final hasCover = coverProvider != null;
    final isSelected = _selectedPlaylistIds.contains(playlist.id);

    return ListenableBuilder(
      listenable: PlaybackService(),
      builder: (context, _) {
        final playback = PlaybackService();
        final isPlayingThis = playback.currentPlaylistId == playlist.id;

        return GestureDetector(
          onTap: () {
            if (_isSelectionMode) {
              _toggleSelection(playlist.id);
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
                ),
              );
            }
          },
          onLongPress: () {
            if (!_isSelectionMode) {
              _enterSelectionMode(playlist.id);
            } else {
              _toggleSelection(playlist.id);
            }
          },
          child: AnimatedScale(
            scale: _isSelectionMode && isSelected ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: hasCover ? null : const Color(0xFF514AED),
                      border: Border.all(
                        color: _isSelectionMode
                            ? (isSelected
                                ? const Color(0xFF514AED)
                                : Colors.white.withValues(alpha: 0.1))
                            : (isPlayingThis
                                ? const Color(0xFF514AED)
                                : Colors.white.withValues(alpha: 0.08)),
                        width: isSelected ? 2.5 : (isPlayingThis ? 2 : 1),
                      ),
                      image: coverProvider != null
                          ? DecorationImage(
                              image: coverProvider,
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: Stack(
                      children: [
                        if (!hasCover)
                          Center(
                            child: Icon(
                              Icons.queue_music,
                              color: Colors.white.withValues(alpha: 0.5),
                              size: 40,
                            ),
                          ),
                        if (_isSelectionMode)
                          Positioned.fill(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: isSelected
                                    ? const Color(0xFF514AED)
                                        .withValues(alpha: 0.28)
                                    : Colors.black.withValues(alpha: 0.25),
                              ),
                            ),
                          ),
                        if (_isSelectionMode)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? const Color(0xFF514AED)
                                    : Colors.black.withValues(alpha: 0.5),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF514AED)
                                      : Colors.white70,
                                  width: 2,
                                ),
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    )
                                  : null,
                            ),
                          ),
                        if (!_isSelectionMode && isPlayingThis)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF514AED)
                                    .withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: NowPlayingBars(
                                playing: playback.isPlaying,
                                color: Colors.white,
                                barWidth: 2,
                                bars: 3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  playlist.name,
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFF817BFF)
                        : (isPlayingThis
                            ? const Color(0xFF817BFF)
                            : Colors.white),
                    fontSize: 14,
                    fontWeight: isSelected || isPlayingThis
                        ? FontWeight.bold
                        : FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${playlist.songs.length} songs',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
