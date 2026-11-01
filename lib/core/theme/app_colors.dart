import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_palette.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';

/// Centralized dynamic color palette tokens for Photo a Day.
///
/// Delegates all themeable tokens to the actively selected [AppPalette] in [AppThemeService].
abstract final class AppColors {
  /// The active dynamic palette instance.
  static AppPalette get current => AppThemeService.instance.currentPalette;

  // Main background
  static Color get background => current.background;

  // Surfaces
  static Color get surface => current.surface;
  static Color get surfaceSubtle => current.surfaceSubtle;
  static Color get surfaceMuted => current.surfaceMuted;
  static Color get surfaceDark => current.surfaceDark;

  // Typography
  static Color get textPrimary => current.textPrimary;
  static Color get textSecondary => current.textSecondary;
  static Color get textMuted => current.textMuted;
  static Color get textOnMedia => current.textOnMedia;

  // Accent & Highlights
  static Color get accent => current.accent;
  static Color get accentLight => current.accentLight;
  static Color get accentForeground => current.accentForeground;

  // Primary Buttons
  static Color get primaryButtonBackground => current.primaryButtonBackground;
  static Color get primaryButtonForeground => current.primaryButtonForeground;

  // Borders & Dividers
  static Color get border => current.border;
  static Color get borderSubtle => current.borderSubtle;

  // Floating Navigation Dock
  static Color get dockBackground => current.dockBackground;
  static Color get dockBorder => current.dockBorder;
  static Color get dockCapturePill => current.dockCapturePill;

  // Overlays
  static const Color photoOverlay = Color(0x40000000);

  // Subtle Calendar & Placeholder Tones
  static Color get textMutedSubtle => current.textMuted.withValues(alpha: 0.6);
  static Color get surfaceDarkFallback => current.surfaceDark;
  static Color get placeholderGradientStart => current.surfaceSubtle;
  static Color get placeholderGradientEnd => current.surfaceMuted;

  // Profile Status & Metric Accents
  static const Color statusActiveGreen = Color(0xFF4CAF50);
  static Color get statDaysGreen =>
      current.isDark || current.id == 'daria_red_light'
      ? current.accent
      : const Color(0xFF6A7F60);
  static Color get statStreakOrange =>
      current.isDark || current.id == 'daria_red_light'
      ? current.accent
      : const Color(0xFFC86D51);
  static Color get statIconPurple =>
      current.isDark || current.id == 'daria_red_light'
      ? current.accent
      : const Color(0xFF6B5B95);
  static Color get statIconBrown =>
      current.isDark || current.id == 'daria_red_light'
      ? current.accent
      : const Color(0xFF8A6552);
  static Color get statIconForest =>
      current.isDark ? const Color(0xFF66BB6A) : const Color(0xFF4A7C59);
  static Color get statIconBlueGrey =>
      current.isDark ? current.textSecondary : const Color(0xFF5E6B7C);
  static Color get statIconNeutral =>
      current.isDark ? current.textMuted : const Color(0xFF888888);

  // Status & Feedback
  static const Color error = Color(0xFFD32F2F);
  static const Color warning = Color(0xFFE69500);
}
