import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/track.dart';
import '../../providers/player_provider.dart';
import '../../widgets/artwork.dart';
import '../../widgets/common.dart';
import '../../widgets/track_menu.dart';
import '../../widgets/track_tile.dart';

/// Полный список треков секции главной («Смотреть все») с editorial-шапкой.
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
    final startIdx = firstFull < 0 ? 0 : firstFull;
    final heroUrl = tracks.isEmpty ? null : tracks.first.artworkUrl;

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
                4,
                8,
                AppSpacing.pageBottom,
              ),
              itemCount: tracks.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: AppRadii.xlAll,
                        border: Border.all(color: AppColors.glassBorder),
                        boxShadow: AppShadows.card,
                      ),
                      child: ArtworkBackdrop(
                        url: heroUrl,
                        blur: 32,
                        overlayColor:
                            AppColors.forestDark.withValues(alpha: 0.56),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            AppColors.background.withValues(alpha: 0.9),
                          ],
                        ),
                        borderRadius: AppRadii.xlAll,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: AppRadii.lgAll,
                                  boxShadow: AppShadows.artwork,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.16),
                                  ),
                                ),
                                child: ArtworkView(
                                  size: 120,
                                  url: heroUrl,
                                  borderRadius: AppRadii.lgAll,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  color: AppColors.text,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                subtitle ?? trackCountLabel(tracks.length),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textDim,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () => context
                                          .read<PlayerProvider>()
                                          .playTracks(
                                            tracks,
                                            startIndex: startIdx,
                                          ),
                                      icon: const Icon(
                                        Icons.play_arrow_rounded,
                                        size: 21,
                                      ),
                                      label: const Text('Слушать'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => context
                                          .read<PlayerProvider>()
                                          .playTracks(
                                            tracks,
                                            startIndex: startIdx,
                                            shuffle: true,
                                          ),
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.08),
                                      ),
                                      icon: const Icon(
                                        Icons.shuffle_rounded,
                                        size: 19,
                                      ),
                                      label: const Text('Перемешать'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
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
                  onLongPress: () => showTrackMenu(context, track: track),
                  trailing: LikeButton(track: track),
                );
              },
            ),
    );
  }
}
