import 'dart:async';
import 'dart:io';

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
    _player.currentIndexStream.listen(
      (index) {
        _updateCurrentMediaItem(index);
        if (index != null) _prefetchUpcoming(index);
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('AudioPlayerHandler: currentIndex stream error: $error');
      },
    );
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
  ///
  /// Источники строятся до изменения очереди: если стартовый трек не удаётся
  /// подготовить, текущее воспроизведение не прерывается. Треки без
  /// пригодного источника просто не попадают в очередь, вместо того чтобы
  /// уронить её всю.
  Future<void> playTracks(
    List<Track> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) return;
    if (startIndex < 0 || startIndex >= tracks.length) startIndex = 0;

    final AudioSource startSource;
    var startIsReliable = false;
    try {
      final start = await _sourceForAsyncTrack(tracks[startIndex]);
      startSource = start.source;
      startIsReliable = start.reliable;
    } on TrackLoadException {
      rethrow;
    } catch (error) {
      debugPrint(
        'AudioPlayerHandler: start source failed for '
        '${tracks[startIndex].title}: $error',
      );
      throw const TrackLoadException(
        'Не удалось подготовить трек к воспроизведению.',
      );
    }

    final queueTracks = <Track>[];
    final sources = <AudioSource>[];
    var initialIndex = 0;

    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final AudioSource source;
      if (i == startIndex) {
        source = startSource;
      } else {
        try {
          source = _sourceFor(track);
        } catch (error) {
          debugPrint(
            'AudioPlayerHandler: skipping ${track.title} (${track.source.name}): '
            '$error',
          );
          continue;
        }
      }
      if (i == startIndex) initialIndex = queueTracks.length;
      queueTracks.add(track);
      sources.add(source);
    }

    if (sources.isEmpty) {
      throw const TrackLoadException('В очереди нет воспроизводимых треков.');
    }

    _tracks
      ..clear()
      ..addAll(queueTracks);

    // Держим очередь audio_service в том же порядке, что и _tracks:
    // addToQueue/removeFromQueue/clearQueue работают с queue.value.
    // Список должен быть изменяемым: QueueHandler добавляет элементы на месте.
    queue.add([for (final t in queueTracks) _mediaItemFor(t)]);

    if (shuffle && !_player.shuffleModeEnabled) {
      await _player.setShuffleModeEnabled(true);
    }
    if (!shuffle && _player.shuffleModeEnabled) {
      await _player.setShuffleModeEnabled(false);
    }

    await _player.setAudioSources(
      sources,
      initialIndex: initialIndex,
      initialPosition: Duration.zero,
      // Не ждём загрузку/метаданные начального трека: play() ниже сам
      // запустит буферизацию. Это убирает из старта лишний сетевой шаг.
      preload: false,
    );

    _updateCurrentMediaItem(initialIndex);
    _startPlayback();

    // Если стартовый YouTube-трек пришлось запустить через быстрый, но
    // неполный поток, подменяем его надёжным в первую очередь — до
    // прогрева следующих треков, иначе SDK-less-ссылка может закончиться
    // (~1 МБ) раньше, чем дойдёт очередь до апгрейда.
    final startTrack = _tracks[initialIndex];
    if (!startIsReliable && startTrack.source == TrackSource.youtube) {
      unawaited(_upgradeSourceAt(initialIndex, allowCurrent: true));
    }

    _prefetchUpcoming(initialIndex);
  }

  /// Добавляет трек в конец очереди (или запускает, если очередь пуста).
  Future<void> addToQueue(Track track) async {
    if (_tracks.isEmpty) {
      await playTracks([track]);
      return;
    }

    // Источник строим до изменения списков: ошибка не должна оставлять
    // очередь и just_audio в разных состояниях.
    final source = _sourceFor(track);
    final mediaItem = _mediaItemFor(track);

    _tracks.add(track);
    await addQueueItem(mediaItem);
    try {
      await _player.addAudioSource(source);
    } catch (error) {
      debugPrint('AudioPlayerHandler: addToQueue failed: $error');
      if (_tracks.isNotEmpty && _tracks.last.id == track.id) {
        _tracks.removeLast();
      }
      try {
        await removeQueueItem(mediaItem);
      } catch (_) {
        // Метаданные очереди не критичны для воспроизведения.
      }
      rethrow;
    }
    _prefetchUpcoming(_player.currentIndex ?? 0);
  }

  /// Ставит трек играть следующим (после текущего).
  Future<void> playNext(Track track) async {
    final insertAt = (_player.currentIndex ?? -1) + 1;
    if (insertAt <= 0 || _tracks.isEmpty) {
      await addToQueue(track);
      return;
    }

    final source = _sourceFor(track);
    final mediaItem = _mediaItemFor(track);

    _tracks.insert(insertAt, track);
    await insertQueueItem(insertAt, mediaItem);
    try {
      await _player.insertAudioSource(insertAt, source);
    } catch (error) {
      debugPrint('AudioPlayerHandler: playNext failed: $error');
      if (insertAt < _tracks.length && _tracks[insertAt].id == track.id) {
        _tracks.removeAt(insertAt);
      }
      try {
        await removeQueueItem(mediaItem);
      } catch (_) {
        // Метаданные очереди не критичны для воспроизведения.
      }
      rethrow;
    }
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

    // Собираем источники до изменения _tracks: если подготовка упадёт,
    // текущая очередь останется нетронутой.
    final nextTracks = [..._tracks];
    nextTracks[index] = resolved;
    final sources = <AudioSource>[
      for (var i = 0; i < nextTracks.length; i++)
        i == index ? resolvedSource : _sourceOrSilence(nextTracks[i]),
    ];

    _tracks[index] = resolved;
    _updateQueueItemAt(index, resolved);
    await _player.setAudioSources(
      sources,
      initialIndex: index,
      initialPosition: Duration.zero,
      preload: false,
    );
    _updateCurrentMediaItem(index);
    _startPlayback();
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
          i == index ? source : _sourceOrSilence(_tracks[i]),
      ];
      await _player.setAudioSources(
        sources,
        initialIndex: index,
        initialPosition: Duration.zero,
      );
      _updateCurrentMediaItem(index);
      if (wasPlaying) _startPlayback();
      _prefetchUpcoming(index);
      return;
    }

    await _player.removeAudioSourceAt(index);
    await _player.insertAudioSource(index, source);
  }

  /// Убирает трек из очереди. Текущий трек удалить нельзя.
  Future<void> removeFromQueue(int index) async {
    final current = _player.currentIndex ?? -1;
    if (index < 0 ||
        index >= _tracks.length ||
        index >= queue.value.length ||
        index == current) {
      return;
    }

    // Сначала удаляем источник из just_audio: если операция не удалась,
    // локальные списки остаются согласованными с плеером.
    final item = queue.value[index];
    try {
      await _player.removeAudioSourceAt(index);
    } catch (error) {
      debugPrint('AudioPlayerHandler: removeFromQueue failed: $error');
      return;
    }
    if (index < _tracks.length) _tracks.removeAt(index);
    try {
      await removeQueueItem(item);
    } catch (_) {
      // Метаданные очереди не критичны для воспроизведения.
    }
  }

  /// Очищает очередь, оставляя только текущий трек.
  Future<void> clearQueue() async {
    final current = _player.currentIndex;
    if (current == null) return;

    for (var i = _tracks.length - 1; i > current; i--) {
      await _removeQueueAt(i);
    }
    for (var i = current - 1; i >= 0; i--) {
      await _removeQueueAt(i);
    }
  }

  /// Удаляет элемент очереди по индексу, не выходя за границы списков.
  Future<void> _removeQueueAt(int index) async {
    if (index < 0 || index >= _tracks.length || index >= queue.value.length) {
      return;
    }
    final item = queue.value[index];
    try {
      await _player.removeAudioSourceAt(index);
    } catch (error) {
      debugPrint('AudioPlayerHandler: clearQueue failed at $index: $error');
      return;
    }
    if (index < _tracks.length) _tracks.removeAt(index);
    try {
      await removeQueueItem(item);
    } catch (_) {
      // Метаданные очереди не критичны для воспроизведения.
    }
  }

  // --- Элементарные операции ------------------------------------------------

  @override
  Future<void> play() async {
    _startPlayback();
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
      // Не задерживаем переход ожиданием манифеста: прямой источник
      // подменится в фоне, а Invidious-заглушка уже стоит в очереди.
      // Готовим надёжный источник до перехода, чтобы он не подменялся
      // повторно во время воспроизведения.
      final prepared = await _upgradeSourceAt(
        next,
        resolveTimeout: const Duration(milliseconds: 1500),
      );
      await _player.seekToNext();
      _startPlayback();
      if (!prepared) {
        unawaited(_upgradeSourceAt(next, allowCurrent: true));
      }
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
      var prepared = false;
      if (previous != null) {
        prepared = await _upgradeSourceAt(
          previous,
          resolveTimeout: const Duration(milliseconds: 1500),
        );
      }
      await _player.seekToPrevious();
      _startPlayback();
      if (previous != null) {
        if (!prepared) {
          unawaited(_upgradeSourceAt(previous, allowCurrent: true));
        }
        _prefetchUpcoming(previous);
      }
    } catch (_) {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    final prepared = await _upgradeSourceAt(
      index,
      allowCurrent: true,
      resolveTimeout: const Duration(milliseconds: 1800),
    );
    try {
      await _player.seek(Duration.zero, index: index);
    } catch (error) {
      debugPrint('AudioPlayerHandler: skipToQueueItem($index) failed: $error');
      return;
    }
    _updateCurrentMediaItem(index);
    _startPlayback();
    if (!prepared) {
      unawaited(_upgradeSourceAt(index, allowCurrent: true));
    }
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

  /// Безопасно строит источник для фоновых элементов очереди.
  ///
  /// Если трек почему-то стал недоступен (файл удалён, ссылка битая),
  /// очередь не падает целиком: проблемный элемент заменяется короткой
  /// тишиной, которую just_audio сразу перескочит.
  AudioSource _sourceOrSilence(Track track) {
    try {
      return _sourceFor(track);
    } catch (error) {
      debugPrint('AudioPlayerHandler: no source for ${track.title}: $error');
      return _silenceSource();
    }
  }

  /// Пустой источник-заглушка для непроигрываемых элементов очереди.
  AudioSource _silenceSource() {
    // SilenceAudioSource поддерживается только на Android. На других
    // платформах используем заведомо недоступный URI — just_audio
    // сообщит об ошибке и перейдёт к следующему треку.
    if (defaultTargetPlatform == TargetPlatform.android) {
      return SilenceAudioSource(duration: const Duration(seconds: 1));
    }
    return AudioSource.uri(Uri.parse('about:blank'));
  }

  /// Запускает воспроизведение, не оставляя необработанных ошибок Future.
  void _startPlayback() {
    unawaited(
      _player.play().catchError((Object error, StackTrace stack) {
        debugPrint('AudioPlayerHandler: play failed: $error');
      }),
    );
  }

  /// Создаёт сетевой источник и проверяет, что ссылка вообще пригодна.
  AudioSource _networkSource(String rawUrl, {Map<String, String>? headers}) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const TrackLoadException(
        'Источник трека содержит некорректную ссылку.',
      );
    }
    return AudioSource.uri(uri, headers: headers);
  }

  AudioSource _sourceFor(Track track) {
    if (track.source == TrackSource.youtube) {
      // Готовый прямой поток (например, из FullTrackResolver) играет без
      // Invidious-прокси и стартует сразу.
      final direct = _directStreamUrl(track);
      if (direct != null) return _networkSource(direct);

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
      return _networkSource(url, headers: YoutubeService.streamHeaders);
    }

    if (track.isAudius) {
      final audiusId = track.audiusId;
      if (audiusId == null || audiusId.isEmpty) {
        throw const TrackLoadException(
          'У трека нет идентификатора Audius. Выберите другой результат.',
        );
      }
      return _networkSource(_musicRepo.streamUrlFor(track));
    }

    final streamUrl = track.streamUrl;
    if (streamUrl != null && streamUrl.isNotEmpty) {
      return _networkSource(streamUrl);
    }

    final localPath = track.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      if (!File(localPath).existsSync()) {
        throw const TrackLoadException(
          'Файл трека не найден. Возможно, он был удалён.',
        );
      }
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
  /// Android SDK-less/VISIONOS (0,4–2,5 с) и только при ошибке падают
  /// обратно на медленный Invidious-прокси.
  Future<AudioSource> _sourceForAsync(Track track) async {
    return (await _sourceForAsyncTrack(track)).source;
  }

  /// Как [_sourceForAsync], но сообщает, удалось ли получить надёжный
  /// googlevideo-URL на весь файл. Быстрый SDK-less-поток отдаёт только
  /// первые ~1 МБ, поэтому после старта его нужно заменить.
  Future<({AudioSource source, bool reliable})> _sourceForAsyncTrack(
    Track track,
  ) async {
    if (track.source != TrackSource.youtube) {
      return (source: _sourceFor(track), reliable: true);
    }

    final direct = _directStreamUrl(track);
    if (direct != null) {
      return (source: _networkSource(direct), reliable: true);
    }

    final videoId = track.externalId;
    if (videoId != null && videoId.isNotEmpty) {
      final resolved = await _youtube.playbackStreamUrl(videoId);
      if (resolved != null && resolved.isNotEmpty) {
        return (
          source: _networkSource(resolved),
          reliable: _youtube.isReliablePlayback(videoId),
        );
      }
    }
    return (source: _sourceFor(track), reliable: false);
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
  ///
  /// Возвращает `true`, только если в очередь попал надёжный поток на
  /// весь файл. Быстрый SDK-less-URL тоже подходит для старта, но его
  /// придётся заменить позже, поэтому вызывающая сторона должна знать
  /// разницу.
  Future<bool> _upgradeSourceAt(
    int index, {
    bool allowCurrent = false,
    Duration resolveTimeout = const Duration(seconds: 8),
  }) {
    final result = _sourceReplaceQueue
        .then(
          (_) => _upgradeSourceAtNow(
            index,
            allowCurrent: allowCurrent,
            resolveTimeout: resolveTimeout,
          ),
        )
        .catchError((Object error, StackTrace stack) {
          debugPrint('AudioPlayerHandler: source upgrade failed: $error');
          return false;
        });
    _sourceReplaceQueue = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<bool> _upgradeSourceAtNow(
    int index, {
    required bool allowCurrent,
    Duration resolveTimeout = const Duration(seconds: 8),
  }) async {
    if (index < 0 || index >= _tracks.length) return false;

    final track = _tracks[index];
    if (track.source != TrackSource.youtube) return false;
    if (_directStreamUrl(track) != null) return false;

    final videoId = track.externalId;
    if (videoId == null || videoId.isEmpty) return false;

    final url = await _youtube.reliablePlaybackStreamUrl(
      videoId,
      timeout: resolveTimeout,
    );
    if (url == null || url.isEmpty) return false;
    final reliable = _youtube.isReliablePlayback(videoId);

    // Пока резолвили URL, очередь могли изменить.
    if (index >= _tracks.length || _tracks[index].id != track.id) return false;

    final source = _networkSource(url);
    var current = _player.currentIndex;

    // После setAudioSources(preload: false) индекс может появиться чуть
    // позже. Без него мы бы приняли стартовый трек за «не текущий» и
    // сделали remove/insert прямо во время загрузки.
    if (current == null) {
      try {
        current = await _player.currentIndexStream
            .firstWhere((value) => value != null)
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        return false;
      }
      if (index >= _tracks.length || _tracks[index].id != track.id)
        return false;
    }

    if (index == current) {
      if (!allowCurrent) return false;
      final wasPlaying = _player.playing;
      // Тот же трек, другая ссылка: сохраняем позицию, чтобы подмена
      // Invidious → googlevideo не начинала песню заново.
      final position = _player.position;
      final sources = <AudioSource>[
        for (var i = 0; i < _tracks.length; i++)
          i == index ? source : _sourceOrSilence(_tracks[i]),
      ];
      await _player.setAudioSources(
        sources,
        initialIndex: index,
        initialPosition: position,
      );
      _updateCurrentMediaItem(index);
      if (wasPlaying) _startPlayback();
      return reliable;
    }

    try {
      await _player.removeAudioSourceAt(index);
      await _player.insertAudioSource(index, source);
      return reliable;
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
      if (index < 0 || index >= _tracks.length) continue;
      final track = _tracks[index];
      if (track.source != TrackSource.youtube) continue;
      if (_directStreamUrl(track) != null) continue;
      final id = track.externalId;
      if (id == null || id.isEmpty) continue;
      ids.add(id);
    }
    if (ids.isEmpty) return;

    _youtube.prefetchPlaybackUrls(ids, limit: ids.length, reliable: true);
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
    if (order.isEmpty) return result;
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
