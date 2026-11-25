import 'package:flutter/material.dart';

/// Палитра Verde «Deep Forest 2.0».
///
/// Тёмный графит с зелёным подтоном, три уровня поверхностей и мягкий
/// акцент вместо чистого чёрного. Все экраны используют эти токены,
/// чтобы редизайн оставался цельным.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF070A08);
  static const Color surface = Color(0xFF0D120F);
  static const Color surfaceRaised = Color(0xFF131A16);
  static const Color surfaceHigh = Color(0xFF1A231D);

  /// Тонкая граница вместо тяжёлых теней.
  static const Color stroke = Color(0x12FFFFFF);

  static const Color accent = Color(0xFF1DB954);
  static const Color accentBright = Color(0xFF3DE27F);
  static const Color accentDeep = Color(0xFF0E9F52);

  static const Color text = Color(0xFFEDF3EF);
  static const Color textDim = Color(0xFF9AA79F);
  static const Color textMuted = Color(0xFF66736B);

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

  /// Затемнение поверх размытой обложки в плеере.
  static const LinearGradient playerScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xB3070A08), Color(0xF2070A08), Color(0xFF070A08)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient cardSheen = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x1F3DE27F), Color(0x00070A08)],
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
  static const double bottomInset = 168;

  /// Отступ для экранов без нижней навигации.
  static const double pageBottom = 32;
}

class AppRadii {
  AppRadii._();

  static const double sm = 10;
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
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);
}

class AppShadows {
  AppShadows._();

  static List<BoxShadow> get card => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.35),
      blurRadius: 24,
      offset: const Offset(0, 12),
    ),
  ];

  static List<BoxShadow> get glow => [
    BoxShadow(
      color: AppColors.accent.withValues(alpha: 0.28),
      blurRadius: 26,
      spreadRadius: 1,
      offset: const Offset(0, 10),
    ),
  ];

  static List<BoxShadow> get artwork => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.5),
      blurRadius: 36,
      offset: const Offset(0, 20),
    ),
  ];
}
