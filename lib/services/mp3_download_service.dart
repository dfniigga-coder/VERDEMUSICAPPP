import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../data/models/lyrics.dart';
import '../data/models/track.dart';
import '../data/repositories/local_tracks_repository.dart';
import 'lyrics_service.dart';
import 'media_store.dart';
import 'youtube_link.dart';
import 'youtube_service.dart';

/// Этапы скачивания — UI показывает их пользователю.
enum DownloadStage { resolving, downloading, converting, saving, done, failed }

extension DownloadStageInfo on DownloadStage {
  String get label {
    switch (this) {
      case DownloadStage.resolving:
        return 'Ищем трек на YouTube Music…';
      case DownloadStage.downloading:
        return 'Скачиваем аудио и лирику…';
      case DownloadStage.converting:
        return 'Конвертируем в MP3 + теги и лирика…';
      case DownloadStage.saving:
        return 'Сохраняем MP3 и файл лирики…';
      case DownloadStage.done:
        return 'Готово';
      case DownloadStage.failed:
        return 'Не удалось скачать';
    }
  }

  bool get isActive =>
      this != DownloadStage.done && this != DownloadStage.failed;
}

class DownloadResult {
  final String localPath;
  final String? publicPath;
  final String? lyricsPath;
  final bool hasLyrics;
  final bool hasSyncedLyrics;
  final String title;
  final String artist;
  final int? durationSec;
  final String? artworkUrl;

  const DownloadResult({
    required this.localPath,
    required this.publicPath,
    this.lyricsPath,
    this.hasLyrics = false,
    this.hasSyncedLyrics = false,
    required this.title,
    required this.artist,
    this.durationSec,
    this.artworkUrl,
  });
}

/// Скачивает трек с YouTube Music, находит лирику, конвертирует аудио в MP3
/// (с обложкой и тегом лирики) и сохраняет `.mp3` + `.lrc` в Music/Verde.
class Mp3DownloadService {
  Mp3DownloadService({
    required YoutubeService youtube,
    required LocalTracksRepository localTracks,
    LyricsService? lyrics,
    http.Client? httpClient,
  }) : _youtube = youtube,
       _localTracks = localTracks,
       _lyrics = lyrics,
       _ownsHttpClient = httpClient == null,
       _http = httpClient ?? http.Client();

  final YoutubeService _youtube;
  final LocalTracksRepository _localTracks;
  final LyricsService? _lyrics;
  final bool _ownsHttpClient;
  final http.Client _http;

  /// Уже сохранённый MP3 этого трека (если он есть в «Моих треках»).
  Track? findDownloaded(Track track) => _localTracks.findDownloaded(track);

  /// Разбирает ссылку YouTube Music / YouTube и возвращает трек
  /// с настоящими названием, исполнителем и обложкой.
  Future<Track> resolveLink(String input) async {
    final link = YoutubeLink.parse(input);
    if (link == null) {
      throw const DownloadException(
        'Не удалось распознать ссылку. Вставьте ссылку с YouTube Music '
        'или YouTube.',
      );
    }

    final videoId = link.videoId;
    if (videoId == null) {
      throw const DownloadException(
        'Это ссылка на плейлист. Откройте трек и скопируйте ссылку на него.',
      );
    }

    try {
      final match = await _youtube.resolveVideo(videoId);
      return Track.youtube(
        videoId: match.videoId,
        title: match.title,
        artist: match.artist,
        artworkUrl: match.artworkUrl,
        durationSec: match.durationSec,
      );
    } on YoutubeException catch (error) {
      throw DownloadException(error.message);
    } catch (error) {
      debugPrint('Mp3DownloadService: link resolve failed: $error');
      throw const DownloadException(
        'Не удалось получить информацию о видео. Проверьте соединение.',
      );
    }
  }

