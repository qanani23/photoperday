import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/in_memory_photo_store.dart';

void main() {
  group('InMemoryPhotoStore — One Photo Per Day Rule', () {
    final store = InMemoryPhotoStore.instance;

    setUp(() {
      store.clear();
    });

    // 1. Empty date has no photo
    test('1. Empty date has no photo', () {
      final date = DateTime(2026, 9, 12);
      expect(store.hasPhoto(date), isFalse);
      expect(store.getPhoto(date), isNull);
      expect(store.hasPhotoByKey(const DateKey(2026, 9, 12)), isFalse);
      expect(store.getPhotoByKey(const DateKey(2026, 9, 12)), isNull);
      expect(store.totalPhotos, 0);
    });

    // 2. Add first photo → photo exists
    test('2. Add first photo -> photo exists', () {
      final date = DateTime(2026, 9, 12, 10, 30);
      final entry = PhotoEntry(
        date: date,
        title: 'Morning Capture',
        gradientColors: const [Colors.amber, Colors.orange],
        imagePath: '/tmp/morning.jpg',
      );

      var notified = false;
      store.addListener(() => notified = true);

      store.setPhoto(entry);

      expect(notified, isTrue);
      expect(store.hasPhoto(date), isTrue);
      expect(store.totalPhotos, 1);
    });

    // 3. Retrieve photo by same date
    test('3. Retrieve photo by same date', () {
      final date = DateTime(2026, 9, 12, 14, 0);
      final entry = PhotoEntry(
        date: date,
        title: 'Afternoon Stroll',
        gradientColors: const [Colors.blue, Colors.indigo],
        imagePath: '/tmp/afternoon.jpg',
      );

      store.setPhoto(entry);

      final retrieved = store.getPhoto(date);
      expect(retrieved, isNotNull);
      expect(retrieved!.title, 'Afternoon Stroll');
      expect(retrieved.imagePath, '/tmp/afternoon.jpg');
      expect(retrieved.hasRealImage, isTrue);
      expect(retrieved.dateKey, const DateKey(2026, 9, 12));
    });

    // 4. Retrieve photo using same calendar date but different time
    test('4. Retrieve photo using same calendar date but different time', () {
      final captureTime = DateTime(2026, 9, 12, 9, 15, 30);
      final entry = PhotoEntry(
        date: captureTime,
        title: 'Morning Light',
        gradientColors: const [Colors.orange, Colors.red],
        imagePath: '/tmp/light.jpg',
      );

      store.setPhoto(entry);

      // Query with different times on the exact same local calendar day
      final noonQuery = DateTime(2026, 9, 12, 12, 0, 0);
      final lateNightQuery = DateTime(2026, 9, 12, 23, 45, 59);
      final midnightQuery = DateTime(2026, 9, 12, 0, 0, 0);

      expect(store.hasPhoto(noonQuery), isTrue);
      expect(store.getPhoto(noonQuery)?.title, 'Morning Light');

      expect(store.hasPhoto(lateNightQuery), isTrue);
      expect(store.getPhoto(lateNightQuery)?.title, 'Morning Light');

      expect(store.hasPhoto(midnightQuery), isTrue);
      expect(store.getPhoto(midnightQuery)?.title, 'Morning Light');
    });

    // 5. Add second photo to same date → replaces first
    test('5. Add second photo to same date -> replaces first', () {
      final dateA = DateTime(2026, 9, 12, 8, 0);
      final photoA = PhotoEntry(
        date: dateA,
        title: 'Photo A',
        gradientColors: const [Colors.red, Colors.pink],
        imagePath: '/tmp/photo_a.jpg',
      );

      store.setPhoto(photoA);
      expect(store.totalPhotos, 1);
      expect(store.getPhoto(dateA)?.title, 'Photo A');

      // Second photo on same date at different hour
      final dateB = DateTime(2026, 9, 12, 17, 30);
      final photoB = PhotoEntry(
        date: dateB,
        title: 'Photo B (Replacement)',
        gradientColors: const [Colors.green, Colors.teal],
        imagePath: '/tmp/photo_b.jpg',
      );

      store.setPhoto(photoB);

      // Exactly ONE photo must remain for this date
      expect(store.totalPhotos, 1);
      expect(store.getPhoto(dateA)?.title, 'Photo B (Replacement)');
      expect(store.getPhoto(dateB)?.title, 'Photo B (Replacement)');
      expect(store.getPhoto(dateB)?.imagePath, '/tmp/photo_b.jpg');
      expect(store.allEntries.length, 1);
    });

    // 6. Replacing multiple times still leaves exactly one photo
    test('6. Replacing multiple times still leaves exactly one photo', () {
      final baseDate = DateTime(2026, 9, 12);

      for (int i = 1; i <= 5; i++) {
        final entry = PhotoEntry(
          date: baseDate.add(Duration(hours: i * 3)),
          title: 'Version $i',
          gradientColors: const [Colors.cyan, Colors.blue],
          imagePath: '/tmp/version_$i.jpg',
        );
        store.setPhoto(entry);
        expect(
          store.totalPhotos,
          1,
          reason: 'Must remain exactly 1 photo after step $i',
        );
      }

      final current = store.getPhoto(baseDate);
      expect(current, isNotNull);
      expect(current!.title, 'Version 5');
      expect(current.imagePath, '/tmp/version_5.jpg');
      expect(store.allEntries.length, 1);
    });

    // 7. Different dates can each have one photo
    test('7. Different dates can each have one photo', () {
      final date1 = DateTime(2026, 9, 12, 11, 0);
      final date2 = DateTime(2026, 9, 13, 14, 0);
      final date3 = DateTime(2026, 9, 14, 18, 0);

      store.setPhoto(
        PhotoEntry(
          date: date1,
          title: 'Day 12 Photo',
          gradientColors: const [Colors.red, Colors.orange],
          imagePath: '/tmp/d12.jpg',
        ),
      );

      store.setPhoto(
        PhotoEntry(
          date: date2,
          title: 'Day 13 Photo',
          gradientColors: const [Colors.green, Colors.lime],
          imagePath: '/tmp/d13.jpg',
        ),
      );

      store.setPhoto(
        PhotoEntry(
          date: date3,
          title: 'Day 14 Photo',
          gradientColors: const [Colors.blue, Colors.purple],
          imagePath: '/tmp/d14.jpg',
        ),
      );

      expect(store.totalPhotos, 3);
      expect(store.hasPhoto(date1), isTrue);
      expect(store.hasPhoto(date2), isTrue);
      expect(store.hasPhoto(date3), isTrue);
      expect(store.getPhoto(date1)?.title, 'Day 12 Photo');
      expect(store.getPhoto(date2)?.title, 'Day 13 Photo');
      expect(store.getPhoto(date3)?.title, 'Day 14 Photo');

      // Replacing day 13 should not affect day 12 or day 14
      store.setPhoto(
        PhotoEntry(
          date: DateTime(2026, 9, 13, 20, 0),
          title: 'Day 13 Updated',
          gradientColors: const [Colors.teal, Colors.tealAccent],
          imagePath: '/tmp/d13_v2.jpg',
        ),
      );

      expect(store.totalPhotos, 3);
      expect(store.getPhoto(date1)?.title, 'Day 12 Photo');
      expect(store.getPhoto(date2)?.title, 'Day 13 Updated');
      expect(store.getPhoto(date3)?.title, 'Day 14 Photo');
    });

    // 8. Removing a photo leaves the date empty
    test('8. Removing a photo leaves the date empty', () {
      final date = DateTime(2026, 9, 12, 16, 45);
      final entry = PhotoEntry(
        date: date,
        title: 'To Be Deleted',
        gradientColors: const [Colors.grey, Colors.black],
        imagePath: '/tmp/delete_me.jpg',
      );

      store.setPhoto(entry);
      expect(store.hasPhoto(date), isTrue);
      expect(store.totalPhotos, 1);

      var notified = false;
      store.addListener(() => notified = true);

      // Remove using different time on same day
      store.removePhoto(DateTime(2026, 9, 12, 22, 0));

      expect(notified, isTrue);
      expect(store.hasPhoto(date), isFalse);
      expect(store.getPhoto(date), isNull);
      expect(store.totalPhotos, 0);
    });

    // 9. Clearing the store removes all temporary photos
    test('9. Clearing the store removes all temporary photos', () {
      store.setPhoto(
        PhotoEntry(
          date: DateTime(2026, 9, 12),
          title: 'Photo 1',
          gradientColors: const [Colors.red, Colors.orange],
        ),
      );
      store.setPhoto(
        PhotoEntry(
          date: DateTime(2026, 9, 13),
          title: 'Photo 2',
          gradientColors: const [Colors.blue, Colors.green],
        ),
      );
      store.setPhoto(
        PhotoEntry(
          date: DateTime(2026, 9, 14),
          title: 'Photo 3',
          gradientColors: const [Colors.purple, Colors.pink],
        ),
      );

      expect(store.totalPhotos, 3);

      var notified = false;
      store.addListener(() => notified = true);

      store.clear();

      expect(notified, isTrue);
      expect(store.totalPhotos, 0);
      expect(store.allEntries, isEmpty);
      expect(store.hasPhoto(DateTime(2026, 9, 12)), isFalse);
      expect(store.hasPhoto(DateTime(2026, 9, 13)), isFalse);
      expect(store.hasPhoto(DateTime(2026, 9, 14)), isFalse);
    });

    // 10. Date normalization behaves correctly around midnight/local DateTime boundaries
    test(
      '10. Date normalization behaves correctly around midnight/local boundaries',
      () {
        // 23:59:59.999 vs 00:00:00.000 on consecutive days
        final endOfDay = DateTime(2026, 9, 12, 23, 59, 59, 999);
        final startOfDay = DateTime(2026, 9, 12, 0, 0, 0, 0);
        final nextDayStart = DateTime(2026, 9, 13, 0, 0, 0, 0);

        store.setPhoto(
          PhotoEntry(
            date: endOfDay,
            title: 'Late Night Sept 12',
            gradientColors: const [Colors.indigo, Colors.black],
            imagePath: '/tmp/late.jpg',
          ),
        );

        // Querying with startOfDay (00:00) of Sept 12 must find the photo
        expect(store.hasPhoto(startOfDay), isTrue);
        expect(store.getPhoto(startOfDay)?.title, 'Late Night Sept 12');

        // Next day start (00:00 Sept 13) is a DIFFERENT date and must be empty
        expect(store.hasPhoto(nextDayStart), isFalse);
        expect(store.getPhoto(nextDayStart), isNull);

        // Now adding a photo to nextDayStart creates a second entry
        store.setPhoto(
          PhotoEntry(
            date: nextDayStart,
            title: 'Midnight Sept 13',
            gradientColors: const [Colors.amber, Colors.yellow],
            imagePath: '/tmp/midnight.jpg',
          ),
        );

        expect(store.totalPhotos, 2);
        expect(store.getPhoto(endOfDay)?.title, 'Late Night Sept 12');
        expect(store.getPhoto(nextDayStart)?.title, 'Midnight Sept 13');
      },
    );

    // Extra: replacePhoto convenience method
    test('replacePhoto explicitly updates entry for specified date', () {
      final date = DateTime(2026, 9, 15);
      final initial = PhotoEntry(
        date: date,
        title: 'Initial',
        gradientColors: const [Colors.brown, Colors.orange],
      );
      store.setPhoto(initial);

      final replacement = PhotoEntry(
        date: date,
        title: 'Replaced Via Method',
        gradientColors: const [Colors.blue, Colors.cyan],
        imagePath: '/tmp/replacement.jpg',
      );
      store.replacePhoto(date, replacement);

      expect(store.totalPhotos, 1);
      final result = store.getPhoto(date);
      expect(result?.title, 'Replaced Via Method');
      expect(result?.imagePath, '/tmp/replacement.jpg');
    });
  });
}
