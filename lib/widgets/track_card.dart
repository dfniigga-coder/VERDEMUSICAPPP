import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/design_tokens.dart';
import '../data/models/track.dart';
import '../data/repositories/local_tracks_repository.dart';
import '../providers/player_provider.dart';
import 'artwork.dart';
import 'equalizer_bars.dart';
import 'pressable_scale.dart';
import 'track_menu.dart';

/// Карточка трека для горизонтальных секций главной в стиле Apple Music / Spotify.
class TrackCard extends StatelessWidget {
  final Track track;

  final VoidCallback onTap;

  final VoidCallback? onLongPress;

  final double width;

  const TrackCard({
    super.key,
    required this.track,
    required this.onTap,
    this.onLongPress,
    this.width = 156,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = context.select<PlayerProvider, bool>(
      (player) => player.currentTrack?.id == track.id,
    );
    final isPlaying = context.select<PlayerProvider, bool>(
      (player) => isCurrent && player.isPlaying,
    );

    return PressableScale(
      child: SizedBox(
        width: width,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress ?? () => showTrackMenu(context, track: track),
          borderRadius: AppRadii.lgAll,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _artwork(context, isCurrent: isCurrent, isPlaying: isPlaying),
              const SizedBox(height: 10),
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                  color: isCurrent ? AppColors.accentBright : AppColors.text,
                ),
              ),
              const SizedBox(height: 2.5),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artwork(
    BuildContext context, {
    required bool isCurrent,
    required bool isPlaying,
  }) {
    const radius = BorderRadius.all(Radius.circular(18));
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
      width: width,
      height: width,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: AppShadows.artwork,
        border: Border.all(
          color: isCurrent
              ? AppColors.accentBright.withValues(alpha: 0.55)
              : AppColors.glassBorder,
        ),
      ),
      child: Stack(
        children: [
          ClipRRect(borderRadius: radius, child: art),
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCurrent
                    ? AppColors.accent
                    : Colors.black.withValues(alpha: 0.62),
                border: Border.all(
                  color: isCurrent
                      ? AppColors.accentBright
                      : Colors.white.withValues(alpha: 0.2),
                ),
              ),
              child: Center(
                child: isCurrent
                    ? EqualizerBars(
                        height: 12,
                        barWidth: 2.5,
                        gap: 1.8,
                        playing: isPlaying,
                        color: Colors.black,
                      )
                    : const Icon(
                        Icons.play_arrow_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
