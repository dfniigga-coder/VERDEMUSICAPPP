import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/track.dart';
import '../../providers/player_provider.dart';
import '../../providers/search_provider.dart';
import '../../services/youtube_link.dart';
import '../../widgets/common.dart';
import '../../widgets/download_sheet.dart';
import '../../widgets/full_track_button.dart';
import '../../widgets/link_download_sheet.dart';
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                onSubmitted: _submit,
                decoration: InputDecoration(
                  hintText: 'Треки, исполнители…',
                  prefixIcon: const Icon(Icons.search),
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
                          icon: const Icon(Icons.close, size: 20),
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

  Widget _body(SearchProvider provider) {
    if (provider.loading && provider.results == null) {
      return const LoadingView(message: 'Ищем во всех источниках…');
    }
    if (provider.error != null) {
      return ErrorView(
        message: provider.error!,
        onRetry: () => _submit(provider.lastQuery),
      );
    }
    if (provider.showRecent) {
      return _RecentSearches(
        onPick: (q) {
          _controller.text = q;
          _submit(q);
        },
      );
    }
    final results = provider.visibleResults;
    if (results.isEmpty && provider.loading) {
      return const LoadingView(message: 'Ищем ещё источники…');
    }
    if (results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
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
      child: Material(
        color: AppTheme.accentGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.music_video_outlined,
                  size: 20,
                  color: AppTheme.accentGreen,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ссылка распознана — скачать трек в MP3?',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: AppTheme.textDim),
              ],
            ),
          ),
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
                selectedColor: AppTheme.accentGreen.withValues(alpha: 0.18),
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
      padding: const EdgeInsets.only(bottom: 110),
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

/// Недавние поиски (чипсы).
class _RecentSearches extends StatelessWidget {
  final void Function(String) onPick;

  const _RecentSearches({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SearchProvider>();
    final recent = provider.recentSearches;

    if (recent.isEmpty) {
      return const EmptyState(
        icon: Icons.tips_and_updates_outlined,
        title: 'Что послушаем?',
        subtitle:
            'Deezer, iTunes, Audius, Jamendo, Internet Archive и YouTube — '
            'в одном поиске',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Text(
              'Недавние запросы',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const Spacer(),
            TextButton(
              onPressed: provider.clearRecentSearches,
              child: const Text('Очистить'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in recent)
              ActionChip(
                label: Text(q),
                labelStyle: const TextStyle(fontSize: 13),
                backgroundColor: AppTheme.surfaceContainer,
                side: BorderSide.none,
                onPressed: () => onPick(q),
              ),
          ],
        ),
      ],
    );
  }
}
