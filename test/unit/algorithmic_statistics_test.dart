import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/services/statistics_service.dart';

void main() {
  group('M44 — Algorithmic Statistics (StatisticsService)', () {
    final statsService = StatisticsService.instance;

    test('1. Empty dates list produces zeroed statistics', () {
      final summary = statsService.calculateStatisticsFromDates(
        dates: [],
        referenceDate: DateTime(2026, 3, 15),
      );

      expect(summary.totalPhotos, 0);
      expect(summary.totalRecordedDays, 0);
      expect(summary.currentStreak, 0);
      expect(summary.longestStreak, 0);
      expect(summary.endedStreakCount, 0);
      expect(summary.averageStreakLength, 0.0);
      expect(summary.longestGapDays, 0);
      expect(summary.firstPhotoDate, isNull);
      expect(summary.latestPhotoDate, isNull);
      expect(summary.mostActiveMonth, isNull);
      expect(summary.yearlyCounts, isEmpty);
      expect(summary.weeklyCounts, isEmpty);
      expect(summary.totalMissedDays, 0);
    });

    test(
      '2. Single synchronized photo produces accurate baseline statistics',
      () {
        final today = DateTime(2026, 3, 15);
        final summary = statsService.calculateStatisticsFromDates(
          dates: [today],
          referenceDate: today,
        );

        expect(summary.totalPhotos, 1);
        expect(summary.totalRecordedDays, 1);
        expect(summary.currentStreak, 1);
        expect(summary.longestStreak, 1);
        expect(summary.endedStreakCount, 0);
        expect(summary.averageStreakLength, 1.0);
        expect(summary.longestGapDays, 0);
        expect(summary.firstPhotoDate, const DateKey(2026, 3, 15));
        expect(summary.latestPhotoDate, const DateKey(2026, 3, 15));
        expect(summary.currentMonthCount, 1);
        expect(summary.currentYearCount, 1);
        expect(summary.mostActiveMonth, 3);
        expect(summary.mostActiveMonthCount, 1);
        expect(summary.yearlyCounts[2026], 1);
      },
    );

    test(
      '3. Complex history: streak runs, gaps, yearly and monthly aggregations',
      () {
        final reference = DateTime(2026, 3, 15);
        final dates = [
          // 2025: 3 consecutive days in December (Dec 1, 2, 3)
          DateTime(2025, 12, 1),
          DateTime(2025, 12, 2),
          DateTime(2025, 12, 3),

          // 2026: 2 consecutive days in January (Jan 10, 11)
          DateTime(2026, 1, 10),
          DateTime(2026, 1, 11),

          // 2026: 4 consecutive days in March ending today (Mar 12, 13, 14, 15)
          DateTime(2026, 3, 12),
          DateTime(2026, 3, 13),
          DateTime(2026, 3, 14),
          DateTime(2026, 3, 15),
        ];

        final summary = statsService.calculateStatisticsFromDates(
          dates: dates,
          referenceDate: reference,
        );

        // Totals
        expect(summary.totalPhotos, 9);
        expect(summary.totalRecordedDays, 9);

        // Streaks:
        // Run 1: Dec 1-3 (len 3, ended)
        // Run 2: Jan 10-11 (len 2, ended)
        // Run 3: Mar 12-15 (len 4, active today)
        expect(summary.currentStreak, 4);
        expect(summary.longestStreak, 4);
        expect(summary.endedStreakCount, 2);
        // Average length = (3 + 2 + 4) / 3 = 3.0
        expect(summary.averageStreakLength, closeTo(3.0, 0.01));

        // Yearly breakdown
        expect(summary.yearlyCounts[2025], 3);
        expect(summary.yearlyCounts[2026], 6);

        // Current year count (2026) = 2 in Jan + 4 in Mar = 6
        expect(summary.currentYearCount, 6);
        // Current month count (Mar 2026) = 4
        expect(summary.currentMonthCount, 4);

        // Most active month: March 2026 (4 photos)
        expect(summary.mostActiveMonth, 3);
        expect(summary.mostActiveMonthCount, 4);

        // Date range
        expect(summary.firstPhotoDate, const DateKey(2025, 12, 1));
        expect(summary.latestPhotoDate, const DateKey(2026, 3, 15));

        // Longest gap: Between Jan 11, 2026 and March 12, 2026 = 59 days
        expect(summary.longestGapDays, greaterThan(50));
      },
    );

    test(
      '4. Deduplication ensures multiple photos on same date do not distort stats',
      () {
        final reference = DateTime(2026, 3, 15);
        final dates = [
          DateTime(2026, 3, 14, 8, 0),
          DateTime(2026, 3, 14, 18, 0),
          DateTime(2026, 3, 15, 9, 30),
        ];

        final summary = statsService.calculateStatisticsFromDates(
          dates: dates,
          referenceDate: reference,
        );

        expect(summary.totalPhotos, 2);
        expect(summary.totalRecordedDays, 2);
        expect(summary.currentStreak, 2);
      },
    );
  });
}
