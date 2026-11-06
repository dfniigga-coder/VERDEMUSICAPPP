import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:soundcloud_explode_dart/soundcloud_explode_dart.dart';

import '../core/constants.dart';
import '../data/models/resolved_track.dart';

/// Выполняет сетевой запрос с таймаутом и никогда не бросает исключение
/// наружу. Ошибка одного источника не должна ломать поиск или UI.
Future<T?> safeRequest<T>(
  Future<T> Function() request, {
  required String source,
  Duration timeout = const Duration(
    seconds: AppConstants.fullTrackTimeoutSeconds,
  ),
}) async {
  try {
    return await request().timeout(timeout);
  } on TimeoutException {
    debugPrint('FullTrackResolver[$source]: timeout');
  } on SocketException catch (error) {
    debugPrint('FullTrackResolver[$source]: network error: ${error.message}');
  } on http.ClientException catch (error) {
    debugPrint('FullTrackResolver[$source]: HTTP error: ${error.message}');
  } on SoundcloudExplodeException catch (error) {
    debugPrint('FullTrackResolver[$source]: SoundCloud error: $error');
  } on FormatException catch (error) {
    debugPrint('FullTrackResolver[$source]: bad response: ${error.message}');
  } catch (error) {
    debugPrint('FullTrackResolver[$source]: $error');
  }
  return null;
}

/// Ищет полную версию трека сначала на SoundCloud, затем на YouTube.
///
/// SoundCloud отдаёт прямой stream URL для just_audio. YouTube используется
/// как fallback: возвращается только videoId, который UI открывает во
/// встроенном iFrame-плеере. Любая ошибка источника = просто следующий шаг.
class FullTrackResolver {
  FullTrackResolver({http.Client? httpClient})
    : _ownsHttpClient = httpClient == null,
      _http = httpClient ?? http.Client() {
    _soundcloud = SoundcloudClient(httpClient: _http);
  }

  static const Duration _cacheTtl = Duration(minutes: 10);
  static const Duration _negativeCacheTtl = Duration(minutes: 2);

