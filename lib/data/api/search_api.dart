import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../services/youtube_service.dart';
import '../models/track.dart';
import 'audius_api.dart';

/// Итог мультиисточникового поиска.
class SearchOutcome {
  final List<Track> tracks;

  /// Сколько источников было опрошено (Jamendo пропускается без ключа).
  final int attemptedSources;

  /// Сколько источников завершилось ошибкой.
  final int failedSources;

  /// Сколько ошибок было сетевыми (таймаут, нет соединения).
  final int networkFailures;

  const SearchOutcome({
    this.tracks = const [],
    this.attemptedSources = 0,
    this.failedSources = 0,
    this.networkFailures = 0,
  });

  bool get allFailed =>
      attemptedSources > 0 && failedSources == attemptedSources;

  bool get noNetwork => allFailed && networkFailures == attemptedSources;
}

/// Параллельный поиск по Deezer, iTunes, Audius, Jamendo, Internet Archive
/// и YouTube.
///
/// Каждый источник изолирован: его ошибка или таймаут не мешает остальным.
class SearchApi {
  SearchApi(this._audius, this._prefs, this._youtube);

  final AudiusApi _audius;
  final SharedPreferences _prefs;
  final YoutubeService _youtube;

  static const Duration _sourceTimeout = Duration(
    seconds: AppConstants.searchTimeoutSeconds,
  );

  static const Map<String, String> _headers = {'User-Agent': 'VerdeMusic/1.0'};

  /// Кэш последних удачных выдач: повторный запрос открывается мгновенно,
  /// а подборки на главной не дёргают одни и те же источники заново.
  static const Duration _cacheTtl = Duration(minutes: 5);
  static const int _maxCacheEntries = 40;
  final Map<String, _CachedSearch> _cache = {};

  Future<SearchOutcome> search(String query) => searchSources(query);

