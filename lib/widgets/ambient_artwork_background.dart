import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/design_tokens.dart';

/// Живой переливающийся фон в стиле Apple Music iOS 18:
/// извлекает палитру обложки (с кэшированием и тёмно-зелёным фолбэком Verde)
/// и плавно смещает цветовые пятна поверх размытой обложки.
class AmbientArtworkBackground extends StatefulWidget {
  final String? artworkUrl;
  final bool animate;
  final Widget? child;

  const AmbientArtworkBackground({
    super.key,
    required this.artworkUrl,
    this.animate = true,
    this.child,
  });

  @override
  State<AmbientArtworkBackground> createState() =>
      _AmbientArtworkBackgroundState();
}

class _AmbientArtworkBackgroundState extends State<AmbientArtworkBackground>
    with SingleTickerProviderStateMixin {
  static const List<Color> _defaultPalette = [
    Color(0xFF0C4A2A),
    Color(0xFF19A950),
    Color(0xFF061F12),
  ];

  static final Map<String, List<Color>> _paletteCache = {};
  static const int _maxCacheEntries = 40;

  late final AnimationController _controller;
  List<Color> _palette = _defaultPalette;
  String? _resolvedUrl;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    _syncAnimation();
    unawaited(_resolvePalette());
  }

  @override
  void didUpdateWidget(covariant AmbientArtworkBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      _syncAnimation();
    }
    if (oldWidget.artworkUrl != widget.artworkUrl) {
      unawaited(_resolvePalette());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  void _syncAnimation() {
    final disable = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.animate && !disable) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      if (_controller.isAnimating) _controller.stop();
    }
  }

  Future<void> _resolvePalette() async {
    final url = widget.artworkUrl?.trim();
    if (url == null || url.isEmpty) {
      if (!mounted) return;
      setState(() {
        _palette = _defaultPalette;
        _resolvedUrl = null;
      });
      return;
    }

    if (url == _resolvedUrl) return;
    _resolvedUrl = url;

    final cached = _paletteCache[url];
    if (cached != null) {
      if (!mounted) return;
      setState(() => _palette = cached);
      return;
    }

    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: CachedNetworkImageProvider(url),
        brightness: Brightness.dark,
      );
      if (!mounted || _resolvedUrl != url) return;

      final colors = <Color>[
        Color.lerp(scheme.primary, AppColors.forestDark, 0.35) ??
            _defaultPalette[0],
        Color.lerp(scheme.secondary, AppColors.accent, 0.25) ??
            _defaultPalette[1],
        Color.lerp(scheme.tertiary, AppColors.background, 0.45) ??
            _defaultPalette[2],
      ];

      _paletteCache[url] = colors;
      if (_paletteCache.length > _maxCacheEntries) {
        _paletteCache.remove(_paletteCache.keys.first);
      }

      setState(() => _palette = colors);
    } catch (_) {
      if (!mounted || _resolvedUrl != url) return;
      setState(() => _palette = _defaultPalette);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disable = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final sigma = disable ? 0.0 : 48.0;
    final url = widget.artworkUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.background),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: url != null && url.isNotEmpty
              ? SizedBox.expand(
                  key: ValueKey(url),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    memCacheWidth: 512,
                    memCacheHeight: 512,
                    fadeInDuration: const Duration(milliseconds: 300),
                    placeholder: (_, _) => const SizedBox.shrink(),
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                )
              : const DecoratedBox(
                  key: ValueKey('fallback'),
                  decoration: BoxDecoration(
                    gradient: AppColors.forestHeroGradient,
                  ),
                ),
        ),
        if (sigma > 0)
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: ColoredBox(
              color: AppColors.background.withValues(alpha: 0.42),
            ),
          )
        else
          ColoredBox(color: AppColors.background.withValues(alpha: 0.55)),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value * math.pi * 2;
            final x1 = -0.45 + math.sin(t) * 0.35;
            final y1 = -0.55 + math.cos(t * 0.8) * 0.25;
            final x2 = 0.5 + math.cos(t * 0.9) * 0.32;
            final y2 = 0.25 + math.sin(t * 1.1) * 0.3;

            return Stack(
              fit: StackFit.expand,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 650),
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(x1, y1),
                      radius: 1.15,
                      colors: [
                        _palette[0].withValues(alpha: 0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 650),
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(x2, y2),
                      radius: 1.1,
                      colors: [
                        _palette[1].withValues(alpha: 0.36),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.playerScrim),
        ),
        ?widget.child,
      ],
    );
  }
}
