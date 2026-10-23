class TrackFilter {
  static const List<String> blockedPatterns = [
    'sombr',
    'stella lefty',
    'grand orchestre du splendid',
  ];

  /// Returns true if a song, artist, query, or ID matches blocked unplayable patterns.
  static bool isBlocked({
    String? artist,
    String? title,
    String? id,
    String? query,
  }) {
    final a = (artist ?? '').toLowerCase().trim();
    final t = (title ?? '').toLowerCase().trim();
    final q = (query ?? '').toLowerCase().trim();
    final i = (id ?? '').toLowerCase().trim();

    if (i == '0' || i == '-1' || i == 'null') return true;

    for (final pattern in blockedPatterns) {
      if (a.contains(pattern)) return true;
      if (t.contains(pattern)) return true;
      if (q.contains(pattern)) return true;
    }

    return false;
  }

  /// Returns true if the track is allowed to be shown or played.
  static bool isAllowed({
    String? artist,
    String? title,
    String? id,
    String? query,
  }) {
    return !isBlocked(artist: artist, title: title, id: id, query: query);
  }

  /// Helper for `Map<String, dynamic>` track objects
  static bool isAllowedMap(dynamic track) {
    if (track is! Map) return false;
    final id = (track['id'] ?? track['track_id'] ?? '').toString();
    final title = (track['title'] ?? '').toString();
    final artistRaw = track['artist'];
    final String artist;
    if (artistRaw is Map) {
      artist = (artistRaw['name'] ?? '').toString();
    } else {
      artist = (artistRaw ?? '').toString();
    }
    return isAllowed(artist: artist, title: title, id: id);
  }
}
