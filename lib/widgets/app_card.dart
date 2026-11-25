import 'package:flutter/material.dart';

import '../core/theme/design_tokens.dart';
import 'pressable_scale.dart';

/// Базовая карточка Verde: мягкая поверхность, тонкая стеклянная граница,
/// опциональный градиент и тактильный отклик.
class AppCard extends StatelessWidget {
  final Widget child;

  final EdgeInsetsGeometry? padding;

  final VoidCallback? onTap;

  final VoidCallback? onLongPress;

  final Color? color;

  final Gradient? gradient;

  final BorderRadius? borderRadius;

  final Border? border;

  final List<BoxShadow>? shadow;

  final Clip clipBehavior;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.onLongPress,
    this.color,
    this.gradient,
    this.borderRadius,
    this.border,
    this.shadow,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppRadii.lgAll;
    final content = Padding(padding: padding ?? EdgeInsets.zero, child: child);
    final interactive = onTap != null || onLongPress != null;

    final card = Container(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: clipBehavior,
        child: Ink(
          decoration: BoxDecoration(
            color: gradient == null ? (color ?? AppColors.surfaceRaised) : null,
            gradient: gradient,
            borderRadius: radius,
            border: border ?? Border.all(color: AppColors.glassBorder),
          ),
          child: !interactive
              ? content
              : InkWell(
                  onTap: onTap,
                  onLongPress: onLongPress,
                  borderRadius: radius,
                  child: content,
                ),
        ),
      ),
    );

    return PressableScale(enabled: interactive, child: card);
  }
}
