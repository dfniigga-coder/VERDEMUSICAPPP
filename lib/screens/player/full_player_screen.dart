import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/track.dart';
import '../../providers/player_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/artwork.dart';
import '../../widgets/download_sheet.dart';
import '../../widgets/lyrics_sheet.dart';
import '../../widgets/play_button.dart';
import '../../widgets/queue_sheet.dart';
import '../../widgets/track_tile.dart';

/// Полноэкранный плеер: размытая обложка на фоне, крупный арт,
/// кастомный seek-bar, управление и строка текста песни.
class FullPlayerScreen extends StatelessWidget {
  static const String heroTag = 'player-artwork';

  const FullPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;

    if (track == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceRaised,
                ),
                child: const Icon(
                  Icons.music_note_rounded,
                  size: 40,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Выберите трек, чтобы начать',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: ArtworkBackdrop(
              url: track.artworkUrl,
              blur: 46,
              overlayColor: Colors.black.withValues(alpha: 0.42),
              gradient: AppColors.playerScrim,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _TopBar(track: track),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Expanded(child: _Artwork(track: track)),
                        const SizedBox(height: 14),
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textDim,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _SeekBar(player: player),
                        const SizedBox(height: 4),
                        _Controls(player: player),
                        const SizedBox(height: 10),
                        _VolumeRow(player: player),
                        const SizedBox(height: 8),
                        _LyricsCard(track: track),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final Track track;

  const _TopBar({required this.track});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 2),
      child: Row(
        children: [
          _CircleIconButton(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: 'Свернуть',
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'СЕЙЧАС ИГРАЕТ',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                  color: AppColors.textDim,
                ),
              ),
            ),
          ),
          LikeButton(track: track),
          DownloadButton(track: track),
          _CircleIconButton(
            icon: Icons.queue_music_rounded,
            tooltip: 'Очередь',
            onTap: () => showQueueSheet(context),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;

  final String tooltip;

  final VoidCallback onTap;

  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.stroke),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        color: AppColors.text,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Большая обложка; для аудио без арт-URL — заглушка.
class _Artwork extends StatelessWidget {
  final Track track;

  const _Artwork({required this.track});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.min(
          constraints.maxWidth - 8,
          constraints.maxHeight - 12,
        );
        final size = available.clamp(1.0, 1000.0).toDouble();

        Widget art;
        if (track.artworkUrl != null && track.artworkUrl!.isNotEmpty) {
          art = ArtworkView(
            url: track.artworkUrl,
            size: size,
            borderRadius: AppRadii.xlAll,
          );
        } else {
          art = Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: AppRadii.xlAll,
              border: Border.all(color: AppColors.stroke),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.library_music_rounded,
                  size: size * 0.42,
                  color: Colors.white10,
                ),
                Text(
                  track.title.isEmpty ? '?' : track.title[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: size * 0.28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accentBright.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          );
        }

        return Center(
          child: Hero(
            tag: FullPlayerScreen.heroTag,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: AppRadii.xlAll,
                boxShadow: AppShadows.artwork,
              ),
              child: art,
            ),
          ),
        );
      },
    );
  }
}

/// Прогресс-полоса с буфером, временем и перемоткой по тапу/drag.
class _SeekBar extends StatelessWidget {
  final PlayerProvider player;

  const _SeekBar({required this.player});

