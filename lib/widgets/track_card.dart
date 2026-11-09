import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../data/models/track.dart';
import '../data/repositories/local_tracks_repository.dart';
import 'artwork.dart';

/// Карточка трека для горизонтальных секций главной.
///
/// Размеры фиксированы, чтобы ListView мог задать высоту рельса заранее:
/// обложка 144×144 + название + исполнитель.
class TrackCard extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final double width;

  const TrackCard({
    super.key,
    required this.track,
    required this.onTap,
    this.width = 144,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _artwork(context),
            const SizedBox(height: 8),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE9ECEA),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
            ),
          ],
        ),
      ),
    );
  }

  Widget _artwork(BuildContext context) {
    final radius = BorderRadius.circular(12);
    final songId = track.localSongId;

    if (track.source == TrackSource.local && songId != null) {
      final repo = context.read<LocalTracksRepository>();
      return LocalArtworkView(
        size: width,
        borderRadius: radius,
        artwork: repo.artwork(songId),
      );
    }

    return ArtworkView(
      size: width,
      url: track.artworkUrl,
      borderRadius: radius,
    );
  }
}
