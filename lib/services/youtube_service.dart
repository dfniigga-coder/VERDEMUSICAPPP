import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../data/models/track.dart';
import 'youtube_link.dart';

/// Прямой аудиопоток YouTube, пригодный для just_audio и скачивания.
class YoutubeAudio {
  final String videoId;
  final String url;
  final String container;
  final int bitrateBps;
  final int sizeBytes;

  const YoutubeAudio({
    required this.videoId,
    required this.url,
    required this.container,
    required this.bitrateBps,
    required this.sizeBytes,
  });

  /// Расширение для временного файла: m4a для MP4/AAC, иначе webm и т.п.
  String get fileExtension =>
      container == 'mp4' ? 'm4a' : (container.isEmpty ? 'webm' : container);
}

/// Найденное видео YouTube с уже очищенными названием и исполнителем.
class YoutubeMatch {
  final String videoId;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int? durationSec;

  const YoutubeMatch({
    required this.videoId,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.durationSec,
  });
}

/// Клиент YouTube без API-ключа.
///
/// Умеет:
/// - искать видео и превращать их в полноценные треки для поиска;
/// - находить лучший ролик под название/исполнителя (для превью Deezer/iTunes);
/// - отдавать прямой аудиопоток для just_audio;
/// - скачивать аудиодорожку во временный файл.
///
/// Потоки YouTube живут несколько часов, поэтому URL кэшируются примерно
/// на час. Ошибки не превращаются в исключения на уровне UI: вызывающая
/// сторона сама решает, показать сообщение или продолжить без YouTube.
class YoutubeService {
  YoutubeService({YoutubeExplode? client})
    : _youtube = client ?? YoutubeExplode();

  static const Duration _audioCacheTtl = Duration(hours: 1);
  static const Duration _searchCacheTtl = Duration(minutes: 10);
  static const Duration _searchTimeout = Duration(seconds: 9);

  /// Короткие Shorts и бесконечные эфиры/монтажи отбрасываются, но длинные
  /// музыкальные вещи (сюиты, живые джемы) остаются доступными.
  static const int _minDurationSec = 20;
  static const int _maxDurationSec = 60 * 60;
  static const Duration _manifestTimeout = Duration(seconds: 25);

  final YoutubeExplode _youtube;

  final Map<String, _CachedAudio> _audioCache = {};
  final Map<String, Future<AudioOnlyStreamInfo?>> _audioInFlight = {};

  String? _cachedSearchQuery;
  List<Track> _cachedSearchResults = const [];
  DateTime? _cachedSearchAt;

  bool _disposed = false;

  /// Поиск YouTube, результат уже в форме [Track].
  ///
  /// Живые трансляции, короткие Shorts и многоминутные миксы отбрасываются:
  /// для музыкального поиска они только мешают.
  Future<List<Track>> searchTracks(String query, {int limit = 10}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final cachedAt = _cachedSearchAt;
    if (_cachedSearchQuery == q &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _searchCacheTtl) {
      return _cachedSearchResults;
    }

    final results = await _youtube.search.search(q).timeout(_searchTimeout);

    final tracks = <Track>[];
    final seen = <String>{};

    for (final video in results) {
      if (video.isLive) continue;
      final durationSec = video.duration?.inSeconds;
      if (durationSec != null &&
          (durationSec < _minDurationSec || durationSec > _maxDurationSec)) {
        continue;
      }

      final parsed = YoutubeTitleParser.parse(video.title, video.author);
      final key =
          '${parsed.title.toLowerCase()}|${parsed.artist.toLowerCase()}';
      if (key.trim() == '|' || !seen.add(key)) continue;

      tracks.add(
        Track.youtube(
          videoId: video.id.value,
          title: parsed.title,
          artist: parsed.artist,
          artworkUrl: video.thumbnails.highResUrl,
          durationSec: durationSec,
        ),
      );
      if (tracks.length >= limit) break;
    }

    _cachedSearchQuery = q;
    _cachedSearchResults = List.unmodifiable(tracks);
    _cachedSearchAt = DateTime.now();
    return _cachedSearchResults;
  }

