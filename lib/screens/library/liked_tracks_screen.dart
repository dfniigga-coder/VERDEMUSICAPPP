import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/track.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/artwork.dart';
import '../../widgets/common.dart';
import '../../widgets/track_menu.dart';
import '../../widgets/track_tile.dart';

/// «Понравившиеся треки».
class LikedTracksScreen extends StatelessWidget {
  const LikedTracksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final tracks = library.likedTracks;

    if (tracks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Понравившиеся')),
        body: const EmptyState(
          icon: Icons.favorite_border_rounded,
          title: 'Пока ничего не понравилось',
          subtitle:
              'Ставьте «сердечки» трекам — они соберутся здесь и останутся '
              'после перезапуска',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Понравившиеся')),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, AppSpacing.pageBottom),
        itemCount: tracks.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return _Header(tracks: tracks);
          final track = tracks[index - 1];
          return TrackTile(
            track: track,
            onTap: () {
              context.read<PlayerProvider>().playTracks(
                tracks,
                startIndex: index - 1,
              );
            },
            onLongPress: () {
              showTrackMenu(context, track: track);
            },
            trailing: LikeButton(track: track),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final List<Track> tracks;

  const _Header({required this.tracks});

  @override
  Widget build(BuildContext context) {
    final urls = <String?>[
      for (final track in tracks.take(4)) track.artworkUrl,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: AppCard(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFB02E4E).withValues(alpha: 0.75),
            AppColors.surfaceRaised,
          ],
        ),
        borderRadius: AppRadii.xlAll,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _HeartMosaic(urls: urls),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'КОЛЛЕКЦИЯ',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: Color(0xFFFF9DB1),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Понравившиеся',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    trackCountLabel(tracks.length),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textDim,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => context
                            .read<PlayerProvider>()
                            .playTracks(tracks, startIndex: 0),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('Слушать'),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => context
                            .read<PlayerProvider>()
                            .playTracks(tracks, startIndex: 0, shuffle: true),
                        icon: const Icon(Icons.shuffle_rounded, size: 20),
                        color: AppColors.text,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          shape: const CircleBorder(),
                        ),
                        tooltip: 'Перемешать',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeartMosaic extends StatelessWidget {
  final List<String?> urls;

  const _HeartMosaic({required this.urls});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFFFF9DB1), const Color(0xFFB02E4E)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB02E4E).withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: urls.isEmpty
          ? const Icon(Icons.favorite_rounded, size: 40, color: Colors.white)
          : ClipOval(
              child: Wrap(
                children: [
                  for (var i = 0; i < 4; i++)
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: i < urls.length && urls[i] != null
                          ? ArtworkView(
                              size: 48,
                              url: urls[i],
                              borderRadius: BorderRadius.zero,
                            )
                          : const ColoredBox(color: AppColors.surfaceHigh),
                    ),
                ],
              ),
            ),
    );
  }
}
