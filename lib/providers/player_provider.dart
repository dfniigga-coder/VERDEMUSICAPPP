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
  bool _preparing = false;

  /// Номер последнего запуска очереди. Нужен, чтобы запоздавший запуск
  /// (пока скачивалось превью) не перебил более новый выбор пользователя.
  int _playRequest = 0;

  /// Отдельный ValueNotifier, чтобы UI мог показывать снекбар без
  /// перерисовки всего дерева на каждое изменение.
  final ValueNotifier<String?> errorNotifier = ValueNotifier<String?>(null);

  AudioPlayerHandler get handler => _handler;

  // --- Состояние -----------------------------------------------------------

  bool get isPlaying => _playing;

  bool get isBuffering =>
      _processing == ProcessingState.buffering ||
      _processing == ProcessingState.loading;

  /// true — прямо сейчас получаем прямые аудиопотоки YouTube.
  /// UI показывает тонкую полоску прогресса, пока очередь готовится.
  bool get isPreparing => _preparing;

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
    _setPreparing(true);
    try {
      final startTrack = tracks[start];
      final downloads = _downloads;
      final needsFullMp3 =
          startTrack.isPreview && !startTrack.isLocal && downloads != null;

      // YouTube-треки приходят из поиска без прямого URL. Получаем их
      // параллельно: обычно это 0,5–2 секунды, после чего очередь
      // полностью готова к фоновому воспроизведению.
      final preparedFuture = Future.wait(
        tracks.map((track) => _prepareTrack(track)),
      );

      // Превью Deezer/iTunes — это 30 секунд. Вместо него скачиваем
      // полный трек в MP3 и играем локальный файл. Остальные треки
      // очереди готовим параллельно, чтобы не ждать дважды.
      Track? downloadedStart;
      if (needsFullMp3) {
        downloadedStart = await downloads.ensureDownloaded(startTrack);
        if (request != _playRequest) return;
        if (downloadedStart == null) {
          // Причина уже показана DownloadProvider (баннер/снекбар).
          return;
        }
      }

      final prepared = await preparedFuture;
      if (request != _playRequest) return;
      if (downloadedStart != null) prepared[start] = downloadedStart;

      final playable = <Track>[];
      var playableStart = -1;
      for (var i = 0; i < prepared.length; i++) {
        final track = prepared[i];
        // Другие превью не ставим в очередь: иначе автопереход снова
        // включит 30-секундный фрагмент.
        if (i != start && track.isPreview) continue;
        if (!_canPlay(track)) continue;
        if (i == start) playableStart = playable.length;
        playable.add(track);
      }

      if (playableStart < 0) {
        errorNotifier.value = prepared[start].source == TrackSource.youtube
            ? 'Не удалось получить аудио с YouTube. Выберите другой результат.'
            : 'Не удалось начать воспроизведение. Проверьте соединение.';
        return;
      }

      await _handler.playTracks(
        playable,
        startIndex: playableStart,
        shuffle: shuffle,
      );

      final recommendations = _recommendations;
      if (recommendations != null) {
        unawaited(recommendations.recordPlay(playable[playableStart]));
      }
    } catch (e) {
      if (request == _playRequest) {
        errorNotifier.value =
            'Не удалось начать воспроизведение. Проверьте соединение.';
      }
    } finally {
      if (request == _playRequest) _setPreparing(false);
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
    _playRequest++;
    try {
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

  Future<void> playAt(int index) {
    _playRequest++;
    return _handler.skipToQueueItem(index);
  }

  Future<void> addToQueue(Track track) async {
    final needsDownload = track.isPreview && !track.isLocal;
    final prepared = await _prepareQueueTrack(track);
    if (prepared == null) {
      if (!needsDownload) {
        errorNotifier.value = 'Не удалось получить аудио этого трека.';
      }
      return;
    }
    try {
      await _handler.addToQueue(prepared);
    } catch (_) {
      errorNotifier.value = 'Не удалось добавить трек в очередь.';
    }
  }

  Future<void> playNext(Track track) async {
    final needsDownload = track.isPreview && !track.isLocal;
    final prepared = await _prepareQueueTrack(track);
    if (prepared == null) {
      if (!needsDownload) {
        errorNotifier.value = 'Не удалось получить аудио этого трека.';
      }
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
  /// Превью Deezer/iTunes сначала скачиваем в MP3: в очереди не должно
  /// оставаться 30-секундных фрагментов.
  Future<Track?> _prepareQueueTrack(Track track) async {
    if (track.isPreview && !track.isLocal) {
      final downloads = _downloads;
      if (downloads == null) return null;

      final downloaded = await downloads.ensureDownloaded(track);
      if (downloaded == null || !_canPlay(downloaded)) return null;
      return downloaded;
    }

    final prepared = await _prepareTrack(track);
    return _canPlay(prepared) ? prepared : null;
  }

  bool _canPlay(Track track) {
    if (track.source == TrackSource.local) {
      return track.localPath?.isNotEmpty ?? false;
    }
    if (track.source == TrackSource.audius) {
      return track.audiusId?.isNotEmpty ?? false;
    }
    return track.streamUrl?.isNotEmpty ?? false;
  }

  Future<Track> _prepareTrack(Track track) async {
    if (track.source != TrackSource.youtube) return track;
    if (track.streamUrl?.isNotEmpty ?? false) return track;

    final youtube = _youtube;
    final videoId = track.externalId;
    if (youtube == null || videoId == null || videoId.isEmpty) return track;

    try {
      final audio = await youtube.audioFor(videoId);
      if (audio == null) return track;
      return track.copyWith(streamUrl: audio.url);
    } catch (error) {
      debugPrint('PlayerProvider: YouTube resolve failed for $videoId: $error');
      return track;
    }
  }

  void _setPreparing(bool value) {
    if (_preparing == value) return;
    _preparing = value;
    notifyListeners();
  }

  @override
  void dispose() {
    errorNotifier.dispose();
    super.dispose();
  }
}
