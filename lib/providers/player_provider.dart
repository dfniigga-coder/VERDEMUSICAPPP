import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../core/errors/app_exceptions.dart';
import '../data/models/track.dart';
import '../services/audio_player_handler.dart';
import '../services/recommendation_service.dart';
import '../services/youtube_service.dart';
import 'download_provider.dart';

/// Пресеты звучания: скорость воспроизведения и высота тона.
enum AudioVibePreset {
  normal('Оригинал', 1.0, 1.0),
  slowed('Slowed · 0.85x', 0.85, 0.88),
  nightcore('Nightcore · 1.22x', 1.22, 1.22),
  boosted('Динамика · 1.12x', 1.12, 1.0),
  custom('Свой режим', 1.0, 1.0);

  final String label;
  final double speed;
  final double pitch;

  const AudioVibePreset(this.label, this.speed, this.pitch);

  String get badge {
    switch (this) {
      case AudioVibePreset.normal:
        return '';
      case AudioVibePreset.slowed:
        return 'SLOWED';
      case AudioVibePreset.nightcore:
        return 'NIGHTCORE';
      case AudioVibePreset.boosted:
        return '1.12x';
      case AudioVibePreset.custom:
        return 'SPEED';
    }
  }
}

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
    _bind(_handler.playbackState.map((state) => state.playing).distinct(), (
      playing,
    ) {
      _playing = playing;
      _notify();
    });

    _bind(_handler.player.processingStateStream, (state) {
      _processing = state;
      if (state == ProcessingState.completed && _sleepEndOfTrack) {
        _sleepEndOfTrack = false;
        unawaited(pause());
      }
      _notify();
    });

    _bind(_handler.player.currentIndexStream, (index) {
      final changed = _currentIndex != null && index != _currentIndex;
      _currentIndex = index;
      if (changed && _sleepEndOfTrack) {
        _sleepEndOfTrack = false;
        unawaited(pause());
      }
      _notify();

      final track = _handler.trackAt(index ?? -1);
      final recommendations = _recommendations;
      if (track != null && recommendations != null) {
        unawaited(recommendations.recordPlay(track));
      }
    });

    _bind(_handler.player.shuffleModeEnabledStream, (enabled) {
      _shuffle = enabled;
      _notify();
    });

    _bind(_handler.player.loopModeStream, (mode) {
      _loopMode = mode;
      _notify();
    });

    _bind(_handler.player.volumeStream, (volume) {
      _volume = volume;
      _notify();
    });

    _bind(_handler.player.speedStream, (speed) {
      if ((_speed - speed).abs() > 0.01) {
        _speed = speed;
        _notify();
      }
    });

    // Позиция и длительность обновляются несколько раз в секунду.
    // Их НЕ прогоняем через notifyListeners: иначе каждый тик перестраивал
    // бы весь список треков и очередь. Виджеты прогресса слушают
    // positionStream/durationStream напрямую (см. MiniPlayerBar).

    // Ошибка загрузки трека: если можно, just_audio автоматически перейдёт
    // к следующему (maxSkipsOnError), о чём сообщаем пользователю.
    _bind(_handler.player.errorStream, (_) {
      if (_disposed) return;
      final more = _handler.player.hasNext;
      errorNotifier.value = more
          ? 'Трек не загрузился, переходим к следующему…'
          : 'Трек не загрузился. Проверьте соединение и попробуйте ещё раз.';
    });
  }

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _disposed = false;

  void _bind<T>(Stream<T> stream, void Function(T value) onData) {
    _subscriptions.add(stream.listen(onData));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
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

  // Скорость, тон и пресет звучания.
  double _speed = 1.0;
  double _pitch = 1.0;
  AudioVibePreset _preset = AudioVibePreset.normal;

  // Таймер сна.
  Timer? _sleepTimer;
  DateTime? _sleepDeadline;
  bool _sleepEndOfTrack = false;

  /// Номер последнего запуска очереди. Нужен, чтобы запоздавший апгрейд
  /// превью не подменил трек уже другой очереди.
  int _playRequest = 0;

  /// Поиски полной версии, которые уже идут: повторное нажатие на тот же
  /// трек не запускает второй поиск YouTube.
  final Map<String, Future<Track?>> _fullTrackInFlight = {};

  /// Отдельный ValueNotifier, чтобы UI мог показывать снекбар без
  /// перерисовки всего дерева на каждое изменение.
  final ValueNotifier<String?> errorNotifier = ValueNotifier<String?>(null);

  /// Оставшееся время таймера сна (обновляется каждую секунду без лишних rebuild).
  final ValueNotifier<Duration?> sleepRemainingNotifier =
      ValueNotifier<Duration?>(null);

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

  double get speed => _speed;

  double get pitch => _pitch;

  AudioVibePreset get audioPreset => _preset;

  bool get hasCustomAudioEffect =>
      _preset != AudioVibePreset.normal ||
      (_speed - 1.0).abs() > 0.01 ||
      (_pitch - 1.0).abs() > 0.01;

  bool get sleepEndOfTrack => _sleepEndOfTrack;

  bool get hasSleepTimer =>
      _sleepEndOfTrack || sleepRemainingNotifier.value != null;

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
    } on AppException catch (error) {
      if (request == _playRequest) {
        errorNotifier.value = error.message;
      }
    } catch (e) {
      if (request == _playRequest) {
        errorNotifier.value =
            'Не удалось начать воспроизведение. Проверьте соединение.';
      }
    }
  }

  /// Запускает бесконечную волну похожих треков на основе [seed].
  Future<bool> startTrackRadio(Track seed) async {
    final recommendations = _recommendations;
    if (recommendations == null) {
      await playTracks([seed]);
      return true;
    }

    try {
      final similar = await recommendations.getSimilarTracks(seed);
      final radio = <Track>[seed];
      final seen = <String>{seed.id};
      for (final track in similar) {
        if (seen.add(track.id)) {
          radio.add(track);
        }
      }
      await playTracks(radio, startIndex: 0);
      return true;
    } catch (_) {
      errorNotifier.value = 'Не удалось собрать волну по треку.';
      return false;
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
      errorNotifier.value = 'Не удалось возозобновить воспроизведение.';
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
    } on AppException catch (error) {
      errorNotifier.value = error.message;
      return false;
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

  // --- Скорость, тон и пресеты ---------------------------------------------

  Future<void> setAudioPreset(AudioVibePreset preset) async {
    if (preset == AudioVibePreset.custom) return;
    _preset = preset;
    _speed = preset.speed;
    _pitch = preset.pitch;
    _notify();
    await _applySpeedAndPitch(_speed, _pitch);
  }

  Future<void> setCustomSpeedPitch({
    required double speed,
    double? pitch,
  }) async {
    _speed = speed.clamp(0.5, 2.0);
    if (pitch != null) {
      _pitch = pitch.clamp(0.7, 1.4);
    }
    if ((_speed - 1.0).abs() <= 0.01 && (_pitch - 1.0).abs() <= 0.01) {
      _preset = AudioVibePreset.normal;
      _speed = 1.0;
      _pitch = 1.0;
    } else {
      _preset = AudioVibePreset.custom;
    }
    _notify();
    await _applySpeedAndPitch(_speed, _pitch);
  }

  Future<void> _applySpeedAndPitch(double speed, double pitch) async {
    try {
      await _handler.player.setSpeed(speed);
    } catch (_) {}
    try {
      await _handler.player.setPitch(pitch);
    } catch (_) {
      // setPitch поддерживается не на всех платформах.
    }
  }

  // --- Таймер сна ----------------------------------------------------------

  void setSleepTimer(Duration? duration, {bool endOfTrack = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepDeadline = null;

    if (endOfTrack) {
      _sleepEndOfTrack = true;
      sleepRemainingNotifier.value = null;
      _notify();
      return;
    }

    _sleepEndOfTrack = false;
    if (duration == null || duration <= Duration.zero) {
      sleepRemainingNotifier.value = null;
      _notify();
      return;
    }

    _sleepDeadline = DateTime.now().add(duration);
    sleepRemainingNotifier.value = duration;
    _notify();

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed || _sleepDeadline == null) {
        timer.cancel();
        return;
      }
      final left = _sleepDeadline!.difference(DateTime.now());
      if (left <= Duration.zero) {
        timer.cancel();
        _sleepTimer = null;
        _sleepDeadline = null;
        sleepRemainingNotifier.value = null;
        _notify();
        unawaited(_fadeOutAndPause());
      } else {
        sleepRemainingNotifier.value = left;
      }
    });
  }

  void cancelSleepTimer() => setSleepTimer(null);

  Future<void> _fadeOutAndPause() async {
    final originalVolume = _volume;
    try {
      const steps = 6;
      for (var i = steps - 1; i >= 0; i--) {
        if (_disposed) return;
        await _handler.player.setVolume(originalVolume * (i / steps));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      await _handler.pause();
    } catch (_) {
      // Игнорируем ошибку затухания, пауза важнее.
    } finally {
      if (!_disposed) {
        try {
          await _handler.player.setVolume(originalVolume);
        } catch (_) {}
      }
    }
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
    _disposed = true;
    _sleepTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    errorNotifier.dispose();
    sleepRemainingNotifier.dispose();
    super.dispose();
  }
}
