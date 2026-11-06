import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../models/collection.dart';
import '../models/track.dart';

/// Клиент Audius API.
///
/// Хост выбирается через bootstrap-адрес api.audius.co, поэтому ключи
/// API не нужны. Все запросы легальны — публичный каталог Audius.
class AudiusApi {
  AudiusApi(this._prefs);

  final SharedPreferences _prefs;

  String? _cachedHost;
  final List<String> _bootstrapHosts = [];
  Future<void>? _bootstrapFuture;

  /// Текущий discovery-хост (из кэша → bootstrap → fallback).
  Future<String> get host async {
    final hosts = await _candidateHosts();
    return hosts.first;
  }

  /// Список хостов в порядке предпочтения: сначала рабочий/сохранённый,
  /// затем discovery-серверы из bootstrap и fallback.
  Future<List<String>> _candidateHosts() async {
    final hosts = <String>[];

    void add(String? value) {
      if (value == null || value.isEmpty || hosts.contains(value)) return;
      hosts.add(value);
    }

    add(_cachedHost);
    add(_prefs.getString(AppConstants.audiusHostKey));

    if (hosts.isEmpty) {
      await _loadBootstrapHosts();
    }
    for (final host in _bootstrapHosts) {
      add(host);
    }
    if (_bootstrapHosts.isEmpty) add(AppConstants.audiusFallbackHost);
    return hosts;
  }

  Future<void> _loadBootstrapHosts() {
    return _bootstrapFuture ??= _fetchBootstrapHosts();
  }

  Future<void> _fetchBootstrapHosts() async {
    final client = http.Client();
    try {
      final res = await client
          .get(Uri.parse(AppConstants.audiusBootstrapUrl))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final data = body is Map ? body['data'] : null;
      if (data is! List) return;
      for (final raw in data) {
        if (raw is! String || !raw.startsWith('http')) continue;
        if (!_bootstrapHosts.contains(raw)) _bootstrapHosts.add(raw);
      }
    } catch (_) {
      // bootstrap не критичен: ниже используем fallback.
    } finally {
      client.close();
    }
  }

  void _rememberHost(String host) {
    _cachedHost = host;
    unawaited(_prefs.setString(AppConstants.audiusHostKey, host));
  }

  /// Прямая ссылка на поток трека. Эндпоинт отвечает 302-редиректом на mp3
  /// с CDN — just_audio корректно идёт по редиректу.
  String streamUrlFor(String audiusId) {
    final h =
        _cachedHost ??
        _prefs.getString(AppConstants.audiusHostKey) ??
        AppConstants.audiusFallbackHost;
    return '$h/v1/tracks/$audiusId/stream?app_name=${AppConstants.audiusAppName}';
  }

