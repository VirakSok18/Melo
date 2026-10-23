import '../../widgets/cached_image.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/playlist_service.dart';
import '../../services/search_service.dart';
import '../../services/recent_search_service.dart';
import '../../services/cookie_service.dart';
import '../../widgets/skeleton_loader.dart';

class AddSongsBottomSheet extends StatefulWidget {
  final String playlistId;

  const AddSongsBottomSheet({super.key, required this.playlistId});

  @override
  State<AddSongsBottomSheet> createState() => _AddSongsBottomSheetState();
}

class _AddSongsBottomSheetState extends State<AddSongsBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final PlaylistService _playlistService = PlaylistService();
  List<SearchResult> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  List<SearchResult> _recentItems = [];
  bool _showAllRecent = false;
  Timer? _debounceTimer;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadRecentItems();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _debounceTimer?.cancel();
    if (query.isNotEmpty) {
      _debounceTimer = Timer(const Duration(milliseconds: 400), () {
        _performSearch(query);
      });
    } else {
      ++_searchGeneration;
      setState(() {
        _results = [];
        _hasSearched = false;
        _isSearching = false;
      });
    }
  }

  Future<void> _loadRecentItems() async {
    final items = await RecentSearchService.getRecentSearches();
    if (mounted) {
      setState(() => _recentItems = items);
    }
  }

  Future<void> _performSearch(String query) async {
    final gen = ++_searchGeneration;
    setState(() => _isSearching = true);
    final results = await SearchService.search(query);
    if (mounted && gen == _searchGeneration) {
      setState(() {
        _results = results;
        _isSearching = false;
        _hasSearched = true;
      });
    }
  }

  void _onRecentItemTap(SearchResult item) {
    _searchController.text = item.title;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: item.title.length),
    );
  }

  void _addSong(SearchResult song) {
    final playlistSong = PlaylistSong(
      trackId: song.id,
      title: song.title,
      artist: song.artist,
      image: song.image,
      duration: song.duration,
      artistId: song.artistId,
      artistImage: song.artistImage,
    );
    _playlistService.addSong(widget.playlistId, playlistSong);
    CookieService.show(
      message: 'Added "${song.title}" to playlist',
      icon: Icons.playlist_add_check_rounded,
      iconColor: const Color(0xFF8A82FF),
    );
    setState(() {});
  }

  bool _isAdded(String trackId) {
    return _playlistService.hasSong(widget.playlistId, trackId);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.88;

    return Container(
      height: maxHeight,
      padding: EdgeInsets.only(bottom: bottomInset),
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
            // Drag handle & top header
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

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _focusNode,
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
                              setState(() {
                                _results = [];
                                _hasSearched = false;
                                _isSearching = false;
                              });
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

            // Body: Search Results or Recent Section
            Expanded(
              child: _isSearching
                  ? ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: 5,
                      itemBuilder: (_, __) => const SkeletonSearchResult(),
                    )
                  : !_hasSearched
                      ? _buildRecentSection()
                      : _results.isEmpty
                          ? Center(
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
                                    'No results found',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.45),
                                      fontSize: 14,
                                      fontFamily: 'Poppins',
                                    ),
                                    textScaler: TextScaler.noScaling,
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                              itemCount: _results.length,
                              itemBuilder: (context, index) {
                                final song = _results[index];
                                final added = _isAdded(song.id);
                                return _buildSearchResultItem(song, added);
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSection() {
    if (_recentItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              color: Colors.white.withValues(alpha: 0.15),
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'Search for songs to add',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 14,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        ),
      );
    }

    final displayItems =
        _showAllRecent ? _recentItems : _recentItems.take(5).toList();
    final canShowMore = _recentItems.length > 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
                textScaler: TextScaler.noScaling,
              ),
              GestureDetector(
                onTap: () async {
                  await RecentSearchService.clearAll();
                  _loadRecentItems();
                },
                child: Text(
                  'Clear',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Poppins',
                  ),
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
            itemCount: displayItems.length + (canShowMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == displayItems.length) {
                return GestureDetector(
                  onTap: () => setState(() => _showAllRecent = !_showAllRecent),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _showAllRecent ? 'Show less' : 'Show more',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Poppins',
                              ),
                              textScaler: TextScaler.noScaling,
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _showAllRecent
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: Colors.white70,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }
              final item = displayItems[index];
              final added = _isAdded(item.id);
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
                    onTap: () => _onRecentItemTap(item),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              item.type == 'artist' ? 22 : 8,
                            ),
                            child: Container(
                              width: 44,
                              height: 44,
                              color: Colors.white.withValues(alpha: 0.06),
                              child: item.image.isNotEmpty
                                  ? CachedImage(
                                      item.image,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _buildPlaceholder(item),
                                    )
                                  : _buildPlaceholder(item),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
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
                                  _recentSubtitle(item),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
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
                          if (item.type == 'song') ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: added ? null : () => _addSong(item),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: added
                                      ? Colors.white.withValues(alpha: 0.16)
                                      : Colors.white.withValues(alpha: 0.08),
                                ),
                                child: Icon(
                                  added
                                      ? Icons.check_rounded
                                      : Icons.add_rounded,
                                  color: added ? Colors.white : Colors.white70,
                                  size: 17,
                                ),
                              ),
                            ),
                          ],
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
    );
  }

  Widget _buildSearchResultItem(SearchResult song, bool added) {
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
          onTap: added ? null : () => _addSong(song),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                                _buildPlaceholder(song),
                          )
                        : _buildPlaceholder(song),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                          color: Colors.white.withValues(alpha: 0.5),
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
                GestureDetector(
                  onTap: added ? null : () => _addSong(song),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: added
                          ? Colors.white.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                    child: Icon(
                      added ? Icons.check_rounded : Icons.add_rounded,
                      color: added ? Colors.white : Colors.white70,
                      size: 17,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(SearchResult item) {
    return Icon(
      item.type == 'artist'
          ? Icons.person
          : item.type == 'album'
              ? Icons.album
              : Icons.music_note,
      color: Colors.white38,
      size: 24,
    );
  }

  String _recentSubtitle(SearchResult item) {
    switch (item.type) {
      case 'artist':
        return 'Artist';
      case 'album':
        return 'Album';
      case 'song':
        return item.artist;
      default:
        return '';
    }
  }
}
