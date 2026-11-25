import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/design_tokens.dart';
import '../../data/models/track.dart';
import '../../providers/player_provider.dart';
import '../../providers/search_provider.dart';
import '../../services/youtube_link.dart';
import '../../widgets/app_card.dart';
import '../../widgets/artwork.dart';
import '../../widgets/common.dart';
import '../../widgets/download_sheet.dart';
import '../../widgets/link_download_sheet.dart';
import '../../widgets/play_button.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/source_badge.dart';
import '../../widgets/track_menu.dart';
import '../../widgets/track_tile.dart';

/// Поиск полных треков из YouTube Music + скачивание MP3 с лирикой.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    final query = _controller.text.trim();
    if (mounted) setState(() {});

    if (query.isEmpty) {
      context.read<SearchProvider>().search('');
      return;
    }
    if (YoutubeLink.parse(query) != null) {
      context.read<SearchProvider>().search('');
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      context.read<SearchProvider>().search(query);
    });
  }

  void _submit(String query) {
    _debounce?.cancel();
    _focusNode.unfocus();

    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    if (YoutubeLink.parse(trimmed) != null) {
      unawaited(showLinkDownloadSheet(context, initialUrl: trimmed));
      return;
    }

    final provider = context.read<SearchProvider>();
    provider.search(trimmed);
    provider.saveRecent(trimmed);
  }

  void _pickQuery(String query) {
    HapticFeedback.selectionClick();
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _submit(query);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SearchProvider>();
    final query = _controller.text.trim();
    final isLink = YoutubeLink.parse(query) != null;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                onSubmitted: _submit,
                decoration: InputDecoration(
                  hintText: 'Треки, артисты, ссылки YT Music…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 22),
                  suffixIcon: _controller.text.isEmpty
                      ? IconButton(
                          onPressed: () => showLinkDownloadSheet(context),
                          tooltip: 'Скачать по ссылке с YouTube Music',
                          icon: const Icon(Icons.link_rounded, size: 21),
                        )
                      : IconButton(
                          onPressed: () {
                            _controller.clear();
                            _focusNode.requestFocus();
                          },
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                ),
              ),
            ),
            if (isLink)
              _LinkHint(
                onTap: () => showLinkDownloadSheet(context, initialUrl: query),
              ),
            if (provider.loading && provider.results != null)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _body(provider)),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Поиск', style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: 2),
                const Text(
                  'YouTube Music · Только полные треки',
                  style: TextStyle(fontSize: 12, color: AppColors.textDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(SearchProvider provider) {
    if (provider.loading && provider.results == null) {
      return ListView(
        padding: const EdgeInsets.only(top: 4),
        children: const [
          SkeletonTrackTile(),
          SkeletonTrackTile(),
          SkeletonTrackTile(),
          SkeletonTrackTile(),
          SkeletonTrackTile(),
          SkeletonTrackTile(),
        ],
      );
    }
    if (provider.error != null) {
      return ErrorView(
        message: provider.error!,
        onRetry: () => _submit(provider.lastQuery),
      );
    }
    if (provider.showRecent) {
      return _BrowseBody(onPick: _pickQuery);
    }
    final results = provider.visibleResults;
    if (results.isEmpty && provider.loading) {
      return const LoadingView(message: 'Ищем в YouTube Music…');
    }
    if (results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Ничего не найдено',
        subtitle: provider.emptySubtitle,
      );
    }
    return _ResultsList(
      results: results,
      onPlay: (tracks, index) {
        context.read<PlayerProvider>().playTracks(tracks, startIndex: index);
      },
    );
  }
}

class _LinkHint extends StatelessWidget {
  final VoidCallback onTap;

  const _LinkHint({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: AppCard(
        onTap: onTap,
        color: AppColors.accentSoft(0.14),
        borderRadius: AppRadii.mdAll,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: const Row(
          children: [
            Icon(
              Icons.music_video_rounded,
              size: 20,
              color: AppColors.accentBright,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ссылка распознана — скачать MP3 + лирику?',
                style: TextStyle(fontSize: 12.5, color: AppColors.text),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Список результатов поиска с выделенной карточкой «Лучший результат».
class _ResultsList extends StatelessWidget {
  final List<Track> results;
  final void Function(List<Track>, int) onPlay;

  const _ResultsList({required this.results, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final top = results.first;
    final showTopResult = results.length >= 2;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.bottomInset),
      itemCount: results.length + (showTopResult ? 1 : 0),
      itemBuilder: (context, index) {
        if (showTopResult && index == 0) {
          return _TopResultCard(
            track: top,
            onTap: () => onPlay(results, 0),
            onLongPress: () => showTrackMenu(context, track: top),
          );
        }
        final trackIndex = showTopResult ? index - 1 : index;
        final track = results[trackIndex];
        return TrackTile(
          track: track,
          onTap: () => onPlay(results, trackIndex),
          onLongPress: () => showTrackMenu(context, track: track),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DownloadButton(track: track),
              LikeButton(track: track),
            ],
          ),
        );
      },
    );
  }
}

class _TopResultCard extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _TopResultCard({
    required this.track,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: AppCard(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: AppRadii.xlAll,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.forestMid.withValues(alpha: 0.45),
            AppColors.surfaceRaised,
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ArtworkView(
              size: 74,
              url: track.artworkUrl,
              borderRadius: AppRadii.mdAll,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ЛУЧШИЙ РЕЗУЛЬТАТ',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: AppColors.accentBright,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.35,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textDim,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (track.source != TrackSource.local)
                    TrackSourceBadge(track: track),
                ],
              ),
            ),
            const SizedBox(width: 8),
            PlayButton(size: 46, onPressed: onTap),
          ],
        ),
      ),
    );
  }
}

