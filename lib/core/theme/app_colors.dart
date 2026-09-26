import 'package:flutter/material.dart';

/// Centralized color palette extracted from the reference design.
///
/// Features a calm, warm linen background, subtle neutral surfaces,
/// refined typography shades, and a distinctive caramel/gold accent.
abstract final class AppColors {
  // Main background (warm linen / soft off-white)
  static const Color background = Color(0xFFFAF7F5);

  // Surfaces
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSubtle = Color(0xFFF0ECE9);
  static const Color surfaceMuted = Color(0xFFE8E3DF);
  static const Color surfaceDark = Color(0xFF1E242B);

  // Typography
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF55504D);
  static const Color textMuted = Color(0xFF8E8A87);
  static const Color textOnMedia = Color(0xFFFFFFFF);

  // Accent & Highlights (Caramel / Gold for today's indicator ring)
  static const Color accent = Color(0xFFC4975F);
  static const Color accentLight = Color(0xFFF8F2EB);

  // Borders & Dividers
  static const Color border = Color(0xFFEBE6E1);
  static const Color borderSubtle = Color(0xFFF3EFEB);

  // Floating Navigation Dock
  static const Color dockBackground = Color(0xFFFFFFFF);
  static const Color dockBorder = Color(0xFFEAE5E0);
  static const Color dockCapturePill = Color(0xFFF2ECE7);

  // Overlays
  static const Color photoOverlay = Color(0x40000000);

  // Subtle Calendar & Placeholder Tones
  static const Color textMutedSubtle = Color(0xFFBCB7B3);
  static const Color surfaceDarkFallback = Color(0xFF4A4E4D);
  static const Color placeholderGradientStart = Color(0xFFE8E2DD);
  static const Color placeholderGradientEnd = Color(0xFFDDD6CF);

  // Profile Status & Metric Accents
  static const Color statusActiveGreen = Color(0xFF4CAF50);
  static const Color statDaysGreen = Color(0xFF6A7F60);
  static const Color statStreakOrange = Color(0xFFC86D51);
  static const Color statIconPurple = Color(0xFF6B5B95);
  static const Color statIconBrown = Color(0xFF8A6552);
  static const Color statIconForest = Color(0xFF4A7C59);
  static const Color statIconBlueGrey = Color(0xFF5E6B7C);
  static const Color statIconNeutral = Color(0xFF888888);

  // Status & Feedback
  static const Color error = Color(0xFFD32F2F);
  static const Color warning = Color(0xFFE69500);
}