  static const Map<String, String> _youtubeHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9',
    'Cookie': 'CONSENT=YES+cb.20210328-17-p0.en+FX+239',
  };

  final bool _ownsHttpClient;
  final http.Client _http;
  late final SoundcloudClient _soundcloud;

  final Map<String, _CacheEntry> _cache = {};
  final Map<String, Future<ResolvedTrack?>> _inFlight = {};

  void dispose() {
    if (_ownsHttpClient) _http.close();
  }

  /// Пробует найти полную версию по названию и исполнителю.
  ///
  /// Все ошибки/timeout'ы проглатываются: в худшем случае вернётся `null`,
  /// и UI останется на превью Deezer/iTunes.
  Future<ResolvedTrack?> resolve(String title, String artist) {
    final cleanTitle = title.trim();
    final cleanArtist = artist.trim();
    if (cleanTitle.isEmpty && cleanArtist.isEmpty) {
      return Future.value(null);
    }

    final key = '${_normalize(cleanTitle)}|${_normalize(cleanArtist)}';
    final cached = _cache[key];
    if (cached != null && !cached.isExpired) {
      return Future.value(cached.track);
    }

    final running = _inFlight[key];
    if (running != null) return running;

    final future = _resolveUncached(cleanTitle, cleanArtist)
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('FullTrackResolver: unexpected error: $error');
          return null;
        })
        .then((resolved) {
          _cache[key] = _CacheEntry(
            resolved,
            DateTime.now().add(
              resolved == null ? _negativeCacheTtl : _cacheTtl,
            ),
          );
          return resolved;
        });

    _inFlight[key] = future;
    unawaited(
      future.whenComplete(() {
        _inFlight.remove(key);
      }),
    );
    return future;
  }

  Future<ResolvedTrack?> _resolveUncached(String title, String artist) async {
    final soundcloud = await _resolveSoundcloud(title, artist);
    if (soundcloud != null) return soundcloud;

    final videoId = await _searchYoutubeVideoId(title, artist);
    if (videoId == null) {
      debugPrint('FullTrackResolver: no full source for "$title — $artist"');
      return null;
    }

    return ResolvedTrack(
      title: title,
      artist: artist,
      source: FullTrackSource.youtube,
      isFullTrack: true,
      youtubeVideoId: videoId,
      externalId: videoId,
    );
  }

  // --- SoundCloud ----------------------------------------------------------

  Future<ResolvedTrack?> _resolveSoundcloud(String title, String artist) async {
    final query = [
      title,
      artist,
    ].where((part) => part.trim().isNotEmpty).join(' ').trim();
    if (query.isEmpty) return null;

    final results = await safeRequest<List<TrackSearchResult>>(() async {
      final firstBatch = await _soundcloud.search
          .getTracks(query, limit: 15)
          .first;
      return firstBatch.toList(growable: false);
    }, source: 'soundcloud.search');
    if (results == null || results.isEmpty) return null;

    final candidates =
        results.where((track) {
          return _isStreamable(track) &&
              _matches(
                title: title,
                artist: artist,
                candidateTitle: track.title,
                candidateArtist: track.user.username,
              );
        }).toList()..sort(
          (a, b) => _scoreTrack(
            b,
            title,
            artist,
          ).compareTo(_scoreTrack(a, title, artist)),
        );

    for (final candidate in candidates.take(3)) {
      final streamUrl = await safeRequest<String>(
        () => _streamUrlFor(candidate.id),
        source: 'soundcloud.stream',
      );
      if (streamUrl == null || streamUrl.isEmpty) continue;

      return ResolvedTrack(
        title: candidate.title,
        artist: candidate.user.username,
        artworkUrl: candidate.artworkUrl?.toString(),
        streamUrl: streamUrl,
        source: FullTrackSource.soundcloud,
        isFullTrack: true,
        externalId: '${candidate.id}',
        durationSec: (candidate.fullDuration / 1000).round(),
      );
    }

    return null;
  }

  /// Пакет не экспортирует `streamable`/`downloadable` напрямую, но
  /// `policy` + совпадение `duration`/`fullDuration` дают тот же ответ:
  /// SNIP/DENY или укороченная длительность = полный трек недоступен
  /// без SoundCloud Go. `downloadable` для стриминга не требуется.
  bool _isStreamable(TrackSearchResult track) {
    final policy = track.policy.toUpperCase();
    if (policy == 'DENY' || policy == 'SNIP') return false;

    final delta = (track.fullDuration - track.duration).abs();
    return track.fullDuration <= 0 || delta < 2000;
  }

  Future<String> _streamUrlFor(int trackId) async {
    final streams = await _soundcloud.tracks.getStreams(trackId);
    final playable = streams
        .where((stream) => !stream.isSnipped && stream.url.isNotEmpty)
        .toList();
    if (playable.isEmpty) {
      throw StateError('No playable streams for SoundCloud track $trackId');
    }

    playable.sort((a, b) => _streamRank(a).compareTo(_streamRank(b)));
    return playable.first.url;
  }

  int _streamRank(StreamInfo stream) {
    final protocol = stream.protocol.toLowerCase();
    final container = stream.container.toLowerCase();
    if (protocol == 'progressive' &&
        (container == 'mpeg' || container == 'mp3')) {
      return 0;
    }
    if (protocol == 'progressive') return 1;
    if (protocol.contains('hls')) return 2;
    return 3;
  }

  bool _matches({
    required String title,
    required String artist,
    required String candidateTitle,
    required String candidateArtist,
  }) {
    final wantedTitle = _normalize(title);
    final candidate = _normalize(candidateTitle);
    if (wantedTitle.isEmpty || candidate.isEmpty) return false;

    final titleMatches =
        candidate.contains(wantedTitle) || wantedTitle.contains(candidate);
    if (!titleMatches) return false;

    final wantedArtist = _normalize(artist);
    if (wantedArtist.isEmpty) return true;

    final candidateArtistName = _normalize(candidateArtist);
    return candidateArtistName.contains(wantedArtist) ||
        wantedArtist.contains(candidateArtistName) ||
        _tokensOverlap(candidateArtistName, wantedArtist);
  }

  int _scoreTrack(TrackSearchResult track, String title, String artist) {
    var score = 0;
    final candidateTitle = _normalize(track.title);
    final candidateArtist = _normalize(track.user.username);
    final wantedTitle = _normalize(title);
    final wantedArtist = _normalize(artist);

    if (candidateTitle == wantedTitle) {
      score += 100;
    } else if (candidateTitle.contains(wantedTitle)) {
      score += 60;
    } else if (wantedTitle.contains(candidateTitle)) {
      score += 40;
    }

    if (wantedArtist.isNotEmpty) {
      if (candidateArtist == wantedArtist) {
        score += 50;
      } else if (candidateArtist.contains(wantedArtist) ||
          wantedArtist.contains(candidateArtist)) {
        score += 30;
      }
    }

    score += (track.likesCount / 1000).clamp(0, 10).toInt();
    return score;
  }

  // --- YouTube -------------------------------------------------------------

  Future<String?> _searchYoutubeVideoId(String title, String artist) async {
    final query = [
      title,
      artist,
    ].where((part) => part.trim().isNotEmpty).join(' ').trim();
    if (query.isEmpty) return null;

    final html = await safeRequest<String>(
      () => _fetchYoutubeResults(query),
      source: 'youtube.search',
    );
    if (html == null || html.isEmpty) return null;

    final candidates = _youtubeCandidates(html);
    if (candidates.isEmpty) return null;

    String? bestId;
    var bestScore = -1;
    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      final score = _scoreYoutubeCandidate(candidate, title, artist, index);
      if (score > bestScore) {
        bestScore = score;
        bestId = candidate.id;
      }
    }

    // Для кандидатов без названия (regex-fallback) score > 0 — это порядок
    // выдачи. Для структурированных результатов требуем хоть какое-то
    // совпадение, чтобы не открыть случайное видео.
    if (bestId == null || bestScore <= 0) return null;
    return bestId;
  }

  Future<String> _fetchYoutubeResults(String query) async {
    final uri = Uri.https('www.youtube.com', '/results', {
      'search_query': query,
      'hl': 'en',
      'gl': 'US',
    });
    final response = await _http.get(uri, headers: _youtubeHeaders);
    if (response.statusCode != 200) {
      throw http.ClientException('YouTube HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  List<_YoutubeCandidate> _youtubeCandidates(String html) {
    final data = _extractYoutubeInitialData(html);
    if (data != null) {
      final candidates = <_YoutubeCandidate>[];
      _walkYoutubeData(data, candidates);
      if (candidates.isNotEmpty) return candidates;
    }
    return _regexYoutubeCandidates(html);
  }

  Map<String, dynamic>? _extractYoutubeInitialData(String html) {
    const markers = [
      'ytInitialData = ',
      'ytInitialData=',
      "ytInitialData'] = ",
      '"ytInitialData"] = ',
    ];

    for (final marker in markers) {
      var searchFrom = 0;
      while (true) {
        final markerIndex = html.indexOf(marker, searchFrom);
        if (markerIndex < 0) break;

        var start = markerIndex + marker.length;
        while (start < html.length && _isJsWhitespace(html.codeUnitAt(start))) {
          start++;
        }
        if (start >= html.length) break;

        final first = html.codeUnitAt(start);
        Map<String, dynamic>? parsed;

        if (first == 0x7B) {
          // Обычный объектный литерал: var ytInitialData = {...};
          final jsonText = _balancedJsonObject(html, start);
          parsed = _tryDecodeJsonMap(jsonText);
        } else if (first == 0x27 || first == 0x22) {
          // Новый формат YouTube: ytInitialData = '\x7b\x22...\x7d';
          final decoded = _readJsStringLiteral(html, start);
          parsed = _tryDecodeJsonMap(decoded);
        }

        if (parsed != null) return parsed;
        searchFrom = markerIndex + marker.length;
      }
    }
    return null;
  }

  Map<String, dynamic>? _tryDecodeJsonMap(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (error) {
      debugPrint('FullTrackResolver: ytInitialData parse failed: $error');
    }
    return null;
  }

  bool _isJsWhitespace(int code) {
    return code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D;
  }

  String? _readJsStringLiteral(String source, int start) {
    final quote = source.codeUnitAt(start);
    final buffer = StringBuffer();

    for (var index = start + 1; index < source.length; index++) {
      final code = source.codeUnitAt(index);
      if (code == quote) return buffer.toString();

      if (code != 0x5C) {
        buffer.writeCharCode(code);
        continue;
      }

      if (index + 1 >= source.length) return null;
      final escape = source.codeUnitAt(index + 1);
      index++;

      switch (escape) {
        case 0x78: // xNN
          if (index + 2 >= source.length) return null;
          final hex = source.substring(index + 1, index + 3);
          final value = int.tryParse(hex, radix: 16);
          if (value == null) return null;
          buffer.writeCharCode(value);
          index += 2;
        case 0x75: // uNNNN
          if (index + 4 >= source.length) return null;
          final hex = source.substring(index + 1, index + 5);
          final value = int.tryParse(hex, radix: 16);
          if (value == null) return null;
          buffer.writeCharCode(value);
          index += 4;
        case 0x6E:
          buffer.write('\n');
        case 0x72:
          buffer.write('\r');
        case 0x74:
          buffer.write('\t');
        case 0x62:
          buffer.write('\b');
        case 0x66:
          buffer.write('\f');
        case 0x76:
          buffer.write('\v');
        case 0x30:
          buffer.write('\x00');
        case 0x0A:
          // Перенос строки после обратного слеша — продолжение строки.
          break;
        case 0x0D:
          if (index + 1 < source.length &&
              source.codeUnitAt(index + 1) == 0x0A) {
            index++;
          }
        default:
          buffer.writeCharCode(escape);
      }
    }
    return null;
  }

  String? _balancedJsonObject(String source, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var index = start; index < source.length; index++) {
      final code = source.codeUnitAt(index);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5C) {
          escaped = true;
        } else if (code == 0x22) {
          inString = false;
        }
        continue;
      }

      if (code == 0x22) {
        inString = true;
      } else if (code == 0x7B) {
        depth++;
      } else if (code == 0x7D) {
        depth--;
        if (depth == 0) return source.substring(start, index + 1);
      }
    }
    return null;
  }

  void _walkYoutubeData(Object? node, List<_YoutubeCandidate> out) {
    if (out.length >= 20) return;

    if (node is Map) {
      final renderer = node['videoRenderer'];
      if (renderer is Map) {
        final id = renderer['videoId'];
        if (id is String && _isVideoId(id)) {
          out.add(
            _YoutubeCandidate(
              id: id,
              title: _runsText(renderer['title']) ?? '',
              author: _runsText(renderer['ownerText']) ?? '',
              length: _runsText(renderer['lengthText']),
            ),
          );
        }
      }

      for (final value in node.values) {
        _walkYoutubeData(value, out);
        if (out.length >= 20) return;
      }
    } else if (node is List) {
      for (final value in node) {
        _walkYoutubeData(value, out);
        if (out.length >= 20) return;
      }
    }
  }

  String? _runsText(Object? value) {
    if (value is Map) {
      final simpleText = value['simpleText'];
      if (simpleText is String) return simpleText;

      final runs = value['runs'];
      if (runs is List) {
        final buffer = StringBuffer();
        for (final run in runs) {
          if (run is Map && run['text'] is String) {
            buffer.write(run['text']);
          }
        }
        if (buffer.isNotEmpty) return buffer.toString();
      }
    } else if (value is String) {
      return value;
    }
    return null;
  }

  bool _isVideoId(String value) {
    return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(value);
  }

  List<_YoutubeCandidate> _regexYoutubeCandidates(String html) {
    final result = <_YoutubeCandidate>[];
    final seen = <String>{};
    final patterns = [
      RegExp(r'"videoId":"([A-Za-z0-9_-]{11})"'),
      RegExp(r'\\x22videoId\\x22:\\x22([A-Za-z0-9_-]{11})\\x22'),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(html)) {
        final id = match.group(1);
        if (id == null || !seen.add(id)) continue;
        result.add(
          _YoutubeCandidate(id: id, title: '', author: '', length: null),
        );
        if (result.length >= 10) return result;
      }
    }
    return result;
  }

  int _scoreYoutubeCandidate(
    _YoutubeCandidate candidate,
    String title,
    String artist,
    int index,
  ) {
    if (candidate.title.isEmpty) {
      return 1000 - index;
    }

    var score = 0;
    final candidateTitle = _normalize(candidate.title);
    final candidateAuthor = _normalize(candidate.author);
    final wantedTitle = _normalize(title);
    final wantedArtist = _normalize(artist);

    if (wantedTitle.isNotEmpty) {
      if (candidateTitle == wantedTitle) {
        score += 100;
      } else if (candidateTitle.contains(wantedTitle) ||
          wantedTitle.contains(candidateTitle)) {
        score += 70;
      } else if (_tokensOverlap(candidateTitle, wantedTitle)) {
        score += 30;
      }
    }

    if (wantedArtist.isNotEmpty) {
      if (candidateAuthor == wantedArtist) {
        score += 50;
      } else if (candidateAuthor.contains(wantedArtist) ||
          wantedArtist.contains(candidateAuthor)) {
        score += 30;
      }
    }

    if ((candidate.length ?? '').toUpperCase().contains('LIVE')) {
      score -= 40;
    }
    return score;
  }

  // --- Нормализация --------------------------------------------------------

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9а-яё\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _tokensOverlap(String left, String right) {
    final leftTokens = left.split(' ').where((token) => token.length > 2);
    final rightTokens = right.split(' ').where((token) => token.length > 2);
    return leftTokens.toSet().intersection(rightTokens.toSet()).isNotEmpty;
  }
}

class _CacheEntry {
  final ResolvedTrack? track;
  final DateTime expiresAt;

  const _CacheEntry(this.track, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class _YoutubeCandidate {
  final String id;
  final String title;
  final String author;
  final String? length;

  const _YoutubeCandidate({
    required this.id,
    required this.title,
    required this.author,
    this.length,
  });
}
