import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/track_menu.dart';
import '../../widgets/track_tile.dart';

/// «Понравившиеся треки».
class LikedTracksScreen extends StatelessWidget {
  const LikedTracksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final tracks = library.likedTracks;

    if (tracks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Понравившиеся треки')),
        body: const EmptyState(
          icon: Icons.favorite_border,
          title: 'Пока ничего не понравилось',
          subtitle: 'Ставьте «сердечки» трекам — они соберутся здесь и останутся после перезапуска',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Понравившиеся треки')),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 110),
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          return TrackTile(
            track: track,
            onTap: () {
              context.read<PlayerProvider>().playTracks(
                tracks,
                startIndex: index,
              );
            },
            onLongPress: () {
              showTrackMenu(context, track: track);
            },
            trailing: LikeButton(track: track),
          );
        },
      ),
    );
  }
}
