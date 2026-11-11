import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../models/track.dart';

/// Снимок локальных треков для UI.
class LocalTracksResult {
  /// false — пользователь не дал разрешение на чтение звука.
  final bool hasPermission;

  /// true — разрешение дано, но треков нет.
  final bool isEmpty;

  final List<Track> tracks;

  const LocalTracksResult({
    required this.hasPermission,
    required this.isEmpty,
    required this.tracks,
  });

  factory LocalTracksResult.noPermission() =>
      const LocalTracksResult(hasPermission: false, isEmpty: false, tracks: []);

  factory LocalTracksResult.loaded(List<Track> tracks) => LocalTracksResult(
    hasPermission: true,
    isEmpty: tracks.isEmpty,
    tracks: tracks,
  );
}

/// Локальная библиотека: музыка из медиатеки (on_audio_query),
/// файлы, выбранные через file_picker, и прямые ссылки пользователя.
class LocalTracksRepository extends ChangeNotifier {
  LocalTracksRepository(this._onAudioQuery, this._prefs) {
    _loadSaved();
  }

  final OnAudioQuery _onAudioQuery;
  final SharedPreferences _prefs;

  List<Track> _cached = const [];
  final List<Track> _saved = [];

  /// Треки, добавленные вручную: файлы и прямые ссылки.
  List<Track> get saved => List.unmodifiable(_saved);

  /// Всё, что показываем в «Моих треках»: добавленное + медиатека.
  ///
  /// Медиатека может содержать копию скачанного трека из Music/Verde,
  /// поэтому дополнительно сравниваем название и исполнителя: иначе один
  /// и тот же MP3 появлялся бы дважды — как файл приложения и как
  /// проиндексированный MediaStore.
  List<Track> get cached {
    final savedPaths = _saved
        .map((track) => track.localPath)
        .whereType<String>()
        .toSet();
    final savedKeys = _saved.map(_trackKey).toSet();
    return List.unmodifiable([
      ..._saved,
      ..._cached.where((track) {
        final path = track.localPath;
        if (path != null && savedPaths.contains(path)) return false;
        return !savedKeys.contains(_trackKey(track));
      }),
    ]);
  }

  String _trackKey(Track track) =>
      '${track.title.trim().toLowerCase()}|'
      '${track.artist.trim().toLowerCase()}';

  /// Ищет уже сохранённый MP3 с тем же названием и исполнителем.
  ///
  /// Нужно, чтобы автозапуск превью не создавал второй файл, если трек
  /// уже скачивали вручную или он попал в «Мои треки» из Music/Verde.
  Track? findDownloaded(Track track) {
    if (track.isLocal) return track;

    final key = _trackKey(track);
    final titleKey = track.title.trim().toLowerCase();
    final unknownArtist = _isUnknownArtist(track.artist);
    for (final candidate in [..._saved, ..._cached]) {
      if (!candidate.isLocal) continue;

      // Если исполнитель неизвестен, сравниваем только название:
      // при скачивании сервис мог подставить реального исполнителя.
      final sameTrack = _trackKey(candidate) == key;
      final sameTitle =
          unknownArtist && candidate.title.trim().toLowerCase() == titleKey;
      if (!sameTrack && !sameTitle) continue;

      final path = candidate.localPath;
      if (path == null || path.isEmpty) continue;

      try {
        if (!File(path).existsSync()) continue;
      } catch (_) {
        // Недоступный путь (например, отключённая SD-карта) пропускаем.
        continue;
      }
      return candidate;
    }
    return null;
  }

  bool _isUnknownArtist(String artist) {
    final value = artist.trim().toLowerCase();
    return value.isEmpty ||
        value == 'неизвестный исполнитель' ||
        value == 'unknown artist';
  }

  bool get hasLoaded => _cached.isNotEmpty || _saved.isNotEmpty;

  /// Проверяет разрешение и запрашивает его при необходимости.
  Future<bool> ensurePermission({bool retryRequest = false}) async {
    return _onAudioQuery.checkAndRequest(retryRequest: retryRequest);
  }

  Future<LocalTracksResult> loadTracks({bool retryRequest = false}) async {
    final hasPermission = await ensurePermission(retryRequest: retryRequest);
    if (!hasPermission) {
      notifyListeners();
      return LocalTracksResult(
        hasPermission: false,
        isEmpty: _saved.isEmpty,
        tracks: List.unmodifiable(_saved),
      );
    }

    final songs = await _onAudioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    final scanned = <Track>[];
    for (final song in songs) {
      final mapped = _mapSong(song);
      if (mapped != null) scanned.add(mapped);
    }
    _cached = scanned;
    notifyListeners();

    return LocalTracksResult.loaded(cached);
  }

