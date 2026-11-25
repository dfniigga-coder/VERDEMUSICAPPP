import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/theme/design_tokens.dart';

/// Полупрозрачная панель с размытием фона.
///
/// Blur используется точечно (навигация, мини-плеер, кнопки поверх обложки):
/// `BackdropFilter` дорог на слабых Android-устройствах. При отключённых
/// анимациях размытие автоматически убирается.
class GlassPanel extends StatelessWidget {
  final Widget child;

  final BorderRadius borderRadius;

  final EdgeInsetsGeometry? padding;

  final Color? color;

  final double blur;

  final Border? border;

  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = AppRadii.xlAll,
    this.padding,
    this.color,
    this.blur = 18,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations;
    final content = Padding(padding: padding ?? EdgeInsets.zero, child: child);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: disableAnimations == true ? 0 : blur,
          sigmaY: disableAnimations == true ? 0 : blur,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color ?? AppColors.surfaceRaised.withValues(alpha: 0.82),
            borderRadius: borderRadius,
            border: border ?? Border.all(color: AppColors.stroke),
          ),
          child: content,
        ),
      ),
    );
  }
}
