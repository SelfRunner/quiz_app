/// YouTube URL helpers (pure Dart, no network).
abstract final class YoutubeUrl {
  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static const _hosts = {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'youtube-nocookie.com',
    'www.youtube-nocookie.com',
  };
  static const _pathPrefixes = {'shorts', 'embed', 'v', 'live', 'e'};

  /// Extracts the 11-character video id from any common YouTube URL form:
  /// `watch?v=`, `youtu.be/`, `/shorts/`, `/embed/`, `/v/`, `/live/`,
  /// mobile/music/nocookie hosts, with or without scheme, or a bare id.
  /// Returns null when [input] is not a recognizable YouTube video link.
  static String? parseVideoId(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    if (_idPattern.hasMatch(text)) return text;

    final withScheme = text.contains('://') ? text : 'https://$text';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      return null;
    }
    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    String? candidate;
    if (host == 'youtu.be' || host == 'www.youtu.be') {
      candidate = segments.isEmpty ? null : segments.first;
    } else if (_hosts.contains(host)) {
      if (segments.isNotEmpty && segments.first == 'watch') {
        candidate = uri.queryParameters['v'];
      } else if (segments.length >= 2 &&
          _pathPrefixes.contains(segments.first)) {
        candidate = segments[1];
      } else if (segments.isEmpty || segments.first == 'attribution_link') {
        // e.g. youtube.com/?v=ID or attribution_link?u=/watch?v=ID
        candidate = uri.queryParameters['v'];
        final u = uri.queryParameters['u'];
        if (candidate == null && u != null) {
          candidate = Uri.tryParse(u)?.queryParameters['v'];
        }
      }
    }
    if (candidate == null) return null;
    return _idPattern.hasMatch(candidate) ? candidate : null;
  }

  /// Canonical `https://www.youtube.com/watch?v=<id>` form.
  static String watchUrl(String videoId) =>
      'https://www.youtube.com/watch?v=$videoId';

  /// Canonical watch URL for [input], or null if it is not a YouTube link.
  static String? normalize(String input) {
    final id = parseVideoId(input);
    return id == null ? null : watchUrl(id);
  }
}
