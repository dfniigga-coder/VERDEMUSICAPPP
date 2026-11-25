import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/design_tokens.dart';
import '../core/utils/formatters.dart';
import '../data/models/track.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import 'app_card.dart';
import 'artwork.dart';
import 'common.dart';
import 'dialogs.dart';
import 'download_sheet.dart';
import 'full_track_button.dart';
import 'lyrics_sheet.dart';
import 'source_badge.dart';

/// Bottom-меню действий над треком в стиле Apple Music iOS 18:
/// быстрые плитки «Далее», «В очередь», «Волна трека» и список опций.
Future<void> showTrackMenu(
  BuildContext context, {
  required Track track,
  VoidCallback? onRemoved,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (sheetContext) {
      void sendSnack(String message) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }

      final isLiked = sheetContext.read<LibraryProvider>().isLiked(track);
      final duration = track.durationSec == null
          ? null
          : formatDuration(Duration(seconds: track.durationSec!));

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.glassBorder,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                borderRadius: AppRadii.lgAll,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ArtworkView(
                      size: 54,
                      url: track.artworkUrl,
                      borderRadius: AppRadii.smAll,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            duration == null
                                ? track.artist
                                : '${track.artist} · $duration',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: 12.5,
                            ),
                          ),
                          if (track.source != TrackSource.local) ...[
                            const SizedBox(height: 5),
                            TrackSourceBadge(track: track),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _QuickMenuAction(
                      icon: Icons.playlist_play_rounded,
                      label: 'Далее',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        navigator.pop();
                        sheetContext.read<PlayerProvider>().playNext(track);
                        sendSnack('«${track.title}» будет следующим');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickMenuAction(
                      icon: Icons.queue_music_rounded,
                      label: 'В очередь',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        navigator.pop();
                        sheetContext.read<PlayerProvider>().addToQueue(track);
                        sendSnack('Добавлено в очередь');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickMenuAction(
                      icon: Icons.podcasts_rounded,
                      label: 'Волна',
                      accent: true,
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        final player = sheetContext.read<PlayerProvider>();
                        navigator.pop();
                        if (context.mounted) {
                          showAppSnackBar(
                            context,
                            'Собираем волну по треку…',
                          );
                        }
                        await player.startTrackRadio(track);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (track.isPreview)
                ListTile(
                  leading: const Icon(
                    Icons.play_circle_outline_rounded,
                    color: AppColors.accentBright,
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
                leading: Icon(
                  isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isLiked ? AppColors.accentBright : null,
                ),
                title: Text(
                  isLiked
                      ? 'Убрать из «Понравившихся»'
                      : 'В «Понравившиеся»',
                ),
                onTap: () {
                  navigator.pop();
                  sheetContext.read<LibraryProvider>().toggleLike(track);
                  sendSnack(
                    isLiked
                        ? 'Убрано из «Понравившихся»'
                        : 'Добавлено в «Понравившиеся»',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: const Text('Добавить в плейлист…'),
                onTap: () {
                  navigator.pop();
                  showAddToPlaylistSheet(context, track);
                },
              ),
              ListTile(
                leading: const Icon(Icons.lyrics_rounded),
                title: const Text('Текст песни'),
                onTap: () {
                  navigator.pop();
                  showLyricsSheet(context, track);
                },
              ),
              if (!track.isLocal)
                ListTile(
                  leading: const Icon(Icons.download_for_offline_outlined),
                  title: const Text('Скачать MP3 + лирику'),
                  subtitle: const Text(
                    'YouTube Music → MP3 + текст (.lrc)',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    navigator.pop();
                    unawaited(startDownloadWithSheet(context, track));
                  },
                ),
              if (onRemoved != null)
                ListTile(
                  leading: const Icon(
                    Icons.playlist_remove_rounded,
                    color: AppColors.deleteRed,
                  ),
                  title: const Text(
                    'Убрать из плейлиста',
                    style: TextStyle(color: AppColors.deleteRed),
                  ),
                  onTap: () {
                    navigator.pop();
                    onRemoved();
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _QuickMenuAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  const _QuickMenuAction({
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
      gradient: accent
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.accentSoft(0.24), AppColors.surfaceRaised],
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 22,
            color: accent ? AppColors.accentBright : AppColors.text,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent ? AppColors.accentBright : AppColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
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
                      ? 'Добавлено в «$playlistName»'
                      : 'Трек уже есть в плейлисте',
                ),
              ),
            );
          }

          return SafeArea(
            child: SizedBox(
              height: 430,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.glassBorder,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Text(
                      'Добавить в плейлист',
                      style: Theme.of(innerContext).textTheme.titleLarge,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.add_circle_outline_rounded,
                      color: AppColors.accentBright,
                    ),
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
                              style: TextStyle(color: AppColors.textDim),
                            ),
                          )
                        : ListView.builder(
                            itemCount: playlists.length,
                            itemBuilder: (listContext, index) {
                              final playlist = playlists[index];
                              final already = playlist.contains(track);
                              return ListTile(
                                leading: const Icon(Icons.queue_music_rounded),
                                title: Text(playlist.name),
                                subtitle: Text(
                                  trackCountLabel(playlist.trackCount),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: already
                                    ? const Icon(
                                        Icons.check_rounded,
                                        color: AppColors.accentBright,
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
