import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/design_tokens.dart';
import '../core/utils/formatters.dart';
import '../data/models/track.dart';
import '../providers/player_provider.dart';
import 'artwork.dart';
import 'equalizer_bars.dart';

/// Стеклянный bottom-лист с очередью воспроизведения.
Future<void> showQueueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (_) => const _QueueSheet(),
  );
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final queue = player.queue;
    final currentIndex = player.currentIndex;

    final height = MediaQuery.of(context).size.height;
    final maxHeight = height - 120;
    final listHeight = maxHeight <= 340
        ? maxHeight
        : (height * 0.78).clamp(340.0, maxHeight).toDouble();

    return SizedBox(
      height: listHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.glassBorder,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Очередь',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Text(
                        trackCountLabel(queue.length),
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: player.hasQueue ? player.toggleShuffle : null,
                      icon: Icon(
                        Icons.shuffle_rounded,
                        size: 18,
                        color: player.isShuffleEnabled
                            ? AppColors.accentBright
                            : AppColors.textDim,
                      ),
                      label: Text(
                        player.isShuffleEnabled ? 'Перемешано' : 'Перемешать',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: player.isShuffleEnabled
                            ? AppColors.accentBright
                            : AppColors.textDim,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: player.hasQueue
                          ? () => player.clearQueue()
                          : null,
                      icon: const Icon(Icons.clear_all_rounded, size: 18),
                      label: const Text('Очистить'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: queue.isEmpty
                ? const EmptyQueue()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                    itemCount: queue.length,
                    itemBuilder: (context, index) {
                      final track = queue[index];
                      final isCurrent = index == currentIndex;

                      Widget trailing;
                      if (isCurrent) {
                        trailing = const PlayingIndicator();
                      } else {
                        trailing = IconButton(
                          onPressed: () => player.removeFromQueue(index),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppColors.textMuted,
                            size: 19,
                          ),
                          tooltip: 'Убрать из очереди',
                        );
                      }

                      return _QueueTile(
                        track: track,
                        isCurrent: isCurrent,
                        trailing: trailing,
                        onTap: () => player.playAt(index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  final Track track;
  final bool isCurrent;
  final Widget trailing;
  final VoidCallback onTap;

  const _QueueTile({
    required this.track,
    required this.isCurrent,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isCurrent ? AppColors.accentSoft(0.12) : Colors.transparent,
        borderRadius: AppRadii.mdAll,
        border: isCurrent
            ? Border.all(color: AppColors.accentBright.withValues(alpha: 0.24))
            : null,
      ),
      child: ListTile(
        onTap: onTap,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
        leading: ArtworkView(
          size: 44,
          url: track.artworkUrl,
          borderRadius: AppRadii.smAll,
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
            fontSize: 14,
            color: isCurrent ? AppColors.accentBright : AppColors.text,
          ),
        ),
        subtitle: Text(
          '${track.artist} · ${formatDuration(track.durationSec == null ? null : Duration(seconds: track.durationSec!))}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
        trailing: trailing,
      ),
    );
  }
}

class EmptyQueue extends StatelessWidget {
  const EmptyQueue({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.queue_music_rounded, size: 46, color: AppColors.textMuted),
          SizedBox(height: 12),
          Text(
            'Очередь пуста',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Индикатор играющего трека.
class PlayingIndicator extends StatelessWidget {
  const PlayingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10),
      child: EqualizerBars(height: 16, barWidth: 3, gap: 2),
    );
  }
}
