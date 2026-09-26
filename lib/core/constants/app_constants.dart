/// Centralized application constants and configurations.
abstract final class AppConstants {
  static const String appName = 'Photo a Day';
  static const String appVersion = '1.0.0';

  // Route Names
  static const String initialRoute = '/';
  static const String photoDetailRoute = '/photo-detail';
  static const String diaryRoute = '/diary';
  static const String swipeDaysRoute = '/swipe-days';
  static const String memoriesRoute = '/memories';
  static const String statisticsRoute = '/statistics';

  /// Practical threshold in bytes for local photo storage warning (500 MB).
  ///
  /// When app-managed photo storage exceeds this threshold, a calm warning
  /// informs the user that photo storage is getting large.
  static const int photoStorageWarningThresholdBytes = 500 * 1024 * 1024;
}
