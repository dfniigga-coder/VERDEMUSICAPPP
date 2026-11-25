import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/models/lyrics.dart';
import '../data/models/track.dart';

/// Клиент LRCLIB — базы настоящих текстов песен.
///
/// Никакой генерации и Whisper: если текста нет в базе, сервис честно
/// возвращает `null`, а UI показывает «Текст не найден».
class LyricsService {
  LyricsService({http.Client? client})
    : _http = client ?? http.Client(),
      _ownsClient = client == null;

  static const String _host = 'lrclib.net';
  static const String _userAgent =
      'Verde/1.2.0 (https://github.com/dfniigga-coder/musicapp)';
  static const Duration _timeout = Duration(seconds: 8);

  final http.Client _http;
  final bool _ownsClient;
  final Map<String, Future<Lyrics?>> _cache = {};

  static const Map<String, String> _headers = {
    'User-Agent': _userAgent,
    'Accept': 'application/json',
  };

  /// Путь к sidecar-файлу `.lrc` рядом с локальным аудиофайлом.
  static String sidecarLrcPath(String audioPath) {
    final dot = audioPath.lastIndexOf('.');
    final slash = audioPath.lastIndexOf(Platform.pathSeparator);
    if (dot > slash && dot > 0) {
      return '${audioPath.substring(0, dot)}.lrc';
    }
    return '$audioPath.lrc';
  }

  /// Ищет текст: сначала локальный `.lrc` рядом с файлом, затем LRCLIB.
  ///
  /// [refresh] сбрасывает кэш для трека — нужен кнопке «Обновить»,
  /// если в первый раз сеть не ответила.
  Future<Lyrics?> fetch(Track track, {bool refresh = false}) {
    final key = _cacheKey(track);
    if (refresh) _cache.remove(key);
    return _cache.putIfAbsent(key, () => _fetch(track, refresh: refresh));
  }

  void dispose() {
    _cache.clear();
    if (_ownsClient) _http.close();
  }

  String _cacheKey(Track track) {
    final title = track.title.trim().toLowerCase();
    final artist = track.artist.trim().toLowerCase();
    final local = track.localPath?.trim() ?? '';
    return '$title|$artist|${track.durationSec ?? ''}|$local';
  }

  Future<Lyrics?> _fetch(Track track, {bool refresh = false}) async {
    final localPath = track.localPath?.trim();
    if (!refresh && localPath != null && localPath.isNotEmpty) {
      final localLyrics = await _readSidecar(localPath, track);
      if (localLyrics != null) return localLyrics;
    }

    final candidates = _candidates(track);
    if (candidates.isEmpty) return null;

    Lyrics? found;
    // Сначала точный запрос: LRCLIB сам подбирает версию по длительности.
    for (final candidate in candidates) {
      found = await _get(candidate, track.durationSec);
      if (found != null) break;
    }

    // Если точного совпадения нет — поиск. Результаты проверяем по
    // названию/исполнителю, чтобы не показать текст чужой песни.
    if (found == null) {
      for (final candidate in candidates) {
        found = await _search(candidate);
        if (found != null) break;
      }
    }

    if (found != null && localPath != null && localPath.isNotEmpty) {
      unawaited(_writeSidecarQuietly(localPath, found, track));
    }

    return found;
  }