  /// [onProgress] вызывается на каждом этапе. Для downloading progress
  /// равен 0.0–1.0, для остальных этапов обычно null (неопределённый).
  Future<DownloadResult> download(
    Track track, {
    required void Function(DownloadStage stage, double? progress) onProgress,
  }) async {
    if (track.isLocal) {
      throw const DownloadException('Этот трек уже есть на устройстве.');
    }

    onProgress(DownloadStage.resolving, null);

    YoutubeMatch? match;
    try {
      match = await _youtube.findBest(
        track.title,
        track.artist,
        durationSec: track.isPreview ? null : track.durationSec,
        minDurationSec: track.isPreview ? 60 : 45,
        preferredVideoId: track.source == TrackSource.youtube
            ? track.externalId
            : null,
      );
    } catch (error) {
      debugPrint('Mp3DownloadService: search failed: $error');
      throw const DownloadException(
        'Не удалось найти трек на YouTube Music. Проверьте соединение.',
      );
    }

    if (match == null) {
      throw const DownloadException(
        'Трек не найден на YouTube Music. Попробуйте изменить запрос.',
      );
    }

    final tempDir = await getTemporaryDirectory();
    File? sourceFile;
    File? coverFile;
    File? rawMp3;
    File? outputFile;

    try {
      final title = _metadataValue(track.title, match.title, 'Без названия');
      final artist = _metadataValue(
        track.artist,
        match.artist,
        'Неизвестный исполнитель',
      );
      final artworkUrl = track.artworkUrl ?? match.artworkUrl;
      final effectiveDuration = track.isPreview
          ? match.durationSec
          : (track.durationSec ?? match.durationSec);

      onProgress(DownloadStage.downloading, 0);

      // Лирику и обложку загружаем параллельно со скачиванием аудиодорожки.
      final lyricsFuture = _fetchLyricsQuietly(
        track,
        title: title,
        artist: artist,
        durationSec: effectiveDuration,
      );
      final coverFuture = _downloadCover(artworkUrl, tempDir);

      try {
        sourceFile = await _youtube.downloadAudio(
          match.videoId,
          directory: tempDir,
          onProgress: (progress) =>
              onProgress(DownloadStage.downloading, progress),
        );
      } catch (error) {
        debugPrint('Mp3DownloadService: download failed: $error');
        throw const DownloadException(
          'Не удалось скачать аудио. Проверьте соединение и попробуйте ещё раз.',
        );
      }

      onProgress(DownloadStage.converting, null);

      final baseDir =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final outputDir = Directory('${baseDir.path}/Music/Verde');
      await outputDir.create(recursive: true);

      final fileName = _safeFileName('$artist - $title');
      outputFile = _uniqueFile(outputDir, fileName, 'mp3');
      rawMp3 = File('${outputFile.path}.raw.mp3');
      await _deleteQuietly(rawMp3);

      final lyrics = await lyricsFuture;
      final lrcContent = lyrics?.toLrcString(
        fallbackTitle: title,
        fallbackArtist: artist,
      );
      final embeddedLyrics =
          (lyrics?.plainText?.trim().isNotEmpty ?? false)
              ? lyrics!.plainText!.trim()
              : lrcContent;

      var converted = await _convertToMp3(
        sourceFile,
        rawMp3,
        title: title,
        artist: artist,
        lyrics: embeddedLyrics,
      );
      // Если FFmpeg не принял длинный тег lyrics, повторяем без него —
      // сама лирика всё равно сохранится в .lrc рядом с файлом.
      if (!converted && embeddedLyrics != null) {
        converted = await _convertToMp3(
          sourceFile,
          rawMp3,
          title: title,
          artist: artist,
        );
      }
      if (!converted || !await rawMp3.exists()) {
        throw const DownloadException(
          'Не удалось конвертировать трек в MP3. Попробуйте ещё раз.',
        );
      }

      coverFile = await coverFuture;
      if (coverFile != null) {
        var withCover = await _attachCover(
          rawMp3,
          coverFile,
          outputFile,
          title: title,
          artist: artist,
          lyrics: embeddedLyrics,
        );
        if (!withCover && embeddedLyrics != null) {
          withCover = await _attachCover(
            rawMp3,
            coverFile,
            outputFile,
            title: title,
            artist: artist,
          );
        }
        if (withCover) {
          await _deleteQuietly(rawMp3);
        } else {
          await _deleteQuietly(outputFile);
          await rawMp3.rename(outputFile.path);
        }
      } else {
        await rawMp3.rename(outputFile.path);
      }

      if (!await outputFile.exists() || await outputFile.length() == 0) {
        throw const DownloadException(
          'Не удалось конвертировать трек в MP3. Попробуйте ещё раз.',
        );
      }

      onProgress(DownloadStage.saving, null);

      String? savedLyricsPath;
      if (lrcContent != null && lrcContent.isNotEmpty) {
        try {
          final lrcFile = File(LyricsService.sidecarLrcPath(outputFile.path));
          await lrcFile.writeAsString(lrcContent, encoding: utf8, flush: true);
          savedLyricsPath = lrcFile.path;
        } catch (error) {
          debugPrint('Mp3DownloadService: lrc write failed: $error');
        }
      }

      String? publicPath;
      try {
        publicPath = await MediaStore.saveAudio(
          filePath: outputFile.path,
          displayName: outputFile.uri.pathSegments.last,
          title: title,
          artist: artist,
        );
      } catch (error) {
        debugPrint('Mp3DownloadService: public save failed: $error');
      }

      await _localTracks.addDownloadedTrack(
        path: outputFile.path,
        title: title,
        artist: artist,
        durationSec: effectiveDuration,
        artworkUrl: artworkUrl,
      );

      onProgress(DownloadStage.done, 1);
      return DownloadResult(
        localPath: outputFile.path,
        publicPath: publicPath,
        lyricsPath: savedLyricsPath,
        hasLyrics: lyrics != null && lyrics.hasText,
        hasSyncedLyrics: lyrics?.hasSynced ?? false,
        title: title,
        artist: artist,
        durationSec: effectiveDuration,
        artworkUrl: artworkUrl,
      );
    } finally {
      await _deleteQuietly(sourceFile);
      await _deleteQuietly(coverFile);
      await _deleteQuietly(rawMp3);
    }
  }

