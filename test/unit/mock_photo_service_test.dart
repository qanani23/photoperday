import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/mock_photo_service.dart';

void main() {
  group('PhotoEntry Model', () {
    test('instantiates with required and default properties', () {
      final entry = PhotoEntry(
        date: DateTime(2026, 3, 15),
        title: 'Golden Sunset',
        gradientColors: const [Colors.amber, Colors.deepOrange],
      );

      expect(entry.date, DateTime(2026, 3, 15));
      expect(entry.title, 'Golden Sunset');
      expect(entry.caption, isNull);
      expect(entry.location, isNull);
      expect(entry.timeFormatted, '2:45 PM');
      expect(entry.category, 'Daily Life');
      expect(entry.icon, Icons.photo_camera_rounded);
      expect(entry.gradientColors.length, 2);
    });

    test(
      'copyWith properly overrides specified fields while preserving others',
      () {
        final original = PhotoEntry(
          date: DateTime(2026, 3, 15),
          title: 'Original Title',
          caption: 'Original Caption',
          location: 'Original Location',
          timeFormatted: '1:00 PM',
          category: 'Original Category',
          icon: Icons.camera,
          gradientColors: const [Colors.red, Colors.blue],
        );

        final updated = original.copyWith(
          title: 'Updated Title',
          caption: 'Updated Caption',
          location: 'New City',
        );

        expect(updated.title, 'Updated Title');
        expect(updated.caption, 'Updated Caption');
        expect(updated.location, 'New City');
        // Preserved fields
        expect(updated.date, original.date);
        expect(updated.timeFormatted, original.timeFormatted);
        expect(updated.category, original.category);
        expect(updated.icon, original.icon);
        expect(updated.gradientColors, original.gradientColors);
      },
    );
  });

  group('MockPhotoService', () {
    final service = MockPhotoService.instance;

    test('retrieves valid seeded photo for known date', () {
      final march14 = DateTime(2026, 3, 14);
      expect(service.hasPhoto(march14), isTrue);

      final photo = service.getPhoto(march14);
      expect(photo, isNotNull);
      expect(photo!.title, 'Late Night Studio');
      expect(photo.location, 'Home Office');
      expect(photo.category, 'Creative');
    });

    test('Day 15 is reserved as today awaiting capture in calendar', () {
      final march15 = DateTime(2026, 3, 15);
      expect(service.hasPhoto(march15), isFalse);
      expect(service.getPhoto(march15), isNull);
    });

    test('returns null and false for unseeded dates', () {
      final futureDate = DateTime(2026, 3, 28);
      expect(service.hasPhoto(futureDate), isFalse);
      expect(service.getPhoto(futureDate), isNull);

      final distantDate = DateTime(2028, 1, 1);
      expect(service.hasPhoto(distantDate), isFalse);
      expect(service.getPhoto(distantDate), isNull);
    });

    test('February 2026 contains all 28 archived days', () {
      for (int day = 1; day <= 28; day++) {
        final febDate = DateTime(2026, 2, day);
        expect(
          service.hasPhoto(febDate),
          isTrue,
          reason: 'Feb $day should exist',
        );
        final photo = service.getPhoto(febDate);
        expect(photo, isNotNull);
        expect(photo!.date.day, day);
      }
    });

    test('defaultTodayPhoto matches March 15 2026 mock entry', () {
      final defaultPhoto = MockPhotoService.defaultTodayPhoto;
      expect(defaultPhoto.date, DateTime(2026, 3, 15));
      expect(defaultPhoto.title, 'Golden Afternoon Reflections');
      expect(defaultPhoto.location, 'Echo Park Lake');
      expect(defaultPhoto.gradientColors.length, greaterThanOrEqualTo(2));
    });
  });

  group('Calendar Month Day Calculation Math', () {
    int getDaysInMonth(int year, int month) {
      return DateTime(year, month + 1, 0).day;
    }

    test('calculates correct days for standard 31-day months', () {
      expect(getDaysInMonth(2026, 1), 31);
      expect(getDaysInMonth(2026, 3), 31);
      expect(getDaysInMonth(2026, 5), 31);
      expect(getDaysInMonth(2026, 7), 31);
      expect(getDaysInMonth(2026, 8), 31);
      expect(getDaysInMonth(2026, 10), 31);
      expect(getDaysInMonth(2026, 12), 31);
    });

    test('calculates correct days for standard 30-day months', () {
      expect(getDaysInMonth(2026, 4), 30);
      expect(getDaysInMonth(2026, 6), 30);
      expect(getDaysInMonth(2026, 9), 30);
      expect(getDaysInMonth(2026, 11), 30);
    });

    test('calculates February days correctly for non-leap and leap years', () {
      expect(getDaysInMonth(2026, 2), 28);
      expect(getDaysInMonth(2024, 2), 29);
      expect(getDaysInMonth(2000, 2), 29);
      expect(getDaysInMonth(2100, 2), 28);
    });
  });
}
