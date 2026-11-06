import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

  /// Текущий discovery-хост (из кэша → bootstrap → fallback).
  Future<String> get host async {
    final cached = _cachedHost;
    if (cached != null) return cached;

    // 1) внешний кэш хоста
    final saved = _prefs.getString(AppConstants.audiusHostKey);
    if (saved != null && saved.isNotEmpty) {
      _cachedHost = saved;
      return saved;
    }

    // 2) bootstrap: список живых discovery-серверов
    final client = http.Client();
    try {
      final res = await client
          .get(Uri.parse(AppConstants.audiusBootstrapUrl))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        final hosts = (body is Map && body['data'] is List)
            ? (body['data'] as List)
                .whereType<String>()
                .where((h) => h.startsWith('http'))
                .toList()
            : <String>[];
        if (hosts.isNotEmpty) {
          // Хост выбираем случайно, чтобы не грузить один сервер.
          final pick = hosts[Random().nextInt(hosts.length)];
          _cachedHost = pick;
          await _prefs.setString(AppConstants.audiusHostKey, pick);
          return pick;
        }
      }
    } on TimeoutException {
      // падение → fallback
    } on SocketException {
      // падение → fallback
    } catch (_) {
      // любая другая ошибка сети/парсинга → fallback
    } finally {
      client.close();
    }

    // 3) fallback
    _cachedHost = AppConstants.audiusFallbackHost;
    return _cachedHost!;
  }

  /// Прямая ссылка на поток трека. Эндпоинт отвечает 302-редиректом на mp3
  /// с CDN — just_audio корректно идёт по редиректу.
  String streamUrlFor(String audiusId) {
    final h = _cachedHost ?? AppConstants.audiusFallbackHost;
    return '$h/v1/tracks/$audiusId/stream?app_name=${AppConstants.audiusAppName}';
  }

  Future<Map<String, Object?>> _getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final h = await host;
    final uri = Uri.parse('$h/v1/$path').replace(
      queryParameters: {
        'app_name': AppConstants.audiusAppName,
        ...?query,
      },
    );

    final client = http.Client();
    try {
      final res = await client
          .get(uri)
          .timeout(const Duration(seconds: AppConstants.requestTimeoutSeconds));
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map) {
          return Map<String, Object?>.from(body);
        }
        throw const ApiException('Неожиданный ответ сервиса Audius.');
      }
      if (res.statusCode >= 500) {
        throw ApiException(
            'Сервис Audius недоступен. Попробуйте позже.', res.statusCode);
      }
      throw ApiException(
        'Сервис Audius вернул ошибку ${res.statusCode}.',
        res.statusCode,
      );
    } on TimeoutException {
      throw const NetworkException(
          'Превышено время ожидания. Проверьте соединение.');
    } on SocketException {
      throw const NetworkException();
    } on http.ClientException {
      throw const NetworkException();
    } finally {
      client.close();
    }
  }

  // --- Эндпоинты -----------------------------------------------------------

  /// Трендовые треки. `time`: week | month | allTime.
  Future<List<Track>> trending({
    String time = 'week',
    int limit = AppConstants.trendingLimit,
  }) async {
    final data = await _getJson('tracks/trending', query: {
      'time': time,
      'limit': '$limit',
    });
    return _tracksFrom(data);
  }

  /// Underground-тренды Audius.
  Future<List<Track>> underground({
    String time = 'month',
    int limit = AppConstants.trendingLimit,
  }) async {
    final data = await _getJson('tracks/trending/underground', query: {
      'time': time,
      'limit': '$limit',
    });
    return _tracksFrom(data);
  }

  /// Поиск треков по названию и исполнителю.
  Future<List<Track>> search(
    String query, {
    int limit = AppConstants.searchLimit,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final data = await _getJson('tracks/search', query: {
      'query': q,
      'limit': '$limit',
    });
    return _tracksFrom(data);
  }

  /// Трендовые плейлисты Audius (раздел «Подборки» на главной).
  Future<List<Collection>> trendingPlaylists({
    String time = 'month',
    int limit = AppConstants.playlistsLimit,
  }) async {
    final data = await _getJson('playlists/trending', query: {
      'time': time,
      'limit': '$limit',
    });
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

      final user = raw['user'] is Map ? raw['user'] as Map : const <String, String>{};
      final artwork =
          raw['artwork'] is Map ? raw['artwork'] as Map : const <String, String>{};
      final rawGenre = raw['genre'];
      final genre = rawGenre is String && rawGenre.trim().isNotEmpty
          ? rawGenre
          : null;

      return Track.audius(
        id: id,
        title: title,
        artist: (user['name'] as String?) ?? 'Неизвестный исполнитель',
        artworkUrl: (artwork['480x480'] as String?) ??
            (artwork['1000x1000'] as String?) ??
            (artwork['150x150'] as String?),
        durationSec:
            raw['duration'] is num ? (raw['duration'] as num).toInt() : null,
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
      final artwork =
          raw['artwork'] is Map ? raw['artwork'] as Map : const <String, String>{};
      return Collection(
        id: id,
        title: name,
        artworkUrl: (artwork['480x480'] as String?) ??
            (artwork['1000x1000'] as String?) ??
            (artwork['150x150'] as String?),
      );
    } catch (_) {
      return null;
    }
  }
}
