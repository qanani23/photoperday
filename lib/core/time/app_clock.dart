import 'package:flutter/foundation.dart';

/// Centralized provider for the application's clock and current time.
///
/// Encapsulates calls to [DateTime.now], enabling deterministic time control
/// for testing time-sensitive features such as midnight rollovers, leap years,
/// streaks, and calendar boundaries.
class AppClock {
  AppClock._();

  static DateTime Function()? _testClock;

  /// Injects a custom clock supplier for deterministic testing.
  @visibleForTesting
  static void setTestClock(DateTime Function()? clock) {
    _testClock = clock;
  }

  /// Sets a static test time.
  @visibleForTesting
  static void setFixedTime(DateTime fixedTime) {
    _testClock = () => fixedTime;
  }

  /// Resets the clock to use the real system time.
  @visibleForTesting
  static void resetTestClock() {
    _testClock = null;
  }

  /// Returns the current [DateTime], or the test clock time if overridden.
  static DateTime now() {
    return _testClock != null ? _testClock!() : DateTime.now();
  }

  /// Returns the current local date at midnight (00:00:00.000).
  static DateTime todayMidnight() {
    final current = now();
    return DateTime(current.year, current.month, current.day);
  }
}
