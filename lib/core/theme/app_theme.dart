import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_palette.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';

/// App theme configurations matching the calm, warm aesthetic of Photo a Day.
abstract final class AppTheme {
  static ThemeData get lightTheme => themeForPalette(AppColors.current);

  static ThemeData get darkTheme => themeForPalette(AppPalettes.dariaRed);

  static ThemeData themeForPalette(AppPalette palette) {
    final isDark = palette.isDark;
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      dividerColor: palette.border,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: palette.textPrimary,
        onPrimary: palette.primaryButtonForeground,
        secondary: palette.accent,
        onSecondary: palette.accentForeground,
        error: const Color(0xFFBA1A1A),
        onError: Colors.white,
        surface: palette.surface,
        onSurface: palette.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: palette.textPrimary),
        titleTextStyle: AppTypography.appTitle.copyWith(
          color: palette.textPrimary,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.card,
          side: BorderSide(color: palette.border, width: 0.8),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.dialogRadius,
          side: BorderSide(color: palette.border, width: 0.8),
        ),
        titleTextStyle: TextStyle(
          fontSize: 18.0,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14.0,
          color: palette.textSecondary,
          height: 1.45,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: 0.8,
        space: 1.0,
      ),
      textTheme: TextTheme(
        headlineMedium: AppTypography.appTitle.copyWith(
          color: palette.textPrimary,
        ),
        titleMedium: AppTypography.sectionTitle.copyWith(
          color: palette.textPrimary,
        ),
        bodyMedium: AppTypography.body.copyWith(color: palette.textPrimary),
        bodySmall: AppTypography.caption.copyWith(color: palette.textMuted),
        labelSmall: AppTypography.appTagline.copyWith(color: palette.textMuted),
      ),
    );
  }
}
