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
  /// Falls back safely to false if nonexistent or inaccessible.
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
  /// and robust resilience against malformed fields, unexpected types, or missing keys.
  factory PhotoEntry.fromJson(Map<String, dynamic> json) {
    DateTime date;
    final dateRaw = json['date'];
    if (dateRaw is String) {
      date = DateTime.tryParse(dateRaw) ?? DateTime.now();
    } else {
      date = DateTime.now();
    }

    // If dateKey is explicitly provided and valid, align date with dateKey
    final dateKeyRaw = json['dateKey'];
    if (dateKeyRaw is String) {
      try {
        final parsedKey = DateKey.parse(dateKeyRaw);
        if (DateKey.fromDateTime(date) != parsedKey) {
          date = parsedKey.toDateTime();
        }
      } catch (_) {}
    }

    final rawColors = json['gradientColors'];
    final List<Color> colors;
    if (rawColors is List && rawColors.isNotEmpty) {
      final parsedColors = rawColors
          .map((v) => v is num ? Color(v.toInt()) : null)
          .whereType<Color>()
          .toList();
      colors = parsedColors.isNotEmpty
          ? parsedColors
          : const [Color(0xFFE28743), Color(0xFF873E23)];
    } else {
      colors = const [Color(0xFFE28743), Color(0xFF873E23)];
    }

    final rawCodePoint = json['iconCodePoint'];
    final codePoint = rawCodePoint is num ? rawCodePoint.toInt() : null;
    final icon = _resolveIcon(codePoint);

    final syncStatusStr = json['syncStatus']?.toString();
    final syncStatus = SyncStatus.fromJson(syncStatusStr);

    final lastModRaw = json['lastModifiedAt'];
    final DateTime lastModifiedAt;
    if (lastModRaw is String) {
      lastModifiedAt = DateTime.tryParse(lastModRaw)?.toUtc() ?? date.toUtc();
    } else {
      lastModifiedAt = date.toUtc();
    }

    final title = json['title']?.toString() ?? 'Daily Capture';
    final caption = json['caption']?.toString();
    final location = json['location']?.toString();
    final timeFormatted = json['timeFormatted']?.toString() ?? '12:00 PM';
    final category = json['category']?.toString() ?? 'Daily Life';
    final imagePath = json['imagePath']?.toString();
    final driveFileId = json['driveFileId']?.toString();
    final driveFileRevision = json['driveFileRevision']?.toString();
    final syncError = json['syncError']?.toString();
    final authorizedEmail = (json['authorizedEmail'] ?? json['accountEmail'])
        ?.toString();

    return PhotoEntry(
      date: date,
      title: title,
      caption: caption,
      location: location,
      timeFormatted: timeFormatted,
      gradientColors: colors,
      icon: icon,
      category: category,
      imagePath: imagePath,
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
    bool clearCaption = false,
    String? location,
    bool clearLocation = false,
    String? timeFormatted,
    List<Color>? gradientColors,
    IconData? icon,
    String? category,
    String? imagePath,
    SyncStatus? syncStatus,
    DateTime? lastModifiedAt,
    String? driveFileId,
    bool clearDriveFileId = false,
    String? driveFileRevision,
    bool clearDriveFileRevision = false,
    String? syncError,
    bool clearSyncError = false,
    String? authorizedEmail,
    bool clearAuthorizedEmail = false,
  }) {
    return PhotoEntry(
      date: date ?? this.date,
      title: title ?? this.title,
      caption: clearCaption ? null : (caption ?? this.caption),
      location: clearLocation ? null : (location ?? this.location),
      timeFormatted: timeFormatted ?? this.timeFormatted,
      gradientColors: gradientColors ?? this.gradientColors,
      icon: icon ?? this.icon,
      category: category ?? this.category,
      imagePath: imagePath ?? this.imagePath,
      syncStatus: syncStatus ?? this.syncStatus,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      driveFileId: clearDriveFileId ? null : (driveFileId ?? this.driveFileId),
      driveFileRevision: clearDriveFileRevision
          ? null
          : (driveFileRevision ?? this.driveFileRevision),
      syncError: clearSyncError ? null : (syncError ?? this.syncError),
      authorizedEmail: clearAuthorizedEmail
          ? null
          : (authorizedEmail ?? this.authorizedEmail),
    );
  }

  /// Maps serialized icon code points to compile-time constant [IconData] instances.
  ///
  /// This ensures release builds support icon font tree-shaking without compiler errors.
  static IconData _resolveIcon(int? codePoint) {
    if (codePoint == null) return Icons.photo_camera_rounded;
    switch (codePoint) {
      case 0xe156:
      case 0xf0663:
        return Icons.coffee_rounded;
      case 0xf002b:
        return Icons.park_rounded;
      case 0xf0083:
        return Icons.pets_rounded;
      case 0xe1b6:
        return Icons.directions_walk_rounded;
      case 0xe4a1:
        return Icons.restaurant_rounded;
      case 0xe6e2:
        return Icons.wb_sunny_rounded;
      case 0xf83d:
        return Icons.local_florist_rounded;
      case 0xe439:
        return Icons.music_note_rounded;
      case 0xe0ef:
        return Icons.book_rounded;
      case 0xe25a:
        return Icons.flight_takeoff_rounded;
      case 0xe4b6:
        return Icons.sports_basketball_rounded;
      case 0xe432:
        return Icons.movie_rounded;
      case 0xe16a:
        return Icons.computer_rounded;
      case 0xe11e:
        return Icons.brush_rounded;
      case 0xf85d:
        return Icons.pool_rounded;
      case 0xe0b2:
        return Icons.beach_access_rounded;
      case 0xe197:
        return Icons.dark_mode_rounded;
      case 0xe0bb:
        return Icons.bed_rounded;
      case 0xe117:
        return Icons.brightness_3_rounded;
      default:
        return Icons.photo_camera_rounded;
    }
  }
}
