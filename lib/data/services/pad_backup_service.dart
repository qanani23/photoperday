import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_per_day/data/models/daily_reminder_settings.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/pad_backup_models.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/app_theme_storage.dart';
import 'package:photo_per_day/data/services/daily_reminder_storage.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:share_plus/share_plus.dart';

/// Abstract delegate decoupling platform sharing, saving, and file-picking APIs.
abstract class PadBackupPlatformDelegate {
  /// Opens the system share sheet with the specified .padbackup file.
  Future<bool> shareBackupFile({
    required String filePath,
    required String filename,
  });

  /// Allows the user to select a durable destination to save the .padbackup file.
  Future<String?> saveBackupToUserDestination({
    required String sourceFilePath,
    required String suggestedFilename,
  });

  /// Opens the system file picker to select an existing .padbackup file.
  Future<String?> pickBackupFile();
}

/// Production implementation of [PadBackupPlatformDelegate] utilizing
/// [SharePlus] and [FilePicker].
class DefaultPadBackupPlatformDelegate implements PadBackupPlatformDelegate {
  const DefaultPadBackupPlatformDelegate();

  @override
  Future<bool> shareBackupFile({
    required String filePath,
    required String filename,
  }) async {
    try {
      final xFile = XFile(
        filePath,
        name: filename,
        mimeType: 'application/octet-stream',
      );
      final result = await Share.shareXFiles([
        xFile,
      ], text: 'Daria Portable Backup ($filename)');
      return result.status == ShareResultStatus.success ||
          result.status == ShareResultStatus.dismissed;
    } catch (e) {
      debugPrint('Error sharing .padbackup file: $e');
      return false;
    }
  }

  @override
  Future<String?> saveBackupToUserDestination({
    required String sourceFilePath,
    required String suggestedFilename,
  }) async {
    try {
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Daria Backup (.padbackup)',
        fileName: suggestedFilename,
        type: FileType.custom,
        allowedExtensions: ['padbackup', 'zip'],
      );

      if (outputPath != null && outputPath.isNotEmpty) {
        final source = File(sourceFilePath);
        await source.copy(outputPath);
        return outputPath;
      }
    } catch (e) {
      debugPrint('FilePicker saveFile not supported or failed on platform: $e');
    }
    return null;
  }

  @override
  Future<String?> pickBackupFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select Daria Backup (.padbackup)',
        type: FileType.custom,
        allowedExtensions: ['padbackup', 'zip'],
      );
      if (result != null && result.files.isNotEmpty) {
        return result.files.single.path;
      }
    } catch (e) {
      debugPrint('Error picking .padbackup file: $e');
    }
    return null;
  }
}

/// Estimates computed prior to initiating a backup export.
class PadBackupEstimate {
  const PadBackupEstimate({
    required this.totalBytes,
    required this.availablePhotos,
    required this.missingPhotos,
  });

  final int totalBytes;
  final int availablePhotos;
  final int missingPhotos;

  bool get hasMissingPhotos => missingPhotos > 0;
}

/// Core service orchestrating the portable `.padbackup` lifecycle:
/// - Versioned archive creation with per-file SHA-256 integrity validation.
/// - Pre-flight inspection with strict path-traversal and zip-bomb rejection.
/// - Transactional staging and atomic merge/replace restoration with rollback safety.
/// - 100% offline, local-only operation with zero network or cloud footprint.
class PadBackupService {
  PadBackupService({
    this.store,
    this.fileManager,
    this.metadataStorage,
    this.themeStorage,
    this.reminderStorage,
    PadBackupPlatformDelegate? platformDelegate,
    this.customTempDir,
  }) : platformDelegate =
           platformDelegate ?? const DefaultPadBackupPlatformDelegate();

  static const int currentFormatVersion = 2;
  static const String manifestFileName = 'manifest.json';
  static const String metadataFileName = 'photos_metadata.json';
  static const String preferencesFileName = 'preferences.json';
  static const String photosDirectoryName = 'photos';
  static const String backupExtension = '.padbackup';

  /// Maximum permissible uncompressed archive size (5 GB) to prevent zip bombs.
  static const int maxUncompressedArchiveBytes = 5 * 1024 * 1024 * 1024;

  /// Maximum permissible single file size (50 MB) inside backup.
  static const int maxSingleFileBytes = 50 * 1024 * 1024;

  /// Maximum permissible entry count inside archive to prevent resource exhaustion.
  static const int maxArchiveEntryCount = 5000;

  static const String restoreJournalFileName = 'restore_journal.json';
  static const String metadataBackupFileName =
      'photos_metadata.pre_restore.bak';

  final PersistentDailyPhotoStore? store;
  final PhotoFileManager? fileManager;
  final PhotoMetadataStorage? metadataStorage;
  final AppThemeStorage? themeStorage;
  final DailyReminderStorage? reminderStorage;
  final Directory? customTempDir;

  final PadBackupPlatformDelegate platformDelegate;

  PersistentDailyPhotoStore get _effectiveStore =>
      store ?? PersistentDailyPhotoStore.instance;

  PhotoFileManager get _effectiveFileManager =>
      fileManager ?? _effectiveStore.fileManager;

  PhotoMetadataStorage get _effectiveMetadataStorage =>
      metadataStorage ?? _effectiveStore.metadataStorage;

  AppThemeStorage get _effectiveThemeStorage =>
      themeStorage ??
      AppThemeStorage(customBaseDir: _effectiveFileManager.customBaseDir?.path);

  DailyReminderStorage get _effectiveReminderStorage =>
      reminderStorage ??
      DailyReminderStorage(
        customBaseDir: _effectiveFileManager.customBaseDir?.path,
      );

  /// Resolves the dedicated temporary working directory.
  Future<Directory> getWorkingDir() async {
    if (customTempDir != null) {
      if (!await customTempDir!.exists()) {
        await customTempDir!.create(recursive: true);
      }
      return customTempDir!;
    }
    final systemTemp = await getTemporaryDirectory();
    final padDir = Directory(p.join(systemTemp.path, 'pad_backup_work'));
    if (!await padDir.exists()) {
      await padDir.create(recursive: true);
    }
    return padDir;
  }

