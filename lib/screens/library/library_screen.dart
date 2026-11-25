import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../data/repositories/local_tracks_repository.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/artwork.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/link_download_sheet.dart';
import '../../widgets/play_button.dart';
import '../settings/settings_screen.dart';
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
    final playlists = library.playlists;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            16,
            14,
            16,
            AppSpacing.bottomInset,
          ),
          children: [
            _header(context),
            const SizedBox(height: 16),
            _StatsRow(
              liked: likedCount,
              playlists: playlists.length,
              local: localCount,
            ),
            const SizedBox(height: 16),
            _LikedCard(
              tracks: library.likedTracks,
              onOpen: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LikedTracksScreen(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _MyTracksCard(
              count: localCount,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LocalTracksScreen(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _QuickActions(
              onPickFiles: () => _pickFiles(context),
              onAddUrl: () => _addByUrl(context),
              onLink: () => showLinkDownloadSheet(context),
            ),
            SectionHeader(
              title: 'Мои плейлисты',
              subtitle: playlists.isEmpty
                  ? 'Соберите первый плейлист'
                  : 'Плейлистов: ${playlists.length}',
              padding: const EdgeInsets.fromLTRB(0, 24, 0, 12),
              action: TextButton.icon(
                onPressed: () => _createPlaylist(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Новый'),
              ),
            ),
            if (playlists.isEmpty)
              _EmptyPlaylists(onCreate: () => _createPlaylist(context))
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.74,
                ),
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return _PlaylistCard(
                    playlist: playlist,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PlaylistDetailsScreen(playlistId: playlist.id),
                      ),
                    ),
                    onMore: () => _showPlaylistActions(context, playlist),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Библиотека',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 4),
              const Text(
                'Ваша музыка, плейлисты и файлы',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        _HeaderIconButton(
          icon: Icons.settings_outlined,
          tooltip: 'Настройки',
          onTap: () => _openSettings(context),
        ),
        const SizedBox(width: 8),
        _HeaderIconButton(
          icon: Icons.add_rounded,
          tooltip: 'Новый плейлист',
          onTap: () => _createPlaylist(context),
          accent: true,
        ),
      ],
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

  void _openSettings(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  Future<void> _pickFiles(BuildContext context) async {
    final repo = context.read<LocalTracksRepository>();
    try {
      final files = await FilePicker.pickFiles(type: FileType.audio);
      if (files.isEmpty) return;

      final paths = files
          .map((file) => file.path)
          .whereType<String>()
          .where((path) => path.isNotEmpty)
          .toList(growable: false);
      if (paths.isEmpty) {
        if (context.mounted) {
          showAppSnackBar(
            context,
            'Не удалось получить путь к выбранным файлам',
            isError: true,
          );
        }
        return;
      }

      final added = await repo.addFiles(paths);
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        added == 0
            ? 'Эти файлы уже есть в библиотеке'
            : 'Добавлено файлов: $added',
      );
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(context, 'Не удалось выбрать файлы', isError: true);
      }
    }
  }

  Future<void> _addByUrl(BuildContext context) async {
    final url = await showTextDialog(
      context,
      title: 'Добавить по ссылке',
      hintText: 'https://example.com/track.mp3',
      positiveLabel: 'Добавить',
    );
    if (url == null || !context.mounted) return;

    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      showAppSnackBar(
        context,
        'Нужна прямая http(s)-ссылка на аудиофайл',
        isError: true,
      );
      return;
    }

    final added = await context.read<LocalTracksRepository>().addStreamUrl(url);
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      added ? 'Трек добавлен в библиотеку' : 'Эта ссылка уже добавлена',
    );
  }

  Future<void> _showPlaylistActions(
    BuildContext context,
    Playlist playlist,
  ) async {
    await showModalBottomSheet<void>(
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
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _playPlaylist(context, playlist);
                },
              ),
              ListTile(
                leading: const Icon(Icons.shuffle_rounded),
                title: const Text('Перемешать и играть'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _playPlaylist(context, playlist, shuffle: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Переименовать'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _renamePlaylist(context, playlist);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.deleteRed,
                ),
                title: const Text(
                  'Удалить',
                  style: TextStyle(color: AppColors.deleteRed),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _deletePlaylist(context, playlist);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _playPlaylist(
    BuildContext context,
    Playlist playlist, {
    bool shuffle = false,
  }) async {
    if (playlist.tracks.isEmpty) {
      showAppSnackBar(context, 'Плейлист пуст');
      return;
    }
    await context.read<PlayerProvider>().playTracks(
      playlist.tracks,
      startIndex: 0,
      shuffle: shuffle,
    );
  }

  Future<void> _renamePlaylist(BuildContext context, Playlist playlist) async {
    final name = await showTextDialog(
      context,
      title: 'Переименовать плейлист',
      initial: playlist.name,
    );
    if (name == null || !context.mounted) return;
    context.read<LibraryProvider>().renamePlaylist(playlist.id, name);
  }

  Future<void> _deletePlaylist(BuildContext context, Playlist playlist) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Удалить плейлист?',
      message:
          '«${playlist.name}» будет удалён безвозвратно. '
          'Треки не затрагиваются.',
    );
    if (!ok || !context.mounted) return;
    context.read<LibraryProvider>().deletePlaylist(playlist.id);
    showAppSnackBar(context, 'Плейлист удалён');
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;

  final String tooltip;

  final VoidCallback onTap;

  final bool accent;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent ? AppColors.accent : AppColors.surfaceRaised,
        border: Border.all(
          color: accent ? AppColors.accentBright : AppColors.stroke,
        ),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        color: accent ? Colors.black : AppColors.text,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int liked;

  final int playlists;

  final int local;

  const _StatsRow({
    required this.liked,
    required this.playlists,
    required this.local,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Stat(value: liked, label: 'лайков'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Stat(value: playlists, label: 'плейлистов'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Stat(value: local, label: 'файлов'),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final int value;

  final String label;

  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderRadius: AppRadii.mdAll,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _LikedCard extends StatelessWidget {
  final List<Track> tracks;

  final VoidCallback onOpen;

  const _LikedCard({required this.tracks, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final urls = <String?>[
      for (final track in tracks.take(4)) track.artworkUrl,
    ];

    return AppCard(
      onTap: onOpen,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.accentDeep.withValues(alpha: 0.85),
          AppColors.surfaceRaised,
        ],
      ),
      borderRadius: AppRadii.xlAll,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _ArtworkMosaic(
            size: 82,
            urls: urls,
            fallbackIcon: Icons.favorite_rounded,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'КОЛЛЕКЦИЯ',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppColors.accentBright,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Понравившиеся',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  trackCountLabel(tracks.length),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDim,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    PlayButton(
                      size: 38,
                      onPressed: tracks.isEmpty
                          ? null
                          : () => context.read<PlayerProvider>().playTracks(
                              tracks,
                              startIndex: 0,
                            ),
                      isPlaying: false,
                    ),
                    const SizedBox(width: 9),
                    const Text(
                      'Слушать',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MyTracksCard extends StatelessWidget {
  final int count;

  final VoidCallback onTap;

  const _MyTracksCard({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      borderRadius: AppRadii.lgAll,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF6FA8FF).withValues(alpha: 0.14),
            ),
            child: const Icon(
              Icons.folder_rounded,
              size: 20,
              color: Color(0xFF6FA8FF),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Мои треки',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count == 0
                      ? 'Файлы, ссылки и музыка с телефона'
                      : trackCountLabel(count),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onPickFiles;

  final VoidCallback onAddUrl;

  final VoidCallback onLink;

  const _QuickActions({
    required this.onPickFiles,
    required this.onAddUrl,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.audio_file_rounded,
            label: 'Файл',
            onTap: onPickFiles,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionTile(
            icon: Icons.link_rounded,
            label: 'Ссылка',
            onTap: onAddUrl,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionTile(
            icon: Icons.smart_display_rounded,
            label: 'YouTube',
            onTap: onLink,
            accent: true,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;

  final String label;

  final VoidCallback onTap;

  final bool accent;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      borderRadius: AppRadii.mdAll,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 17,
            color: accent ? AppColors.accentBright : AppColors.textDim,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: accent ? AppColors.accentBright : AppColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final Playlist playlist;

  final VoidCallback onTap;

  final VoidCallback onMore;

  const _PlaylistCard({
    required this.playlist,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final urls = <String?>[
      for (final track in playlist.tracks.take(4)) track.artworkUrl,
    ];

    return AppCard(
      onTap: onTap,
      borderRadius: AppRadii.lgAll,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, constraints) => _ArtworkMosaic(
                size: constraints.maxWidth,
                urls: urls,
                fallbackIcon: Icons.queue_music_rounded,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        trackCountLabel(playlist.trackCount),
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onMore,
                  icon: const Icon(Icons.more_vert_rounded, size: 18),
                  color: AppColors.textMuted,
                  tooltip: 'Действия',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtworkMosaic extends StatelessWidget {
  final double size;

  final List<String?> urls;

  final IconData fallbackIcon;

  const _ArtworkMosaic({
    required this.size,
    required this.urls,
    required this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: AppRadii.mdAll,
        ),
        child: Icon(
          fallbackIcon,
          size: size * 0.36,
          color: Colors.black.withValues(alpha: 0.72),
        ),
      );
    }

    if (urls.length == 1) {
      return ClipRRect(
        borderRadius: AppRadii.mdAll,
        child: ArtworkView(
          size: size,
          url: urls.first,
          borderRadius: AppRadii.mdAll,
          placeholderIcon: fallbackIcon,
        ),
      );
    }

    final cell = size / 2;
    return ClipRRect(
      borderRadius: AppRadii.mdAll,
      child: Wrap(
        spacing: 0,
        runSpacing: 0,
        children: [
          for (var i = 0; i < 4; i++)
            SizedBox(
              width: cell,
              height: cell,
              child: i < urls.length && urls[i] != null
                  ? ArtworkView(
                      size: cell,
                      url: urls[i],
                      borderRadius: BorderRadius.zero,
                      placeholderIcon: fallbackIcon,
                    )
                  : const ColoredBox(color: AppColors.surfaceHigh),
            ),
        ],
      ),
    );
  }
}

class _EmptyPlaylists extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyPlaylists({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderRadius: AppRadii.lgAll,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const Icon(
            Icons.queue_music_rounded,
            size: 34,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 8),
          const Text(
            'Плейлистов пока нет',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Соберите музыку под настроение или случай.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: AppColors.textDim),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Создать плейлист'),
          ),
        ],
      ),
    );
  }
}
