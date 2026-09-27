import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';

/// Structured result of a diary export operation.
class ExportResult {
  const ExportResult({
    this.zipFile,
    required this.exportedCount,
    required this.skippedCount,
    required this.totalEntries,
    this.archiveSizeBytes = 0,
    this.isSuccess = false,
    this.isPartial = false,
    this.isEmpty = false,
    this.errorMessage,
  });

  /// The generated ZIP archive file, or null if no archive was produced.
  final File? zipFile;

  /// Count of photo entries successfully included in the export archive.
  final int exportedCount;

  /// Count of photo entries that were skipped due to missing or unreadable files.
  final int skippedCount;

  /// Total count of photo entries evaluated for export.
  final int totalEntries;

  /// Total size of the generated ZIP archive in bytes.
  final int archiveSizeBytes;

  /// Whether the export completed with 100% of photos exported without errors.
  final bool isSuccess;

  /// Whether the export was partial (some photos exported, but some were skipped).
  final bool isPartial;

  /// Whether there were zero photos in the diary to export.
  final bool isEmpty;

  /// Error message if the export failed entirely.
  final String? errorMessage;

  factory ExportResult.empty() {
    return const ExportResult(
      exportedCount: 0,
      skippedCount: 0,
      totalEntries: 0,
      isEmpty: true,
      isSuccess: false,
    );
  }

  factory ExportResult.failure({
    required String errorMessage,
    int exportedCount = 0,
    int skippedCount = 0,
    int totalEntries = 0,
  }) {
    return ExportResult(
      zipFile: null,
      exportedCount: exportedCount,
      skippedCount: skippedCount,
      totalEntries: totalEntries,
      errorMessage: errorMessage,
      isSuccess: false,
      isPartial: false,
      isEmpty: false,
    );
  }
}

/// Service that exports the user's Photo a Day diary into a portable ZIP archive.
///
/// Principles:
/// - **Local-First**: Operates strictly on the local photo store without needing
///   Google Drive connectivity, credentials, or network access.
/// - **Clean Metadata**: Generates a standard JSON manifest with versioning, dates,
///   titles, captions, and locations. Never includes OAuth tokens, secrets, or internal sync state.
/// - **Memory Efficient**: Streams photo files directly to the ZIP archive on disk
///   without loading the entire photo library into RAM.
/// - **Resilient**: Gracefully handles missing, empty, or unreadable photo files,
///   recording them in the manifest and marking the export as partial instead of crashing.
/// - **Safe Paths**: Protects against directory traversal (`../`) using deterministic naming.
class DiaryExportService {
  DiaryExportService({this.store, this.defaultExportDir});

  final PersistentDailyPhotoStore? store;
  final Directory? defaultExportDir;

  PersistentDailyPhotoStore get _effectiveStore =>
      store ?? PersistentDailyPhotoStore.instance;

  static DiaryExportService? _instance;

  /// The active singleton instance.
  static DiaryExportService get instance => _instance ??= DiaryExportService();

  @visibleForTesting
  static void setTestInstance(DiaryExportService service) {
    _instance = service;
  }

  @visibleForTesting
  static void resetTestInstance() {
    _instance = null;
  }

  static const int currentExportVersion = 1;
  static const String exportDirectoryName = 'diary_exports';

  /// Resolves the dedicated temporary directory used for export archives.
  Future<Directory> getExportDirectory({
    Directory? customExportDir,
    Directory? customBaseDir,
  }) async {
    final effectiveDir = customExportDir ?? defaultExportDir;
    if (effectiveDir != null) {
      if (!await effectiveDir.exists()) {
        await effectiveDir.create(recursive: true);
      }
      return effectiveDir;
    }
    final Directory base = customBaseDir ?? await getTemporaryDirectory();
    final exportDir = Directory(p.join(base.path, exportDirectoryName));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    return exportDir;
  }

