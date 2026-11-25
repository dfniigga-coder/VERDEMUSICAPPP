import 'package:flutter/material.dart';

import '../core/theme/design_tokens.dart';

/// Мягкое уменьшение нажатого элемента до 0.97.
///
/// Слушает pointer-события, но не участвует в gesture arena: внутренние
/// `InkWell`/`GestureDetector` продолжают получать тапы и свайпы как обычно.
class PressableScale extends StatefulWidget {
  final Widget child;

  final bool enabled;

  final double scale;

  const PressableScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 0.97,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: AppDurations.fast,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
