import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/track.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/artwork.dart';
import '../../widgets/common.dart';
import '../../widgets/track_menu.dart';
import '../../widgets/track_tile.dart';

/// «Понравившиеся треки» с editorial-шапкой в стиле Apple Music и быстрым фильтром.
class LikedTracksScreen extends StatefulWidget {
  const LikedTracksScreen({super.key});

  @override
  State<LikedTracksScreen> createState() => _LikedTracksScreenState();
}

class _LikedTracksScreenState extends State<LikedTracksScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final allTracks = library.likedTracks;

    if (allTracks.isEmpty) {
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

    final q = _filter.trim().toLowerCase();
    final tracks = q.isEmpty
        ? allTracks
        : allTracks
              .where(
                (t) =>
                    t.title.toLowerCase().contains(q) ||
                    t.artist.toLowerCase().contains(q),
              )
              .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Понравившиеся')),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, AppSpacing.pageBottom),
        itemCount: tracks.length + (allTracks.length >= 6 ? 2 : 1),
        itemBuilder: (context, index) {
          if (index == 0) return _Header(tracks: allTracks);
          if (allTracks.length >= 6 && index == 1) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: TextField(
                onChanged: (v) => setState(() => _filter = v),
                decoration: const InputDecoration(
                  hintText: 'Фильтр по названию или артисту…',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                ),
              ),
            );
          }
          final trackIndex = index - (allTracks.length >= 6 ? 2 : 1);
          final track = tracks[trackIndex];
          return TrackTile(
            track: track,
            onTap: () {
              context.read<PlayerProvider>().playTracks(
                tracks,
                startIndex: trackIndex,
              );
            },
            onLongPress: () => showTrackMenu(context, track: track),
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

  String _totalDurationLabel() {
    var sec = 0;
    for (final t in tracks) {
      sec += t.durationSec ?? 0;
    }
    if (sec <= 0) return trackCountLabel(tracks.length);
    final mins = (sec / 60).round();
    return '${trackCountLabel(tracks.length)} · ~$mins мин';
  }

  @override
  Widget build(BuildContext context) {
    final urls = <String?>[
      for (final track in tracks.take(4)) track.artworkUrl,
    ];
    final firstArtwork = urls.firstWhere((u) => u != null, orElse: () => null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadii.xlAll,
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: AppShadows.card,
        ),
        child: ArtworkBackdrop(
          url: firstArtwork,
          blur: 32,
          overlayColor: const Color(0xFF4A1221).withValues(alpha: 0.65),
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
                _HeartMosaic(urls: urls),
                const SizedBox(height: 14),
                const Text(
                  'КОЛЛЕКЦИЯ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: Color(0xFFFF9DB1),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Понравившиеся',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _totalDurationLabel(),
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
                            .playTracks(tracks, startIndex: 0),
                        icon: const Icon(Icons.play_arrow_rounded, size: 21),
                        label: const Text('Слушать'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context
                            .read<PlayerProvider>()
                            .playTracks(tracks, startIndex: 0, shuffle: true),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                        ),
                        icon: const Icon(Icons.shuffle_rounded, size: 19),
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
}

class _HeartMosaic extends StatelessWidget {
  final List<String?> urls;

  const _HeartMosaic({required this.urls});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 124,
      height: 124,
      decoration: BoxDecoration(
        borderRadius: AppRadii.lgAll,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF9DB1), Color(0xFFB02E4E)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB02E4E).withValues(alpha: 0.45),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: urls.isEmpty
          ? const Icon(Icons.favorite_rounded, size: 48, color: Colors.white)
          : ClipRRect(
              borderRadius: AppRadii.lgAll,
              child: Wrap(
                children: [
                  for (var i = 0; i < 4; i++)
                    SizedBox(
                      width: 62,
                      height: 62,
                      child: i < urls.length && urls[i] != null
                          ? ArtworkView(
                              size: 62,
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