  /// Поиск только по выбранным источникам.
  ///
  /// `sources == null` — все источники, как в обычном поиске. Рекомендации
  /// передают ограниченный набор, чтобы не дёргать Audius/Archive/Jamendo
  /// на каждый похожий трек и не упираться в rate limit.
  ///
  /// [onPartial] вызывается после ответа каждого источника. Благодаря этому
  /// поиск показывает первые результаты сразу, не ожидая самый медленный
  /// источник. Итоговый результат по-прежнему возвращается целиком.
  Future<SearchOutcome> searchSources(
    String query, {
    Set<TrackSource>? sources,
    void Function(SearchOutcome outcome)? onPartial,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const SearchOutcome();

    // Поиск по умолчанию ведётся только по полным трекам YouTube Music.
    final effectiveSources = sources ?? const {TrackSource.youtube};

    final cacheKey = _cacheKey(q, effectiveSources);
    final cached = _cache[cacheKey];
    if (cached != null) {
      if (DateTime.now().difference(cached.createdAt) < _cacheTtl) {
        try {
          onPartial?.call(cached.outcome);
        } catch (_) {
          // Ошибка UI-колбэка не должна ломать поиск.
        }
        return cached.outcome;
      }
      _cache.remove(cacheKey);
    }

    bool enabled(TrackSource source) => effectiveSources.contains(source);

    final futures = <Future<_SourceAttempt>>[];
    if (enabled(TrackSource.audius)) {
      futures.add(_attempt(TrackSource.audius, () => _audius.search(q)));
    }
    if (enabled(TrackSource.deezer)) {
      futures.add(_attempt(TrackSource.deezer, () => _deezer(q)));
    }
    if (enabled(TrackSource.itunes)) {
      futures.add(_attempt(TrackSource.itunes, () => _itunes(q)));
    }
    if (enabled(TrackSource.archive)) {
      futures.add(_attempt(TrackSource.archive, () => _archive(q)));
    }
    if (enabled(TrackSource.youtube)) {
      futures.add(
        _attempt(
          TrackSource.youtube,
          () => _youtube.searchTracks(q),
          // YouTube ищет дольше остальных источников; внутренний таймаут
          // сервиса (9 с) срабатывает раньше этого предохранителя.
          timeout: const Duration(seconds: 10),
        ),
      );
    }

    final jamendoClientId =
        _prefs.getString(AppConstants.jamendoClientIdKey)?.trim() ?? '';
    if (enabled(TrackSource.jamendo) && jamendoClientId.isNotEmpty) {
      futures.add(
        _attempt(TrackSource.jamendo, () => _jamendo(q, jamendoClientId)),
      );
    }

    if (futures.isEmpty) return const SearchOutcome();
    final total = futures.length;
    final attempts = <_SourceAttempt>[];

    await Future.wait([
      for (final future in futures)
        future.then((attempt) {
          attempts.add(attempt);
          if (onPartial == null) return;

          try {
            onPartial(_outcome(attempts, q, total));
          } catch (_) {
            // Ошибка UI-колбэка не должна отменять сам поиск.
          }
        }),
    ]);

    final outcome = _outcome(attempts, q, total);
    // Неполную выдачу не кэшируем: при повторе источник может ответить,
    // и пользователь получит полные треки, а не только превью.
    if (outcome.tracks.isNotEmpty && outcome.failedSources == 0) {
      _cache[cacheKey] = _CachedSearch(outcome, DateTime.now());
      if (_cache.length > _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
    }
    return outcome;
  }

  SearchOutcome _outcome(
    List<_SourceAttempt> attempts,
    String query,
    int total,
  ) {
    return SearchOutcome(
      tracks: _merge(attempts, query),
      attemptedSources: total,
      failedSources: attempts.where((attempt) => attempt.failed).length,
      networkFailures: attempts
          .where((attempt) => attempt.failed && attempt.network)
          .length,
    );
  }

  String _cacheKey(String query, Set<TrackSource>? sources) {
    final sourceKey = sources == null
        ? 'all'
        : (sources.map((source) => source.name).toList()..sort()).join(',');
    return '${_normalize(query)}|$sourceKey';
  }

  Future<_SourceAttempt> _attempt(
    TrackSource source,
    Future<List<Track>> Function() load, {
    Duration? timeout,
  }) async {
    try {
      final tracks = await load().timeout(timeout ?? _sourceTimeout);
      return _SourceAttempt(tracks);
    } on TimeoutException {
      return const _SourceAttempt([], failed: true, network: true);
    } on NetworkException {
      return const _SourceAttempt([], failed: true, network: true);
    } on IOException {
      return const _SourceAttempt([], failed: true, network: true);
    } on http.ClientException {
      return const _SourceAttempt([], failed: true, network: true);
    } catch (_) {
      return const _SourceAttempt([], failed: true);
    }
  }

  // --- Объединение результатов ---------------------------------------------

  List<Track> _merge(List<_SourceAttempt> attempts, String query) {
    final unique = <String, Track>{};

    for (final attempt in attempts) {
      for (final track in attempt.tracks) {
        final key = _dedupeKey(track);
        final existing = unique[key];
        unique[key] = existing == null ? track : _prefer(existing, track);
      }
    }

    final scored = <_ScoredTrack>[
      for (final track in unique.values)
        _ScoredTrack(track, _relevance(track, query)),
    ];

    scored.sort((a, b) {
      // 1. Лучшее совпадение с запросом.
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;

      // 2. Полные треки выше превью.
      final byPreview = (a.track.isPreview ? 1 : 0).compareTo(
        b.track.isPreview ? 1 : 0,
      );
      if (byPreview != 0) return byPreview;

      return a.track.title.toLowerCase().compareTo(b.track.title.toLowerCase());
    });

    return [for (final item in scored) item.track];
  }

  Track _prefer(Track current, Track candidate) {
    if (current.isPreview && !candidate.isPreview) {
      // Полная версия важнее, но обложку от превью не теряем.
      if (candidate.artworkUrl == null && current.artworkUrl != null) {
        return candidate.copyWith(artworkUrl: current.artworkUrl);
      }
      return candidate;
    }
    if (!current.isPreview && candidate.isPreview) return current;
    if (current.artworkUrl == null && candidate.artworkUrl != null) {
      return candidate;
    }
    return current;
  }

  String _dedupeKey(Track track) =>
      '${_normalize(track.title)}|${_normalize(track.artist)}';

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  bool _titleMatches(String candidate, String wanted) {
    final left = _normalize(candidate);
    final right = _normalize(wanted);
    if (left.isEmpty || right.isEmpty) return false;
    return left == right || left.contains(right) || right.contains(left);
  }

  bool _artistMatches(String candidate, String wanted) {
    final left = _normalize(candidate);
    final right = _normalize(wanted);
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;

    final leftWords = left.split(' ');
    final rightWords = right.split(' ');
    return rightWords.every(leftWords.contains) ||
        leftWords.every(rightWords.contains);
  }

  int _relevance(Track track, String query) {
    final title = _normalize(track.title);
    final artist = _normalize(track.artist);
    final q = _normalize(query);
    if (q.isEmpty) return 0;

    var score = 0;
    if (title == q) {
      score += 100;
    } else if (title.startsWith(q)) {
      score += 80;
    } else if (title.contains(q)) {
      score += 60;
    }

    if (artist == q) {
      score += 50;
    } else if (artist.contains(q)) {
      score += 30;
    }

    final words = q.split(' ').where((word) => word.length > 1).toList();
    if (words.isNotEmpty) {
      final haystack = '$title $artist';
      var matched = 0;
      for (final word in words) {
        if (haystack.contains(word)) matched++;
      }
      score += (matched * 20) ~/ words.length;
    }

    return score;
  }

  // --- HTTP ----------------------------------------------------------------

  Future<Map<String, dynamic>> _getJson(Uri uri, {Duration? timeout}) async {
    try {
      final response = await http
          .get(uri, headers: _headers)
          .timeout(timeout ?? _sourceTimeout);
      if (response.statusCode != 200) {
        throw ApiException(
          'Сервис вернул ошибку ${response.statusCode}.',
          response.statusCode,
        );
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map) return Map<String, dynamic>.from(body);
      throw const ApiException('Неожиданный ответ сервиса.');
    } on TimeoutException {
      throw const NetworkException();
    } on IOException {
      throw const NetworkException();
    } on http.ClientException {
      throw const NetworkException();
    }
  }

  // --- Deezer --------------------------------------------------------------

  Future<List<Track>> _deezer(String query) async {
    final body = await _getJson(
      Uri.https('api.deezer.com', '/search', {
        'q': query,
        'limit': '${AppConstants.searchLimit}',
      }),
    );
    if (body['error'] != null) {
      throw const ApiException('Deezer временно недоступен.');
    }
    final data = body['data'];
    if (data is! List) return const [];

    final tracks = <Track>[];
    for (final raw in data.whereType<Map>()) {
      final track = _deezerTrack(raw);
      if (track != null) tracks.add(track);
    }
    return tracks;
  }

  /// Похожие треки без ключа Last.fm: Deezer знает связанных исполнителей,
  /// а их популярные треки дают хорошую отправную точку для главной.
  Future<List<Track>> deezerRelatedTracks(Track seed, {int limit = 12}) async {
    final artistId = await _deezerArtistId(seed);
    if (artistId == null) return const [];

    final body = await _getJson(
      Uri.https('api.deezer.com', '/artist/$artistId/related', {'limit': '6'}),
      timeout: const Duration(seconds: 4),
    );
    final data = body['data'];
    if (data is! List) return const [];

    final relatedIds = <int>[];
    final seenIds = <int>{};
    for (final raw in data.whereType<Map>()) {
      final id = raw['id'];
      if (id is num && seenIds.add(id.toInt())) {
        relatedIds.add(id.toInt());
      }
    }
    if (relatedIds.isEmpty) return const [];

    final lists = await Future.wait([
      for (final id in relatedIds.take(5)) _deezerTopTracks(id, limit: 3),
    ]);
    final result = <Track>[];
    final seen = <String>{_dedupeKey(seed)};
    for (final track in lists.expand((list) => list)) {
      if (!seen.add(_dedupeKey(track))) continue;
      result.add(track);
      if (result.length >= limit) break;
    }
    return result;
  }

  Future<int?> _deezerArtistId(Track seed) async {
    final body = await _getJson(
      Uri.https('api.deezer.com', '/search', {
        'q': '${seed.title} ${seed.artist}',
        'limit': '10',
      }),
      timeout: const Duration(seconds: 4),
    );
    if (body['error'] != null) return null;

    final data = body['data'];
    if (data is List) {
      int? bestId;
      var bestScore = -1;
      for (final raw in data.whereType<Map>()) {
        final artist = raw['artist'];
        if (artist is! Map) continue;
        final id = artist['id'];
        if (id is! num) continue;

        final title = raw['title']?.toString() ?? '';
        final artistName = artist['name']?.toString() ?? '';
        var score = 0;
        if (_titleMatches(title, seed.title)) score += 2;
        if (_artistMatches(artistName, seed.artist)) score += 3;
        if (score > bestScore) {
          bestScore = score;
          bestId = id.toInt();
        }
      }
      // Совпадения только по названию недостаточно: у каверов другой артист.
      if (bestScore >= 3 && bestId != null) return bestId;
    }

    final artistBody = await _getJson(
      Uri.https('api.deezer.com', '/search/artist', {
        'q': seed.artist,
        'limit': '5',
      }),
      timeout: const Duration(seconds: 4),
    );
    final artists = artistBody['data'];
    if (artists is! List) return null;

    int? fallbackId;
    for (final raw in artists.whereType<Map>()) {
      final id = raw['id'];
      if (id is! num) continue;
      final name = raw['name']?.toString() ?? '';
      fallbackId ??= id.toInt();
      if (_artistMatches(name, seed.artist)) return id.toInt();
    }
    return fallbackId;
  }

  Future<List<Track>> _deezerTopTracks(
    int artistId, {
    required int limit,
  }) async {
    try {
      final body = await _getJson(
        Uri.https('api.deezer.com', '/artist/$artistId/top', {
          'limit': '$limit',
        }),
        timeout: const Duration(seconds: 4),
      );
      final data = body['data'];
      if (data is! List) return const [];

      final tracks = <Track>[];
      for (final raw in data.whereType<Map>()) {
        final track = _deezerTrack(raw);
        if (track != null) tracks.add(track);
      }
      return tracks;
    } catch (_) {
      // Один проблемный исполнитель не должен обнулять всю подборку.
      return const [];
    }
  }

  Track? _deezerTrack(Map raw) {
    final id = raw['id'];
    final title = raw['title'];
    final preview = raw['preview'];
    if (id == null ||
        title is! String ||
        title.trim().isEmpty ||
        preview is! String ||
        preview.isEmpty) {
      return null;
    }

    final artistData = raw['artist'];
    final albumData = raw['album'];
    final artist = artistData is Map && artistData['name'] is String
        ? (artistData['name'] as String).trim()
        : '';
    final cover = albumData is Map && albumData['cover_big'] is String
        ? albumData['cover_big'] as String
        : null;

    return Track.online(
      source: TrackSource.deezer,
      id: '$id',
      title: title,
      artist: artist.isEmpty ? 'Неизвестный исполнитель' : artist,
      artworkUrl: cover,
      streamUrl: preview,
      durationSec: 30,
      isPreview: true,
    );
  }

  // --- iTunes --------------------------------------------------------------

  Future<List<Track>> _itunes(String query) async {
    final body = await _getJson(
      Uri.https('itunes.apple.com', '/search', {
        'term': query,
        'media': 'music',
        'entity': 'song',
        'limit': '${AppConstants.searchLimit}',
      }),
    );
    final results = body['results'];
    if (results is! List) return const [];

    final tracks = <Track>[];
    for (final raw in results.whereType<Map>()) {
      final id = raw['trackId'];
      final title = raw['trackName'];
      final preview = raw['previewUrl'];
      if (id == null ||
          title is! String ||
          title.trim().isEmpty ||
          preview is! String ||
          preview.isEmpty) {
        continue;
      }

      final artist = raw['artistName'] is String
          ? (raw['artistName'] as String).trim()
          : '';
      final artwork = raw['artworkUrl100'];
      final cover = artwork is String
          ? artwork.replaceAll('100x100', '600x600')
          : null;

      tracks.add(
        Track.online(
          source: TrackSource.itunes,
          id: '$id',
          title: title,
          artist: artist.isEmpty ? 'Неизвестный исполнитель' : artist,
          artworkUrl: cover,
          streamUrl: preview,
          durationSec: 30,
          isPreview: true,
        ),
      );
    }
    return tracks;
  }

  // --- Jamendo -------------------------------------------------------------

  Future<List<Track>> _jamendo(String query, String clientId) async {
    final body = await _getJson(
      Uri.https('api.jamendo.com', '/v3.0/tracks/', {
        'client_id': clientId,
        'format': 'json',
        'limit': '${AppConstants.searchLimit}',
        'search': query,
        'audioformat': 'mp32',
      }),
    );

    final headers = body['headers'];
    if (headers is Map && headers['status'] == 'failed') {
      throw const ApiException('Jamendo отклонил client_id.');
    }

    final results = body['results'];
    if (results is! List) return const [];

    final tracks = <Track>[];
    for (final raw in results.whereType<Map>()) {
      final id = raw['id'];
      final title = raw['name'];
      final audio = raw['audio'];
      if (id == null ||
          title is! String ||
          title.trim().isEmpty ||
          audio is! String ||
          audio.isEmpty) {
        continue;
      }

      final artist = raw['artist_name'] is String
          ? (raw['artist_name'] as String).trim()
          : '';
      final image = raw['image'] is String ? raw['image'] as String : null;
      final duration = _toSeconds(raw['duration']);

      tracks.add(
        Track.online(
          source: TrackSource.jamendo,
          id: '$id',
          title: title,
          artist: artist.isEmpty ? 'Неизвестный исполнитель' : artist,
          artworkUrl: image,
          streamUrl: audio,
          durationSec: duration,
        ),
      );
    }
    return tracks;
  }

  // --- Internet Archive ----------------------------------------------------

  Future<List<Track>> _archive(String query) async {
    final body = await _getJson(
      Uri.https('archive.org', '/advancedsearch.php', {
        'q': '$query AND mediatype:audio',
        'fl[]': ['identifier', 'title', 'creator'],
        'rows': '10',
        'page': '1',
        'output': 'json',
      }),
    );

    final response = body['response'];
    if (response is! Map) return const [];
    final docs = response['docs'];
    if (docs is! List) return const [];

    final futures = <Future<Track?>>[
      for (final doc in docs.whereType<Map>().take(10)) _archiveTrack(doc),
    ];
    final found = await Future.wait(futures);
    return found.whereType<Track>().toList(growable: false);
  }

  Future<Track?> _archiveTrack(Map doc) async {
    try {
      final identifier = doc['identifier'];
      if (identifier is! String || identifier.isEmpty) return null;

      final meta = await _getJson(
        Uri.https('archive.org', '/metadata/$identifier'),
      ).timeout(const Duration(seconds: 5));
      final files = meta['files'];
      if (files is! List) return null;

      Map? best;
      for (final raw in files.whereType<Map>()) {
        final name = raw['name'];
        final format = raw['format'];
        if (name is! String || name.isEmpty) continue;
        if (raw['private'] == true) continue;
        final type = format is String ? format.toLowerCase() : '';
        if (!type.contains('mp3')) continue;
        best ??= raw;
        if (type.contains('vbr')) {
          best = raw;
          break;
        }
      }
      if (best == null) return null;

      final fileName = best['name'] as String;
      final title = _text(doc['title']) ?? _text(best['title']) ?? identifier;
      final artist = _text(doc['creator']) ?? 'Internet Archive';

      return Track.online(
        source: TrackSource.archive,
        id: '$identifier/$fileName',
        title: title,
        artist: artist,
        artworkUrl: 'https://archive.org/services/img/$identifier',
        streamUrl: Uri.https(
          'archive.org',
          '/download/$identifier/$fileName',
        ).toString(),
        durationSec: _toSeconds(best['length']),
      );
    } catch (_) {
      return null;
    }
  }

  String? _text(Object? value) {
    if (value is String) {
      final text = value.trim();
      return text.isEmpty ? null : text;
    }
    if (value is List) {
      for (final item in value) {
        final text = _text(item);
        if (text != null) return text;
      }
    }
    return null;
  }

  int? _toSeconds(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return num.tryParse(value)?.toInt();
    return null;
  }
}

class _SourceAttempt {
  final List<Track> tracks;
  final bool failed;
  final bool network;

  const _SourceAttempt(
    this.tracks, {
    this.failed = false,
    this.network = false,
  });
}

class _ScoredTrack {
  final Track track;
  final int score;

  const _ScoredTrack(this.track, this.score);
}

class _CachedSearch {
  final SearchOutcome outcome;
  final DateTime createdAt;

  const _CachedSearch(this.outcome, this.createdAt);
}
