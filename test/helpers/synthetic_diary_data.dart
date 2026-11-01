import 'package:flutter/material.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';

/// Reusable fixture generator for large synthetic diary datasets.
///
/// Supports generating 100, 500, 1,000, and 5,000+ realistic photo entries
/// with consecutive calendar dates, valid metadata, and varied sync states,
/// without creating thousands of physical image files on disk.
class SyntheticDiaryData {
  SyntheticDiaryData._();

  static const List<List<Color>> _colorPalettes = [
    [Color(0xFFE28743), Color(0xFF873E23)],
    [Color(0xFF1E3C72), Color(0xFF2A5298)],
    [Color(0xFF11998E), Color(0xFF38EF7D)],
    [Color(0xFFFF5F6D), Color(0xFFFFC371)],
    [Color(0xFF4776E6), Color(0xFF8E54E9)],
    [Color(0xFF00B4DB), Color(0xFF0083B0)],
  ];

  static const List<String> _sampleTitles = [
    'Morning Coffee',
    'Park Walk',
    'Workspace Setup',
    'Sunset View',
    'Rainy Afternoon',
    'City Stroll',
    'Weekend Hiking',
    'Quiet Reading',
    'Garden Bloom',
    'Family Dinner',
  ];

  static const List<String> _sampleLocations = [
    'Home Studio',
    'Central Park',
    'Downtown Cafe',
    'Hilltop Lookout',
    'Local Library',
    'Neighborhood Walk',
  ];

  /// Generates a list of [count] consecutive [PhotoEntry] records ending on [endDateKey]
  /// (defaulting to today). Ordered chronologically from oldest to newest.
  static List<PhotoEntry> generateEntries(
    int count, {
    DateKey? endDateKey,
    bool includeVirtualImagePath = true,
  }) {
    final endKey = endDateKey ?? DateKey.today();
    final entries = <PhotoEntry>[];

    // Compute start DateKey by stepping backwards (count - 1) days
    var currentKey = endKey;
    for (int i = 0; i < count - 1; i++) {
      currentKey = currentKey.previousDay;
    }

    // Now step forward from startKey to endKey to produce chronologically ordered entries
    for (int i = 0; i < count; i++) {
      final palette = _colorPalettes[i % _colorPalettes.length];
      final title = _sampleTitles[i % _sampleTitles.length];
      final location = _sampleLocations[i % _sampleLocations.length];
      final date = currentKey.toDateTime(
        hour: 12 + (i % 8),
        minute: (i * 7) % 60,
      );

      entries.add(
        PhotoEntry(
          date: date,
          title: '$title $i',
          location: location,
          timeFormatted:
              '${(i % 12) + 1}:${((i * 5) % 60).toString().padLeft(2, '0')} PM',
          gradientColors: palette,
          category: 'Daily Life',
          imagePath: includeVirtualImagePath
              ? '/virtual/photos/${currentKey.format()}_$i.jpg'
              : null,
          syncStatus: i % 5 == 0
              ? SyncStatus.synced
              : (i % 7 == 0 ? SyncStatus.pending : SyncStatus.localOnly),
          driveFileId: i % 5 == 0 ? 'drive_file_id_$i' : null,
          lastModifiedAt: date.toUtc(),
        ),
      );

      currentKey = currentKey.nextDay;
    }

    return entries;
  }

  /// Generates a Map of [DateKey] to [PhotoEntry] containing [count] entries.
  static Map<DateKey, PhotoEntry> generateEntryMap(
    int count, {
    DateKey? endDateKey,
    bool includeVirtualImagePath = true,
  }) {
    final list = generateEntries(
      count,
      endDateKey: endDateKey,
      includeVirtualImagePath: includeVirtualImagePath,
    );
    final map = <DateKey, PhotoEntry>{};
    for (final entry in list) {
      map[entry.dateKey] = entry;
    }
    return map;
  }

  /// Populates [store] with [count] synthetic entries.
  ///
  /// Uses internal memory injection when testing for instant setup of 5,000 entries.
  static void populateStore(
    PersistentDailyPhotoStore store,
    int count, {
    DateKey? endDateKey,
    bool includeVirtualImagePath = true,
  }) {
    final entries = generateEntries(
      count,
      endDateKey: endDateKey,
      includeVirtualImagePath: includeVirtualImagePath,
    );
    for (final entry in entries) {
      store.setPhoto(entry);
    }
  }
}
