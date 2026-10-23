import '../../widgets/cached_image.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/search_service.dart';
import '../../services/recent_search_service.dart';
import '../../services/recent_query_service.dart';
import '../../services/youtube_service.dart';
import '../../services/background_prefetch_service.dart';
import '../../services/profile_follow_service.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/fade_page_route.dart';
import '../../services/playback_service.dart';
import '../../services/premium_service.dart';
import '../artist_screen/artist_screen.dart';
import '../album_screen/album_detail_screen.dart';
import '../profile_screen/user_profile_screen.dart';
import '../../services/autocomplete_service.dart';
import 'search_result_item.dart';

class SearchOverlay extends StatefulWidget {
  final TextEditingController searchController;
  final FocusNode searchFocusNode;

  const SearchOverlay({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
  });

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  bool _isSearchTab = true; // true = Music, false = People
  List<SearchResult> _results = [];
  List<UserProfileItem> _peopleResults = [];
  List<String> _autocompleteSuggestions = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  List<SearchResult> _recentItems = [];
  List<String> _recentMusicQueries = [];
  List<String> _recentPeopleQueries = [];
  bool _showAllRecent = false;
  bool _showAllQueries = false;
  Timer? _debounceTimer;
  int _searchGeneration = 0;
  int _autocompleteGen = 0;
  bool _isSelectingSuggestion = false;
  String? _activeFilter; // null = All, 'song', 'artist', 'album'

  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_onSearchChanged);
    ProfileFollowService().addListener(_onFollowsChanged);
    _loadRecentItems();
  }

  @override
  void didUpdateWidget(SearchOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasSearched) {
      _loadRecentItems();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    widget.searchController.removeListener(_onSearchChanged);
    ProfileFollowService().removeListener(_onFollowsChanged);
    super.dispose();
  }

  void _onFollowsChanged() {
    if (mounted && !_isSearchTab) setState(() {});
  }

  Future<void> _loadRecentItems() async {
    final items = await RecentSearchService.getRecentSearches();
    final musicQueries =
        await RecentQueryService.getRecentQueries(isPeople: false);
    final peopleQueries =
        await RecentQueryService.getRecentQueries(isPeople: true);
    if (mounted) {
      setState(() {
        _recentItems = items;
        _recentMusicQueries = musicQueries;
        _recentPeopleQueries = peopleQueries;
      });
      YouTubeService.prefetchStreamUrls(items);
      BackgroundPrefetchService.instance
          .enqueueTracks(items, tag: 'recent_search');
    }
  }

  void _onSuggestionTap(String text) {
    _debounceTimer?.cancel();
    _isSelectingSuggestion = true;
    widget.searchController.text = text;
    widget.searchController.selection =
        TextSelection.fromPosition(TextPosition(offset: text.length));
    setState(() {
      _autocompleteSuggestions = []; // suggestions sentences are gone
      _results = []; // clear old results so skeleton loader shows
      _isSearching = true;
      _hasSearched = true;
    });
    _performSubmittedSearch(text);
  }

  Future<void> _performSubmittedSearch(String query) async {
    _debounceTimer?.cancel();
    final gen = ++_searchGeneration;
    setState(() {
      _isSearching = true;
      _results = [];
      _autocompleteSuggestions = [];
    });

    if (_isSearchTab) {
      final results = await SearchService.search(query);
      if (mounted && gen == _searchGeneration) {
        setState(() {
          _results = results;
          _autocompleteSuggestions = []; // keep suggestions gone
          _isSearching = false;
          _hasSearched = true;
        });
        YouTubeService.prefetchStreamUrls(results);
        BackgroundPrefetchService.instance
            .enqueueTracks(results, tag: 'search_results');
      }
    } else {
      final people = await ProfileFollowService().searchUsers(query);
      if (mounted && gen == _searchGeneration) {
        setState(() {
          _peopleResults = people;
          _autocompleteSuggestions = [];
          _isSearching = false;
          _hasSearched = true;
        });
      }
    }

    if (query.trim().isNotEmpty) {
      await RecentQueryService.addQuery(query, isPeople: !_isSearchTab);
      final queries =
          await RecentQueryService.getRecentQueries(isPeople: !_isSearchTab);
      if (mounted) {
        setState(() {
          if (_isSearchTab) {
            _recentMusicQueries = queries;
          } else {
            _recentPeopleQueries = queries;
          }
        });
      }
    }
  }

  void _fetchInstantSuggestions(String query) async {
    final gen = ++_autocompleteGen;
    final suggestions = await AutocompleteService.getSuggestions(query);
    if (mounted &&
        gen == _autocompleteGen &&
        widget.searchController.text.trim() == query) {
      setState(() {
        _autocompleteSuggestions = suggestions;
      });
    }
  }

  void _onSearchChanged() {
    if (_isSelectingSuggestion) {
      _isSelectingSuggestion = false;
      return;
    }
    _debounceTimer?.cancel();
    final query = widget.searchController.text.trim();
    if (query.length >= 2) {
      if (_isSearchTab) {
        _fetchInstantSuggestions(query);
      }
      _debounceTimer = Timer(const Duration(milliseconds: 400), () {
        _performSearch(query);
      });
    } else {
      ++_searchGeneration;
      ++_autocompleteGen;
      setState(() {
        _results = [];
        _peopleResults = [];
        _autocompleteSuggestions = [];
        _hasSearched = false;
        _isSearching = false;
        _showAllRecent = false;
        _activeFilter = null;
      });
      _loadRecentItems();
    }
  }

  Future<void> _performSearch(String query) async {
    _debounceTimer?.cancel();
    final gen = ++_searchGeneration;
    setState(() => _isSearching = true);

    if (_isSearchTab) {
      final futures = await Future.wait([
        SearchService.search(query),
        AutocompleteService.getSuggestions(query),
      ]);
      final results = futures[0] as List<SearchResult>;
      final suggestions = futures[1] as List<String>;
      if (mounted && gen == _searchGeneration) {
        setState(() {
          _results = results;
          if (suggestions.isNotEmpty) {
            _autocompleteSuggestions = suggestions;
          }
          _isSearching = false;
          _hasSearched = true;
        });
        YouTubeService.prefetchStreamUrls(results);
        BackgroundPrefetchService.instance
            .enqueueTracks(results, tag: 'search_results');
      }
    } else {
      final people = await ProfileFollowService().searchUsers(query);
      if (mounted && gen == _searchGeneration) {
        setState(() {
          _peopleResults = people;
          _autocompleteSuggestions = [];
          _isSearching = false;
          _hasSearched = true;
        });
      }
    }

    if (query.trim().isNotEmpty) {
      await RecentQueryService.addQuery(query, isPeople: !_isSearchTab);
      final queries =
          await RecentQueryService.getRecentQueries(isPeople: !_isSearchTab);
      if (mounted) {
        setState(() {
          if (_isSearchTab) {
            _recentMusicQueries = queries;
          } else {
            _recentPeopleQueries = queries;
          }
        });
      }
    }
  }

  void _onRecentItemTap(SearchResult item) {
    if (item.type == 'song') {
      if (!PremiumService().checkAndConsumeTrackSwitch(
        context,
        newTitle: item.title,
        newArtist: item.artist,
        newId: item.id,
      )) {
        return;
      }
      final playback = PlaybackService();
      playback.playTrack(item);
    } else if (item.type == 'artist') {
      Navigator.of(context, rootNavigator: true).push(
        FadePageRoute(
          page: ArtistScreen(
            artistId: item.id,
            artistName: item.title,
            artistImage: item.image,
            nbFan: item.nbFan,
          ),
        ),
      );
    } else if (item.type == 'album') {
      Navigator.of(context, rootNavigator: true).push(
        FadePageRoute(
          page: AlbumDetailScreen(
            albumId: item.id,
            albumTitle: item.title,
            albumImage: item.image,
            artistName: item.artist,
            artistId: '',
          ),
        ),
      );
    } else {
      widget.searchController.text = item.title;
      widget.searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: item.title.length),
      );
    }
  }

  Future<void> _removeRecentItem(String id) async {
    await RecentSearchService.removeItem(id);
    _loadRecentItems();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF191919),
      child: Column(
        children: [
          const SizedBox(height: 44),
          _buildSegmentedTabs(),
          const SizedBox(height: 12),
          Expanded(
            child: _isSearchTab ? _buildSearchTab() : _buildPeopleTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildTab('Music', _isSearchTab, () {
                setState(() => _isSearchTab = true);
                final q = widget.searchController.text.trim();
                if (q.length >= 2) _performSearch(q);
              }),
            ),
            Expanded(
              child: _buildTab('People', !_isSearchTab, () {
                setState(() => _isSearchTab = false);
                final q = widget.searchController.text.trim();
                if (q.length >= 2) _performSearch(q);
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF514AED) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white54,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'Poppins',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchTab() {
    final query = widget.searchController.text.trim();
    final isQueryActive = query.length >= 2;

    if (!isQueryActive && !_hasSearched && !_isSearching) {
      return _buildRecentSection();
    }

    final bottomPad = 120.0 + MediaQuery.of(context).viewInsets.bottom;

    return Column(
      children: [
        if (_results.isNotEmpty && _autocompleteSuggestions.isEmpty)
          _buildFilterChips(),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad),
            children: _buildGroupedResults(),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    final songs = _results.where((r) => r.type == 'song').length;
    final artists = _results.where((r) => r.type == 'artist').length;
    final albums = _results.where((r) => r.type == 'album').length;
    final playlists = _results.where((r) => r.type == 'playlist').length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildChip('All', null, _results.length),
            const SizedBox(width: 6),
            _buildChip('Songs', 'song', songs),
            const SizedBox(width: 6),
            _buildChip('Artists', 'artist', artists),
            const SizedBox(width: 6),
            _buildChip('Albums', 'album', albums),
            if (playlists > 0) ...[
              const SizedBox(width: 6),
              _buildChip('Playlists', 'playlist', playlists),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, String? filter, int count) {
    final isActive = _activeFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF514AED).withValues(alpha: 0.25)
              : const Color(0xFF222222),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? const Color(0xFF514AED).withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive ? const Color(0xFF8B85FF) : Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF514AED).withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isActive
                      ? const Color(0xFF8B85FF)
                      : Colors.white.withValues(alpha: 0.4),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeopleTab() {
    if (_isSearching) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: _buildSkeletonCard(count: 3),
      );
    }

    if (_hasSearched) {
      if (_peopleResults.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_search,
                  size: 48, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              const Text(
                'No people found',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 15,
                  fontFamily: 'Poppins',
                ),
              ),
            ],
          ),
        );
      }

      final bottomPad = 120.0 + MediaQuery.of(context).viewInsets.bottom;

      return ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad),
        itemCount: _peopleResults.length,
        itemBuilder: (context, index) {
          final user = _peopleResults[index];
          final followService = ProfileFollowService();
          final isFollowing = followService.isFollowing(user.id);
          final isMutual = followService.isMutualFriend(user.id);

          return InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(
                    userId: user.id,
                    initialDisplayName: user.displayName,
                    initialUsername: user.username,
                    initialAvatarUrl: user.avatarUrl,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  ClipOval(
                    child: user.avatarUrl.isNotEmpty
                        ? CachedImage(user.avatarUrl,
                            width: 48, height: 48, fit: BoxFit.cover)
                        : Container(
                            width: 48,
                            height: 48,
                            color: const Color(0xFF2A2A2A),
                            child: const Icon(Icons.person,
                                color: Colors.white38, size: 24),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName.isNotEmpty
                              ? user.displayName
                              : 'User',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.username.isNotEmpty ? '@${user.username}' : '',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                            fontFamily: 'Poppins',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      if (isFollowing) {
                        ProfileFollowService().unfollowUser(user.id);
                      } else {
                        ProfileFollowService().followUser(user);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isMutual
                            ? const Color(0xFF10B981).withValues(alpha: 0.2)
                            : isFollowing
                                ? Colors.white.withValues(alpha: 0.08)
                                : const Color(0xFF514AED),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isMutual
                              ? const Color(0xFF10B981)
                              : isFollowing
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        isMutual
                            ? 'Friends'
                            : isFollowing
                                ? 'Following'
                                : 'Follow',
                        style: TextStyle(
                          color:
                              isMutual ? const Color(0xFF10B981) : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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
      );
    }

    final hasQueries = _recentPeopleQueries.isNotEmpty;
    final bottomPad = 120.0 + MediaQuery.of(context).viewInsets.bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
      children: [
        if (hasQueries) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.history_rounded,
                      color: Color(0xFF514AED), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Recent Searches',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (_recentPeopleQueries.length > 4) ...[
                    GestureDetector(
                      onTap: () =>
                          setState(() => _showAllQueries = !_showAllQueries),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF514AED).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _showAllQueries ? 'Show less' : 'View all',
                          style: const TextStyle(
                            color: Color(0xFF7A73FF),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  GestureDetector(
                    onTap: () async {
                      await RecentQueryService.clearAll(isPeople: true);
                      setState(() {
                        _recentPeopleQueries = [];
                        _showAllQueries = false;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Clear',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: (_showAllQueries
                    ? _recentPeopleQueries
                    : _recentPeopleQueries.take(6).toList())
                .map((q) => _buildQueryBubble(q))
                .toList(),
          ),
          const SizedBox(height: 32),
        ],
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Icon(Icons.people_outline,
                  size: 54, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(height: 12),
              Text(
                'Search for friends by name or @username',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                  fontFamily: 'Poppins',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentSection() {
    final hasItems = _recentItems.isNotEmpty;
    final hasQueries = _recentMusicQueries.isNotEmpty;

    if (!hasItems && !hasQueries) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF222222),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Icon(Icons.search_rounded,
                  size: 32, color: Color(0xFF514AED)),
            ),
            const SizedBox(height: 16),
            const Text(
              'Explore Melo',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Search for songs, artists, or friends',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 13,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        ),
      );
    }

    final bottomPad = 120.0 + MediaQuery.of(context).viewInsets.bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
      children: [
        if (hasQueries) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.history_rounded,
                      color: Color(0xFF514AED), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Recent Searches',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (_recentMusicQueries.length > 4) ...[
                    GestureDetector(
                      onTap: () =>
                          setState(() => _showAllQueries = !_showAllQueries),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF514AED).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _showAllQueries ? 'Show less' : 'View all',
                          style: const TextStyle(
                            color: Color(0xFF7A73FF),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  GestureDetector(
                    onTap: () async {
                      await RecentQueryService.clearAll(isPeople: false);
                      setState(() {
                        _recentMusicQueries = [];
                        _showAllQueries = false;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Clear',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: (_showAllQueries
                    ? _recentMusicQueries
                    : _recentMusicQueries.take(6).toList())
                .map((q) => _buildQueryBubble(q))
                .toList(),
          ),
          const SizedBox(height: 24),
        ],
        if (hasItems) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.play_circle_filled_rounded,
                      color: Color(0xFF514AED), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Recently Played',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
              if (_recentItems.length > 4)
                GestureDetector(
                  onTap: () => setState(() => _showAllRecent = !_showAllRecent),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF514AED).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _showAllRecent ? 'Show less' : 'View all',
                      style: const TextStyle(
                        color: Color(0xFF7A73FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: (_showAllRecent
                      ? _recentItems
                      : _recentItems.take(5).toList())
                  .length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                thickness: 1,
                color: Colors.white.withValues(alpha: 0.04),
                indent: 64,
                endIndent: 16,
              ),
              itemBuilder: (context, i) {
                final list = _showAllRecent
                    ? _recentItems
                    : _recentItems.take(5).toList();
                return _buildRecentItemRow(list[i]);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRecentItemRow(SearchResult item) {
    final isArtist = item.type == 'artist';

    return InkWell(
      onTap: () => _onRecentItemTap(item),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(isArtist ? 22 : 8),
              child: Container(
                width: 44,
                height: 44,
                color: const Color(0xFF2A2A2A),
                child: item.image.isNotEmpty
                    ? CachedImage(item.image,
                        width: 44, height: 44, fit: BoxFit.cover)
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
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Poppins',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF514AED).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.type.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF8B85FF),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _recentSubtitle(item),
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
              ),
            ),
            GestureDetector(
              onTap: () => _removeRecentItem(item.id),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
                child: Icon(Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.35), size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(List<SearchResult> items,
      {List<SearchResult>? allContext}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: items.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 1,
          color: Colors.white.withValues(alpha: 0.04),
          indent: 64,
          endIndent: 16,
        ),
        itemBuilder: (context, i) {
          return SearchResultItem(
              result: items[i], allResults: allContext);
        },
      ),
    );
  }

  Widget _buildSkeletonCard({int count = 5}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: count,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 1,
          color: Colors.white.withValues(alpha: 0.04),
          indent: 64,
          endIndent: 16,
        ),
        itemBuilder: (_, __) => const SkeletonSearchResult(),
      ),
    );
  }

  List<Widget> _buildGroupedResults() {
    final artists = _results.where((r) => r.type == 'artist').toList();
    final allSongs = _results.where((r) => r.type == 'song').toList();
    final albums = _results.where((r) => r.type == 'album').toList();
    final playlists = _results.where((r) => r.type == 'playlist').toList();

    // When a filter is active, only show that type
    if (_activeFilter != null) {
      final widgets = <Widget>[];
      if (_isSearching && _results.isEmpty) {
        widgets.add(_buildSkeletonCard(count: 3));
        return widgets;
      }
      if (_activeFilter == 'artist') {
        if (artists.isNotEmpty) {
          widgets.add(
              _buildSectionHeader(artists.length > 1 ? 'Artists' : 'Artist'));
          widgets.add(_buildResultCard(artists, allContext: artists));
        }
      } else if (_activeFilter == 'song') {
        if (allSongs.isNotEmpty) {
          widgets.add(_buildSectionHeader('Songs'));
          widgets.add(_buildResultCard(allSongs));
        }
      } else if (_activeFilter == 'album') {
        if (albums.isNotEmpty) {
          widgets.add(_buildSectionHeader('Albums'));
          widgets.add(_buildResultCard(albums, allContext: albums));
        }
      } else if (_activeFilter == 'playlist') {
        if (playlists.isNotEmpty) {
          widgets.add(_buildSectionHeader('Playlists'));
          widgets.add(_buildResultCard(playlists, allContext: playlists));
        }
      }
      if (widgets.isEmpty && _hasSearched) {
        widgets.add(const SizedBox(height: 48));
        widgets.add(Center(
          child: Text(
            'No ${_activeFilter}s found',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 14,
              fontFamily: 'Poppins',
            ),
          ),
        ));
      }
      return widgets;
    }

    final widgets = <Widget>[];

    // 1. Suggestions on TOP (Loaded immediately with NO wait as user types - matches Spotify layout)
    if (_autocompleteSuggestions.isNotEmpty) {
      widgets.add(_buildSuggestionsSection(_autocompleteSuggestions));
      widgets.add(const SizedBox(height: 6));
    }

    // 2. Loading state when searching and no song results yet
    if (_isSearching && _results.isEmpty) {
      widgets.add(_buildSkeletonCard(count: 5));
      return widgets;
    }

    // 3. If query was searched and returned no results:
    if (_hasSearched && _results.isEmpty && !_isSearching) {
      widgets.add(const SizedBox(height: 36));
      widgets.add(const Center(
        child: Text(
          'No results found',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 16,
            fontFamily: 'Poppins',
          ),
        ),
      ));
      return widgets;
    }

    // 4. Initial debounce waiting state (query >= 2 chars, results empty, search about to fire)
    if (_results.isEmpty && !_hasSearched) {
      widgets.add(_buildSkeletonCard(count: 5));
      return widgets;
    }

    // 5. Songs (Matched songs directly below suggestions)
    if (allSongs.isNotEmpty) {
      // In Spotify typing mode (when suggestions are visible), songs follow suggestions directly without header
      if (_autocompleteSuggestions.isEmpty) {
        widgets.add(_buildSectionHeader('Songs'));
      }
      widgets.add(
          _buildResultCard(allSongs.take(6).toList()));
    }

    // 6. Artists
    if (artists.isNotEmpty) {
      widgets.add(const SizedBox(height: 10));
      widgets
          .add(_buildSectionHeader(artists.length > 1 ? 'Artists' : 'Artist'));
      widgets
          .add(_buildResultCard(artists.take(3).toList(), allContext: artists));
    }

    // 7. Albums
    if (albums.isNotEmpty) {
      widgets.add(const SizedBox(height: 10));
      widgets.add(_buildSectionHeader('Albums'));
      widgets
          .add(_buildResultCard(albums.take(3).toList(), allContext: albums));
    }

    // 8. Playlists
    if (playlists.isNotEmpty) {
      widgets.add(const SizedBox(height: 10));
      widgets.add(_buildSectionHeader('Playlists'));
      widgets.add(
          _buildResultCard(playlists.take(3).toList(), allContext: playlists));
    }

    // 9. Dedicated Section: More Artists
    if (artists.length > 3) {
      final moreArtists = artists.skip(3).toList();
      if (moreArtists.isNotEmpty) {
        widgets.add(const SizedBox(height: 10));
        widgets.add(_buildSectionHeader('More Artists'));
        widgets.add(_buildResultCard(moreArtists, allContext: artists));
      }
    }

    // 10. Dedicated Bottom Section: More Songs
    if (allSongs.length > 6) {
      final moreSongs = allSongs.skip(6).toList();
      widgets.add(const SizedBox(height: 10));
      widgets.add(_buildSectionHeader('More Songs'));
      widgets.add(_buildResultCard(moreSongs));
    }

    return widgets;
  }

  Widget _buildSuggestionsSection(List<String> suggestions) {
    final currentQuery = widget.searchController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: suggestions.take(5).map((text) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _onSuggestionTap(text),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF514AED),
                      size: 15,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSuggestionText(text, currentQuery),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _debounceTimer?.cancel();
                        _isSelectingSuggestion = true;
                        widget.searchController.text = text;
                        widget.searchController.selection =
                            TextSelection.fromPosition(
                                TextPosition(offset: text.length));
                        _fetchInstantSuggestions(text);
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.north_west_rounded,
                          color: Colors.white38,
                          size: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSuggestionText(String text, String query) {
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    const khmerFontFallback = [
      'Kantumruy Pro',
      'Battambang',
      'Noto Sans Khmer',
      'Khmer OS Siemreap',
      'Khmer OS',
      'sans-serif',
    ];

    if (lowerQuery.isNotEmpty && lowerText.startsWith(lowerQuery)) {
      final prefix = text.substring(0, query.length);
      final suffix = text.substring(query.length);
      return RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontFamily: 'Poppins',
            fontFamilyFallback: khmerFontFallback,
            height: 1.35,
          ),
          children: [
            TextSpan(
              text: prefix,
              style: const TextStyle(
                fontWeight: FontWeight.w400,
                color: Colors.white70,
              ),
            ),
            TextSpan(
              text: suffix,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        fontFamily: 'Poppins',
        fontFamilyFallback: khmerFontFallback,
        height: 1.35,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          fontFamily: 'Poppins',
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
              : item.type == 'playlist'
                  ? Icons.playlist_play_rounded
                  : Icons.music_note,
      color: Colors.white38,
      size: 20,
    );
  }

  Widget _buildQueryBubble(String query, {bool isFullWidth = false}) {
    return Material(
      color: const Color(0xFF222222),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () {
          widget.searchController.text = query;
          widget.searchController.selection = TextSelection.fromPosition(
            TextPosition(offset: query.length),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: isFullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
            children: [
              const Icon(Icons.search_rounded,
                  color: Color(0xFF514AED), size: 15),
              const SizedBox(width: 8),
              Expanded(
                flex: isFullWidth ? 1 : 0,
                child: Text(
                  query,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    fontFamily: 'Poppins',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isFullWidth)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    await RecentQueryService.removeQuery(query,
                        isPeople: !_isSearchTab);
                    final updated = await RecentQueryService.getRecentQueries(
                        isPeople: !_isSearchTab);
                    if (mounted) {
                      setState(() {
                        if (_isSearchTab) {
                          _recentMusicQueries = updated;
                        } else {
                          _recentPeopleQueries = updated;
                        }
                      });
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.white.withValues(alpha: 0.35),
                      size: 15,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _recentSubtitle(SearchResult item) {
    switch (item.type) {
      case 'song':
        return 'Song \u00b7 ${item.artist}';
      case 'artist':
        return 'Artist';
      case 'album':
        return 'Album \u00b7 ${item.artist}';
      default:
        return '';
    }
  }
}