  @override
  Widget build(BuildContext context) {
    final audioPlayer = player.handler.player;

    return StreamBuilder<Duration?>(
      stream: audioPlayer.durationStream,
      builder: (context, durationSnapshot) {
        final duration =
            durationSnapshot.data ?? audioPlayer.duration ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: audioPlayer.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            return StreamBuilder<Duration>(
              stream: audioPlayer.bufferedPositionStream,
              builder: (context, bufferedSnapshot) {
                return _ValueSeekBar(
                  player: player,
                  duration: duration,
                  position: position,
                  buffered: bufferedSnapshot.data ?? Duration.zero,
                );
              },
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

  final Duration buffered;

  const _ValueSeekBar({
    required this.player,
    required this.duration,
    required this.position,
    required this.buffered,
  });

  @override
  State<_ValueSeekBar> createState() => _ValueSeekBarState();
}

class _ValueSeekBarState extends State<_ValueSeekBar> {
  double? _dragValue;

  double get _max => widget.duration.inMilliseconds.toDouble();

  double get _current =>
      _dragValue ?? widget.position.inMilliseconds.toDouble();

  void _setFromDx(double dx, double width) {
    if (_max <= 0 || width <= 0) return;
    final value = (dx / width).clamp(0.0, 1.0).toDouble() * _max;
    setState(() => _dragValue = value);
  }

  void _commit() {
    final value = _dragValue;
    if (value == null) return;
    widget.player.seek(Duration(milliseconds: value.round()));
    setState(() => _dragValue = null);
  }

  @override
  Widget build(BuildContext context) {
    final max = _max;
    final value = max > 0 ? _current.clamp(0.0, max).toDouble() : 0.0;
    final progress = max > 0 ? value / max : 0.0;
    final buffered = max > 0
        ? (widget.buffered.inMilliseconds / max).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: max > 0
                  ? (details) => _setFromDx(details.localPosition.dx, width)
                  : null,
              onTapUp: max > 0 ? (_) => _commit() : null,
              onHorizontalDragStart: max > 0
                  ? (details) => _setFromDx(details.localPosition.dx, width)
                  : null,
              onHorizontalDragUpdate: max > 0
                  ? (details) => _setFromDx(details.localPosition.dx, width)
                  : null,
              onHorizontalDragEnd: max > 0 ? (_) => _commit() : null,
              child: SizedBox(
                height: 34,
                width: width,
                child: CustomPaint(
                  painter: _SeekPainter(progress: progress, buffered: buffered),
                ),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(
                  _dragValue == null
                      ? widget.position
                      : Duration(milliseconds: _dragValue!.round()),
                ),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textDim,
                ),
              ),
              Text(
                formatDuration(widget.duration),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textDim,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SeekPainter extends CustomPainter {
  final double progress;

  final double buffered;

  const _SeekPainter({required this.progress, required this.buffered});

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    const trackHeight = 4.0;
    final radius = Radius.circular(trackHeight / 2);

    final base = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, centerY - trackHeight / 2, size.width, trackHeight),
      radius,
    );
    canvas.drawRRect(base, Paint()..color = AppColors.surfaceHigh);

    final bufferedWidth = buffered.clamp(0.0, 1.0).toDouble() * size.width;
    if (bufferedWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            0,
            centerY - trackHeight / 2,
            bufferedWidth,
            trackHeight,
          ),
          radius,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.14),
      );
    }

    final progressWidth = progress.clamp(0.0, 1.0).toDouble() * size.width;
    if (progressWidth > 0) {
      final shaderRect = Rect.fromLTWH(
        0,
        centerY - trackHeight / 2,
        math.max(progressWidth, 1),
        trackHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            0,
            centerY - trackHeight / 2,
            progressWidth,
            trackHeight,
          ),
          radius,
        ),
        Paint()..shader = AppColors.accentGradient.createShader(shaderRect),
      );
    }

    final thumbX = progress.clamp(0.0, 1.0).toDouble() * size.width;
    canvas.drawCircle(
      Offset(thumbX, centerY),
      7,
      Paint()..color = AppColors.accentBright,
    );
    canvas.drawCircle(
      Offset(thumbX, centerY),
      2.8,
      Paint()..color = AppColors.background,
    );
  }

  @override
  bool shouldRepaint(covariant _SeekPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.buffered != buffered;
  }
}

/// Кнопки управления: shuffle / prev / play-pause / next / repeat.
class _Controls extends StatelessWidget {
  final PlayerProvider player;

  const _Controls({required this.player});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          onPressed: player.hasQueue ? player.toggleShuffle : null,
          icon: const Icon(Icons.shuffle_rounded),
          iconSize: 24,
          color: player.isShuffleEnabled
              ? AppColors.accentBright
              : AppColors.textDim,
          tooltip: 'Перемешать',
        ),
        IconButton(
          onPressed: player.hasQueue ? player.previous : null,
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: 38,
          color: AppColors.text,
          tooltip: 'Назад',
        ),
        PlayButton(
          size: 70,
          onPressed: () {
            HapticFeedback.mediumImpact();
            player.togglePlay();
          },
          isPlaying: player.isPlaying,
          isBuffering: player.isBuffering,
        ),
        IconButton(
          onPressed: player.hasQueue ? player.next : null,
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: 38,
          color: AppColors.text,
          tooltip: 'Вперёд',
        ),
        IconButton(
          onPressed: player.hasQueue ? player.cycleRepeat : null,
          icon: Icon(
            player.isRepeatOne
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
          ),
          iconSize: 24,
          color: player.isRepeatAll || player.isRepeatOne
              ? AppColors.accentBright
              : AppColors.textDim,
          tooltip: player.isRepeatOne
              ? 'Повтор трека'
              : (player.isRepeatAll ? 'Повтор очереди' : 'Повтор выключен'),
        ),
      ],
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
        const Icon(
          Icons.volume_down_rounded,
          size: 19,
          color: AppColors.textDim,
        ),
        Expanded(
          child: Slider(
            value: volume,
            onChanged: (value) => player.setVolume(value),
          ),
        ),
        const Icon(Icons.volume_up_rounded, size: 19, color: AppColors.textDim),
        SizedBox(
          width: 40,
          child: Text(
            '${(volume * 100).round()}%',
            style: const TextStyle(fontSize: 11, color: AppColors.textDim),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// Строка-переход к тексту песни.
class _LyricsCard extends StatelessWidget {
  final Track track;

  const _LyricsCard({required this.track});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => showLyricsSheet(context, track),
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: AppRadii.mdAll,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          const Icon(
            Icons.lyrics_rounded,
            size: 19,
            color: AppColors.accentBright,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Текст песни',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Синхронно с LRCLIB',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontSize: 10.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}
