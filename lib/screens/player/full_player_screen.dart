import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/track.dart';
import '../../providers/player_provider.dart';
import '../../widgets/artwork.dart';
import '../../widgets/download_sheet.dart';
import '../../widgets/queue_sheet.dart';
import '../../widgets/track_tile.dart';

/// Полноэкранный плеер: обложка, прогресс, управление, громкость, очередь.
class FullPlayerScreen extends StatelessWidget {
  const FullPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Сейчас играет'),
        actions: [
          if (track != null) DownloadButton(track: track),
          if (track != null)
            LikeButton(track: track)
          else
            const SizedBox.shrink(),
          IconButton(
            onPressed: () => showQueueSheet(context),
            icon: const Icon(Icons.queue_music_outlined),
            tooltip: 'Очередь',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: buildBody(player, track),
    );
  }

  Widget buildBody(PlayerProvider player, Track? track) {
    if (track == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note, size: 64, color: AppTheme.textDim),
            SizedBox(height: 16),
            Text('Выберите трек, чтобы начать'),
          ],
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const Spacer(flex: 2),
            _Artwork(player: player, track: track),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, color: AppTheme.textDim),
                ),
              ],
            ),
            const Spacer(),
            _SeekBar(player: player),
            const SizedBox(height: 12),
            const _Controls(),
            const SizedBox(height: 24),
            _VolumeRow(player: player),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Большая обложка; для аудио без арт-URL — заглушка.
class _Artwork extends StatelessWidget {
  final PlayerProvider player;

  final Track track;

  const _Artwork({required this.player, required this.track});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.width - 64;

    Widget art;
    if (track.artworkUrl != null && track.artworkUrl!.isNotEmpty) {
      art = ArtworkView(
        url: track.artworkUrl,
        size: size,
        borderRadius: BorderRadius.circular(24),
      );
    } else {
      art = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.library_music,
              size: 96,
              color: Colors.white10,
            ),
            Text(
              track.title.isEmpty ? '?' : track.title[0].toUpperCase(),
              style: TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.w800,
                color: AppTheme.accentGreen.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        art,
        if (player.isBuffering)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: const CircularProgressIndicator(),
          ),
      ],
    );
  }
}

/// Прогресс-полоса с временной отметкой и перемоткой по тапу/drag.
class _SeekBar extends StatelessWidget {
  final PlayerProvider player;

  const _SeekBar({required this.player});

  @override
  Widget build(BuildContext context) {
    final audioPlayer = player.handler.player;

    return StreamBuilder<Duration?>(
      stream: audioPlayer.durationStream,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: audioPlayer.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            return _ValueSeekBar(
              player: player,
              duration: duration,
              position: position,
            );
          },
        );
      },
    );
  }
}

class _ValueSeekBar extends StatefulWidget {
  final PlayerProvider player;

  final Duration duration;

  final Duration position;

  const _ValueSeekBar({
    required this.player,
    required this.duration,
    required this.position,
  });

  @override
  State<_ValueSeekBar> createState() => _ValueSeekBarState();
}

class _ValueSeekBarState extends State<_ValueSeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final max = widget.duration.inMilliseconds.toDouble();
    final current = _dragValue ?? widget.position.inMilliseconds.toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: Theme.of(context).sliderTheme,
          child: Slider(
            value: max > 0 ? current.clamp(0.0, max).toDouble() : 0.0,
            max: max > 0 ? max : 1.0,
            onChanged: max > 0 ? (value) => setState(() => _dragValue = value) : null,
            onChangeEnd: (value) {
              widget.player.seek(Duration(milliseconds: value.round()));
              setState(() => _dragValue = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(_dragValue == null
                    ? widget.position
                    : Duration(milliseconds: _dragValue!.round())),
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textDim),
              ),
              Text(
                formatDuration(widget.duration),
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textDim),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Кнопки управления: shuffle / prev / play-pause / next / repeat.
class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          onPressed: player.hasQueue ? player.toggleShuffle : null,
          icon: const Icon(Icons.shuffle_rounded),
          iconSize: 26,
          color: player.isShuffleEnabled
              ? AppTheme.accentGreen
              : AppTheme.textDim,
          tooltip: 'Перемешать',
        ),
        IconButton(
          onPressed: player.hasQueue ? player.previous : null,
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: 40,
          color: const Color(0xFFE9ECEA),
          tooltip: 'Назад',
        ),
        _PlayPauseButton(player: player),
        IconButton(
          onPressed: player.hasQueue ? player.next : null,
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: 40,
          color: const Color(0xFFE9ECEA),
          tooltip: 'Вперёд',
        ),
        IconButton(
          onPressed: player.hasQueue ? player.cycleRepeat : null,
          icon: Icon(
            player.isRepeatOne ? Icons.repeat_one_rounded : Icons.repeat_rounded,
          ),
          iconSize: 26,
          color: player.isRepeatAll || player.isRepeatOne
              ? AppTheme.accentGreen
              : AppTheme.textDim,
          tooltip: player.isRepeatOne
              ? 'Повтор трека'
              : (player.isRepeatAll ? 'Повтор очереди' : 'Повтор выключен'),
        ),
      ],
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final PlayerProvider player;

  const _PlayPauseButton({required this.player});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: const BoxDecoration(
        color: AppTheme.accentGreen,
        shape: BoxShape.circle,
      ),
      child: player.isBuffering
          ? const Padding(
              padding: EdgeInsets.all(18),
              child: CircularProgressIndicator(
                color: Colors.black,
                strokeWidth: 3,
              ),
            )
          : IconButton(
              onPressed: player.togglePlay,
              icon: Icon(
                player.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
              iconSize: 40,
              color: Colors.black87,
              tooltip: player.isPlaying ? 'Пауза' : 'Играть',
            ),
    );
  }
}

/// Громкость плеера (0–100%).
class _VolumeRow extends StatelessWidget {
  final PlayerProvider player;

  const _VolumeRow({required this.player});

  @override
  Widget build(BuildContext context) {
    final volume = player.volume;

    return Row(
      children: [
        const Icon(Icons.volume_down, size: 20, color: AppTheme.textDim),
        Expanded(
          child: Slider(
            value: volume,
            onChanged: (value) => player.setVolume(value),
          ),
        ),
        const Icon(Icons.volume_up, size: 20, color: AppTheme.textDim),
        SizedBox(
          width: 44,
          child: Text(
            '${(volume * 100).round()}%',
            style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
