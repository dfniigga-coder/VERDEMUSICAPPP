import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/track.dart';
import '../../data/repositories/local_tracks_repository.dart';
import '../../providers/player_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/common.dart';
import '../../widgets/track_menu.dart';
import '../../widgets/track_tile.dart';

/// «Мои треки»: медиатека телефона, добавленные файлы и прямые ссылки.
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
    LocalTracksResult result;
    try {
      result = await repo.loadTracks(retryRequest: retryRequest);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _tracks = repo.cached;
      });
      return;
    }
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
      appBar: AppBar(title: const Text('Мои треки')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const LoadingView(message: 'Сканируем устройство…');
    }
    if (_permissionDenied && _tracks.isEmpty) {
      return _permissionDeniedView(context);
    }
    if (_tracks.isEmpty) {
      return const EmptyState(
        icon: Icons.music_off_rounded,
        title: 'Пока нет треков',
        subtitle: 'Добавьте файл или ссылку в Библиотеке — они появятся здесь.',
      );
    }

    final list = ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, AppSpacing.pageBottom),
      itemCount: _tracks.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _Header(tracks: _tracks, onRefresh: () => _load());
        }
        final track = _tracks[index - 1];
        return TrackTile(
          track: track,
          onTap: () {
            context.read<PlayerProvider>().playTracks(
              _tracks,
              startIndex: index - 1,
            );
          },
          onLongPress: () {
            showTrackMenu(context, track: track);
          },
          trailing: LikeButton(track: track),
        );
      },
    );

    if (!_permissionDenied) return list;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: AppCard(
            borderRadius: AppRadii.mdAll,
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Нет доступа к музыке на устройстве — показаны только '
                    'добавленные треки.',
                    style: TextStyle(
                      color: AppColors.textDim,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _load(retryRequest: true),
                  child: const Text('Разрешить'),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: list),
      ],
    );
  }

  Widget _permissionDeniedView(BuildContext context) {
    return EmptyState(
      icon: Icons.lock_outline_rounded,
      title: 'Нужен доступ к музыке',
      subtitle:
          'Разрешите приложению читать аудиофайлы — треки останутся '
          'только на устройстве.',
      action: FilledButton.icon(
        onPressed: () => _load(retryRequest: true),
        icon: const Icon(Icons.perm_media_outlined, size: 19),
        label: const Text('Дать разрешение'),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final List<Track> tracks;

  final VoidCallback onRefresh;

  const _Header({required this.tracks, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: AppCard(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2C4C7A).withValues(alpha: 0.75),
            AppColors.surfaceRaised,
          ],
        ),
        borderRadius: AppRadii.xlAll,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                borderRadius: AppRadii.mdAll,
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(color: AppColors.stroke),
              ),
              child: const Icon(
                Icons.folder_rounded,
                size: 36,
                color: Color(0xFF9CC4FF),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'НА УСТРОЙСТВЕ',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: Color(0xFF9CC4FF),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    trackCountLabel(tracks.length),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 10),
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
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        color: AppColors.text,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          shape: const CircleBorder(),
                        ),
                        tooltip: 'Обновить',
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
