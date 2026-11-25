import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/design_tokens.dart';

/// Обложка трека/подборки: сетевая картинка с кэшированием,
/// либо аккуратная заглушка с иконкой музыки.
///
/// Картинки не обрезаются: 16:9-превью YouTube вписывается в квадратную
/// рамку целиком, а пустые поля заполняет размытая копия обложки.
class ArtworkView extends StatelessWidget {
  final String? url;

  final double size;

  final BorderRadius borderRadius;

  final IconData placeholderIcon;

  const ArtworkView({
    super.key,
    required this.size,
    this.url,
    this.borderRadius = AppRadii.smAll,
    this.placeholderIcon = Icons.music_note,
  }) : assert(size > 0);

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: borderRadius,
      ),
      child: Icon(
        placeholderIcon,
        size: size * 0.38,
        color: AppColors.textMuted,
      ),
    );

    if (url == null || url!.isEmpty) return placeholder;

    // Ограничиваем декодируемое разрешение: 4K-обложка для иконки 48×48
    // занимает мегабайты памяти и легко приводит к OOM в длинных списках.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheSize = (size * dpr).clamp(64.0, 1024.0).round();

    Widget image({required BoxFit fit, Color? tint, double? blurSigma}) {
      final child = CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: fit,
        memCacheWidth: cacheSize,
        memCacheHeight: cacheSize,
        fadeInDuration: const Duration(milliseconds: 220),
        placeholder: (context, url) => placeholder,
        errorWidget: (context, url, error) => placeholder,
        color: tint,
        colorBlendMode: tint == null ? null : BlendMode.darken,
      );

      if (blurSigma == null) return child;
      return ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: child,
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Крупные обложки получают размытую подложку, чтобы поля
            // 16:9-превью не выглядели пустыми. Для мелких иконок
            // хватает спокойного фона — так список не тормозит.
            if (size >= 80)
              image(
                fit: BoxFit.cover,
                tint: Colors.black.withValues(alpha: 0.32),
                blurSigma: 14,
              )
            else
              ColoredBox(color: AppColors.surfaceRaised),
            image(fit: BoxFit.contain),
          ],
        ),
      ),
    );
  }
}

/// Обложка локального трека (artwork из тэга через on_audio_query).
class LocalArtworkView extends StatelessWidget {
  final double size;

  final BorderRadius borderRadius;

  final Future<Uint8List?>? artwork;

  const LocalArtworkView({
    super.key,
    required this.size,
    required this.artwork,
    this.borderRadius = AppRadii.smAll,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: artwork,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null || data.isEmpty) {
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: borderRadius,
            ),
            child: Icon(
              Icons.library_music,
              size: size * 0.38,
              color: AppColors.textMuted,
            ),
          );
        }
        final cacheSize = (size * MediaQuery.devicePixelRatioOf(context))
            .clamp(64.0, 1024.0)
            .round();
        return ClipRRect(
          borderRadius: borderRadius,
          child: Image.memory(
            data,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: cacheSize,
            cacheHeight: cacheSize,
            gaplessPlayback: true,
          ),
        );
      },
    );
  }
}

/// Размытая обложка на фоне карточки или полноэкранного плеера.
///
/// Слой [BackdropFilter] размывает саму картинку, а градиентный оверлей
/// делает поверхность достаточно тёмной для читаемого текста.
class ArtworkBackdrop extends StatelessWidget {
  final String? url;

  final Widget child;

  final double blur;

  final Color? overlayColor;

  final Gradient? gradient;

  final BorderRadius? borderRadius;

  const ArtworkBackdrop({
    super.key,
    required this.child,
    this.url,
    this.blur = 28,
    this.overlayColor,
    this.gradient,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations;
    final sigma = disableAnimations == true ? 0.0 : blur;

    Widget background;
    if (url == null || url!.isEmpty) {
      background = const DecoratedBox(
        decoration: BoxDecoration(gradient: AppColors.accentGradient),
      );
    } else {
      background = CachedNetworkImage(
        imageUrl: url!,
        fit: BoxFit.cover,
        memCacheWidth: 900,
        memCacheHeight: 900,
        fadeInDuration: const Duration(milliseconds: 240),
        placeholder: (context, url) =>
            const ColoredBox(color: AppColors.surface),
        errorWidget: (context, url, error) =>
            const ColoredBox(color: AppColors.surface),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          background,
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: ColoredBox(
              color: overlayColor ?? Colors.black.withValues(alpha: 0.38),
            ),
          ),
          if (gradient != null)
            DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
          child,
        ],
      ),
    );
  }
}
