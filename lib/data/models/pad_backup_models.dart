import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/models/date_key.dart';

/// Supported restore operations for a `.padbackup` file.
enum PadRestoreMode {
  /// Preserves existing diary entries and adds non-conflicting backup entries.
  merge,

  /// Completely replaces the active diary with the contents of the backup archive.
  replace,
}

/// Strategy for resolving same-day photo conflicts during [PadRestoreMode.merge].
enum PadConflictResolution {
  /// Keeps the live diary photo and discards the backup photo for that date.
  keepExisting,

  /// Replaces the live diary photo with the backup photo for that date.
  overwriteWithBackup,
}

/// Represents an individual photo item archived within a `.padbackup` package.
@immutable
class PadBackupPhotoItem {
  const PadBackupPhotoItem({
    required this.dateKey,
    required this.archivePath,
    required this.sizeBytes,
    required this.sha256,
    required this.title,
    this.location,
    required this.timeFormatted,
    this.id,
    this.order,
  });

  final String dateKey;
  final String archivePath;
  final int sizeBytes;
  final String sha256;
  final String title;
  final String? location;
  final String timeFormatted;

  /// Unique identifier of the photo entry within the DayEntry.
  final String? id;

  /// Zero-based display order within the multi-photo day.
  final int? order;

  Map<String, dynamic> toJson() => {
    'dateKey': dateKey,
    'archivePath': archivePath,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'title': title,
    if (location != null && location!.trim().isNotEmpty)
      'location': location!.trim(),
    'timeFormatted': timeFormatted,
    if (id != null && id!.isNotEmpty) 'id': id,
    if (order != null) 'order': order,
  };

  factory PadBackupPhotoItem.fromJson(Map<String, dynamic> json) {
    return PadBackupPhotoItem(
      dateKey: json['dateKey'] as String? ?? '',
      archivePath: json['archivePath'] as String? ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'] as String? ?? '',
      title: json['title'] as String? ?? '',
      location: json['location'] as String?,
      timeFormatted: json['timeFormatted'] as String? ?? '12:00 PM',
      id: json['id'] as String?,
      order: (json['order'] as num?)?.toInt(),
    );
  }
}

/// Represents a photo entry that could not be read or included during backup creation.
@immutable
class PadBackupSkippedItem {
  const PadBackupSkippedItem({
    required this.dateKey,
    required this.reason,
    this.photoId,
  });

  final String dateKey;
  final String reason;
  final String? photoId;

  Map<String, dynamic> toJson() => {
    'dateKey': dateKey,
    'reason': reason,
    if (photoId != null && photoId!.isNotEmpty) 'photoId': photoId,
  };

  factory PadBackupSkippedItem.fromJson(Map<String, dynamic> json) {
    return PadBackupSkippedItem(
      dateKey: json['dateKey'] as String? ?? '',
      reason: json['reason'] as String? ?? 'Unknown error',
      photoId: json['photoId'] as String?,
    );
  }
}

/// The versioned manifest metadata embedded in root of every `.padbackup` archive.
@immutable
class PadBackupManifest {
  const PadBackupManifest({
    required this.formatVersion,
    required this.appVersion,
    required this.appName,
    required this.createdAt,
    required this.isPartial,
    required this.photoCount,
    this.dayCount,
    required this.totalSizeBytes,
    this.startDate,
    this.endDate,
    required this.photos,
    required this.skippedPhotos,
    required this.metadataChecksum,
    this.preferencesChecksum,
  });

  /// The version of the .padbackup specification (1 for legacy single-photo, 2 for multi-photo DayEntry).
  final int formatVersion;

  /// The app version that generated this archive.
  final String appVersion;

  /// The application name ('Photo a Day').
  final String appName;

  /// UTC timestamp when this backup was compiled.
  final DateTime createdAt;

  /// Whether some photos were omitted due to missing or unreadable source files.
  final bool isPartial;

  /// Total count of valid photos packaged into this archive.
  final int photoCount;

  /// Total count of recorded day entries (including note-only days) represented in this backup.
  final int? dayCount;

  /// Total uncompressed size of all photo files in bytes.
  final int totalSizeBytes;

  /// Earliest photo date key in this backup (e.g. '2026-01-01').
  final String? startDate;

  /// Latest photo date key in this backup (e.g. '2026-12-31').
  final String? endDate;

  /// List of all photo items packaged in the archive.
  final List<PadBackupPhotoItem> photos;

  /// List of skipped entries if partial backup was permitted.
  final List<PadBackupSkippedItem> skippedPhotos;

  /// SHA-256 checksum of the packaged `photos_metadata.json`.
  final String metadataChecksum;

  /// Optional SHA-256 checksum of the packaged `preferences.json`.
  final String? preferencesChecksum;

