import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../providers/player_provider.dart';
import '../screens/player/full_player_screen.dart';
import 'artwork.dart';

/// Мини-плеер над нижней навигацией. Тап открывает полноэкранный плеер.
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final track = player.currentTrack;
        if (track == null) return const SizedBox.shrink();

        return Material(
          color: AppTheme.surfaceContainer,
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _progressLine(player),
                InkWell(
                  onTap: () => _openFullPlayer(context),
                  child: SizedBox(
                    height: 62,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: ArtworkView(
                            size: 44,
                            url: track.artworkUrl,
                            borderRadius:
                                const BorderRadius.all(Radius.circular(8)),
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
                                  color: Color(0xFFE9ECEA),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textDim,
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
                            onPressed: player.togglePlay,
                            icon: Icon(
                              player.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            iconSize: 32,
                            color: const Color(0xFFE9ECEA),
                          ),
                        IconButton(
                          onPressed: player.hasQueue ? player.next : null,
                          icon: const Icon(Icons.skip_next_rounded),
                          iconSize: 28,
                          color: const Color(0xFFE9ECEA),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Тонкая линия прогресса сверху.
  Widget _progressLine(PlayerProvider player) {
    return StreamBuilder<Duration>(
      stream: player.handler.player.positionStream,
      builder: (context, _) {
        final duration = player.handler.player.duration;
        final position = player.handler.player.position;
        final value = duration == null || duration.inMilliseconds == 0
            ? null
            : (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0)
                .toDouble();
        return LinearProgressIndicator(
          value: value,
          minHeight: 2,
          backgroundColor: Colors.transparent,
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
