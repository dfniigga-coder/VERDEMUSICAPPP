import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Тёмная Material 3 тема с зелёным акцентом (в стиле Spotify).
class AppTheme {
  AppTheme._();

  static const Color accentGreen = Color(0xFF1DB954);
  static const Color background = Color(0xFF0A0B0D);
  static const Color surface = Color(0xFF121417);
  static const Color surfaceContainer = Color(0xFF1A1D21);
  static const Color textDim = Color(0xFF9AA0A3);

  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: accentGreen,
      brightness: Brightness.dark,
    );
    final scheme = base.copyWith(
      primary: accentGreen,
      onPrimary: Colors.black,
      secondary: const Color(0xFF9CF0B2),
      surface: surface,
      onSurface: const Color(0xFFE9ECEA),
      surfaceContainerHighest: surfaceContainer,
      error: const Color(0xFFE57373),
      onError: Colors.black,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Color(0xFF0A0B0D),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: Color(0xFFE9ECEA),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0E1013),
        indicatorColor: accentGreen.withValues(alpha: 0.18),
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? const Color(0xFFE9ECEA) : textDim,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? const Color(0xFFE9ECEA) : textDim,
          );
        }),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 3,
        thumbColor: accentGreen,
        activeTrackColor: accentGreen,
        inactiveTrackColor: Color(0xFF2A2D31),
        overlayColor: Color(0x331DB954),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF16191C),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: const TextStyle(color: textDim),
        labelStyle: const TextStyle(color: textDim),
        prefixIconColor: textDim,
        suffixIconColor: textDim,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accentGreen, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentGreen,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: const CardThemeData(
        color: surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: const Color(0xFFE9ECEA),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF15181B),
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        useSafeArea: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF17191C),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Color(0xFFE9ECEA),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF1C1F23),
        contentTextStyle: TextStyle(color: Color(0xFFE9ECEA), fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accentGreen,
        linearTrackColor: Color(0xFF2A2D31),
      ),
      dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.06)),
    );
  }
}