  /// Находит лучший ролик под трек. Если известен [preferredVideoId]
  /// (трек пришёл из поиска YouTube), поиск не выполняется.
  Future<YoutubeMatch?> findBest(
    String title,
    String artist, {
    int? durationSec,
    String? preferredVideoId,
    int minDurationSec = _minDurationSec,
  }) async {
    final cleanTitle = title.trim();
    final cleanArtist = artist.trim();
    final preferred = preferredVideoId?.trim();
    final minDuration = minDurationSec.clamp(_minDurationSec, _maxDurationSec);

    if (preferred != null && preferred.isNotEmpty) {
      return YoutubeMatch(
        videoId: preferred,
        title: cleanTitle,
        artist: cleanArtist,
        artworkUrl: 'https://img.youtube.com/vi/$preferred/hqdefault.jpg',
        durationSec: durationSec,
      );
    }

    final query = [
      cleanTitle,
      cleanArtist,
    ].where((part) => part.isNotEmpty).join(' ').trim();
    if (query.isEmpty) return null;

    final results = await _youtube.search.search(query).timeout(_searchTimeout);

    _ScoredVideo? best;
    for (final video in results) {
      if (video.isLive) continue;
      final candidateDuration = video.duration?.inSeconds;
      if (candidateDuration != null &&
          (candidateDuration < minDuration ||
              candidateDuration > _maxDurationSec)) {
        continue;
      }

      final parsed = YoutubeTitleParser.parse(video.title, video.author);
      final score = _score(
        parsed: parsed,
        rawTitle: video.title,
        channel: video.author,
        durationSec: candidateDuration,
        wantedTitle: cleanTitle,
        wantedArtist: cleanArtist,
        wantedDuration: durationSec,
      );

      if (best == null || score > best.score) {
        best = _ScoredVideo(
          match: YoutubeMatch(
            videoId: video.id.value,
            title: parsed.title,
            artist: parsed.artist,
            artworkUrl: video.thumbnails.highResUrl,
            durationSec: candidateDuration,
          ),
          score: score,
        );
      }
    }

    if (best == null) return null;
    return best.match;
  }

  /// Метаданные конкретного видео по id — для скачивания по ссылке.
  ///
  /// У YouTube Music в watch page есть блок `musicData`: название и
  /// исполнитель уже разложены по полям, поэтому он приоритетнее
  /// разбора заголовка вида «Artist - Song».
  Future<YoutubeMatch> resolveVideo(String videoId) async {
    final id = videoId.trim();
    if (!YoutubeLink.isVideoId(id)) {
      throw const YoutubeException('Некорректная ссылка на видео YouTube.');
    }

    final Video video;
    try {
      video = await _youtube.videos.get(id).timeout(_manifestTimeout);
    } catch (error) {
      debugPrint('YoutubeService: resolve $id failed: $error');
      throw const YoutubeException(
        'Не удалось получить информацию о видео. Проверьте ссылку и соединение.',
      );
    }

    if (video.isLive) {
      throw const YoutubeException(
        'Прямые трансляции нельзя скачать как трек.',
      );
    }

    final durationSec = video.duration?.inSeconds;
    if (durationSec != null && durationSec > _maxDurationSec) {
      throw const YoutubeException(
        'Видео длиннее часа — для одного MP3 это слишком много.',
      );
    }

    final parsed = YoutubeTitleParser.parse(video.title, video.author);
    final music = video.musicData.isEmpty ? null : video.musicData.first;
    final musicTitle = music?.song?.trim();
    // В structured description исполнитель иногда идёт как
    // «Artist • Album» — для тега оставляем только исполнителя.
    final musicArtist = music?.artist
        ?.split(RegExp(r'\s*[•·]\s*'))
        .first
        .trim();

    return YoutubeMatch(
      videoId: video.id.value,
      title: musicTitle != null && musicTitle.isNotEmpty
          ? musicTitle
          : parsed.title,
      artist: musicArtist != null && musicArtist.isNotEmpty
          ? musicArtist
          : parsed.artist,
      artworkUrl: video.thumbnails.highResUrl,
      durationSec: durationSec,
    );
  }

