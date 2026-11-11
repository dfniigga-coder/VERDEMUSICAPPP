import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:soundcloud_explode_dart/soundcloud_explode_dart.dart';

import '../core/constants.dart';
import '../data/models/resolved_track.dart';
import 'youtube_service.dart';

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
  } on YoutubeException catch (error) {
    debugPrint('FullTrackResolver[$source]: YouTube error: ${error.message}');
  } on FormatException catch (error) {
    debugPrint('FullTrackResolver[$source]: bad response: ${error.message}');
  } catch (error) {
    debugPrint('FullTrackResolver[$source]: $error');
  }
  return null;
}

/// Ищет полную версию трека сначала на YouTube, затем на SoundCloud.
///
/// YouTube через VISIONOS отдаёт прямой аудиопоток (m4a/webm) за пару
/// секунд, поэтому трек играет в обычном плеере и в фоне. SoundCloud —
/// запасной источник с готовым stream URL. Если поток получить не удалось,
/// остаётся videoId — UI откроет встроенный iFrame-плеер.
class FullTrackResolver {
  FullTrackResolver({required YoutubeService youtube, http.Client? httpClient})
    : _youtube = youtube,
      _ownsHttpClient = httpClient == null,
      _http = httpClient ?? http.Client() {
    _soundcloud = SoundcloudClient(httpClient: _http);
  }

  static const Duration _cacheTtl = Duration(minutes: 10);
  static const Duration _negativeCacheTtl = Duration(minutes: 2);

  final YoutubeService _youtube;
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
    // YouTube первым: прямой VISIONOS-поток стартует за пару секунд.
    // SoundCloud остаётся запасным источником, если поток не получен.
    final youtube = await _resolveYoutube(title, artist);
    if (youtube != null && youtube.canPlayInJustAudio) return youtube;

    final soundcloud = await _resolveSoundcloud(title, artist);
    if (soundcloud != null) return soundcloud;

    if (youtube == null) {
      debugPrint('FullTrackResolver: no full source for "$title — $artist"');
    }
    return youtube;
  }

  Future<ResolvedTrack?> _resolveYoutube(String title, String artist) async {
    final match = await safeRequest<YoutubeMatch?>(
      () => _youtube.findBest(title, artist, minDurationSec: 60),
      source: 'youtube.search',
    );
    if (match == null) return null;

    final audio = await safeRequest<YoutubeAudio?>(
      () => _youtube.audioFor(match.videoId),
      source: 'youtube.audio',
    );

    return ResolvedTrack(
      title: match.title.trim().isEmpty ? title : match.title,
      artist: match.artist.trim().isEmpty ? artist : match.artist,
      artworkUrl: match.artworkUrl,
      streamUrl: audio?.url,
      source: FullTrackSource.youtube,
      isFullTrack: true,
      youtubeVideoId: match.videoId,
      externalId: match.videoId,
      durationSec: match.durationSec,
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

  // --- Нормализация --------------------------------------------------------

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), ' ')
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