  Future<Lyrics?> _fetchLyricsQuietly(
    Track original, {
    required String title,
    required String artist,
    int? durationSec,
  }) async {
    final lyricsService = _lyrics;
    if (lyricsService == null) return null;

    try {
      final queryTrack = original.copyWith(
        title: title,
        artist: artist,
        durationSec: durationSec,
      );
      final found = await lyricsService
          .fetch(queryTrack)
          .timeout(const Duration(seconds: 7), onTimeout: () => null);
      if (found == null || !found.hasText) return null;
      return found;
    } catch (error) {
      debugPrint('Mp3DownloadService: lyrics fetch failed: $error');
      return null;
    }
  }

  Future<bool> _convertToMp3(
    File input,
    File output, {
    required String title,
    required String artist,
    String? lyrics,
  }) async {
    if (await output.exists()) {
      await _deleteQuietly(output);
    }

    final arguments = <String>[
      '-hide_banner',
      '-y',
      '-threads',
      '0',
      '-i',
      input.path,
      '-map',
      '0:a:0',
      '-c:a',
      'libmp3lame',
      '-b:a',
      '192k',
      '-compression_level',
      '0',
      '-map_metadata',
      '-1',
      '-id3v2_version',
      '3',
      '-metadata',
      'title=$title',
      '-metadata',
      'artist=$artist',
      '-metadata',
      'album=Verde',
      if (lyrics != null && lyrics.isNotEmpty) ...[
        '-metadata',
        'lyrics=$lyrics',
      ],
      output.path,
    ];

    try {
      final session = await FFmpegKit.executeWithArguments(arguments);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode) && await output.exists()) {
        return await output.length() > 0;
      }

      debugPrint(
        'Mp3DownloadService: ffmpeg failed ($returnCode): '
        '${await session.getOutput()}',
      );
      await _deleteQuietly(output);
      return false;
    } catch (error) {
      debugPrint('Mp3DownloadService: ffmpeg error: $error');
      await _deleteQuietly(output);
      return false;
    }
  }

  Future<bool> _attachCover(
    File audio,
    File cover,
    File output, {
    required String title,
    required String artist,
    String? lyrics,
  }) async {
    if (await output.exists()) {
      await _deleteQuietly(output);
    }

    final arguments = <String>[
      '-hide_banner',
      '-y',
      '-threads',
      '0',
      '-i',
      audio.path,
      '-i',
      cover.path,
      '-map',
      '0:a:0',
      '-map',
      '1:v:0',
      '-c',
      'copy',
      '-disposition:v',
      'attached_pic',
      '-id3v2_version',
      '3',
      '-metadata',
      'title=$title',
      '-metadata',
      'artist=$artist',
      '-metadata',
      'album=Verde',
      if (lyrics != null && lyrics.isNotEmpty) ...[
        '-metadata',
        'lyrics=$lyrics',
      ],
      '-metadata:s:v',
      'title=Album cover',
      '-metadata:s:v',
      'comment=Cover (front)',
      output.path,
    ];

    try {
      final session = await FFmpegKit.executeWithArguments(arguments);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode) && await output.exists()) {
        return await output.length() > 0;
      }

      debugPrint(
        'Mp3DownloadService: cover attach failed ($returnCode): '
        '${await session.getOutput()}',
      );
      await _deleteQuietly(output);
      return false;
    } catch (error) {
      debugPrint('Mp3DownloadService: cover attach error: $error');
      await _deleteQuietly(output);
      return false;
    }
  }

  Future<File?> _downloadCover(String? url, Directory tempDir) async {
    if (url == null || url.trim().isEmpty) return null;

    try {
      final response = await _http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;

      final bytes = response.bodyBytes;
      final isJpeg = bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;
      final isPng =
          bytes.length > 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47;
      if (!isJpeg && !isPng) return null;

      final extension = isPng ? 'png' : 'jpg';
      final file = File(
        '${tempDir.path}/verde_cover_'
        '${DateTime.now().microsecondsSinceEpoch}.$extension',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (error) {
      debugPrint('Mp3DownloadService: cover download failed: $error');
      return null;
    }
  }

  String _metadataValue(String primary, String fallback, String emptyValue) {
    final primaryValue = primary.trim();
    final fallbackValue = fallback.trim();
    final useFallback =
        primaryValue.isEmpty || primaryValue == 'Неизвестный исполнитель';
    final value = useFallback ? fallbackValue : primaryValue;
    return value.isEmpty ? emptyValue : value;
  }

  String _safeFileName(String value) {
    var name = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    name = name.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
    if (name.isEmpty) name = 'Verde track';
    if (name.length > 120) name = name.substring(0, 120).trim();
    return name;
  }

  File _uniqueFile(Directory directory, String baseName, String extension) {
    var file = File('${directory.path}/$baseName.$extension');
    var counter = 2;
    while (file.existsSync()) {
      file = File('${directory.path}/$baseName ($counter).$extension');
      counter++;
    }
    return file;
  }

  Future<void> _deleteQuietly(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Временный файл удалит система.
    }
  }

  void dispose() {
    if (_ownsHttpClient) _http.close();
  }
}

class DownloadException implements Exception {
  final String message;

  const DownloadException(this.message);

  @override
  String toString() => message;
}
