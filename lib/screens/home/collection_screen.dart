import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/collection.dart';
import '../../data/models/track.dart';
import '../../data/repositories/music_repository.dart';
import '../../providers/player_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/artwork.dart';
import '../../widgets/common.dart';
import '../../widgets/track_tile.dart';

/// Содержимое подборки Audius (плейлист из раздела «Подборки»).
class CollectionScreen extends StatefulWidget {
  final Collection collection;

  const CollectionScreen({super.key, required this.collection});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  List<Track>? _tracks;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = context.read<MusicRepository>();
    try {
      final tracks = await repo.playlistTracks(widget.collection);
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить подборку. Попробуйте ещё раз.';
        _loading = false;
      });
    }
  }

  void _play(List<Track> tracks, int index) {
    context.read<PlayerProvider>().playTracks(tracks, startIndex: index);
  }

  void _playTracksShuffled(List<Track> tracks) {
    if (tracks.isEmpty) return;
    final index = DateTime.now().millisecondsSinceEpoch ~/ 1000 % tracks.length;
    context.read<PlayerProvider>().playTracks(
      tracks,
      startIndex: index,
      shuffle: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    return Scaffold(
      appBar: AppBar(title: const Text('Подборка')),
      body: _buildBody(collection),
    );
  }

  Widget _buildBody(Collection collection) {
    if (_loading && _tracks == null) {
      return const LoadingView(message: 'Загружаем подборку…');
    }
    if (_error != null && _tracks == null) {
      return ErrorView(message: _error!, onRetry: _load);
    }

    final tracks = _tracks ?? const <Track>[];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, AppSpacing.pageBottom),
      itemCount: tracks.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _header(collection, tracks);
        }
        final track = tracks[index - 1];
        final trackIndex = index - 1;
        return TrackTile(
          track: track,
          onTap: () => _play(tracks, trackIndex),
          trailing: LikeButton(track: track),
        );
      },
    );
  }

  Widget _header(Collection collection, List<Track> tracks) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: AppCard(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accentDeep.withValues(alpha: 0.5),
            AppColors.surfaceRaised,
          ],
        ),
        borderRadius: AppRadii.xlAll,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ArtworkView(
              size: 112,
              url: collection.artworkUrl,
              borderRadius: AppRadii.mdAll,
              placeholderIcon: Icons.queue_music_rounded,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ПОДБОРКА',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: AppColors.accentBright,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    collection.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      height: 1.2,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    trackCountLabel(tracks.length),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textDim,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: tracks.isEmpty
                            ? null
                            : () => _play(tracks, 0),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('Слушать'),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: tracks.isEmpty
                            ? null
                            : () => _playTracksShuffled(tracks),
                        icon: const Icon(Icons.shuffle_rounded, size: 20),
                        color: AppColors.text,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          shape: const CircleBorder(),
                        ),
                        tooltip: 'Перемешать',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
