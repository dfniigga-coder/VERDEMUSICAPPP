import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/design_tokens.dart';
import '../core/utils/formatters.dart';
import '../data/models/track.dart';
import '../providers/download_provider.dart';
import '../services/mp3_download_service.dart';
import '../services/youtube_link.dart';
import 'artwork.dart';
import 'download_sheet.dart';

/// Нижний лист «ссылка → MP3».
///
/// Ссылку можно вставить вручную, взять из буфера обмена или передать
/// приложению через Android-меню «Поделиться». После проверки ссылки
/// лист показывает трек и запускает обычное скачивание
/// YouTube → MP3 → `Music/Verde`.
Future<void> showLinkDownloadSheet(
  BuildContext context, {
  String? initialUrl,
  bool autoStart = false,
}) async {
  final track = await showModalBottomSheet<Track>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    builder: (_) =>
        LinkDownloadSheet(initialUrl: initialUrl, autoStart: autoStart),
  );

  if (track == null || !context.mounted) return;
  await startDownloadWithSheet(context, track);
}

class LinkDownloadSheet extends StatefulWidget {
  /// Готовая ссылка (например, из «Поделиться» или поисковой строки).
  final String? initialUrl;

  /// Сразу запустить скачивание после проверки ссылки — для ссылок,
  /// которыми поделились с приложением.
  final bool autoStart;

  const LinkDownloadSheet({super.key, this.initialUrl, this.autoStart = false});

  @override
  State<LinkDownloadSheet> createState() => _LinkDownloadSheetState();
}

class _LinkDownloadSheetState extends State<LinkDownloadSheet> {
  late final TextEditingController _controller;

  Track? _track;
  String? _error;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl ?? '');
    _controller.addListener(_onTextChanged);

    if ((widget.initialUrl ?? '').trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_resolve());
      });
    } else {
      unawaited(_prefillFromClipboard());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {
      _track = null;
      _error = null;
    });
  }

  Future<void> _prefillFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (!mounted || text == null || text.isEmpty) return;
      if (_controller.text.trim().isNotEmpty) return;
      if (YoutubeLink.parse(text) == null) return;

      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
    } catch (_) {
      // Буфер обмена недоступен — не мешаем ввести ссылку вручную.
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (!mounted) return;
      if (text == null || text.isEmpty) {
        setState(() => _error = 'Буфер обмена пуст.');
        return;
      }

      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
      if (YoutubeLink.parse(text) != null) {
        unawaited(_resolve());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось прочитать буфер обмена.');
    }
  }

  Future<void> _resolve() async {
    if (_resolving) return;

    final input = _controller.text.trim();
    if (input.isEmpty) return;

    FocusScope.of(context).unfocus();

    final link = YoutubeLink.parse(input);
    if (link == null) {
      setState(() {
        _track = null;
        _error = 'Это не похоже на ссылку YouTube Music или YouTube.';
      });
      return;
    }
    if (!link.hasVideo) {
      setState(() {
        _track = null;
        _error =
            'Ссылка ведёт на плейлист. Откройте трек и скопируйте '
            'ссылку на него.';
      });
      return;
    }

    setState(() {
      _resolving = true;
      _track = null;
      _error = null;
    });

    try {
      final track = await context.read<DownloadProvider>().resolveLink(input);
      if (!mounted) return;

      setState(() {
        _track = track;
        _resolving = false;
      });

      if (widget.autoStart) {
        // Даём листу показать трек и сразу возвращаем его наружу —
        // дальше откроется экран прогресса скачивания.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(track);
        });
      }
    } on DownloadException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _resolving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось получить информацию о треке.';
        _resolving = false;
      });
    }
  }

  bool get _canResolve => _controller.text.trim().isNotEmpty && !_resolving;

  @override
  Widget build(BuildContext context) {
    final track = _track;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
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
            const Row(
              children: [
                Icon(
                  Icons.music_video_outlined,
                  color: AppColors.accentBright,
                  size: 26,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Скачать с YouTube Music',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Скопируйте ссылку на трек в YouTube Music и вставьте её сюда — '
              'приложение скачает аудио и конвертирует его в MP3.',
              style: TextStyle(
                color: AppColors.textDim,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: widget.initialUrl == null,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.search,
              minLines: 1,
              maxLines: 2,
              enabled: !_resolving,
              onSubmitted: (_) => _resolve(),
              decoration: InputDecoration(
                hintText: 'https://music.youtube.com/watch?v=…',
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: IconButton(
                  onPressed: _resolving ? null : _pasteFromClipboard,
                  tooltip: 'Вставить из буфера',
                  icon: const Icon(Icons.content_paste_rounded, size: 20),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _canResolve ? _resolve : null,
              icon: _resolving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(
                _resolving ? 'Проверяем ссылку…' : 'Проверить ссылку',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 17,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (track != null) ...[
              const SizedBox(height: 18),
              _TrackPreview(track: track),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(track),
                icon: const Icon(Icons.download_for_offline_outlined),
                label: const Text('Скачать MP3'),
              ),
              const SizedBox(height: 8),
              const Text(
                'MP3, 192 кбит/с · файл сохранится в Music/Verde',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDim, fontSize: 11),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Скачивайте только тот контент, на который у вас есть права.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackPreview extends StatelessWidget {
  final Track track;

  const _TrackPreview({required this.track});

  @override
  Widget build(BuildContext context) {
    final duration = track.durationSec;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ArtworkView(size: 60, url: track.artworkUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                  ),
                ),
                if (duration != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 13,
                        color: AppColors.textDim,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        formatDuration(Duration(seconds: duration)),
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
