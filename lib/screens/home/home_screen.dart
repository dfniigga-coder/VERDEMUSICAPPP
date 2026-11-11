import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/track.dart';
import '../../providers/player_provider.dart';
import '../../services/recommendation_service.dart';
import '../../widgets/common.dart';
import '../../widgets/track_card.dart';

/// Главная в стиле YouTube Music: горизонтальные секции рекомендаций.
///
/// [RecommendationService] берёт несколько песен пользователя как семена и
/// подбирает к ним похожие треки. Если Last.fm или поиск недоступны,
/// соответствующие секции просто не показываются.
class HomeScreen extends StatefulWidget {
  /// RootShell передаёт true, когда вкладка «Главная» выбрана.
  final bool isActive;

  const HomeScreen({super.key, this.isActive = true});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeRecommendations? _data;
  bool _loading = true;
  String? _error;
  int _loadedRevision = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive || _loading) return;

    final service = context.read<RecommendationService>();
    if (service.revision != _loadedRevision) {
      _load();
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final service = context.read<RecommendationService>();
    try {
      final data = await service.loadHome();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _loadedRevision = service.revision;
      });
    } catch (error) {
      debugPrint('[HomeScreen] recommendations: $error');
      if (!mounted) return;
      setState(() {
        _error =
            'Не удалось собрать рекомендации. Потяните вниз, чтобы повторить.';
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
    final data = _data;

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
            if (_loading && data == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: LoadingView(message: 'Собираем рекомендации…'),
              )
            else if (_error != null && data == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorView(message: _error!, onRetry: _load),
              )
            else if (data == null || data.sections.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _emptyState(data?.hasTaste ?? false),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final section = data.sections[index];
                  return _RecommendationRail(
                    section: section,
                    onPlay: _playTracks,
                  );
                }, childCount: data.sections.length),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _header() {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verde',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'На основе вашей музыки',
              style: TextStyle(color: AppTheme.textDim, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(bool hasTaste) {
    return EmptyState(
      icon: Icons.headphones_outlined,
      title: 'Слушайте музыку, чтобы получить рекомендации',
      subtitle: hasTaste
          ? 'Мы уже собираем подборки — потяните вниз, чтобы обновить.'
          : 'История прослушиваний, лайки, плейлисты и локальная '
                'библиотека помогут подобрать треки.',
    );
  }
}

/// Секция: заголовок + «Играть все» + горизонтальная лента карточек.
class _RecommendationRail extends StatelessWidget {
  final RecommendationSection section;
  final void Function(List<Track>, int) onPlay;

  const _RecommendationRail({required this.section, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final tracks = section.tracks;
    final fullCount = tracks.where((track) => !track.isPreview).length;
    final firstFull = tracks.indexWhere((track) => !track.isPreview);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (section.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        section.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textDim,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Превью в очередь не попадают (иначе автопереход включит
              // 30-секундный фрагмент), поэтому «Играть все» показываем
              // только когда полных треков действительно несколько.
              if (fullCount >= 3)
                TextButton(
                  onPressed: () =>
                      onPlay(tracks, firstFull < 0 ? 0 : firstFull),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentGreen,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Играть все'),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 205,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: tracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return TrackCard(
                track: tracks[index],
                onTap: () => onPlay(tracks, index),
              );
            },
          ),
        ),
      ],
    );
  }
}
