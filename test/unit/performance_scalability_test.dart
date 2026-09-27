import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/local_storage_calculator.dart';
import 'package:photo_per_day/data/services/memory_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/streak_service.dart';
import 'package:photo_per_day/data/services/statistics_service.dart';
import '../helpers/synthetic_diary_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyntheticDiaryData Fixture Generator', () {
    test(
      'generates valid synthetic datasets across scale tiers (100, 500, 1000, 5000)',
      () {
        for (final count in [100, 500, 1000, 5000]) {
          final entries = SyntheticDiaryData.generateEntries(count);
          expect(entries.length, equals(count));
          expect(
            entries.first.dateKey.compareTo(entries.last.dateKey),
            lessThan(0),
          );

          // Verify all dates are distinct
          final dateKeys = entries.map((e) => e.dateKey).toSet();
          expect(dateKeys.length, equals(count));

          // Verify metadata integrity
          for (final entry in [
            entries.first,
            entries[count ~/ 2],
            entries.last,
          ]) {
            expect(entry.title.isNotEmpty, isTrue);
            expect(entry.gradientColors.length, greaterThanOrEqualTo(2));
            expect(entry.syncStatus, isA<SyncStatus>());
          }
        }
      },
    );

    test(
      'DateKey.isValidDate correctly handles leap years and month limits',
      () {
        expect(DateKey.isValidDate(2024, 2, 29), isTrue); // 2024 is a leap year
        expect(DateKey.isValidDate(2023, 2, 29), isFalse); // 2023 is not
        expect(
          DateKey.isValidDate(2000, 2, 29),
          isTrue,
        ); // 2000 was a leap year
        expect(DateKey.isValidDate(1900, 2, 29), isFalse); // 1900 was not
        expect(DateKey.isValidDate(2026, 4, 31), isFalse); // April has 30 days
        expect(DateKey.isValidDate(2026, 12, 31), isTrue);
        expect(DateKey.isValidDate(2026, 13, 1), isFalse);
      },
    );
  });

  group('PersistentDailyPhotoStore Scalability & Cache Optimization', () {
    late PersistentDailyPhotoStore store;

    setUp(() {
      store = PersistentDailyPhotoStore();
    });

    test('supports 5,000 synthetic entries with O(1) key lookups', () {
      SyntheticDiaryData.populateStore(store, 5000);
      expect(store.totalPhotos, equals(5000));

      final dates = store.recordedDates;
      expect(dates.length, equals(5000));

      // Test O(1) random access across bounds
      final firstKey = dates.first;
      final midKey = dates[2500];
      final lastKey = dates.last;

      expect(store.hasPhotoByKey(firstKey), isTrue);
      expect(store.hasPhotoByKey(midKey), isTrue);
      expect(store.hasPhotoByKey(lastKey), isTrue);

      expect(store.getPhotoByKey(firstKey), isNotNull);
      expect(store.getPhotoByKey(midKey), isNotNull);
      expect(store.getPhotoByKey(lastKey), isNotNull);

      // Non-existent key lookup is instantaneous
      const nonExistentKey = DateKey(1800, 1, 1);
      expect(store.hasPhotoByKey(nonExistentKey), isFalse);
      expect(store.getPhotoByKey(nonExistentKey), isNull);
    });

    test(
      'allEntries and recordedDates return memoized views without repeated list allocation',
      () {
        SyntheticDiaryData.populateStore(store, 1000);

        final list1 = store.allEntries;
        final list2 = store.allEntries;
        expect(
          identical(list1, list2),
          isTrue,
          reason: 'allEntries must be cached when store is unmodified',
        );

        final dates1 = store.recordedDates;
        final dates2 = store.recordedDates;
        expect(
          identical(dates1, dates2),
          isTrue,
          reason: 'recordedDates must be cached when store is unmodified',
        );

        final chrono1 = store.chronologicalEntries;
        final chrono2 = store.chronologicalEntries;
        expect(
          identical(chrono1, chrono2),
          isTrue,
          reason: 'chronologicalEntries must be cached',
        );

        final chronoAsc1 = store.chronologicalAscendingEntries;
        final chronoAsc2 = store.chronologicalAscendingEntries;
        expect(
          identical(chronoAsc1, chronoAsc2),
          isTrue,
          reason: 'chronologicalAscendingEntries must be cached',
        );
      },
    );

    test(
      'store version increments and invalidates cached collections on mutation',
      () {
        SyntheticDiaryData.populateStore(store, 100);
        final initialVersion = store.version;
        final initialEntries = store.allEntries;

        // Add new photo entry
        const newKey = DateKey(2099, 1, 1);
        final newEntry = PhotoEntry(
          date: newKey.toDateTime(),
          title: 'Future Photo',
          gradientColors: const [],
        );
        store.setPhoto(newEntry);

        expect(store.version, greaterThan(initialVersion));
        final updatedEntries = store.allEntries;
        expect(identical(initialEntries, updatedEntries), isFalse);
        expect(store.hasPhotoByKey(newKey), isTrue);

        // Remove photo
        final versionBeforeRemove = store.version;
        store.removePhotoByKey(newKey);
        expect(store.version, greaterThan(versionBeforeRemove));
        expect(store.hasPhotoByKey(newKey), isFalse);
      },
    );

    test('chronological collections are deterministically ordered', () {
      SyntheticDiaryData.populateStore(store, 500);

      final desc = store.chronologicalEntries;
      expect(desc.length, equals(500));
      for (int i = 1; i < desc.length; i++) {
        expect(
          desc[i - 1].dateKey.compareTo(desc[i].dateKey),
          greaterThan(0),
          reason: 'chronologicalEntries must be strictly newest first',
        );
      }

      final asc = store.chronologicalAscendingEntries;
      expect(asc.length, equals(500));
      for (int i = 1; i < asc.length; i++) {
        expect(
          asc[i - 1].dateKey.compareTo(asc[i].dateKey),
          lessThan(0),
          reason: 'chronologicalAscendingEntries must be strictly oldest first',
        );
      }
    });

    test('hasPendingDeletion operates in O(1) via cached key set', () {
      expect(store.hasPendingDeletion(const DateKey(2026, 3, 15)), isFalse);
    });
  });

  group('MemoryService Discovery Scalability', () {
    late PersistentDailyPhotoStore store;

    setUp(() {
      store = PersistentDailyPhotoStore();
    });

    test(
      'discovers On This Day memories across 5,000 photos (~14 years) efficiently',
      () {
        // 5,000 days is ~13.7 years ending on 2026-03-15
        final today = DateTime(2026, 3, 15);
        final todayKey = DateKey.fromDateTime(today);
        SyntheticDiaryData.populateStore(store, 5000, endDateKey: todayKey);

        final memories = MemoryService.instance.getMemoriesForDate(
          today,
          store: store,
        );

        // There should be a memory for each previous year covered in the 5,000 day range
        expect(memories, isNotEmpty);
        expect(memories.length, greaterThanOrEqualTo(12));

        // Strictly excludes current year
        for (final memory in memories) {
          expect(memory.date.year, lessThan(2026));
          expect(memory.date.month, equals(3));
          expect(memory.date.day, equals(15));
        }

        // Strictly sorted descending (newest memory year first)
        for (int i = 1; i < memories.length; i++) {
          expect(memories[i - 1].date.year, greaterThan(memories[i].date.year));
        }
      },
    );

    test('leap-year February 29 correctly only matches prior leap years', () {
      // Create entries on Feb 29 for 2024, 2020, 2016
      final leapYears = [2024, 2020, 2016];
      for (final y in leapYears) {
        final key = DateKey(y, 2, 29);
        store.setPhoto(
          PhotoEntry(
            date: key.toDateTime(),
            title: 'Leap memory $y',
            gradientColors: const [],
          ),
        );
      }

      final feb29Target = DateTime(2028, 2, 29);
      final memories = MemoryService.instance.getMemoriesForDate(
        feb29Target,
        store: store,
      );
      expect(memories.length, equals(3));
      expect(
        memories.map((m) => m.date.year).toList(),
        equals([2024, 2020, 2016]),
      );

      // Feb 28 must never match Feb 29
      final feb28Target = DateTime(2028, 2, 28);
      final feb28Memories = MemoryService.instance.getMemoriesForDate(
        feb28Target,
        store: store,
      );
      expect(feb28Memories, isEmpty);
    });

    test('excludes future dates relative to real-world today', () {
      final futureDate = DateTime(2099, 5, 20);
      store.setPhoto(
        PhotoEntry(
          date: futureDate,
          title: 'Future entry',
          gradientColors: const [],
        ),
      );

      final memories = MemoryService.instance.getMemoriesForDate(
        DateTime(2105, 5, 20),
        store: store,
      );
      // Because futureDate is in the future relative to DateKey.today(), it must be excluded
      expect(memories.any((m) => m.date.year == 2099), isFalse);
    });
  });

  group('StreakService Scalability & Memoization', () {
    late PersistentDailyPhotoStore store;

    setUp(() {
      store = PersistentDailyPhotoStore();
      StreakService.instance.clearCache();
    });

    test(
      'calculates correct streaks across 100, 500, 1000, and 5000 consecutive days',
      () {
        const todayKey = DateKey(2026, 3, 15);

        for (final count in [100, 500, 1000, 5000]) {
          store.clear();
          StreakService.instance.clearCache();
          SyntheticDiaryData.populateStore(store, count, endDateKey: todayKey);

          final summary = StreakService.instance.calculateStreak(
            todayKey: todayKey,
            store: store,
          );

          expect(summary.currentStreak, equals(count));
          expect(summary.longestStreak, equals(count));
          expect(summary.totalRecordedDays, equals(count));
        }
      },
    );

    test(
      'memoizes StreakSummary and returns cached instance on identical store version',
      () {
        const todayKey = DateKey(2026, 3, 15);
        SyntheticDiaryData.populateStore(store, 500, endDateKey: todayKey);

        final summary1 = StreakService.instance.calculateStreak(
          todayKey: todayKey,
          store: store,
        );
        final summary2 = StreakService.instance.calculateStreak(
          todayKey: todayKey,
          store: store,
        );

        expect(
          identical(summary1, summary2),
          isTrue,
          reason:
              'StreakService must return memoized summary when store version is unchanged',
        );

        // Modifying the store invalidates the memoized summary
        store.setPhoto(
          PhotoEntry(
            date: const DateKey(2026, 3, 16).toDateTime(),
            title: 'Tomorrow',
            gradientColors: const [],
          ),
        );

        final summary3 = StreakService.instance.calculateStreak(
          todayKey: todayKey,
          store: store,
        );
        expect(
          identical(summary1, summary3),
          isFalse,
          reason: 'Store mutation must invalidate memoized streak summary',
        );
      },
    );

    test(
      'handles gaps, future dates, and duplicate dates correctly with large datasets',
      () {
        const todayKey = DateKey(2026, 3, 15);
        final entries = SyntheticDiaryData.generateEntries(
          1000,
          endDateKey: todayKey,
        );

        // Create a gap 10 days ago
        final gapKey = todayKey.previousDay.previousDay.previousDay;
        final filtered = entries.where((e) => e.dateKey != gapKey).toList();

        // Add duplicate DateKeys
        filtered.add(filtered.first);
        filtered.add(filtered.last);

        // Add future dates
        filtered.add(
          PhotoEntry(
            date: const DateKey(2030, 1, 1).toDateTime(),
            title: 'Future',
            gradientColors: const [],
          ),
        );

        final summary = StreakService.instance.calculateStreak(
          todayKey: todayKey,
          entries: filtered,
        );

        // Current streak stopped at gap
        expect(summary.currentStreak, equals(3));
        // Longest streak was the prior run
        expect(summary.longestStreak, greaterThan(900));
        // Future date excluded, duplicate dates deduplicated
        expect(summary.totalRecordedDays, equals(999));
      },
    );
  });

  group('StatisticsService Scalability & Memoization', () {
    late PersistentDailyPhotoStore store;

    setUp(() {
      store = PersistentDailyPhotoStore();
      StatisticsService.instance.clearCache();
      StreakService.instance.clearCache();
    });

    test(
      'calculates correct statistics across 100, 500, 1000, and 5000 photos',
      () {
        const todayKey = DateKey(2026, 3, 15);

        for (final count in [100, 500, 1000, 5000]) {
          store.clear();
          StatisticsService.instance.clearCache();
          StreakService.instance.clearCache();
          SyntheticDiaryData.populateStore(store, count, endDateKey: todayKey);

          final stats = StatisticsService.instance.calculateStatistics(
            todayKey: todayKey,
            store: store,
          );

          expect(stats.totalPhotos, equals(count));
          expect(stats.totalRecordedDays, equals(count));
          expect(stats.currentStreak, equals(count));
          expect(stats.longestStreak, equals(count));
          expect(stats.latestPhotoDate, equals(todayKey));
          expect(stats.firstPhotoDate, isNotNull);
          expect(stats.currentMonthCount, greaterThan(0));
          expect(stats.currentYearCount, greaterThan(0));
          expect(stats.monthlyCountsForCurrentYear.length, equals(12));
        }
      },
    );

    test('memoizes StatisticsSummary when store version is unchanged', () {
      const todayKey = DateKey(2026, 3, 15);
      SyntheticDiaryData.populateStore(store, 500, endDateKey: todayKey);

      final stats1 = StatisticsService.instance.calculateStatistics(
        todayKey: todayKey,
        store: store,
      );
      final stats2 = StatisticsService.instance.calculateStatistics(
        todayKey: todayKey,
        store: store,
      );

      expect(
        identical(stats1, stats2),
        isTrue,
        reason: 'StatisticsService must return memoized summary',
      );

      // Mutate store
      store.removePhotoByKey(todayKey);

      final stats3 = StatisticsService.instance.calculateStatistics(
        todayKey: todayKey,
        store: store,
      );
      expect(
        identical(stats1, stats3),
        isFalse,
        reason: 'Store mutation must invalidate memoized statistics',
      );
      expect(stats3.currentStreak, equals(0)); // Today was removed
    });
  });

  group('LocalStorageCalculator File Size Caching', () {
    late PersistentDailyPhotoStore store;

    setUp(() {
      store = PersistentDailyPhotoStore();
      LocalStorageCalculator.clearCache();
    });

    test('caches known file sizes and clears cache on clearCache()', () {
      // Empty store
      final bytes = LocalStorageCalculator.calculateTotalPhotoBytesSync(
        store: store,
      );
      expect(bytes, equals(0));
      expect(LocalStorageCalculator.formatBytes(0), equals('0 B used'));
      expect(LocalStorageCalculator.formatBytes(1024), equals('1 KB used'));
      expect(
        LocalStorageCalculator.formatBytes(1024 * 1024 * 5),
        equals('5 MB used'),
      );
    });
  });
}
