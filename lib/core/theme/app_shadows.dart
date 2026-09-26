import 'package:flutter/material.dart';

/// Centralized shadow definitions providing calm, subtle ambient elevation.
abstract final class AppShadows {
  /// Soft ambient shadow for the floating bottom navigation dock
  static const List<BoxShadow> bottomDock = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 24,
      spreadRadius: 0,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 8,
      spreadRadius: 0,
      offset: Offset(0, 2),
    ),
  ];

  /// Subtle shadow for the header logo badge
  static const List<BoxShadow> logoBadge = [
    BoxShadow(color: Color(0x20000000), blurRadius: 8, offset: Offset(0, 3)),
  ];

  /// Card / surface shadow
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4)),
  ];
}
