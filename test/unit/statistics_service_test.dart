import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/statistics_service.dart';
import 'package:photo_per_day/data/services/streak_service.dart';

void main() {
  group('Milestone 32 — StatisticsService Domain Tests', () {
    const today = DateKey(2026, 3, 20);

    test('1. Empty dataset -> all 0s, null dates, empty state', () {
      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: [],
      );

      expect(summary.totalPhotos, 0);
      expect(summary.totalRecordedDays, 0);
      expect(summary.currentStreak, 0);
      expect(summary.longestStreak, 0);
      expect(summary.firstPhotoDate, isNull);
      expect(summary.latestPhotoDate, isNull);
      expect(summary.currentMonthCount, 0);
      expect(summary.currentYearCount, 0);
      expect(summary.hasPhotos, isFalse);
      expect(
        StatisticsSummary.formatDate(summary.firstPhotoDate),
        'Not available',
      );
      expect(
        StatisticsSummary.formatDate(summary.latestPhotoDate),
        'Not available',
      );

      // 12 months in current year are all 0
      for (int m = 1; m <= 12; m++) {
        expect(summary.monthlyCountsForCurrentYear[m], 0);
      }
    });

    test('2. Single photo today -> counts, streak, dates match', () {
      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: [today],
      );

      expect(summary.totalPhotos, 1);
      expect(summary.totalRecordedDays, 1);
      expect(summary.currentStreak, 1);
      expect(summary.longestStreak, 1);
      expect(summary.firstPhotoDate, today);
      expect(summary.latestPhotoDate, today);
      expect(summary.currentMonthCount, 1);
      expect(summary.currentYearCount, 1);
      expect(summary.hasPhotos, isTrue);
      expect(summary.monthlyCountsForCurrentYear[3], 1);
      expect(summary.monthlyCountsForCurrentYear[1], 0);
      expect(
        StatisticsSummary.formatDate(summary.firstPhotoDate),
        'March 20, 2026',
      );
      expect(
        StatisticsSummary.formatDate(summary.latestPhotoDate),
        'March 20, 2026',
      );
    });

    test('3. Multiple unique photos -> calculated accurately', () {
      final dateKeys = [
        const DateKey(2026, 3, 1),
        const DateKey(2026, 3, 5),
        const DateKey(2026, 3, 10),
        const DateKey(2026, 3, 15),
      ];

      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: dateKeys,
      );

      expect(summary.totalPhotos, 4);
      expect(summary.totalRecordedDays, 4);
      expect(summary.firstPhotoDate, const DateKey(2026, 3, 1));
      expect(summary.latestPhotoDate, const DateKey(2026, 3, 15));
      expect(summary.currentMonthCount, 4);
      expect(summary.currentYearCount, 4);
    });

    test('4. Duplicate DateKeys are not double-counted', () {
      final dateKeys = [
        const DateKey(2026, 3, 10),
        const DateKey(2026, 3, 10),
        const DateKey(2026, 3, 20),
        const DateKey(2026, 3, 20),
        const DateKey(2026, 3, 20),
      ];

      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: dateKeys,
      );

      expect(summary.totalPhotos, 2);
      expect(summary.totalRecordedDays, 2);
      expect(summary.currentMonthCount, 2);
      expect(summary.currentYearCount, 2);
      expect(summary.monthlyCountsForCurrentYear[3], 2);
    });

    test('5. Future dates are excluded', () {
      final dateKeys = [
        const DateKey(2026, 3, 19),
        const DateKey(2026, 3, 20),
        const DateKey(2026, 3, 21), // future
        const DateKey(2026, 4, 1), // future
        const DateKey(2027, 1, 1), // future
      ];

      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: dateKeys,
      );

      expect(summary.totalPhotos, 2);
      expect(summary.totalRecordedDays, 2);
      expect(summary.currentStreak, 2);
      expect(summary.firstPhotoDate, const DateKey(2026, 3, 19));
      expect(summary.latestPhotoDate, const DateKey(2026, 3, 20));
      expect(summary.currentMonthCount, 2);
      expect(summary.currentYearCount, 2);
      expect(summary.monthlyCountsForCurrentYear[4], 0);
    });

    test('6. First photo date finds earliest recorded date in history', () {
      final dateKeys = [
        const DateKey(2024, 5, 12),
        const DateKey(2025, 11, 28),
        const DateKey(2026, 1, 3),
        const DateKey(2026, 3, 20),
      ];

      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: dateKeys,
      );

      expect(summary.firstPhotoDate, const DateKey(2024, 5, 12));
      expect(
        StatisticsSummary.formatDate(summary.firstPhotoDate),
        'May 12, 2024',
      );
    });

    test('7. Latest photo date finds latest recorded date <= today', () {
      final dateKeys = [
        const DateKey(2025, 12, 25),
        const DateKey(2026, 2, 14),
        const DateKey(2026, 3, 18),
        const DateKey(2026, 3, 25), // future relative to March 20
      ];

      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: dateKeys,
      );

      expect(summary.latestPhotoDate, const DateKey(2026, 3, 18));
      expect(
        StatisticsSummary.formatDate(summary.latestPhotoDate),
        'March 18, 2026',
      );
    });

    test('8. Current month count counts only photos in current month', () {
      final dateKeys = [
        const DateKey(2026, 1, 10),
        const DateKey(2026, 2, 15),
        const DateKey(2026, 3, 2),
        const DateKey(2026, 3, 8),
        const DateKey(2026, 3, 20),
      ];

      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: dateKeys,
      );

      expect(summary.currentMonthCount, 3);
      expect(summary.currentYearCount, 5);
      expect(summary.monthlyCountsForCurrentYear[1], 1);
      expect(summary.monthlyCountsForCurrentYear[2], 1);
      expect(summary.monthlyCountsForCurrentYear[3], 3);
    });

    test('9. Current year count counts all photos in current year', () {
      final dateKeys = [
        const DateKey(2025, 12, 31), // previous year
        const DateKey(2026, 1, 1), // current year
        const DateKey(2026, 2, 1), // current year
        const DateKey(2026, 3, 1), // current year
      ];

      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: dateKeys,
      );

      expect(summary.totalRecordedDays, 4);
      expect(summary.currentYearCount, 3);
    });

    test('10. Previous-year photos do not count toward current year', () {
      final dateKeys = [
        const DateKey(2023, 6, 1),
        const DateKey(2024, 7, 1),
        const DateKey(2025, 8, 1),
        const DateKey(2026, 3, 20),
      ];

      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: dateKeys,
      );

      expect(summary.totalPhotos, 4);
      expect(summary.totalRecordedDays, 4);
      expect(summary.currentYearCount, 1);
      expect(summary.currentMonthCount, 1);
    });

    test('11. Previous-month photos do not count toward current month', () {
      final dateKeys = [
        const DateKey(2026, 1, 5),
        const DateKey(2026, 2, 20),
        const DateKey(2026, 3, 20),
      ];

      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: dateKeys,
      );

      expect(summary.currentMonthCount, 1);
      expect(summary.currentYearCount, 3);
    });

    test('12. Month boundary behavior', () {
      // Non-leap year 2025: Feb 27, Feb 28, March 1
      const nonLeapToday = DateKey(2025, 3, 1);
      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: nonLeapToday,
        dateKeys: [
          const DateKey(2025, 2, 27),
          const DateKey(2025, 2, 28),
          const DateKey(2025, 3, 1),
        ],
      );

      expect(summary.currentStreak, 3);
      expect(summary.longestStreak, 3);
      expect(summary.currentMonthCount, 1); // only March 1 in current month
      expect(summary.currentYearCount, 3); // all 3 in 2025
      expect(summary.firstPhotoDate, const DateKey(2025, 2, 27));
      expect(summary.latestPhotoDate, const DateKey(2025, 3, 1));
    });

    test('13. Year boundary behavior', () {
      const newYearToday = DateKey(2026, 1, 2);
      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: newYearToday,
        dateKeys: [
          const DateKey(2025, 12, 30),
          const DateKey(2025, 12, 31),
          const DateKey(2026, 1, 1),
          const DateKey(2026, 1, 2),
        ],
      );

      expect(summary.currentStreak, 4);
      expect(summary.longestStreak, 4);
      expect(summary.totalPhotos, 4);
      expect(summary.totalRecordedDays, 4);
      expect(summary.firstPhotoDate, const DateKey(2025, 12, 30));
      expect(summary.latestPhotoDate, const DateKey(2026, 1, 2));
      expect(summary.currentYearCount, 2); // only 2026
      expect(summary.currentMonthCount, 2); // only Jan 2026
    });

    test('14. Leap-year behavior / February 29', () {
      const leapToday = DateKey(2024, 3, 1);
      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: leapToday,
        dateKeys: [
          const DateKey(2024, 2, 28),
          const DateKey(2024, 2, 29),
          const DateKey(2024, 3, 1),
        ],
      );

      expect(summary.currentStreak, 3);
      expect(summary.longestStreak, 3);
      expect(summary.totalPhotos, 3);
      expect(summary.totalRecordedDays, 3);
      expect(summary.firstPhotoDate, const DateKey(2024, 2, 28));
      expect(summary.latestPhotoDate, const DateKey(2024, 3, 1));
      expect(summary.currentMonthCount, 1);
      expect(summary.currentYearCount, 3);
      expect(summary.monthlyCountsForCurrentYear[2], 2); // Feb 28, Feb 29
      expect(summary.monthlyCountsForCurrentYear[3], 1); // Mar 1
    });

    test('15. Statistics reuses correct current streak from StreakService', () {
      // Missing today -> current streak must be 0
      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: [
          const DateKey(2026, 3, 17),
          const DateKey(2026, 3, 18),
          const DateKey(2026, 3, 19),
        ],
        allowYesterdayActive: false,
      );

      final streakSummary = StreakService.instance.calculateStreak(
        todayKey: today,
        dateKeys: [
          const DateKey(2026, 3, 17),
          const DateKey(2026, 3, 18),
          const DateKey(2026, 3, 19),
        ],
        allowYesterdayActive: false,
      );

      expect(summary.currentStreak, equals(streakSummary.currentStreak));
      expect(summary.currentStreak, 0);
    });

    test('15b. Statistics preserves active yesterday streak (M44)', () {
      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: [
          const DateKey(2026, 3, 17),
          const DateKey(2026, 3, 18),
          const DateKey(2026, 3, 19),
        ],
      );

      expect(summary.currentStreak, 3);
      expect(summary.isCurrentStreakActive, isTrue);
    });

    test('16. Statistics reuses correct longest streak from StreakService', () {
      final dateKeys = [
        const DateKey(2026, 2, 1),
        const DateKey(2026, 2, 2),
        const DateKey(2026, 2, 3),
        const DateKey(2026, 2, 4),
        const DateKey(2026, 2, 5),
        const DateKey(2026, 3, 19),
        const DateKey(2026, 3, 20),
      ];

      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: dateKeys,
      );

      final streakSummary = StreakService.instance.calculateStreak(
        todayKey: today,
        dateKeys: dateKeys,
      );

      expect(summary.longestStreak, equals(streakSummary.longestStreak));
      expect(summary.longestStreak, 5);
      expect(summary.currentStreak, equals(streakSummary.currentStreak));
      expect(summary.currentStreak, 2);
    });

    test('Supports passing PhotoEntry collection directly', () {
      final entries = [
        PhotoEntry(
          date: DateTime(2026, 3, 18),
          title: 'Memory 1',
          gradientColors: const [],
        ),
        PhotoEntry(
          date: DateTime(2026, 3, 19),
          title: 'Memory 2',
          gradientColors: const [],
        ),
        PhotoEntry(
          date: DateTime(2026, 3, 20),
          title: 'Memory 3',
          gradientColors: const [],
        ),
      ];

      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        entries: entries,
      );

      expect(summary.totalPhotos, 3);
      expect(summary.totalRecordedDays, 3);
      expect(summary.currentStreak, 3);
      expect(summary.longestStreak, 3);
      expect(summary.firstPhotoDate, const DateKey(2026, 3, 18));
      expect(summary.latestPhotoDate, const DateKey(2026, 3, 20));
      expect(summary.currentMonthCount, 3);
      expect(summary.currentYearCount, 3);
    });

    test('StatisticsSummary equality and hashCode contracts', () {
      final summary1 = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: [today],
      );
      final summary2 = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: [today],
      );

      expect(summary1, equals(summary2));
      expect(summary1.hashCode, equals(summary2.hashCode));
      expect(summary1.toString(), contains('StatisticsSummary'));
    });

    test('M50: Weekday distribution is computed accurately', () {
      // March 16 (Mon), March 17 (Tue), March 18 (Wed), March 19 (Thu), March 20 (Fri) 2026
      final dateKeys = [
        const DateKey(2026, 3, 16), // Mon
        const DateKey(2026, 3, 17), // Tue
        const DateKey(2026, 3, 18), // Wed
        const DateKey(2026, 3, 19), // Thu
        const DateKey(2026, 3, 20), // Fri
      ];

      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        dateKeys: dateKeys,
      );

      expect(summary.weekdayCounts[DateTime.monday], 1);
      expect(summary.weekdayCounts[DateTime.tuesday], 1);
      expect(summary.weekdayCounts[DateTime.wednesday], 1);
      expect(summary.weekdayCounts[DateTime.thursday], 1);
      expect(summary.weekdayCounts[DateTime.friday], 1);
      expect(summary.weekdayCounts[DateTime.saturday], 0);
      expect(summary.weekdayCounts[DateTime.sunday], 0);
    });

    test(
      'M50: Statistics include localOnly, pending, failed, and synced entries',
      () {
        final entries = [
          PhotoEntry(
            date: DateTime(2026, 3, 17),
            title: 'Local',
            syncStatus: SyncStatus.localOnly,
            gradientColors: const [],
          ),
          PhotoEntry(
            date: DateTime(2026, 3, 18),
            title: 'Pending',
            syncStatus: SyncStatus.pending,
            gradientColors: const [],
          ),
          PhotoEntry(
            date: DateTime(2026, 3, 19),
            title: 'Failed',
            syncStatus: SyncStatus.failed,
            syncError: 'Network timeout',
            gradientColors: const [],
          ),
          PhotoEntry(
            date: DateTime(2026, 3, 20),
            title: 'Synced',
            syncStatus: SyncStatus.synced,
            driveFileId: 'drive_123',
            authorizedEmail: 'user@example.com',
            gradientColors: const [],
          ),
        ];

        final summary = StatisticsService.instance.calculateStatistics(
          todayKey: today,
          entries: entries,
        );

        expect(summary.totalPhotos, 4);
        expect(summary.totalRecordedDays, 4);
        expect(summary.currentStreak, 4);
        expect(summary.longestStreak, 4);
        expect(summary.currentMonthCount, 4);
        expect(summary.currentYearCount, 4);
      },
    );

    test('M50: Statistics handle missing local image files safely', () {
      final entries = [
        PhotoEntry(
          date: DateTime(2026, 3, 19),
          title: 'Missing image 1',
          imagePath: '/path/does/not/exist_1.jpg',
          gradientColors: const [],
        ),
        PhotoEntry(
          date: DateTime(2026, 3, 20),
          title: 'Missing image 2',
          imagePath: '/path/does/not/exist_2.jpg',
          gradientColors: const [],
        ),
      ];

      final summary = StatisticsService.instance.calculateStatistics(
        todayKey: today,
        entries: entries,
      );

      expect(summary.totalPhotos, 2);
      expect(summary.totalRecordedDays, 2);
      expect(summary.currentStreak, 2);
    });
  });
}
