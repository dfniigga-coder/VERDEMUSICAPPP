import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../core/errors/app_exceptions.dart';
import '../data/models/track.dart';
import '../data/repositories/music_repository.dart';

/// Аудио-хендлер: связывает just_audio с audio_service.
///
/// Отвечает за очередь, метаданные уведомления (экран блокировки, кнопки
/// гарнитуры) и корректную работу в фоне. UI взаимодействует с ним
/// через [PlayerProvider], который оборачивает этот класс.
class AudioPlayerHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  AudioPlayerHandler(this._musicRepo)
    : _player = AudioPlayer(maxSkipsOnError: 2) {
    // Транслируем состояние just_audio в уведомление/клиентов.
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {},
    );

    // При смене позиции в очереди обновляем MediaItem уведомления.
    _player.currentIndexStream.listen((index) {
      _updateCurrentMediaItem(index);
    });
  }

  final MusicRepository _musicRepo;

  /// just_audio-плеер. UI читает его стримы (позиция, длительность) напрямую.
  final AudioPlayer _player;

  AudioPlayer get player => _player;

  /// Треки текущей очереди (индексы совпадают с источниками just_audio).
  final List<Track> _tracks = [];

  List<Track> get tracks => List.unmodifiable(_tracks);

  Track? trackAt(int index) {
    if (index >= 0 && index < _tracks.length) return _tracks[index];
    return null;
  }

  // --- Очередь -------------------------------------------------------------

  /// Воспроизводит список треков, начиная с [startIndex].
  Future<void> playTracks(
    List<Track> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) return;
    if (startIndex < 0 || startIndex >= tracks.length) startIndex = 0;

    _tracks
      ..clear()
      ..addAll(tracks);

    final sources = <AudioSource>[for (final t in tracks) _sourceFor(t)];

    if (shuffle && !_player.shuffleModeEnabled) {
      await _player.setShuffleModeEnabled(true);
    }
    if (!shuffle && _player.shuffleModeEnabled) {
      await _player.setShuffleModeEnabled(false);
    }

    await _player.setAudioSources(
      sources,
      initialIndex: startIndex,
      initialPosition: Duration.zero,
    );

    _updateCurrentMediaItem(startIndex);
    await _player.play();
  }

  /// Добавляет трек в конец очереди (или запускает, если очередь пуста).
  Future<void> addToQueue(Track track) async {
    final mediaItem = _mediaItemFor(track);
    if (_tracks.isEmpty) {
      await playTracks([track]);
      return;
    }
    _tracks.add(track);
    await addQueueItem(mediaItem);
    await _player.addAudioSource(_sourceFor(track));
  }

  /// Ставит трек играть следующим (после текущего).
  Future<void> playNext(Track track) async {
    final insertAt = (_player.currentIndex ?? -1) + 1;
    if (insertAt <= 0 || _tracks.isEmpty) {
      await addToQueue(track);
      return;
    }
    _tracks.insert(insertAt, track);
    await insertQueueItem(insertAt, _mediaItemFor(track));
    await _player.insertAudioSource(insertAt, _sourceFor(track));
  }

  /// Заменяет превью на полную версию в текущей очереди и запускает её.
  ///
  /// Если исходного трека в очереди нет (например, нажали «Слушать полностью»
  /// в результатах поиска), играет полную версию отдельной очередью.
  Future<void> playResolvedTrack(Track original, Track resolved) async {
    final index = _tracks.indexWhere((track) => track.id == original.id);
    if (index < 0) {
      await playTracks([resolved]);
      return;
    }

    _tracks[index] = resolved;
    final sources = <AudioSource>[
      for (final track in _tracks) _sourceFor(track),
    ];
    await _player.setAudioSources(
      sources,
      initialIndex: index,
      initialPosition: Duration.zero,
    );
    _updateCurrentMediaItem(index);
    await _player.play();
  }

  /// Убирает трек из очереди. Текущий трек удалить нельзя.
  Future<void> removeFromQueue(int index) async {
    final current = _player.currentIndex ?? -1;
    if (index < 0 || index >= _tracks.length || index == current) return;

    final item = queue.value[index];
    _tracks.removeAt(index);
    await removeQueueItem(item);
    await _player.removeAudioSourceAt(index);
  }

  /// Очищает очередь, оставляя только текущий трек.
  Future<void> clearQueue() async {
    final current = _player.currentIndex;
    if (current == null) return;
    for (var i = _tracks.length - 1; i > current; i--) {
      final item = queue.value[i];
      _tracks.removeAt(i);
      await removeQueueItem(item);
      await _player.removeAudioSourceAt(i);
    }
    for (var i = current - 1; i >= 0; i--) {
      final item = queue.value[i];
      _tracks.removeAt(i);
      await removeQueueItem(item);
      await _player.removeAudioSourceAt(i);
    }
  }

  // --- Элементарные операции ------------------------------------------------

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_tracks.isEmpty) return;
    try {
      // При включённом shuffle just_audio сам переходит по перемешанному
      // порядку; с LoopMode.all обход по кругу работает автоматически.
      await _player.seekToNext();
      await _player.play();
    } catch (_) {
      // на последнем треке — игнорируем
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_tracks.isEmpty) return;
    // Стандартное поведение: если прошло больше 3 секунд — перематываем
    // текущий трек в начало, иначе — переходим к предыдущему.
    if (_player.position.inSeconds >= 3) {
      await _player.seek(Duration.zero);
      return;
    }
    try {
      await _player.seekToPrevious();
      await _player.play();
    } catch (_) {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    await _player.seek(Duration.zero, index: index);
    _updateCurrentMediaItem(index);
    await _player.play();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    // Если ничего не играет — убиваем сервис; играющий трек в фоне live.
    final playing = _player.playing;
    await super.onTaskRemoved();
    if (!playing) await stop();
  }

  // --- Шаффл / повтор ------------------------------------------------------

  Future<void> toggleShuffle() async {
    final next = !_player.shuffleModeEnabled;
    await _player.setShuffleModeEnabled(next);
  }

  Future<void> cycleRepeat() async {
    final current = _player.loopMode;
    final next = switch (current) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      _ => LoopMode.off,
    };
    await _player.setLoopMode(next);
  }

  // --- Вспомогательное -----------------------------------------------------

  AudioSource _sourceFor(Track track) {
    if (track.source == TrackSource.youtube &&
        (track.streamUrl == null || track.streamUrl!.isEmpty)) {
      throw const TrackLoadException(
        'Аудиопоток YouTube ещё не получен. Попробуйте снова.',
      );
    }

    if (track.isAudius) {
      return AudioSource.uri(Uri.parse(_musicRepo.streamUrlFor(track)));
    }

    final streamUrl = track.streamUrl;
    if (streamUrl != null && streamUrl.isNotEmpty) {
      return AudioSource.uri(Uri.parse(streamUrl));
    }

    final localPath = track.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      return AudioSource.uri(Uri.file(localPath));
    }

    throw const TrackLoadException('У трека нет источника воспроизведения.');
  }

  MediaItem _mediaItemFor(Track track) {
    return MediaItem(
      id: track.id,
      album: track.isLocal ? 'Треки на устройстве' : track.source.label,
      title: track.title,
      artist: track.artist,
      duration: track.durationSec == null
          ? null
          : Duration(seconds: track.durationSec!),
      artUri: track.artworkUrl != null ? Uri.tryParse(track.artworkUrl!) : null,
    );
  }

  void _updateCurrentMediaItem(int? index) {
    final track = index == null ? null : trackAt(index);
    if (track == null) {
      mediaItem.add(queue.value.isEmpty ? null : queue.value.first);
      return;
    }
    // Очередь может быть ещё не обновлённой — строим MediaItem по треку.
    final media = _mediaItemFor(track);
    mediaItem.add(media);
  }

  /// Преобразует событие just_audio в PlaybackState для audio_service:
  /// кнопки уведомления (4 позиции, 3 компактные), seek, статус.
  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final processingState = _player.processingState;

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ),
    );
  }
}
