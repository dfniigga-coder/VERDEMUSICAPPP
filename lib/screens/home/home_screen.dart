import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/design_tokens.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../providers/library_provider.dart';
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
import '../library/playlist_details_screen.dart';
import '../settings/settings_screen.dart';
import '../stats/vibe_stats_screen.dart';
import 'section_screen.dart';

enum _HomeFilter { all, forYou, repeat, recent }

extension on _HomeFilter {
  String get label {
    switch (this) {
      case _HomeFilter.all:
        return 'Все';
      case _HomeFilter.forYou:
        return 'Для вас';
      case _HomeFilter.repeat:
        return 'На повторе';
      case _HomeFilter.recent:
        return 'Недавние';
    }
  }
}

/// Главная в стиле Apple Music + Spotify:
/// приветствие по времени суток, чипы фильтрации, сетка 2×3 быстрого доступа,
/// editorial hero-карусель и секции рекомендаций.
class HomeScreen extends StatefulWidget {
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
  _HomeFilter _filter = _HomeFilter.all;

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

  void _playTracks(List<Track> tracks, int index, {bool shuffle = false}) {
    if (tracks.isEmpty) return;
    context.read<PlayerProvider>().playTracks(
      tracks,
      startIndex: index,
      shuffle: shuffle,
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Доброе утро';
    if (hour >= 12 && hour < 17) return 'Добрый день';
    if (hour >= 17 && hour < 23) return 'Добрый вечер';
    return 'Ночной вайб';
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final service = context.watch<RecommendationService?>();
    final recentTracks = service?.recentUniqueTracks ?? const <Track>[];
    final mostPlayed = service?.mostPlayedTracks ?? const <Track>[];

    final sections = data?.sections ?? const <RecommendationSection>[];
    final heroSections = sections.take(3).toList(growable: false);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned(
            top: -120,
            left: -80,
            right: -80,
            height: 360,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.4),
                    radius: 0.9,
                    colors: [
                      AppColors.forestMid.withValues(alpha: 0.42),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: AppColors.accentBright,
              backgroundColor: AppColors.surfaceRaised,
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _header(context)),
                  SliverToBoxAdapter(
                    child: _FilterChips(
                      selected: _filter,
                      onSelect: (f) {
                        HapticFeedback.selectionClick();
                        setState(() => _filter = f);
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _SpotifyQuickGrid(
                      onOpenLibrary: widget.onOpenLibrary,
                      onPlay: _playTracks,
                    ),
                  ),
                  if (_loading && data == null)
                    const SliverToBoxAdapter(
                      child: Column(children: [SkeletonRail(), SkeletonRail()]),
                    )
                  else if (_error != null && data == null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: ErrorView(message: _error!, onRetry: _load),
                    )
                  else if (data == null ||
                      (data.sections.isEmpty &&
                          recentTracks.isEmpty &&
                          mostPlayed.isEmpty))
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _emptyState(data?.hasTaste ?? false),
                    )
                  else ...[
                    if (_filter == _HomeFilter.all ||
                        _filter == _HomeFilter.forYou) ...[
                      if (heroSections.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _HeroCarousel(
                            sections: heroSections,
                            onPlay: _playTracks,
                          ),
                        ),
                    ],
                    if ((_filter == _HomeFilter.all ||
                            _filter == _HomeFilter.recent) &&
                        recentTracks.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _RecommendationRail(
                          section: RecommendationSection(
                            title: 'Недавно прослушано',
                            subtitle: 'Возвращайтесь к последним трекам',
                            tracks: recentTracks,
                          ),
                          onPlay: (t, i) => _playTracks(t, i),
                        ),
                      ),
                    if ((_filter == _HomeFilter.all ||
                            _filter == _HomeFilter.repeat) &&
                        mostPlayed.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _RecommendationRail(
                          section: RecommendationSection(
                            title: 'На повторе',
                            subtitle: 'Ваши самые частые треки',
                            tracks: mostPlayed,
                          ),
                          onPlay: (t, i) => _playTracks(t, i),
                        ),
                      ),
                    if (_filter == _HomeFilter.all ||
                        _filter == _HomeFilter.forYou)
                      SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final section = sections[index];
                          return _RecommendationRail(
                            section: section,
                            onPlay: (t, i) => _playTracks(t, i),
                          );
                        }, childCount: sections.length),
                      ),
                  ],
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.bottomInset),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          const VerdeLogoMark(size: 28, strokeWidth: 4.2),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                    color: AppColors.text,
                  ),
                ),
                const Text(
                  'Подобрано по вашему вкусу',
                  style: TextStyle(fontSize: 12, color: AppColors.textDim),
                ),
              ],
            ),
          ),
          _TopCircleIcon(
            icon: Icons.auto_awesome_rounded,
            tooltip: 'Мой вайб',
            accent: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const VibeStatsScreen()),
            ),
          ),
          const SizedBox(width: 8),
          _TopCircleIcon(
            icon: Icons.link_rounded,
            tooltip: 'Скачать по ссылке',
            onTap: () => showLinkDownloadSheet(context),
          ),
          const SizedBox(width: 8),
          _TopCircleIcon(
            icon: Icons.settings_outlined,
            tooltip: 'Настройки',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
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

class _TopCircleIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool accent;

  const _TopCircleIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent
            ? AppColors.accentSoft(0.2)
            : AppColors.surfaceRaised.withValues(alpha: 0.9),
        border: Border.all(
          color: accent
              ? AppColors.accentBright.withValues(alpha: 0.35)
              : AppColors.glassBorder,
        ),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 19),
        color: accent ? AppColors.accentBright : AppColors.text,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  final _HomeFilter selected;
  final ValueChanged<_HomeFilter> onSelect;

  const _FilterChips({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          for (final filter in _HomeFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PressableScale(
                child: Material(
                  color: selected == filter
                      ? AppColors.accent
                      : AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  child: InkWell(
                    onTap: () => onSelect(filter),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7.5,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(
                          color: selected == filter
                              ? AppColors.accentBright
                              : AppColors.glassBorder,
                        ),
                      ),
                      child: Text(
                        filter.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: selected == filter
                              ? Colors.black
                              : AppColors.textDim,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Компактная сетка быстрого доступа Spotify 2×3.
class _SpotifyQuickGrid extends StatelessWidget {
  final VoidCallback? onOpenLibrary;
  final void Function(List<Track>, int) onPlay;

  const _SpotifyQuickGrid({
    required this.onOpenLibrary,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final playlists = library.playlists;
    final likedCount = library.likedTracks.length;

    final tiles = <_QuickGridData>[
      _QuickGridData(
        title: 'Понравившиеся',
        subtitle: likedCount > 0 ? '$likedCount треков' : 'Избранное',
        icon: Icons.favorite_rounded,
        gradient: const [Color(0xFF9E2646), Color(0xFF42101D)],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const LikedTracksScreen()),
        ),
      ),
      _QuickGridData(
        title: 'Мои треки',
        subtitle: 'С устройства',
        icon: Icons.folder_rounded,
        gradient: const [Color(0xFF1F4E7A), Color(0xFF0E2236)],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const LocalTracksScreen()),
        ),
      ),
      _QuickGridData(
        title: 'Мой вайб',
        subtitle: 'Статистика',
        icon: Icons.auto_awesome_rounded,
        gradient: const [Color(0xFF0F6B3A), Color(0xFF072B17)],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const VibeStatsScreen()),
        ),
      ),
      for (final Playlist playlist in playlists.take(2))
        _QuickGridData(
          title: playlist.name,
          subtitle: '${playlist.trackCount} треков',
          icon: Icons.queue_music_rounded,
          artworkUrl: playlist.tracks.isNotEmpty
              ? playlist.tracks.first.artworkUrl
              : null,
          gradient: const [Color(0xFF1A2B22), Color(0xFF101914)],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PlaylistDetailsScreen(playlistId: playlist.id),
            ),
          ),
        ),
      _QuickGridData(
        title: playlists.isEmpty ? 'Плейлисты' : 'Скачать MP3',
        subtitle: playlists.isEmpty ? 'Медиатека' : 'По ссылке YT',
        icon: playlists.isEmpty
            ? Icons.library_music_rounded
            : Icons.link_rounded,
        gradient: const [Color(0xFF4A3615), Color(0xFF1E1608)],
        onTap: playlists.isEmpty
            ? onOpenLibrary
            : () => showLinkDownloadSheet(context),
      ),
    ];

    // Гарантируем чётное количество элементов (до 6).
    final visible = tiles.take(6).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in visible)
                SizedBox(
                  width: itemWidth,
                  child: _SpotifyQuickTile(data: item),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _QuickGridData {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final String? artworkUrl;
  final VoidCallback? onTap;

  const _QuickGridData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    this.artworkUrl,
    this.onTap,
  });
}

