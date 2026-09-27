import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/streak_service.dart';

/// Immutable summary of the user's overall photo journaling statistics.
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
  });

  /// The total number of persisted photo entries on or before today.
  /// Because of the ONE PHOTO PER DAY rule, this equals [totalRecordedDays].
  final int totalPhotos;

  /// The number of unique calendar days containing a photo on or before today.
  final int totalRecordedDays;

  /// The current consecutive streak ending today (delegated to [StreakService]).
  final int currentStreak;

  /// The longest consecutive streak anywhere in history (delegated to [StreakService]).
  final int longestStreak;

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
    Object.hashAll(monthlyCountsForCurrentYear.keys),
    Object.hashAll(monthlyCountsForCurrentYear.values),
  );

  @override
  String toString() =>
      'StatisticsSummary(totalPhotos: $totalPhotos, recordedDays: $totalRecordedDays, '
      'currentStreak: $currentStreak, longestStreak: $longestStreak, '
      'first: $firstPhotoDate, latest: $latestPhotoDate, '
      'month: $currentMonthCount, year: $currentYearCount)';
}

/// Domain service for deriving calm, accurate statistics from photo journal records.
///
/// Rules:
/// - Authoritative source: [PersistentDailyPhotoStore] / provided DateKeys.
/// - Pure/read-only, synchronous, in-memory computation.
/// - Excludes future dates strictly.
/// - Operates defensively on unique [DateKey]s.
/// - Reuses [StreakService] for current and longest streak calculations.
/// - Supports deterministic testing via injected date keys and reference todayKey.
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

  /// Calculates a [StatisticsSummary] from the provided entries/keys or from
  /// [PersistentDailyPhotoStore.instance].
  ///
  /// [todayKey] or [todayDate] defines "today" for calculation (defaults to local today).
  StatisticsSummary calculateStatistics({
    DateTime? todayDate,
    DateKey? todayKey,
    List<PhotoEntry>? entries,
    Iterable<DateKey>? dateKeys,
    PersistentDailyPhotoStore? store,
    StreakService? streakService,
  }) {
    final effectiveTodayKey =
        todayKey ??
        (todayDate != null ? DateKey.fromDateTime(todayDate) : DateKey.today());

    final isFromStore = (dateKeys == null && entries == null);
    final effectiveStore = store ?? PersistentDailyPhotoStore.instance;

    if (isFromStore &&
        _memoizedSummary != null &&
        identical(_memoizedStore, effectiveStore) &&
        _memoizedStoreVersion == effectiveStore.version &&
        _memoizedTodayKey == effectiveTodayKey) {
      return _memoizedSummary!;
    }

    // 1. Gather candidate DateKeys
    final Iterable<DateKey> candidateKeys;
    if (dateKeys != null) {
      candidateKeys = dateKeys;
    } else if (entries != null) {
      candidateKeys = entries.map((e) => e.dateKey);
    } else {
      candidateKeys = effectiveStore.recordedDates;
    }

    // 2. Filter out future dates and deduplicate defensively
    final validKeys = <DateKey>{};
    for (final key in candidateKeys) {
      if (key.compareTo(effectiveTodayKey) <= 0) {
        validKeys.add(key);
      }
    }

    // 3. Delegate streak calculation to StreakService
    final effectiveStreakService = streakService ?? StreakService.instance;
    final streakSummary = effectiveStreakService.calculateStreak(
      todayKey: effectiveTodayKey,
      dateKeys: validKeys,
    );

    if (validKeys.isEmpty) {
      // Build 12-month zero-count map for current year
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
      );
      if (isFromStore) {
        _memoizedStore = effectiveStore;
        _memoizedStoreVersion = effectiveStore.version;
        _memoizedTodayKey = effectiveTodayKey;
        _memoizedSummary = summary;
      }
      return summary;
    }

    // 4. Sort valid keys to determine earliest and latest recorded dates
    final sortedKeys = validKeys.toList()..sort();
    final firstPhotoDate = sortedKeys.first;
    final latestPhotoDate = sortedKeys.last;

    // 5. Calculate current-month, current-year, and monthly breakdown
    int currentMonthCount = 0;
    int currentYearCount = 0;
    final monthlyCounts = <int, int>{};
    for (int m = 1; m <= 12; m++) {
      monthlyCounts[m] = 0;
    }

    for (final key in sortedKeys) {
      if (key.year == effectiveTodayKey.year) {
        currentYearCount++;
        monthlyCounts[key.month] = (monthlyCounts[key.month] ?? 0) + 1;
        if (key.month == effectiveTodayKey.month) {
          currentMonthCount++;
        }
      }
    }

    final summary = StatisticsSummary(
      totalPhotos: streakSummary.totalRecordedDays,
      totalRecordedDays: streakSummary.totalRecordedDays,
      currentStreak: streakSummary.currentStreak,
      longestStreak: streakSummary.longestStreak,
      firstPhotoDate: firstPhotoDate,
      latestPhotoDate: latestPhotoDate,
      currentMonthCount: currentMonthCount,
      currentYearCount: currentYearCount,
      monthlyCountsForCurrentYear: monthlyCounts,
    );

    if (isFromStore) {
      _memoizedStore = effectiveStore;
      _memoizedStoreVersion = effectiveStore.version;
      _memoizedTodayKey = effectiveTodayKey;
      _memoizedSummary = summary;
    }

    return summary;
  }
}
