import '../../widgets/cached_image.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/artist_service.dart';
import '../../services/artist_follow_service.dart';
import '../../main.dart';
import '../../widgets/skeleton_loader.dart';

class ArtistStep extends StatefulWidget {
  final VoidCallback onContinue;
  final VoidCallback onBack;
  final Set<String> selectedGenres;
  final String? username;
  final String? displayName;
  final File? pickedImage;
  final String? selectedAvatar;

  const ArtistStep({
    super.key,
    required this.onContinue,
    required this.onBack,
    this.selectedGenres = const {},
    this.username,
    this.displayName,
    this.pickedImage,
    this.selectedAvatar,
  });

  @override
  State<ArtistStep> createState() => _ArtistStepState();
}

class _ArtistStepState extends State<ArtistStep> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  final int _minSelections = 3;
  final int _maxSelections = 10;

  bool _isLoading = true;
  bool _isSearching = false;
  bool _isSaving = false;
  Timer? _debounce;
  List<Map<String, dynamic>> _artists = [];
  List<Map<String, dynamic>> _cachedArtists = [];
  final List<Map<String, dynamic>> _pinnedArtists = [];
  final Set<String> _selectedArtistIds = {};
  final Set<String> _searchResultIds = {};

  @override
  void initState() {
    super.initState();
    _loadArtistsByGenres();
  }

  @override
  void didUpdateWidget(covariant ArtistStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_setEquals(oldWidget.selectedGenres, widget.selectedGenres)) {
      _searchController.clear();
      _searchResultIds.clear();
      _pinnedArtists.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _isLoading = true);
          _loadArtistsByGenres();
        }
      });
    }
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadArtistsByGenres() async {
    try {
      final genres = widget.selectedGenres.toList();
      debugPrint('Loading curated artists for genres: $genres');
      final List<Map<String, dynamic>> artists;
      if (genres.isEmpty) {
        artists =
            await ArtistService.getCuratedArtists(["Pop", "Hip Hop", "R&B"]);
      } else {
        artists = await ArtistService.getCuratedArtists(genres);
        debugPrint('Curated artists count: ${artists.length}');
      }
      debugPrint('Total artists: ${artists.length}');
      if (mounted) {
        setState(() {
          _cachedArtists = artists;
          _artists = _buildDisplayList(artists);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Load artists error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _buildDisplayList(
      List<Map<String, dynamic>> baseList) {
    final result = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    for (final artist in _pinnedArtists) {
      final id = artist['id']?.toString() ?? '';
      if (id.isNotEmpty && _selectedArtistIds.contains(id) && seenIds.add(id)) {
        result.add(artist);
      }
    }
    for (final artist in baseList) {
      final id = artist['id']?.toString() ?? '';
      if (id.isNotEmpty && seenIds.add(id)) {
        result.add(artist);
      }
    }
    return result;
  }

  List<Map<String, dynamic>> _sortArtists(List<Map<String, dynamic>> list) {
    final sorted = List<Map<String, dynamic>>.from(list);
    sorted.sort((a, b) {
      final aIsSearchedSelected = _searchResultIds.contains(a['id']) &&
          _selectedArtistIds.contains(a['id']);
      final bIsSearchedSelected = _searchResultIds.contains(b['id']) &&
          _selectedArtistIds.contains(b['id']);
      if (aIsSearchedSelected && !bIsSearchedSelected) return -1;
      if (!aIsSearchedSelected && bIsSearchedSelected) return 1;
      return 0;
    });
    return sorted;
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _artists = _buildDisplayList(_cachedArtists);
      _isSearching = false;
    });
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _artists = _buildDisplayList(_cachedArtists);
        _isSearching = false;
      });
      return;
    }
    if (query.length < 2) {
      // Filter local list only for single characters (no API call)
      final filtered = _cachedArtists
          .where((a) => (a['name']?.toString() ?? '')
              .toLowerCase()
              .contains(query.toLowerCase()))
          .where((a) => (a['name']?.toString() ?? '')
              .toLowerCase()
              .contains(query.toLowerCase()))
          .toList();
      setState(() {
        _artists = _sortArtists(filtered);
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 800), () {
      _searchArtists(query);
    });
  }

  Future<void> _searchArtists(String query) async {
    setState(() => _isSearching = true);
    try {
      final searchResults = await ArtistService.searchArtists(query);
      final results = searchResults
          .map((r) => {
                'id': r.id,
                'name': r.title,
                'image': r.artistImage,
                'picture_big': r.artistImage,
                'nb_fan': r.nbFan,
                'type': r.type,
              })
          .toList();
      final baseIds = _cachedArtists.map((a) => a['id']).toSet();
      for (final artist in results) {
        _searchResultIds.add(artist['id']?.toString() ?? '');
        if (!baseIds.contains(artist['id']) &&
            !_pinnedArtists.any((a) => a['id'] == artist['id'])) {
          _pinnedArtists.add(artist);
        }
      }
      if (mounted) {
        setState(() {
          _artists = _sortArtists(results);
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('Search artists error: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _toggleArtist(Map<String, dynamic> artist) {
    final id = artist['id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() {
      if (_selectedArtistIds.contains(id)) {
        _selectedArtistIds.remove(id);
        _searchResultIds.remove(id);
        _pinnedArtists.removeWhere((a) => a['id'] == id);
      } else if (_selectedArtistIds.length < _maxSelections) {
        _selectedArtistIds.add(id);
      }
      _artists = _sortArtists(_artists);
    });
  }

  bool _isSelected(Map<String, dynamic> artist) {
    return _selectedArtistIds.contains(artist['id']);
  }

  String _formatGenres(List<dynamic> genres) {
    if (genres.isEmpty) return '';
    final shown = genres.take(2).map((g) {
      final s = g.toString();
      return s[0].toUpperCase() + s.substring(1);
    }).toList();
    return shown.join(' • ');
  }

  Future<void> _saveAndContinue() async {
    if (_selectedArtistIds.length < _minSelections) return;

    setState(() => _isSaving = true);

    try {
      final userId = _supabase.auth.currentUser!.id;
      final selectedArtists = _artists
          .where((a) => _selectedArtistIds.contains(a['id']))
          .map((a) => {'id': a['id'], 'name': a['name'], 'image': a['image']})
          .toList();

      String? avatarUrl;

      // Upload avatar straight to Supabase Storage (no backend needed).
      // Same bucket/path convention the backend used:
      //   avatars/{userId}/profile.{ext}
      if (widget.pickedImage != null) {
        try {
          final ext = widget.pickedImage!.path.split('.').last.toLowerCase();
          final fileBytes = await widget.pickedImage!.readAsBytes();
          final contentType = switch (ext) {
            'png' => 'image/png',
            'webp' => 'image/webp',
            'gif' => 'image/gif',
            _ => 'image/jpeg',
          };
          final path = '$userId/profile.$ext';

          await _supabase.storage.from('avatars').uploadBinary(
                path,
                fileBytes,
                fileOptions:
                    FileOptions(upsert: true, contentType: contentType),
              );
          avatarUrl = _supabase.storage.from('avatars').getPublicUrl(path);
        } catch (e) {
          debugPrint('Avatar upload failed: $e');
        }
      } else if (widget.selectedAvatar != null) {
        avatarUrl = widget.selectedAvatar;
      }

      // Submit full profile setup directly to Supabase
      await _supabase.from('profiles').upsert({
        'id': userId,
        if (widget.username != null && widget.username!.isNotEmpty)
          'username': widget.username,
        if (widget.displayName != null && widget.displayName!.isNotEmpty)
          'display_name': widget.displayName,
        if (avatarUrl != null && avatarUrl.isNotEmpty)
          'avatar_url': avatarUrl,
        'favorite_genres': widget.selectedGenres.toList(),
        'favorite_artists': selectedArtists,
        'profile_setup_completed': true,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Also register followed artists in local and remote cache
      for (final artist in selectedArtists) {
        final aId = artist['id']?.toString() ?? '';
        final aName = artist['name']?.toString() ?? '';
        final aImg = artist['image']?.toString() ?? '';
        if (aId.isNotEmpty && aName.isNotEmpty) {
          try {
            await ArtistFollowService().followArtist(
              artistId: aId,
              artistName: aName,
              artistImage: aImg,
            );
          } catch (_) {}
        }
      }

      // Seed the profile-complete cache so AuthGate goes straight to Home
      await AuthGate.markProfileComplete();
      widget.onContinue();
    } catch (e) {
      debugPrint('Setup error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Something went wrong: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _onBackPressed() {
    if (_selectedArtistIds.isEmpty) {
      widget.onBack();
      return;
    }
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
                'Go Back?',
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
                'Your selected artists will be cleared if you leave now.',
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
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _selectedArtistIds.clear();
                          _searchResultIds.clear();
                          _pinnedArtists.clear();
                          widget.onBack();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF514AED),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        child: const Text(
                          'Go Back',
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
    final hasMinimum = _selectedArtistIds.length >= _minSelections;
    final remaining = _minSelections - _selectedArtistIds.length;
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return SafeArea(
      bottom: false,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                height: isKeyboardOpen ? 8 : 16,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: _onBackPressed,
                    child: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 24),
                  ),
                  GestureDetector(
                    onTap: (hasMinimum && !_isSaving) ? _saveAndContinue : null,
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Color(0xFF514AED),
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            hasMinimum
                                ? 'Next'
                                : _selectedArtistIds.isEmpty
                                    ? 'Select at least 3'
                                    : 'Select $remaining more',
                            style: TextStyle(
                              color: hasMinimum
                                  ? const Color(0xFF514AED)
                                  : Colors.white.withValues(alpha: 0.4),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Poppins',
                            ),
                          ),
                  ),
                ],
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                height: isKeyboardOpen ? 8 : 14,
              ),
              Text(
                'Who do you love\nlistening to?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isKeyboardOpen ? 19 : 22,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                  height: 1.25,
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                height: isKeyboardOpen ? 8 : 14,
              ),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontFamily: 'Poppins',
                  ),
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 15,
                      fontFamily: 'Poppins',
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: Colors.white.withValues(alpha: 0.3),
                      size: 20,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? GestureDetector(
                            onTap: _clearSearch,
                            behavior: HitTestBehavior.opaque,
                            child: Icon(
                              Icons.close,
                              color: Colors.white.withValues(alpha: 0.4),
                              size: 18,
                            ),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _isLoading
                    ? GridView.builder(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.68,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: 9,
                        itemBuilder: (context, index) =>
                            const SkeletonArtistCard(),
                      )
                    : _artists.isEmpty && _isSearching
                        ? GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.68,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: 9,
                            itemBuilder: (context, index) =>
                                const SkeletonArtistCard(),
                          )
                        : _artists.isEmpty
                            ? Center(
                                child: Text(
                                  'No artists found',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 14,
                                    fontFamily: 'Poppins',
                                  ),
                                ),
                              )
                            : GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.68,
                                ),
                                itemCount: _artists.length,
                                itemBuilder: (context, index) {
                                  final artist = _artists[index];
                                  final selected = _isSelected(artist);
                                  final genres =
                                      _formatGenres(artist['genres'] ?? []);

                                  return GestureDetector(
                                    onTap: () => _toggleArtist(artist),
                                    child: Column(
                                      children: [
                                        Stack(
                                          children: [
                                            Container(
                                              width: 104,
                                              height: 104,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: selected
                                                      ? const Color(0xFF514AED)
                                                      : Colors.transparent,
                                                  width: 3,
                                                ),
                                              ),
                                              padding: const EdgeInsets.all(3),
                                              child: ClipOval(
                                                child: artist['image'] != null
                                                    ? CachedImage(
                                                        artist['image'],
                                                        key: ValueKey(
                                                            'step_artist_${artist['id']}_${artist['image']}'),
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (context,
                                                            error, stackTrace) {
                                                          return Container(
                                                            color: const Color(
                                                                0xFF2D2D44),
                                                            child: const Icon(
                                                              Icons.person,
                                                              color: Colors
                                                                  .white38,
                                                              size: 40,
                                                            ),
                                                          );
                                                        },
                                                      )
                                                    : Container(
                                                        color: const Color(
                                                            0xFF2D2D44),
                                                        child: const Icon(
                                                          Icons.person,
                                                          color: Colors.white38,
                                                          size: 40,
                                                        ),
                                                      ),
                                              ),
                                            ),
                                            if (selected)
                                              Positioned(
                                                top: 0,
                                                right: 0,
                                                child: Container(
                                                  width: 28,
                                                  height: 28,
                                                  decoration:
                                                      const BoxDecoration(
                                                    color: Color(0xFF514AED),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.check,
                                                    color: Colors.white,
                                                    size: 16,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          artist['name']?.toString() ?? '',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: 'Poppins',
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (genres.isNotEmpty)
                                          Text(
                                            genres,
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.4),
                                              fontSize: 10,
                                              fontFamily: 'Poppins',
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