  /// Exports the local diary to a ZIP archive containing all valid photo files
  /// and a `manifest.json` metadata file.
  Future<ExportResult> exportDiary({Directory? customExportDir}) async {
    final store = _effectiveStore;
    final entries = store.allEntries;

    if (entries.isEmpty) {
      return ExportResult.empty();
    }

    final exportDir = await getExportDirectory(
      customExportDir: customExportDir,
    );
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final zipPath = p.join(exportDir.path, 'photo_a_day_export_$timestamp.zip');
    final zipFile = File(zipPath);

    final encoder = ZipFileEncoder();
    try {
      encoder.create(zipPath);

      final exportedPhotos = <Map<String, dynamic>>[];
      final skippedPhotos = <Map<String, dynamic>>[];

      // Sort entries chronologically for deterministic manifest order
      final sortedEntries = List<PhotoEntry>.from(entries)
        ..sort((a, b) => a.date.compareTo(b.date));

      for (final entry in sortedEntries) {
        final dateKeyStr = entry.dateKey.format();
        final imagePath = entry.imagePath;

        if (imagePath == null || imagePath.trim().isEmpty) {
          skippedPhotos.add({
            'date': dateKeyStr,
            'reason': 'No local image path recorded for entry',
          });
          continue;
        }

        final photoFile = File(imagePath.trim());
        if (!await photoFile.exists()) {
          skippedPhotos.add({
            'date': dateKeyStr,
            'reason': 'Photo file does not exist on disk',
          });
          continue;
        }

        int fileSize = 0;
        try {
          fileSize = await photoFile.length();
        } catch (e) {
          skippedPhotos.add({
            'date': dateKeyStr,
            'reason': 'Failed to read photo file size: $e',
          });
          continue;
        }

        if (fileSize == 0) {
          skippedPhotos.add({
            'date': dateKeyStr,
            'reason': 'Photo file is empty (0 bytes)',
          });
          continue;
        }

        // Determine safe filename inside the archive
        final rawExt = p.extension(imagePath).toLowerCase();
        final safeExt =
            (rawExt == '.png' || rawExt == '.jpg' || rawExt == '.jpeg')
            ? rawExt
            : '.jpg';
        final safeArchiveFilename = 'photos/$dateKeyStr$safeExt';

        try {
          await encoder.addFile(photoFile, safeArchiveFilename);

          final photoMetadata = <String, dynamic>{
            'date': dateKeyStr,
            'filename': safeArchiveFilename,
            'title': entry.title,
            if (entry.caption != null && entry.caption!.trim().isNotEmpty)
              'caption': entry.caption!.trim(),
            if (entry.location != null && entry.location!.trim().isNotEmpty)
              'location': entry.location!.trim(),
            'category': entry.category,
            'timeFormatted': entry.timeFormatted,
            'createdAt': entry.date.toUtc().toIso8601String(),
            'lastModifiedAt': entry.effectiveLastModifiedAt.toIso8601String(),
          };

          exportedPhotos.add(photoMetadata);
        } catch (e) {
          skippedPhotos.add({
            'date': dateKeyStr,
            'reason': 'Failed to archive photo file: $e',
          });
        }
      }

      // If all photos were skipped (e.g. all files missing)
      if (exportedPhotos.isEmpty) {
        await encoder.close();
        if (await zipFile.exists()) {
          await zipFile.delete();
        }
        return ExportResult.failure(
          errorMessage:
              'None of the ${entries.length} photo files could be read from disk.',
          skippedCount: skippedPhotos.length,
          totalEntries: entries.length,
        );
      }

      // Build manifest JSON without any credentials, tokens, or sync internals
      final manifestMap = <String, dynamic>{
        'exportVersion': currentExportVersion,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'appName': 'Photo a Day',
        'totalPhotos': exportedPhotos.length,
        'photos': exportedPhotos,
        if (skippedPhotos.isNotEmpty) 'skippedPhotos': skippedPhotos,
      };

      final manifestString = const JsonEncoder.withIndent(
        '  ',
      ).convert(manifestMap);
      final manifestBytes = utf8.encode(manifestString);

      encoder.addArchiveFile(ArchiveFile.bytes('manifest.json', manifestBytes));

      await encoder.close();

      final archiveSize = await zipFile.length();
      final isPartial = skippedPhotos.isNotEmpty;

      return ExportResult(
        zipFile: zipFile,
        exportedCount: exportedPhotos.length,
        skippedCount: skippedPhotos.length,
        totalEntries: entries.length,
        archiveSizeBytes: archiveSize,
        isSuccess: !isPartial,
        isPartial: isPartial,
      );
    } catch (e) {
      try {
        await encoder.close();
      } catch (_) {}
      if (await zipFile.exists()) {
        try {
          await zipFile.delete();
        } catch (_) {}
      }
      return ExportResult.failure(
        errorMessage: 'Export failed with error: $e',
        totalEntries: entries.length,
      );
    }
  }

  /// Removes all temporary ZIP export archives created by the app.
  Future<int> cleanTemporaryExports({
    Directory? customExportDir,
    Directory? customBaseDir,
  }) async {
    try {
      final exportDir = await getExportDirectory(
        customExportDir: customExportDir,
        customBaseDir: customBaseDir,
      );
      if (!await exportDir.exists()) return 0;

      int deletedCount = 0;
      final entities = exportDir.listSync();
      for (final entity in entities) {
        if (entity is File &&
            p.basename(entity.path).startsWith('photo_a_day_export_') &&
            entity.path.endsWith('.zip')) {
          try {
            await entity.delete();
            deletedCount++;
          } catch (_) {}
        }
      }
      return deletedCount;
    } catch (e) {
      debugPrint('Error cleaning temporary exports: $e');
      return 0;
    }
  }
}
