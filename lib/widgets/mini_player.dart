import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/design_tokens.dart';
import '../providers/player_provider.dart';
import '../screens/player/full_player_screen.dart';
import 'artwork.dart';
import 'pressable_scale.dart';
import 'track_tile.dart';

/// Парящий мини-плеер в стиле Apple Music iOS 18 + жесты Spotify:
/// горизонтальный свайп переключает трек, свайп вверх или тап открывают
/// полноэкранный плеер с плавным переходом.
class MiniPlayerBar extends StatefulWidget {
  const MiniPlayerBar({super.key});

  @override
  State<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<MiniPlayerBar> {
  double _dragDx = 0;

  void _openFullPlayer(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 340),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) => const FullPlayerScreen(),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.14),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          );
        },
      ),
    );
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragDx = (_dragDx + details.delta.dx).clamp(-64.0, 64.0);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details, PlayerProvider player) {
    final dx = _dragDx;
    final velocity = details.primaryVelocity ?? 0;
    setState(() => _dragDx = 0);

    if (!player.hasQueue) return;
    if (dx < -34 || velocity < -380) {
      HapticFeedback.selectionClick();
      player.next();
    } else if (dx > 34 || velocity > 380) {
      HapticFeedback.selectionClick();
      player.previous();
    }
  }

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
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: (details) =>
                _onHorizontalDragEnd(details, player),
            onHorizontalDragCancel: () => setState(() => _dragDx = 0),
            child: AnimatedContainer(
              duration: _dragDx == 0
                  ? const Duration(milliseconds: 220)
                  : Duration.zero,
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(_dragDx, 0, 0),
              decoration: BoxDecoration(
                borderRadius: AppRadii.lgAll,
                boxShadow: AppShadows.floatingBar,
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: AppRadii.lgAll,
                clipBehavior: Clip.antiAlias,
                child: ArtworkBackdrop(
                  url: track.artworkUrl,
                  blur: 24,
                  overlayColor: AppColors.surfaceRaised.withValues(alpha: 0.65),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.surfaceRaised.withValues(alpha: 0.78),
                      AppColors.background.withValues(alpha: 0.92),
                    ],
                  ),
                  borderRadius: AppRadii.lgAll,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: AppRadii.lgAll,
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    foregroundDecoration: BoxDecoration(
                      borderRadius: AppRadii.lgAll,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.08),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.3],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 62,
                          child: Row(
                            children: [
                              const SizedBox(width: 9),
                              Hero(
                                tag: FullPlayerScreen.heroTag,
                                child: ArtworkView(
                                  size: 46,
                                  url: track.artworkUrl,
                                  borderRadius: AppRadii.smAll,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            track.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13.5,
                                              letterSpacing: -0.15,
                                              color: AppColors.text,
                                            ),
                                          ),
                                        ),
                                        if (player.hasCustomAudioEffect) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 1.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.accentSoft(0.24),
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                            ),
                                            child: Text(
                                              '${player.speed.toStringAsFixed(2)}x',
                                              style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.accentBright,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (player.hasSleepTimer) ...[
                                          const SizedBox(width: 5),
                                          const Icon(
                                            Icons.bedtime_rounded,
                                            size: 12,
                                            color: AppColors.accentBright,
                                          ),
                                        ],
                                      ],
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
                              LikeButton(
                                track: track,
                                inactiveColor: AppColors.textDim,
                                size: 20,
                              ),
                              if (player.isBuffering)
                                const Padding(
                                  padding: EdgeInsets.all(10),
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
                                iconSize: 25,
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
          ),
        );
      },
    );
  }
}

/// Полоска прогресса мини-плеера.
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
              backgroundColor: Colors.white.withValues(alpha: 0.1),
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
