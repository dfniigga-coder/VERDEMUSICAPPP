import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../data/models/track.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import 'artwork.dart';
import 'dialogs.dart';
import 'full_track_button.dart';

/// Bottom-меню действий над треком: очередь, лайк, плейлисты.
Future<void> showTrackMenu(
  BuildContext context, {
  required Track track,
  VoidCallback? onRemoved,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      void sendSnack(String message) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }

      final isLiked = sheetContext.read<LibraryProvider>().isLiked(track);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  ArtworkView(size: 44, url: track.artworkUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textDim,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (track.isPreview)
              ListTile(
                leading: const Icon(
                  Icons.play_circle_outline,
                  color: AppTheme.accentGreen,
                ),
                title: const Text('Слушать полностью'),
                subtitle: const Text(
                  'SoundCloud / YouTube',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () {
                  navigator.pop();
                  playFullTrack(context, track);
                },
              ),
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: const Text('Слушать следующим'),
              onTap: () {
                navigator.pop();
                sheetContext.read<PlayerProvider>().playNext(track);
                sendSnack('«${track.title}» будет следующим');
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue),
              title: const Text('Добавить в очередь'),
              onTap: () {
                navigator.pop();
                sheetContext.read<PlayerProvider>().addToQueue(track);
                sendSnack('Добавлено в очередь');
              },
            ),
            ListTile(
              leading: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border_rounded,
                color: isLiked ? AppTheme.accentGreen : null,
              ),
              title: Text(
                isLiked ? 'Убрать из «Мне нравится»' : 'В «Мне нравится»',
              ),
              onTap: () {
                navigator.pop();
                sheetContext.read<LibraryProvider>().toggleLike(track);
                sendSnack(
                  isLiked
                      ? 'Убрано из «Мне нравится»'
                      : 'Добавлено в «Мне нравится»',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Добавить в плейлист…'),
              onTap: () {
                navigator.pop();
                showAddToPlaylistSheet(context, track);
              },
            ),
            if (onRemoved != null)
              ListTile(
                leading: const Icon(Icons.playlist_remove),
                title: const Text('Убрать из плейлиста'),
                onTap: () {
                  navigator.pop();
                  onRemoved();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Выбор плейлиста для добавления трека.
Future<void> showAddToPlaylistSheet(BuildContext context, Track track) async {
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return Consumer<LibraryProvider>(
        builder: (innerContext, library, _) {
          final playlists = library.playlists;

          void feedback(bool added, String playlistName) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  added
                      ? 'Добавлено в "$playlistName"'
                      : 'Трек уже есть в плейлисте',
                ),
              ),
            );
          }

          return SafeArea(
            child: SizedBox(
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      'Добавить в плейлист',
                      style: Theme.of(innerContext).textTheme.titleMedium,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Новый плейлист'),
                    onTap: () async {
                      final name = await showTextDialog(
                        innerContext,
                        title: 'Новый плейлист',
                        positiveLabel: 'Создать',
                      );
                      if (name == null || !innerContext.mounted) return;

                      final libraryHere = innerContext.read<LibraryProvider>();
                      final playlist = libraryHere.createPlaylist(name);
                      final added = libraryHere.addTrackToPlaylist(
                        playlist.id,
                        track,
                      );
                      if (!innerContext.mounted) return;
                      Navigator.of(innerContext).pop();
                      feedback(added, playlist.name);
                    },
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: playlists.isEmpty
                        ? const Center(
                            child: Text(
                              'Плейлистов пока нет',
                              style: TextStyle(color: AppTheme.textDim),
                            ),
                          )
                        : ListView.builder(
                            itemCount: playlists.length,
                            itemBuilder: (listContext, index) {
                              final playlist = playlists[index];
                              final already = playlist.contains(track);
                              return ListTile(
                                leading: const Icon(Icons.queue_music),
                                title: Text(playlist.name),
                                subtitle: Text(
                                  trackCountLabel(playlist.trackCount),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: already
                                    ? const Icon(
                                        Icons.check,
                                        color: AppTheme.accentGreen,
                                      )
                                    : null,
                                enabled: !already,
                                onTap: already
                                    ? null
                                    : () {
                                        final added = innerContext
                                            .read<LibraryProvider>()
                                            .addTrackToPlaylist(
                                              playlist.id,
                                              track,
                                            );
                                        Navigator.of(innerContext).pop();
                                        feedback(added, playlist.name);
                                      },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
