import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/design_tokens.dart';
import '../providers/player_provider.dart';
import '../screens/player/full_player_screen.dart';
import 'artwork.dart';
import 'pressable_scale.dart';

/// Мини-плеер над нижней навигацией: карточка с размытой обложкой,
/// тапом открывается полноэкранный плеер, свайпом вверх — тоже.
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final track = player.currentTrack;
        if (track == null) return const SizedBox.shrink();

        return PressableScale(
          child: GestureDetector(
            onTap: () => _openFullPlayer(context),
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -250) _openFullPlayer(context);
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: AppRadii.lgAll,
                boxShadow: AppShadows.card,
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: AppRadii.lgAll,
                clipBehavior: Clip.antiAlias,
                child: ArtworkBackdrop(
                  url: track.artworkUrl,
                  blur: 20,
                  overlayColor: AppColors.surfaceRaised.withValues(alpha: 0.58),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.surfaceRaised.withValues(alpha: 0.72),
                      AppColors.background.withValues(alpha: 0.9),
                    ],
                  ),
                  borderRadius: AppRadii.lgAll,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 62,
                        child: Row(
                          children: [
                            const SizedBox(width: 8),
                            Hero(
                              tag: FullPlayerScreen.heroTag,
                              child: ArtworkView(
                                size: 46,
                                url: track.artworkUrl,
                                borderRadius: AppRadii.smAll,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: AppColors.text,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textDim,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (player.isBuffering)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                  ),
                                ),
                              )
                            else
                              IconButton(
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  player.togglePlay();
                                },
                                icon: Icon(
                                  player.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                iconSize: 30,
                                color: AppColors.accentBright,
                                tooltip: player.isPlaying ? 'Пауза' : 'Играть',
                              ),
                            IconButton(
                              onPressed: player.hasQueue ? player.next : null,
                              icon: const Icon(Icons.skip_next_rounded),
                              iconSize: 26,
                              color: AppColors.text,
                              tooltip: 'Следующий трек',
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                      const _MiniProgressBar(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openFullPlayer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const FullPlayerScreen(),
      ),
    );
  }
}

/// Полоска прогресса мини-плеера.
///
/// Слушает [AudioPlayer.positionStream] напрямую: обновления позиции
/// происходят несколько раз в секунду и не должны перестраивать дерево
/// через [PlayerProvider].
class _MiniProgressBar extends StatelessWidget {
  const _MiniProgressBar();

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerProvider>().handler.player;
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snapshot) {
        final duration = player.duration;
        final position = snapshot.data ?? Duration.zero;
        final value = (duration != null && duration.inMilliseconds > 0)
            ? (position.inMilliseconds / duration.inMilliseconds)
                  .clamp(0.0, 1.0)
                  .toDouble()
            : null;
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 2.5,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.accentBright,
              ),
            ),
          ),
        );
      },
    );
  }
}
