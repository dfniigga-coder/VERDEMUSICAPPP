import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/lyrics.dart';
import '../../data/models/track.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/lyrics_service.dart';
import '../../widgets/ambient_artwork_background.dart';
import '../../widgets/artwork.dart';
import '../../widgets/audio_effects_sheet.dart';
import '../../widgets/common.dart';
import '../../widgets/download_sheet.dart';
import '../../widgets/equalizer_bars.dart';
import '../../widgets/play_button.dart';
import '../../widgets/track_menu.dart';
import '../../widgets/track_tile.dart';

enum _PlayerMode { artwork, lyrics, queue }

/// Полноэкранный плеер в стиле Apple Music iOS 18 + жесты Spotify:
/// переливающийся фон из обложки, «дышащая» обложка со свайпом треков,
/// двойной тап для лайка, встроенное караоке с размытием глубины и очередь.
class FullPlayerScreen extends StatefulWidget {
  static const String heroTag = 'player-artwork';

  const FullPlayerScreen({super.key});

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  _PlayerMode _mode = _PlayerMode.artwork;
  double _dismissOffsetY = 0;

  void _toggleMode(_PlayerMode target) {
    HapticFeedback.selectionClick();
    setState(() {
      _mode = _mode == target ? _PlayerMode.artwork : target;
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_mode != _PlayerMode.artwork) return;
    if (details.delta.dy > 0 || _dismissOffsetY > 0) {
      setState(() {
        _dismissOffsetY = (_dismissOffsetY + details.delta.dy).clamp(0.0, 220.0);
      });
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_mode != _PlayerMode.artwork) return;
    final velocity = details.primaryVelocity ?? 0;
    if (_dismissOffsetY > 95 || velocity > 650) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _dismissOffsetY = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;

    if (track == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceRaised,
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: const Icon(
                  Icons.music_note_rounded,
                  size: 40,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Выберите трек, чтобы начать',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: AnimatedContainer(
          duration: _dismissOffsetY == 0
              ? const Duration(milliseconds: 200)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _dismissOffsetY, 0),
          child: AmbientArtworkBackground(
            artworkUrl: track.artworkUrl,
            animate: player.isPlaying,
            child: SafeArea(
              child: Column(
                children: [
                  _TopBar(track: track),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Column(
                        children: [
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: AppDurations.normal,
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: switch (_mode) {
                                _PlayerMode.artwork => _ArtworkStage(
                                    key: const ValueKey('artwork'),
                                    track: track,
                                    player: player,
                                  ),
                                _PlayerMode.lyrics => _EmbeddedLyricsStage(
                                    key: ValueKey('lyrics-${track.id}'),
                                    track: track,
                                  ),
                                _PlayerMode.queue => _EmbeddedQueueStage(
                                    key: const ValueKey('queue'),
                                    track: track,
                                    player: player,
                                  ),
                              },
                            ),
                          ),
                          if (_mode == _PlayerMode.artwork) ...[
                            const SizedBox(height: 12),
                            _TrackMetaRow(track: track, player: player),
                          ],
                          const SizedBox(height: 12),
                          _ElasticSeekBar(player: player, track: track),
                          const SizedBox(height: 4),
                          _Controls(player: player),
                          const SizedBox(height: 8),
                          _BottomDock(
                            mode: _mode,
                            player: player,
                            onToggleLyrics: () =>
                                _toggleMode(_PlayerMode.lyrics),
                            onToggleQueue: () => _toggleMode(_PlayerMode.queue),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final Track track;

  const _TopBar({required this.track});

  @override
  Widget build(BuildContext context) {
    final sourceLabel = track.isLocal
        ? 'НА УСТРОЙСТВЕ'
        : track.source.label.toUpperCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: Column(
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _GlassCircleButton(
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: 'Свернуть',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Column(
                  children: [
                    const Text(
                      'СЕЙЧАС ИГРАЕТ',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: AppColors.textDim,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      sourceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.accentBright,
                      ),
                    ),
                  ],
                ),
              ),
              if (!track.isLocal) ...[
                DownloadButton(track: track),
              ],
              _GlassCircleButton(
                icon: Icons.more_horiz_rounded,
                tooltip: 'Действия с треком',
                onTap: () => showTrackMenu(context, track: track),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _GlassCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 21),
        color: AppColors.text,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Основная сцена с «дышащей» обложкой, свайпом треков и двойным тапом для лайка.
class _ArtworkStage extends StatefulWidget {
  final Track track;
  final PlayerProvider player;

  const _ArtworkStage({
    super.key,
    required this.track,
    required this.player,
  });

  @override
  State<_ArtworkStage> createState() => _ArtworkStageState();
}

class _ArtworkStageState extends State<_ArtworkStage>
    with SingleTickerProviderStateMixin {
  double _swipeDx = 0;
  bool _showHeart = false;
  Timer? _heartTimer;

  void _onDoubleTap() {
    HapticFeedback.mediumImpact();
    final library = context.read<LibraryProvider>();
    if (!library.isLiked(widget.track)) {
      library.toggleLike(widget.track);
    }
    _heartTimer?.cancel();
    setState(() => _showHeart = true);
    _heartTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!widget.player.hasQueue) return;
    setState(() {
      _swipeDx = (_swipeDx + details.delta.dx).clamp(-110.0, 110.0);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final dx = _swipeDx;
    final velocity = details.primaryVelocity ?? 0;
    setState(() => _swipeDx = 0);

    if (!widget.player.hasQueue) return;
    if (dx < -48 || velocity < -450) {
      HapticFeedback.selectionClick();
      widget.player.next();
    } else if (dx > 48 || velocity > 450) {
      HapticFeedback.selectionClick();
      widget.player.previous();
    }
  }

  @override
  void dispose() {
    _heartTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = widget.player.isPlaying;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.min(
          constraints.maxWidth - 6,
          constraints.maxHeight - 10,
        );
        final size = available.clamp(1.0, 420.0).toDouble();

        Widget art;
        if (widget.track.artworkUrl != null &&
            widget.track.artworkUrl!.isNotEmpty) {
          art = ArtworkView(
            url: widget.track.artworkUrl,
            size: size,
            borderRadius: AppRadii.xlAll,
          );
        } else {
          art = Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: AppColors.forestHeroGradient,
              borderRadius: AppRadii.xlAll,
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.library_music_rounded,
                  size: size * 0.42,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                Text(
                  widget.track.title.isEmpty
                      ? '?'
                      : widget.track.title[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: size * 0.28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accentBright.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          );
        }

        return Center(
          child: GestureDetector(
            onDoubleTap: _onDoubleTap,
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            onHorizontalDragCancel: () => setState(() => _swipeDx = 0),
            child: AnimatedScale(
              scale: playing ? 1.0 : 0.86,
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: _swipeDx == 0
                    ? const Duration(milliseconds: 260)
                    : Duration.zero,
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(_swipeDx, 0, 0),
                decoration: BoxDecoration(
                  borderRadius: AppRadii.xlAll,
                  boxShadow: playing
                      ? AppShadows.artwork
                      : AppShadows.artworkPaused,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: playing ? 0.16 : 0.08),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Hero(
                      tag: FullPlayerScreen.heroTag,
                      child: art,
                    ),
                    AnimatedOpacity(
                      opacity: _showHeart ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: AnimatedScale(
                        scale: _showHeart ? 1.0 : 0.6,
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.elasticOut,
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.52),
                            border: Border.all(
                              color: AppColors.accentBright.withValues(
                                alpha: 0.45,
                              ),
                            ),
                          ),
                          child: const Icon(
                            Icons.favorite_rounded,
                            size: 42,
                            color: AppColors.accentBright,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Название трека, исполнитель и быстрые кнопки лайка и «Волны».
class _TrackMetaRow extends StatelessWidget {
  final Track track;
  final PlayerProvider player;

  const _TrackMetaRow({required this.track, required this.player});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () async {
              HapticFeedback.selectionClick();
              showAppSnackBar(
                context,
                'Собираем волну по треку «${track.title}»…',
              );
              await player.startTrackRadio(track);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _GlassCircleButton(
          icon: Icons.podcasts_rounded,
          tooltip: 'Волна по треку',
          onTap: () async {
            HapticFeedback.selectionClick();
            showAppSnackBar(context, 'Запускаем волну похожих треков…');
            await player.startTrackRadio(track);
          },
        ),
        const SizedBox(width: 8),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: LikeButton(
            track: track,
            inactiveColor: AppColors.text,
            size: 20,
          ),
        ),
      ],
    );
  }
}

/// Компактная шапка для режимов «Караоке» и «Очередь».
class _CompactHeader extends StatelessWidget {
  final Track track;
  final String badge;

  const _CompactHeader({required this.track, required this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          ArtworkView(
            size: 46,
            url: track.artworkUrl,
            borderRadius: AppRadii.smAll,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accentSoft(0.2),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.accentBright,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Встроенное караоке Apple Music с размытием глубины неактивных строк.
class _EmbeddedLyricsStage extends StatefulWidget {
  final Track track;

  const _EmbeddedLyricsStage({super.key, required this.track});

  @override
  State<_EmbeddedLyricsStage> createState() => _EmbeddedLyricsStageState();
}

class _EmbeddedLyricsStageState extends State<_EmbeddedLyricsStage> {
  late Future<Lyrics?> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<LyricsService>().fetch(widget.track);
  }

  void _retry() {
    setState(() {
      _future = context.read<LyricsService>().fetch(
        widget.track,
        refresh: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 6),
        _CompactHeader(track: widget.track, badge: 'ТЕКСТ'),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<Lyrics?>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final lyrics = snapshot.data;
              if (lyrics == null || !lyrics.hasContent) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lyrics_outlined,
                        size: 40,
                        color: AppColors.textDim,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Текст для этого трека не найден',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Повторить'),
                      ),
                    ],
                  ),
                );
              }
              if (lyrics.instrumental) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.music_off_rounded,
                        size: 40,
                        color: AppColors.textDim,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Инструментальная композиция',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                );
              }
              if (lyrics.hasSynced) {
                return _DepthSyncedLyrics(lyrics: lyrics);
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  lyrics.plainText?.trim() ?? '',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.6,
                    color: AppColors.text,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DepthSyncedLyrics extends StatefulWidget {
  final Lyrics lyrics;

  const _DepthSyncedLyrics({required this.lyrics});

  @override
  State<_DepthSyncedLyrics> createState() => _DepthSyncedLyricsState();
}

class _DepthSyncedLyricsState extends State<_DepthSyncedLyrics> {
  final ScrollController _scroll = ScrollController();
  late final List<GlobalKey> _keys;
  late final PlayerProvider _player;
  StreamSubscription<Duration>? _positionSubscription;
  int _active = -1;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
    _player = context.read<PlayerProvider>();
    _active = _indexFor(_player.handler.player.position);
    _positionSubscription = _player.handler.player.positionStream.listen(
      _onPosition,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollTo(_active);
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onPosition(Duration position) {
    final index = _indexFor(position);
    if (index == _active) return;
    setState(() => _active = index);
    _scrollTo(index);
  }

  int _indexFor(Duration position) {
    var low = 0;
    var high = widget.lyrics.lines.length - 1;
    var result = -1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      if (widget.lyrics.lines[middle].time <= position) {
        result = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return result;
  }

  void _scrollTo(int index) {
    if (index < 0 || index >= _keys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lineContext = _keys[index].currentContext;
      if (lineContext == null) return;
      unawaited(
        Scrollable.ensureVisible(
          lineContext,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          alignment: 0.34,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return ShaderMask(
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, 0.1, 0.88, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: 28),
        itemCount: widget.lyrics.lines.length,
        itemBuilder: (context, index) {
          final line = widget.lyrics.lines[index];
          final active = index == _active;
          final distance = _active < 0 ? 1 : (index - _active).abs();
          final blurSigma = disableAnimations || active
              ? 0.0
              : (distance == 1 ? 0.6 : (distance >= 2 ? 1.5 : 0.0));

          Widget textWidget = AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: active ? 23 : 18.5,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              height: 1.32,
              letterSpacing: active ? -0.4 : -0.15,
              color: active
                  ? Colors.white
                  : Colors.white.withValues(alpha: distance == 1 ? 0.48 : 0.28),
              shadows: active
                  ? [
                      Shadow(
                        color: AppColors.accentBright.withValues(alpha: 0.35),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
            ),
            child: Text(line.text),
          );

          if (blurSigma > 0) {
            textWidget = ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
              ),
              child: textWidget,
            );
          }

          return GestureDetector(
            key: _keys[index],
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              _player.seek(line.time);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: textWidget,
            ),
          );
        },
      ),
    );
  }
}

/// Встроенная очередь воспроизведения прямо внутри плеера.
class _EmbeddedQueueStage extends StatelessWidget {
  final Track track;
  final PlayerProvider player;

  const _EmbeddedQueueStage({
    super.key,
    required this.track,
    required this.player,
  });

  @override
  Widget build(BuildContext context) {
    final queue = player.queue;
    final currentIndex = player.currentIndex;

    return Column(
      children: [
        const SizedBox(height: 6),
        _CompactHeader(track: track, badge: 'ДАЛЕЕ · ${queue.length}'),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              onPressed: player.hasQueue ? player.toggleShuffle : null,
              icon: Icon(
                Icons.shuffle_rounded,
                size: 17,
                color: player.isShuffleEnabled
                    ? AppColors.accentBright
                    : AppColors.textDim,
              ),
              label: Text(
                player.isShuffleEnabled ? 'Перемешано' : 'Перемешать',
                style: TextStyle(
                  color: player.isShuffleEnabled
                      ? AppColors.accentBright
                      : AppColors.textDim,
                ),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: player.hasQueue ? player.clearQueue : null,
              icon: const Icon(Icons.clear_all_rounded, size: 17),
              label: const Text('Очистить'),
              style: TextButton.styleFrom(foregroundColor: AppColors.textDim),
            ),
          ],
        ),
        Expanded(
          child: queue.isEmpty
              ? const Center(
                  child: Text(
                    'Очередь пуста',
                    style: TextStyle(color: AppColors.textDim),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: queue.length,
                  itemBuilder: (context, index) {
                    final item = queue[index];
                    final isCurrent = index == currentIndex;
                    return ListTile(
                      onTap: () => player.playAt(index),
                      tileColor: isCurrent
                          ? AppColors.accentSoft(0.14)
                          : Colors.transparent,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadii.mdAll,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      leading: ArtworkView(
                        size: 44,
                        url: item.artworkUrl,
                        borderRadius: AppRadii.smAll,
                      ),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w600,
                          color: isCurrent
                              ? AppColors.accentBright
                              : AppColors.text,
                        ),
                      ),
                      subtitle: Text(
                        item.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textDim,
                        ),
                      ),
                      trailing: isCurrent
                          ? const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: EqualizerBars(
                                height: 15,
                                barWidth: 3,
                                gap: 2,
                              ),
                            )
                          : IconButton(
                              onPressed: () => player.removeFromQueue(index),
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: AppColors.textMuted,
                              ),
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Эластичная полоса прогресса в стиле Apple Music:
/// при захвате плавно утолщается, слева — текущее время, справа — оставшееся.
class _ElasticSeekBar extends StatelessWidget {
  final PlayerProvider player;
  final Track track;

  const _ElasticSeekBar({required this.player, required this.track});

  @override
  Widget build(BuildContext context) {
    final audioPlayer = player.handler.player;

    return StreamBuilder<Duration?>(
      stream: audioPlayer.durationStream,
      builder: (context, durationSnapshot) {
        final duration =
            durationSnapshot.data ?? audioPlayer.duration ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: audioPlayer.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            return StreamBuilder<Duration>(
              stream: audioPlayer.bufferedPositionStream,
              builder: (context, bufferedSnapshot) {
                return _ElasticValueSeekBar(
                  player: player,
                  track: track,
                  duration: duration,
                  position: position,
                  buffered: bufferedSnapshot.data ?? Duration.zero,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ElasticValueSeekBar extends StatefulWidget {
  final PlayerProvider player;
  final Track track;
  final Duration duration;
  final Duration position;
  final Duration buffered;

  const _ElasticValueSeekBar({
    required this.player,
    required this.track,
    required this.duration,
    required this.position,
    required this.buffered,
  });

  @override
  State<_ElasticValueSeekBar> createState() => _ElasticValueSeekBarState();
}

class _ElasticValueSeekBarState extends State<_ElasticValueSeekBar> {
  double? _dragValue;
  bool _dragging = false;

  double get _max => widget.duration.inMilliseconds.toDouble();

  double get _current =>
      _dragValue ?? widget.position.inMilliseconds.toDouble();

  void _setFromDx(double dx, double width) {
    if (_max <= 0 || width <= 0) return;
    final value = (dx / width).clamp(0.0, 1.0).toDouble() * _max;
    setState(() {
      _dragging = true;
      _dragValue = value;
    });
  }

  void _commit() {
    final value = _dragValue;
    if (value != null) {
      widget.player.seek(Duration(milliseconds: value.round()));
    }
    setState(() {
      _dragging = false;
      _dragValue = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final max = _max;
    final value = max > 0 ? _current.clamp(0.0, max).toDouble() : 0.0;
    final progress = max > 0 ? value / max : 0.0;
    final buffered = max > 0
        ? (widget.buffered.inMilliseconds / max).clamp(0.0, 1.0).toDouble()
        : 0.0;

    final shownPos = _dragValue == null
        ? widget.position
        : Duration(milliseconds: _dragValue!.round());
    final remainingMs = math.max(
      0,
      widget.duration.inMilliseconds - shownPos.inMilliseconds,
    );
    final remaining = Duration(milliseconds: remainingMs);

    final badgeText = widget.player.hasCustomAudioEffect
        ? (widget.player.audioPreset == AudioVibePreset.custom
            ? '${widget.player.speed.toStringAsFixed(2)}x'
            : widget.player.audioPreset.badge)
        : (widget.track.isPreview
            ? 'ПРЕВЬЮ 30С'
            : (widget.track.isLocal ? 'LOSSLESS / LOCAL' : 'HIGH QUALITY'));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: max > 0
                  ? (details) => _setFromDx(details.localPosition.dx, width)
                  : null,
              onTapUp: max > 0 ? (_) => _commit() : null,
              onHorizontalDragStart: max > 0
                  ? (details) {
                      HapticFeedback.selectionClick();
                      _setFromDx(details.localPosition.dx, width);
                    }
                  : null,
              onHorizontalDragUpdate: max > 0
                  ? (details) => _setFromDx(details.localPosition.dx, width)
                  : null,
              onHorizontalDragEnd: max > 0 ? (_) => _commit() : null,
              onHorizontalDragCancel: () => setState(() {
                _dragging = false;
                _dragValue = null;
              }),
              child: SizedBox(
                height: 30,
                width: width,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 5.0, end: _dragging ? 10.5 : 5.0),
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  builder: (context, trackHeight, _) {
                    return CustomPaint(
                      painter: _ElasticSeekPainter(
                        progress: progress,
                        buffered: buffered,
                        trackHeight: trackHeight,
                        dragging: _dragging,
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(
              formatDuration(shownPos),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: _dragging ? FontWeight.w700 : FontWeight.w600,
                color: _dragging ? AppColors.text : AppColors.textDim,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: widget.player.hasCustomAudioEffect
                    ? AppColors.accentSoft(0.22)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: Border.all(
                  color: widget.player.hasCustomAudioEffect
                      ? AppColors.accentBright.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: widget.player.hasCustomAudioEffect
                      ? AppColors.accentBright
                      : AppColors.textDim,
                ),
              ),
            ),
            const Spacer(),
            Text(
              '-${formatDuration(remaining)}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: _dragging ? FontWeight.w700 : FontWeight.w600,
                color: _dragging ? AppColors.text : AppColors.textDim,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ElasticSeekPainter extends CustomPainter {
  final double progress;
  final double buffered;
  final double trackHeight;
  final bool dragging;

  const _ElasticSeekPainter({
    required this.progress,
    required this.buffered,
    required this.trackHeight,
    required this.dragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final radius = Radius.circular(trackHeight / 2);

    final base = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, centerY - trackHeight / 2, size.width, trackHeight),
      radius,
    );
    canvas.drawRRect(
      base,
      Paint()..color = Colors.white.withValues(alpha: 0.14),
    );

    final bufferedWidth = buffered.clamp(0.0, 1.0).toDouble() * size.width;
    if (bufferedWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            0,
            centerY - trackHeight / 2,
            bufferedWidth,
            trackHeight,
          ),
          radius,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.22),
      );
    }

    final progressWidth = progress.clamp(0.0, 1.0).toDouble() * size.width;
    if (progressWidth > 0) {
      final fillRect = Rect.fromLTWH(
        0,
        centerY - trackHeight / 2,
        progressWidth,
        trackHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, radius),
        Paint()
          ..shader = LinearGradient(
            colors: dragging
                ? [AppColors.accentBright, Colors.white]
                : [AppColors.accent, AppColors.accentBright],
          ).createShader(fillRect),
      );
    }

    if (dragging) {
      final thumbX = progress.clamp(0.0, 1.0).toDouble() * size.width;
      canvas.drawCircle(
        Offset(thumbX, centerY),
        7.5,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ElasticSeekPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.buffered != buffered ||
        oldDelegate.trackHeight != trackHeight ||
        oldDelegate.dragging != dragging;
  }
}

/// Кнопки управления: shuffle / prev / play-pause / next / repeat
/// с точками активности в стиле Spotify.
class _Controls extends StatelessWidget {
  final PlayerProvider player;

  const _Controls({required this.player});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ModeIconWithDot(
          icon: Icons.shuffle_rounded,
          active: player.isShuffleEnabled,
          tooltip: 'Перемешать',
          onPressed: player.hasQueue
              ? () {
                  HapticFeedback.selectionClick();
                  player.toggleShuffle();
                }
              : null,
        ),
        IconButton(
          onPressed: player.hasQueue
              ? () {
                  HapticFeedback.lightImpact();
                  player.previous();
                }
              : null,
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: 42,
          color: AppColors.text,
          tooltip: 'Назад',
        ),
        PlayButton(
          size: 72,
          onPressed: () {
            HapticFeedback.mediumImpact();
            player.togglePlay();
          },
          isPlaying: player.isPlaying,
          isBuffering: player.isBuffering,
        ),
        IconButton(
          onPressed: player.hasQueue
              ? () {
                  HapticFeedback.lightImpact();
                  player.next();
                }
              : null,
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: 42,
          color: AppColors.text,
          tooltip: 'Вперёд',
        ),
        _ModeIconWithDot(
          icon: player.isRepeatOne
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          active: player.isRepeatAll || player.isRepeatOne,
          tooltip: player.isRepeatOne
              ? 'Повтор трека'
              : (player.isRepeatAll ? 'Повтор очереди' : 'Повтор выключен'),
          onPressed: player.hasQueue
              ? () {
                  HapticFeedback.selectionClick();
                  player.cycleRepeat();
                }
              : null,
        ),
      ],
    );
  }
}

class _ModeIconWithDot extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback? onPressed;

  const _ModeIconWithDot({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          iconSize: 24,
          color: active ? AppColors.accentBright : AppColors.textDim,
          tooltip: tooltip,
        ),
        AnimatedContainer(
          duration: AppDurations.fast,
          width: active ? 4.5 : 0,
          height: 4.5,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accentBright,
          ),
        ),
      ],
    );
  }
}

/// Нижний док Apple Music: Текст, Звучание/Скорость, Таймер сна, Очередь.
class _BottomDock extends StatelessWidget {
  final _PlayerMode mode;
  final PlayerProvider player;
  final VoidCallback onToggleLyrics;
  final VoidCallback onToggleQueue;

  const _BottomDock({
    required this.mode,
    required this.player,
    required this.onToggleLyrics,
    required this.onToggleQueue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _DockButton(
            icon: Icons.lyrics_rounded,
            label: 'Текст',
            active: mode == _PlayerMode.lyrics,
            onTap: onToggleLyrics,
          ),
          _DockButton(
            icon: Icons.graphic_eq_rounded,
            label: player.hasCustomAudioEffect
                ? '${player.speed.toStringAsFixed(2)}x'
                : 'Звук',
            active: player.hasCustomAudioEffect,
            onTap: () => showAudioEffectsSheet(context),
          ),
          ValueListenableBuilder<Duration?>(
            valueListenable: player.sleepRemainingNotifier,
            builder: (context, remaining, _) {
              final active = player.sleepEndOfTrack || remaining != null;
              final label = player.sleepEndOfTrack
                  ? 'Трек'
                  : (remaining != null ? formatDuration(remaining) : 'Сон');
              return _DockButton(
                icon: Icons.bedtime_rounded,
                label: label,
                active: active,
                onTap: () =>
                    showAudioEffectsSheet(context, focusSleepTimer: true),
              );
            },
          ),
          _DockButton(
            icon: Icons.queue_music_rounded,
            label: 'Очередь',
            active: mode == _PlayerMode.queue,
            onTap: onToggleQueue,
          ),
        ],
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _DockButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accentBright : AppColors.textDim;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.accentSoft(0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