  /// Добавляет выбранные вручную файлы. Возвращает число новых треков.
  Future<int> addFiles(List<String> paths) async {
    final existing = _saved.map((track) => track.id).toSet();
    var added = 0;

    for (final rawPath in paths) {
      final path = rawPath.trim();
      if (path.isEmpty) continue;

      final track = _trackFromPath(path);
      if (existing.contains(track.id)) continue;

      _saved.add(track);
      existing.add(track.id);
      added++;
    }

    if (added > 0) {
      await _persistSaved();
      notifyListeners();
    }
    return added;
  }

  /// Добавляет скачанный приложением MP3 в «Мои треки».
  ///
  /// В отличие от [addFiles], сохраняет нормальные название, исполнителя,
  /// длительность и обложку, а не разбирает имя файла.
  Future<bool> addDownloadedTrack({
    required String path,
    required String title,
    required String artist,
    int? durationSec,
    String? artworkUrl,
  }) async {
    final track = Track.downloaded(
      path: path,
      title: title,
      artist: artist,
      durationSec: durationSec,
      artworkUrl: artworkUrl,
    );
    if (_saved.any((item) => item.id == track.id)) return false;

    _saved.insert(0, track);
    await _persistSaved();
    notifyListeners();
    return true;
  }

  /// Добавляет прямую ссылку на MP3. false — ссылка уже есть в библиотеке.
  Future<bool> addStreamUrl(String url) async {
    final clean = url.trim();
    final uri = Uri.tryParse(clean);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return false;
    }

    final track = Track.external(url: clean, title: _titleFromUrl(uri));
    if (_saved.any((item) => item.id == track.id)) return false;

    _saved.add(track);
    await _persistSaved();
    notifyListeners();
    return true;
  }

  Track? _mapSong(SongModel song) {
    try {
      final path = song.data;
      if (path.isEmpty) return null;

      final rawTitle = song.title.trim();
      final title = rawTitle.isEmpty ? 'Без названия' : rawTitle;
      final artist = song.artist;
      final cleanArtist =
          (artist == null ||
              artist.trim().isEmpty ||
              artist.trim() == '<unknown>')
          ? 'Неизвестный исполнитель'
          : artist.trim();
      final durationMs = song.duration;
      final secs = durationMs == null ? null : (durationMs ~/ 1000);

      return Track.local(
        songId: song.id,
        title: title,
        artist: cleanArtist,
        path: path,
        durationSec: secs,
      );
    } catch (_) {
      return null;
    }
  }

  Track _trackFromPath(String path) {
    var name = path.split('/').last;
    name = name.replaceAll(RegExp(r'\.[a-zA-Z0-9]{2,5}$'), '').trim();

    var artist = 'Файл на устройстве';
    var title = name;

    final separator = name.indexOf(' - ');
    if (separator > 0) {
      artist = name.substring(0, separator).trim();
      title = name.substring(separator + 3).trim();
    }

    if (title.isEmpty) title = name.isEmpty ? 'Аудиофайл' : name;
    if (artist.isEmpty) artist = 'Файл на устройстве';

    return Track.file(path: path, title: title, artist: artist);
  }

  String _titleFromUrl(Uri uri) {
    var name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    try {
      name = Uri.decodeComponent(name);
    } catch (_) {
      // Имя из URL может быть повреждено — оставляем как есть.
    }
    name = name
        .replaceAll(RegExp(r'\.[a-zA-Z0-9]{2,5}$'), '')
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .trim();
    return name.isEmpty ? 'Трек по ссылке' : name;
  }

  void _loadSaved() {
    try {
      final raw = _prefs.getString(AppConstants.importedTracksKey);
      final loaded = Track.listFromDynamic(
        raw,
      ).where((track) => track.isLocal || track.source == TrackSource.external);
      _saved
        ..clear()
        ..addAll(loaded);
    } catch (_) {
      // Повреждённый список не должен ломать приложение.
      _saved.clear();
    }
  }

  Future<void> _persistSaved() async {
    try {
      await _prefs.setString(
        AppConstants.importedTracksKey,
        Track.encodeList(_saved),
      );
    } catch (_) {
      // Хранилище не критично для воспроизведения.
    }
  }

  /// Обложка локального трека (байты). null — обложки нет.
  Future<Uint8List?> artwork(int songId) {
    return _onAudioQuery.queryArtwork(
      songId,
      ArtworkType.AUDIO,
      size: 512,
      quality: 90,
    );
  }
}
