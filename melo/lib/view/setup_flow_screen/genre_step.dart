import 'package:flutter/material.dart';

class GenreStep extends StatefulWidget {
  final VoidCallback onContinue;
  final VoidCallback onBack;
  final void Function(Set<String> genres)? onGenresSelected;
  final Set<String>? initialSelectedGenres;

  const GenreStep({
    super.key,
    required this.onContinue,
    required this.onBack,
    this.onGenresSelected,
    this.initialSelectedGenres,
  });

  @override
  State<GenreStep> createState() => _GenreStepState();
}

class _GenreStepState extends State<GenreStep> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedGenres = {};

  static const int _maxSelections = 3;

  @override
  void initState() {
    super.initState();
    if (widget.initialSelectedGenres != null) {
      _selectedGenres.addAll(widget.initialSelectedGenres!);
    }
  }

  final List<Map<String, String>> _genres = [
    {
      'name': 'Pop',
      'subtitle': 'Catchy and upbeat',
      'image': 'asset/Genre/pop.png'
    },
    {
      'name': 'Hip Hop',
      'subtitle': 'Beats and bars',
      'image': 'asset/Genre/hiphop.png'
    },
    {
      'name': 'R&B',
      'subtitle': 'Smooth and soulful',
      'image': 'asset/Genre/r&b.png'
    },
    {
      'name': 'Rock',
      'subtitle': 'Raw and energetic',
      'image': 'asset/Genre/rock.png'
    },
    {
      'name': 'Jazz',
      'subtitle': 'Cool and improvisational',
      'image': 'asset/Genre/jazz.png'
    },
    {
      'name': 'Electronic',
      'subtitle': 'Beats and synths',
      'image': 'asset/Genre/electronic.png'
    },
    {
      'name': 'Classical',
      'subtitle': 'Orchestral and timeless',
      'image': 'asset/Genre/classical.jpg'
    },
    {
      'name': 'Country',
      'subtitle': 'Heartland and stories',
      'image': 'asset/Genre/country.jpg'
    },
    {
      'name': 'Indie',
      'subtitle': 'Alternative vibes',
      'image': 'asset/Genre/indie.jpg'
    },
    {
      'name': 'Latin',
      'subtitle': 'Rhythmic and vibrant',
      'image': 'asset/Genre/latin.jpg'
    },
    {
      'name': 'K-Pop',
      'subtitle': 'Korean pop culture',
      'image': 'asset/Genre/kpop.jpg'
    },
    {
      'name': 'Metal',
      'subtitle': 'Heavy and intense',
      'image': 'asset/Genre/metal.jpg'
    },
    {
      'name': 'Reggae',
      'subtitle': 'Chill and rhythmic',
      'image': 'asset/Genre/Reggae.jpg'
    },
    {
      'name': 'Folk',
      'subtitle': 'Acoustic and storytelling',
      'image': 'asset/Genre/Folk.jpg'
    },
    {
      'name': 'Soul',
      'subtitle': 'Deep and emotional',
      'image': 'asset/Genre/Soul.jpg'
    },
    {
      'name': 'Punk',
      'subtitle': 'Fast and rebellious',
      'image': 'asset/Genre/Punk.jpg'
    },
    {
      'name': 'Blues',
      'subtitle': 'Raw and melancholic',
      'image': 'asset/Genre/Blues.jpg'
    },
    {
      'name': 'Alternative',
      'subtitle': 'Beyond the mainstream',
      'image': 'asset/Genre/Alternative.jpg'
    },
    {
      'name': 'Lo-Fi',
      'subtitle': 'Chill beats to study to',
      'image': 'asset/Genre/Lo-Fi.jpg'
    },
    {
      'name': 'Ambient',
      'subtitle': 'Atmospheric sounds',
      'image': 'asset/Genre/Ambient.jpg'
    },
    {
      'name': 'Dance',
      'subtitle': 'Club and party',
      'image': 'asset/Genre/Dance.jpg'
    },
    {
      'name': 'Anime',
      'subtitle': 'Japanese soundtracks',
      'image': 'asset/Genre/Anime.jpg'
    },
    {
      'name': 'Gaming',
      'subtitle': 'Game soundtracks',
      'image': 'asset/Genre/Gaming.jpg'
    },
  ];

  List<Map<String, String>> get _filteredGenres {
    if (_searchQuery.isEmpty) return _genres;
    return _genres
        .where((g) =>
            g['name']!.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            g['subtitle']!.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleGenre(String name) {
    setState(() {
      if (_selectedGenres.contains(name)) {
        _selectedGenres.remove(name);
      } else if (_selectedGenres.length < _maxSelections) {
        _selectedGenres.add(name);
      }
    });
    widget.onGenresSelected?.call(_selectedGenres);
  }

  Future<void> _saveAndContinue() async {
    if (_selectedGenres.length != _maxSelections) return;
    widget.onGenresSelected?.call(_selectedGenres);
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredGenres;
    final allSelected = _selectedGenres.length == _maxSelections;

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
                    onTap: widget.onBack,
                    child: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 24),
                  ),
                  GestureDetector(
                    onTap: allSelected ? _saveAndContinue : null,
                    child: Text(
                      allSelected
                          ? 'Next'
                          : _selectedGenres.isEmpty
                              ? 'Select at least 3'
                              : 'Select ${_maxSelections - _selectedGenres.length} more',
                      style: TextStyle(
                        color: allSelected
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
                'What kind of\nmusic do you like?',
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
                  onChanged: (value) => setState(() => _searchQuery = value),
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
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
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
                child: GridView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final genre = filtered[index];
                    final name = genre['name']!;
                    final isSelected = _selectedGenres.contains(name);

                    return GestureDetector(
                      onTap: () => _toggleGenre(name),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF514AED)
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset(
                                genre['image']!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: const Color(0xFF2D2D44),
                                    child: const Icon(
                                      Icons.music_note,
                                      color: Colors.white38,
                                      size: 40,
                                    ),
                                  );
                                },
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.8),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 12,
                                bottom: 12,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Poppins',
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      genre['subtitle']!,
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.6),
                                        fontSize: 11,
                                        fontFamily: 'Poppins',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: const BoxDecoration(
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
                        ),
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
