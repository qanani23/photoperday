import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';

void main() {
  group('PhotoEntry Camera Enhancements', () {
    test('hasRealImage reflects presence of valid imagePath', () {
      final mockOnly = PhotoEntry(
        date: DateTime(2026, 3, 15),
        title: 'Mock Photo',
        gradientColors: const [Colors.orange, Colors.red],
      );
      expect(mockOnly.hasRealImage, isFalse);
      expect(mockOnly.imagePath, isNull);

      final emptyPath = PhotoEntry(
        date: DateTime(2026, 3, 15),
        title: 'Empty Path Photo',
        gradientColors: const [Colors.orange, Colors.red],
        imagePath: '',
      );
      expect(emptyPath.hasRealImage, isFalse);

      final realPhoto = PhotoEntry(
        date: DateTime(2026, 3, 15),
        title: 'Captured Photo',
        gradientColors: const [Colors.orange, Colors.red],
        imagePath: '/data/user/0/com.photoaday/cache/CAP_123.jpg',
      );
      expect(realPhoto.hasRealImage, isTrue);
      expect(
        realPhoto.imagePath,
        '/data/user/0/com.photoaday/cache/CAP_123.jpg',
      );
    });

    test(
      'copyWith updates imagePath correctly while preserving other fields',
      () {
        final original = PhotoEntry(
          date: DateTime(2026, 3, 15),
          title: 'Original Memory',
          gradientColors: const [Colors.purple, Colors.indigo],
          location: 'Before capture',
        );

        final withImage = original.copyWith(
          imagePath: '/path/to/capture.jpg',
          title: 'After Capture',
        );

        expect(withImage.hasRealImage, isTrue);
        expect(withImage.imagePath, '/path/to/capture.jpg');
        expect(withImage.title, 'After Capture');
        expect(withImage.location, 'Before capture');
        expect(withImage.date, original.date);
        expect(withImage.gradientColors, original.gradientColors);
      },
    );
  });
}
