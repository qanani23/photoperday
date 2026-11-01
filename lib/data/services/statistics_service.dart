import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/streak_service.dart';

/// Immutable summary of the user's algorithmic statistics derived from the synchronized diary.
@immutable
class StatisticsSummary {
  const StatisticsSummary({
    required this.totalPhotos,
    required this.totalRecordedDays,
    required this.currentStreak,
    required this.longestStreak,
    required this.firstPhotoDate,
    required this.latestPhotoDate,
    required this.currentMonthCount,
    required this.currentYearCount,
    required this.monthlyCountsForCurrentYear,
    this.endedStreakCount = 0,
    this.streakCount = 0,
    this.averageStreakLength = 0.0,
    this.longestGapDays = 0,
    this.mostActiveMonth,
    this.mostActiveMonthCount = 0,
    this.yearlyCounts = const {},
    this.weeklyCounts = const {},
    this.weekdayCounts = const {},
    this.totalMissedDays = 0,
    this.isCurrentStreakActive = false,
  });

  /// The total number of synchronized photo entries on or before today.
  final int totalPhotos;

  /// The number of unique calendar days containing a photo on or before today.
  final int totalRecordedDays;

  /// Total synchronized photo days (alias for totalRecordedDays).
  int get totalSynchronizedDays => totalRecordedDays;

  /// The current consecutive streak ending today or yesterday (derived from [StreakService]).
  final int currentStreak;

  /// The longest consecutive streak anywhere in history (derived from [StreakService]).
  final int longestStreak;

  /// Whether the current streak is actively ongoing.
  final bool isCurrentStreakActive;

  /// Number of completed/ended streak runs.
  final int endedStreakCount;

  /// Total count of distinct streak runs across history.
  final int streakCount;

  /// Average length of streak runs.
  final double averageStreakLength;

  /// Longest gap (in missing calendar days) between photo entries.
  final int longestGapDays;

  /// Most active month in the current year (1..12), or null if no photos.
  final int? mostActiveMonth;

  /// Photo count in the most active month.
  final int mostActiveMonthCount;

  /// The earliest recorded photo date (or null if no photos exist).
  final DateKey? firstPhotoDate;

  /// The latest recorded photo date on or before today (or null if no photos exist).
  final DateKey? latestPhotoDate;

  /// Number of photos recorded in the local calendar month containing today.
  final int currentMonthCount;

  /// Number of photos recorded in the local calendar year containing today.
  final int currentYearCount;

  /// Map of month numbers (1..12) to photo counts for the current calendar year.
  final Map<int, int> monthlyCountsForCurrentYear;

  /// Map of calendar years to total photo counts for each year.
  final Map<int, int> yearlyCounts;

  /// Map of ISO week representations ('YYYY-Wxx') to photo counts.
  final Map<String, int> weeklyCounts;

  /// Map of ISO weekday numbers (1 = Monday, 7 = Sunday) to photo counts.
  final Map<int, int> weekdayCounts;

  /// Total missing days between first photo date and today.
  final int totalMissedDays;

  /// Whether the user has recorded at least one photo.
  bool get hasPhotos => totalRecordedDays > 0;

  /// Formats a [DateKey] as a calm, human-readable date string (e.g. "March 15, 2026"),
  /// or "Not available" if null.
  static String formatDate(DateKey? dateKey) {
    if (dateKey == null) return 'Not available';
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final monthName = months[dateKey.month - 1];
    return '$monthName ${dateKey.day}, ${dateKey.year}';
  }

