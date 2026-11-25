import 'package:flutter/material.dart';

/// Палитра Verde «Liquid Forest Glass» — эстетика Apple Music iOS 18 и Spotify
/// в глубокой тёмно-зелёной и изумрудной палитре.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF050806);
  static const Color surface = Color(0xFF0A100D);
  static const Color surfaceRaised = Color(0xFF101914);
  static const Color surfaceHigh = Color(0xFF17241C);

  // Токены жидкого стекла и тёмного леса.
  static const Color forestDark = Color(0xFF0A3820);
  static const Color forestMid = Color(0xFF0F5430);
  static const Color glassSurface = Color(0xB8101914);
  static const Color glassBorder = Color(0x22FFFFFF);
  static const Color glassHighlight = Color(0x30FFFFFF);

  /// Тонкая граница вместо тяжёлых теней.
  static const Color stroke = Color(0x16FFFFFF);
  static const Color strokeSoft = Color(0x0EFFFFFF);

  static const Color accent = Color(0xFF1DB954);
  static const Color accentBright = Color(0xFF4AE88A);
  static const Color accentDeep = Color(0xFF0D8A47);

  static const Color text = Color(0xFFF2F7F4);
  static const Color textDim = Color(0xFFA3B3AA);
  static const Color textMuted = Color(0xFF6A7A71);

  static const Color warning = Color(0xFFF0C674);
  static const Color error = Color(0xFFFF6B6B);
  static const Color deleteRed = Color(0xFFFF6B6B);

  /// Зелёная подложка для чипов и выделенных строк.
  static Color accentSoft([double alpha = 0.16]) =>
      accent.withValues(alpha: alpha);

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentBright, accent, accentDeep],
  );

  static const LinearGradient forestHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF125A34), Color(0xFF09311C), Color(0xFF07150D)],
  );

  static const LinearGradient liquidGlassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x22FFFFFF), Color(0x06FFFFFF), Color(0x0A1DB954)],
  );

  /// Затемнение поверх размытой обложки в плеере.
  static const LinearGradient playerScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x99050806), Color(0xD8050806), Color(0xFA050806)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient cardSheen = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x244AE88A), Color(0x00050806)],
  );
}

/// Шаг сетки. Кратен 4, чтобы отступы не «плавали» между экранами.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double huge = 32;

  /// Отступ под плавающую навигацию + мини-плеер.
  static const double bottomInset = 176;

  /// Отступ для экранов без нижней навигации.
  static const double pageBottom = 32;
}

class AppRadii {
  AppRadii._();

  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
}

class AppDurations {
  AppDurations._();

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 360);
}

class AppShadows {
  AppShadows._();

  static List<BoxShadow> get card => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.42),
      blurRadius: 28,
      offset: const Offset(0, 14),
    ),
  ];

  static List<BoxShadow> get floatingBar => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.55),
      blurRadius: 32,
      spreadRadius: -4,
      offset: const Offset(0, 14),
    ),
    BoxShadow(
      color: AppColors.accent.withValues(alpha: 0.08),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get glow => [
    BoxShadow(
      color: AppColors.accent.withValues(alpha: 0.34),
      blurRadius: 28,
      spreadRadius: 1,
      offset: const Offset(0, 10),
    ),
  ];

  static List<BoxShadow> get artwork => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.6),
      blurRadius: 42,
      spreadRadius: -4,
      offset: const Offset(0, 24),
    ),
  ];

  static List<BoxShadow> get artworkPaused => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.35),
      blurRadius: 20,
      spreadRadius: -6,
      offset: const Offset(0, 10),
    ),
  ];
}
