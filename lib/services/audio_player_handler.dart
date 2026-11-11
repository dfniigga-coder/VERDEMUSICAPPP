import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../core/errors/app_exceptions.dart';
import '../data/models/track.dart';
import '../data/repositories/music_repository.dart';
import 'youtube_service.dart';

/// Аудио-хендлер: связывает just_audio с audio_service.
///
/// Отвечает за очередь, метаданные уведомления (экран блокировки, кнопки
/// гарнитуры) и корректную работу в фоне. UI взаимодействует с ним
/// через [PlayerProvider], который оборачивает этот класс.
class AudioPlayerHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  AudioPlayerHandler(this._musicRepo, this._youtube)
    : _player = AudioPlayer(maxSkipsOnError: 2) {
    // Транслируем состояние just_audio в уведомление/клиентов.
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {},
    );

    // При смене позиции в очереди обновляем MediaItem уведомления и
    // заранее готовим прямые ссылки для следующих треков.
    _player.currentIndexStream.listen((index) {
      _updateCurrentMediaItem(index);
      if (index != null) _prefetchUpcoming(index);
    });
  }

  final MusicRepository _musicRepo;
  final YoutubeService _youtube;

  /// just_audio-плеер. UI читает его стримы (позиция, длительность) напрямую.
  final AudioPlayer _player;

  AudioPlayer get player => _player;

  /// Треки текущей очереди (индексы совпадают с источниками just_audio).
  final List<Track> _tracks = [];

  /// Замены источников выполняются последовательно: remove/insert сдвигают
  /// индексы, и параллельные обновления могли бы перепутать очередь.
  Future<void> _sourceReplaceQueue = Future<void>.value();

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

    // Держим очередь audio_service в том же порядке, что и _tracks:
    // addToQueue/removeFromQueue/clearQueue работают с queue.value.
    // Список должен быть изменяемым: QueueHandler добавляет элементы на месте.
    queue.add([for (final t in tracks) _mediaItemFor(t)]);

    // Текущий трек получает прямой googlevideo-URL: это 1–2 секунды до
    // звука вместо минуты через публичный Invidious-прокси. Остальные
    // источники создаются без сети и обновляются в фоне.
    final startSource = await _sourceForAsync(tracks[startIndex]);
    final sources = <AudioSource>[
      for (var i = 0; i < tracks.length; i++)
        i == startIndex ? startSource : _sourceFor(tracks[i]),
    ];

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
    unawaited(_player.play());
    _prefetchUpcoming(startIndex);
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
    _prefetchUpcoming(_player.currentIndex ?? 0);
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
    _prefetchUpcoming(_player.currentIndex ?? 0);
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

    final resolvedSource = await _sourceForAsync(resolved);
    _tracks[index] = resolved;
    _updateQueueItemAt(index, resolved);
    final sources = <AudioSource>[
      for (var i = 0; i < _tracks.length; i++)
        i == index ? resolvedSource : _sourceFor(_tracks[i]),
    ];
    await _player.setAudioSources(
      sources,
      initialIndex: index,
      initialPosition: Duration.zero,
    );
    _updateCurrentMediaItem(index);
    unawaited(_player.play());
    _prefetchUpcoming(index);
  }

  /// Заменяет трек в очереди, не сбрасывая остальные источники.
  ///
  /// Нужен для фонового апгрейда 30-секундного превью до полной версии.
  /// Если трек сейчас играет, источник перезапускается с начала: у превью
  /// и полной версии разные временные шкалы, поэтому сохранять позицию
  /// бессмысленно.
  Future<void> replaceTrack(Track original, Track replacement) async {
    final initialIndex = _tracks.indexWhere((track) => track.id == original.id);
    if (initialIndex < 0) return;

    // Источник строим до изменения списка: если он недоступен, очередь
    // остаётся прежней и текущее воспроизведение не прерывается.
    final source = await _sourceForAsync(replacement);

    // Пока шёл поиск, очередь могли изменить.
    final index = _tracks.indexWhere((track) => track.id == original.id);
    if (index < 0) return;
    final current = _player.currentIndex;

    _tracks[index] = replacement;
    _updateQueueItemAt(index, replacement);

    if (index == current) {
      final wasPlaying = _player.playing;
      final sources = <AudioSource>[
        for (var i = 0; i < _tracks.length; i++)
          i == index ? source : _sourceFor(_tracks[i]),
      ];
      await _player.setAudioSources(
        sources,
        initialIndex: index,
        initialPosition: Duration.zero,
      );
      _updateCurrentMediaItem(index);
      if (wasPlaying) unawaited(_player.play());
      _prefetchUpcoming(index);
      return;
    }

    await _player.removeAudioSourceAt(index);
    await _player.insertAudioSource(index, source);
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
  Future<void> play() async {
    unawaited(_player.play());
  }

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
      final next = _player.nextIndex;
      if (next == null) return;
      await _upgradeSourceAt(next, allowCurrent: true);
      await _player.seekToNext();
      unawaited(_player.play());
      _prefetchUpcoming(next);
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
      final previous = _player.previousIndex;
      if (previous != null) {
        await _upgradeSourceAt(previous, allowCurrent: true);
      }
      await _player.seekToPrevious();
      unawaited(_player.play());
      if (previous != null) _prefetchUpcoming(previous);
    } catch (_) {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    await _upgradeSourceAt(index, allowCurrent: true);
    await _player.seek(Duration.zero, index: index);
    _updateCurrentMediaItem(index);
    unawaited(_player.play());
    _prefetchUpcoming(index);
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
    if (track.source == TrackSource.youtube) {
      // Готовый прямой поток (например, из FullTrackResolver) играет без
      // Invidious-прокси и стартует сразу.
      final direct = _directStreamUrl(track);
      if (direct != null) return AudioSource.uri(Uri.parse(direct));

      // videoId приоритетнее streamUrl: у полной версии из ResolvedTrack
      // в streamUrl мог остаться 30-секундный URL превью. Invidious-ссылку
      // строим здесь, без запроса манифеста.
      final url = _youtubeUrlFor(track);
      if (url == null) {
        throw const TrackLoadException(
          'У трека нет идентификатора YouTube. Выберите другой результат.',
        );
      }
      // just_audio сам поднимет локальный прокси и пробросит Range.
      return AudioSource.uri(
        Uri.parse(url),
        headers: YoutubeService.streamHeaders,
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

  /// URL для YouTube-трека: videoId → Invidious, иначе готовый streamUrl.
  String? _youtubeUrlFor(Track track) {
    final videoId = track.externalId;
    if (videoId != null && videoId.isNotEmpty) {
      return _youtube.playbackUrl(videoId);
    }
    final streamUrl = track.streamUrl;
    if (streamUrl != null && streamUrl.isNotEmpty) return streamUrl;
    return null;
  }

  /// Строит источник для трека, дожидаясь прямого googlevideo-URL.
  ///
  /// Для локальных, Audius и SoundCloud-треков URL уже известен, поэтому
  /// метод возвращает его мгновенно. YouTube-треки резолвятся через
  /// VISIONOS-манифест (1–2 секунды) и только при ошибке падают обратно
  /// на медленный Invidious-прокси.
  Future<AudioSource> _sourceForAsync(Track track) async {
    if (track.source != TrackSource.youtube) return _sourceFor(track);

    final direct = _directStreamUrl(track);
    if (direct != null) return AudioSource.uri(Uri.parse(direct));

    final videoId = track.externalId;
    if (videoId != null && videoId.isNotEmpty) {
      final resolved = await _youtube.playbackStreamUrl(videoId);
      if (resolved != null && resolved.isNotEmpty) {
        return AudioSource.uri(Uri.parse(resolved));
      }
    }
    return _sourceFor(track);
  }

  String? _directStreamUrl(Track track) {
    final streamUrl = track.streamUrl;
    if (streamUrl == null || streamUrl.isEmpty) return null;
    final host = Uri.tryParse(streamUrl)?.host ?? '';
    return host.endsWith('googlevideo.com') ? streamUrl : null;
  }

  /// Подменяет Invidious-заглушку на прямой поток в фоне.
  ///
  /// Очередь не ждёт: текущий трек уже играет, а следующие источники
  /// обновляются до того, как до них дойдёт автопереход.
  Future<bool> _upgradeSourceAt(int index, {bool allowCurrent = false}) {
    final result = _sourceReplaceQueue.then(
      (_) => _upgradeSourceAtNow(index, allowCurrent: allowCurrent),
    );
    _sourceReplaceQueue = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<bool> _upgradeSourceAtNow(
    int index, {
    required bool allowCurrent,
  }) async {
    if (index < 0 || index >= _tracks.length) return false;

    final track = _tracks[index];
    if (track.source != TrackSource.youtube) return false;
    if (_directStreamUrl(track) != null) return false;

    final videoId = track.externalId;
    if (videoId == null || videoId.isEmpty) return false;

    final url = await _youtube.playbackStreamUrl(videoId);
    if (url == null || url.isEmpty) return false;

    // Пока резолвили URL, очередь могли изменить.
    if (index >= _tracks.length || _tracks[index].id != track.id) return false;

    final source = AudioSource.uri(Uri.parse(url));
    final current = _player.currentIndex;

    if (index == current) {
      if (!allowCurrent) return false;
      final wasPlaying = _player.playing;
      final sources = <AudioSource>[
        for (var i = 0; i < _tracks.length; i++)
          i == index ? source : _sourceFor(_tracks[i]),
      ];
      await _player.setAudioSources(
        sources,
        initialIndex: index,
        initialPosition: Duration.zero,
      );
      _updateCurrentMediaItem(index);
      if (wasPlaying) unawaited(_player.play());
      return true;
    }

    try {
      await _player.removeAudioSourceAt(index);
      await _player.insertAudioSource(index, source);
      return true;
    } catch (error) {
      debugPrint('AudioPlayerHandler: source upgrade failed: $error');
      return false;
    }
  }

  /// Готовит прямые ссылки для текущего и следующих трёх треков.
  void _prefetchUpcoming(int currentIndex) {
    if (_tracks.isEmpty) return;

    final indices = _upcomingIndices(currentIndex, 3);
    final ids = <String>[];
    for (final index in indices) {
      final track = _tracks[index];
      if (track.source != TrackSource.youtube) continue;
      if (_directStreamUrl(track) != null) continue;
      final id = track.externalId;
      if (id == null || id.isEmpty) continue;
      ids.add(id);
    }
    if (ids.isEmpty) return;

    _youtube.prefetchPlaybackUrls(ids, limit: ids.length);
    for (final index in indices) {
      unawaited(_upgradeSourceAt(index));
    }
  }

  /// Индексы треков, которые прозвучат после [currentIndex] с учётом
  /// перемешивания и повтора всей очереди.
  List<int> _upcomingIndices(int currentIndex, int count) {
    final result = <int>[];
    if (_tracks.isEmpty || count <= 0) return result;

    if (!_player.shuffleModeEnabled) {
      for (var offset = 1; offset <= count; offset++) {
        final index = currentIndex + offset;
        if (index < _tracks.length) {
          result.add(index);
        } else if (_player.loopMode == LoopMode.all) {
          result.add(index % _tracks.length);
        } else {
          break;
        }
      }
      return result;
    }

    final order = _player.effectiveIndices;
    final position = order.indexOf(currentIndex);
    if (position < 0) return result;

    for (var offset = 1; offset <= count; offset++) {
      var next = position + offset;
      if (next >= order.length) {
        if (_player.loopMode != LoopMode.all) break;
        next %= order.length;
      }
      result.add(order[next]);
    }
    return result;
  }

  void _updateQueueItemAt(int index, Track track) {
    final items = queue.value.toList();
    if (index < 0 || index >= items.length) return;
    items[index] = _mediaItemFor(track);
    // Без List.unmodifiable: QueueHandler меняет список на месте.
    queue.add(items);
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
