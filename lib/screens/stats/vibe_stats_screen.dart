import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/local_tracks_repository.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/recommendation_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/artwork.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/track_menu.dart';
import '../../widgets/track_tile.dart';

/// Экран личной статистики и истории прослушиваний «Мой вайб»
/// в стиле Apple Music Replay / Spotify Wrapped.
class VibeStatsScreen extends StatefulWidget {
  const VibeStatsScreen({super.key});

  @override
  State<VibeStatsScreen> createState() => _VibeStatsScreenState();
}

class _VibeStatsScreenState extends State<VibeStatsScreen> {
  Future<void> _clearHistory() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Очистить историю?',
      message:
          'Статистика прослушиваний и «Мой вайб» будут сброшены. '
          'Лайки и плейлисты останутся.',
      confirmLabel: 'Очистить',
    );
    if (!ok || !mounted) return;
    await context.read<RecommendationService>().clearHistory();
    if (!mounted) return;
    setState(() {});
    showAppSnackBar(context, 'История прослушиваний очищена');
  }

  @override
  Widget build(BuildContext context) {
    final recs = context.watch<RecommendationService?>();
    final service = recs ?? Provider.of<RecommendationService>(context);
    final library = context.watch<LibraryProvider>();
    final localRepo = context.watch<LocalTracksRepository>();

    final totalPlays = service.totalPlaysCount;
    final totalDuration = service.totalListenDuration;
    final topArtists = service.topArtistStats;
    final mostPlayed = service.mostPlayedTracks;
    final history = service.recentHistory;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мой вайб'),
        actions: [
          if (totalPlays > 0)
            IconButton(
              onPressed: _clearHistory,
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Очистить историю',
            ),
        ],
      ),
      body: totalPlays == 0 && library.likedTracks.isEmpty
          ? const EmptyState(
              icon: Icons.auto_awesome_rounded,
              title: 'Ваш музыкальный вайб ещё формируется',
              subtitle:
                  'Послушайте несколько треков — здесь появятся топ-артисты, '
                  'любимые повторы и время прослушивания.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                16,
                8,
                16,
                AppSpacing.pageBottom,
              ),
              children: [
                _ReplayHeroCard(
                  totalPlays: totalPlays,
                  totalDuration: totalDuration,
                  likedCount: library.likedTracks.length,
                  localCount: localRepo.cached.length,
                  onPlayMostPlayed: mostPlayed.isEmpty
                      ? null
                      : () => context.read<PlayerProvider>().playTracks(
                          mostPlayed,
                          startIndex: 0,
                        ),
                ),
                if (topArtists.isNotEmpty) ...[
                  const SectionHeader(
                    title: 'Топ исполнители',
                    subtitle: 'Чаще всего звучали за последнее время',
                    padding: EdgeInsets.fromLTRB(0, 24, 0, 12),
                  ),
                  SizedBox(
                    height: 124,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: topArtists.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (context, index) {
                        final stat = topArtists[index];
                        return _ArtistStatTile(stat: stat, rank: index + 1);
                      },
                    ),
                  ),
                ],
                if (mostPlayed.isNotEmpty) ...[
                  SectionHeader(
                    title: 'На повторе',
                    subtitle: 'Треки, к которым вы возвращаетесь',
                    padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
                    actionLabel: 'Включить',
                    onAction: () => context.read<PlayerProvider>().playTracks(
                      mostPlayed,
                      startIndex: 0,
                    ),
                  ),
                  for (var i = 0; i < mostPlayed.length; i++)
                    TrackTile(
                      track: mostPlayed[i],
                      onTap: () => context.read<PlayerProvider>().playTracks(
                        mostPlayed,
                        startIndex: i,
                      ),
                      onLongPress: () =>
                          showTrackMenu(context, track: mostPlayed[i]),
                      trailing: LikeButton(track: mostPlayed[i]),
                    ),
                ],
                if (history.isNotEmpty) ...[
                  const SectionHeader(
                    title: 'История прослушиваний',
                    subtitle: 'Недавно звучали в Verde',
                    padding: EdgeInsets.fromLTRB(0, 22, 0, 8),
                  ),
                  for (final item in history)
                    _HistoryTrackRow(
                      item: item,
                      onTap: () => context.read<PlayerProvider>().playTracks([
                        item.track,
                      ]),
                      onLongPress: () =>
                          showTrackMenu(context, track: item.track),
                    ),
                ],
              ],
            ),
    );
  }
}

class _ReplayHeroCard extends StatelessWidget {
  final int totalPlays;
  final Duration totalDuration;
  final int likedCount;
  final int localCount;
  final VoidCallback? onPlayMostPlayed;

  const _ReplayHeroCard({
    required this.totalPlays,
    required this.totalDuration,
    required this.likedCount,
    required this.localCount,
    this.onPlayMostPlayed,
  });

  String _durationLabel() {
    final hours = totalDuration.inHours;
    final mins = totalDuration.inMinutes % 60;
    if (hours > 0) return '$hours ч $mins м';
    return '${totalDuration.inMinutes} мин';
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderRadius: AppRadii.xlAll,
      gradient: AppColors.forestHeroGradient,
      shadow: AppShadows.card,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft(0.24),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(
                    color: AppColors.accentBright.withValues(alpha: 0.35),
                  ),
                ),
                child: const Text(
                  'VERDE REPLAY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppColors.accentBright,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.auto_awesome_rounded,
                size: 20,
                color: AppColors.accentBright,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _durationLabel(),
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.1,
              height: 1.05,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'примерное время звучания вашей музыки',
            style: TextStyle(fontSize: 13, color: AppColors.textDim),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _MiniMetric(value: '$totalPlays', label: 'запусков'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniMetric(value: '$likedCount', label: 'в любимых'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniMetric(value: '$localCount', label: 'на устройстве'),
              ),
            ],
          ),
          if (onPlayMostPlayed != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPlayMostPlayed,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('Включить мои повторы'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String value;
  final String label;

  const _MiniMetric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
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
            style: const TextStyle(fontSize: 10.5, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}

class _ArtistStatTile extends StatelessWidget {
  final ArtistTasteStat stat;
  final int rank;

  const _ArtistStatTile({required this.stat, required this.rank});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: rank == 1
                        ? AppColors.accentBright
                        : AppColors.glassBorder,
                    width: rank == 1 ? 2 : 1,
                  ),
                  boxShadow: AppShadows.card,
                ),
                child: ClipOval(
                  child: stat.artworkUrl != null
                      ? ArtworkView(
                          size: 82,
                          url: stat.artworkUrl,
                          borderRadius: BorderRadius.circular(999),
                        )
                      : Container(
                          color: AppColors.surfaceHigh,
                          alignment: Alignment.center,
                          child: Text(
                            firstLetter(stat.name),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppColors.accentBright,
                            ),
                          ),
                        ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: rank == 1
                        ? AppColors.accent
                        : AppColors.surfaceRaised,
                    border: Border.all(color: AppColors.background, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: rank == 1 ? Colors.black : AppColors.text,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            stat.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTrackRow extends StatelessWidget {
  final PlayedHistoryItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _HistoryTrackRow({
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  String _relativeTime(DateTime playedAt) {
    final diff = DateTime.now().difference(playedAt);
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
    if (diff.inHours < 24) return '${diff.inHours} ч назад';
    if (diff.inDays < 7) return '${diff.inDays} д назад';
    return '${playedAt.day}.${playedAt.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return TrackTile(
      track: item.track,
      onTap: onTap,
      onLongPress: onLongPress,
      trailing: Text(
        _relativeTime(item.playedAt),
        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
      ),
    );
  }
}