  /// Прямой аудиопоток для just_audio.
  ///
  /// По умолчанию выбирается MP4/AAC: он максимально совместим с Android.
  /// Для скачивания запрашивается самый качественный поток (часто Opus).
  Future<YoutubeAudio?> audioFor(
    String videoId, {
    bool preferMp4 = true,
  }) async {
    final info = await _streamInfo(videoId, preferMp4: preferMp4);
    if (info == null) return null;
    return YoutubeAudio(
      videoId: videoId,
      url: info.url.toString(),
      container: info.container.name,
      bitrateBps: info.bitrate.bitsPerSecond,
      sizeBytes: info.size.totalBytes,
    );
  }

  /// Скачивает аудиодорожку во временный файл.
  ///
  /// [onProgress] получает 0.0–1.0, если YouTube сообщил размер файла.
  /// При обрыве/истёкшем URL делает одну повторную попытку со свежим
  /// манифестом.
  Future<File> downloadAudio(
    String videoId, {
    required Directory directory,
    void Function(double? progress)? onProgress,
  }) async {
    await directory.create(recursive: true);
    Object? lastError;

    for (var attempt = 0; attempt < 2; attempt++) {
      final info = await _streamInfo(
        videoId,
        preferMp4: false,
        forceRefresh: attempt > 0,
      );
      if (info == null) {
        throw const YoutubeException('Не удалось получить аудио с YouTube.');
      }

      final file = File(
        '${directory.path}/verde_${DateTime.now().microsecondsSinceEpoch}'
        '.${info.container.name == 'mp4' ? 'm4a' : info.container.name}',
      );

      try {
        await _writeStream(
          _youtube.videos.streams.get(info),
          file,
          totalBytes: info.size.totalBytes,
          onProgress: onProgress,
        );
        if (await file.length() == 0) {
          throw const YoutubeException('YouTube вернул пустой аудиофайл.');
        }
        return file;
      } catch (error) {
        lastError = error;
        _audioCache.remove(_cacheKey(videoId, preferMp4: false));
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {
            // Временный файл не критичен.
          }
        }
        if (attempt == 0) {
          debugPrint('YoutubeService: download retry for $videoId: $error');
          continue;
        }
      }
    }