  /// Empty summary for brand new users or zero recorded photos.
  static const StatisticsSummary zero = StatisticsSummary(
    totalPhotos: 0,
    totalRecordedDays: 0,
    currentStreak: 0,
    longestStreak: 0,
    firstPhotoDate: null,
    latestPhotoDate: null,
    currentMonthCount: 0,
    currentYearCount: 0,
    monthlyCountsForCurrentYear: {},
    endedStreakCount: 0,
    streakCount: 0,
    averageStreakLength: 0.0,
    longestGapDays: 0,
    mostActiveMonth: null,
    mostActiveMonthCount: 0,
    yearlyCounts: {},
    weeklyCounts: {},
    weekdayCounts: {},
    totalMissedDays: 0,
    isCurrentStreakActive: false,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatisticsSummary &&
          runtimeType == other.runtimeType &&
          totalPhotos == other.totalPhotos &&
          totalRecordedDays == other.totalRecordedDays &&
          currentStreak == other.currentStreak &&
          longestStreak == other.longestStreak &&
          firstPhotoDate == other.firstPhotoDate &&
          latestPhotoDate == other.latestPhotoDate &&
          currentMonthCount == other.currentMonthCount &&
          currentYearCount == other.currentYearCount &&
          endedStreakCount == other.endedStreakCount &&
          longestGapDays == other.longestGapDays &&
          mapEquals(
            monthlyCountsForCurrentYear,
            other.monthlyCountsForCurrentYear,
          );

  @override
  int get hashCode => Object.hash(
    totalPhotos,
    totalRecordedDays,
    currentStreak,
    longestStreak,
    firstPhotoDate,
    latestPhotoDate,
    currentMonthCount,
    currentYearCount,
    endedStreakCount,
    longestGapDays,
  );

  @override
  String toString() =>
      'StatisticsSummary(totalPhotos: $totalPhotos, recordedDays: $totalRecordedDays, '
      'currentStreak: $currentStreak, longestStreak: $longestStreak, '
      'endedStreaks: $endedStreakCount, avgStreak: $averageStreakLength, longestGap: $longestGapDays)';
}

/// Domain service for deriving calm, accurate statistics algorithmically from synchronized diary data (Milestone 44).
///
/// Principles:
/// - Authoritative source: successfully synchronized photo dates.
/// - Pure/read-only in-memory computation.
/// - Never stores mutable counter databases.
/// - Reuses [StreakService] for streak run calculations.
class StatisticsService {
  StatisticsService._internal();

  /// Singleton instance of [StatisticsService].
  static final StatisticsService instance = StatisticsService._internal();

  int? _memoizedStoreVersion;
  DateKey? _memoizedTodayKey;
  PersistentDailyPhotoStore? _memoizedStore;
  StatisticsSummary? _memoizedSummary;

  /// Clears internal memoization cache.
  void clearCache() {
    _memoizedStoreVersion = null;
    _memoizedTodayKey = null;
    _memoizedStore = null;
    _memoizedSummary = null;
  }

  /// Calculates an ISO week identifier string for a given [DateKey] (e.g. '2026-W11').
  static String formatIsoWeek(DateKey key) {
    final dt = DateTime(key.year, key.month, key.day);
    // Find Thursday in current week
    final dayOfWeek = dt.weekday; // 1 = Monday, 7 = Sunday
    final thursday = dt.add(Duration(days: 4 - dayOfWeek));
    final year = thursday.year;
    final firstDayOfYear = DateTime(year, 1, 1);
    final dayOfYear = thursday.difference(firstDayOfYear).inDays + 1;
    final weekNumber = ((dayOfYear - 1) / 7).floor() + 1;
    return '$year-W${weekNumber.toString().padLeft(2, '0')}';
  }