  Map<String, dynamic> toJson() => {
    'formatVersion': formatVersion,
    'appVersion': appVersion,
    'appName': appName,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'isPartial': isPartial,
    'photoCount': photoCount,
    if (dayCount != null) 'dayCount': dayCount,
    'totalSizeBytes': totalSizeBytes,
    if (startDate != null) 'startDate': startDate,
    if (endDate != null) 'endDate': endDate,
    'photos': photos.map((p) => p.toJson()).toList(),
    'skippedPhotos': skippedPhotos.map((s) => s.toJson()).toList(),
    'metadataChecksum': metadataChecksum,
    if (preferencesChecksum != null) 'preferencesChecksum': preferencesChecksum,
  };

  factory PadBackupManifest.fromJson(Map<String, dynamic> json) {
    final rawPhotos = json['photos'] as List? ?? [];
    final rawSkipped = json['skippedPhotos'] as List? ?? [];

    return PadBackupManifest(
      formatVersion: (json['formatVersion'] as num?)?.toInt() ?? 1,
      appVersion: json['appVersion'] as String? ?? '1.0.0',
      appName: json['appName'] as String? ?? 'Daria',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      isPartial: json['isPartial'] as bool? ?? false,
      photoCount: (json['photoCount'] as num?)?.toInt() ?? 0,
      dayCount: (json['dayCount'] as num?)?.toInt(),
      totalSizeBytes: (json['totalSizeBytes'] as num?)?.toInt() ?? 0,
      startDate: json['startDate'] as String?,
      endDate: json['endDate'] as String?,
      photos: rawPhotos
          .whereType<Map>()
          .map((m) => PadBackupPhotoItem.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      skippedPhotos: rawSkipped
          .whereType<Map>()
          .map(
            (m) => PadBackupSkippedItem.fromJson(Map<String, dynamic>.from(m)),
          )
          .toList(),
      metadataChecksum: json['metadataChecksum'] as String? ?? '',
      preferencesChecksum: json['preferencesChecksum'] as String?,
    );
  }
}

/// The result of a `.padbackup` export operation.
@immutable
class PadBackupExportResult {
  const PadBackupExportResult({
    this.backupFile,
    required this.photoCount,
    required this.skippedCount,
    required this.totalSizeBytes,
    required this.isSuccess,
    this.isPartial = false,
    this.isEmpty = false,
    this.errorMessage,
    this.manifest,
  });

  final File? backupFile;
  final int photoCount;
  final int skippedCount;
  final int totalSizeBytes;
  final bool isSuccess;
  final bool isPartial;
  final bool isEmpty;
  final String? errorMessage;
  final PadBackupManifest? manifest;

  factory PadBackupExportResult.empty() {
    return const PadBackupExportResult(
      backupFile: null,
      photoCount: 0,
      skippedCount: 0,
      totalSizeBytes: 0,
      isSuccess: false,
      isEmpty: true,
    );
  }

  factory PadBackupExportResult.failure(String error) {
    return PadBackupExportResult(
      backupFile: null,
      photoCount: 0,
      skippedCount: 0,
      totalSizeBytes: 0,
      isSuccess: false,
      errorMessage: error,
    );
  }
}

/// Result of inspecting a `.padbackup` file before restore.
@immutable
class PadBackupInspectionResult {
  const PadBackupInspectionResult({
    required this.isValid,
    this.validationError,
    this.manifest,
    this.stagingDir,
    this.totalPhotosInBackup = 0,
    this.currentPhotosInDiary = 0,
    this.nonConflictingCount = 0,
    this.conflictingCount = 0,
    this.conflictingDates = const [],
    this.hasPreferences = false,
  });

  final bool isValid;
  final String? validationError;
  final PadBackupManifest? manifest;
  final Directory? stagingDir;
  final int totalPhotosInBackup;
  final int currentPhotosInDiary;
  final int nonConflictingCount;
  final int conflictingCount;
  final List<DateKey> conflictingDates;
  final bool hasPreferences;

  factory PadBackupInspectionResult.invalid(String error) {
    return PadBackupInspectionResult(isValid: false, validationError: error);
  }
}

/// The result of executing a `.padbackup` restore operation.
@immutable
class PadRestoreResult {
  const PadRestoreResult({
    required this.isSuccess,
    required this.mode,
    this.importedCount = 0,
    this.preservedCount = 0,
    this.replacedCount = 0,
    this.errorMessage,
  });

  final bool isSuccess;
  final PadRestoreMode mode;
  final int importedCount;
  final int preservedCount;
  final int replacedCount;
  final String? errorMessage;

  factory PadRestoreResult.success({
    required PadRestoreMode mode,
    required int importedCount,
    int preservedCount = 0,
    int replacedCount = 0,
  }) {
    return PadRestoreResult(
      isSuccess: true,
      mode: mode,
      importedCount: importedCount,
      preservedCount: preservedCount,
      replacedCount: replacedCount,
    );
  }

  factory PadRestoreResult.failure({
    required PadRestoreMode mode,
    required String errorMessage,
  }) {
    return PadRestoreResult(
      isSuccess: false,
      mode: mode,
      errorMessage: errorMessage,
    );
  }
}
