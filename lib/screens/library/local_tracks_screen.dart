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
  String _filter = '';

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
      appBar: AppBar(
        title: const Text('Мои треки'),
        actions: [
          IconButton(
            onPressed: () => _load(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить список',
          ),
        ],
      ),
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
        subtitle:
            'Добавьте файл или ссылку в Медиатеке — они появятся здесь.',
      );
    }

    final q = _filter.trim().toLowerCase();
    final visible = q.isEmpty
        ? _tracks
        : _tracks
              .where(
                (t) =>
                    t.title.toLowerCase().contains(q) ||
                    t.artist.toLowerCase().contains(q),
              )
              .toList(growable: false);
    final showSearch = _tracks.length >= 6;

    final list = ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, AppSpacing.pageBottom),
      itemCount: visible.length + (showSearch ? 2 : 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _Header(tracks: _tracks);
        }
        if (showSearch && index == 1) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: TextField(
              onChanged: (v) => setState(() => _filter = v),
              decoration: const InputDecoration(
                hintText: 'Поиск по вашим трекам…',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
              ),
            ),
          );
        }
        final trackIndex = index - (showSearch ? 2 : 1);
        final track = visible[trackIndex];
        return TrackTile(
          track: track,
          onTap: () {
            context.read<PlayerProvider>().playTracks(
              visible,
              startIndex: trackIndex,
            );
          },
          onLongPress: () => showTrackMenu(context, track: track),
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

  const _Header({required this.tracks});

  String _durationSummary() {
    var sec = 0;
    for (final t in tracks) {
      sec += t.durationSec ?? 0;
    }
    if (sec <= 0) return trackCountLabel(tracks.length);
    final mins = (sec / 60).round();
    return '${trackCountLabel(tracks.length)} · ~$mins мин';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
      child: AppCard(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F426B), AppColors.surfaceRaised],
        ),
        borderRadius: AppRadii.xlAll,
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                borderRadius: AppRadii.lgAll,
                color: Colors.white.withValues(alpha: 0.1),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                boxShadow: AppShadows.card,
              ),
              child: const Icon(
                Icons.folder_rounded,
                size: 46,
                color: Color(0xFF9CC4FF),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'НА УСТРОЙСТВЕ',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: Color(0xFF9CC4FF),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Мои треки',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _durationSummary(),
              style: const TextStyle(fontSize: 12.5, color: AppColors.textDim),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context
                        .read<PlayerProvider>()
                        .playTracks(tracks, startIndex: 0),
                    icon: const Icon(Icons.play_arrow_rounded, size: 21),
                    label: const Text('Слушать'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context
                        .read<PlayerProvider>()
                        .playTracks(tracks, startIndex: 0, shuffle: true),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                    icon: const Icon(Icons.shuffle_rounded, size: 19),
                    label: const Text('Перемешать'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
