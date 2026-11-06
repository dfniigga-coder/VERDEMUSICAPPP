import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Обложка трека/подборки: сетевая картинка с кэшированием,
/// либо аккуратная заглушка с иконкой музыки.
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
      child: Icon(
        placeholderIcon,
        size: size * 0.38,
        color: AppTheme.textDim,
      ),
    );

    if (url == null || url!.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: borderRadius,
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (context, url) => placeholder,
        errorWidget: (context, url, error) => placeholder,
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
        return ClipRRect(
          borderRadius: borderRadius,
          child: Image.memory(
            data,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      },
    );
  }
}
