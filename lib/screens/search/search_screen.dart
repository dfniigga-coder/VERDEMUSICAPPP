import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/track.dart';
import '../../providers/player_provider.dart';
import '../../providers/search_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/track_tile.dart';

/// Поиск по трекам Audius (название и исполнитель).
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
    if (query.isEmpty) {
      context.read<SearchProvider>().search('');
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      context.read<SearchProvider>().search(query);
    });
  }

  void _submit(String query) {
    _debounce?.cancel();
    final provider = context.read<SearchProvider>();
    provider.search(query);
    if (query.trim().isNotEmpty) {
      provider.saveRecent(query);
    }
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SearchProvider>();

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
                      ? null
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
            Expanded(child: _body(provider)),
          ],
        ),
      ),
    );
  }

  Widget _body(SearchProvider provider) {
    if (provider.loading && (provider.results == null)) {
      return const LoadingView('Ищем…');
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
    if (!provider.hasResults) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'Ничего не нашлось',
        subtitle: 'Попробуйте другой запрос',
      );
    }
    return _ResultsList(
      results: provider.results!,
      onPlay: (tracks, index) {
        context.read<PlayerProvider>().playTracks(tracks, startIndex: index);
      },
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
          trailing: LikeButton(track: track),
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
        subtitle: 'Поиск по трекам Audius — бесплатные официальные релизы',
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
