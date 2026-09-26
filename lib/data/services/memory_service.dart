import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';

/// Service responsible for discovering historical "On This Day" / "Memories"
/// from previous years that match the month and day of a target date.
///
/// Rules:
/// - Matches exact month and day (`entry.date.month == target.month && entry.date.day == target.day`).
/// - Strictly excludes current-year photos (`entry.date.year < target.year`).
/// - Strictly excludes future entries (`entry.dateKey <= DateKey.today()`).
/// - Leap-year safe: February 29 only matches actual February 29 entries from previous leap years.
/// - Deterministically sorted: Newest memory year first (e.g., 2025 before 2024).
/// - Pure domain logic: Read-only, no storage duplication, returns real [PhotoEntry] instances.
class MemoryService {
  MemoryService._internal();

  /// Singleton instance of [MemoryService].
  static final MemoryService instance = MemoryService._internal();

  /// Discovers all historical memories for the given [targetDate].
  ///
  /// If [sourceEntries] is provided, uses that list; otherwise fetches from
  /// [PersistentDailyPhotoStore.instance.allEntries].
  List<PhotoEntry> getMemoriesForDate(
    DateTime targetDate, {
    List<PhotoEntry>? sourceEntries,
    PersistentDailyPhotoStore? store,
  }) {
    final effectiveStore = store ?? PersistentDailyPhotoStore.instance;
    final entries = sourceEntries ?? effectiveStore.allEntries;
    final todayKey = DateKey.today();
    final targetMonth = targetDate.month;
    final targetDay = targetDate.day;
    final targetYear = targetDate.year;

    final memories = <PhotoEntry>[];

    for (final entry in entries) {
      // 1. Exclude future dates relative to real-world today
      if (entry.dateKey.compareTo(todayKey) > 0) {
        continue;
      }

      // 2. Exclude future dates relative to targetDate
      if (entry.date.year > targetYear) {
        continue;
      }

      // 3. Exclude current year (same year as targetDate)
      if (entry.date.year == targetYear) {
        continue;
      }

      // 4. Exact month and day matching
      // Note: If targetDate is Feb 29, only entries on Feb 29 match.
      // If targetDate is Feb 28, only entries on Feb 28 match (never Feb 29).
      if (entry.date.month == targetMonth && entry.date.day == targetDay) {
        memories.add(entry);
      }
    }

    // 5. Deterministic sorting: Newest memory year first (descending dateKey)
    memories.sort((a, b) => b.dateKey.compareTo(a.dateKey));

    return memories;
  }

  /// Returns the count of memories discovered for [targetDate].
  int getMemoryCountForDate(
    DateTime targetDate, {
    List<PhotoEntry>? sourceEntries,
    PersistentDailyPhotoStore? store,
  }) {
    return getMemoriesForDate(
      targetDate,
      sourceEntries: sourceEntries,
      store: store,
    ).length;
  }

  /// Calculates how many years ago a memory was captured relative to [targetDate].
  int getYearsAgo(DateTime memoryDate, DateTime targetDate) {
    final diff = targetDate.year - memoryDate.year;
    return diff > 0 ? diff : 0;
  }
}
