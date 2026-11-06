import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/models/track.dart';
import '../services/audio_player_handler.dart';

/// UI-состояние плеера. Обёртка вокруг [AudioPlayerHandler]:
/// хранит флаги для экранов и делегирует команды аудио-хендлеру.
class PlayerProvider extends ChangeNotifier {
  PlayerProvider(this._handler) {
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
