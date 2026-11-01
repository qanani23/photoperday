/// Centralized application constants and configurations.
abstract final class AppConstants {
  static const String appName = 'Daria';
  static const String appVersion = '1.0.0';

  // Route Names
  static const String initialRoute = '/';
  static const String onboardingRoute = '/onboarding';
  static const String photoDetailRoute = '/photo-detail';
  static const String diaryRoute = '/diary';
  static const String swipeDaysRoute = '/swipe-days';
  static const String memoriesRoute = '/memories';
  static const String statisticsRoute = '/statistics';
  static const String settingsRoute = '/settings';
  static const String themeRoute = '/theme';
  static const String aboutRoute = '/about';
  static const String privacyRoute = '/privacy';
  static const String termsRoute = '/terms';
  static const String fullCalendarRoute = '/full-calendar';

  // Brand Assets
  static const String dariaLogoAsset = 'assets/images/icons/dariaicon.png';

  // Onboarding Assets
  static const String onboardingImage1 = 'assets/images/onboarding/img1.png';
  static const String onboardingImage2 = 'assets/images/onboarding/img4.png';
  static const String onboardingImage3 = 'assets/images/onboarding/img6.jpg';

  /// Practical threshold in bytes for local photo storage warning (500 MB).
  ///
  /// When app-managed photo storage exceeds this threshold, a calm warning
  /// informs the user that photo storage is getting large.
  static const int photoStorageWarningThresholdBytes = 500 * 1024 * 1024;
}
