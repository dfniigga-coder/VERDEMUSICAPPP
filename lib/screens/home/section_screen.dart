import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/track.dart';
import '../../providers/player_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/track_tile.dart';

/// Полный список треков секции главной («Смотреть все»).
class SectionTracksScreen extends StatelessWidget {
  final String title;

  final String? subtitle;

  final List<Track> tracks;

  const SectionTracksScreen({
    super.key,
    required this.title,
    required this.tracks,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final firstFull = tracks.indexWhere((track) => !track.isPreview);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: tracks.isEmpty
          ? const EmptyState(
              icon: Icons.queue_music_rounded,
              title: 'Здесь пока нет треков',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                8,
                8,
                8,
                AppSpacing.pageBottom,
              ),
              itemCount: tracks.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trackCountLabel(tracks.length),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 3),
                                Text(
                                  subtitle!,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.textMuted),
                                ),
                              ],
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () =>
                              context.read<PlayerProvider>().playTracks(
                                tracks,
                                startIndex: firstFull < 0 ? 0 : firstFull,
                              ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text('Слушать'),
                        ),
                      ],
                    ),
                  );
                }

                final track = tracks[index - 1];
                return TrackTile(
                  track: track,
                  onTap: () => context.read<PlayerProvider>().playTracks(
                    tracks,
                    startIndex: index - 1,
                  ),
                  trailing: LikeButton(track: track),
                );
              },
            ),
    );
  }
}