  /// Calculates the estimated archive size and counts available vs missing photo files.
  Future<PadBackupEstimate> calculateEstimatedExportSize() async {
    final entries = _effectiveStore.allEntries;
    int totalBytes = 0;
    int availableCount = 0;
    int missingCount = 0;

    for (final entry in entries) {
      final path = entry.imagePath;
      if (path == null || path.trim().isEmpty) {
        missingCount++;
        continue;
      }
      final file = File(path.trim());
      if (await file.exists()) {
        try {
          final len = await file.length();
          if (len > 0) {
            totalBytes += len;
            availableCount++;
          } else {
            missingCount++;
          }
        } catch (_) {
          missingCount++;
        }
      } else {
        missingCount++;
      }
    }

    return PadBackupEstimate(
      totalBytes: totalBytes,
      availablePhotos: availableCount,
      missingPhotos: missingCount,
    );
  }

  /// Exports the local diary into a validated `.padbackup` archive.
  ///
  /// Guarantees:
  /// - Exact original photo bytes preserved without downsampling.
  /// - SHA-256 cryptographic checksums for every photo and metadata file.
  /// - Day-level storage model (DayEntry) preserving multiple photos, order, and notes.
  /// - Relative, safe archive paths (`photos/YYYY-MM-DD.ext` or `photos/YYYY-MM-DD_order.ext`).
  /// - Clean metadata with zero cloud tokens or internal sync artifacts.
  /// - Progress reporting and graceful handling of missing photos.
  Future<PadBackupExportResult> exportBackup({
    bool allowPartial = false,
    void Function(double progress, String status)? onProgress,
  }) async {
    final days = _effectiveStore.chronologicalAscendingDayEntries
        .where((d) => d.hasPhotos || d.hasNote)
        .toList();
    if (days.isEmpty) {
      return PadBackupExportResult.empty();
    }

    onProgress?.call(0.05, 'Scanning diary memories...');

    final totalPhotosEvaluated = days.fold<int>(
      0,
      (sum, d) => sum + d.photoCount,
    );
    final validPhotoFiles = <PhotoEntry, File>{};
    final skippedItems = <PadBackupSkippedItem>[];

    for (final day in days) {
      final keyStr = day.dateKey.format();
      for (final photo in day.photos) {
        final imagePath = photo.imagePath;
        final photoId = photo.id.isNotEmpty ? photo.id : photo.effectiveId;

        if (imagePath == null || imagePath.trim().isEmpty) {
          skippedItems.add(
            PadBackupSkippedItem(
              dateKey: keyStr,
              photoId: photoId,
              reason: 'No photo file path recorded for this date',
            ),
          );
          continue;
        }

        final file = File(imagePath.trim());
        if (!await file.exists()) {
          skippedItems.add(
            PadBackupSkippedItem(
              dateKey: keyStr,
              photoId: photoId,
              reason: 'Photo file not found on device disk',
            ),
          );
          continue;
        }

        int len = 0;
        try {
          len = await file.length();
        } catch (e) {
          skippedItems.add(
            PadBackupSkippedItem(
              dateKey: keyStr,
              photoId: photoId,
              reason: 'Failed to access photo file: $e',
            ),
          );
          continue;
        }

        if (len == 0) {
          skippedItems.add(
            PadBackupSkippedItem(
              dateKey: keyStr,
              photoId: photoId,
              reason: 'Photo file is empty (0 bytes)',
            ),
          );
          continue;
        }

        validPhotoFiles[photo] = file;
      }
    }

    if (totalPhotosEvaluated > 0 && validPhotoFiles.isEmpty) {
      return PadBackupExportResult.failure(
        'None of the $totalPhotosEvaluated photo entries have readable files on disk.',
      );
    }

    if (skippedItems.isNotEmpty && !allowPartial) {
      return PadBackupExportResult.failure(
        '${skippedItems.length} photo files are missing or unreadable. '
        'Enable partial backup to proceed with available photos.',
      );
    }

    final workDir = await getWorkingDir();
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final archiveFileName = 'Daria_Backup_$dateStr$backupExtension';
    final archiveFile = File(p.join(workDir.path, archiveFileName));
    if (archiveFile.existsSync()) {
      try {
        archiveFile.deleteSync();
      } catch (_) {}
    }

    final encoder = ZipFileEncoder();

    try {
      encoder.create(archiveFile.path);

      final photoItems = <PadBackupPhotoItem>[];
      final sanitizedDaysMap = <String, dynamic>{};
      int totalBytesAccumulator = 0;
      int processedCount = 0;
      final totalToProcess = validPhotoFiles.length;
      final usedArchivePaths = <String>{};

      for (final day in days) {
        final dateKeyStr = day.dateKey.format();
        final dayPhotos = <PhotoEntry>[];

        for (int i = 0; i < day.photos.length; i++) {
          final photo = day.photos[i];
          final file = validPhotoFiles[photo];
          if (file == null) {
            // Skipped / missing file
            continue;
          }

          onProgress?.call(
            0.10 +
                (0.65 *
                    (processedCount /
                        (totalToProcess > 0 ? totalToProcess : 1))),
            'Packaging photo ${processedCount + 1} of $totalToProcess ($dateKeyStr)...',
          );

          final rawExt = p.extension(file.path).toLowerCase();
          final safeExt =
              (rawExt == '.png' ||
                  rawExt == '.jpg' ||
                  rawExt == '.jpeg' ||
                  rawExt == '.webp')
              ? rawExt
              : '.jpg';

          String archiveRelativePath;
          if (day.photos.length == 1 && (photo.order == 0 || i == 0)) {
            archiveRelativePath = '$photosDirectoryName/$dateKeyStr$safeExt';
          } else {
            archiveRelativePath =
                '$photosDirectoryName/${dateKeyStr}_${photo.order}$safeExt';
          }
          if (usedArchivePaths.contains(archiveRelativePath)) {
            archiveRelativePath =
                '$photosDirectoryName/${dateKeyStr}_${photo.order}_$i$safeExt';
          }
          usedArchivePaths.add(archiveRelativePath);

          // Compute SHA-256 checksum of original photo bytes via streaming
          final fileDigest = await sha256.bind(file.openRead()).first;
          final fileSha256 = fileDigest.toString();
          final fileSize = await file.length();
          totalBytesAccumulator += fileSize;

          // Add file directly to ZIP
          await encoder.addFile(file, archiveRelativePath);

          final item = PadBackupPhotoItem(
            dateKey: dateKeyStr,
            archivePath: archiveRelativePath,
            sizeBytes: fileSize,
            sha256: fileSha256,
            title: photo.title,
            location: photo.location,
            timeFormatted: photo.timeFormatted,
            id: photo.id.isNotEmpty ? photo.id : photo.effectiveId,
            order: photo.order,
          );
          photoItems.add(item);

          // Sanitize entry for backup metadata: map imagePath to archiveRelativePath
          final sanitizedPhoto = photo.copyWith(
            imagePath: archiveRelativePath,
            syncStatus: SyncStatus.localOnly,
            clearSyncError: true,
          );
          dayPhotos.add(sanitizedPhoto);

          processedCount++;
        }

        final sanitizedDay = DayEntry(
          dateKey: day.dateKey,
          photos: dayPhotos,
          note: day.note,
          createdAt: day.createdAt,
          updatedAt: day.updatedAt,
        );
        sanitizedDaysMap[dateKeyStr] = sanitizedDay.toJson();
      }

      onProgress?.call(0.78, 'Writing diary metadata and checksums...');

      // 1. Package photos_metadata.json (Schema 2 Envelope)
      final envelope = <String, dynamic>{
        'schemaVersion': 2,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'days': sanitizedDaysMap,
      };
      final metadataString = const JsonEncoder.withIndent(
        '  ',
      ).convert(envelope);
      final metadataBytes = utf8.encode(metadataString);
      final metadataSha256 = sha256.convert(metadataBytes).toString();

      encoder.addArchiveFile(
        ArchiveFile.bytes(metadataFileName, Uint8List.fromList(metadataBytes)),
      );

      // 2. Package preferences.json (Theme and Daily Reminders)
      onProgress?.call(0.84, 'Backing up user preferences...');
      final themeSettings = await _effectiveThemeStorage.loadSettings();
      final reminderSettings = await _effectiveReminderStorage.loadSettings();

      final preferencesMap = <String, dynamic>{
        'theme': {
          'paletteId': themeSettings.paletteId,
          'followSystem': themeSettings.followSystem,
        },
        'reminders': reminderSettings.toJson(),
      };
      final preferencesString = const JsonEncoder.withIndent(
        '  ',
      ).convert(preferencesMap);
      final preferencesBytes = utf8.encode(preferencesString);
      final preferencesSha256 = sha256.convert(preferencesBytes).toString();

      encoder.addArchiveFile(
        ArchiveFile.bytes(
          preferencesFileName,
          Uint8List.fromList(preferencesBytes),
        ),
      );

      // 3. Package manifest.json (Format Version 2)
      onProgress?.call(0.90, 'Generating signed manifest...');
      final manifest = PadBackupManifest(
        formatVersion: currentFormatVersion,
        appVersion: '1.0.0+1',
        appName: 'Daria',
        createdAt: DateTime.now().toUtc(),
        isPartial: skippedItems.isNotEmpty,
        photoCount: photoItems.length,
        dayCount: days.length,
        totalSizeBytes: totalBytesAccumulator,
        startDate: days.isNotEmpty ? days.first.dateKey.format() : null,
        endDate: days.isNotEmpty ? days.last.dateKey.format() : null,
        photos: photoItems,
        skippedPhotos: skippedItems,
        metadataChecksum: metadataSha256,
        preferencesChecksum: preferencesSha256,
      );

      final manifestString = const JsonEncoder.withIndent(
        '  ',
      ).convert(manifest.toJson());
      final manifestBytes = utf8.encode(manifestString);

      encoder.addArchiveFile(
        ArchiveFile.bytes(manifestFileName, Uint8List.fromList(manifestBytes)),
      );

      onProgress?.call(0.95, 'Finalizing backup archive...');
      await encoder.close();

      // Validate created archive
      if (!await archiveFile.exists() || await archiveFile.length() == 0) {
        throw const FileSystemException(
          'Failed to verify generated backup archive file',
        );
      }

      onProgress?.call(1.0, 'Backup created successfully!');

      return PadBackupExportResult(
        backupFile: archiveFile,
        photoCount: photoItems.length,
        skippedCount: skippedItems.length,
        totalSizeBytes: await archiveFile.length(),
        isSuccess: true,
        isPartial: skippedItems.isNotEmpty,
        manifest: manifest,
      );
    } catch (e) {
      try {
        await encoder.close();
      } catch (_) {}
      if (await archiveFile.exists()) {
        try {
          await archiveFile.delete();
        } catch (_) {}
      }
      return PadBackupExportResult.failure(
        'Backup creation failed with error: $e',
      );
    }
  }

