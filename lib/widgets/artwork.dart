import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

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
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.placeholderIcon = Icons.music_note,
  }) : assert(size > 0);

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: borderRadius,
      ),
      child: Icon(placeholderIcon, size: size * 0.38, color: AppTheme.textDim),
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
        fadeInDuration: const Duration(milliseconds: 200),
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
                tint: Colors.black.withValues(alpha: 0.28),
                blurSigma: 14,
              )
            else
              ColoredBox(color: AppTheme.surfaceContainer),
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
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
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
              color: AppTheme.surfaceContainer,
              borderRadius: borderRadius,
            ),
            child: Icon(
              Icons.library_music,
              size: size * 0.38,
              color: AppTheme.textDim,
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
