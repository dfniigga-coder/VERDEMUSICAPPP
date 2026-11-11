import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/models/track.dart';
import '../services/audio_player_handler.dart';
import '../services/recommendation_service.dart';
import '../services/youtube_service.dart';
import 'download_provider.dart';

/// UI-состояние плеера. Обёртка вокруг [AudioPlayerHandler]:
/// хранит флаги для экранов и делегирует команды аудио-хендлеру.
///
/// Треки запускаются сразу: YouTube-источники создаются лениво по videoId,
/// а превью Deezer/iTunes играет 30-секундный фрагмент, пока в фоне ищется
/// полная версия. Поэтому нажатие «Играть» больше не ждёт скачивания MP3.
class PlayerProvider extends ChangeNotifier {
  PlayerProvider(
    this._handler, {
    RecommendationService? recommendations,
    YoutubeService? youtube,
    DownloadProvider? downloads,
  }) : _recommendations = recommendations,
       _youtube = youtube,
       _downloads = downloads {
    _handler.playbackState.map((s) => s.playing).distinct().listen((playing) {
      _playing = playing;
      notifyListeners();
    });

    _handler.player.processingStateStream.listen((state) {
      _processing = state;
      notifyListeners();
    });

    _handler.player.currentIndexStream.listen((index) {
      _currentIndex = index;
      notifyListeners();

      final track = _handler.trackAt(index ?? -1);
      final recommendations = _recommendations;
      if (track != null && recommendations != null) {
        unawaited(recommendations.recordPlay(track));
      }
    });

    _handler.player.shuffleModeEnabledStream.listen((enabled) {
      _shuffle = enabled;
      notifyListeners();
    });

    _handler.player.loopModeStream.listen((mode) {
      _loopMode = mode;
      notifyListeners();
    });

    _handler.player.volumeStream.listen((volume) {
      _volume = volume;
      notifyListeners();
    });

    // Ошибка загрузки трека: если можно, just_audio автоматически перейдёт
    // к следующему (maxSkipsOnError), о чём сообщаем пользователю.
    _handler.player.errorStream.listen((_) {
      final more = _handler.player.hasNext;
      errorNotifier.value = more
          ? 'Трек не загрузился, переходим к следующему…'
          : 'Трек не загрузился. Проверьте соединение и попробуйте ещё раз.';
    });
  }

  final AudioPlayerHandler _handler;
  final RecommendationService? _recommendations;
  final YoutubeService? _youtube;
  final DownloadProvider? _downloads;

  bool _playing = false;
  ProcessingState _processing = ProcessingState.idle;
  int? _currentIndex;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;
  double _volume = 1.0;

  /// Номер последнего запуска очереди. Нужен, чтобы запоздавший апгрейд
  /// превью не подменил трек уже другой очереди.
  int _playRequest = 0;

  /// Поиски полной версии, которые уже идут: повторное нажатие на тот же
  /// трек не запускает второй поиск YouTube.
  final Map<String, Future<Track?>> _fullTrackInFlight = {};

  /// Отдельный ValueNotifier, чтобы UI мог показывать снекбар без
  /// перерисовки всего дерева на каждое изменение.
  final ValueNotifier<String?> errorNotifier = ValueNotifier<String?>(null);

  AudioPlayerHandler get handler => _handler;

  // --- Состояние -----------------------------------------------------------

  bool get isPlaying => _playing;

  bool get isBuffering =>
      _processing == ProcessingState.buffering ||
      _processing == ProcessingState.loading;

  bool get hasQueue => _handler.tracks.isNotEmpty;

  int get queueLength => _handler.tracks.length;

  List<Track> get queue => _handler.tracks;

  int? get currentIndex => _currentIndex;

  Track? get currentTrack => _handler.trackAt(_currentIndex ?? -1);

  bool get isShuffleEnabled => _shuffle;

  bool get isRepeatAll => _loopMode == LoopMode.all;

  bool get isRepeatOne => _loopMode == LoopMode.one;

  /// 0.0–1.0.
  double get volume => _volume;

  // --- Команды -------------------------------------------------------------

  Future<void> playTracks(
    List<Track> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) return;

    var start = startIndex;
    if (start < 0 || start >= tracks.length) start = 0;

