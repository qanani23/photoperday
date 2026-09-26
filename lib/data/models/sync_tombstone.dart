import 'package:photo_per_day/data/models/date_key.dart';

/// Represents a record of a deleted local photo that had an associated remote
/// cloud file in Google Drive ([driveFileId]).
///
/// This provides the persistent seam for future Milestone 17 (Upload Queue)
/// to detect which remote files must be deleted from Google Drive when syncing.
class SyncTombstone {
  const SyncTombstone({
    required this.dateKey,
    required this.driveFileId,
    required this.deletedAt,
    this.authorizedEmail,
  });

  /// The normalized calendar DateKey of the deleted photo.
  final DateKey dateKey;

  /// The remote Google Drive file identifier that must be deleted remotely.
  final String driveFileId;

  /// UTC timestamp when the local photo was deleted.
  final DateTime deletedAt;

  /// The Google account email that owned the deleted remote Drive file.
  final String? authorizedEmail;

  /// Converts this tombstone into a JSON-serializable Map.
  Map<String, dynamic> toJson() {
    return {
      'dateKey': dateKey.format(),
      'driveFileId': driveFileId,
      'deletedAt': deletedAt.toIso8601String(),
      if (authorizedEmail != null) 'authorizedEmail': authorizedEmail,
    };
  }

  /// Reconstructs a [SyncTombstone] from a JSON map.
  factory SyncTombstone.fromJson(Map<String, dynamic> json) {
    final dateKeyStr = json['dateKey'] as String;
    final driveFileId = json['driveFileId'] as String;
    final deletedAtStr = json['deletedAt'] as String?;
    final deletedAt = deletedAtStr != null
        ? DateTime.parse(deletedAtStr).toUtc()
        : DateTime.now().toUtc();
    final authorizedEmail =
        (json['authorizedEmail'] ?? json['accountEmail']) as String?;

    return SyncTombstone(
      dateKey: DateKey.parse(dateKeyStr),
      driveFileId: driveFileId,
      deletedAt: deletedAt,
      authorizedEmail: authorizedEmail,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncTombstone &&
          runtimeType == other.runtimeType &&
          dateKey == other.dateKey &&
          driveFileId == other.driveFileId &&
          authorizedEmail == other.authorizedEmail;

  @override
  int get hashCode => Object.hash(dateKey, driveFileId, authorizedEmail);

  @override
  String toString() =>
      'SyncTombstone(dateKey: $dateKey, driveFileId: $driveFileId, deletedAt: $deletedAt, email: $authorizedEmail)';
}
