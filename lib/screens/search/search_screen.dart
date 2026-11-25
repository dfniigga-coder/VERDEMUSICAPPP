import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/design_tokens.dart';
import '../../data/models/track.dart';
import '../../providers/player_provider.dart';
import '../../providers/search_provider.dart';
import '../../services/youtube_link.dart';
import '../../widgets/app_card.dart';
import '../../widgets/common.dart';
import '../../widgets/download_sheet.dart';
import '../../widgets/full_track_button.dart';
import '../../widgets/link_download_sheet.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/track_menu.dart';
import '../../widgets/track_tile.dart';

/// Мультиисточниковый поиск: Deezer, iTunes, Audius, Jamendo, Archive, YouTube.
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
    // Ссылку с YouTube Music в текстовый поиск не отправляем: её
    // обрабатывает лист «ссылка → MP3».
    if (YoutubeLink.parse(query) != null) {
      context.read<SearchProvider>().search('');
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 250), () {
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
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _submit(query);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SearchProvider>();
    final query = _controller.text.trim();
    final isLink = YoutubeLink.parse(query) != null;
    final hasQuery = query.isNotEmpty && !isLink;

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
                  hintText: 'Треки, исполнители, ссылки…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 21),
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
            if (hasQuery) _FilterBar(provider: provider),
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Поиск', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 4),
          const Text(
            'Deezer · iTunes · Audius · Jamendo · Archive · YouTube',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
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
      return _RecentSearches(onPick: _pickQuery);
    }
    final results = provider.visibleResults;
    if (results.isEmpty && provider.loading) {
      return const LoadingView(message: 'Ищем ещё источники…');
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

/// Подсказка, когда в поисковую строку вставлена ссылка YouTube.
class _LinkHint extends StatelessWidget {
  final VoidCallback onTap;

  const _LinkHint({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: AppCard(
        onTap: onTap,
        color: AppColors.accentSoft(0.12),
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
                'Ссылка распознана — скачать трек в MP3?',
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

/// Чипы фильтра: все треки, только полные, только превью.
class _FilterBar extends StatelessWidget {
  final SearchProvider provider;

  const _FilterBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          for (final filter in SearchFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(filter.label),
                selected: provider.filter == filter,
                showCheckmark: false,
                selectedColor: AppColors.accentSoft(0.2),
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: provider.filter == filter
                      ? AppColors.accentBright
                      : AppColors.textDim,
                ),
                onSelected: (_) =>
                    context.read<SearchProvider>().setFilter(filter),
              ),
            ),
        ],
      ),
    );
  }
}

/// Список результатов поиска.
class _ResultsList extends StatelessWidget {
  final List<Track> results;

  final void Function(List<Track>, int) onPlay;

  const _ResultsList({required this.results, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.bottomInset),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final track = results[index];
        return TrackTile(
          track: track,
          onTap: () => onPlay(results, index),
          onLongPress: () => showTrackMenu(context, track: track),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (track.isPreview) FullTrackButton(track: track),
              DownloadButton(track: track),
              LikeButton(track: track),
            ],
          ),
        );
      },
    );
  }
}

/// Недавние поиски и подсказки, когда запроса ещё нет.
class _RecentSearches extends StatelessWidget {
  final void Function(String) onPick;

  const _RecentSearches({required this.onPick});

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
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
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
                    color: AppColors.text,
                  ),
                  backgroundColor: AppColors.surfaceRaised,
                  side: const BorderSide(color: AppColors.stroke),
                  avatar: const Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  onPressed: () => onPick(q),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        _LinkCta(onTap: () => showLinkDownloadSheet(context)),
        const SizedBox(height: 24),
        const Text(
          'Источники',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 10),
        _SourceGrid(),
        const SizedBox(height: 24),
        const Text(
          'Попробуйте',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final query in _popularQueries)
              ActionChip(
                label: Text(query),
                labelStyle: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.text,
                ),
                backgroundColor: AppColors.surfaceRaised,
                side: const BorderSide(color: AppColors.stroke),
                onPressed: () => onPick(query),
              ),
          ],
        ),
      ],
    );
  }
}

const List<String> _popularQueries = [
  'Lo-fi',
  'Рэп',
  'Рок',
  'Электроника',
  'Джаз',
  'Классика',
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
        colors: [AppColors.accentSoft(0.2), AppColors.surfaceRaised],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: 0.18),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Вставьте ссылку — Verde сохранит MP3',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textDim),
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

class _SourceGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final source in _sources)
              SizedBox(
                width: width,
                child: AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  borderRadius: AppRadii.mdAll,
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: source.color.withValues(alpha: 0.14),
                        ),
                        child: Icon(source.icon, size: 17, color: source.color),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              source.name,
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
                              source.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SourceInfo {
  final String name;

  final String subtitle;

  final IconData icon;

  final Color color;

  const _SourceInfo(this.name, this.subtitle, this.icon, this.color);
}

const List<_SourceInfo> _sources = [
  _SourceInfo(
    'Deezer',
    'Превью 30 секунд',
    Icons.graphic_eq_rounded,
    Color(0xFFB06BFF),
  ),
  _SourceInfo(
    'iTunes',
    'Превью 30 секунд',
    Icons.music_note_rounded,
    Color(0xFFFF6B81),
  ),
  _SourceInfo('Audius', 'Полные треки', Icons.waves_rounded, Color(0xFFCC6BFF)),
  _SourceInfo(
    'Jamendo',
    'Полные треки',
    Icons.public_rounded,
    Color(0xFFFFB35C),
  ),
  _SourceInfo(
    'Archive',
    'Полные треки',
    Icons.account_balance_rounded,
    Color(0xFF6FA8FF),
  ),
  _SourceInfo(
    'YouTube',
    'Полные треки и MP3',
    Icons.smart_display_rounded,
    Color(0xFFFF6B6B),
  ),
];
