import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
  YoutubeService({YoutubeExplode? client, http.Client? httpClient})
    : _youtube = client ?? YoutubeExplode(),
      _http = httpClient ?? http.Client(),
      _ownsHttpClient = httpClient == null;

  static const Duration _audioCacheTtl = Duration(hours: 1);
  static const Duration _searchCacheTtl = Duration(minutes: 10);
  static const Duration _searchTimeout = Duration(seconds: 9);

  /// Короткие Shorts и бесконечные эфиры/монтажи отбрасываются, но длинные
  /// музыкальные вещи (сюиты, живые джемы) остаются доступными.
  static const int _minDurationSec = 20;
  static const int _maxDurationSec = 60 * 60;
  static const Duration _manifestTimeout = Duration(seconds: 25);

  /// Таймауты скачивания аудио. Длинный таймаут здесь опасен: при
  /// заблокированном googlevideo прогресс просто стоит на нуле.
  static const Duration _headersTimeout = Duration(seconds: 8);
  static const Duration _chunkTimeout = Duration(seconds: 20);

  /// YouTube без PO-токена отдаёт только небольшие куски файла.
  /// 64 КиБ — проверенный размер, который проходит для таких ссылок.
  static const int _directChunkBytes = 64 * 1024;

  static const String _browserUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  /// Публичные Invidious-инстансы умеют проксировать аудио через себя
  /// (`local=true`) и подставляют PO-токен. Поэтому они работают там,
  /// где прямой googlevideo-хост отдаёт 403 или зависает.
  static const List<String> _invidiousFallbackHosts = [
    'https://yt.chocolatemoo53.com',
    'https://invidious.nerdvpn.de',
    'https://yewtu.be',
    'https://invidious.tiekoetter.com',
    'https://inv.nadeko.net',
  ];

  final YoutubeExplode _youtube;
  final http.Client _http;
  final bool _ownsHttpClient;

  final Map<String, _CachedAudio> _audioCache = {};
  final Map<String, Future<AudioOnlyStreamInfo?>> _audioInFlight = {};

  String? _cachedSearchQuery;
  List<Track> _cachedSearchResults = const [];
  DateTime? _cachedSearchAt;

  String? _activeInvidiousHost;

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
  /// Сам поток идёт через Invidious-прокси: обычные googlevideo-ссылки
  /// без PO-токена отдают только первые ~1 МБ и обрываются.
  Future<YoutubeAudio?> audioFor(
    String videoId, {
    bool preferMp4 = true,
  }) async {
    final info = await _streamInfo(videoId, preferMp4: preferMp4);
    if (info == null) return null;
    final useMp4 = preferMp4 && info.container.name == 'mp4';
    return YoutubeAudio(
      videoId: videoId,
      url: _invidiousStreamUrl(videoId, useMp4 ? 140 : 251),
      container: useMp4 ? 'mp4' : 'webm',
      bitrateBps: info.bitrate.bitsPerSecond,
      sizeBytes: info.size.totalBytes,
    );
  }

  String _invidiousStreamUrl(String videoId, int itag) {
    final host = _activeInvidiousHost ?? _invidiousFallbackHosts.first;
    return Uri.parse('$host/latest_version')
        .replace(
          queryParameters: {'id': videoId, 'itag': '$itag', 'local': 'true'},
        )
        .toString();
  }

  /// Скачивает аудиодорожку во временный файл.
  ///
  /// Сначала используется Invidious: его прокси присылает готовый поток
  /// с PO-токеном и не зависит от того, отдаёт ли googlevideo файл
  /// напрямую. Если прокси недоступен, включается прямой запасной путь:
  /// свежий манифест YouTube и загрузка небольшими range-кусками.
  ///
  /// [onProgress] получает 0.0–1.0, если известен размер файла.
  Future<File> downloadAudio(
    String videoId, {
    required Directory directory,
    void Function(double? progress)? onProgress,
  }) async {
    await directory.create(recursive: true);
    final safeId = videoId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final base = '${directory.path}/verde_${stamp}_$safeId';

    // Пока устанавливаем соединение с зеркалом, процент ещё неизвестен.
    // Неопределённый прогресс лучше, чем «застывшие» 0%.
    onProgress?.call(null);

    // 1. Основной путь: прокси Invidious. Он медленнее прямого YouTube
    // примерно на секунду, зато не зависает на нулевом прогрессе.
    try {
      final file = await _downloadFromInvidious(
        videoId,
        base,
        onProgress: onProgress,
      );
      if (file != null) return file;
    } catch (error) {
      debugPrint('YoutubeService: Invidious failed for $videoId: $error');
    }

    // 2. Запасной путь: прямой YouTube. Некоторые видео отдают полный
    // файл только с PO-токеном, поэтому качаем маленькими кусками —
    // такие запросы YouTube принимает и без токена.
    onProgress?.call(null);
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      File? directFile;
      try {
        final info = await _streamInfo(
          videoId,
          preferMp4: false,
          forceRefresh: true,
        );
        if (info == null) {
          throw const YoutubeException('Не удалось получить аудио с YouTube.');
        }

        final extension = info.container.name == 'mp4'
            ? 'm4a'
            : (info.container.name.isEmpty ? 'webm' : info.container.name);
        directFile = File('$base.direct.$extension');
        await _downloadDirect(info, directFile, onProgress: onProgress);
        if (await directFile.length() < 32 * 1024) {
          throw const YoutubeException('YouTube вернул пустой аудиофайл.');
        }
        return directFile;
      } catch (error) {
        lastError = error;
        if (directFile != null) await _deleteQuietly(directFile);
        _audioCache.remove(_cacheKey(videoId, preferMp4: false));
        if (attempt == 0) {
          debugPrint('YoutubeService: direct retry for $videoId: $error');
          continue;
        }
      }
    }

    debugPrint('YoutubeService: download failed for $videoId: $lastError');
    throw const YoutubeException(
      'Не удалось скачать аудио. Проверьте соединение и попробуйте ещё раз.',
    );
  }

  /// Загружает аудио через `latest_version?local=true` на Invidious.
  ///
  /// Возвращает `null`, если ни один инстанс не смог отдать файл.
  Future<File?> _downloadFromInvidious(
    String videoId,
    String base, {
    void Function(double? progress)? onProgress,
  }) async {
    Object? lastError;
    var hostsTried = 0;

    for (final host in _invidiousFallbackHosts) {
      if (_disposed || hostsTried >= 3) break;
      hostsTried++;

      // 251 — Opus в WebM, 140 — AAC в M4A. Сначала лучшее качество,
      // затем максимально совместимый AAC.
      for (final itag in const [251, 140]) {
        final extension = itag == 251 ? 'webm' : 'm4a';
        final file = File('$base.invidious.$itag.$extension');
        try {
          final downloaded = await _downloadInvidiousStream(
            host,
            videoId,
            itag,
            file,
            onProgress: onProgress,
          );
          if (downloaded) {
            _activeInvidiousHost = host;
            return file;
          }
        } catch (error) {
          lastError = error;
          await _deleteQuietly(file);
          // Если хост не отвечает, второй itag на нём тоже не поможет —
          // сразу переходим к следующему зеркалу.
          if (error is TimeoutException ||
              error is SocketException ||
              error is http.ClientException) {
            break;
          }
        }
      }
    }

    if (lastError != null) throw lastError;
    return null;
  }

  Future<bool> _downloadInvidiousStream(
    String host,
    String videoId,
    int itag,
    File file, {
    void Function(double? progress)? onProgress,
  }) async {
    final uri = Uri.parse('$host/latest_version').replace(
      queryParameters: {'id': videoId, 'itag': '$itag', 'local': 'true'},
    );
    final request = http.Request('GET', uri);
    request.headers.addAll({
      'User-Agent': _browserUserAgent,
      'Accept': 'audio/*,video/*,application/octet-stream;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Referer': '$host/watch?v=$videoId',
    });

    final response = await _http.send(request).timeout(_headersTimeout);
    if (response.statusCode != 200) {
      await _drainQuietly(response);
      throw HttpException('Invidious $host: HTTP ${response.statusCode}');
    }

    final contentType =
        response.headers['content-type']?.toLowerCase().trim() ?? '';
    // Ошибочные страницы инстансов иногда приходят с кодом 200.
    if (contentType.startsWith('text/') ||
        contentType.contains('html') ||
        contentType.contains('json')) {
      await _drainQuietly(response);
      throw HttpException('Invidious $host: не аудио ($contentType)');
    }

    final total = response.contentLength ?? 0;
    final sink = file.openWrite();
    var received = 0;
    var lastProgressAt = -1000;
    final clock = Stopwatch()..start();
    try {
      onProgress?.call(total > 0 ? 0 : null);
      await for (final chunk in response.stream.timeout(_chunkTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        final now = clock.elapsedMilliseconds;
        if (total > 0) {
          if (now - lastProgressAt >= 100 || received >= total) {
            lastProgressAt = now;
            onProgress?.call((received / total).clamp(0.0, 1.0));
          }
        } else if (now - lastProgressAt >= 250) {
          lastProgressAt = now;
          onProgress?.call(null);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (received < 32 * 1024) {
      throw const YoutubeException('Invidious вернул слишком маленький файл.');
    }
    if (total > 0 && received < total) {
      throw const YoutubeException('Загрузка через Invidious оборвалась.');
    }
    return true;
  }

  /// Прямая загрузка с googlevideo маленькими range-кусками.
  ///
  /// Это обход двух проблем: зависания stream-обёртки youtube_explode
  /// и ограничения YouTube на размер range-запроса без PO-токена.
  Future<void> _downloadDirect(
    AudioOnlyStreamInfo info,
    File file, {
    void Function(double? progress)? onProgress,
  }) async {
    final total = info.size.totalBytes;
    if (total <= 0) {
      throw const YoutubeException('YouTube не сообщил размер аудио.');
    }

    final source = info.url;
    final android = source.queryParameters['c']?.toUpperCase() == 'ANDROID';
    final sink = file.openWrite();
    var received = 0;
    var lastProgressAt = -1000;
    final clock = Stopwatch()..start();

    try {
      onProgress?.call(0);
      while (received < total) {
        if (_disposed) {
          throw const YoutubeException('Загрузка отменена.');
        }

        final from = received;
        final to = math.min(from + _directChunkBytes, total) - 1;
        final response = await _sendDirectRange(
          source,
          from: from,
          to: to,
          android: android,
        );

        final status = response.statusCode;
        if (status != 200 && status != 206) {
          await _drainQuietly(response);
          throw HttpException('YouTube: HTTP $status');
        }
        if (status == 200 && from > 0) {
          await _drainQuietly(response);
          throw const YoutubeException(
            'YouTube проигнорировал диапазон загрузки.',
          );
        }

        // Если сервер вернул 200 на первый кусок, он отдаёт файл целиком.
        // Это допустимо — просто дочитываем его до конца.
        final allowFull = status == 200 && from == 0;
        var rangeReceived = 0;
        await for (final chunk in response.stream.timeout(_chunkTimeout)) {
          sink.add(chunk);
          received += chunk.length;
          rangeReceived += chunk.length;
          if (!allowFull && received > to + 1) {
            throw const YoutubeException('YouTube вернул лишние данные.');
          }
          if (received > total) {
            throw const YoutubeException('YouTube вернул больше, чем нужно.');
          }

          final now = clock.elapsedMilliseconds;
          if (now - lastProgressAt >= 100 || received >= total) {
            lastProgressAt = now;
            onProgress?.call((received / total).clamp(0.0, 1.0));
          }
        }

        if (rangeReceived == 0) {
          throw const YoutubeException('YouTube прислал пустой кусок аудио.');
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (received < total) {
      throw const YoutubeException('Загрузка с YouTube оборвалась.');
    }
  }

  Future<http.StreamedResponse> _sendDirectRange(
    Uri source, {
    required int from,
    required int to,
    required bool android,
  }) async {
    var target = source;
    if (!android) {
      target = source.replace(
        queryParameters: {...source.queryParameters, 'range': '$from-$to'},
      );
    }

    Future<http.StreamedResponse> send(Uri uri) {
      final request = http.Request('GET', uri);
      request.headers.addAll(YoutubeHttpClient.defaultHeaders);
      request.headers['accept'] = '*/*';
      request.headers['accept-encoding'] = 'identity';
      if (android) {
        request.headers['Range'] = 'bytes=$from-$to';
      }
      return _http.send(request).timeout(_headersTimeout);
    }

    try {
      final response = await send(target);
      // Блокировка конкретного rr-хоста часто выглядит как 403/410.
      // Пробуем тот же подписанный запрос через redirector.
      if ((response.statusCode == 403 || response.statusCode == 410) &&
          target.host != 'redirector.googlevideo.com') {
        await _drainQuietly(response);
        return await send(target.replace(host: 'redirector.googlevideo.com'));
      }
      return response;
    } catch (error) {
      // Иногда конкретный rr-хост заблокирован, а redirector работает.
      final redirected = target.replace(host: 'redirector.googlevideo.com');
      if (redirected.host == target.host) rethrow;
      debugPrint('YoutubeService: host fallback for $from-$to: $error');
      return await send(redirected);
    }
  }

  Future<void> _drainQuietly(http.StreamedResponse response) async {
    try {
      await response.stream.drain<void>().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Ошибочный ответ уже не нужен.
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Временный файл не критичен.
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
    if (_ownsHttpClient) _http.close();
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
