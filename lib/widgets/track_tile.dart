import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/design_tokens.dart';
import '../data/models/track.dart';
import '../data/repositories/local_tracks_repository.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import 'artwork.dart';
import 'equalizer_bars.dart';
import 'source_badge.dart';

/// Строка трека: обложка, название, исполнитель, опциональный trailing.
///
/// Родитель отвечает за поведение по нажатию (обычно — playTracks по списку).
class TrackTile extends StatelessWidget {
  final Track track;

  final VoidCallback? onTap;

  final VoidCallback? onLongPress;

  final Widget? trailing;

  const TrackTile({
    super.key,
    required this.track,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = context.select<PlayerProvider, bool>(
      (player) => player.currentTrack?.id == track.id,
    );
    final isPlaying = context.select<PlayerProvider, bool>(
      (player) => isCurrent && player.isPlaying,
    );

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      tileColor: isCurrent ? AppColors.accentSoft(0.08) : null,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      leading: _leading(isCurrent: isCurrent, isPlaying: isPlaying),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: isCurrent ? AppColors.accentBright : AppColors.text,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ),
            if (track.isPreview) ...[
              const SizedBox(width: 6),
              const PreviewBadge(),
            ],
            if (track.source != TrackSource.local) ...[
              const SizedBox(width: 6),
              TrackSourceBadge(track: track),
            ],
          ],
        ),
      ),
      trailing: trailing ?? _duration(),
    );
  }

  Widget _leading({required bool isCurrent, required bool isPlaying}) {
    Widget art;
    if (track.source == TrackSource.local) {
      final songId = track.localSongId;
      if (songId != null) {
        art = _LocalLeading(songId: songId);
      } else {
        art = ArtworkView(
          size: 52,
          url: track.artworkUrl,
          borderRadius: AppRadii.smAll,
          placeholderIcon: Icons.audio_file_outlined,
        );
      }
    } else {
      art = ArtworkView(
        size: 52,
        url: track.artworkUrl,
        borderRadius: AppRadii.smAll,
      );
    }

    if (!isCurrent) return art;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        art,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.stroke),
            ),
            child: Center(
              child: EqualizerBars(
                height: 9,
                barWidth: 2,
                gap: 1.5,
                playing: isPlaying,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _duration() {
    if (track.durationSec == null) return null;
    final m = track.durationSec! ~/ 60;
    final s = (track.durationSec! % 60).toString().padLeft(2, '0');
    return Text(
      '$m:$s',
      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
    );
  }
}

/// Обложка локального трека — грузит artwork по id песни.
///
/// Future кэшируется в состоянии: без этого каждый ребилд строки
/// (например, при смене текущего трека) заново запрашивал бы обложку
/// из MediaStore.
class _LocalLeading extends StatefulWidget {
  final int songId;

  const _LocalLeading({required this.songId});

  @override
  State<_LocalLeading> createState() => _LocalLeadingState();
}

class _LocalLeadingState extends State<_LocalLeading> {
  Future<Uint8List?>? _artwork;

  @override
  void initState() {
    super.initState();
    _loadArtwork();
  }

  @override
  void didUpdateWidget(covariant _LocalLeading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) _loadArtwork();
  }

  void _loadArtwork() {
    _artwork = context.read<LocalTracksRepository>().artwork(widget.songId);
  }

  @override
  Widget build(BuildContext context) {
    return LocalArtworkView(
      size: 52,
      artwork: _artwork,
      borderRadius: AppRadii.smAll,
    );
  }
}

/// Кнопка-сердечко для trailing у строки трека.
class LikeButton extends StatelessWidget {
  final Track track;

  const LikeButton({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    final liked = context.select<LibraryProvider, bool>(
      (lib) => lib.isLiked(track),
    );

    return IconButton(
      onPressed: () => context.read<LibraryProvider>().toggleLike(track),
      icon: Icon(
        liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        size: 21,
      ),
      color: liked ? AppColors.accentBright : AppColors.textMuted,
      tooltip: liked ? 'Убрать из «Мне нравится»' : 'Добавить в «Мне нравится»',
    );
  }
}