  /// Calculates a [StatisticsSummary] from the provided entries/keys or from
  /// the active [PersistentDailyPhotoStore].
  StatisticsSummary calculateStatistics({
    DateTime? todayDate,
    DateKey? todayKey,
    DateTime? referenceDate,
    Iterable<DateTime>? dates,
    List<PhotoEntry>? entries,
    Iterable<DateKey>? dateKeys,
    PersistentDailyPhotoStore? store,
    StreakService? streakService,
    bool allowYesterdayActive = true,
  }) {
    final effectiveTodayKey =
        todayKey ??
        (referenceDate != null
            ? DateKey.fromDateTime(referenceDate)
            : (todayDate != null
                  ? DateKey.fromDateTime(todayDate)
                  : DateKey.today()));

    final effectiveDateKeys = dateKeys ?? dates?.map(DateKey.fromDateTime);

    final isFromStore = (effectiveDateKeys == null && entries == null);
    final effectiveStore = store ?? PersistentDailyPhotoStore.instance;

    if (isFromStore &&
        _memoizedSummary != null &&
        identical(_memoizedStore, effectiveStore) &&
        _memoizedStoreVersion == effectiveStore.version &&
        _memoizedTodayKey == effectiveTodayKey) {
      return _memoizedSummary!;
    }

    final effectiveStreakService = streakService ?? StreakService.instance;

    // 1. Calculate streak metrics using StreakService
    final streakSummary = effectiveStreakService.calculateStreak(
      todayKey: effectiveTodayKey,
      entries: entries,
      dateKeys: effectiveDateKeys,
      store: effectiveStore,
      allowYesterdayActive: allowYesterdayActive,
    );

    // 2. Resolve the candidate dates evaluated by the streak calculation
    final Iterable<DateKey> candidateKeys;
    if (effectiveDateKeys != null) {
      candidateKeys = effectiveDateKeys;
    } else if (entries != null) {
      candidateKeys = entries.map((e) => e.dateKey);
    } else {
      candidateKeys = effectiveStore.allEntries.map((e) => e.dateKey);
    }

    // 3. Filter out future dates and deduplicate defensively
    final validKeys = <DateKey>{};
    for (final key in candidateKeys) {
      if (key.compareTo(effectiveTodayKey) <= 0) {
        validKeys.add(key);
      }
    }

    if (validKeys.isEmpty) {
      final emptyMonths = <int, int>{};
      for (int m = 1; m <= 12; m++) {
        emptyMonths[m] = 0;
      }
      final summary = StatisticsSummary(
        totalPhotos: 0,
        totalRecordedDays: 0,
        currentStreak: 0,
        longestStreak: 0,
        firstPhotoDate: null,
        latestPhotoDate: null,
        currentMonthCount: 0,
        currentYearCount: 0,
        monthlyCountsForCurrentYear: emptyMonths,
        endedStreakCount: 0,
        streakCount: 0,
        averageStreakLength: 0.0,
        longestGapDays: 0,
        mostActiveMonth: null,
        mostActiveMonthCount: 0,
        yearlyCounts: const {},
        weeklyCounts: const {},
        weekdayCounts: const {},
        totalMissedDays: 0,
        isCurrentStreakActive: false,
      );
      if (isFromStore) {
        _memoizedStore = effectiveStore;
        _memoizedStoreVersion = effectiveStore.version;
        _memoizedTodayKey = effectiveTodayKey;
        _memoizedSummary = summary;
      }
      return summary;
    }

    // 4. Sort valid keys chronologically
    final sortedKeys = validKeys.toList()..sort();
    final firstPhotoDate = sortedKeys.first;
    final latestPhotoDate = sortedKeys.last;

    // 5. Aggregate yearly, monthly, weekly, and weekday counts
    int currentMonthCount = 0;
    int currentYearCount = 0;
    final monthlyCounts = <int, int>{};
    for (int m = 1; m <= 12; m++) {
      monthlyCounts[m] = 0;
    }
    final yearlyCounts = <int, int>{};
    final weeklyCounts = <String, int>{};
    final weekdayCounts = <int, int>{};
    for (int w = 1; w <= 7; w++) {
      weekdayCounts[w] = 0;
    }

    for (final key in sortedKeys) {
      // Yearly count
      yearlyCounts[key.year] = (yearlyCounts[key.year] ?? 0) + 1;

      // Current year monthly counts
      if (key.year == effectiveTodayKey.year) {
        currentYearCount++;
        monthlyCounts[key.month] = (monthlyCounts[key.month] ?? 0) + 1;
        if (key.month == effectiveTodayKey.month) {
          currentMonthCount++;
        }
      }

      // Weekly count
      final weekKey = formatIsoWeek(key);
      weeklyCounts[weekKey] = (weeklyCounts[weekKey] ?? 0) + 1;

      // Weekday count (1 = Mon, 7 = Sun)
      final dt = DateTime(key.year, key.month, key.day);
      weekdayCounts[dt.weekday] = (weekdayCounts[dt.weekday] ?? 0) + 1;
    }

    // 6. Find most active month in current year
    int? mostActiveMonth;
    int mostActiveMonthCount = 0;
    for (int m = 1; m <= 12; m++) {
      final count = monthlyCounts[m] ?? 0;
      if (count > mostActiveMonthCount) {
        mostActiveMonthCount = count;
        mostActiveMonth = m;
      }
    }

    // 7. Calculate average streak length
    final double avgStreak = streakSummary.runs.isEmpty
        ? 0.0
        : validKeys.length / streakSummary.runs.length;

    // 8. Calculate total missed days between first photo date and today
    final totalSpanDays =
        StreakService.calendarDaysBetween(firstPhotoDate, effectiveTodayKey) +
        1;
    final totalMissedDays = (totalSpanDays - validKeys.length).clamp(0, 999999);

    final int resolvedTotalPhotos;
    if (entries != null) {
      resolvedTotalPhotos = entries
          .where((e) => e.dateKey.compareTo(effectiveTodayKey) <= 0)
          .length;
    } else if (effectiveDateKeys != null) {
      resolvedTotalPhotos = validKeys.length;
    } else {
      resolvedTotalPhotos = effectiveStore.allEntries
          .where((e) => e.dateKey.compareTo(effectiveTodayKey) <= 0)
          .length;
    }

    final summary = StatisticsSummary(
      totalPhotos: resolvedTotalPhotos,
      totalRecordedDays: streakSummary.totalRecordedDays,
      currentStreak: streakSummary.currentStreak,
      longestStreak: streakSummary.longestStreak,
      firstPhotoDate: firstPhotoDate,
      latestPhotoDate: latestPhotoDate,
      currentMonthCount: currentMonthCount,
      currentYearCount: currentYearCount,
      monthlyCountsForCurrentYear: monthlyCounts,
      endedStreakCount: streakSummary.endedStreakCount,
      streakCount: streakSummary.streakCount,
      averageStreakLength: double.parse(avgStreak.toStringAsFixed(1)),
      longestGapDays: streakSummary.longestGapDays,
      mostActiveMonth: mostActiveMonth,
      mostActiveMonthCount: mostActiveMonthCount,
      yearlyCounts: Map.unmodifiable(yearlyCounts),
      weeklyCounts: Map.unmodifiable(weeklyCounts),
      weekdayCounts: Map.unmodifiable(weekdayCounts),
      totalMissedDays: totalMissedDays,
      isCurrentStreakActive: streakSummary.isCurrentStreakActive,
    );

    if (isFromStore) {
      _memoizedStore = effectiveStore;
      _memoizedStoreVersion = effectiveStore.version;
      _memoizedTodayKey = effectiveTodayKey;
      _memoizedSummary = summary;
    }

    return summary;
  }

  /// Convenience method to compute statistics from active store.
  StatisticsSummary getStatistics({
    PersistentDailyPhotoStore? store,
    DateKey? todayKey,
    DateTime? referenceDate,
  }) => calculateStatistics(
    store: store,
    todayKey: todayKey,
    referenceDate: referenceDate,
  );

  /// Convenience method to compute statistics directly from a list of [DateTime]s.
  StatisticsSummary calculateStatisticsFromDates({
    required List<DateTime> dates,
    DateTime? referenceDate,
  }) => calculateStatistics(dates: dates, referenceDate: referenceDate);
}
