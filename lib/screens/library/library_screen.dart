import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/local_tracks_repository.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';
import 'liked_tracks_screen.dart';
import 'local_tracks_screen.dart';
import 'playlist_details_screen.dart';

/// Библиотека: лайки, плейлисты, треки с устройства.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final localRepo = context.watch<LocalTracksRepository>();

    final likedCount = library.likedTracks.length;
    final localCount = localRepo.cached.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Библиотека'),
        actions: [
          IconButton(
            onPressed: () => _createPlaylist(context),
            icon: const Icon(Icons.add),
            tooltip: 'Новый плейлист',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 110),
        children: [
          LibraryTile(
            icon: Icons.favorite,
            title: 'Понравившиеся треки',
            subtitle: trackCountLabel(likedCount),
            iconColor: AppTheme.accentGreen,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LikedTracksScreen(),
              ),
            ),
          ),
          LibraryTile(
            icon: Icons.library_music,
            title: 'Треки на устройстве',
            subtitle: localCount == 0 ? 'Нажмите, чтобы загрузить' : trackCountLabel(localCount),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LocalTracksScreen(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Text(
                  'Мои плейлисты',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _createPlaylist(context),
                  icon: const Icon(Icons.playlist_add, size: 22),
                  tooltip: 'Новый плейлист',
                ),
              ],
            ),
          ),
          if (library.playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Плейлистов пока нет.\nНажмите «+», чтобы создать первый.',
                style: TextStyle(color: AppTheme.textDim, height: 1.5),
              ),
            )
          else
            for (final playlist in library.playlists)
              _PlaylistRow(
                playlistId: playlist.id,
                name: playlist.name,
                trackCount: playlist.trackCount,
              ),
        ],
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context) async {
    final name = await showTextDialog(
      context,
      title: 'Новый плейлист',
      positiveLabel: 'Создать',
    );
    if (name == null || !context.mounted) return;
    final playlist = context.read<LibraryProvider>().createPlaylist(name);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistDetailsScreen(playlistId: playlist.id),
      ),
    );
  }
}

class LibraryTile extends StatelessWidget {
  final IconData icon;

  final String title;

  final String subtitle;

  final Color? iconColor;

  final VoidCallback onTap;

  const LibraryTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: iconColor ?? AppTheme.textDim, size: 28),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.textDim),
      ),
    );
  }
}

/// Плейлист в списке: тап открывает детали, кнопка «…» — переименовать/удалить.
class _PlaylistRow extends StatelessWidget {
  final String playlistId;

  final String name;

  final int trackCount;

  const _PlaylistRow({
    required this.playlistId,
    required this.name,
    required this.trackCount,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlaylistDetailsScreen(playlistId: playlistId),
        ),
      ),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.queue_music, color: AppTheme.textDim),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        trackCountLabel(trackCount),
        style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        onPressed: () => _showActions(context),
      ),
    );
  }

  Future<void> _showActions(BuildContext context) async {
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
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _play(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Переименовать'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _rename(context);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.deleteRed,
                ),
                title: const Text(
                  'Удалить',
                  style: TextStyle(color: AppColors.deleteRed),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _delete(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _play(BuildContext context) async {
    final library = context.read<LibraryProvider>();
    final playlist = library.playlistById(playlistId);
    if (playlist == null || playlist.tracks.isEmpty) {
      showAppSnackBar(context, 'Плейлист пуст');
      return;
    }
    await context
        .read<PlayerProvider>()
        .playTracks(playlist.tracks, startIndex: 0);
  }

  Future<void> _rename(BuildContext context) async {
    final current = context.read<LibraryProvider>().playlistById(playlistId);
    if (current == null) return;
    final name = await showTextDialog(
      context,
      title: 'Переименовать плейлист',
      initial: current.name,
    );
    if (name == null || !context.mounted) return;
    context.read<LibraryProvider>().renamePlaylist(playlistId, name);
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Удалить плейлист?',
      message: '«$name» будет удалён безвозвратно. Треки не затрагиваются.',
    );
    if (!ok || !context.mounted) return;
    context.read<LibraryProvider>().deletePlaylist(playlistId);
    showAppSnackBar(context, 'Плейлист удалён');
  }
}
