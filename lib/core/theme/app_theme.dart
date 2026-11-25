import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';

/// Тёмная Material 3 тема Verde «Deep Forest 2.0».
///
/// Палитра и радиусы живут в [AppColors]/[AppRadii], а здесь собирается
/// единый ThemeData: типографика Manrope, стеклянные поверхности,
/// пилюли-кнопки и спокойные состояния.
class AppTheme {
  AppTheme._();

  static const String fontFamily = 'Manrope';

  // Совместимые алиасы: старые экраны продолжают работать, но получают
  // новые цвета из дизайн-токенов.
  static const Color accentGreen = AppColors.accent;
  static const Color accentBright = AppColors.accentBright;
  static const Color background = AppColors.background;
  static const Color surface = AppColors.surface;
  static const Color surfaceContainer = AppColors.surfaceRaised;
  static const Color surfaceHigh = AppColors.surfaceHigh;
  static const Color textDim = AppColors.textDim;
  static const Color text = AppColors.text;
  static const Color error = AppColors.error;
  static const Color warning = AppColors.warning;

  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
    );
    final scheme = base.copyWith(
      primary: AppColors.accent,
      onPrimary: Colors.black,
      secondary: AppColors.accentBright,
      onSecondary: Colors.black,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      surfaceContainerHighest: AppColors.surfaceHigh,
      surfaceTint: Colors.transparent,
      outline: AppColors.stroke,
      outlineVariant: AppColors.stroke,
      error: AppColors.error,
      onError: Colors.black,
    );

    final textTheme = _textTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      cardColor: AppColors.surfaceRaised,
      dividerColor: AppColors.stroke,
      disabledColor: AppColors.textMuted,
      hintColor: AppColors.textMuted,
      focusColor: AppColors.accentSoft(0.2),
      hoverColor: Colors.white.withValues(alpha: 0.04),
      splashColor: AppColors.accentSoft(0.12),
      highlightColor: Colors.white.withValues(alpha: 0.03),
      applyElevationOverlayColor: false,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.text),
        actionsIconTheme: IconThemeData(color: AppColors.textDim),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.background,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: AppColors.text,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceRaised,
        indicatorColor: AppColors.accentSoft(0.18),
        surfaceTintColor: Colors.transparent,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: fontFamily,
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.text : AppColors.textDim,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? AppColors.accentBright : AppColors.textDim,
          );
        }),
      ),
      iconTheme: const IconThemeData(color: AppColors.text, size: 24),
      sliderTheme: const SliderThemeData(
        trackHeight: 4,
        thumbColor: AppColors.accentBright,
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.surfaceHigh,
        overlayColor: Color(0x331DB954),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 18),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 14,
        ),
        hintStyle: const TextStyle(
          fontFamily: fontFamily,
          color: AppColors.textMuted,
          fontSize: 14,
        ),
        labelStyle: const TextStyle(
          fontFamily: fontFamily,
          color: AppColors.textDim,
        ),
        prefixIconColor: AppColors.textDim,
        suffixIconColor: AppColors.textDim,
        border: _inputBorder(AppColors.stroke, 1),
        enabledBorder: _inputBorder(AppColors.stroke, 1),
        focusedBorder: _inputBorder(AppColors.accent, 1.4),
        errorBorder: _inputBorder(AppColors.error, 1.2),
        focusedErrorBorder: _inputBorder(AppColors.error, 1.4),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColors.surfaceHigh,
          disabledForegroundColor: AppColors.textMuted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.stroke),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentBright,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.lgAll,
          side: BorderSide(color: AppColors.stroke),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textDim,
        textColor: AppColors.text,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        dragHandleColor: AppColors.stroke,
        modalBarrierColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.xlAll),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: AppColors.text,
        ),
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          height: 1.45,
          color: AppColors.textDim,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: AppColors.text,
          fontSize: 13.5,
        ),
        actionTextColor: AppColors.accentBright,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentBright,
        linearTrackColor: AppColors.surfaceHigh,
        circularTrackColor: AppColors.surfaceHigh,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.stroke,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceRaised,
        selectedColor: AppColors.accentSoft(0.18),
        disabledColor: AppColors.surface,
        side: const BorderSide(color: AppColors.stroke),
        shape: const StadiumBorder(),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        labelStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textDim,
        ),
        secondaryLabelStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.accentBright,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? AppColors.accentBright
                : AppColors.textDim;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? AppColors.accentSoft(0.16)
                : AppColors.surfaceRaised;
          }),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.stroke),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.lgAll),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: AppRadii.smAll,
          border: Border.all(color: AppColors.stroke),
        ),
        textStyle: const TextStyle(
          fontFamily: fontFamily,
          color: AppColors.text,
          fontSize: 12,
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          color: AppColors.text,
          fontSize: 14,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.accentBright,
        selectionColor: AppColors.accentSoft(0.3),
        selectionHandleColor: AppColors.accent,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: AppRadii.mdAll,
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _textTheme() {
    const family = fontFamily;
    const primary = AppColors.text;
    const secondary = AppColors.textDim;

    return const TextTheme(
      displayLarge: TextStyle(
        fontFamily: family,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        height: 1.12,
        color: primary,
      ),
      displayMedium: TextStyle(
        fontFamily: family,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        height: 1.15,
        color: primary,
      ),
      displaySmall: TextStyle(
        fontFamily: family,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.18,
        color: primary,
      ),
      headlineLarge: TextStyle(
        fontFamily: family,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.2,
        color: primary,
      ),
      headlineMedium: TextStyle(
        fontFamily: family,
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.2,
        color: primary,
      ),
      headlineSmall: TextStyle(
        fontFamily: family,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.25,
        color: primary,
      ),
      titleLarge: TextStyle(
        fontFamily: family,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.25,
        color: primary,
      ),
      titleMedium: TextStyle(
        fontFamily: family,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        height: 1.3,
        color: primary,
      ),
      titleSmall: TextStyle(
        fontFamily: family,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: primary,
      ),
      bodyLarge: TextStyle(
        fontFamily: family,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: primary,
      ),
      bodyMedium: TextStyle(
        fontFamily: family,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: primary,
      ),
      bodySmall: TextStyle(
        fontFamily: family,
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: secondary,
      ),
      labelLarge: TextStyle(
        fontFamily: family,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        height: 1.2,
        color: primary,
      ),
      labelMedium: TextStyle(
        fontFamily: family,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        height: 1.2,
        color: secondary,
      ),
      labelSmall: TextStyle(
        fontFamily: family,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        height: 1.2,
        color: secondary,
      ),
    );
  }
}
