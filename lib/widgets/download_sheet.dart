import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/design_tokens.dart';
import '../data/models/track.dart';
import '../providers/download_provider.dart';
import '../services/mp3_download_service.dart';
import 'artwork.dart';
import 'common.dart';

/// Запускает скачивание и сразу открывает лист с прогрессом.
///
/// Скачивание продолжается, даже если лист свернуть: прогресс остаётся
/// в нижней панели приложения.
Future<void> startDownloadWithSheet(BuildContext context, Track track) async {
  final downloads = context.read<DownloadProvider>();

  if (track.isLocal) {
    showAppSnackBar(
      context,
      'Этот трек уже есть на устройстве.',
      isError: true,
    );
    return;
  }
  if (downloads.isDownloading) {
    showAppSnackBar(
      context,
      'Уже скачивается «${downloads.task!.track.title}». '
      'Дождитесь окончания.',
      isError: true,
    );
    return;
  }

  unawaited(downloads.download(track));

  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => DownloadProgressSheet(track: track),
  );
}

/// Нижний лист со стадиями: поиск → загрузка → конвертация → сохранение.
class DownloadProgressSheet extends StatelessWidget {
  final Track track;

  const DownloadProgressSheet({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadProvider>(
      builder: (context, downloads, _) {
        final task = downloads.taskFor(track);
        final stage = task?.stage ?? DownloadStage.resolving;
        final active = task?.isActive ?? true;
        final done = task?.isDone ?? false;
        final failed = stage == DownloadStage.failed;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.stroke,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    ArtworkView(size: 56, url: track.artworkUrl),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _Status(
                  stage: stage,
                  progress: task?.progress,
                  error: task?.error,
                  result: task?.result,
                ),
                const SizedBox(height: 22),
                if (active) ...[
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Свернуть'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Скачивание продолжится — прогресс виден внизу экрана.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textDim, fontSize: 11),
                  ),
                ] else if (failed) ...[
                  FilledButton.icon(
                    onPressed: () => downloads.download(track),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Повторить'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      downloads.clearFinished();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Закрыть'),
                  ),
                ] else if (done)
                  FilledButton(
                    onPressed: () {
                      downloads.clearFinished();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Готово'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Status extends StatelessWidget {
  final DownloadStage stage;
  final double? progress;
  final String? error;
  final DownloadResult? result;

  const _Status({
    required this.stage,
    required this.progress,
    required this.error,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    if (stage == DownloadStage.done) {
      final publicPath = result?.publicPath;
      return Column(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.accentBright,
            size: 42,
          ),
          const SizedBox(height: 8),
          const Text(
            'Трек скачан',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            publicPath != null
                ? 'Файл сохранён: $publicPath'
                : 'Файл сохранён в приложении и добавлен в «Мои треки».',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            'MP3, 192 кбит/с',
            style: TextStyle(color: AppColors.textDim, fontSize: 11),
          ),
        ],
      );
    }

    if (stage == DownloadStage.failed) {
      return Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 42,
          ),
          const SizedBox(height: 8),
          Text(
            error ?? 'Не удалось скачать трек.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 6),
          const Text(
            'Проверьте соединение или попробуйте другой результат поиска.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textDim, fontSize: 11),
          ),
        ],
      );
    }

    final determinate = stage == DownloadStage.downloading && progress != null;
    final percent = progress == null ? null : (progress! * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            // Без анимации: пока прогресс неизвестен, показываем пустую
            // шкалу, а не бегущую зелёную полоску.
            value: determinate ? progress : 0,
            minHeight: 5,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(stage.label, style: const TextStyle(fontSize: 13)),
            ),
            if (percent != null)
              Text(
                '$percent%',
                style: const TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
          ],
        ),
      ],
    );
  }
}

/// Тонкая панель прогресса над мини-плеером — видна из любого экрана.
class DownloadProgressBanner extends StatelessWidget {
  const DownloadProgressBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final task = context.select<DownloadProvider, DownloadTask?>(
      (downloads) => downloads.task,
    );
    if (task == null || !task.isActive) return const SizedBox.shrink();

    final percent = task.progress == null
        ? null
        : (task.progress! * 100).round();
    final determinate =
        task.stage == DownloadStage.downloading && task.progress != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.surfaceRaised,
        borderRadius: AppRadii.mdAll,
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: determinate ? task.progress : 0,
              minHeight: 2,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.downloading,
                    size: 16,
                    color: AppColors.accentBright,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${task.stage.label} ${task.track.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                  if (percent != null)
                    Text(
                      '$percent%',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Компактная кнопка скачивания для списков треков.
class DownloadButton extends StatelessWidget {
  final Track track;

  const DownloadButton({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    if (track.isLocal) return const SizedBox.shrink();

    final task = context.select<DownloadProvider, DownloadTask?>(
      (downloads) => downloads.taskFor(track),
    );
    final downloading = task?.isActive ?? false;
    final another = context.select<DownloadProvider, bool>(
      (downloads) =>
          downloads.isDownloading && !downloads.isTrackDownloading(track),
    );

    return IconButton(
      tooltip: downloading ? 'Скачивается…' : 'Скачать трек',
      onPressed: downloading || another
          ? null
          : () => startDownloadWithSheet(context, track),
      color: AppColors.accentBright,
      icon: downloading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: task!.stage == DownloadStage.downloading
                    ? task.progress
                    : null,
              ),
            )
          : const Icon(Icons.cloud_download_outlined),
    );
  }
}
