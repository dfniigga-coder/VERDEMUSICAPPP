import 'dart:convert';

/// Источник воспроизведения трека.
enum TrackSource {
  audius,
  deezer,
  itunes,
  jamendo,
  archive,
  external,
  local,
  soundcloud,
  youtube,
}

extension TrackSourceInfo on TrackSource {
  String get label {
    switch (this) {
      case TrackSource.audius:
        return 'Audius';
      case TrackSource.deezer:
        return 'Deezer';
      case TrackSource.itunes:
        return 'iTunes';
      case TrackSource.jamendo:
        return 'Jamendo';
      case TrackSource.archive:
        return 'Archive';
      case TrackSource.external:
        return 'Ссылка';
      case TrackSource.local:
        return 'Файл';
      case TrackSource.soundcloud:
        return 'SoundCloud (полный)';
      case TrackSource.youtube:
        return 'YT Music';
    }
  }
}

/// Единая модель трека для онлайн-сервисов и локальных источников.
///
/// Стабильный [id] вычисляется из источника и идентификатора, поэтому
/// его можно использовать в лайках, плейлистах и как `MediaItem.id`.
class Track {
  final TrackSource source;

  /// Id трека в Audius.
  final String? audiusId;

  /// Id трека во внешнем источнике (Deezer, iTunes, Jamendo, Archive).
  final String? externalId;

  /// Id трека в on_audio_query (для локальных треков из медиатеки).
  final int? localSongId;

  /// Абсолютный путь к файлу (для локальных треков).
  final String? localPath;

  /// Прямая ссылка на аудиопоток (для сетевых источников).
  final String? streamUrl;

  final String title;
  final String artist;
  final String? artworkUrl;
  final int? durationSec;
  final String? genre;

  /// true — доступен только короткий фрагмент (Deezer/iTunes, 30 секунд).
  final bool isPreview;

  /// Явный стабильный id. Нужен, когда трек заменяется полной версией из
  /// другого источника: лайки, плейлисты и очередь должны остаться
  /// привязанными к исходному треку.
  final String? idOverride;

  const Track({
    required this.source,
    this.audiusId,
    this.externalId,
    this.localSongId,
    this.localPath,
    this.streamUrl,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.durationSec,
    this.genre,
    this.isPreview = false,
    this.idOverride,
  });

  factory Track.audius({
    required String id,
    required String title,
    required String artist,
    String? artworkUrl,
    int? durationSec,
    String? genre,
  }) => Track(
    source: TrackSource.audius,
    audiusId: id,
    title: title,
    artist: artist,
    artworkUrl: artworkUrl,
    durationSec: durationSec,
    genre: genre,
  );

  factory Track.local({
    required int songId,
    required String title,
    required String artist,
    required String path,
    int? durationSec,
    String? artworkUrl,
  }) => Track(
    source: TrackSource.local,
    localSongId: songId,
    localPath: path,
    title: title,
    artist: artist,
    durationSec: durationSec,
    artworkUrl: artworkUrl,
  );

  /// Локальный файл, выбранный вручную через file_picker (без id медиатеки).
  factory Track.file({
    required String path,
    required String title,
    required String artist,
    int? durationSec,
    String? artworkUrl,
  }) => Track(
    source: TrackSource.local,
    localPath: path,
    title: title,
    artist: artist,
    durationSec: durationSec,
    artworkUrl: artworkUrl,
  );

  /// MP3, скачанный приложением (YouTube → MP3).
  ///
  /// Хранится как локальный файл, поэтому играет без сети и виден
  /// в «Моих треках» наравне с музыкой с телефона.
  factory Track.downloaded({
    required String path,
    required String title,
    required String artist,
    int? durationSec,
    String? artworkUrl,
  }) => Track.file(
    path: path,
    title: title,
    artist: artist,
    durationSec: durationSec,
    artworkUrl: artworkUrl,
  );

  /// Трек из поиска YouTube. [streamUrl] может быть null: прямой аудиопоток
  /// резолвится лениво перед воспроизведением.
  factory Track.youtube({
    required String videoId,
    required String title,
    required String artist,
    String? artworkUrl,
    int? durationSec,
    String? streamUrl,
  }) => Track(
    source: TrackSource.youtube,
    externalId: videoId,
    title: title,
    artist: artist,
    artworkUrl: artworkUrl,
    durationSec: durationSec,
    streamUrl: streamUrl,
  );

  /// Трек из публичного онлайн-источника.
  factory Track.online({
    required TrackSource source,
    required String id,
    required String title,
    required String artist,
    required String streamUrl,
    String? artworkUrl,
    int? durationSec,
    String? genre,
    bool isPreview = false,
  }) => Track(
    source: source,
    externalId: id,
    title: title,
    artist: artist,
    artworkUrl: artworkUrl,
    streamUrl: streamUrl,
    durationSec: durationSec,
    genre: genre,
    isPreview: isPreview,
  );

