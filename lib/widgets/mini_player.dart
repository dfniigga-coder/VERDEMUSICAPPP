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
                            borderRadius: const BorderRadius.all(
                              Radius.circular(8),
                            ),
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
                // Тонкая статичная полоска прогресса.
                //
                // Позицию берём напрямую из just_audio: PlayerProvider
                // намеренно не рассылает уведомления на каждый тик, иначе
                // перестраивался бы весь список треков.
                const _MiniProgressBar(),
              ],
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
            ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                0.0,
                1.0,
              )
            : null;
        return LinearProgressIndicator(
          value: value,
          minHeight: 2,
          backgroundColor: AppTheme.surfaceContainer,
          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentGreen),
        );
      },
    );
  }
}
