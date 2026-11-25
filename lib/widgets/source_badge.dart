import 'package:flutter/material.dart';

import '../core/theme/design_tokens.dart';
import '../data/models/track.dart';

/// Маленький бейдж источника или пометки «превью».
class SourceBadge extends StatelessWidget {
  final String text;

  final IconData icon;

  final Color foreground;

  final Color background;

  const SourceBadge({
    super.key,
    required this.text,
    required this.icon,
    this.foreground = AppColors.textDim,
    this.background = const Color(0x14FFFFFF),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: foreground.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: foreground),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 9.5,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// Бейдж источника трека.
class TrackSourceBadge extends StatelessWidget {
  final Track track;

  const TrackSourceBadge({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    if (track.source == TrackSource.local) return const SizedBox.shrink();
    final color = sourceColor(track.source);
    return SourceBadge(
      text: track.source.label,
      icon: sourceIcon(track.source),
      foreground: color,
      background: color.withValues(alpha: 0.12),
    );
  }
}

/// Пометка о 30-секундном превью.
class PreviewBadge extends StatelessWidget {
  const PreviewBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return SourceBadge(
      text: 'превью 30 с',
      icon: Icons.timer_outlined,
      foreground: AppColors.warning,
      background: AppColors.warning.withValues(alpha: 0.12),
    );
  }
}

Color sourceColor(TrackSource source) {
  switch (source) {
    case TrackSource.audius:
      return const Color(0xFFCC6BFF);
    case TrackSource.deezer:
      return const Color(0xFFB06BFF);
    case TrackSource.itunes:
      return const Color(0xFFFF6B81);
    case TrackSource.jamendo:
      return const Color(0xFFFFB35C);
    case TrackSource.archive:
      return const Color(0xFF6FA8FF);
    case TrackSource.external:
      return AppColors.textDim;
    case TrackSource.local:
      return AppColors.textDim;
    case TrackSource.soundcloud:
      return const Color(0xFFFF8A4C);
    case TrackSource.youtube:
      return const Color(0xFFFF6B6B);
  }
}

IconData sourceIcon(TrackSource source) {
  switch (source) {
    case TrackSource.audius:
      return Icons.waves;
    case TrackSource.deezer:
      return Icons.graphic_eq;
    case TrackSource.itunes:
      return Icons.music_note;
    case TrackSource.jamendo:
      return Icons.public;
    case TrackSource.archive:
      return Icons.account_balance;
    case TrackSource.external:
      return Icons.link;
    case TrackSource.local:
      return Icons.folder;
    case TrackSource.soundcloud:
      return Icons.cloud;
    case TrackSource.youtube:
      return Icons.smart_display;
  }
}
