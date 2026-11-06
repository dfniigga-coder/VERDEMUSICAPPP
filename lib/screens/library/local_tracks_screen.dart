import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/track.dart';
import '../../data/repositories/local_tracks_repository.dart';
import '../../providers/player_provider.dart';
import '../../widgets/track_menu.dart';
import '../../widgets/track_tile.dart';

/// Локальные треки с телефона (on_audio_query).
class LocalTracksScreen extends StatefulWidget {
  const LocalTracksScreen({super.key});

  @override
  State<LocalTracksScreen> createState() => _LocalTracksScreenState();
}

class _LocalTracksScreenState extends State<LocalTracksScreen> {
  bool _loading = true;
  bool _permissionDenied = false;
  List<Track> _tracks = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool retryRequest = false}) async {
    setState(() {
      _loading = true;
      _permissionDenied = false;
    });
    final repo = context.read<LocalTracksRepository>();
    final result = await repo.loadTracks();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _permissionDenied = !result.hasPermission;
      _tracks = result.tracks;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Треки на устройстве')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_permissionDenied) {
      return buildPermissionDenied(context);
    }
    if (_tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.music_off, size: 56, color: Color(0xFF9AA0A3)),
            SizedBox(height: 16),
            Text('На устройстве нет музыки'),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 110),
      itemCount: _tracks.length,
      itemBuilder: (context, index) {
        final track = _tracks[index];
        return TrackTile(
          track: track,
          onTap: () {
            context
                .read<PlayerProvider>()
                .playTracks(_tracks, startIndex: index);
          },
          onLongPress: () {
            showTrackMenu(context, track: track);
          },
          trailing: LikeButton(track: track),
        );
      },
    );
  }

  Widget buildPermissionDenied(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 56, color: Color(0xFF9AA0A3)),
            const SizedBox(height: 16),
            const Text(
              'Нужен доступ к музыке',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Разрешите приложению читать аудиофайлы — '
              'треки останутся только на устройстве.',
              style: TextStyle(color: Color(0xFF9AA0A3), height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _load(retryRequest: true),
              icon: const Icon(Icons.perm_media_outlined),
              label: const Text('Дать разрешение'),
            ),
          ],
        ),
      ),
    );
  }
}