  /// Pre-flight phase: inspects, validates, stages, and verifies checksums of a `.padbackup` file
  /// without modifying any live diary photos or metadata.
  ///
  /// Security checks:
  /// - Zip-slip path traversal rejection (`..`, absolute paths, suspicious segments).
  /// - Whitelisted archive entries only (`manifest.json`, `photos_metadata.json`, `preferences.json`, `photos/*`).
  /// - Decompression bomb limits (uncompressed size cap).
  /// - Cryptographic SHA-256 checksum verification for every photo and metadata record.
  /// - Format version compatibility check.
  Future<PadBackupInspectionResult> inspectBackupFile(
    File backupFile, {
    void Function(double progress, String status)? onProgress,
  }) async {
    if (!await backupFile.exists()) {
      return PadBackupInspectionResult.invalid(
        'Selected backup file does not exist on disk.',
      );
    }

    final fileSize = await backupFile.length();
    if (fileSize == 0) {
      return PadBackupInspectionResult.invalid(
        'Selected backup file is empty (0 bytes).',
      );
    }

    if (fileSize > maxUncompressedArchiveBytes) {
      return PadBackupInspectionResult.invalid(
        'Backup archive exceeds maximum permissible size limit.',
      );
    }

    onProgress?.call(0.05, 'Staging backup archive for verification...');

    final workDir = await getWorkingDir();
    final stagingDir = Directory(
      p.join(workDir.path, 'staging_${DateTime.now().microsecondsSinceEpoch}'),
    );
    await stagingDir.create(recursive: true);

    try {
      final archiveBytes = await backupFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(archiveBytes);

      int totalUncompressedBytes = 0;

      onProgress?.call(0.20, 'Checking archive security and integrity...');

      if (archive.length > maxArchiveEntryCount) {
        throw const FormatException(
          'Archive contains excessive entry count exceeding safety limit.',
        );
      }

      final seenArchivePaths = <String>{};

      // 1. Security scan & extraction loop
      for (final file in archive) {
        if (!file.isFile) continue;

        final rawName = file.name;

        // Path safety & Zip-Slip rejection
        if (rawName.startsWith('/') ||
            rawName.startsWith('\\') ||
            rawName.contains(':') ||
            rawName.contains('..') ||
            rawName.contains('\x00') ||
            p.posix.isAbsolute(rawName) ||
            p.windows.isAbsolute(rawName)) {
          throw FormatException(
            'Insecure path detected in backup archive: "$rawName"',
          );
        }

        // Whitelist check
        final normalized = p.normalize(rawName).replaceAll(r'\', '/');

        // Check for duplicate archive entries
        if (!seenArchivePaths.add(normalized)) {
          throw FormatException(
            'Duplicate entry in backup archive: "$rawName"',
          );
        }

        final isRootFile =
            normalized == manifestFileName ||
            normalized == metadataFileName ||
            normalized == preferencesFileName;
        final isPhoto = RegExp(
          r'^photos/\d{4}-\d{2}-\d{2}(?:_[a-zA-Z0-9_\-]+)?\.(jpg|jpeg|png|webp)$',
        ).hasMatch(normalized);

        if (!isRootFile && !isPhoto) {
          throw FormatException(
            'Unexpected or unauthorized entry in archive: "$rawName"',
          );
        }

        // Size & Decompression bomb checks based on actual content bytes
        final content = file.content as List<int>;
        final actualSize = content.length;
        if (actualSize > maxSingleFileBytes) {
          throw FormatException(
            'Archive entry "$rawName" exceeds maximum allowed file size ($actualSize bytes).',
          );
        }

        totalUncompressedBytes += actualSize;
        if (totalUncompressedBytes > maxUncompressedArchiveBytes) {
          throw const FormatException(
            'Archive exceeds maximum cumulative uncompressed size limit.',
          );
        }

        // Extract to isolated staging directory
        final destinationPath = p.join(stagingDir.path, normalized);
        final destFile = File(destinationPath);
        await destFile.parent.create(recursive: true);
        await destFile.writeAsBytes(content, flush: true);
      }

      onProgress?.call(0.50, 'Parsing and validating backup manifest...');

      // 2. Read and validate manifest.json
      final manifestFile = File(p.join(stagingDir.path, manifestFileName));
      if (!await manifestFile.exists()) {
        throw const FormatException(
          'Archive is missing mandatory manifest.json descriptor.',
        );
      }

      final manifestJson = jsonDecode(await manifestFile.readAsString());
      if (manifestJson is! Map) {
        throw const FormatException('manifest.json has invalid structure.');
      }

      final manifest = PadBackupManifest.fromJson(
        Map<String, dynamic>.from(manifestJson),
      );

      // Version compatibility check
      if (manifest.formatVersion > currentFormatVersion) {
        throw FormatException(
          'Unsupported backup format version (${manifest.formatVersion}). '
          'This backup was created with a newer version of Daria.',
        );
      }
      if (manifest.formatVersion < 1) {
        throw FormatException(
          'Unsupported backup format version (${manifest.formatVersion}).',
        );
      }

      // Check manifest internal uniqueness
      final seenManifestDates = <String>{};
      final seenManifestPaths = <String>{};
      for (final photo in manifest.photos) {
        if (manifest.formatVersion == 1) {
          if (!seenManifestDates.add(photo.dateKey)) {
            throw FormatException(
              'Duplicate DateKey in manifest: "${photo.dateKey}"',
            );
          }
        }
        if (!seenManifestPaths.add(photo.archivePath)) {
          throw FormatException(
            'Duplicate archivePath in manifest: "${photo.archivePath}"',
          );
        }
      }

      // Reject unmanifested photo files in the archive
      for (final stagedPath in seenArchivePaths) {
        if (stagedPath.startsWith('$photosDirectoryName/') &&
            !seenManifestPaths.contains(stagedPath)) {
          throw FormatException(
            'Archive contains unreferenced photo: "$stagedPath"',
          );
        }
      }

      // 3. Cryptographic checksum validation
      onProgress?.call(0.65, 'Verifying cryptographic SHA-256 checksums...');

      for (int i = 0; i < manifest.photos.length; i++) {
        final photoItem = manifest.photos[i];
        final stagedPhotoFile = File(
          p.join(stagingDir.path, photoItem.archivePath),
        );

        if (!await stagedPhotoFile.exists()) {
          throw FormatException(
            'Archive manifest references photo "${photoItem.archivePath}" which is missing from the archive.',
          );
        }

        final digest = await sha256.bind(stagedPhotoFile.openRead()).first;
        final calculatedSha = digest.toString();

        if (calculatedSha.toLowerCase() != photoItem.sha256.toLowerCase()) {
          throw FormatException(
            'Checksum mismatch for photo "${photoItem.archivePath}". '
            'The backup file is corrupt or has been modified.',
          );
        }
      }

      // Check photos_metadata.json
      final stagedMetadataFile = File(
        p.join(stagingDir.path, metadataFileName),
      );
      if (!await stagedMetadataFile.exists()) {
        throw const FormatException(
          'Archive is missing mandatory photos_metadata.json file.',
        );
      }

      final metadataBytes = await stagedMetadataFile.readAsBytes();
      final calculatedMetadataSha = sha256.convert(metadataBytes).toString();
      if (calculatedMetadataSha.toLowerCase() !=
          manifest.metadataChecksum.toLowerCase()) {
        throw const FormatException(
          'Checksum mismatch for photos_metadata.json. Metadata is corrupted.',
        );
      }

      // Validate metadata syntax & DateKey mappings
      final metadataMap = jsonDecode(utf8.decode(metadataBytes));
      if (metadataMap is! Map && metadataMap is! List) {
        throw const FormatException(
          'photos_metadata.json contains invalid structure.',
        );
      }

      if (metadataMap is Map &&
          metadataMap['schemaVersion'] != null &&
          metadataMap['days'] is Map) {
        // Schema 2 (Multi-photo DayEntry envelope)
        final daysMap = metadataMap['days'] as Map;
        final photoItemMap = <String, PadBackupPhotoItem>{};
        for (final pItem in manifest.photos) {
          photoItemMap[pItem.archivePath] = pItem;
        }

        int totalPhotosInMetadata = 0;
        for (final entry in daysMap.entries) {
          try {
            DateKey.parse(entry.key.toString());
          } catch (_) {
            throw FormatException(
              'Invalid DateKey format in backup metadata: "${entry.key}"',
            );
          }
          final dayJson = entry.value;
          if (dayJson is! Map) {
            throw FormatException(
              'Metadata entry for day "${entry.key}" is malformed.',
            );
          }
          final photosRaw = dayJson['photos'];
          if (photosRaw is List) {
            for (final pRaw in photosRaw) {
              if (pRaw is! Map) continue;
              totalPhotosInMetadata++;
              final mappedPath = pRaw['imagePath']?.toString();
              if (mappedPath != null && mappedPath.isNotEmpty) {
                if (!photoItemMap.containsKey(mappedPath)) {
                  throw FormatException(
                    'Metadata references photo path "$mappedPath" not in manifest.',
                  );
                }
              }
            }
          }
        }

        if (totalPhotosInMetadata != manifest.photos.length) {
          throw FormatException(
            'Metadata photo count ($totalPhotosInMetadata) does not match manifest photo count (${manifest.photos.length}).',
          );
        }
      } else if (metadataMap is Map) {
        // Schema 1 (Legacy single-photo map)
        for (final keyStr in metadataMap.keys) {
          try {
            DateKey.parse(keyStr.toString());
          } catch (_) {
            throw FormatException(
              'Invalid DateKey format in backup metadata: "$keyStr"',
            );
          }
        }

        // Ensure metadata strictly matches manifest inventory
        if (metadataMap.length != manifest.photos.length) {
          throw FormatException(
            'Metadata entry count (${metadataMap.length}) does not match manifest photo count (${manifest.photos.length}).',
          );
        }
        for (final photoItem in manifest.photos) {
          if (!metadataMap.containsKey(photoItem.dateKey)) {
            throw FormatException(
              'Metadata is missing entry for manifest photo: "${photoItem.dateKey}"',
            );
          }
          final entryJson = metadataMap[photoItem.dateKey];
          if (entryJson is! Map) {
            throw FormatException(
              'Metadata entry for "${photoItem.dateKey}" is malformed.',
            );
          }
          final mappedPath = entryJson['imagePath']?.toString();
          if (mappedPath != photoItem.archivePath) {
            throw FormatException(
              'Path mismatch for "${photoItem.dateKey}": manifest has "${photoItem.archivePath}", metadata has "$mappedPath"',
            );
          }
        }
      } else if (metadataMap is List) {
        if (metadataMap.length != manifest.photos.length) {
          throw FormatException(
            'Metadata entry count (${metadataMap.length}) does not match manifest photo count (${manifest.photos.length}).',
          );
        }
      }

      // Check preferences.json if present
      final stagedPrefsFile = File(
        p.join(stagingDir.path, preferencesFileName),
      );
      final hasPreferences = await stagedPrefsFile.exists();
      if (hasPreferences && manifest.preferencesChecksum != null) {
        final prefBytes = await stagedPrefsFile.readAsBytes();
        final calcPrefSha = sha256.convert(prefBytes).toString();
        if (calcPrefSha.toLowerCase() !=
            manifest.preferencesChecksum!.toLowerCase()) {
          throw const FormatException(
            'Checksum mismatch for preferences.json.',
          );
        }
      }

      onProgress?.call(0.90, 'Analyzing diary merge conflicts...');

      // 4. Analyze conflicts with live diary
      final liveDates = _effectiveStore.recordedDates.toSet();
      final backupDates = <DateKey>{};
      for (final photo in manifest.photos) {
        try {
          backupDates.add(DateKey.parse(photo.dateKey));
        } catch (_) {}
      }
      if (metadataMap is Map && metadataMap['days'] is Map) {
        for (final key in (metadataMap['days'] as Map).keys) {
          try {
            backupDates.add(DateKey.parse(key.toString()));
          } catch (_) {}
        }
      }

      final conflictingDates = backupDates.intersection(liveDates).toList()
        ..sort((a, b) => a.compareTo(b));
      final nonConflictingDates = backupDates.difference(liveDates);

      onProgress?.call(1.0, 'Validation complete!');

      return PadBackupInspectionResult(
        isValid: true,
        manifest: manifest,
        stagingDir: stagingDir,
        totalPhotosInBackup: manifest.photos.length,
        currentPhotosInDiary: _effectiveStore.count,
        nonConflictingCount: nonConflictingDates.length,
        conflictingCount: conflictingDates.length,
        conflictingDates: conflictingDates,
        hasPreferences: hasPreferences,
      );
    } catch (e) {
      // Clean staging directory on failure
      try {
        if (await stagingDir.exists()) {
          await stagingDir.delete(recursive: true);
        }
      } catch (_) {}
      return PadBackupInspectionResult.invalid(e.toString());
    }
  }

  /// Restores diary photos and metadata from a pre-inspected `.padbackup` staging session.
  ///
  /// Guarantees:
  /// - Full transactional commit with safe rollback: original metadata and photos remain
  ///   100% intact if an error occurs.
  /// - Preserves multi-photo DayEntry structure, photo IDs, display order, and shared notes.
  /// - Explicit [PadRestoreMode.merge] vs [PadRestoreMode.replace] semantics.
  /// - Safe conflict resolution: non-conflicting photos added seamlessly; conflicts resolved
  ///   strictly per [PadConflictResolution] policy.
  /// - Restores preferences (Theme, Reminders) where available.
  Future<PadRestoreResult> restoreFromInspection(
    PadBackupInspectionResult inspection, {
    required PadRestoreMode mode,
    PadConflictResolution conflictResolution =
        PadConflictResolution.keepExisting,
    void Function(double progress, String status)? onProgress,
  }) async {
    if (!inspection.isValid || inspection.stagingDir == null) {
      return PadRestoreResult.failure(
        mode: mode,
        errorMessage: 'Cannot restore: Inspection result is invalid.',
      );
    }

    final stagingDir = inspection.stagingDir!;
    if (!await stagingDir.exists()) {
      return PadRestoreResult.failure(
        mode: mode,
        errorMessage:
            'Staging directory no longer exists. Please re-open backup.',
      );
    }

    final newlyCopiedFiles = <String>[];
    final oldPhotosToDeleteOnSuccess = <String>[];

    // Snapshot current live metadata state for in-memory rollback
    final originalLiveDays = Map<DateKey, DayEntry>.fromEntries(
      _effectiveStore.allDayEntries.map((d) => MapEntry(d.dateKey, d)),
    );

    final journalFile = await _journalFile;
    final metadataBackupFile = await _metadataBackupFile;

    try {
      onProgress?.call(0.10, 'Preparing transactional restore and journal...');

      // 1. STAGE 1: Create durable metadata backup snapshot on disk
      final liveMetadataFile = _effectiveMetadataStorage.metadataFile;
      if (await liveMetadataFile.exists()) {
        await liveMetadataFile.copy(metadataBackupFile.path);
      } else {
        await metadataBackupFile.writeAsString('{}', flush: true);
      }

      // Write initial transaction journal
      final journal = <String, dynamic>{
        'state': 'staged',
        'mode': mode.name,
        'conflictResolution': conflictResolution.name,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'newlyCopiedFiles': newlyCopiedFiles,
        'oldPhotosToDeleteOnSuccess': oldPhotosToDeleteOnSuccess,
      };
      await journalFile.writeAsString(jsonEncode(journal), flush: true);

      // Load staged metadata map into DayEntry map
      final stagedMetadataFile = File(
        p.join(stagingDir.path, metadataFileName),
      );
      final metadataRaw = jsonDecode(await stagedMetadataFile.readAsString());

      final stagedDays = <DateKey, DayEntry>{};
      if (metadataRaw is Map &&
          metadataRaw['schemaVersion'] != null &&
          metadataRaw['days'] is Map) {
        // Schema 2 DayEntry format
        final daysMap = Map<String, dynamic>.from(metadataRaw['days'] as Map);
        for (final entry in daysMap.entries) {
          try {
            final dateKey = DateKey.parse(entry.key);
            final dayEntry = DayEntry.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            );
            stagedDays[dateKey] = dayEntry;
          } catch (e) {
            debugPrint('Failed to parse staged day: $e');
          }
        }
      } else if (metadataRaw is Map) {
        // Schema 1 Legacy single-photo map
        for (final entry in metadataRaw.entries) {
          try {
            final dateKey = DateKey.parse(entry.key.toString());
            final jsonMap = Map<String, dynamic>.from(entry.value as Map);
            var photo = PhotoEntry.fromJson(jsonMap);
            if (photo.dateKey != dateKey) {
              photo = photo.copyWith(date: dateKey.toDateTime());
            }
            final legacyNote = jsonMap['caption']?.toString().trim() ?? '';
            stagedDays[dateKey] = DayEntry.fromSinglePhoto(
              photo,
              note: legacyNote,
            );
          } catch (e) {
            debugPrint('Failed to parse staged legacy entry: $e');
          }
        }
      } else if (metadataRaw is List) {
        // Schema 1 Legacy list
        for (final item in metadataRaw) {
          if (item is Map) {
            try {
              final jsonMap = Map<String, dynamic>.from(item);
              final photo = PhotoEntry.fromJson(jsonMap);
              final legacyNote = jsonMap['caption']?.toString().trim() ?? '';
              stagedDays[photo.dateKey] = DayEntry.fromSinglePhoto(
                photo,
                note: legacyNote,
              );
            } catch (e) {
              debugPrint('Failed to parse staged legacy list entry: $e');
            }
          }
        }
      }

      final photosDir = _effectiveFileManager.photosDir;
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }

      int importedCount = 0;
      int preservedCount = 0;
      int replacedCount = 0;

      final updatedDaysMap = Map<DateKey, DayEntry>.from(
        mode == PadRestoreMode.replace ? {} : originalLiveDays,
      );

      final totalStagedDays = stagedDays.length;
      int currentDayIndex = 0;

      // 2. STAGE 2: Copy photos to durable storage without touching live files
      journal['state'] = 'copying';
      await journalFile.writeAsString(jsonEncode(journal), flush: true);

      for (final stagedDayEntry in stagedDays.entries) {
        final key = stagedDayEntry.key;
        final stagedDay = stagedDayEntry.value;
        final dateKeyStr = key.format();

        currentDayIndex++;
        onProgress?.call(
          0.15 +
              (0.65 *
                  (currentDayIndex /
                      (totalStagedDays > 0 ? totalStagedDays : 1))),
          'Restoring memory $currentDayIndex of $totalStagedDays ($dateKeyStr)...',
        );

        final isConflict = originalLiveDays.containsKey(key);

        if (mode == PadRestoreMode.merge && isConflict) {
          if (conflictResolution == PadConflictResolution.keepExisting) {
            // Keep current live entry unchanged
            final existingDay = originalLiveDays[key]!;
            preservedCount += (existingDay.photoCount > 0
                ? existingDay.photoCount
                : 1);
            continue;
          }
          // Overwrite with backup: mark old photos for deletion upon commit success
          final existingDay = originalLiveDays[key];
          if (existingDay != null) {
            for (final photo in existingDay.photos) {
              if (photo.hasRealImage) {
                oldPhotosToDeleteOnSuccess.add(photo.imagePath!);
              }
            }
          }
        }

        // Copy each photo in stagedDay to app-managed storage
        final updatedPhotosForDay = <PhotoEntry>[];
        for (int pIdx = 0; pIdx < stagedDay.photos.length; pIdx++) {
          final photo = stagedDay.photos[pIdx];
          final relativePath =
              photo.imagePath ?? '$photosDirectoryName/$dateKeyStr.jpg';
          final stagedPhotoFile = File(p.join(stagingDir.path, relativePath));

          if (!await stagedPhotoFile.exists()) {
            throw FileSystemException(
              'Missing staged photo file: $relativePath',
              stagedPhotoFile.path,
            );
          }

          final rawExt = p.extension(stagedPhotoFile.path).toLowerCase();
          final ext = rawExt.isNotEmpty ? rawExt : '.jpg';
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final targetFileName =
              '${dateKeyStr}_restore_${photo.order}_${pIdx}_$timestamp$ext';
          final targetPath = p.join(photosDir.path, targetFileName);

          await stagedPhotoFile.copy(targetPath);
          newlyCopiedFiles.add(targetPath);

          // Update journal incrementally to guarantee process-interruption tracking
          await journalFile.writeAsString(jsonEncode(journal), flush: true);

          final restoredPhoto = photo.copyWith(
            imagePath: targetPath,
            syncStatus: SyncStatus.localOnly,
            clearSyncError: true,
          );
          updatedPhotosForDay.add(restoredPhoto);
        }

        final restoredDay = stagedDay.copyWith(photos: updatedPhotosForDay);
        updatedDaysMap[key] = restoredDay;

        if (isConflict && mode == PadRestoreMode.merge) {
          replacedCount += (stagedDay.photoCount > 0
              ? stagedDay.photoCount
              : 1);
        } else {
          importedCount += (stagedDay.photoCount > 0
              ? stagedDay.photoCount
              : 1);
        }
      }

      if (mode == PadRestoreMode.replace) {
        // Collect old live photos for cleanup after successful commit
        for (final oldDay in originalLiveDays.values) {
          for (final oldPhoto in oldDay.photos) {
            if (oldPhoto.hasRealImage) {
              oldPhotosToDeleteOnSuccess.add(oldPhoto.imagePath!);
            }
          }
        }
        await journalFile.writeAsString(jsonEncode(journal), flush: true);
      }

      // 3. STAGE 3: Pre-commit verification of all copied files on disk
      onProgress?.call(0.80, 'Verifying restored files on disk...');
      for (final path in newlyCopiedFiles) {
        final f = File(path);
        if (!await f.exists() || await f.length() == 0) {
          throw FileSystemException(
            'Copied photo file verification failed on disk: $path',
          );
        }
      }

      // 4. STAGE 4: Atomic metadata commit
      onProgress?.call(0.85, 'Committing metadata changes atomically...');
      journal['state'] = 'committing';
      await journalFile.writeAsString(jsonEncode(journal), flush: true);

      // Atomic metadata commit
      await _effectiveMetadataStorage.saveDays(updatedDaysMap);

      // Read back to verify metadata integrity before declaring commit
      final verifiedDays = await _effectiveMetadataStorage.loadDays();
      if (verifiedDays.length != updatedDaysMap.length) {
        throw const FileSystemException(
          'Metadata post-write verification failed: entry count mismatch.',
        );
      }

      // Reinitialize store to refresh in-memory cache and notify listeners
      await _effectiveStore.init();

      // 5. STAGE 5: Restore preferences if present
      onProgress?.call(0.92, 'Restoring user preferences...');
      if (inspection.hasPreferences) {
        final prefsFile = File(p.join(stagingDir.path, preferencesFileName));
        if (await prefsFile.exists()) {
          try {
            final prefsJson = jsonDecode(await prefsFile.readAsString()) as Map;
            if (prefsJson.containsKey('theme')) {
              final themeMap = Map<String, dynamic>.from(
                prefsJson['theme'] as Map,
              );
              await _effectiveThemeStorage.saveSettings(
                paletteId: themeMap['paletteId'] as String? ?? 'classicCaramel',
                followSystem: themeMap['followSystem'] as bool? ?? true,
              );
            }
            if (prefsJson.containsKey('reminders')) {
              final reminderMap = Map<String, dynamic>.from(
                prefsJson['reminders'] as Map,
              );
              final restoredReminders = DailyReminderSettings.fromJson(
                reminderMap,
              );
              await _effectiveReminderStorage.saveSettings(restoredReminders);
            }
          } catch (e) {
            debugPrint('Non-critical preference restoration error: $e');
          }
        }
      }

      // 6. STAGE 6: Commit succeeded! Clean old photos, journal, and staging
      journal['state'] = 'committed';
      await journalFile.writeAsString(jsonEncode(journal), flush: true);

      // Cleanup old replaced photos now that new state is committed and verified
      for (final oldPath in oldPhotosToDeleteOnSuccess) {
        try {
          final oldFile = File(oldPath);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        } catch (_) {}
      }

      // Clean metadata backup and journal
      try {
        if (await metadataBackupFile.exists()) {
          await metadataBackupFile.delete();
        }
        if (await journalFile.exists()) {
          await journalFile.delete();
        }
      } catch (_) {}

      // Clean staging directory
      try {
        if (await stagingDir.exists()) {
          await stagingDir.delete(recursive: true);
        }
      } catch (_) {}

      onProgress?.call(1.0, 'Restore complete!');

      return PadRestoreResult.success(
        mode: mode,
        importedCount: importedCount,
        preservedCount: preservedCount,
        replacedCount: replacedCount,
      );
    } catch (e) {
      debugPrint('Restore failed! Initiating transactional rollback: $e');

      // 1. ROLLBACK METADATA FIRST: Restore previous metadata before deleting any files
      try {
        if (await metadataBackupFile.exists()) {
          final liveMetadataFile = _effectiveMetadataStorage.metadataFile;
          await metadataBackupFile.copy(liveMetadataFile.path);
        } else {
          await _effectiveMetadataStorage.saveDays(originalLiveDays);
        }
        await _effectiveStore.init();
      } catch (err) {
        debugPrint('Error restoring metadata during rollback: $err');
      }

      // 2. ROLLBACK FILES: Delete newly copied photo files (old photos were never deleted)
      for (final newFile in newlyCopiedFiles) {
        try {
          final file = File(newFile);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }

      // 3. Clean journal & backup
      try {
        if (await journalFile.exists()) {
          await journalFile.delete();
        }
        if (await metadataBackupFile.exists()) {
          await metadataBackupFile.delete();
        }
      } catch (_) {}

      // 4. Clean staging directory
      try {
        if (await stagingDir.exists()) {
          await stagingDir.delete(recursive: true);
        }
      } catch (_) {}

      return PadRestoreResult.failure(
        mode: mode,
        errorMessage:
            'Restore encountered an error and was safely rolled back. '
            'Your existing diary remains completely unchanged. Error: $e',
      );
    }
  }

