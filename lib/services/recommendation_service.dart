import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../data/api/search_api.dart';
import '../data/models/track.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/local_tracks_repository.dart';

const Duration _requestTimeout = Duration(seconds: 8);

/// Безопасный сетевой вызов: 8 секунд, try/catch и только debugPrint.
/// Ошибки не пробрасываются в UI — рекомендации просто получаются пустыми.
Future<T?> safeRequest<T>(
  String label,
  Future<T> Function() request, {
  Duration timeout = _requestTimeout,
  void Function(Object error)? onError,
}) async {
  try {
    return await request().timeout(timeout);
  } on TimeoutException catch (error) {
    debugPrint(
      '[RecommendationService] $label: таймаут ${timeout.inSeconds} с',
    );
    onError?.call(error);
    return null;
  } catch (error) {
    debugPrint('[RecommendationService] $label: $error');
    onError?.call(error);
    return null;
  }
}

/// Готовая секция главного экрана.
class RecommendationSection {
  final String title;
  final String? subtitle;
  final List<Track> tracks;

  const RecommendationSection({
    required this.title,
    required this.tracks,
    this.subtitle,
  });
}

/// Результат сборки главного экрана.
class HomeRecommendations {
  final List<RecommendationSection> sections;

  /// true — есть история, лайки или локальная музыка.
  final bool hasTaste;

  const HomeRecommendations({required this.sections, required this.hasTaste});

  bool get isEmpty => sections.isEmpty;
}

/// Локальный рекомендательный движок без внешнего сервера.
///
/// История хранится в shared_preferences (до 300 событий), потому что
/// этого достаточно для быстрых агрегатов и не нужна SQL-база.
/// Last.fm используется только для похожих треков; Deezer/iTunes — для
/// получения актуального streamUrl и обложек.
class RecommendationService {
  RecommendationService({
    required SharedPreferences prefs,
    required SearchApi searchApi,
    required LibraryRepository library,
    required LocalTracksRepository localTracks,
    http.Client? httpClient,
  }) : _prefs = prefs,
       _searchApi = searchApi,
       _library = library,
       _localTracks = localTracks,
       _http = httpClient ?? http.Client() {
    _loadHistory();
  }

  final SharedPreferences _prefs;
  final SearchApi _searchApi;
  final LibraryRepository _library;
  final LocalTracksRepository _localTracks;
  final http.Client _http;

  final List<_HistoryEntry> _history = [];
  int _revision = 0;

  /// Меняется после каждой записи прослушивания. Главная сравнивает
  /// ревизию и обновляет секции при возврате на вкладку.
  int get revision => _revision;

  static const int _maxHistoryEntries = 300;
  static const Duration _repeatWindow = Duration(seconds: 45);
  static const Duration _listenAgainAfter = Duration(days: 3);
  static const Duration _artistWindow = Duration(days: 30);
  static const Duration _similarCacheTtl = Duration(minutes: 20);
  static const int _maxSimilarCacheEntries = 24;

  /// Похожие для одного и того же семени не меняются каждые несколько
  /// секунд. Кэш экономит десятки запросов при возврате на главную.
  final Map<String, _CachedTracks> _similarCache = {};

  /// Deezer/iTunes — превью и обложки; для похожих добавляем Audius,
  /// где иногда находится полная версия.
  static const Set<TrackSource> _previewSources = {
    TrackSource.deezer,
    TrackSource.itunes,
  };
  static const Set<TrackSource> _similarSources = {
    TrackSource.deezer,
    TrackSource.itunes,
    TrackSource.audius,
  };

  bool get hasTaste =>
      _history.isNotEmpty ||
      _library.likedTracks.isNotEmpty ||
      _hasPlaylistTracks ||
      _localTracks.cached.isNotEmpty;

  bool get _hasPlaylistTracks =>
      _library.playlists.any((playlist) => playlist.tracks.isNotEmpty);

  int get historyLength => _history.length;

