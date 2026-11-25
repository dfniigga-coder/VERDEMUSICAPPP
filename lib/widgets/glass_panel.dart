import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/theme/design_tokens.dart';

/// Полупрозрачная панель с эффектом жидкого стекла iOS 18 и верхним бликом.
///
/// При отключённых системных анимациях размытие автоматически отключается.
class GlassPanel extends StatelessWidget {
  final Widget child;

  final BorderRadius borderRadius;

  final EdgeInsetsGeometry? padding;

  final Color? color;

  final double blur;

  final Border? border;

  final bool specularHighlight;

  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = AppRadii.xlAll,
    this.padding,
    this.color,
    this.blur = 20,
    this.border,
    this.specularHighlight = true,
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
        child: Container(
          decoration: BoxDecoration(
            color: color ?? AppColors.glassSurface,
            borderRadius: borderRadius,
            border: border ?? Border.all(color: AppColors.glassBorder),
          ),
          foregroundDecoration: specularHighlight
              ? BoxDecoration(
                  borderRadius: borderRadius,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.09),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.08),
                    ],
                    stops: const [0.0, 0.25, 1.0],
                  ),
                )
              : null,
          child: content,
        ),
      ),
    );
  }
}