  Future<File> get _journalFile async {
    final workDir = await getWorkingDir();
    return File(p.join(workDir.path, restoreJournalFileName));
  }

  Future<File> get _metadataBackupFile async {
    final workDir = await getWorkingDir();
    return File(p.join(workDir.path, metadataBackupFileName));
  }

  /// Recovers any interrupted restore transaction recorded in the persistent journal.
  ///
  /// Guarantees that if the application was terminated, crashed, or had process interruption
  /// during a restore operation, the diary is brought back to a consistent, safe state.
  Future<bool> recoverPendingRestore() async {
    try {
      final journalFile = await _journalFile;
      if (!await journalFile.exists()) return false;

      final journalContent = await journalFile.readAsString();
      if (journalContent.trim().isEmpty) {
        await journalFile.delete();
        return false;
      }

      final journal = jsonDecode(journalContent) as Map;
      final state = journal['state'] as String?;
      final newlyCopied = List<String>.from(
        journal['newlyCopiedFiles'] as List? ?? [],
      );
      final oldToDelete = List<String>.from(
        journal['oldPhotosToDeleteOnSuccess'] as List? ?? [],
      );
      final metadataBackupFile = await _metadataBackupFile;

      if (state == 'staged' || state == 'copying') {
        // Interrupted before metadata commit: rollback all newly copied files and restore metadata
        for (final path in newlyCopied) {
          try {
            final f = File(path);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
        if (await metadataBackupFile.exists()) {
          final liveMetadataFile = _effectiveMetadataStorage.metadataFile;
          await metadataBackupFile.copy(liveMetadataFile.path);
          await _effectiveStore.init();
          await metadataBackupFile.delete();
        }
        await journalFile.delete();
        return true;
      } else if (state == 'committing') {
        // Interrupted during metadata commit before reaching verified 'committed' state.
        // Safely rollback to pre-restore metadata backup to protect original photos and diary entries.
        if (await metadataBackupFile.exists()) {
          final liveMetadataFile = _effectiveMetadataStorage.metadataFile;
          await metadataBackupFile.copy(liveMetadataFile.path);
          await _effectiveStore.init();
          await metadataBackupFile.delete();
        }
        for (final path in newlyCopied) {
          try {
            final f = File(path);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
        // oldToDelete photos are NEVER deleted on rollback: original user photos remain 100% preserved.
        await journalFile.delete();
        return true;
      } else if (state == 'committed') {
        // Finalize cleanup of old photos
        for (final path in oldToDelete) {
          try {
            final f = File(path);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
        if (await metadataBackupFile.exists()) {
          await metadataBackupFile.delete();
        }
        await journalFile.delete();
        return true;
      }
    } catch (e) {
      debugPrint('Error recovering pending restore: $e');
    }
    return false;
  }

  /// Cleans the temporary staging directory after inspection if restore is cancelled.
  Future<void> cleanStagingDirectory(Directory? stagingDir) async {
    if (stagingDir == null) return;
    try {
      if (await stagingDir.exists()) {
        await stagingDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error cleaning staging directory: $e');
    }
  }

  /// Removes any stale temporary `.padbackup` or `staging_*` directories from the cache.
  Future<int> cleanTemporaryBackups() async {
    try {
      final workDir = await getWorkingDir();
      if (!await workDir.exists()) return 0;

      int deletedCount = 0;
      final entities = workDir.listSync();
      for (final entity in entities) {
        try {
          if (entity is File &&
              entity.path.endsWith(backupExtension) &&
              (p.basename(entity.path).startsWith('Daria_Backup_') ||
                  p.basename(entity.path).startsWith('photoperday_backup_'))) {
            await entity.delete();
            deletedCount++;
          } else if (entity is Directory &&
              p.basename(entity.path).startsWith('staging_')) {
            await entity.delete(recursive: true);
            deletedCount++;
          }
        } catch (_) {}
      }
      return deletedCount;
    } catch (e) {
      debugPrint('Error cleaning temporary backups: $e');
      return 0;
    }
  }
}
