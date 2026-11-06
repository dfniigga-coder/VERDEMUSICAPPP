import 'dart:convert';

/// Источник воспроизведения трека.
enum TrackSource { audius, local }

/// Единая модель трека для онлайн- (Audius) и локальных источников.
///
/// Стабильный [id] вычисляется из источника и идентификатора, поэтому
/// его можно использовать в лайках, плейлистах и как `MediaItem.id`.
class Track {
  final String? audiusId;

  /// Id трека в on_audio_query (для локальных треков).
  final int? localSongId;

  /// Абсолютный путь к файлу (только для локальных треков).
  final String? localPath;

  final String title;
  final String artist;
  final String? artworkUrl;
  final int? durationSec;
  final String? genre;

  const Track({
    this.audiusId,
    this.localSongId,
    this.localPath,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.durationSec,
    this.genre,
  });

  factory Track.audius({
    required String id,
    required String title,
    required String artist,
    String? artworkUrl,
    int? durationSec,
    String? genre,
  }) =>
      Track(
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
  }) =>
      Track(
        localSongId: songId,
        localPath: path,
        title: title,
        artist: artist,
        durationSec: durationSec,
      );

  bool get isAudius => audiusId != null;

  TrackSource get source =>
      audiusId != null ? TrackSource.audius : TrackSource.local;

  /// Стабильный идентификатор «audius:...» или «local:...».
  String get id {
    if (audiusId != null) return 'audius:$audiusId';
    return 'local:${localSongId ?? 0}';
  }

  Track copyWith({
    String? title,
    String? artist,
    String? artworkUrl,
    int? durationSec,
    String? genre,
  }) {
    return Track(
      audiusId: audiusId,
      localSongId: localSongId,
      localPath: localPath,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      durationSec: durationSec ?? this.durationSec,
      genre: genre ?? this.genre,
    );
  }

  Map<String, Object?> toJson() => {
        'sid': audiusId,
        'lid': localSongId,
        'p': localPath,
        't': title,
        'a': artist,
        'art': artworkUrl,
        'd': durationSec,
        'g': genre,
      };

  factory Track.fromJson(Map<dynamic, dynamic> json) {
    return Track(
      audiusId: json['sid'] is String ? json['sid'] as String : null,
      localSongId: json['lid'] is num ? (json['lid'] as num).toInt() : null,
      localPath: json['p'] is String ? json['p'] as String : null,
      title: (json['t'] as String?) ?? 'Без названия',
      artist: (json['a'] as String?) ?? 'Неизвестный исполнитель',
      artworkUrl: json['art'] is String ? json['art'] as String : null,
      durationSec: json['d'] is num ? (json['d'] as num).toInt() : null,
      genre: json['g'] is String ? json['g'] as String : null,
    );
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
