import 'package:flutter/material.dart';

/// Centralized responsive breakpoint scale and maximum width constraints.
///
/// Designed to provide optimal space utilization across:
/// - Mobile screens and narrow desktop windows (< 600px)
/// - Medium / Tablet / compact desktop screens (600px - 1024px)
/// - Standard laptop and 1366px desktop displays (1024px - 1440px)
/// - Full HD 1920px monitors and ultra-wide displays (>= 1440px)
abstract final class AppBreakpoints {
  /// Mobile breakpoint boundary (< 600px)
  static const double mobile = 600.0;

  /// Compact desktop / tablet breakpoint boundary (600px - 1024px)
  static const double tablet = 1024.0;

  /// Large desktop breakpoint boundary (1024px - 1440px)
  static const double desktop = 1440.0;

  /// Standard two-column threshold for screens with side-by-side details
  static const double twoColumnThreshold = 800.0;

  /// Multi-column calendar threshold for 3-column quarterly layout
  static const double threeColumnCalendarThreshold = 1150.0;

  /// Multi-column calendar threshold for 2-column layout
  static const double twoColumnCalendarThreshold = 700.0;

  /// Global maximum content width on ultra-wide screens to maintain
  /// comfortable reading line lengths and balanced photo composition.
  static const double maxContentWidth = 1360.0;

  /// Maximum content width for settings and preferences forms
  /// to ensure form controls and switches remain comfortably readable.
  static const double maxSettingsWidth = 1000.0;

  /// Maximum content width for single-column visual diary lists.
  static const double maxDiaryWidth = 1080.0;

  /// Maximum width for floating bottom navigation dock.
  static const double maxBottomDockWidth = 440.0;

  /// Returns whether the current window width is considered compact / mobile.
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobile;

  /// Returns whether the current window width is medium / tablet.
  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= mobile && w < tablet;
  }

  /// Returns whether the current window width is standard desktop (>= 1024px).
  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tablet;

  /// Returns whether the current window width is wide / ultra-wide (>= 1440px).
  static bool isWideDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktop;
}
