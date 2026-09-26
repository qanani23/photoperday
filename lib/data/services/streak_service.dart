import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';

/// Immutable summary of the user's recorded streak metrics.
@immutable
class StreakSummary {
  const StreakSummary({
    required this.currentStreak,
    required this.longestStreak,
    required this.totalRecordedDays,
  });

  /// The number of consecutive calendar days ending TODAY for which the user has a recorded photo.
  /// If today has no photo, this is 0.
  final int currentStreak;

  /// The maximum number of consecutive calendar days containing a photo anywhere in the user's history
  /// (ending on or before today).
  final int longestStreak;

  /// The total count of distinct valid recorded days on or before today.
  final int totalRecordedDays;

  /// Empty summary for brand new users or zero recorded photos.
  static const StreakSummary zero = StreakSummary(
    currentStreak: 0,
    longestStreak: 0,
    totalRecordedDays: 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreakSummary &&
          runtimeType == other.runtimeType &&
          currentStreak == other.currentStreak &&
          longestStreak == other.longestStreak &&
          totalRecordedDays == other.totalRecordedDays;

  @override
  int get hashCode =>
      Object.hash(currentStreak, longestStreak, totalRecordedDays);

  @override
  String toString() =>
      'StreakSummary(current: $currentStreak, longest: $longestStreak, recorded: $totalRecordedDays)';
}

/// Domain service for calculating photo journaling streaks.
///
/// Rules:
/// - Uses local calendar dates ([DateKey]), never UTC timestamps.
/// - Current streak: Number of consecutive calendar days ending TODAY with a photo.
///   If today has no photo, current streak is 0.
/// - Longest streak: Maximum number of consecutive calendar days containing a photo
///   anywhere in history on or before today.
/// - Future dates are strictly excluded.
/// - Unique DateKeys are enforced defensively.
/// - Fully respects month, year, and leap-day boundaries via calendar arithmetic.
/// - Pure domain logic: zero disk/network I/O, does not modify photo entries.
class StreakService {
  StreakService._internal();

  /// Singleton instance of [StreakService].
  static final StreakService instance = StreakService._internal();

  /// Calculates a [StreakSummary] from the provided entries/keys or from
  /// [PersistentDailyPhotoStore.instance].
  ///
  /// [todayKey] or [todayDate] defines "today" for calculation (defaults to local today).
  StreakSummary calculateStreak({
    DateTime? todayDate,
    DateKey? todayKey,
    List<PhotoEntry>? entries,
    Iterable<DateKey>? dateKeys,
    PersistentDailyPhotoStore? store,
  }) {
    final effectiveTodayKey =
        todayKey ??
        (todayDate != null ? DateKey.fromDateTime(todayDate) : DateKey.today());

    // 1. Gather all candidate DateKeys
    final candidateKeys = <DateKey>[];
    if (dateKeys != null) {
      candidateKeys.addAll(dateKeys);
    } else if (entries != null) {
      candidateKeys.addAll(entries.map((e) => e.dateKey));
    } else {
      final effectiveStore = store ?? PersistentDailyPhotoStore.instance;
      candidateKeys.addAll(effectiveStore.allEntries.map((e) => e.dateKey));
    }

    // 2. Filter out future dates and deduplicate defensively
    final validKeys = <DateKey>{};
    for (final key in candidateKeys) {
      if (key.compareTo(effectiveTodayKey) <= 0) {
        validKeys.add(key);
      }
    }

    if (validKeys.isEmpty) {
      return StreakSummary.zero;
    }

    final totalRecordedDays = validKeys.length;

    // 3. Current streak: Consecutive days ending on effectiveTodayKey
    int currentStreak = 0;
    if (validKeys.contains(effectiveTodayKey)) {
      currentStreak = 1;
      var cursor = effectiveTodayKey.previousDay;
      while (validKeys.contains(cursor)) {
        currentStreak++;
        cursor = cursor.previousDay;
      }
    }

    // 4. Longest streak: Maximum consecutive day run in history
    final sortedKeys = validKeys.toList()..sort();
    int longestStreak = 1;
    int currentRun = 1;

    for (int i = 1; i < sortedKeys.length; i++) {
      final prev = sortedKeys[i - 1];
      final curr = sortedKeys[i];

      if (prev.nextDay == curr) {
        currentRun++;
        if (currentRun > longestStreak) {
          longestStreak = currentRun;
        }
      } else {
        currentRun = 1;
      }
    }

    return StreakSummary(
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      totalRecordedDays: totalRecordedDays,
    );
  }
}
