import 'package:flutter/material.dart';

/// Centralized corner radius definitions matching the reference image.
abstract final class AppRadii {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 13.0; // Calendar cells
  static const double lg = 16.0; // App icon & cards
  static const double xl = 22.0;
  static const double dialog = 20.0; // Modal & confirmation dialogs
  static const double sheet = 24.0; // Modal bottom sheets
  static const double dock = 34.0; // Floating bottom dock
  static const double pill = 999.0; // Circular buttons, badges

  // Border radius objects for convenience
  static const BorderRadius cell = BorderRadius.all(Radius.circular(md));
  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius dialogRadius = BorderRadius.all(
    Radius.circular(dialog),
  );
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
  static const BorderRadius iconBadge = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius bottomDock = BorderRadius.all(
    Radius.circular(dock),
  );
  static const BorderRadius roundedPill = BorderRadius.all(
    Radius.circular(pill),
  );
}
