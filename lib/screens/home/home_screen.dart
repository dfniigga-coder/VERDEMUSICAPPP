import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/design_tokens.dart';
import '../../data/models/track.dart';
import '../../providers/player_provider.dart';
import '../../services/recommendation_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/artwork.dart';
import '../../widgets/common.dart';
import '../../widgets/link_download_sheet.dart';
import '../../widgets/play_button.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/track_card.dart';
import '../../widgets/verde_logo.dart';
import '../library/liked_tracks_screen.dart';
import '../library/local_tracks_screen.dart';
import 'section_screen.dart';

/// Главная в стиле YouTube Music: hero-блок, быстрый доступ и
/// горизонтальные секции рекомендаций.
///
/// [RecommendationService] берёт несколько песен пользователя как семена и
/// подбирает к ним похожие треки. Если Last.fm или поиск недоступны,
/// соответствующие секции просто не показываются.
class HomeScreen extends StatefulWidget {
  /// RootShell передаёт true, когда вкладка «Главная» выбрана.
  final bool isActive;

  final VoidCallback? onOpenLibrary;

  final VoidCallback? onOpenSearch;

  const HomeScreen({
    super.key,
    this.isActive = true,
    this.onOpenLibrary,
    this.onOpenSearch,
  });

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
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.accentBright,
          backgroundColor: AppColors.surfaceRaised,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _header()),
              if (_loading && data == null)
                const SliverToBoxAdapter(
                  child: Column(children: [SkeletonRail(), SkeletonRail()]),
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
              else ...[
                SliverToBoxAdapter(
                  child: _HeroCard(
                    section: data.sections.first,
                    onPlay: _playTracks,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _QuickAccess(onOpenLibrary: widget.onOpenLibrary),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final section = data.sections[index];
                    return _RecommendationRail(
                      section: section,
                      onPlay: _playTracks,
                    );
                  }, childCount: data.sections.length),
                ),
              ],
              const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.bottomInset),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VerdeLogo(markSize: 28, fontSize: 28),
          SizedBox(height: 6),
          Text(
            'На основе вашей музыки',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(bool hasTaste) {
    return EmptyState(
      icon: Icons.headphones_rounded,
      title: 'Слушайте музыку, чтобы получить рекомендации',
      subtitle: hasTaste
          ? 'Мы уже собираем подборки — потяните вниз, чтобы обновить.'
          : 'История прослушиваний, лайки, плейлисты и локальная '
                'библиотека помогут подобрать треки.',
      action: widget.onOpenSearch == null
          ? null
          : FilledButton.icon(
              onPressed: widget.onOpenSearch,
              icon: const Icon(Icons.search_rounded, size: 19),
              label: const Text('Открыть поиск'),
            ),
    );
  }
}

/// Hero-блок «Для вас» с большой обложкой и градиентом.
class _HeroCard extends StatelessWidget {
  final RecommendationSection section;

  final void Function(List<Track>, int) onPlay;

  const _HeroCard({required this.section, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final tracks = section.tracks;
    if (tracks.isEmpty) return const SizedBox.shrink();

    final hero = tracks.first;
    final firstFull = tracks.indexWhere((track) => !track.isPreview);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: PressableScale(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppRadii.xlAll,
            boxShadow: AppShadows.card,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: AppRadii.xlAll,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onPlay(tracks, firstFull < 0 ? 0 : firstFull),
              borderRadius: AppRadii.xlAll,
              child: ArtworkBackdrop(
                url: hero.artworkUrl,
                blur: 30,
                overlayColor: AppColors.background.withValues(alpha: 0.5),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0.15),
                    AppColors.background.withValues(alpha: 0.88),
                  ],
                ),
                borderRadius: AppRadii.xlAll,
                child: SizedBox(
                  height: 188,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft(0.22),
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            border: Border.all(
                              color: AppColors.accentBright.withValues(
                                alpha: 0.28,
                              ),
                            ),
                          ),
                          child: const Text(
                            'ДЛЯ ВАС',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: AppColors.accentBright,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          section.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1.15,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hero.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textDim,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            PlayButton(
                              size: 46,
                              onPressed: () =>
                                  onPlay(tracks, firstFull < 0 ? 0 : firstFull),
                              isPlaying: false,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Слушать подборку',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.text,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Четыре быстрых действия под hero-блоком.
class _QuickAccess extends StatelessWidget {
  final VoidCallback? onOpenLibrary;

  const _QuickAccess({this.onOpenLibrary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _QuickTile(
              icon: Icons.favorite_rounded,
              label: 'Лайки',
              color: const Color(0xFFFF6B81),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LikedTracksScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickTile(
              icon: Icons.folder_rounded,
              label: 'Мои треки',
              color: const Color(0xFF6FA8FF),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LocalTracksScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickTile(
              icon: Icons.queue_music_rounded,
              label: 'Плейлисты',
              color: AppColors.accentBright,
              onTap: onOpenLibrary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickTile(
              icon: Icons.link_rounded,
              label: 'Ссылка',
              color: const Color(0xFFFFB35C),
              onTap: () => showLinkDownloadSheet(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;

  final String label;

  final Color color;

  final VoidCallback? onTap;

  const _QuickTile({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      borderRadius: AppRadii.mdAll,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.14),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

/// Секция: заголовок + действия + горизонтальная лента карточек.
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
        SectionHeader(
          title: section.title,
          subtitle: section.subtitle,
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Превью в очередь не попадают (иначе автопереход включит
              // 30-секундный фрагмент), поэтому «Играть» показываем
              // только когда полных треков действительно несколько.
              if (fullCount >= 3)
                IconButton(
                  onPressed: () =>
                      onPlay(tracks, firstFull < 0 ? 0 : firstFull),
                  icon: const Icon(Icons.play_circle_fill_rounded),
                  iconSize: 26,
                  color: AppColors.accentBright,
                  tooltip: 'Играть все',
                  visualDensity: VisualDensity.compact,
                ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SectionTracksScreen(
                      title: section.title,
                      subtitle: section.subtitle,
                      tracks: tracks,
                    ),
                  ),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Все'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 218,
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
