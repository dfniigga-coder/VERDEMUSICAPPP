import 'track.dart';

/// Откуда удалось получить полную (или лучшую доступную) версию трека.
///
/// Это отдельная абстракция от [TrackSource]: поиск возвращает превью,
/// а резолвер сообщает UI, что именно удалось найти и как это играть.
enum FullTrackSource {
  soundcloud,
  youtube,
  deezerPreview,
  itunesPreview,
  audius,
  jamendo,
  archive,
  unknown,
}

extension FullTrackSourceInfo on FullTrackSource {
  String get label {
    switch (this) {
      case FullTrackSource.soundcloud:
        return 'SoundCloud (полный)';
      case FullTrackSource.youtube:
        return 'YouTube (полный)';
      case FullTrackSource.deezerPreview:
        return 'Deezer (превью)';
      case FullTrackSource.itunesPreview:
        return 'iTunes (превью)';
      case FullTrackSource.audius:
        return 'Audius (полный)';
      case FullTrackSource.jamendo:
        return 'Jamendo (полный)';
      case FullTrackSource.archive:
        return 'Internet Archive (полный)';
      case FullTrackSource.unknown:
        return 'Источник неизвестен';
    }
  }

  bool get isFullTrack {
    switch (this) {
      case FullTrackSource.soundcloud:
      case FullTrackSource.youtube:
      case FullTrackSource.audius:
      case FullTrackSource.jamendo:
      case FullTrackSource.archive:
        return true;
      case FullTrackSource.deezerPreview:
      case FullTrackSource.itunesPreview:
      case FullTrackSource.unknown:
        return false;
    }
  }

  TrackSource get trackSource {
    switch (this) {
      case FullTrackSource.soundcloud:
        return TrackSource.soundcloud;
      case FullTrackSource.youtube:
        return TrackSource.youtube;
      case FullTrackSource.deezerPreview:
        return TrackSource.deezer;
      case FullTrackSource.itunesPreview:
        return TrackSource.itunes;
      case FullTrackSource.audius:
        return TrackSource.audius;
      case FullTrackSource.jamendo:
        return TrackSource.jamendo;
      case FullTrackSource.archive:
        return TrackSource.archive;
      case FullTrackSource.unknown:
        return TrackSource.external;
    }
  }
}

/// Результат работы `FullTrackResolver`.
///
/// [streamUrl] заполнен для источников, которые можно отдать в just_audio
/// (SoundCloud и YouTube). Для YouTube также сохраняется [youtubeVideoId] —
/// запасной вариант со встроенным iFrame-плеером.
class ResolvedTrack {
  final String title;
  final String artist;
  final String? artworkUrl;

  /// Прямой URL аудиопотока для just_audio (SoundCloud или YouTube).
  final String? streamUrl;

  final FullTrackSource source;
  final bool isFullTrack;

  /// Идентификатор видео YouTube (11 символов), если источник — YouTube.
  final String? youtubeVideoId;

  /// Id трека в источнике (SoundCloud track id, YouTube videoId и т.п.).
  final String? externalId;

  final int? durationSec;

  const ResolvedTrack({
    required this.title,
    required this.artist,
    required this.source,
    required this.isFullTrack,
    this.artworkUrl,
    this.streamUrl,
    this.youtubeVideoId,
    this.externalId,
    this.durationSec,
  });

  /// Можно ли отдать трек в существующий just_audio/audio_service плеер.
  ///
  /// YouTube тоже играет через just_audio: сервис извлекает прямой
  /// аудиопоток, поэтому доступны фон, уведомление и экран блокировки.
  bool get canPlayInJustAudio =>
      (source == FullTrackSource.soundcloud ||
          source == FullTrackSource.youtube) &&
      streamUrl != null &&
      streamUrl!.isNotEmpty;

  /// Можно ли открыть встроенный YouTube-плеер.
  bool get canPlayInYoutube =>
      source == FullTrackSource.youtube &&
      youtubeVideoId != null &&
      youtubeVideoId!.isNotEmpty;

  /// Превращает результат в [Track], совместимый с очередью just_audio.
  ///
  /// Для YouTube поток играет через just_audio; если он недоступен,
  /// UI может открыть встроенный iFrame-плеер.
  Track toTrack({Track? fallback}) {
    return Track(
      source: source.trackSource,
      externalId: externalId ?? fallback?.externalId,
      title: title,
      artist: artist,
      artworkUrl: artworkUrl ?? fallback?.artworkUrl,
      streamUrl: streamUrl ?? fallback?.streamUrl,
      durationSec: durationSec ?? fallback?.durationSec,
      genre: fallback?.genre,
      isPreview: !isFullTrack,
    );
  }
}
