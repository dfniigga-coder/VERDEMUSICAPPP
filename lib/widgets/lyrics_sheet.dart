import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../data/models/lyrics.dart';
import '../data/models/track.dart';
import '../providers/player_provider.dart';
import '../services/lyrics_service.dart';

/// Открывает шторку с настоящим текстом трека из LRCLIB.
Future<void> showLyricsSheet(BuildContext context, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => LyricsSheet(track: track),
  );
}

class LyricsSheet extends StatefulWidget {
  const LyricsSheet({super.key, required this.track});

  final Track track;

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
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
    final height = MediaQuery.of(context).size.height * 0.82;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Текст песни',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.track.title} · ${widget.track.artist}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: AppTheme.textDim,
                  tooltip: 'Закрыть',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: FutureBuilder<Lyrics?>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final lyrics = snapshot.data;
                if (lyrics == null || !lyrics.hasContent) {
                  return _EmptyLyrics(onRetry: _retry);
                }
                if (lyrics.instrumental) {
                  return const _InstrumentalLyrics();
                }
                if (lyrics.hasSynced) {
                  return _SyncedLyrics(lyrics: lyrics);
                }
                return _PlainLyrics(text: lyrics.plainText ?? '');
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Текст: LRCLIB',
              style: TextStyle(fontSize: 10, color: AppTheme.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncedLyrics extends StatefulWidget {
  const _SyncedLyrics({required this.lyrics});

  final Lyrics lyrics;

  @override
  State<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends State<_SyncedLyrics> {
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
    _active = _indexFor(_player.position);
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
    int low = 0;
    int high = widget.lyrics.lines.length - 1;
    int result = -1;

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
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0.35,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      children: [
        for (var index = 0; index < widget.lyrics.lines.length; index++)
          _LyricLineView(
            key: _keys[index],
            line: widget.lyrics.lines[index],
            active: index == _active,
            onTap: () => _player.seek(widget.lyrics.lines[index].time),
          ),
      ],
    );
  }
}

class _LyricLineView extends StatelessWidget {
  const _LyricLineView({
    super.key,
    required this.line,
    required this.active,
    required this.onTap,
  });

  final LyricLine line;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          style: TextStyle(
            fontSize: active ? 21 : 17,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            height: 1.35,
            color: active ? AppTheme.accentGreen : AppTheme.textDim,
          ),
          child: Text(line.text),
        ),
      ),
    );
  }
}

class _PlainLyrics extends StatelessWidget {
  const _PlainLyrics({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Text(
        text.trim(),
        style: const TextStyle(
          fontSize: 17,
          height: 1.55,
          color: Color(0xFFE9ECEA),
        ),
      ),
    );
  }
}

class _EmptyLyrics extends StatelessWidget {
  const _EmptyLyrics({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lyrics_outlined,
              size: 42,
              color: AppTheme.textDim,
            ),
            const SizedBox(height: 12),
            const Text(
              'Текст не найден',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'LRCLIB не нашёл текст для этого трека. Попробуйте обновить.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textDim),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Обновить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstrumentalLyrics extends StatelessWidget {
  const _InstrumentalLyrics();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_off_outlined, size: 42, color: AppTheme.textDim),
          SizedBox(height: 12),
          Text(
            'Инструментальная композиция',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6),
          Text(
            'В этом треке нет слов.',
            style: TextStyle(fontSize: 13, color: AppTheme.textDim),
          ),
        ],
      ),
    );
  }
}
