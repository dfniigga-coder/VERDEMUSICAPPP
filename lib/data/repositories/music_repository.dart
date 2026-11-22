import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../api/audius_api.dart';
import '../models/collection.dart';
import '../models/track.dart';

/// Данные для главной: тренды, андеграунд и подборки.
class HomeData {
  final List<Track> trending;
  final List<Track> underground;
  final List<Collection> playlists;

  /// true — секции взяты из кэша (сеть была недоступна).
  final bool isCached;

  const HomeData({
    required this.trending,
    required this.underground,
    required this.playlists,
    this.isCached = false,
  });

  bool get isEmpty =>
      trending.isEmpty && underground.isEmpty && playlists.isEmpty;
}

/// Репозиторий онлайн-музыки: тонкая обёртка над AudiusApi
/// с кэшем главной в shared_preferences для работы офлайн.
class MusicRepository {
  MusicRepository(this._api, this._prefs);

  final AudiusApi _api;
  final SharedPreferences _prefs;

  final Map<String, List<Track>> _playlistTracksCache = {};

  Future<List<Track>> search(String query) => _api.search(query);

  Future<List<Track>> playlistTracks(Collection collection) async {
    final cached = _playlistTracksCache[collection.id];
    if (cached != null) return cached;
    final tracks = await _api.playlistTracks(collection.id);
    _playlistTracksCache[collection.id] = tracks;
    return tracks;
  }

  /// Ссылка на поток audius-трека (используется аудио-хендлером).
  ///
  /// Бросает [TrackLoadException] вместо `null`-проверки: трек без
  /// audiusId не должен приводить к `TypeError` в глубине плеера.
  String streamUrlFor(Track track) {
    final audiusId = track.audiusId;
    if (audiusId == null || audiusId.isEmpty) {
      throw const TrackLoadException(
        'У трека нет идентификатора Audius. Выберите другой результат.',
      );
    }
    return _api.streamUrlFor(audiusId);
  }

  /// Загружает главную. Запросы идут параллельно; при ошибке сети
  /// возвращает кэш с пометкой [HomeData.isCached], иначе бросает AppException.
  Future<HomeData> loadHome() async {
    final weekF = _api.trending(time: 'week');
    final undF = _safe(_api.underground(time: 'month'));
    final plF = _safe(_api.trendingPlaylists(time: 'month'));

    try {
      final week = await weekF;
      // Вторичные секции могут не загрузиться — не роняем весь экран.
      final underground = (await undF) ?? const <Track>[];
      final playlists = (await plF) ?? const <Collection>[];
      final data = HomeData(
        trending: week,
        underground: underground,
        playlists: playlists,
      );
      await _cacheHome(data);
      return data;
    } on AppException {
      final cached = _readHomeCache();
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Съедает ошибку вторичного запроса (секция просто будет пустой).
  Future<T?> _safe<T>(Future<T> future) =>
      future.then<T?>((value) => value, onError: (Object _) => null);

  // --- Кэш -----------------------------------------------------------------

  Future<void> _cacheHome(HomeData data) async {
    try {
      final json = Map<String, Object?>.from({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'trending': Track.encodeList(data.trending),
        'underground': Track.encodeList(data.underground),
        'playlists': data.playlists
            .map(
              (c) => {
                'id': c.id,
                'title': c.title,
                'subtitle': c.subtitle,
                'art': c.artworkUrl,
              },
            )
            .toList(),
      });
      await _prefs.setString(AppConstants.homeCacheKey, jsonEncode(json));
    } catch (_) {
      // Кэш не критичен.
    }
  }

  HomeData? _readHomeCache() {
    try {
      final raw = _prefs.getString(AppConstants.homeCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final trending = Track.listFromDynamic(json['trending']);
      final underground = Track.listFromDynamic(json['underground']);
      final collections = <Collection>[];
      if (json['playlists'] is List) {
        for (final c in (json['playlists'] as List).whereType<Map>()) {
          final id = c['id'];
          final title = c['title'];
          if (id is! String || title is! String) continue;
          collections.add(
            Collection(
              id: id,
              title: title,
              subtitle: c['subtitle'] is String
                  ? c['subtitle'] as String
                  : null,
              artworkUrl: c['art'] is String ? c['art'] as String : null,
            ),
          );
        }
      }
      return HomeData(
        trending: trending,
        underground: underground,
        playlists: collections,
        isCached: true,
      );
    } catch (_) {
      return null;
    }
  }
}
