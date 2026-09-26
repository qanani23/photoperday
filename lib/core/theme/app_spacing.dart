/// Centralized spacing scale matching the reference's layout density.
abstract final class AppSpacing {
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;

  // Specific semantic spacings
  static const double pageHorizontal = 18.0;
  static const double gridGap = 6.0;
  static const double headerGap = 12.0;
  static const double sectionBottomGap = 8.0;
  static const double sectionTopGap = 18.0;

  // Scroll clearance over floating bottom dock
  static const double dockClearance = 110.0;
  static const double dockClearanceExtended = 120.0;
}
