import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../data/repositories/local_tracks_repository.dart';
import '../../data/repositories/music_repository.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/artwork.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/track_menu.dart';
import '../../widgets/track_tile.dart';

/// Детальный экран плейлиста: воспроизведение, шаффл, добавление треков,
/// переименование/удаление, удаление треков из плейлиста.
class PlaylistDetailsScreen extends StatelessWidget {
  final String playlistId;

  const PlaylistDetailsScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final playlist = library.playlistById(playlistId);

    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Плейлист')),
        body: const EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Плейлист не найден',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name, maxLines: 1),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () => _showHeaderMenu(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTracks(context),
        child: const Icon(Icons.add_rounded),
      ),
      body: playlist.tracks.isEmpty
          ? EmptyState(
              icon: Icons.queue_music_rounded,
              title: 'Плейлист пуст',
              subtitle:
                  'Нажмите «+», чтобы добавить треки из поиска или '
                  'с устройства',
              action: FilledButton.icon(
                onPressed: () => _addTracks(context),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Добавить треки'),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                8,
                4,
                8,
                AppSpacing.pageBottom,
              ),
              itemCount: playlist.tracks.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return _Header(playlist: playlist);
                final track = playlist.tracks[index - 1];
                final trackIndex = index - 1;
                return TrackTile(
                  track: track,
                  onTap: () => context.read<PlayerProvider>().playTracks(
                    playlist.tracks,
                    startIndex: trackIndex,
                  ),
                  onLongPress: () => showTrackMenu(
                    context,
                    track: track,
                    onRemoved: () {
                      context.read<LibraryProvider>().removeTrackFromPlaylist(
                        playlistId,
                        track,
                      );
                      showAppSnackBar(context, 'Трек убран из плейлиста');
                    },
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 19),
                    color: AppColors.textMuted,
                    onPressed: () {
                      context.read<LibraryProvider>().removeTrackFromPlaylist(
                        playlistId,
                        track,
                      );
                      showAppSnackBar(context, 'Трек убран из плейлиста');
                    },
                    tooltip: 'Убрать из плейлиста',
                  ),
                );
              },
            ),
    );
  }

  Future<void> _showHeaderMenu(BuildContext context) async {
    final library = context.read<LibraryProvider>();
    final playlist = library.playlistById(playlistId);
    if (playlist == null) return;

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      trackCountLabel(playlist.trackCount),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('Включить плейлист'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  if (playlist.tracks.isNotEmpty) {
                    context.read<PlayerProvider>().playTracks(
                      playlist.tracks,
                      startIndex: 0,
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.shuffle_rounded),
                title: const Text('Перемешать и играть'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  if (playlist.tracks.isNotEmpty) {
                    context.read<PlayerProvider>().playTracks(
                      playlist.tracks,
                      startIndex: 0,
                      shuffle: true,
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Переименовать'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final name = await showTextDialog(
                    context,
                    title: 'Переименовать плейлист',
                    initial: playlist.name,
                  );
                  if (name == null || !context.mounted) return;
                  context.read<LibraryProvider>().renamePlaylist(
                    playlistId,
                    name,
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.deleteRed,
                ),
                title: const Text(
                  'Удалить плейлист',
                  style: TextStyle(color: AppColors.deleteRed),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final ok = await showConfirmDialog(
                    context,
                    title: 'Удалить плейлист?',
                    message: '«${playlist.name}» будет удалён безвозвратно.',
                  );
                  if (!ok || !context.mounted) return;
                  context.read<LibraryProvider>().deletePlaylist(playlistId);
                  Navigator.of(context).pop();
                  showAppSnackBar(context, 'Плейлист удалён');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addTracks(BuildContext context) async {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddTracksSheet(playlistId: playlistId),
    );
  }
}

/// Шапка плейлиста: мозаичная обложка, название, счётчик и действия.
class _Header extends StatelessWidget {
  final Playlist playlist;

  const _Header({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final tracks = playlist.tracks;
    final firstArtwork = tracks.isEmpty ? null : tracks.first.artworkUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: AppCard(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accentDeep.withValues(alpha: 0.55),
            AppColors.surfaceRaised,
          ],
        ),
        borderRadius: AppRadii.xlAll,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ArtworkView(
              size: 108,
              url: firstArtwork,
              borderRadius: AppRadii.mdAll,
              placeholderIcon: Icons.queue_music_rounded,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ПЛЕЙЛИСТ',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: AppColors.accentBright,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    playlist.name,
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
                        onPressed: () => context
                            .read<PlayerProvider>()
                            .playTracks(tracks, startIndex: 0),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('Слушать'),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => context
                            .read<PlayerProvider>()
                            .playTracks(tracks, startIndex: 0, shuffle: true),
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

/// Добавление треков: поиск по Audius или треки с устройства.
class _AddTracksSheet extends StatefulWidget {
  final String playlistId;

  const _AddTracksSheet({required this.playlistId});

  @override
  State<_AddTracksSheet> createState() => _AddTracksSheetState();
}

class _AddTracksSheetState extends State<_AddTracksSheet> {
  int _sourceIndex = 0; // 0 — онлайн, 1 — локальные
  Timer? _debounce;
  String _query = '';
  String? _error;
  bool _loading = false;
  List<Track> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _searchOnline(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final repo = context.read<MusicRepository>();
      final tracks = await repo.search(q);
      if (!mounted) return;
      setState(() {
        _results = tracks;
        _error = null;
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
        _error = 'Не удалось выполнить поиск.';
        _loading = false;
      });
    }
  }

  Future<void> _loadLocal() async {
    setState(() => _loading = true);
    final repo = context.read<LocalTracksRepository>();
    try {
      final result = await repo.loadTracks();
      if (!mounted) return;
      setState(() {
        _results = result.hasPermission ? result.tracks : const [];
        _error = result.hasPermission ? null : 'Нет доступа к аудиофайлам';
        _loading = false;
      });
    } catch (error) {
      debugPrint('PlaylistDetails: local tracks failed: $error');
      if (!mounted) return;
      setState(() {
        _results = const [];
        _error = 'Не удалось прочитать файлы на устройстве.';
        _loading = false;
      });
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _query = value;
    if (_sourceIndex != 0) return;
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _searchOnline(_query);
    });
  }

  Future<void> _add(Track track) async {
    final messenger = ScaffoldMessenger.of(context);
    final added = context.read<LibraryProvider>().addTrackToPlaylist(
      widget.playlistId,
      track,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(added ? 'Добавлено в плейлист' : 'Трек уже в плейлисте'),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.82,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.stroke,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Добавить треки',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: AppColors.textDim,
                  tooltip: 'Закрыть',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.cloud_outlined, size: 18),
                  label: Text('Онлайн'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.smartphone_rounded, size: 18),
                  label: Text('Телефон'),
                ),
              ],
              selected: {_sourceIndex},
              onSelectionChanged: (selection) {
                setState(() {
                  _sourceIndex = selection.first;
                  _results = const [];
                  _error = null;
                  _query = '';
                  if (_sourceIndex == 1) _loadLocal();
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: TextField(
              onChanged: _onQueryChanged,
              onSubmitted: (_) =>
                  _sourceIndex == 0 ? _searchOnline(_query) : null,
              decoration: InputDecoration(
                hintText: _sourceIndex == 0
                    ? 'Поиск по трекам Audius'
                    : 'Фильтр по названию',
                prefixIcon: const Icon(Icons.search_rounded, size: 21),
              ),
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const LoadingView();
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textDim),
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _query.isEmpty
                ? 'Наберите запрос, чтобы найти треки'
                : 'Ничего не нашлось',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textDim),
          ),
        ),
      );
    }

    final library = context.watch<LibraryProvider>();
    final playlist = library.playlistById(widget.playlistId);
    final inPlaylist = <String>{
      for (final t in playlist?.tracks ?? const <Track>[]) t.id,
    };

    // Локальные треки дополнительно фильтруем по введённому тексту.
    final visible = _sourceIndex == 1 && _query.isNotEmpty
        ? _results
              .where(
                (t) =>
                    t.title.toLowerCase().contains(_query.trim().toLowerCase()),
              )
              .toList()
        : _results;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final track = visible[index];
        final added = inPlaylist.contains(track.id);
        return ListTile(
          onTap: added ? null : () => _add(track),
          leading: ArtworkView(
            size: 44,
            url: track.artworkUrl,
            borderRadius: AppRadii.smAll,
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
          trailing: added
              ? const Icon(Icons.check_rounded, color: AppColors.accentBright)
              : const Icon(
                  Icons.playlist_add_rounded,
                  color: AppColors.textMuted,
                ),
        );
      },
    );
  }
}
