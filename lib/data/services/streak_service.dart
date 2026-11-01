import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';

/// Semantic state of the photo diary streak.
enum StreakCloudState {
  /// Zero recorded photos exist.
  notConnected,

  /// Zero photos exist on or before today.
  noSyncedPhotos,

  /// The streak is active (ends today or yesterday).
  active,

  /// The most recent photo is older than yesterday.
  ended,
}

/// Represents a single consecutive run of photo dates.
@immutable
class StreakRun {
  final DateKey startDate;
  final DateKey endDate;
  final int length;

  const StreakRun({
    required this.startDate,
    required this.endDate,
    required this.length,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreakRun &&
          runtimeType == other.runtimeType &&
          startDate == other.startDate &&
          endDate == other.endDate &&
          length == other.length;

  @override
  int get hashCode => Object.hash(startDate, endDate, length);

  @override
  String toString() => 'StreakRun($startDate to $endDate: $length days)';
}

/// Immutable summary of the user's algorithmic streak metrics.
@immutable
class StreakSummary {
  const StreakSummary({
    required this.currentStreak,
    required this.longestStreak,
    required this.totalRecordedDays,
    this.cloudState = StreakCloudState.notConnected,
    this.isCurrentStreakActive = false,
    this.currentStreakStartDate,
    this.currentStreakEndDate,
    this.endedStreaks = const [],
    this.endedStreakCount = 0,
    this.streakCount = 0,
    this.longestGapDays = 0,
    this.runs = const [],
  });

  /// The number of consecutive calendar days in the current active run (ending today or yesterday).
  /// If the streak is ended, this is 0.
  final int currentStreak;

  /// The maximum number of consecutive calendar days in any run in history.
  final int longestStreak;

  /// The total count of distinct valid recorded days on or before today.
  final int totalRecordedDays;

  /// Semantic state of the streak.
  final StreakCloudState cloudState;

  /// Whether the current streak is actively ongoing (ends today or yesterday).
  final bool isCurrentStreakActive;

  /// Start date of current active streak run (null if no active streak).
  final DateKey? currentStreakStartDate;

  /// End date of current active streak run (null if no active streak).
  final DateKey? currentStreakEndDate;

  /// List of ended (completed) streak runs.
  final List<StreakRun> endedStreaks;

  /// Number of ended (completed) streak runs.
  final int endedStreakCount;

  /// Total count of distinct streak runs across history.
  final int streakCount;

  /// Maximum gap (in missing calendar days) between any two recorded photo days.
  final int longestGapDays;

  /// All consecutive runs chronologically ordered.
  final List<StreakRun> runs;

  /// Total count of photo days (alias for totalRecordedDays).
  int get totalSynchronizedDays => totalRecordedDays;

  /// Alias for whether the current streak is active.
  bool get isActive => isCurrentStreakActive;

  /// Alias for the active streak start date.
  DateKey? get startDate => currentStreakStartDate;

  /// Alias for the active streak end date.
  DateKey? get endDate => currentStreakEndDate;

  /// Empty summary for brand new users or zero recorded photos.
  static const StreakSummary zero = StreakSummary(
    currentStreak: 0,
    longestStreak: 0,
    totalRecordedDays: 0,
    cloudState: StreakCloudState.notConnected,
    isCurrentStreakActive: false,
    currentStreakStartDate: null,
    currentStreakEndDate: null,
    endedStreaks: [],
    endedStreakCount: 0,
    streakCount: 0,
    longestGapDays: 0,
    runs: [],
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreakSummary &&
          runtimeType == other.runtimeType &&
          currentStreak == other.currentStreak &&
          longestStreak == other.longestStreak &&
          totalRecordedDays == other.totalRecordedDays &&
          cloudState == other.cloudState &&
          isCurrentStreakActive == other.isCurrentStreakActive &&
          currentStreakStartDate == other.currentStreakStartDate &&
          currentStreakEndDate == other.currentStreakEndDate &&
          endedStreakCount == other.endedStreakCount &&
          longestGapDays == other.longestGapDays;

  @override
  int get hashCode => Object.hash(
    currentStreak,
    longestStreak,
    totalRecordedDays,
    cloudState,
    isCurrentStreakActive,
    currentStreakStartDate,
    currentStreakEndDate,
    endedStreakCount,
    longestGapDays,
  );

  @override
  String toString() =>
      'StreakSummary(current: $currentStreak, longest: $longestStreak, recorded: $totalRecordedDays, state: $cloudState, active: $isCurrentStreakActive)';
}

/// Domain service for calculating photo journaling streaks exclusively from local diary photos.
///
/// Principles:
/// 1. PHOTO DATE DATA IS THE SOLE SOURCE OF TRUTH.
/// 2. Streaks are DERIVED algorithmically from valid local diary photo dates.
/// 3. Never stores authoritative streak counters (e.g. `streak = 17`).
/// 4. 100% offline and local: zero dependency on cloud sync or account identity.
/// 5. Truthful streak states:
///    - If most recent date is today: active run ending today.
///    - If most recent date is yesterday: active run ending yesterday (grace period).
///    - If older than yesterday: streak is ended (currentStreak = 0).
class StreakService {
  StreakService._internal();

  /// Singleton instance of [StreakService].
  static final StreakService instance = StreakService._internal();

  int? _memoizedStoreVersion;
  DateKey? _memoizedTodayKey;
  PersistentDailyPhotoStore? _memoizedStore;
  StreakSummary? _memoizedSummary;

  /// Clears internal memoization cache.
  void clearCache() {
    _memoizedStoreVersion = null;
    _memoizedTodayKey = null;
    _memoizedStore = null;
    _memoizedSummary = null;
  }

  /// Calculates the exact number of missing calendar days between two [DateKey]s.
  /// Uses UTC to avoid daylight saving offset issues.
  static int calendarDaysBetween(DateKey a, DateKey b) {
    final dtA = DateTime.utc(a.year, a.month, a.day);
    final dtB = DateTime.utc(b.year, b.month, b.day);
    return dtB.difference(dtA).inDays;
  }

  /// Extracts the set of valid recorded local diary photo dates on or before [maxDate].
  Set<DateKey> getLocalPhotoDates({
    PersistentDailyPhotoStore? store,
    DateKey? maxDate,
  }) {
    final effectiveStore = store ?? PersistentDailyPhotoStore.instance;
    final effectiveMaxDate = maxDate ?? DateKey.today();
    final result = <DateKey>{};
    for (final entry in effectiveStore.allEntries) {
      if (entry.dateKey.compareTo(effectiveMaxDate) <= 0) {
        result.add(entry.dateKey);
      }
    }
    return result;
  }

  /// Calculates a [StreakSummary] from the provided dates/entries or from
  /// the active [PersistentDailyPhotoStore].
  StreakSummary calculateStreak({
    DateTime? todayDate,
    DateKey? todayKey,
    DateTime? referenceDate,
    Iterable<DateTime>? dates,
    List<PhotoEntry>? entries,
    Iterable<DateKey>? dateKeys,
    PersistentDailyPhotoStore? store,
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

    // 1. Gather candidate DateKeys
    final Iterable<DateKey> candidateKeys;

    if (effectiveDateKeys != null) {
      candidateKeys = effectiveDateKeys;
    } else if (entries != null) {
      candidateKeys = entries.map((e) => e.dateKey);
    } else {
      candidateKeys = effectiveStore.allEntries.map((e) => e.dateKey);
    }

    // 2. Filter out future dates and eliminate duplicate DateKeys
    final validKeys = <DateKey>{};
    for (final key in candidateKeys) {
      if (key.compareTo(effectiveTodayKey) <= 0) {
        validKeys.add(key);
      }
    }

    if (validKeys.isEmpty) {
      const summary = StreakSummary.zero;
      if (isFromStore) {
        _memoizedStore = effectiveStore;
        _memoizedStoreVersion = effectiveStore.version;
        _memoizedTodayKey = effectiveTodayKey;
        _memoizedSummary = summary;
      }
      return summary;
    }

    final totalRecordedDays = validKeys.length;

    // 3. Sort dates chronologically
    final sortedKeys = validKeys.toList()..sort();

    // 4. Group consecutive dates into runs
    final runs = <StreakRun>[];
    DateKey runStart = sortedKeys.first;
    DateKey runEnd = sortedKeys.first;
    int runLength = 1;

    for (int i = 1; i < sortedKeys.length; i++) {
      final curr = sortedKeys[i];
      if (runEnd.nextDay == curr) {
        runEnd = curr;
        runLength++;
      } else {
        runs.add(
          StreakRun(startDate: runStart, endDate: runEnd, length: runLength),
        );
        runStart = curr;
        runEnd = curr;
        runLength = 1;
      }
    }
    runs.add(
      StreakRun(startDate: runStart, endDate: runEnd, length: runLength),
    );

    // 5. Calculate longest streak
    int longestStreak = 0;
    for (final run in runs) {
      if (run.length > longestStreak) {
        longestStreak = run.length;
      }
    }

    // 6. Calculate longest gap between photo days
    int longestGapDays = 0;
    for (int i = 1; i < sortedKeys.length; i++) {
      final gap = calendarDaysBetween(sortedKeys[i - 1], sortedKeys[i]) - 1;
      if (gap > longestGapDays) {
        longestGapDays = gap;
      }
    }

    // 7. Determine current run and ended runs
    final lastRun = runs.last;
    final latestDate = lastRun.endDate;
    final yesterdayKey = effectiveTodayKey.previousDay;

    int currentStreak = 0;
    bool isCurrentStreakActive = false;
    DateKey? currentStreakStartDate;
    DateKey? currentStreakEndDate;
    List<StreakRun> endedStreaks;

    final bool isConnecting = allowYesterdayActive
        ? (latestDate == effectiveTodayKey || latestDate == yesterdayKey)
        : (latestDate == effectiveTodayKey);

    StreakCloudState resolvedCloudState;
    if (isConnecting) {
      currentStreak = lastRun.length;
      isCurrentStreakActive = true;
      currentStreakStartDate = lastRun.startDate;
      currentStreakEndDate = lastRun.endDate;
      resolvedCloudState = StreakCloudState.active;
      endedStreaks = runs.sublist(0, runs.length - 1);
    } else {
      currentStreak = 0;
      isCurrentStreakActive = false;
      resolvedCloudState = StreakCloudState.ended;
      endedStreaks = List.unmodifiable(runs);
    }

    final summary = StreakSummary(
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      totalRecordedDays: totalRecordedDays,
      cloudState: resolvedCloudState,
      isCurrentStreakActive: isCurrentStreakActive,
      currentStreakStartDate: currentStreakStartDate,
      currentStreakEndDate: currentStreakEndDate,
      endedStreaks: List.unmodifiable(endedStreaks),
      endedStreakCount: endedStreaks.length,
      streakCount: runs.length,
      longestGapDays: longestGapDays,
      runs: List.unmodifiable(runs),
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
