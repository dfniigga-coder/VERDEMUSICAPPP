import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/track.dart';
import '../../data/repositories/music_repository.dart';
import '../../providers/library_provider.dart';
import '../../data/repositories/local_tracks_repository.dart';
import '../../providers/player_provider.dart';
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
          icon: Icons.error_outline,
          title: 'Плейлист не найден',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name, maxLines: 1),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showHeaderMenu(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTracks(context),
        child: const Icon(Icons.add),
      ),
      body: playlist.tracks.isEmpty
          ? EmptyState(
              icon: Icons.queue_music_outlined,
              title: 'Плейлист пуст',
              subtitle: 'Нажмите «+», чтобы добавить треки из поиска или '
                  'с устройства',
              action: FilledButton.icon(
                onPressed: () => _addTracks(context),
                icon: const Icon(Icons.add),
                label: const Text('Добавить треки'),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 110),
              itemCount: playlist.tracks.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _Header(playlistName: playlist.name,
                      trackCount: playlist.trackCount);
                }
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
                      context
                          .read<LibraryProvider>()
                          .removeTrackFromPlaylist(playlistId, track);
                      showAppSnackBar(
                        context,
                        'Трек убран из плейлиста',
                      );
                    },
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: AppTheme.textDim,
                    onPressed: () {
                      context
                          .read<LibraryProvider>()
                          .removeTrackFromPlaylist(playlistId, track);
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
                leading: const Icon(Icons.shuffle),
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
                  Icons.delete_outline,
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
                    message:
                        '«${playlist.name}» будет удалён безвозвратно.',
                  );
                  if (!ok || !context.mounted) return;
                  context.read<LibraryProvider>().deletePlaylist(playlistId);
                  Navigator.of(context).pop();
                  showAppSnackBar(context, 'Плейлист удалён');
                },
              ),
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

/// Шапка плейлиста.
class _Header extends StatelessWidget {
  final String playlistName;

  final int trackCount;

  const _Header({required this.playlistName, required this.trackCount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            playlistName,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            trackCountLabel(trackCount),
            style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
          ),
        ],
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
    } catch (e) {
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
    final result = await repo.loadTracks();
    if (!mounted) return;
    setState(() {
      _results = result.hasPermission ? result.tracks : const [];
      _error = result.hasPermission ? null : 'Нет доступа к аудиофайлам';
      _loading = false;
    });
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
    final added = context
        .read<LibraryProvider>()
        .addTrackToPlaylist(widget.playlistId, track);
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
      height: MediaQuery.of(context).size.height * 0.78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Добавить треки',
              style: Theme.of(context).textTheme.titleLarge,
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
                  icon: Icon(Icons.smartphone, size: 18),
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
                prefixIcon: const Icon(Icons.search),
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
        child: Text(
          _error!,
          style: const TextStyle(color: AppTheme.textDim),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty
              ? 'Наберите запрос, чтобы найти треки'
              : 'Ничего не нашлось',
          style: const TextStyle(color: AppTheme.textDim),
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
            .where((t) =>
                t.title.toLowerCase().contains(_query.trim().toLowerCase()))
            .toList()
        : _results;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final track = visible[index];
        final added = inPlaylist.contains(track.id);
        return ListTile(
          onTap: added ? null : () => _add(track),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
          ),
          trailing: added
              ? const Icon(Icons.check, color: AppTheme.accentGreen)
              : const Icon(Icons.playlist_add, color: AppTheme.textDim),
        );
      },
    );
  }
}