    debugPrint('YoutubeService: download failed for $videoId: $lastError');
    throw YoutubeException(
      'Не удалось скачать аудио с YouTube. Попробуйте ещё раз.',
    );
  }

  Future<void> _writeStream(
    Stream<List<int>> stream,
    File file, {
    required int totalBytes,
    void Function(double? progress)? onProgress,
  }) async {
    final sink = file.openWrite();
    var received = 0;
    var lastProgressAt = -1000;
    final clock = Stopwatch()..start();
    try {
      await for (final chunk in stream.timeout(const Duration(seconds: 45))) {
        sink.add(chunk);
        received += chunk.length;

        // Не дёргаем UI на каждый сетевой пакет: при быстрой загрузке
        // это сотни перестроений в секунду и заметный лишний расход CPU.
        final now = clock.elapsedMilliseconds;
        if (totalBytes > 0) {
          if (now - lastProgressAt >= 100 || received >= totalBytes) {
            lastProgressAt = now;
            onProgress?.call((received / totalBytes).clamp(0.0, 1.0));
          }
        } else if (now - lastProgressAt >= 250) {
          lastProgressAt = now;
          onProgress?.call(null);
        }
      }
      await sink.flush();
      if (totalBytes > 0 && received < totalBytes) {
        throw const YoutubeException('Загрузка с YouTube оборвалась.');
      }
    } finally {
      await sink.close();
    }
  }

  Future<AudioOnlyStreamInfo?> _streamInfo(
    String videoId, {
    required bool preferMp4,
    bool forceRefresh = false,
  }) {
    if (_disposed) return Future.value(null);

    final key = _cacheKey(videoId, preferMp4: preferMp4);
    if (!forceRefresh) {
      final cached = _audioCache[key];
      if (cached != null && !cached.isExpired) {
        return Future.value(cached.info);
      }
    } else {
      _audioCache.remove(key);
    }

    final running = _audioInFlight[key];
    if (running != null) return running;

    final future = _loadStreamInfo(videoId, preferMp4: preferMp4)
        .then<AudioOnlyStreamInfo?>((info) => info)
        .catchError((Object error, StackTrace stack) {
          debugPrint('YoutubeService: manifest for $videoId failed: $error');
          return null;
        })
        .then((info) {
          if (info != null) {
            _audioCache[key] = _CachedAudio(
              info,
              DateTime.now().add(_audioCacheTtl),
            );
          }
          return info;
        });

    _audioInFlight[key] = future;
    unawaited(
      future.whenComplete(() {
        _audioInFlight.remove(key);
      }),
    );
    return future;
  }

  Future<AudioOnlyStreamInfo> _loadStreamInfo(
    String videoId, {
    required bool preferMp4,
  }) async {
    final manifest = await _youtube.videos.streams
        .getManifest(videoId, requireWatchPage: false)
        .timeout(_manifestTimeout);

    final candidates = manifest.audioOnly
        .where((stream) => stream.url.toString().isNotEmpty)
        .toList(growable: false);
    if (candidates.isEmpty) {
      throw const YoutubeException('У видео нет доступных аудиодорожек.');
    }

    final sorted = candidates.toList(growable: false)
      ..sort((a, b) {
        if (preferMp4) {
          final aMp4 = a.container.name == 'mp4';
          final bMp4 = b.container.name == 'mp4';
          if (aMp4 != bMp4) return aMp4 ? -1 : 1;
        }
        return b.bitrate.compareTo(a.bitrate);
      });
    return sorted.first;
  }

  String _cacheKey(String videoId, {required bool preferMp4}) =>
      '$videoId|${preferMp4 ? 'mp4' : 'best'}';

  int _score({
    required YoutubeTitle parsed,
    required String rawTitle,
    required String channel,
    required int? durationSec,
    required String wantedTitle,
    required String wantedArtist,
    required int? wantedDuration,
  }) {
    final title = _normalize(parsed.title);
    final raw = _normalize(rawTitle);
    final artist = _normalize(parsed.artist);
    final wanted = _normalize(wantedTitle);
    final wantedArtistNorm = _normalize(wantedArtist);
    final channelNorm = _normalize(channel);

    var score = 0;

    if (title == wanted) {
      score += 100;
    } else if (title.contains(wanted) || wanted.contains(title)) {
      score += 65;
    } else if (_tokensOverlap(title, wanted)) {
      score += 25;
    } else if (raw.contains(wanted)) {
      score += 15;
    }

    if (wantedArtistNorm.isNotEmpty) {
      if (artist == wantedArtistNorm ||
          channelNorm == wantedArtistNorm ||
          channelNorm.contains(wantedArtistNorm)) {
        score += 55;
      } else if (artist.contains(wantedArtistNorm) ||
          wantedArtistNorm.contains(artist) ||
          channelNorm.contains(artist)) {
        score += 30;
      } else if (_tokensOverlap(artist, wantedArtistNorm) ||
          _tokensOverlap(channelNorm, wantedArtistNorm)) {
        score += 15;
      }
    }

    if (wantedDuration != null && durationSec != null) {
      final delta = (durationSec - wantedDuration).abs();
      if (delta <= 5) {
        score += 35;
      } else if (delta <= 15) {
        score += 20;
      } else if (delta <= 40) {
        score += 5;
      } else {
        score -= 10;
      }
    }

    final rawLower = rawTitle.toLowerCase();
    if (rawLower.contains('official audio') ||
        rawLower.contains('official video') ||
        rawLower.contains('topic')) {
      score += 10;
    }
    if (rawLower.contains('live') ||
        rawLower.contains('karaoke') ||
        rawLower.contains('instrumental') ||
        rawLower.contains('reaction')) {
      score -= 35;
    }

    return score;
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _tokensOverlap(String left, String right) {
    final leftTokens = left
        .split(' ')
        .where((token) => token.length > 2)
        .toSet();
    final rightTokens = right
        .split(' ')
        .where((token) => token.length > 2)
        .toSet();
    return leftTokens.intersection(rightTokens).isNotEmpty;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _youtube.close();
  }
}

