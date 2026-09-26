import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/sync_status.dart';

/// Represents a photo memory for a given calendar date.
class PhotoEntry {
  const PhotoEntry({
    required this.date,
    required this.title,
    this.caption,
    this.location,
    this.timeFormatted = '2:45 PM',
    required this.gradientColors,
    this.icon = Icons.photo_camera_rounded,
    this.category = 'Daily Life',
    this.imagePath,
    this.syncStatus = SyncStatus.localOnly,
    this.lastModifiedAt,
    this.driveFileId,
    this.driveFileRevision,
    this.syncError,
    this.authorizedEmail,
  });

  final DateTime date;
  final String title;
  final String? caption;
  final String? location;
  final String timeFormatted;
  final List<Color> gradientColors;
  final IconData icon;
  final String category;

  /// Optional local file path for real captured photo.
  final String? imagePath;

  /// Synchronization state representing the local/cloud backup lifecycle.
  final SyncStatus syncStatus;

  /// UTC timestamp of creation or last local modification.
  final DateTime? lastModifiedAt;

  /// Remote Google Drive file identifier (null until uploaded/synced).
  final String? driveFileId;

  /// Remote revision or content hash from Google Drive (null until uploaded/synced).
  final String? driveFileRevision;

  /// Concise error description if [syncStatus] is [SyncStatus.failed].
  final String? syncError;

  /// Google account email that authorized/owns the remote [driveFileId].
  final String? authorizedEmail;

  /// Resolves the effective last modified UTC timestamp.
  DateTime get effectiveLastModifiedAt => lastModifiedAt ?? date.toUtc();

  /// Whether this entry has an actual captured image file path.
  bool get hasRealImage => imagePath != null && imagePath!.isNotEmpty;

  /// Whether the image file actually exists on disk.
  bool get isImageFileAvailable {
    if (!hasRealImage) return false;
    try {
      return File(imagePath!).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// The normalized calendar date key for this photo memory.
  DateKey get dateKey => DateKey.fromDateTime(date);

  /// Local midnight DateTime for this calendar day.
  DateTime get normalizedDate => dateKey.toDateTime();

  /// Converts this [PhotoEntry] into a JSON-serializable Map.
  Map<String, dynamic> toJson() {
    return {
      'dateKey': dateKey.format(),
      'date': date.toIso8601String(),
      'title': title,
      'caption': caption,
      'location': location,
      'timeFormatted': timeFormatted,
      'gradientColors': gradientColors.map((c) => c.toARGB32()).toList(),
      'iconCodePoint': icon.codePoint,
      'iconFontFamily': icon.fontFamily,
      'category': category,
      'imagePath': imagePath,
      'syncStatus': syncStatus.toJson(),
      'lastModifiedAt': effectiveLastModifiedAt.toIso8601String(),
      'driveFileId': driveFileId,
      'driveFileRevision': driveFileRevision,
      'syncError': syncError,
      'authorizedEmail': authorizedEmail,
    };
  }

  /// Reconstructs a [PhotoEntry] from a JSON map with 100% backward compatibility
  /// for legacy records missing sync metadata.
  factory PhotoEntry.fromJson(Map<String, dynamic> json) {
    final dateStr = json['date'] as String?;
    final date = dateStr != null ? DateTime.parse(dateStr) : DateTime.now();

    final rawColors = json['gradientColors'] as List<dynamic>?;
    final List<Color> colors;
    if (rawColors != null && rawColors.isNotEmpty) {
      colors = rawColors.map((v) => Color((v as num).toInt())).toList();
    } else {
      colors = const [Color(0xFFE28743), Color(0xFF873E23)];
    }

    final codePoint = json['iconCodePoint'] as int?;
    final fontFamily = json['iconFontFamily'] as String?;
    final icon = codePoint != null
        // ignore: non_const_argument_for_const_parameter
        ? IconData(codePoint, fontFamily: fontFamily ?? 'MaterialIcons')
        : Icons.photo_camera_rounded;

    final syncStatusStr = json['syncStatus'] as String?;
    final syncStatus = SyncStatus.fromJson(syncStatusStr);

    final lastModStr = json['lastModifiedAt'] as String?;
    final lastModifiedAt = lastModStr != null
        ? DateTime.parse(lastModStr).toUtc()
        : date.toUtc();

    final driveFileId = json['driveFileId'] as String?;
    final driveFileRevision = json['driveFileRevision'] as String?;
    final syncError = json['syncError'] as String?;
    final authorizedEmail = json['authorizedEmail'] as String?;

    return PhotoEntry(
      date: date,
      title: json['title'] as String? ?? 'Daily Capture',
      caption: json['caption'] as String?,
      location: json['location'] as String?,
      timeFormatted: json['timeFormatted'] as String? ?? '12:00 PM',
      gradientColors: colors,
      icon: icon,
      category: json['category'] as String? ?? 'Daily Life',
      imagePath: json['imagePath'] as String?,
      syncStatus: syncStatus,
      lastModifiedAt: lastModifiedAt,
      driveFileId: driveFileId,
      driveFileRevision: driveFileRevision,
      syncError: syncError,
      authorizedEmail: authorizedEmail,
    );
  }

  PhotoEntry copyWith({
    DateTime? date,
    String? title,
    String? caption,
    String? location,
    String? timeFormatted,
    List<Color>? gradientColors,
    IconData? icon,
    String? category,
    String? imagePath,
    SyncStatus? syncStatus,
    DateTime? lastModifiedAt,
    String? driveFileId,
    String? driveFileRevision,
    String? syncError,
    bool clearSyncError = false,
    String? authorizedEmail,
    bool clearAuthorizedEmail = false,
  }) {
    return PhotoEntry(
      date: date ?? this.date,
      title: title ?? this.title,
      caption: caption ?? this.caption,
      location: location ?? this.location,
      timeFormatted: timeFormatted ?? this.timeFormatted,
      gradientColors: gradientColors ?? this.gradientColors,
      icon: icon ?? this.icon,
      category: category ?? this.category,
      imagePath: imagePath ?? this.imagePath,
      syncStatus: syncStatus ?? this.syncStatus,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      driveFileId: driveFileId ?? this.driveFileId,
      driveFileRevision: driveFileRevision ?? this.driveFileRevision,
      syncError: clearSyncError ? null : (syncError ?? this.syncError),
      authorizedEmail: clearAuthorizedEmail
          ? null
          : (authorizedEmail ?? this.authorizedEmail),
    );
  }
}
