import 'package:flutter/material.dart';

import '../core/theme/design_tokens.dart';
import 'pressable_scale.dart';

/// Главная кнопка воспроизведения: зелёный градиент, свечение и
/// аккуратный индикатор буферизации.
class PlayButton extends StatelessWidget {
  final VoidCallback? onPressed;

  final bool isPlaying;

  final bool isBuffering;

  final double size;

  final Color? color;

  final Color foreground;

  const PlayButton({
    super.key,
    required this.onPressed,
    this.isPlaying = false,
    this.isBuffering = false,
    this.size = 64,
    this.color,
    this.foreground = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fill = color ?? AppColors.accent;

    return PressableScale(
      enabled: enabled,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: Curves.easeOut,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: color == null
              ? AppColors.accentGradient
              : LinearGradient(colors: [fill, fill]),
          boxShadow: enabled ? AppShadows.glow : null,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            customBorder: const CircleBorder(),
            child: Center(
              child: isBuffering
                  ? SizedBox(
                      width: size * 0.34,
                      height: size * 0.34,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: foreground,
                      ),
                    )
                  : Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: size * 0.5,
                      color: enabled ? foreground : AppColors.textMuted,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