class _SpotifyQuickTile extends StatelessWidget {
  final _QuickGridData data;

  const _SpotifyQuickTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: data.onTap,
      borderRadius: AppRadii.mdAll,
      color: AppColors.surfaceRaised,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            if (data.artworkUrl != null)
              ArtworkView(
                size: 54,
                url: data.artworkUrl,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppRadii.md),
                  bottomLeft: Radius.circular(AppRadii.md),
                ),
              )
            else
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: data.gradient,
                  ),
                ),
                child: Icon(data.icon, size: 22, color: Colors.white),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      data.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Карусель editorial hero-карточек в стиле Apple Music.
class _HeroCarousel extends StatefulWidget {
  final List<RecommendationSection> sections;
  final void Function(List<Track>, int, {bool shuffle}) onPlay;

  const _HeroCarousel({required this.sections, required this.onPlay});

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  late final PageController _pageController;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.92);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.sections.where((s) => s.tracks.isNotEmpty).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: 16),
        SizedBox(
          height: 204,
          child: PageView.builder(
            controller: _pageController,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _HeroCard(
                  section: items[index],
                  tag: index == 0 ? 'МИКС ДНЯ · ДЛЯ ВАС' : 'ПОДБОРКА VERDE',
                  onPlay: widget.onPlay,
                ),
              );
            },
          ),
        ),
        if (items.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < items.length; i++)
                AnimatedContainer(
                  duration: AppDurations.fast,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _page == i ? 18 : 6,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _page == i
                        ? AppColors.accentBright
                        : AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final RecommendationSection section;
  final String tag;
  final void Function(List<Track>, int, {bool shuffle}) onPlay;

  const _HeroCard({
    required this.section,
    required this.tag,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final tracks = section.tracks;
    final hero = tracks.first;
    final firstFull = tracks.indexWhere((track) => !track.isPreview);
    final startIdx = firstFull < 0 ? 0 : firstFull;

    return PressableScale(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadii.xlAll,
          boxShadow: AppShadows.card,
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: AppRadii.xlAll,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onPlay(tracks, startIdx),
            borderRadius: AppRadii.xlAll,
            child: ArtworkBackdrop(
              url: hero.artworkUrl,
              blur: 32,
              overlayColor: AppColors.forestDark.withValues(alpha: 0.48),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.forestMid.withValues(alpha: 0.25),
                  AppColors.background.withValues(alpha: 0.9),
                ],
              ),
              borderRadius: AppRadii.xlAll,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft(0.24),
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            border: Border.all(
                              color: AppColors.accentBright.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: AppColors.accentBright,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: AppRadii.smAll,
                            boxShadow: AppShadows.card,
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: ArtworkView(
                            size: 56,
                            url: hero.artworkUrl,
                            borderRadius: AppRadii.smAll,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      section.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${hero.artist} и ещё ${tracks.length} треков',
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
                          size: 42,
                          onPressed: () => onPlay(tracks, startIdx),
                          isPlaying: false,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Слушать',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () =>
                              onPlay(tracks, startIdx, shuffle: true),
                          icon: const Icon(Icons.shuffle_rounded, size: 20),
                          color: AppColors.text,
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.1),
                            shape: const CircleBorder(),
                          ),
                          tooltip: 'Перемешать',
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
    );
  }
}

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