  /// Вызывается из PlayerProvider при старте трека и смене текущего индекса.
  Future<void> recordPlay(Track track) async {
    if (track.title.trim().isEmpty) return;

    final now = DateTime.now();
    // Очередь иногда перезагружается, и индекс приходит дважды.
    // Короткое окно не даёт записать один и тот же старт два раза.
    _history.removeWhere(
      (entry) =>
          entry.track.id == track.id &&
          now.difference(entry.playedAt) < _repeatWindow,
    );
    _history.insert(0, _HistoryEntry(track, now));
    if (_history.length > _maxHistoryEntries) {
      _history.removeRange(_maxHistoryEntries, _history.length);
    }
    _revision++;
    await _saveHistory();
  }

  Future<void> clearHistory() async {
    _history.clear();
    _revision++;
    try {
      await _prefs.remove(AppConstants.playHistoryKey);
    } catch (error) {
      debugPrint('[RecommendationService] clear history: $error');
    }
  }

  /// 6–8 знакомых/подходящих треков по топ-3 исполнителям.
  Future<List<Track>> getQuickPicks() async {
    final artists = _topArtists(3);
    if (artists.isEmpty) return const [];

    final lists = await Future.wait([
      for (final artist in artists) _quickPickCandidates(artist),
    ]);

    final result = <Track>[];
    final seen = <String>{};

    // Круговая выборка не даёт первому исполнителю занять всю секцию.
    var round = 0;
    var added = true;
    while (added && result.length < 8) {
      added = false;
      for (final list in lists) {
        if (round >= list.length) continue;
        final track = list[round];
        if (seen.add(_dedupeKey(track))) {
          result.add(track);
          added = true;
          if (result.length >= 8) break;
        }
      }
      round++;
    }

    if (result.length < 6) {
      _fillSuggestions(result, seen, _mostPlayedTracks(20), 6);
      _fillSuggestions(result, seen, _library.likedTracks, 6);
      _fillSuggestions(result, seen, _localTracks.cached, 6);
    }

    return result.take(8).toList(growable: false);
  }

  /// Треки, которые давно не слушались. URL Deezer обновляем:
  /// подписанные preview-ссылки со временем истекают.
  Future<List<Track>> getListenAgain() async {
    final candidates = _listenAgainCandidates();
    if (candidates.isEmpty) return const [];

    final refreshed = await Future.wait(candidates.map(_refreshForPlayback));
    final unique = <String, Track>{};
    for (final track in refreshed) {
      unique.putIfAbsent(track.id, () => track);
    }
    return unique.values.toList(growable: false);
  }