  /// Прямая ссылка, которую пользователь добавил вручную.
  factory Track.external({
    required String url,
    required String title,
    String artist = 'Неизвестный исполнитель',
    String? artworkUrl,
    int? durationSec,
  }) => Track(
    source: TrackSource.external,
    externalId: url,
    streamUrl: url,
    title: title,
    artist: artist,
    artworkUrl: artworkUrl,
    durationSec: durationSec,
  );

  bool get isAudius => source == TrackSource.audius;

  bool get isLocal => source == TrackSource.local;

  /// Стабильный идентификатор «audius:…», «deezer:…», «local:…».
  String get id {
    final override = idOverride;
    if (override != null && override.isNotEmpty) return override;

    switch (source) {
      case TrackSource.audius:
        return 'audius:${audiusId ?? externalId ?? title}';
      case TrackSource.local:
        return 'local:${localSongId ?? localPath ?? title}';
      case TrackSource.external:
        return 'external:${streamUrl ?? externalId ?? title}';
      case TrackSource.deezer:
      case TrackSource.itunes:
      case TrackSource.jamendo:
      case TrackSource.archive:
      case TrackSource.soundcloud:
      case TrackSource.youtube:
        return '${source.name}:${externalId ?? streamUrl ?? title}';
    }
  }

  Track copyWith({
    TrackSource? source,
    String? streamUrl,
    String? idOverride,
    String? title,
    String? artist,
    String? artworkUrl,
    int? durationSec,
    String? genre,
    bool? isPreview,
  }) {
    return Track(
      source: source ?? this.source,
      audiusId: audiusId,
      externalId: externalId,
      localSongId: localSongId,
      localPath: localPath,
      streamUrl: streamUrl ?? this.streamUrl,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      durationSec: durationSec ?? this.durationSec,
      genre: genre ?? this.genre,
      isPreview: isPreview ?? this.isPreview,
      idOverride: idOverride ?? this.idOverride,
    );
  }

  Map<String, Object?> toJson() => {
    'src': source.name,
    'id': idOverride,
    'sid': audiusId,
    'eid': externalId,
    'lid': localSongId,
    'p': localPath,
    'url': streamUrl,
    't': title,
    'a': artist,
    'art': artworkUrl,
    'd': durationSec,
    'g': genre,
    'prev': isPreview,
  };

  factory Track.fromJson(Map<dynamic, dynamic> json) {
    final audiusId = json['sid'] is String ? json['sid'] as String : null;
    final localSongId = json['lid'] is num
        ? (json['lid'] as num).toInt()
        : null;
    final localPath = json['p'] is String ? json['p'] as String : null;
    final streamUrl = json['url'] is String ? json['url'] as String : null;
    final source = _sourceFromJson(json, audiusId);

    return Track(
      source: source,
      audiusId: audiusId,
      externalId: json['eid'] is String ? json['eid'] as String : null,
      localSongId: localSongId,
      localPath: localPath,
      streamUrl: streamUrl,
      title: json['t'] is String ? json['t'] as String : 'Без названия',
      artist: json['a'] is String
          ? json['a'] as String
          : 'Неизвестный исполнитель',
      artworkUrl: json['art'] is String ? json['art'] as String : null,
      durationSec: json['d'] is num ? (json['d'] as num).toInt() : null,
      genre: json['g'] is String ? json['g'] as String : null,
      isPreview: json['prev'] == true,
      idOverride: json['id'] is String ? json['id'] as String : null,
    );
  }

  static TrackSource _sourceFromJson(
    Map<dynamic, dynamic> json,
    String? audiusId,
  ) {
    final raw = json['src'];
    if (raw is String) {
      for (final source in TrackSource.values) {
        if (source.name == raw) return source;
      }
    }
    if (audiusId != null) return TrackSource.audius;
    if (json['url'] is String) return TrackSource.external;
    return TrackSource.local;
  }

  static String encodeList(List<Track> tracks) =>
      jsonEncode(tracks.map((t) => t.toJson()).toList());

  /// Десериализация списка треков из JSON-строки или уже разобранного списка.
  /// Повреждённые элементы молча пропускаются.
  static List<Track> listFromDynamic(dynamic raw) {
    try {
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((m) => Track.fromJson(m))
            .toList(growable: false);
      }
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((m) => Track.fromJson(m))
              .toList(growable: false);
        }
      }
    } catch (_) {
      // Игнорируем повреждённые данные, вернём пустой список.
    }
    return const [];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Track && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
