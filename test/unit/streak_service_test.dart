import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/streak_service.dart';

void main() {
  group('Milestone 31 — StreakService Domain Tests', () {
    const today = DateKey(2026, 3, 20);

    test('1. No photos -> all values are zero', () {
      final summary = StreakService.instance.calculateStreak(
        todayKey: today,
        dateKeys: [],
      );

      expect(summary.currentStreak, 0);
      expect(summary.longestStreak, 0);
      expect(summary.totalRecordedDays, 0);
      expect(summary, equals(StreakSummary.zero));
    });

    test('2. One photo today -> current = 1, longest = 1', () {
      final summary = StreakService.instance.calculateStreak(
        todayKey: today,
        dateKeys: [today],
      );

      expect(summary.currentStreak, 1);
      expect(summary.longestStreak, 1);
      expect(summary.totalRecordedDays, 1);
    });

    test('3. Consecutive 3-day sequence -> current = 3, longest = 3', () {
      final summary = StreakService.instance.calculateStreak(
        todayKey: today,
        dateKeys: [
          const DateKey(2026, 3, 18),
          const DateKey(2026, 3, 19),
          const DateKey(2026, 3, 20),
        ],
      );

      expect(summary.currentStreak, 3);
      expect(summary.longestStreak, 3);
      expect(summary.totalRecordedDays, 3);
    });

    test('4. Missing today -> current = 0', () {
      // Photos exist on March 17, 18, 19, but today (March 20) is missing
      final summary = StreakService.instance.calculateStreak(
        todayKey: today,
        dateKeys: [
          const DateKey(2026, 3, 17),
          const DateKey(2026, 3, 18),
          const DateKey(2026, 3, 19),
        ],
      );

      expect(summary.currentStreak, 0);
      expect(summary.longestStreak, 3);
      expect(summary.totalRecordedDays, 3);
    });

    test(
      '5. Historical consecutive sequence -> longest calculated correctly',
      () {
        // 5-day sequence in February, no photo today
        final summary = StreakService.instance.calculateStreak(
          todayKey: today,
          dateKeys: [
            const DateKey(2026, 2, 10),
            const DateKey(2026, 2, 11),
            const DateKey(2026, 2, 12),
            const DateKey(2026, 2, 13),
            const DateKey(2026, 2, 14),
          ],
        );

        expect(summary.currentStreak, 0);
        expect(summary.longestStreak, 5);
        expect(summary.totalRecordedDays, 5);
      },
    );

    test('6. Gap breaks a streak', () {
      // March 15, 16 (gap on 17), March 18, 19, 20
      final summary = StreakService.instance.calculateStreak(
        todayKey: today,
        dateKeys: [
          const DateKey(2026, 3, 15),
          const DateKey(2026, 3, 16),
          // gap: March 17
          const DateKey(2026, 3, 18),
          const DateKey(2026, 3, 19),
          const DateKey(2026, 3, 20),
        ],
      );

      // Current streak only counts back to the gap on 17
      expect(summary.currentStreak, 3);
      expect(summary.longestStreak, 3);
      expect(summary.totalRecordedDays, 5);
    });

    test('7. Multiple streaks -> longest chooses the longest sequence', () {
      // Run 1: March 1, 2, 3 (3 days)
      // Gap: March 4
      // Run 2: March 5, 6, 7, 8 (4 days)
      // Gap: March 9..18
      // Run 3: March 19, 20 (2 days, ending today)
      final summary = StreakService.instance.calculateStreak(
        todayKey: today,
        dateKeys: [
          const DateKey(2026, 3, 1),
          const DateKey(2026, 3, 2),
          const DateKey(2026, 3, 3),
          const DateKey(2026, 3, 5),
          const DateKey(2026, 3, 6),
          const DateKey(2026, 3, 7),
          const DateKey(2026, 3, 8),
          const DateKey(2026, 3, 19),
          const DateKey(2026, 3, 20),
        ],
      );

      expect(summary.currentStreak, 2);
      expect(summary.longestStreak, 4);
      expect(summary.totalRecordedDays, 9);
    });

    test('8. Future dates excluded', () {
      // Today is March 20. March 21 and March 22 should be completely excluded.
      final summary = StreakService.instance.calculateStreak(
        todayKey: today,
        dateKeys: [
          const DateKey(2026, 3, 19),
          const DateKey(2026, 3, 20),
          const DateKey(2026, 3, 21), // future
          const DateKey(2026, 3, 22), // future
        ],
      );

      expect(summary.currentStreak, 2);
      expect(summary.longestStreak, 2);
      expect(summary.totalRecordedDays, 2);
    });

    test('9. Month boundary works', () {
      // 1. February to March in non-leap year (2025): Feb 27, Feb 28, March 1
      const nonLeapToday = DateKey(2025, 3, 1);
      final nonLeapSummary = StreakService.instance.calculateStreak(
        todayKey: nonLeapToday,
        dateKeys: [
          const DateKey(2025, 2, 27),
          const DateKey(2025, 2, 28),
          const DateKey(2025, 3, 1),
        ],
      );
      expect(nonLeapSummary.currentStreak, 3);
      expect(nonLeapSummary.longestStreak, 3);

      // 2. March 31 to April 1
      const aprilToday = DateKey(2026, 4, 2);
      final aprilSummary = StreakService.instance.calculateStreak(
        todayKey: aprilToday,
        dateKeys: [
          const DateKey(2026, 3, 31),
          const DateKey(2026, 4, 1),
          const DateKey(2026, 4, 2),
        ],
      );
      expect(aprilSummary.currentStreak, 3);
      expect(aprilSummary.longestStreak, 3);
    });

    test('10. Year boundary works', () {
      // Dec 30 2025, Dec 31 2025, Jan 1 2026, Jan 2 2026
      const newYearToday = DateKey(2026, 1, 2);
      final summary = StreakService.instance.calculateStreak(
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
      expect(summary.totalRecordedDays, 4);
    });

    test('11. Leap-year / February 29 works', () {
      // 2024 is a leap year. Feb 28, Feb 29, March 1
      const leapToday = DateKey(2024, 3, 1);
      final summary = StreakService.instance.calculateStreak(
        todayKey: leapToday,
        dateKeys: [
          const DateKey(2024, 2, 28),
          const DateKey(2024, 2, 29),
          const DateKey(2024, 3, 1),
        ],
      );

      expect(summary.currentStreak, 3);
      expect(summary.longestStreak, 3);
      expect(summary.totalRecordedDays, 3);
    });

    test('12. Duplicate DateKeys do not inflate counts', () {
      // Passing duplicates of March 19 and March 20
      final summary = StreakService.instance.calculateStreak(
        todayKey: today,
        dateKeys: [
          const DateKey(2026, 3, 19),
          const DateKey(2026, 3, 19),
          const DateKey(2026, 3, 20),
          const DateKey(2026, 3, 20),
          const DateKey(2026, 3, 20),
        ],
      );

      expect(summary.currentStreak, 2);
      expect(summary.longestStreak, 2);
      expect(summary.totalRecordedDays, 2);
    });

    test('Supports passing PhotoEntry list directly', () {
      final entries = [
        PhotoEntry(
          date: DateTime(2026, 3, 19),
          title: 'Day 1',
          gradientColors: const [],
        ),
        PhotoEntry(
          date: DateTime(2026, 3, 20),
          title: 'Day 2',
          gradientColors: const [],
        ),
      ];

      final summary = StreakService.instance.calculateStreak(
        todayKey: today,
        entries: entries,
      );

      expect(summary.currentStreak, 2);
      expect(summary.longestStreak, 2);
      expect(summary.totalRecordedDays, 2);
    });
  });
}
