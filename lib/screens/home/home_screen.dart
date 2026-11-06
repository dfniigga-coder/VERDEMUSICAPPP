import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/collection.dart';
import '../../data/models/track.dart';
import '../../data/repositories/music_repository.dart';
import '../../providers/player_provider.dart';
import '../../widgets/artwork.dart';
import '../../widgets/common.dart';
import 'collection_screen.dart';

/// Главная: популярные треки, андеграунд и подборки Audius.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeData? _data;
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
      final data = await repo.loadHome();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Что-то пошло не так. Потяните вниз, чтобы обновить.';
        _loading = false;
      });
    }
  }

  void _playTracks(List<Track> tracks, int index) {
    if (tracks.isEmpty) return;
    context.read<PlayerProvider>().playTracks(tracks, startIndex: index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        color: AppTheme.accentGreen,
        backgroundColor: AppTheme.surfaceContainer,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _header(),
            if (_loading && _data == null)
              const SliverFillRemaining(
                child: LoadingView(message: 'Загружаем музыку…'),
              )
            else if (_error != null && _data == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorView(message: _error!, onRetry: _load),
              )
            else ..._buildSections(),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _header() {
    final cached = _data?.isCached ?? false;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verde',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Лучшее с Audius прямо сейчас',
              style: const TextStyle(color: AppTheme.textDim, fontSize: 14),
            ),
            if (cached) ...[
              const SizedBox(height: 8),
              const _OfflineBadge(),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSections() {
    final data = _data!;
    final sections = <Widget>[];

    if (data.trending.isNotEmpty) {
      sections.add(const SectionHeader(
        title: 'Популярное сейчас',
        subtitle: 'Тренды Audius за неделю',
      ));
      sections.add(_TrackRail(
        tracks: data.trending,
        onPlay: _playTracks,
      ));
    }

    if (data.underground.isNotEmpty) {
      sections.add(const SectionHeader(
        title: 'Андеграунд',
        subtitle: 'Свежее из инди-сообщества Audius',
      ));
      sections.add(_TrackRail(
        tracks: data.underground,
        onPlay: _playTracks,
      ));
    }

    if (data.playlists.isNotEmpty) {
      sections.add(const SectionHeader(
        title: 'Подборки',
        subtitle: 'Трендовые плейлисты Audius',
      ));
      sections.add(_CollectionRail(collections: data.playlists));
    }

    if (sections.isEmpty) {
      sections.add(
        const SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.music_off_outlined,
            title: 'Здесь пока пусто',
            subtitle: 'Потяните вниз, чтобы обновить подборки',
          ),
        ),
      );
    }

    return sections;
  }
}

/// Плашка «данные из кэша».
class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.wifi_off, size: 14, color: AppTheme.textDim),
          SizedBox(width: 6),
          Text(
            'Показаны сохранённые данные',
            style: TextStyle(color: AppTheme.textDim, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Горизонтальная лента треков.
class _TrackRail extends StatelessWidget {
  final List<Track> tracks;

  final void Function(List<Track>, int) onPlay;

  const _TrackRail({required this.tracks, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: tracks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final track = tracks[index];
          return _TrackCard(
            track: track,
            onTap: () => onPlay(tracks, index),
          );
        },
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  final Track track;

  final VoidCallback onTap;

  const _TrackCard({required this.track, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ArtworkView(
              size: 140,
              url: track.artworkUrl,
              borderRadius: const BorderRadius.all(Radius.circular(14)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textDim,
                      fontSize: 12,
                    ),
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

/// Горизонтальная лента подборок (плейлисты Audius).
class _CollectionRail extends StatelessWidget {
  final List<Collection> collections;

  const _CollectionRail({required this.collections});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: collections.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final collection = collections[index];
          return _CollectionCard(collection: collection);
        },
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  final Collection collection;

  const _CollectionCard({required this.collection});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CollectionScreen(collection: collection),
          ),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ArtworkView(
              size: 150,
              url: collection.artworkUrl,
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              placeholderIcon: Icons.queue_music,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                collection.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
