import 'package:flutter/foundation.dart';

/// Immutable response returned by [DriveApiAdapter.uploadPhotoFile].
///
/// Contains ONLY public/non-sensitive remote file identifiers:
/// - [fileId]: The Google Drive file identifier.
/// - [revision]: The Google Drive version / revision identifier (if provided by Drive API).
/// - [filename]: The remote name of the file (e.g., "photo_2026-09-13.jpg").
/// - [uploadedAt]: The UTC timestamp when the file was created in Google Drive.
///
/// Under no circumstances are OAuth tokens or authorization headers stored in this object.
@immutable
class DrivePhotoUploadResponse {
  final String fileId;
  final String? revision;
  final String filename;
  final DateTime? uploadedAt;

  const DrivePhotoUploadResponse({
    required this.fileId,
    this.revision,
    required this.filename,
    this.uploadedAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrivePhotoUploadResponse &&
          runtimeType == other.runtimeType &&
          fileId == other.fileId &&
          revision == other.revision &&
          filename == other.filename;

  @override
  int get hashCode => Object.hash(fileId, revision, filename);

  @override
  String toString() =>
      'DrivePhotoUploadResponse(fileId: $fileId, revision: $revision, filename: $filename, uploadedAt: $uploadedAt)';
}
