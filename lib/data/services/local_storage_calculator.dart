import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';

/// Service responsible for calculating actual local disk storage consumed
/// by app-managed photo files.
///
/// Guarantees:
/// - Exact disk usage: Sums actual byte lengths on disk; never estimates based on photo count.
/// - Scope isolated: Scans ONLY files managed by [PersistentDailyPhotoStore]; ignores unrelated app files.
/// - Resilient: Gracefully handles missing files, zero-byte files, and unreadable files without crashing.
/// - De-duplicated: Ensures each unique file path is counted at most once.
class LocalStorageCalculator {
  const LocalStorageCalculator();

  /// Practical threshold in bytes for local photo storage warning.
  /// Defaults to [AppConstants.photoStorageWarningThresholdBytes] (500 MB).
  static int storageWarningThresholdBytes =
      AppConstants.photoStorageWarningThresholdBytes;

  /// Checks whether local photo storage exceeds the warning threshold.
  static bool isStorageWarning({required int bytes, int? customThreshold}) {
    final threshold = customThreshold ?? storageWarningThresholdBytes;
    return bytes >= threshold;
  }

  /// Calculates total bytes used by all app-managed photo files on disk.
  static Future<int> calculateTotalPhotoBytes({
    required PersistentDailyPhotoStore store,
  }) async {
    final entries = store.allEntries;
    int totalBytes = 0;
    final processedPaths = <String>{};

    for (final entry in entries) {
      final path = entry.imagePath;
      if (path == null || path.trim().isEmpty) continue;

      final normalizedPath = path.trim();
      if (!processedPaths.add(normalizedPath)) {
        // File path already accounted for
        continue;
      }

      try {
        final file = File(normalizedPath);
        if (await file.exists()) {
          final length = await file.length();
          if (length > 0) {
            totalBytes += length;
          }
        }
      } catch (e) {
        // File system errors, permission issues, or file-locked exceptions
        // are caught safely so one unreadable file never crashes the calculation.
        debugPrint(
          'LocalStorageCalculator: Safely ignored unreadable file "$normalizedPath": $e',
        );
      }
    }

    return totalBytes;
  }

  /// Synchronously calculates total bytes from entries whose files are immediately readable.
  static int calculateTotalPhotoBytesSync({
    required PersistentDailyPhotoStore store,
  }) {
    final entries = store.allEntries;
    int totalBytes = 0;
    final processedPaths = <String>{};

    for (final entry in entries) {
      final path = entry.imagePath;
      if (path == null || path.trim().isEmpty) continue;

      final normalizedPath = path.trim();
      if (!processedPaths.add(normalizedPath)) continue;

      try {
        final file = File(normalizedPath);
        if (file.existsSync()) {
          final length = file.lengthSync();
          if (length > 0) {
            totalBytes += length;
          }
        }
      } catch (_) {
        // Ignored safely
      }
    }

    return totalBytes;
  }

  /// Formats a byte count into a calm, human-readable storage string.
  ///
  /// Examples:
  /// - 0 bytes -> "0 B used"
  /// - 512 bytes -> "512 B used"
  /// - 1024 * 50 bytes -> "50 KB used"
  /// - 142 * 1024 * 1024 bytes -> "142 MB used"
  /// - 1.5 * 1024 * 1024 bytes -> "1.5 MB used"
  /// - 2.4 * 1024 * 1024 * 1024 bytes -> "2.4 GB used"
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B used';

    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int unitIndex = 0;
    double size = bytes.toDouble();

    while (size >= 1024.0 && unitIndex < units.length - 1) {
      size /= 1024.0;
      unitIndex++;
    }

    if (unitIndex == 0) {
      return '$bytes B used';
    } else if (size >= 100.0 || size == size.roundToDouble()) {
      return '${size.toStringAsFixed(0)} ${units[unitIndex]} used';
    } else {
      return '${size.toStringAsFixed(1)} ${units[unitIndex]} used';
    }
  }
}