/// Экран обзора в поиске: недавние, баннер ссылки, жанры и источники.
class _BrowseBody extends StatelessWidget {
  final void Function(String) onPick;

  const _BrowseBody({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SearchProvider>();
    final recent = provider.recentSearches;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, AppSpacing.bottomInset),
      children: [
        if (recent.isNotEmpty) ...[
          SectionHeader(
            title: 'Недавние запросы',
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
            action: TextButton(
              onPressed: provider.clearRecentSearches,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textDim,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Очистить'),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in recent)
                ActionChip(
                  label: Text(q),
                  labelStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                  backgroundColor: AppColors.surfaceRaised,
                  side: const BorderSide(color: AppColors.glassBorder),
                  avatar: const Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: AppColors.accentBright,
                  ),
                  onPressed: () => onPick(q),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        _LinkCta(onTap: () => showLinkDownloadSheet(context)),
        const SizedBox(height: 22),
        const Text(
          'Настроения и жанры',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final mood in _moodGenres)
                  SizedBox(
                    width: tileWidth,
                    child: _MoodTile(
                      mood: mood,
                      onTap: () => onPick(mood.query),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        const Text(
          'Источник и загрузка',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textDim,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final source in _sources)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(source.icon, size: 15, color: source.color),
                    const SizedBox(width: 6),
                    Text(
                      source.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MoodTile extends StatelessWidget {
  final _MoodGenre mood;
  final VoidCallback onTap;

  const _MoodTile({required this.mood, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      borderRadius: AppRadii.mdAll,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: mood.colors,
      ),
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 84,
        child: Stack(
          children: [
            Positioned(
              right: -10,
              bottom: -10,
              child: Transform.rotate(
                angle: 0.35,
                child: Icon(
                  mood.icon,
                  size: 62,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  mood.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.15,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoodGenre {
  final String title;
  final String query;
  final IconData icon;
  final List<Color> colors;

  const _MoodGenre(this.title, this.query, this.icon, this.colors);
}

const List<_MoodGenre> _moodGenres = [
  _MoodGenre(
    'Ночной драйв',
    'Phonk',
    Icons.directions_car_rounded,
    [Color(0xFF0E6839), Color(0xFF062916)],
  ),
  _MoodGenre(
    'Lo-Fi & Chill',
    'Lo-fi',
    Icons.nightlight_round,
    [Color(0xFF284B7A), Color(0xFF101F36)],
  ),
  _MoodGenre(
    'Хип-хоп',
    'Hip hop',
    Icons.mic_external_on_rounded,
    [Color(0xFF8C441E), Color(0xFF3A1A0A)],
  ),
  _MoodGenre(
    'Электроника',
    'Electronic',
    Icons.waves_rounded,
    [Color(0xFF5D2D82), Color(0xFF231036)],
  ),
  _MoodGenre(
    'Инди и Рок',
    'Indie rock',
    Icons.electric_bolt_rounded,
    [Color(0xFF8C243D), Color(0xFF360B16)],
  ),
  _MoodGenre(
    'Поп-хиты',
    'Pop hits',
    Icons.star_rounded,
    [Color(0xFF167C5E), Color(0xFF093226)],
  ),
  _MoodGenre(
    'Для фокуса',
    'Ambient focus',
    Icons.spa_rounded,
    [Color(0xFF2C5C4E), Color(0xFF10241E)],
  ),
  _MoodGenre(
    'Джаз и Соул',
    'Jazz soul',
    Icons.piano_rounded,
    [Color(0xFF6E5120), Color(0xFF2B1F0A)],
  ),
];

class _LinkCta extends StatelessWidget {
  final VoidCallback onTap;

  const _LinkCta({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.accentSoft(0.24), AppColors.surfaceRaised],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: 0.2),
            ),
            child: const Icon(
              Icons.link_rounded,
              color: AppColors.accentBright,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Скачать с YouTube Music',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Вставьте ссылку — Verde сохранит MP3 + лирику',
                  style: TextStyle(fontSize: 12, color: AppColors.textDim),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textMuted,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _SourceInfo {
  final String name;
  final IconData icon;
  final Color color;

  const _SourceInfo(this.name, this.icon, this.color);
}

const List<_SourceInfo> _sources = [
  _SourceInfo(
    'YouTube Music · Полные треки',
    Icons.smart_display_rounded,
    Color(0xFFFF6B6B),
  ),
  _SourceInfo(
    'LRCLIB · Лирика офлайн (.lrc)',
    Icons.lyrics_rounded,
    AppColors.accentBright,
  ),
];