/// Очищает типичные YouTube-заголовки:
/// «Artist - Song (Official Video)» → title: «Song», artist: «Artist».
class YoutubeTitleParser {
  YoutubeTitleParser._();

  static final RegExp _brackets = RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]');
  static final RegExp _trailingNoise = RegExp(
    r'\s*(?:\b(?:official\s+)?(?:music\s+)?(?:video|audio|lyrics?|'
    r'lyric\s+video|visualizer|remaster(?:ed)?|version|4k|8k|hd|hq)\b)\s*$',
    caseSensitive: false,
  );

  static YoutubeTitle parse(String rawTitle, String author) {
    var work = rawTitle.replaceAll(_brackets, ' ');
    work = work.replaceAll(RegExp(r'\s+'), ' ').trim();

    final separator = RegExp(r'\s+[-–—]\s+').firstMatch(work);
    if (separator != null) {
      final left = _clean(work.substring(0, separator.start));
      final right = _clean(work.substring(separator.end));
      if (left.isNotEmpty && right.isNotEmpty) {
        // В подавляющем большинстве музыкальных роликов формат
        // «Исполнитель - Название». Если слева явно название, а справа
        // исполнитель, канал всё равно поможет не потерять трек.
        return YoutubeTitle(title: right, artist: left);
      }
    }

    final cleaned = _clean(work);
    final channel = _cleanChannel(author);
    return YoutubeTitle(
      title: cleaned.isEmpty ? rawTitle.trim() : cleaned,
      artist: channel.isEmpty ? 'YouTube' : channel,
    );
  }

  static String _cleanChannel(String author) {
    // Официальные аудио-каналы YouTube называются «Artist - Topic»,
    // а VEVO-каналы — «ArtistVEVO».
    return author
        .trim()
        .replaceFirst(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*VEVO$', caseSensitive: false), '')
        .trim();
  }

  static String _clean(String value) {
    var result = value;
    // Иногда «Official Video» идёт без скобок и даже повторяется.
    for (var i = 0; i < 3; i++) {
      final next = result.replaceFirst(_trailingNoise, '').trim();
      if (next == result) break;
      result = next;
    }
    result = result
        .replaceAll(RegExp(r'[|•·]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s\-–—:]+|[\s\-–—:]+$'), '')
        .trim();
    return result;
  }
}

class YoutubeTitle {
  final String title;
  final String artist;

  const YoutubeTitle({required this.title, required this.artist});
}

class YoutubeException implements Exception {
  final String message;

  const YoutubeException(this.message);

  @override
  String toString() => message;
}

class _CachedAudio {
  final AudioOnlyStreamInfo info;
  final DateTime expiresAt;

  const _CachedAudio(this.info, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class _ScoredVideo {
  final YoutubeMatch match;
  final int score;

  const _ScoredVideo({required this.match, required this.score});
}
