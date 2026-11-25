import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/design_tokens.dart';
import '../core/utils/formatters.dart';
import '../providers/player_provider.dart';
import 'app_card.dart';
import 'common.dart';

/// Открывает стеклянную панель управления звучанием:
/// скорость, высота тона, пресеты (Slowed / Nightcore) и таймер сна.
Future<void> showAudioEffectsSheet(
  BuildContext context, {
  bool focusSleepTimer = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    builder: (_) => _AudioEffectsSheet(focusSleepTimer: focusSleepTimer),
  );
}

class _AudioEffectsSheet extends StatelessWidget {
  final bool focusSleepTimer;

  const _AudioEffectsSheet({required this.focusSleepTimer});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final presets = [
      AudioVibePreset.normal,
      AudioVibePreset.slowed,
      AudioVibePreset.nightcore,
      AudioVibePreset.boosted,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentSoft(0.18),
                  border: Border.all(
                    color: AppColors.accentBright.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  size: 20,
                  color: AppColors.accentBright,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      focusSleepTimer
                          ? 'Таймер сна и звук'
                          : 'Звучание и эффекты',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Скорость, тональность и автостоп',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              if (player.hasCustomAudioEffect)
                TextButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    player.setAudioPreset(AudioVibePreset.normal);
                  },
                  child: const Text('Сбросить'),
                ),
            ],
          ),
          if (!focusSleepTimer) ...[
            const SizedBox(height: 18),
            _buildPresetsGrid(player, presets),
            const SizedBox(height: 18),
            _buildSlidersCard(player),
            const SizedBox(height: 20),
            _buildSleepSection(context, player),
          ] else ...[
            const SizedBox(height: 18),
            _buildSleepSection(context, player),
            const SizedBox(height: 20),
            _buildPresetsGrid(player, presets),
            const SizedBox(height: 18),
            _buildSlidersCard(player),
          ],
        ],
      ),
    );
  }

  Widget _buildPresetsGrid(
    PlayerProvider player,
    List<AudioVibePreset> presets,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Аудио-вайб',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in presets)
              _PresetChip(
                label: preset.label,
                selected: player.audioPreset == preset,
                onTap: () {
                  HapticFeedback.selectionClick();
                  player.setAudioPreset(preset);
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSlidersCard(PlayerProvider player) {
    return AppCard(
      borderRadius: AppRadii.lgAll,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        children: [
          _SliderRow(
            icon: Icons.speed_rounded,
            label: 'Скорость',
            valueLabel: '${player.speed.toStringAsFixed(2)}x',
            value: player.speed,
            min: 0.5,
            max: 2.0,
            divisions: 30,
            onChanged: (value) =>
                player.setCustomSpeedPitch(speed: value, pitch: player.pitch),
          ),
          const Divider(height: 14),
          _SliderRow(
            icon: Icons.tune_rounded,
            label: 'Высота тона',
            valueLabel: '${player.pitch.toStringAsFixed(2)}x',
            value: player.pitch,
            min: 0.7,
            max: 1.4,
            divisions: 28,
            onChanged: (value) =>
                player.setCustomSpeedPitch(speed: player.speed, pitch: value),
          ),
          const Divider(height: 14),
          _SliderRow(
            icon: Icons.volume_up_rounded,
            label: 'Громкость',
            valueLabel: '${(player.volume * 100).round()}%',
            value: player.volume,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            onChanged: player.setVolume,
          ),
        ],
      ),
    );
  }

  Widget _buildSleepSection(BuildContext context, PlayerProvider player) {
    const minutesList = [5, 15, 30, 45, 60];

    return AppCard(
      borderRadius: AppRadii.lgAll,
      gradient: player.hasSleepTimer
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.accentSoft(0.18), AppColors.surfaceRaised],
            )
          : null,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bedtime_rounded,
                size: 19,
                color: AppColors.accentBright,
              ),
              const SizedBox(width: 8),
              const Text(
                'Таймер сна',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const Spacer(),
              ValueListenableBuilder<Duration?>(
                valueListenable: player.sleepRemainingNotifier,
                builder: (context, remaining, _) {
                  if (player.sleepEndOfTrack) {
                    return const Text(
                      'До конца трека',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentBright,
                      ),
                    );
                  }
                  if (remaining == null) {
                    return const Text(
                      'Выключен',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    );
                  }
                  return Text(
                    'Пауза через ${formatDuration(remaining)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentBright,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in minutesList)
                _PresetChip(
                  label: '$m мин',
                  selected: false,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    player.setSleepTimer(Duration(minutes: m));
                    showAppSnackBar(context, 'Таймер сна: $m мин');
                  },
                ),
              _PresetChip(
                label: 'До конца трека',
                selected: player.sleepEndOfTrack,
                onTap: () {
                  HapticFeedback.selectionClick();
                  player.setSleepTimer(null, endOfTrack: true);
                  showAppSnackBar(context, 'Остановим после текущего трека');
                },
              ),
              if (player.hasSleepTimer)
                _PresetChip(
                  label: 'Отключить',
                  selected: false,
                  destructive: true,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    player.cancelSleepTimer();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool destructive;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = destructive
        ? AppColors.error.withValues(alpha: 0.14)
        : selected
        ? AppColors.accent
        : AppColors.surfaceHigh;
    final fg = destructive
        ? AppColors.error
        : selected
        ? Colors.black
        : AppColors.text;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: destructive
                  ? AppColors.error.withValues(alpha: 0.35)
                  : selected
                  ? AppColors.accentBright
                  : AppColors.glassBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 17, color: AppColors.accentBright),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const Spacer(),
            Text(
              valueLabel,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.accentBright,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