  Future<Lyrics?> _readSidecar(String audioPath, Track track) async {
    try {
      final file = File(sidecarLrcPath(audioPath));
      if (!await file.exists()) return null;
      final raw = await file.readAsString(encoding: utf8);
      return Lyrics.fromLrcContent(
        raw,
        title: track.title,
        artist: track.artist,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSidecarQuietly(
    String audioPath,
    Lyrics lyrics,
    Track track,
  ) async {
    try {
      final content = lyrics.toLrcString(
        fallbackTitle: track.title,
        fallbackArtist: track.artist,
      );
      if (content == null || content.isEmpty) return;
      final audioFile = File(audioPath);
      if (!await audioFile.exists()) return;
      final lrcFile = File(sidecarLrcPath(audioPath));
      await lrcFile.writeAsString(content, encoding: utf8, flush: true);
    } catch (_) {
      // Отсутствие прав на запись рядом с системным файлом не критично.
    }
  }

  Future<Lyrics?> _get(_LyricsQuery query, int? durationSec) async {
    final params = <String, String>{
      'artist_name': query.artist,
      'track_name': query.title,
    };
    if (durationSec != null && durationSec > 0) {
      params['duration'] = '$durationSec';
    }

    final uri = Uri.https(_host, '/api/get', params);
    try {
      final response = await _http
          .get(uri, headers: _headers)
          .timeout(_timeout);
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        debugPrint('LyricsService: get ${response.statusCode}');
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final lyrics = Lyrics.fromJson(decoded);
      return lyrics.hasContent ? lyrics : null;
    } catch (error) {
      debugPrint('LyricsService: get failed: $error');
      return null;
    }
  }

  Future<Lyrics?> _search(_LyricsQuery query) async {
    final text = [
      query.artist,
      query.title,
    ].where((part) => part.isNotEmpty).join(' ');
    final uri = Uri.https(_host, '/api/search', {'q': text});
    try {
      final response = await _http
          .get(uri, headers: _headers)
          .timeout(_timeout);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! List) return null;

      Lyrics? best;
      var bestScore = 0;
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final candidate = Lyrics.fromJson(item);
        if (!candidate.hasContent) continue;

        final score = _score(candidate, query);
        final betterSynced =
            score == bestScore &&
            candidate.hasSynced &&
            !(best?.hasSynced ?? false);
        if (score > bestScore || betterSynced) {
          best = candidate;
          bestScore = score;
        }
      }

      // Слишком слабое совпадение — лучше ничего, чем чужие слова.
      return bestScore >= 4 ? best : null;
    } catch (error) {
      debugPrint('LyricsService: search failed: $error');
      return null;
    }
  }

  int _score(Lyrics lyrics, _LyricsQuery query) {
    final title = _normalize(lyrics.title ?? '');
    final artist = _normalize(lyrics.artist ?? '');
    final qTitle = _normalize(query.title);
    final qArtist = _normalize(query.artist);

    var score = 0;
    if (qTitle.isNotEmpty && title.isNotEmpty) {
      if (title == qTitle) {
        score += 4;
      } else if (title.contains(qTitle) || qTitle.contains(title)) {
        score += 2;
      }
    }

    if (qArtist.isNotEmpty && artist.isNotEmpty) {
      if (artist == qArtist) {
        score += 4;
      } else if (artist.contains(qArtist) || qArtist.contains(artist)) {
        score += 2;
      }
    }

    if (lyrics.hasSynced) score += 1;
    return score;
  }

  List<_LyricsQuery> _candidates(Track track) {
    final rawTitle = track.title.trim();
    final rawArtist = track.artist.trim();
    if (rawTitle.isEmpty) return const [];

    final title = _clean(rawTitle);
    final artist = _cleanArtist(rawArtist);
    final result = <_LyricsQuery>[];

    void add(String value, String performer) {
      final cleanedTitle = _clean(value);
      final cleanedArtist = _cleanArtist(performer);
      if (cleanedTitle.isEmpty || cleanedArtist.isEmpty) return;

      final key =
          '${cleanedTitle.toLowerCase()}|${cleanedArtist.toLowerCase()}';
      if (result.any((query) => query.key == key)) return;
      result.add(_LyricsQuery(cleanedTitle, cleanedArtist));
    }

    add(title, artist);

    // YouTube-названия часто выглядят как «Artist - Song (Official Video)».
    final split = _splitArtistTitle(rawTitle);
    if (split != null) {
      add(split.$2, split.$1);
      add(split.$2, artist);
    }

    final withoutFeat = _removeFeat(title);
    if (withoutFeat != title) add(withoutFeat, artist);

    return result.take(4).toList();
  }

  (String, String)? _splitArtistTitle(String raw) {
    final cleaned = _clean(raw);
    final parts = cleaned.split(RegExp(r'\s+[-–—]\s+'));
    if (parts.length < 2) return null;

    final artist = parts.first.trim();
    final title = parts.sublist(1).join(' - ').trim();
    if (artist.isEmpty || title.isEmpty) return null;
    return (artist, title);
  }

  static final RegExp _bracketedNoise = RegExp(
    r'\s*[\(\[](?:official|lyrics?|audio|video|visualizer|remaster(?:ed)?|live|explicit|hd|4k|mv|m/v)[^)\]]*[\)\]]',
    caseSensitive: false,
  );

  static final RegExp _dashNoise = RegExp(
    r'\s*[-–—]\s*(?:official(?:\s+(?:music\s+)?(?:video|audio))?|lyrics?|audio|video|visualizer|remaster(?:ed)?(?:\s+\d{4})?|explicit|hd|4k|mv|m/v|live(?:\s+(?:at|from|in)\s+.*)?)\s*$',
    caseSensitive: false,
  );

  static final RegExp _feat = RegExp(
    r'\s*[\(\[]\s*(?:feat\.?|ft\.?|with)\s+[^)\]]*[\)\]]',
    caseSensitive: false,
  );

  static final RegExp _topic = RegExp(
    r'\s*[-–—]\s*topic\s*$',
    caseSensitive: false,
  );

  static final RegExp _vevo = RegExp(r'\s*vevo\s*$', caseSensitive: false);

  String _clean(String value) {
    var result = value.replaceAll(_bracketedNoise, '');
    result = result.replaceAll(_dashNoise, '');
    result = result.replaceAll(RegExp(r'\s+'), ' ');
    return result.trim();
  }

  String _cleanArtist(String value) {
    var result = _clean(value);
    result = result.replaceAll(_topic, '');
    result = result.replaceAll(_vevo, '');
    return result.trim();
  }

  String _removeFeat(String value) {
    return value.replaceAll(_feat, '').trim();
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r"""[()\[\]{}.,!?;:'"`~@#$%^&*_+=|\\/<>-]"""), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _LyricsQuery {
  const _LyricsQuery(this.title, this.artist);

  final String title;
  final String artist;

  String get key => '${title.toLowerCase()}|${artist.toLowerCase()}';
}