    final request = ++_playRequest;
    try {
      final startTrack = tracks[start];

      // Очередь собирается мгновенно: для YouTube достаточно videoId,
      // а превью не требуют сетевых запросов. Другие превью в очередь
      // не ставим, иначе автопереход снова включит 30-секундный фрагмент.
      // Уже скачанный MP3 подставляется сразу — он играет без сети.
      final playable = <Track>[];
      var playableStart = -1;
      Track? playableStartTrack;
      for (var i = 0; i < tracks.length; i++) {
        final track = _localCopy(tracks[i]);
        if (i != start && track.isPreview) continue;
        if (!_canPlay(track)) continue;
        if (i == start) {
          playableStart = playable.length;
          playableStartTrack = track;
        }
        playable.add(track);
      }

      if (playableStart < 0 || playableStartTrack == null) {
        errorNotifier.value = startTrack.source == TrackSource.youtube
            ? 'Не удалось получить аудио с YouTube. Выберите другой результат.'
            : 'Не удалось начать воспроизведение. Проверьте соединение.';
        return;
      }

      await _handler.playTracks(
        playable,
        startIndex: playableStart,
        shuffle: shuffle,
      );

      // Превью уже играет — ищем полную версию в фоне и подменяем
      // источник через replaceTrack, не останавливая воспроизведение.
      if (request == _playRequest &&
          playableStartTrack.isPreview &&
          !playableStartTrack.isLocal) {
        _upgradePreview(startTrack, request);
      }
    } catch (e) {
      if (request == _playRequest) {
        errorNotifier.value =
            'Не удалось начать воспроизведение. Проверьте соединение.';
      }
    }
  }

  Future<void> togglePlay() async {
    try {
      if (_playing) {
        await _handler.pause();
      } else {
        await _handler.play();
      }
    } catch (e) {
      errorNotifier.value = 'Не удалось запустить трек.';
    }
  }

  /// Пауза нужна YouTube-плееру, чтобы не было наложения звука.
  Future<void> pause() async {
    try {
      await _handler.pause();
    } catch (e) {
      errorNotifier.value = 'Не удалось поставить трек на паузу.';
    }
  }

  /// Возобновление обычного плеера после закрытия YouTube.
  Future<void> resume() async {
    try {
      await _handler.play();
    } catch (e) {
      errorNotifier.value = 'Не удалось возобновить воспроизведение.';
    }
  }

  /// Подменяет превью на полную версию в существующей очереди и играет её.
  ///
  /// Возвращает `false`, если запуск не удался: UI не должен показывать
  /// сообщение об успехе в этом случае.
  Future<bool> playResolvedTrack(Track original, Track resolved) async {
    // Отменяем фоновый апгрейд этого же превью: полная версия уже найдена.
    _playRequest++;
    try {
      if (!_canPlay(resolved)) {
        errorNotifier.value = 'Не удалось включить полную версию.';
        return false;
      }
      await _handler.playResolvedTrack(original, resolved);
      return true;
    } catch (e) {
      errorNotifier.value = 'Не удалось включить полную версию.';
      return false;
    }
  }

  Future<void> next() => _handler.skipToNext();

  Future<void> previous() => _handler.skipToPrevious();

  Future<void> seek(Duration position) => _handler.seek(position);

  Future<void> playAt(int index) => _handler.skipToQueueItem(index);

  Future<void> addToQueue(Track track) async {
    final prepared = await _prepareQueueTrack(track);
    if (prepared == null) {
      errorNotifier.value = track.isPreview && !track.isLocal
          ? 'Не удалось найти полную версию трека.'
          : 'Не удалось получить аудио этого трека.';
      return;
    }
    try {
      await _handler.addToQueue(prepared);
    } catch (_) {
      errorNotifier.value = 'Не удалось добавить трек в очередь.';
    }
  }

  Future<void> playNext(Track track) async {
    final prepared = await _prepareQueueTrack(track);
    if (prepared == null) {
      errorNotifier.value = track.isPreview && !track.isLocal
          ? 'Не удалось найти полную версию трека.'
          : 'Не удалось получить аудио этого трека.';
      return;
    }
    try {
      await _handler.playNext(prepared);
    } catch (_) {
      errorNotifier.value = 'Не удалось поставить трек следующим.';
    }
  }

  Future<void> removeFromQueue(int index) => _handler.removeFromQueue(index);

  Future<void> clearQueue() => _handler.clearQueue();

  Future<void> toggleShuffle() => _handler.toggleShuffle();

  Future<void> cycleRepeat() => _handler.cycleRepeat();

  Future<void> setVolume(double value) {
    final v = value.clamp(0.0, 1.0);
    return _handler.player.setVolume(v);
  }

  // --- Подготовка треков ----------------------------------------------------

  /// Готовит трек для добавления в очередь.
  ///
  /// Превью Deezer/iTunes сначала превращаем в полную версию YouTube:
  /// в очереди не должно оставаться 30-секундных фрагментов. Остальные
  /// треки уже готовы к ленивому созданию источника.
  Future<Track?> _prepareQueueTrack(Track track) async {
    final local = _localCopy(track);
    if (local.isLocal && (local.localPath?.isNotEmpty ?? false)) return local;

    if (track.isPreview && !track.isLocal) {
      final full = await _findFullTrack(track);
      return full != null && _canPlay(full) ? full : null;
    }
    return _canPlay(track) ? track : null;
  }

  /// Запускает фоновый поиск полной версии для стартового превью.
  void _upgradePreview(Track preview, int request) {
    if (!preview.isPreview || preview.isLocal || _youtube == null) return;

    unawaited(() async {
      final full = await _findFullTrack(preview);
      if (full == null || request != _playRequest) return;

      try {
        await _handler.replaceTrack(preview, full);
      } catch (error) {
        debugPrint(
          'PlayerProvider: upgrade failed for ${preview.title}: $error',
        );
      }
    }());
  }

  /// Ищет полную версию превью на YouTube.
  ///
  /// Возвращает трек с тем же [Track.id], что и превью: очередь, лайки и
  /// история остаются привязанными к исходному треку. Повторные вызовы
  /// для одного трека переиспользуют уже идущий поиск.
  Future<Track?> _findFullTrack(Track preview) {
    // Уже скачанный MP3 — самый быстрый «полный трек»: сеть не нужна.
    final local = _localCopy(preview);
    if (local.isLocal && (local.localPath?.isNotEmpty ?? false)) {
      return Future.value(local);
    }

    final id = preview.id;
    final running = _fullTrackInFlight[id];
    if (running != null) return running;

    final future = _lookupFullTrack(preview);
    _fullTrackInFlight[id] = future;
    unawaited(
      future.whenComplete(() {
        _fullTrackInFlight.remove(id);
      }),
    );
    return future;
  }

  Future<Track?> _lookupFullTrack(Track preview) async {
    final youtube = _youtube;
    if (youtube == null) return null;

    try {
      final match = await youtube.findBest(
        preview.title,
        preview.artist,
        // 30 секунд превью — не настоящая длительность, поэтому
        // подсказку по времени не передаём. Отсекаем только Shorts.
        minDurationSec: 60,
      );
      if (match == null) return null;

      return Track.youtube(
        videoId: match.videoId,
        title: preview.title,
        artist: preview.artist,
        artworkUrl: preview.artworkUrl ?? match.artworkUrl,
        durationSec: match.durationSec,
      ).copyWith(idOverride: preview.id);
    } catch (error) {
      debugPrint(
        'PlayerProvider: full track lookup failed for ${preview.title}: '
        '$error',
      );
      return null;
    }
  }

  /// Подставляет уже скачанный MP3 вместо сетевого источника.
  ///
  /// Идентификатор исходного трека сохраняется, поэтому лайки, плейлисты
  /// и история прослушиваний продолжают работать как раньше.
  Track _localCopy(Track track) {
    final downloads = _downloads;
    if (downloads == null || track.isLocal) return track;

    final downloaded = downloads.findDownloaded(track);
    if (downloaded == null) return track;

    final path = downloaded.localPath;
    if (path == null || path.isEmpty) return track;
    return downloaded.copyWith(idOverride: track.id);
  }

  bool _canPlay(Track track) {
    if (track.source == TrackSource.local) {
      return track.localPath?.isNotEmpty ?? false;
    }
    if (track.source == TrackSource.audius) {
      return track.audiusId?.isNotEmpty ?? false;
    }
    if (track.source == TrackSource.youtube) {
      // Invidious-ссылка строится лениво из videoId в AudioPlayerHandler.
      return (track.externalId?.isNotEmpty ?? false) ||
          (track.streamUrl?.isNotEmpty ?? false);
    }
    return track.streamUrl?.isNotEmpty ?? false;
  }

  @override
  void dispose() {
    errorNotifier.dispose();
    super.dispose();
  }
}
