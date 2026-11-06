import 'dart:typed_data';

import 'package:on_audio_query/on_audio_query.dart';

import '../models/track.dart';

/// Снимок локальных треков для UI.
class LocalTracksResult {
  /// false — пользователь не дал разрешение на чтение звука.
  final bool hasPermission;

  /// true — разрешение дано, но на устройстве нет музыки.
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

/// Локальные аудиофайлы с телефона (on_audio_query).
class LocalTracksRepository {
  LocalTracksRepository(this._onAudioQuery);

  final OnAudioQuery _onAudioQuery;

  List<Track> _cached = const [];

  /// Кэш последней успешной загрузки — используется для счётчика в библиотеке.
  List<Track> get cached => List.unmodifiable(_cached);

  bool get hasLoaded => _cached.isNotEmpty;

  /// Проверяет разрешение и запрашивает его при необходимости.
  Future<bool> ensurePermission({bool retryRequest = false}) async {
    return _onAudioQuery.checkAndRequest(retryRequest: retryRequest);
  }

  Future<LocalTracksResult> loadTracks() async {
    final hasPermission = await ensurePermission();
    if (!hasPermission) return LocalTracksResult.noPermission();

    final songs = await _onAudioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    final tracks = <Track>[];
    for (final song in songs) {
      final mapped = _mapSong(song);
      if (mapped != null) tracks.add(mapped);
    }
    _cached = tracks;
    return LocalTracksResult.loaded(tracks);
  }

  Track? _mapSong(SongModel song) {
    try {
      final path = song.data;
      if (path.isEmpty) return null;

      final title = song.title.trim().isEmpty ? 'Без названия' : song.title;
      final artist = song.artist;
      final cleanArtist = (artist == null ||
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
