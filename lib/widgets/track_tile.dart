import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../data/models/track.dart';
import '../data/repositories/local_tracks_repository.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import 'artwork.dart';

/// Строка трека: обложка, название, исполнитель, опциональный trailing.
///
/// Родитель отвечает за поведение по нажатию (обычно —_playTracks по списку).
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
    final provider = context.watch<PlayerProvider>();
    final isCurrent = provider.currentTrack?.id == track.id;

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: _leading(),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: isCurrent ? AppTheme.accentGreen : const Color(0xFFE9ECEA),
        ),
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
          ),
          if (track.isAudius && track.genre != null) ...[
            const SizedBox(width: 6),
            Text(
              track.genre!,
              maxLines: 1,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
            ),
          ],
        ],
      ),
      trailing: trailing ?? _duration(),
    );
  }

  Widget _leading() {
    if (track.isAudius) {
      return ArtworkView(size: 52, url: track.artworkUrl);
    }
    return _LocalLeading(songId: track.localSongId ?? 0);
  }

  Widget? _duration() {
    if (track.durationSec == null) return null;
    final m = track.durationSec! ~/ 60;
    final s = (track.durationSec! % 60).toString().padLeft(2, '0');
    return Text(
      '$m:$s',
      style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
    );
  }
}

/// Обложка локального трека — грузит artwork по id песни.
class _LocalLeading extends StatelessWidget {
  final int songId;

  const _LocalLeading({required this.songId});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<LocalTracksRepository>();
    return LocalArtworkView(
      size: 52,
      artwork: repo.artwork(songId),
    );
  }
}

/// Кнопка-сердечко для trailing у строки трека.
class LikeButton extends StatelessWidget {
  final Track track;

  const LikeButton({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    final liked = context.select<LibraryProvider, bool>((lib) => lib.isLiked(track));

    return IconButton(
      onPressed: () => context.read<LibraryProvider>().toggleLike(track),
      icon: Icon(liked ? Icons.favorite : Icons.favorite_border_outlined),
      color: liked ? AppTheme.accentGreen : AppTheme.textDim,
      tooltip: liked ? 'Убрать из «Мне нравится»' : 'Добавить в «Мне нравится»',
    );
  }
}
