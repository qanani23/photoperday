import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/daily_photo_rule.dart';

void main() {
  group('DateKey Model Tests', () {
    test('instantiates with year, month, day and formats to YYYY-MM-DD', () {
      const key = DateKey(2026, 9, 12);
      expect(key.year, 2026);
      expect(key.month, 9);
      expect(key.day, 12);
      expect(key.format(), '2026-09-12');
      expect(key.toString(), '2026-09-12');
    });

    test('correctly zero-pads single-digit month and day', () {
      const key = DateKey(2026, 3, 5);
      expect(key.format(), '2026-03-05');
    });

    test('fromDateTime extracts local calendar year, month, day', () {
      final morning = DateTime(2026, 9, 12, 8, 30, 45);
      final evening = DateTime(2026, 9, 12, 22, 15, 10);

      final key1 = DateKey.fromDateTime(morning);
      final key2 = DateKey.fromDateTime(evening);

      expect(key1, equals(key2));
      expect(key1.format(), '2026-09-12');
    });

    test('parse correctly reconstructs DateKey from ISO string', () {
      final key = DateKey.parse('2026-11-04');
      expect(key.year, 2026);
      expect(key.month, 11);
      expect(key.day, 4);
      expect(key.format(), '2026-11-04');
    });

    test('parse throws FormatException on invalid input', () {
      expect(() => DateKey.parse('invalid-date'), throwsFormatException);
      expect(() => DateKey.parse('2026-09'), throwsFormatException);
    });

    test('toDateTime returns DateTime at midnight local time', () {
      const key = DateKey(2026, 9, 12);
      final dt = key.toDateTime();
      expect(dt.year, 2026);
      expect(dt.month, 9);
      expect(dt.day, 12);
      expect(dt.hour, 0);
      expect(dt.minute, 0);
      expect(dt.second, 0);
      expect(dt.millisecond, 0);
    });

    test('value equality and hashCode allow usage as map keys', () {
      const keyA = DateKey(2026, 9, 12);
      final keyB = DateKey.fromDateTime(DateTime(2026, 9, 12, 14, 0));
      const keyC = DateKey(2026, 9, 13);

      expect(keyA, equals(keyB));
      expect(keyA.hashCode, equals(keyB.hashCode));
      expect(keyA, isNot(equals(keyC)));

      final map = <DateKey, String>{};
      map[keyA] = 'First';
      map[keyB] = 'Replaced';

      expect(map.length, 1);
      expect(map[keyA], 'Replaced');
    });

    test('compareTo sorts chronologically', () {
      const d1 = DateKey(2026, 1, 15);
      const d2 = DateKey(2026, 3, 10);
      const d3 = DateKey(2026, 3, 15);
      const d4 = DateKey(2027, 1, 1);

      final list = [d3, d1, d4, d2]..sort();
      expect(list, [d1, d2, d3, d4]);
    });

    test('isToday returns true only for current calendar day', () {
      final todayKey = DateKey.today();
      expect(todayKey.isToday, isTrue);

      const pastKey = DateKey(2020, 1, 1);
      expect(pastKey.isToday, isFalse);
    });
  });

  group('DailyPhotoRule Domain Tests', () {
    test('normalize converts DateTime into DateKey', () {
      final dt = DateTime(2026, 9, 12, 19, 45);
      final key = DailyPhotoRule.normalize(dt);
      expect(key, const DateKey(2026, 9, 12));
    });

    test('isSameDay correctly identifies same vs different calendar days', () {
      final t1 = DateTime(2026, 9, 12, 0, 1);
      final t2 = DateTime(2026, 9, 12, 23, 59);
      final t3 = DateTime(2026, 9, 13, 0, 0);

      expect(DailyPhotoRule.isSameDay(t1, t2), isTrue);
      expect(DailyPhotoRule.isSameDay(t1, t3), isFalse);
    });

    test('formatKey returns formatted YYYY-MM-DD string', () {
      final dt = DateTime(2026, 9, 12, 15, 30);
      expect(DailyPhotoRule.formatKey(dt), '2026-09-12');
    });

    test('toMidnight normalizes DateTime to start of day', () {
      final dt = DateTime(2026, 9, 12, 15, 30, 45, 123);
      final midnight = DailyPhotoRule.toMidnight(dt);
      expect(midnight, DateTime(2026, 9, 12, 0, 0, 0, 0));
    });

    test('isReplacement detects replacement when dates match', () {
      final existing = PhotoEntry(
        date: DateTime(2026, 9, 12, 9, 0),
        title: 'Morning Photo',
        gradientColors: const [Colors.amber, Colors.orange],
      );
      final incomingSameDay = PhotoEntry(
        date: DateTime(2026, 9, 12, 18, 30),
        title: 'Sunset Photo',
        gradientColors: const [Colors.blue, Colors.purple],
      );
      final incomingOtherDay = PhotoEntry(
        date: DateTime(2026, 9, 13, 10, 0),
        title: 'Next Day Photo',
        gradientColors: const [Colors.green, Colors.teal],
      );

      expect(
        DailyPhotoRule.isReplacement(
          existing: existing,
          incoming: incomingSameDay,
        ),
        isTrue,
      );
      expect(
        DailyPhotoRule.isReplacement(
          existing: existing,
          incoming: incomingOtherDay,
        ),
        isFalse,
      );
      expect(
        DailyPhotoRule.isReplacement(existing: null, incoming: incomingSameDay),
        isFalse,
      );
    });
  });
}