  Future<Map<String, Object?>> _getJson(
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(
      seconds: AppConstants.requestTimeoutSeconds,
    ),
  }) async {
    final tried = <String>{};
    Object? lastError;

    for (var round = 0; round < 2; round++) {
      final hosts = await _candidateHosts();
      var triedNewHost = false;

      for (final h in hosts) {
        if (!tried.add(h)) continue;
        triedNewHost = true;

        final client = http.Client();
        try {
          final uri = Uri.parse('$h/v1/$path').replace(
            queryParameters: {
              'app_name': AppConstants.audiusAppName,
              ...?query,
            },
          );
          final res = await client.get(uri).timeout(timeout);
          if (res.statusCode == 200) {
            final body = jsonDecode(utf8.decode(res.bodyBytes));
            if (body is Map) {
              _rememberHost(h);
              return Map<String, Object?>.from(body);
            }
            lastError = const ApiException('Неожиданный ответ сервиса Audius.');
          } else if (res.statusCode >= 500) {
            lastError = ApiException(
              'Сервис Audius недоступен. Попробуйте позже.',
              res.statusCode,
            );
          } else {
            lastError = ApiException(
              'Сервис Audius вернул ошибку ${res.statusCode}.',
              res.statusCode,
            );
          }
        } on TimeoutException {
          lastError = const NetworkException(
            'Превышено время ожидания. Проверьте соединение.',
          );
        } on IOException {
          lastError = const NetworkException();
        } on http.ClientException {
          lastError = const NetworkException();
        } finally {
          client.close();
        }
      }

      // Если сохранённый хост не ответил, получаем полный список
      // discovery-серверов и пробуем следующий хост из него.
      if (round == 0 && _bootstrapHosts.isEmpty) {
        await _loadBootstrapHosts();
        if (_bootstrapHosts.isNotEmpty) continue;
      }
      if (!triedNewHost) break;
      if (round == 1) break;
    }

    if (lastError is AppException) throw lastError;
    throw const NetworkException();
  }

  // --- Эндпоинты -----------------------------------------------------------

  /// Трендовые треки. `time`: week | month | allTime.
  Future<List<Track>> trending({
    String time = 'week',
    int limit = AppConstants.trendingLimit,
  }) async {
    final data = await _getJson(
      'tracks/trending',
      query: {'time': time, 'limit': '$limit'},
    );
    return _tracksFrom(data);
  }

  /// Underground-тренды Audius.
  Future<List<Track>> underground({
    String time = 'month',
    int limit = AppConstants.trendingLimit,
  }) async {
    final data = await _getJson(
      'tracks/trending/underground',
      query: {'time': time, 'limit': '$limit'},
    );
    return _tracksFrom(data);
  }

  /// Поиск треков по названию и исполнителю.
  Future<List<Track>> search(
    String query, {
    int limit = AppConstants.searchLimit,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final data = await _getJson(
      'tracks/search',
      query: {'query': q, 'limit': '$limit'},
      // Даём шанс переключиться на следующий хост в рамках общего
      // восьмисекундного таймаута источника поиска.
      timeout: const Duration(seconds: 3),
    );
    return _tracksFrom(data);
  }

  /// Трендовые плейлисты Audius (раздел «Подборки» на главной).
  Future<List<Collection>> trendingPlaylists({
    String time = 'month',
    int limit = AppConstants.playlistsLimit,
  }) async {
    final data = await _getJson(
      'playlists/trending',
      query: {'time': time, 'limit': '$limit'},
    );
    return _collectionsFrom(data);
  }

  /// Треки плейлиста Audius.
  Future<List<Track>> playlistTracks(String playlistId) async {
    final data = await _getJson('playlists/$playlistId/tracks');
    return _tracksFrom(data);
  }

  // --- Парсинг -------------------------------------------------------------

  static List<Track> _tracksFrom(Map<String, Object?> data) {
    final list = data['data'];
    if (list is! List) return const [];
    return list.map(_trackFromJson).whereType<Track>().toList(growable: false);
  }

  static Track? _trackFromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      final id = raw['id'] as String?;
      final title = raw['title'] as String?;
      if (id == null || title == null || title.isEmpty) return null;

      final user = raw['user'] is Map
          ? raw['user'] as Map
          : const <String, String>{};
      final artwork = raw['artwork'] is Map
          ? raw['artwork'] as Map
          : const <String, String>{};
      final rawGenre = raw['genre'];
      final genre = rawGenre is String && rawGenre.trim().isNotEmpty
          ? rawGenre
          : null;

      return Track.audius(
        id: id,
        title: title,
        artist: (user['name'] as String?) ?? 'Неизвестный исполнитель',
        artworkUrl:
            (artwork['480x480'] as String?) ??
            (artwork['1000x1000'] as String?) ??
            (artwork['150x150'] as String?),
        durationSec: raw['duration'] is num
            ? (raw['duration'] as num).toInt()
            : null,
        genre: genre,
      );
    } catch (_) {
      return null;
    }
  }

  static List<Collection> _collectionsFrom(Map<String, Object?> data) {
    final list = data['data'];
    if (list is! List) return const [];
    return list
        .map(_collectionFromJson)
        .whereType<Collection>()
        .toList(growable: false);
  }

  static Collection? _collectionFromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      final id = raw['id'] as String?;
      final name = raw['playlist_name'] as String?;
      if (id == null || name == null || name.isEmpty) return null;
      final artwork = raw['artwork'] is Map
          ? raw['artwork'] as Map
          : const <String, String>{};
      return Collection(
        id: id,
        title: name,
        artworkUrl:
            (artwork['480x480'] as String?) ??
            (artwork['1000x1000'] as String?) ??
            (artwork['150x150'] as String?),
      );
    } catch (_) {
      return null;
    }
  }
}
