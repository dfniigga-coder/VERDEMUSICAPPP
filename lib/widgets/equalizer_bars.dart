import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/design_tokens.dart';

/// Анимированный эквалайзер для строки «сейчас играет».
class EqualizerBars extends StatefulWidget {
  final Color color;

  final double height;

  final double barWidth;

  final double gap;

  final bool playing;

  final int barCount;

  const EqualizerBars({
    super.key,
    this.color = AppColors.accentBright,
    this.height = 14,
    this.barWidth = 3,
    this.gap = 2,
    this.playing = true,
    this.barCount = 3,
  });

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant EqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (widget.playing) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value * math.pi * 2;
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < widget.barCount; i++) ...[
                if (i > 0) SizedBox(width: widget.gap),
                _bar(i, t),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _bar(int index, double t) {
    final phase = index * 1.7;
    final wave = widget.playing
        ? 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t + phase))
        : 0.32 + 0.12 * index;
    final height = (widget.height * wave).clamp(3.0, widget.height).toDouble();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      width: widget.barWidth,
      height: height,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(widget.barWidth),
      ),
    );
  }
}
