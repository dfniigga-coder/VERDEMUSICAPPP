import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/design_tokens.dart';
import '../data/models/track.dart';
import '../data/repositories/local_tracks_repository.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import 'artwork.dart';
import 'common.dart';
import 'equalizer_bars.dart';
import 'source_badge.dart';

/// Строка трека в стиле Apple Music / Spotify:
/// обложка 52×52, поверх играющей обложки — эквалайзер, свайп вправо добавляет
/// трек в очередь, свайп влево ставит/убирает лайк.
class TrackTile extends StatelessWidget {
  final Track track;

  final VoidCallback? onTap;

  final VoidCallback? onLongPress;

  final Widget? trailing;

  final bool enableSwipe;

  const TrackTile({
    super.key,
    required this.track,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.enableSwipe = true,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = context.select<PlayerProvider, bool>(
      (player) => player.currentTrack?.id == track.id,
    );
    final isPlaying = context.select<PlayerProvider, bool>(
      (player) => isCurrent && player.isPlaying,
    );

    final tile = Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isCurrent ? AppColors.accentSoft(0.11) : Colors.transparent,
        borderRadius: AppRadii.mdAll,
        border: isCurrent
            ? Border.all(color: AppColors.accentBright.withValues(alpha: 0.24))
            : null,
      ),
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        leading: _leading(isCurrent: isCurrent, isPlaying: isPlaying),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
            fontSize: 14.5,
            letterSpacing: -0.15,
            color: isCurrent ? AppColors.accentBright : AppColors.text,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2.5),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12.5,
                  ),
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
      ),
    );

    if (!enableSwipe) return tile;
    return _SwipeableTrackWrapper(track: track, child: tile);
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

    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          art,
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: AppRadii.smAll,
              color: Colors.black.withValues(alpha: 0.56),
            ),
            child: Center(
              child: EqualizerBars(
                height: 15,
                barWidth: 3,
                gap: 2.2,
                playing: isPlaying,
                color: AppColors.accentBright,
              ),
            ),
          ),
        ],
      ),
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

/// Лёгкий свайп без удаления элемента из дерева:
/// свайп вправо → «В очередь», свайп влево → «Лайк».
class _SwipeableTrackWrapper extends StatefulWidget {
  final Track track;
  final Widget child;

  const _SwipeableTrackWrapper({required this.track, required this.child});

  @override
  State<_SwipeableTrackWrapper> createState() => _SwipeableTrackWrapperState();
}

class _SwipeableTrackWrapperState extends State<_SwipeableTrackWrapper>
    with SingleTickerProviderStateMixin {
  static const double _maxExtent = 78.0;
  static const double _triggerThreshold = 52.0;

  double _dragOffset = 0;
  bool _triggered = false;

  void _onDragUpdate(DragUpdateDetails details) {
    final next = (_dragOffset + details.delta.dx).clamp(
      -_maxExtent,
      _maxExtent,
    );
    if ((next.abs() >= _triggerThreshold) && !_triggered) {
      _triggered = true;
      HapticFeedback.mediumImpact();
    } else if (next.abs() < _triggerThreshold) {
      _triggered = false;
    }
    setState(() => _dragOffset = next);
  }

  void _onDragEnd(DragEndDetails details) {
    final offset = _dragOffset;
    setState(() {
      _dragOffset = 0;
      _triggered = false;
    });

    if (offset >= _triggerThreshold) {
      context.read<PlayerProvider>().addToQueue(widget.track);
      showAppSnackBar(context, '«${widget.track.title}» добавлен в очередь');
    } else if (offset <= -_triggerThreshold) {
      final library = context.read<LibraryProvider>();
      final wasLiked = library.isLiked(widget.track);
      library.toggleLike(widget.track);
      showAppSnackBar(
        context,
        wasLiked ? 'Убрано из «Понравившихся»' : 'Добавлено в «Понравившиеся»',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragOffset.abs() / _triggerThreshold).clamp(0.0, 1.0);
    final isQueueSwipe = _dragOffset > 0;
    final isLikeSwipe = _dragOffset < 0;

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: () => setState(() {
        _dragOffset = 0;
        _triggered = false;
      }),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isQueueSwipe)
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                padding: const EdgeInsets.only(left: 18),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14 + 0.16 * progress),
                  borderRadius: AppRadii.mdAll,
                ),
                alignment: Alignment.centerLeft,
                child: Icon(
                  Icons.queue_music_rounded,
                  color: AppColors.accentBright.withValues(alpha: 0.5 + 0.5 * progress),
                  size: 22,
                ),
              ),
            ),
          if (isLikeSwipe)
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                padding: const EdgeInsets.only(right: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B81).withValues(
                    alpha: 0.14 + 0.16 * progress,
                  ),
                  borderRadius: AppRadii.mdAll,
                ),
                alignment: Alignment.centerRight,
                child: Icon(
                  Icons.favorite_rounded,
                  color: const Color(0xFFFF6B81).withValues(
                    alpha: 0.5 + 0.5 * progress,
                  ),
                  size: 22,
                ),
              ),
            ),
          AnimatedContainer(
            duration: _dragOffset == 0
                ? const Duration(milliseconds: 220)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_dragOffset, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// Обложка локального трека — грузит artwork по id песни.
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
  final Color? inactiveColor;
  final double size;

  const LikeButton({
    super.key,
    required this.track,
    this.inactiveColor,
    this.size = 21,
  });

  @override
  Widget build(BuildContext context) {
    final liked = context.select<LibraryProvider, bool>(
      (lib) => lib.isLiked(track),
    );

    return IconButton(
      onPressed: () {
        HapticFeedback.selectionClick();
        context.read<LibraryProvider>().toggleLike(track);
      },
      icon: Icon(
        liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        size: size,
      ),
      color: liked
          ? AppColors.accentBright
          : (inactiveColor ?? AppColors.textMuted),
      tooltip: liked ? 'Убрать из «Мне нравится»' : 'Добавить в «Мне нравится»',
    );
  }
}
