import 'package:flutter/material.dart';

import '../core/theme/design_tokens.dart';

/// Мягко пульсирующий прямоугольник-заглушка вместо спиннера.
class SkeletonBox extends StatefulWidget {
  final double? width;

  final double height;

  final BorderRadius borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = AppRadii.smAll,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(
              AppColors.surfaceRaised,
              AppColors.surfaceHigh,
              t,
            ),
            borderRadius: widget.borderRadius,
          ),
        );
      },
    );
  }
}

/// Скелетон строки трека.
class SkeletonTrackTile extends StatelessWidget {
  const SkeletonTrackTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          const SkeletonBox(
            width: 52,
            height: 52,
            borderRadius: AppRadii.smAll,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 180, height: 13),
                SizedBox(height: 8),
                SkeletonBox(width: 110, height: 10),
              ],
            ),
          ),
          const SkeletonBox(width: 34, height: 10),
        ],
      ),
    );
  }
}

/// Скелетон карточки для горизонтальных секций.
class SkeletonTrackCard extends StatelessWidget {
  final double width;

  const SkeletonTrackCard({super.key, this.width = 164});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(
            width: width,
            height: width,
            borderRadius: AppRadii.lgAll,
          ),
          const SizedBox(height: 10),
          const SkeletonBox(width: 130, height: 12),
          const SizedBox(height: 7),
          const SkeletonBox(width: 90, height: 10),
        ],
      ),
    );
  }
}

/// Готовая лента-скелетон для главной.
class SkeletonRail extends StatelessWidget {
  final bool showHeader;

  const SkeletonRail({super.key, this.showHeader = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 22, 16, 14),
            child: SkeletonBox(width: 170, height: 16),
          ),
        SizedBox(
          height: 218,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, _) => const SkeletonTrackCard(),
          ),
        ),
      ],
    );
  }
}
