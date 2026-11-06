import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';
import '../data/models/resolved_track.dart';
import '../data/models/track.dart';
import '../providers/player_provider.dart';
import '../services/full_track_resolver.dart';
import 'common.dart';
import 'youtube_full_track_player.dart';

/// Кнопка «Слушать полностью» для превью-треков Deezer/iTunes.
///
/// Сначала пробует SoundCloud (играет через существующий just_audio),
/// затем YouTube (встроенный iFrame-плеер). Если не нашлось ничего,
/// предлагает открыть поиск YouTube в браузере/приложении.
class FullTrackButton extends StatefulWidget {
  final Track track;

  const FullTrackButton({super.key, required this.track});

  @override
  State<FullTrackButton> createState() => _FullTrackButtonState();
}

class _FullTrackButtonState extends State<FullTrackButton> {
  bool _loading = false;

  Future<void> _handle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await playFullTrack(context, widget.track);
    } catch (error) {
      debugPrint('FullTrackButton: $error');
      if (mounted) {
        showAppSnackBar(
          context,
          'Не удалось получить полную версию.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.track.isPreview) return const SizedBox.shrink();

    return IconButton(
      onPressed: _loading ? null : _handle,
      tooltip: 'Слушать полностью (SoundCloud / YouTube)',
      color: AppTheme.accentGreen,
      icon: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.play_circle_outline),
    );
  }
}

/// Находит и запускает полную версию трека.
Future<void> playFullTrack(BuildContext context, Track track) async {
  if (!track.isPreview) return;

  final resolver = context.read<FullTrackResolver>();
  final player = context.read<PlayerProvider>();

  showAppSnackBar(context, 'Ищем полную версию…');

  ResolvedTrack? resolved;
  try {
    resolved = await resolver.resolve(track.title, track.artist);
  } catch (error) {
    debugPrint('playFullTrack: resolve failed: $error');
  }

  if (!context.mounted) return;

  if (resolved == null) {
    await _offerYoutubeSearch(context, track);
    return;
  }

  if (resolved.canPlayInJustAudio) {
    final fullTrack = resolved.toTrack(fallback: track);
    final started = await player.playResolvedTrack(track, fullTrack);
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      started
          ? 'Включено: ${resolved.source.label}'
          : 'Не удалось включить полную версию.',
      isError: !started,
    );
    return;
  }

  if (resolved.canPlayInYoutube) {
    await showYouTubeFullTrack(context, track: resolved);
    return;
  }

  if (context.mounted) {
    showAppSnackBar(context, 'Полная версия не найдена.', isError: true);
  }
}

Future<void> _offerYoutubeSearch(BuildContext context, Track track) async {
  final query = Uri.encodeQueryComponent('${track.title} ${track.artist}');
  final uri = Uri.parse('https://www.youtube.com/results?search_query=$query');

  final open = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Полная версия не найдена'),
        content: const Text(
          'Можно открыть поиск YouTube — там часто есть официальный '
          'клип или аудио этого трека.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Открыть YouTube'),
          ),
        ],
      );
    },
  );

  if (open != true || !context.mounted) return;

  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      showAppSnackBar(context, 'Не удалось открыть YouTube.', isError: true);
    }
  } catch (error) {
    debugPrint('playFullTrack: launchUrl failed: $error');
    if (context.mounted) {
      showAppSnackBar(context, 'Не удалось открыть YouTube.', isError: true);
    }
  }
}
