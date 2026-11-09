import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/models/track.dart';
import '../services/audio_player_handler.dart';
import '../services/recommendation_service.dart';

/// UI-состояние плеера. Обёртка вокруг [AudioPlayerHandler]:
/// хранит флаги для экранов и делегирует команды аудио-хендлеру.
class PlayerProvider extends ChangeNotifier {
  PlayerProvider(this._handler, {RecommendationService? recommendations})
    : _recommendations = recommendations {
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

  bool _playing = false;
  ProcessingState _processing = ProcessingState.idle;
  int? _currentIndex;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;
  double _volume = 1.0;

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
    try {
      await _handler.playTracks(
        tracks,
        startIndex: startIndex,
        shuffle: shuffle,
      );

      final recommendations = _recommendations;
      if (recommendations != null && tracks.isNotEmpty) {
        var start = startIndex;
        if (start < 0 || start >= tracks.length) start = 0;
        unawaited(recommendations.recordPlay(tracks[start]));
      }
    } catch (e) {
      errorNotifier.value =
          'Не удалось начать воспроизведение. Проверьте соединение.';
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

  Future<void> playAt(int index) => _handler.skipToQueueItem(index);

  Future<void> addToQueue(Track track) => _handler.addToQueue(track);

  Future<void> playNext(Track track) => _handler.playNext(track);

  Future<void> removeFromQueue(int index) => _handler.removeFromQueue(index);

  Future<void> clearQueue() => _handler.clearQueue();

  Future<void> toggleShuffle() => _handler.toggleShuffle();

  Future<void> cycleRepeat() => _handler.cycleRepeat();

  Future<void> setVolume(double value) {
    final v = value.clamp(0.0, 1.0);
    return _handler.player.setVolume(v);
  }

  @override
  void dispose() {
    errorNotifier.dispose();
    super.dispose();
  }
}
