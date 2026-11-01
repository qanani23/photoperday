import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';

/// Centralized typography definitions reproducing the reference hierarchy.
abstract final class AppTypography {
  /// App header title ("Photo a Day")
  static TextStyle get appTitle => TextStyle(
    fontSize: 20.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
  );

  /// Header uppercase tagline ("CAPTURE YOUR LIFE,\nONE PHOTO AT A TIME")
  static TextStyle get appTagline => TextStyle(
    fontSize: 9.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    height: 1.25,
    color: AppColors.textMuted,
  );

  /// Subtitle under primary screen headers (Today, Profile)
  static TextStyle get screenSubtitle => TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  /// Month section headers ("March 2026", "February 2026")
  static TextStyle get sectionTitle => TextStyle(
    fontSize: 15.5,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  /// Number inside photo calendar cells
  static const TextStyle cellNumberPhoto = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    shadows: [
      Shadow(offset: Offset(0, 1), blurRadius: 3, color: Color(0x99000000)),
    ],
  );

  /// Number inside empty date blocks (e.g. 20..31)
  static TextStyle get cellNumberEmpty => TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  /// Number inside today's ring indicator
  static TextStyle get cellNumberToday => TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  /// Small labels under header action buttons ("Explore >", "Me")
  static TextStyle get actionLabel => TextStyle(
    fontSize: 10.0,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: -0.1,
  );

  /// Bottom navigation bar labels
  static TextStyle get navLabel => TextStyle(
    fontSize: 11.0,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  /// Body text
  static TextStyle get body => TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  /// Caption text
  static TextStyle get caption => TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );
}