  /// Похожие треки для конкретной песни пользователя.
  ///
  /// Сначала используется Last.fm `track.getsimilar`, если задан ключ.
  /// Без ключа или при пустом ответе включаются связанные исполнители
  /// Deezer и другие треки того же артиста — главная остаётся полезной
  /// даже без внешней настройки.
  Future<List<Track>> getSimilarTracks(Track seed) async {
    final cacheKey =
        '${_dedupeKey(seed)}|${_lastFmApiKey.isEmpty ? 'fallback' : 'lastfm'}';
    final cached = _similarCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) < _similarCacheTtl) {
      return cached.tracks;
    }

    final result =
        await safeRequest(
          'Similar ${seed.title}',
          () => _buildSimilarTracks(seed),
          timeout: const Duration(seconds: 10),
        ) ??
        const <Track>[];

    if (result.isNotEmpty) {
      _similarCache[cacheKey] = _CachedTracks(result, DateTime.now());
      if (_similarCache.length > _maxSimilarCacheEntries) {
        _similarCache.remove(_similarCache.keys.first);
      }
    }
    return result;
  }

  Future<List<Track>> _buildSimilarTracks(Track seed) async {
    final result = <Track>[];
    final seen = <String>{_dedupeKey(seed)};

    void addAll(Iterable<Track> tracks) {
      for (final track in tracks) {
        if (!_isPlayable(track)) continue;
        if (seen.add(_dedupeKey(track))) result.add(track);
      }
    }

    final lastFm = await _lastFmSimilar(seed);
    if (lastFm.isNotEmpty) {
      final resolved = await Future.wait([
        for (final item in lastFm.take(6)) _resolveSimilar(item),
      ]);
      addAll(resolved.whereType<Track>());
    }

    if (result.length < 6) {
      final fallback = await Future.wait([
        _deezerRelated(seed),
        _sameArtistTracks(seed),
      ]);
      for (final list in fallback) {
        addAll(list);
        if (result.length >= 10) break;
      }
    }

    final known = _knownKeys();
    final fresh = <Track>[
      for (final track in result)
        if (!known.contains(_dedupeKey(track))) track,
    ];
    final picked = fresh.length >= 4 ? fresh : result;

    // Полные треки ставим первыми: «Играть все» не должно превращаться
    // в один 30-секундный фрагмент из-за превью в начале подборки.
    final ordered = <Track>[
      for (final track in picked)
        if (!track.isPreview) track,
      for (final track in picked)
        if (track.isPreview) track,
    ];
    return ordered.take(10).toList(growable: false);
  }

  Future<List<Track>> _deezerRelated(Track seed) async {
    final tracks = await safeRequest(
      'Deezer related ${seed.title}',
      () => _searchApi.deezerRelatedTracks(seed),
    );
    return tracks ?? const [];
  }

  Future<List<Track>> _sameArtistTracks(Track seed) async {
    final outcome = await safeRequest(
      'More from ${seed.artist}',
      () => _searchApi.searchSources(seed.artist, sources: _similarSources),
    );
    if (outcome == null) return const [];

    final tracks = _tracksForArtist(outcome.tracks, seed.artist);
    final candidates = <Track>[
      for (final track in tracks)
        if (_dedupeKey(track) != _dedupeKey(seed)) track,
    ];
    final ordered = <Track>[
      for (final track in candidates)
        if (!track.isPreview) track,
      for (final track in candidates)
        if (track.isPreview) track,
    ];
    return ordered.take(8).toList(growable: false);
  }

  /// Ежедневный микс: быстрые подборки + похожие на несколько ваших песен
  /// + «слушайте снова».
  Future<List<Track>> getDailyMix() async {
    final seeds = _tasteSeeds(limit: 2);
    final futures = <Future<List<Track>>>[
      getQuickPicks(),
      getListenAgain(),
      for (final seed in seeds) getSimilarTracks(seed),
    ];
    final results = await Future.wait(futures);
    final quick = results[0];
    final again = results[1];
    final similar = <Track>[
      for (var i = 0; i < seeds.length; i++) ...results[i + 2],
    ];
    return _mix(quick, similar, again);
  }

  /// Полная сборка главной: все секции считаются один раз.
  ///
  /// Алгоритм идёт не от «топ-исполнителя», а от конкретных песен
  /// пользователя: история, лайки и локальная медиатека дают семена,
  /// к каждому из них подбираются похожие треки.
  Future<HomeRecommendations> loadHome() async {
    final seeds = _tasteSeeds(limit: 2);
    final futures = <Future<List<Track>>>[
      getQuickPicks(),
      getListenAgain(),
      for (final seed in seeds) getSimilarTracks(seed),
    ];
    final results = await Future.wait(futures);
    final quick = results[0];
    final again = results[1];
    final similar = <List<Track>>[
      for (var i = 0; i < seeds.length; i++) results[i + 2],
    ];

    final forYou = _forYou(similar);
    final sections = <RecommendationSection>[];
    final used = <String>{for (final track in forYou) _dedupeKey(track)};

    if (forYou.isNotEmpty) {
      sections.add(
        RecommendationSection(
          title: 'Для вас',
          subtitle: seeds.isEmpty
              ? 'Подборка на основе вашей музыки'
              : 'Похоже на ваши песни',
          tracks: forYou,
        ),
      );
    }

    var rails = 0;
    for (var i = 0; i < seeds.length; i++) {
      final source = similar[i];
      if (source.length < 3) continue;

      var tracks = <Track>[
        for (final track in source)
          if (!used.contains(_dedupeKey(track))) track,
      ];
      // Если после «Для вас» почти ничего не осталось, лучше показать
      // повтор, чем пустую секцию.
      if (tracks.length < 3) tracks = source;
      if (tracks.length < 3) continue;

      sections.add(
        RecommendationSection(
          title: 'Похоже на «${seeds[i].title}»',
          subtitle: '${seeds[i].artist} · на основе вашей музыки',
          tracks: tracks,
        ),
      );
      for (final track in tracks) {
        used.add(_dedupeKey(track));
      }
      rails++;
      if (rails >= 2) break;
    }

    if (quick.isNotEmpty) {
      sections.add(
        RecommendationSection(
          title: 'Любимые исполнители',
          subtitle: 'Треки от знакомых артистов',
          tracks: quick,
        ),
      );
    }
    if (again.isNotEmpty) {
      sections.add(
        RecommendationSection(
          title: 'Слушайте снова',
          subtitle: 'Давно не звучали в Verde',
          tracks: again,
        ),
      );
    }

    return HomeRecommendations(sections: sections, hasTaste: hasTaste);
  }

  // --- Быстрый выбор -------------------------------------------------------

  Future<List<Track>> _quickPickCandidates(_ArtistTaste artist) async {
    final known = <Track>[];
    final familiar = <Track>[
      ..._localTracks.cached,
      ..._library.likedTracks,
      ..._library.playlists.expand((playlist) => playlist.tracks),
    ];
    for (final track in familiar) {
      if (_artistMatches(track.artist, artist.name) && _isPlayable(track)) {
        known.add(track);
        if (known.length >= 2) break;
      }
    }

    final outcome = await safeRequest(
      'Quick Picks ${artist.name}',
      () => _searchApi.searchSources(artist.name, sources: _previewSources),
    );
    final online = outcome == null
        ? const <Track>[]
        : _tracksForArtist(outcome.tracks, artist.name);

    final result = <Track>[];
    final seen = <String>{};
    for (final track in [...known, ...online.take(3)]) {
      if (seen.add(_dedupeKey(track))) result.add(track);
    }
    return result;
  }

  List<Track> _tracksForArtist(List<Track> tracks, String artist) {
    final matches = <Track>[
      for (final track in tracks)
        if (_isPlayable(track) && _artistMatches(track.artist, artist)) track,
    ];
    if (matches.isEmpty) return const [];

    // По задаче сначала Deezer/iTunes; полные Audius/Jamendo — как бонус.
    final preferred = <Track>[
      for (final track in matches)
        if (track.source == TrackSource.deezer ||
            track.source == TrackSource.itunes)
          track,
    ];
    final ordered = preferred.isNotEmpty
        ? <Track>[
            ...preferred,
            for (final track in matches)
              if (track.source != TrackSource.deezer &&
                  track.source != TrackSource.itunes)
                track,
          ]
        : matches;

    final result = <Track>[];
    final seen = <String>{};
    for (final track in ordered) {
      if (seen.add(_dedupeKey(track))) result.add(track);
    }
    return result;
  }

  // --- Слушайте снова ------------------------------------------------------

  List<Track> _listenAgainCandidates() {
    final now = DateTime.now();
    final latest = <String, _HistoryEntry>{};
    final counts = <String, int>{};
    for (final entry in _history) {
      latest.putIfAbsent(entry.track.id, () => entry);
      counts[entry.track.id] = (counts[entry.track.id] ?? 0) + 1;
    }

    final candidates =
        latest.values
            .where(
              (entry) => now.difference(entry.playedAt) >= _listenAgainAfter,
            )
            .toList()
          ..sort((a, b) {
            final byDate = b.playedAt.compareTo(a.playedAt);
            if (byDate != 0) return byDate;
            return (counts[b.track.id] ?? 0).compareTo(counts[a.track.id] ?? 0);
          });

    return candidates
        .take(10)
        .map((entry) => entry.track)
        .toList(growable: false);
  }

  Future<Track> _refreshForPlayback(Track track) async {
    if (track.source != TrackSource.deezer) return track;

    final outcome = await safeRequest(
      'Refresh Deezer ${track.title}',
      () => _searchApi.searchSources(
        '${track.title} ${track.artist}',
        sources: _previewSources,
      ),
    );
    if (outcome == null) return track;

    final match = _pickBest(outcome.tracks, track.title, track.artist);
    if (match == null) return track;

    final refreshed = match.id == track.id
        ? match
        : match.copyWith(idOverride: track.id);
    _updateHistoryTrack(track, refreshed);
    return refreshed;
  }

  void _updateHistoryTrack(Track oldTrack, Track newTrack) {
    var changed = false;
    for (var i = 0; i < _history.length; i++) {
      final entry = _history[i];
      if (entry.track.id == oldTrack.id) {
        _history[i] = _HistoryEntry(newTrack, entry.playedAt);
        changed = true;
      }
    }
    if (changed) unawaited(_saveHistory());
  }

  // --- Похожие -------------------------------------------------------------

  Future<List<_SimilarSeed>> _lastFmSimilar(Track seed) async {
    final apiKey = _lastFmApiKey;
    if (apiKey.isEmpty) {
      debugPrint(
        '[RecommendationService] Last.fm: API key не задан, '
        'используем связанных исполнителей Deezer',
      );
      return const [];
    }

    final uri = Uri.https('ws.audioscrobbler.com', '/2.0/', {
      'method': 'track.getsimilar',
      'artist': seed.artist,
      'track': seed.title,
      'api_key': apiKey,
      'format': 'json',
      'limit': '10',
      'autocorrect': '1',
    });

    final body = await safeRequest<Map<String, dynamic>>(
      'Last.fm similar ${seed.title}',
      () async {
        final response = await _http.get(uri);
        if (response.statusCode != 200) {
          throw http.ClientException(
            'Last.fm вернул ${response.statusCode}',
            uri,
          );
        }
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map) {
          throw const FormatException('Last.fm: неожиданный ответ');
        }
        return Map<String, dynamic>.from(decoded);
      },
    );
    if (body == null) return const [];

    if (body['error'] != null) {
      debugPrint(
        '[RecommendationService] Last.fm error: ${body['message'] ?? ''}',
      );
      return const [];
    }

    final container = body['similartracks'] ?? body['similarTracks'];
    if (container is! Map) return const [];

    final rawTracks = container['track'];
    final List<dynamic> rawItems;
    if (rawTracks is List) {
      rawItems = rawTracks;
    } else if (rawTracks is Map) {
      rawItems = [rawTracks];
    } else {
      return const [];
    }

    final result = <_SimilarSeed>[];
    for (final raw in rawItems.whereType<Map>()) {
      final name = raw['name']?.toString().trim() ?? '';
      final artistRaw = raw['artist'];
      var artist = '';
      if (artistRaw is Map) {
        artist = artistRaw['name']?.toString().trim() ?? '';
      } else if (artistRaw != null) {
        artist = artistRaw.toString().trim();
      }
      if (name.isEmpty || artist.isEmpty) continue;
      if (_normalize(name) == _normalize(seed.title) &&
          _artistMatches(artist, seed.artist)) {
        continue;
      }
      result.add(_SimilarSeed(name, artist));
    }
    return result;
  }

  Future<Track?> _resolveSimilar(_SimilarSeed item) async {
    final outcome = await safeRequest(
      'Similar ${item.title}',
      () => _searchApi.searchSources(
        '${item.title} ${item.artist}',
        sources: _similarSources,
      ),
    );
    if (outcome == null) return null;
    return _pickBest(outcome.tracks, item.title, item.artist);
  }

  // --- Ежедневный микс -----------------------------------------------------

  List<Track> _mix(List<Track> quick, List<Track> similar, List<Track> again) {
    final pool = <Track>[
      ...quick,
      ...similar,
      ...again,
      ..._mostPlayedTracks(20),
      ..._library.likedTracks,
      ..._library.playlists.expand((playlist) => playlist.tracks),
      ..._localTracks.cached,
    ];
    final seen = <String>{};
    final mixed = <Track>[];
    for (final track in pool) {
      if (_isPlayable(track) && seen.add(_dedupeKey(track))) {
        mixed.add(track);
      }
    }
    mixed.shuffle(Random(_dailySeed()));
    return mixed.take(20).toList(growable: false);
  }

  int _dailySeed() {
    final now = DateTime.now();
    final start = DateTime(now.year, 1, 1);
    return now.year * 1000 + now.difference(start).inDays;
  }

  /// Общий микс «Для вас»: три лучших похожих трека от каждого семени.
  /// Остальные похожие остаются для отдельных секций «Похоже на …»,
  /// поэтому подборки не повторяют друг друга.
  List<Track> _forYou(List<List<Track>> similar) {
    final result = <Track>[];
    final seen = <String>{};

    void add(Track track) {
      if (!_isPlayable(track)) return;
      if (seen.add(_dedupeKey(track))) result.add(track);
    }

    const perSeedLimit = 3;
    for (var round = 0; round < perSeedLimit; round++) {
      for (final list in similar) {
        if (round >= list.length) continue;
        add(list[round]);
      }
    }

    result.shuffle(Random(_dailySeed()));
    return result;
  }

  // --- Вкусы и статистика --------------------------------------------------

  List<_ArtistTaste> _topArtists(int limit) {
    final scores = <String, _ArtistTaste>{};

    void add(String rawName, int weight) {
      final name = _cleanArtist(rawName);
      if (name == null) return;
      final key = _normalize(name);
      if (key.isEmpty) return;
      final current = scores[key];
      scores[key] = current == null
          ? _ArtistTaste(name, weight)
          : _ArtistTaste(current.name, current.weight + weight);
    }

    final since = DateTime.now().subtract(_artistWindow);
    for (final entry in _history) {
      if (entry.playedAt.isAfter(since)) {
        add(entry.track.artist, 1);
      }
    }
    for (final track in _library.likedTracks) {
      add(track.artist, 3);
    }

    // Локальная библиотека может быть большой — ограничиваем вклад
    // одного исполнителя, чтобы она не перебивала реальные прослушивания.
    final localWeights = <String, _ArtistTaste>{};
    for (final track in _localTracks.cached) {
      final name = _cleanArtist(track.artist);
      if (name == null) continue;
      final key = _normalize(name);
      final current = localWeights[key];
      if (current == null) {
        localWeights[key] = _ArtistTaste(name, 1);
      } else if (current.weight < 4) {
        localWeights[key] = _ArtistTaste(current.name, current.weight + 1);
      }
    }
    for (final item in localWeights.values) {
      add(item.name, item.weight);
    }

    final ranked = scores.values.toList()
      ..sort((a, b) => b.weight.compareTo(a.weight));
    return ranked.take(limit).toList(growable: false);
  }

  /// Несколько песен-семян (по умолчанию до трёх): недавние прослушивания,
  /// лайки, плейлисты и локальная музыка.
  ///
  /// Один артист сначала даёт только одно семя, иначе главная превращается
  /// в дискографию случайного исполнителя. Если музыки мало, ограничение
  /// снимается, чтобы подборки вообще появились.
  List<Track> _tasteSeeds({int limit = 3}) {
    final now = DateTime.now();
    final since = now.subtract(const Duration(days: 180));
    final candidates = <String, _SeedCandidate>{};

    void add(Track track, int weight, {DateTime? playedAt}) {
      if (!_isPlayable(track)) return;
      if (_cleanArtist(track.artist) == null) return;
      if (track.title.trim().isEmpty) return;

      final key = _dedupeKey(track);
      final current = candidates[key];
      if (current == null) {
        candidates[key] = _SeedCandidate(track, weight, playedAt);
        return;
      }
      candidates[key] = _SeedCandidate(
        current.track,
        current.weight + weight,
        _latestDate(current.lastPlayed, playedAt),
      );
    }

    for (final entry in _history) {
      if (entry.playedAt.isBefore(since)) continue;
      final days = now.difference(entry.playedAt).inDays;
      final recency = days <= 7
          ? 3
          : days <= 30
          ? 2
          : 1;
      add(entry.track, 1 + recency, playedAt: entry.playedAt);
    }
    for (final track in _library.likedTracks) {
      add(track, 6);
    }
    var playlistCount = 0;
    for (final playlist in _library.playlists) {
      for (final track in playlist.tracks) {
        if (playlistCount++ >= 120) break;
        add(track, 3);
      }
      if (playlistCount >= 120) break;
    }
    for (final track in _localTracks.cached) {
      add(track, 2);
    }

    final ranked = candidates.values.toList()
      ..sort((a, b) {
        final byWeight = b.weight.compareTo(a.weight);
        if (byWeight != 0) return byWeight;

        final aDate = a.lastPlayed;
        final bDate = b.lastPlayed;
        if (aDate != null && bDate != null) {
          final byDate = bDate.compareTo(aDate);
          if (byDate != 0) return byDate;
        } else if (aDate != null) {
          return -1;
        } else if (bDate != null) {
          return 1;
        }
        return a.track.title.compareTo(b.track.title);
      });

    final result = <_SeedCandidate>[];
    final usedArtists = <String>{};
    for (final candidate in ranked) {
      if (result.length >= limit) break;
      final artist = _normalize(candidate.track.artist);
      if (!usedArtists.add(artist)) continue;
      result.add(candidate);
    }
    if (result.length < limit) {
      for (final candidate in ranked) {
        if (result.length >= limit) break;
        if (result.contains(candidate)) continue;
        result.add(candidate);
      }
    }
    return [for (final candidate in result) candidate.track];
  }

  Set<String> _knownKeys() {
    final keys = <String>{};
    void addAll(Iterable<Track> tracks) {
      for (final track in tracks) {
        keys.add(_dedupeKey(track));
      }
    }

    addAll(_history.map((entry) => entry.track));
    addAll(_library.likedTracks);
    addAll(_library.playlists.expand((playlist) => playlist.tracks));
    addAll(_localTracks.cached);
    return keys;
  }

  List<Track> _mostPlayedTracks(int limit) {
    final stats = <String, _TrackStat>{};
    for (final entry in _history) {
      final current = stats[entry.track.id];
      if (current == null) {
        stats[entry.track.id] = _TrackStat(entry.track, 1, entry.playedAt);
      } else {
        stats[entry.track.id] = _TrackStat(
          current.track,
          current.count + 1,
          entry.playedAt.isAfter(current.lastPlayed)
              ? entry.playedAt
              : current.lastPlayed,
        );
      }
    }
    final ranked = stats.values.toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        return b.lastPlayed.compareTo(a.lastPlayed);
      });
    return ranked.take(limit).map((item) => item.track).toList(growable: false);
  }

  // --- Выбор и нормализация ------------------------------------------------

  Track? _pickBest(List<Track> tracks, String title, String artist) {
    final wantedTitle = _normalize(title);
    final wantedArtist = _normalize(artist);
    if (wantedTitle.isEmpty || wantedArtist.isEmpty) return null;

    Track? best;
    var bestScore = -1;
    for (final track in tracks) {
      if (!_isPlayable(track)) continue;
      final candidateTitle = _normalize(track.title);
      final candidateArtist = _normalize(track.artist);
      if (!_titleMatches(candidateTitle, wantedTitle)) continue;
      if (!_artistMatches(track.artist, artist)) continue;

      var score = 0;
      if (candidateTitle == wantedTitle) {
        score += 100;
      } else if (candidateTitle.contains(wantedTitle)) {
        score += 60;
      } else {
        score += 30;
      }
      if (candidateArtist == wantedArtist) {
        score += 100;
      } else {
        score += 40;
      }
      if (!track.isPreview) score += 20;
      if (track.artworkUrl != null && track.artworkUrl!.isNotEmpty) {
        score += 2;
      }
      if (score > bestScore) {
        bestScore = score;
        best = track;
      }
    }
    return best;
  }

  void _fillSuggestions(
    List<Track> result,
    Set<String> seen,
    List<Track> source,
    int limit,
  ) {
    for (final track in source) {
      if (result.length >= limit) return;
      if (_isPlayable(track) && seen.add(_dedupeKey(track))) {
        result.add(track);
      }
    }
  }

  bool _isPlayable(Track track) {
    if (track.isLocal) {
      return track.localPath?.isNotEmpty ?? false;
    }
    if (track.isAudius) return true;
    return track.streamUrl?.isNotEmpty ?? false;
  }

  bool _titleMatches(String candidate, String wanted) {
    if (candidate.isEmpty || wanted.isEmpty) return false;
    return candidate == wanted ||
        candidate.contains(wanted) ||
        wanted.contains(candidate);
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

  String? _cleanArtist(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return null;
    final normalized = _normalize(name);
    if (normalized.isEmpty) return null;

    const ignored = {
      'неизвестный исполнитель',
      'файл на устройстве',
      'unknown artist',
      'various artists',
    };
    if (ignored.contains(normalized)) return null;
    return name;
  }

  String _dedupeKey(Track track) =>
      '${_normalize(track.title)}|${_normalize(track.artist)}';

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9а-яё]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  DateTime? _latestDate(DateTime? left, DateTime? right) {
    if (left == null) return right;
    if (right == null) return left;
    return right.isAfter(left) ? right : left;
  }

  String get _lastFmApiKey {
    final stored = _prefs.getString(AppConstants.lastFmApiKeyKey)?.trim() ?? '';
    if (stored.isNotEmpty) return stored;
    return AppConstants.lastFmApiKeyFromEnv.trim();
  }

  // --- История -------------------------------------------------------------

  void _loadHistory() {
    final raw = _prefs.getString(AppConstants.playHistoryKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded.whereType<Map>()) {
        final trackRaw = item['track'];
        final playedAt = item['at'];
        if (trackRaw is! Map || playedAt is! num) continue;
        try {
          _history.add(
            _HistoryEntry(
              Track.fromJson(trackRaw),
              DateTime.fromMillisecondsSinceEpoch(playedAt.toInt()),
            ),
          );
        } catch (_) {
          // Одна повреждённая запись не должна ломать всю историю.
        }
      }
      _history.sort((a, b) => b.playedAt.compareTo(a.playedAt));
      if (_history.length > _maxHistoryEntries) {
        _history.removeRange(_maxHistoryEntries, _history.length);
      }
    } catch (error) {
      debugPrint('[RecommendationService] history load: $error');
      _history.clear();
    }
  }

  Future<void> _saveHistory() async {
    try {
      final raw = jsonEncode([
        for (final entry in _history)
          {
            'track': entry.track.toJson(),
            'at': entry.playedAt.millisecondsSinceEpoch,
          },
      ]);
      await _prefs.setString(AppConstants.playHistoryKey, raw);
    } catch (error) {
      debugPrint('[RecommendationService] history save: $error');
    }
  }
}

class _HistoryEntry {
  final Track track;
  final DateTime playedAt;

  const _HistoryEntry(this.track, this.playedAt);
}

class _ArtistTaste {
  final String name;
  final int weight;

  const _ArtistTaste(this.name, this.weight);
}

class _TrackStat {
  final Track track;
  final int count;
  final DateTime lastPlayed;

  const _TrackStat(this.track, this.count, this.lastPlayed);
}

class _SeedCandidate {
  final Track track;
  final int weight;
  final DateTime? lastPlayed;

  const _SeedCandidate(this.track, this.weight, this.lastPlayed);
}

class _CachedTracks {
  final List<Track> tracks;
  final DateTime createdAt;

  const _CachedTracks(this.tracks, this.createdAt);
}

class _SimilarSeed {
  final String title;
  final String artist;

  const _SimilarSeed(this.title, this.artist);
}
