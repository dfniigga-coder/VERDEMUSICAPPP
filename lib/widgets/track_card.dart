import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/design_tokens.dart';
import '../data/models/track.dart';
import '../data/repositories/local_tracks_repository.dart';
import 'artwork.dart';
import 'pressable_scale.dart';

/// Карточка трека для горизонтальных секций главной.
///
/// Размеры фиксированы, чтобы ListView мог задать высоту рельса заранее:
/// обложка [width]×[width] + название + исполнитель.
class TrackCard extends StatelessWidget {
  final Track track;

  final VoidCallback onTap;

  final double width;

  const TrackCard({
    super.key,
    required this.track,
    required this.onTap,
    this.width = 160,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: SizedBox(
        width: width,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.lgAll,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _artwork(context),
              const SizedBox(height: 10),
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artwork(BuildContext context) {
    final radius = AppRadii.lgAll;
    final songId = track.localSongId;

    Widget art;
    if (track.source == TrackSource.local && songId != null) {
      final repo = context.read<LocalTracksRepository>();
      art = LocalArtworkView(
        size: width,
        borderRadius: radius,
        artwork: repo.artwork(songId),
      );
    } else {
      art = ArtworkView(
        size: width,
        url: track.artworkUrl,
        borderRadius: radius,
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: AppShadows.artwork,
      ),
      child: art,
    );
  }
}
