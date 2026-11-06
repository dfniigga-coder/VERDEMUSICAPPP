import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../data/models/track.dart';
import '../providers/player_provider.dart';
import 'artwork.dart';

/// Bottom-лист с очередью воспроизведения: текущий трек подсвечен,
/// есть кнопки перемешивания по списку и удаления треков.
Future<void> showQueueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
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
    final listHeight = (height * 0.72).clamp(320.0, height - 160).toDouble();

    return SizedBox(
      height: listHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Очередь',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${queue.length} ${queue.length == 1 ? 'трек' : 'треков'}',
                  style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: player.hasQueue ? player.toggleShuffle : null,
                      icon: Icon(
                        Icons.shuffle,
                        size: 18,
                        color: player.isShuffleEnabled
                            ? AppTheme.accentGreen
                            : AppTheme.textDim,
                      ),
                      label: Text(
                        player.isShuffleEnabled ? 'Перемешано' : 'Перемешать',
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed:
                          player.hasQueue ? () => player.clearQueue() : null,
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text('Очистить'),
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
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: queue.length,
                    itemBuilder: (context, index) {
                      final track = queue[index];
                      final isCurrent = index == currentIndex;

                      Widget trailing;
                      if (isCurrent) {
                        if (player.isPlaying) {
                          trailing = const PlayingIndicator();
                        } else {
                          trailing = const Icon(
                            Icons.pause_rounded,
                            color: AppTheme.accentGreen,
                          );
                        }
                      } else {
                        trailing = IconButton(
                          onPressed: () => player.removeFromQueue(index),
                          icon: const Icon(
                            Icons.close,
                            color: AppTheme.textDim,
                            size: 20,
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
    return ListTile(
      onTap: onTap,
      leading: ArtworkView(
        size: 44,
        url: track.artworkUrl,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: isCurrent
              ? AppTheme.accentGreen
              : const Color(0xFFE9ECEA),
        ),
      ),
      subtitle: Text(
        '${track.artist} · ${formatDuration(
          track.durationSec == null
              ? null
              : Duration(seconds: track.durationSec!),
        )}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
      ),
      trailing: trailing,
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
          Icon(Icons.queue_music, size: 48, color: AppTheme.textDim),
          SizedBox(height: 12),
          Text('Очередь пуста'),
        ],
      ),
    );
  }
}

/// Пульсирующий индикатор играющего трека.
class PlayingIndicator extends StatelessWidget {
  const PlayingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.volume_up, size: 16, color: AppTheme.accentGreen),
        SizedBox(width: 4),
        _Bars(),
      ],
    );
  }
}

class _Bars extends StatefulWidget {
  const _Bars();

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        const colors = AppTheme.accentGreen;
        return Row(
          children: [
            _bar(0.3 + 0.7 * (0.5 + 0.5 * (t * 6 % 2 == 0 ? t : 1 - t)), colors),
            const SizedBox(width: 2),
            _bar(0.3 + 0.7 * (0.5 + 0.5 * ((t * 4 + 0.3) % 2)), colors),
            const SizedBox(width: 2),
            _bar(0.3 + 0.7 * (0.5 + 0.5 * ((t * 8 + 0.6) % 2)), colors),
          ],
        );
      },
    );
  }

  Widget _bar(double h, Color color) {
    return Container(
      width: 3,
      height: 14 * h.clamp(0.2, 1.0),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
