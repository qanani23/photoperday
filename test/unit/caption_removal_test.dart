import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';

void main() {
  group('M44 — Complete Caption Removal Verification', () {
    test('1. PhotoEntry model serializes to JSON without caption field', () {
      final entry = PhotoEntry(
        date: DateTime(2026, 3, 15, 14, 30),
        title: 'Sunny Morning',
        location: 'Sunset Cliffs',
        category: 'Travel',
        timeFormatted: '2:30 PM',
        gradientColors: const [Colors.amber, Colors.orange],
        syncStatus: SyncStatus.synced,
        driveFileId: 'drive_123',
      );

      final jsonMap = entry.toJson();

      // Assert caption key is completely absent from produced JSON
      expect(jsonMap.containsKey('caption'), isFalse);
      expect(jsonMap['title'], equals('Sunny Morning'));
      expect(jsonMap['location'], equals('Sunset Cliffs'));
    });

    test(
      '2. Legacy JSON with caption deserializes safely and completely ignores caption',
      () {
        final legacyJson = {
          'date': '2026-03-15T14:30:00.000Z',
          'title': 'Legacy Memory',
          'caption': 'This was a legacy caption written in an older version',
          'location': 'Old Harbor',
          'category': 'Daily Life',
          'timeFormatted': '2:30 PM',
          'gradientColors': [4294951168, 4294944000],
          'syncStatus': 'synced',
          'driveFileId': 'drive_legacy_999',
        };

        final entry = PhotoEntry.fromJson(legacyJson);

        expect(entry.title, equals('Legacy Memory'));
        expect(entry.location, equals('Old Harbor'));
        expect(entry.dateKey, equals(const DateKey(2026, 3, 15)));

        // Reserializing must NOT write the caption back out
        final reserialized = entry.toJson();
        expect(reserialized.containsKey('caption'), isFalse);
      },
    );

    test(
      '4. Legacy string encoded JSON containing caption survives roundtrip cleanly',
      () {
        const rawJsonString =
            '{"date":"2026-05-01T10:00:00.000Z","title":"Spring Day","caption":"Old thoughts","location":"Botanical Garden","gradientColors":[4278190080,4278190335]}';

        final decoded = jsonDecode(rawJsonString) as Map<String, dynamic>;
        final entry = PhotoEntry.fromJson(decoded);

        expect(entry.title, equals('Spring Day'));
        expect(entry.location, equals('Botanical Garden'));

        final reEncoded = jsonEncode(entry.toJson());
        expect(reEncoded.contains('caption'), isFalse);
      },
    );
  });
}
