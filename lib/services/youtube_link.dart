/// Ссылка YouTube / YouTube Music, разобранная на идентификаторы.
class YoutubeLink {
  /// 11-символьный id видео, если ссылка ведёт на конкретный трек.
  final String? videoId;

  /// id плейлиста/радио из параметра `list`, если он есть.
  final String? playlistId;

  const YoutubeLink({this.videoId, this.playlistId});

  bool get hasVideo => videoId != null;

  static final RegExp _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final RegExp _urlInText = RegExp(
    r'https?://[^\s<>"]+',
    caseSensitive: false,
  );
  static final RegExp _trailingPunctuation = RegExp(r'[)\].,;!?]+$');

  static bool isVideoId(String value) => _videoIdPattern.hasMatch(value.trim());

  /// Понимает:
  /// - `https://music.youtube.com/watch?v=…`
  /// - `https://www.youtube.com/watch?v=…&list=…`
  /// - `https://youtu.be/…?si=…`
  /// - `https://youtube.com/shorts/…`, `/live/…`, `/embed/…`
  /// - голый 11-символьный id
  /// - текст вида «Смотри: https://…» (ссылку достаём из строки).
  ///
  /// Возвращает `null`, если это не ссылка YouTube.
  static YoutubeLink? parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    if (isVideoId(text)) return YoutubeLink(videoId: text);

    // В тексте «поделиться» ссылка может быть не первой — перебираем все.
    final urls = _urlInText
        .allMatches(text)
        .map((match) => match.group(0)!)
        .toList(growable: false);
    if (urls.isEmpty) return _parseUrl(text);

    for (final url in urls) {
      final link = _parseUrl(url);
      if (link != null) return link;
    }
    return null;
  }

  static YoutubeLink? _parseUrl(String input) {
    final text = input.replaceFirst(_trailingPunctuation, '');

    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    if (uri == null || uri.host.isEmpty) return null;

    final host = uri.host.toLowerCase();
    String? videoId;
    var playlistId = uri.queryParameters['list'];

    if (host == 'youtu.be') {
      final segments = _segments(uri);
      if (segments.isNotEmpty) videoId = _valid(segments.first);
    } else if (_isYoutubeHost(host)) {
      final segments = _segments(uri);
      if (segments.isEmpty) {
        videoId = _valid(uri.queryParameters['v']);
      } else {
        final first = segments.first.toLowerCase();
        if (first == 'watch' || first == 'playlist') {
          videoId = _valid(uri.queryParameters['v']);
        } else if (first == 'shorts' ||
            first == 'live' ||
            first == 'embed' ||
            first == 'v') {
          if (segments.length > 1) videoId = _valid(segments[1]);
        } else {
          // music.youtube.com иногда отдаёт ссылки без /watch.
          videoId = _valid(uri.queryParameters['v']);
        }
      }
    } else {
      return null;
    }

    if (playlistId != null && playlistId.isEmpty) playlistId = null;
    if (videoId == null && playlistId == null) return null;

    return YoutubeLink(videoId: videoId, playlistId: playlistId);
  }

  static bool _isYoutubeHost(String host) =>
      host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtube-nocookie.com' ||
      host.endsWith('.youtube-nocookie.com');

  static List<String> _segments(Uri uri) =>
      uri.pathSegments.where((segment) => segment.isNotEmpty).toList();

  static String? _valid(String? value) {
    final candidate = value?.trim();
    if (candidate == null || candidate.isEmpty) return null;
    return isVideoId(candidate) ? candidate : null;
  }
}
