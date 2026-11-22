import 'dart:typed_data';

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
    final isCurrent = context.select<PlayerProvider, bool>(
      (player) => player.currentTrack?.id == track.id,
    );

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      tileColor: isCurrent
          ? AppTheme.accentGreen.withValues(alpha: 0.08)
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
          if (track.isPreview) ...[
            const SizedBox(width: 6),
            const _TrackBadge(
              text: 'превью 30 с',
              icon: Icons.timer_outlined,
              foreground: Color(0xFFF0C674),
              background: Color(0x33F0C674),
            ),
          ],
          if (track.source != TrackSource.local) ...[
            const SizedBox(width: 6),
            _TrackBadge(
              text: track.source.label,
              icon: _sourceIcon(track.source),
            ),
          ],
        ],
      ),
      trailing: trailing ?? _duration(),
    );
  }

  Widget _leading() {
    if (track.source == TrackSource.local) {
      final songId = track.localSongId;
      if (songId != null) return _LocalLeading(songId: songId);
      return ArtworkView(
        size: 52,
        url: track.artworkUrl,
        placeholderIcon: Icons.audio_file_outlined,
      );
    }
    return ArtworkView(size: 52, url: track.artworkUrl);
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
    return LocalArtworkView(size: 52, artwork: _artwork);
  }
}

/// Небольшой значок источника или пометка «превью».
class _TrackBadge extends StatelessWidget {
  final String text;

  final IconData icon;

  final Color foreground;

  final Color background;

  const _TrackBadge({
    required this.text,
    required this.icon,
    this.foreground = AppTheme.textDim,
    this.background = const Color(0x1AFFFFFF),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: foreground),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 9.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _sourceIcon(TrackSource source) {
  switch (source) {
    case TrackSource.audius:
      return Icons.waves;
    case TrackSource.deezer:
      return Icons.graphic_eq;
    case TrackSource.itunes:
      return Icons.music_note;
    case TrackSource.jamendo:
      return Icons.public;
    case TrackSource.archive:
      return Icons.account_balance;
    case TrackSource.external:
      return Icons.link;
    case TrackSource.local:
      return Icons.folder;
    case TrackSource.soundcloud:
      return Icons.cloud;
    case TrackSource.youtube:
      return Icons.smart_display;
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
      icon: Icon(liked ? Icons.favorite : Icons.favorite_border_outlined),
      color: liked ? AppTheme.accentGreen : AppTheme.textDim,
      tooltip: liked ? 'Убрать из «Мне нравится»' : 'Добавить в «Мне нравится»',
    );
  }
}
