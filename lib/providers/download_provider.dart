import 'package:flutter/foundation.dart';

import '../data/models/track.dart';
import '../services/mp3_download_service.dart';

/// Текущая (или последняя) задача скачивания.
///
/// Одновременно выполняется только одна задача: YouTube не любит
/// параллельные загрузки, а пользователю проще видеть один прогресс.
class DownloadTask {
  final Track track;
  final DownloadStage stage;
  final double? progress;
  final String? error;
  final DownloadResult? result;

  const DownloadTask({
    required this.track,
    required this.stage,
    this.progress,
    this.error,
    this.result,
  });

  bool get isActive =>
      stage != DownloadStage.done && stage != DownloadStage.failed;

  bool get isDone => stage == DownloadStage.done;
}

/// Сообщение для глобального снекбара.
class DownloadNotice {
  final String message;
  final bool isError;

  const DownloadNotice(this.message, {this.isError = false});
}

/// Управляет скачиванием треков: YouTube → MP3 → «Мои треки» + Music/Verde.
class DownloadProvider extends ChangeNotifier {
  DownloadProvider(this._service);

  final Mp3DownloadService _service;

  DownloadTask? _task;

  DownloadTask? get task => _task;

  bool get isDownloading => _task?.isActive ?? false;

  /// Уже сохранённый MP3 этого трека.
  Track? findDownloaded(Track track) => _service.findDownloaded(track);

  /// Отдельный notifier, чтобы снекбар не перестраивал всё дерево.
  final ValueNotifier<DownloadNotice?> notice = ValueNotifier<DownloadNotice?>(
    null,
  );

  /// Задача именно для этого трека (включая завершённую).
  DownloadTask? taskFor(Track track) {
    final task = _task;
    if (task == null || task.track.id != track.id) return null;
    return task;
  }

  bool isTrackDownloading(Track track) => taskFor(track)?.isActive ?? false;

  /// Метаданные трека по ссылке YouTube Music / YouTube.
  ///
  /// Ошибки разбора и сети приходят как [DownloadException] — лист
  /// скачивания показывает их прямо в поле ввода.
  Future<Track> resolveLink(String input) => _service.resolveLink(input);

  /// Скачивает [track]. Возвращает true при успехе.
  Future<bool> download(Track track) async {
    if (track.isLocal) {
      notice.value = const DownloadNotice(
        'Этот трек уже есть на устройстве.',
        isError: true,
      );
      return false;
    }

    if (isDownloading) {
      notice.value = DownloadNotice(
        'Уже скачивается «${_task!.track.title}». Дождитесь окончания.',
        isError: true,
      );
      return false;
    }

    final existing = findDownloaded(track);
    final existingPath = existing?.localPath;
    if (existing != null && existingPath != null && existingPath.isNotEmpty) {
      _task = DownloadTask(
        track: track,
        stage: DownloadStage.done,
        progress: 1,
        result: DownloadResult(
          localPath: existingPath,
          publicPath: null,
          title: existing.title,
          artist: existing.artist,
          durationSec: existing.durationSec,
          artworkUrl: existing.artworkUrl,
        ),
      );
      notifyListeners();
      notice.value = DownloadNotice(
        '«${existing.title}» уже есть в «Моих треках».',
      );
      return true;
    }

    return _performDownload(track);
  }

  Future<bool> _performDownload(Track track) async {
    _task = DownloadTask(track: track, stage: DownloadStage.resolving);
    notifyListeners();

    try {
      final result = await _service.download(
        track,
        onProgress: (stage, progress) {
          final current = _task;
          if (current == null || current.track.id != track.id) return;
          _task = DownloadTask(
            track: track,
            stage: stage,
            progress: progress,
            result: current.result,
          );
          notifyListeners();
        },
      );

      _task = DownloadTask(
        track: track,
        stage: DownloadStage.done,
        progress: 1,
        result: result,
      );
      notifyListeners();

      notice.value = DownloadNotice(
        result.publicPath != null
            ? '«${result.title}» сохранён в ${result.publicPath}'
            : '«${result.title}» добавлен в «Мои треки»',
      );
      return true;
    } on DownloadException catch (error) {
      _fail(track, error.message);
      return false;
    } catch (error) {
      debugPrint('DownloadProvider: unexpected error: $error');
      _fail(track, 'Не удалось скачать трек. Попробуйте ещё раз.');
      return false;
    }
  }

  /// Убирает завершённую/проваленную задачу из UI.
  void clearFinished() {
    final task = _task;
    if (task == null || task.isActive) return;
    _task = null;
    notifyListeners();
  }

  void _fail(Track track, String message) {
    _task = DownloadTask(
      track: track,
      stage: DownloadStage.failed,
      error: message,
    );
    notifyListeners();
    notice.value = DownloadNotice(message, isError: true);
  }

  @override
  void dispose() {
    notice.dispose();
    super.dispose();
  }
}
