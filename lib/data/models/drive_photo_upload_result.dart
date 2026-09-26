import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/models/date_key.dart';

/// Categories of failure when uploading a photo to Google Drive.
enum DrivePhotoUploadErrorType {
  /// User is not signed in to a Google account.
  notSignedIn,

  /// Google Drive permission (`drive.file`) has not been granted.
  notAuthorized,

  /// Target "Photo a Day" Drive folder is uninitialized or unavailable.
  folderNotReady,

  /// Local image file does not exist on disk.
  fileMissing,

  /// Local image file is empty (0 bytes).
  fileEmpty,

  /// Photo metadata (e.g. dateKey or imagePath) is invalid or malformed.
  invalidMetadata,

  /// An upload for this photo memory is already actively in progress.
  alreadyInProgress,

  /// Photo memory has already been successfully synced to Google Drive.
  alreadySynced,

  /// Network failure, socket error, or connection timeout.
  networkError,

  /// 401 Unauthorized / expired token.
  unauthorized,

  /// 403 Forbidden / insufficient Drive permissions.
  forbidden,

  /// 404 Not Found (e.g. target parent folder deleted remotely).
  notFound,

  /// Drive API response was malformed or missing the file ID.
  malformedResponse,

  /// General platform or Google Drive API exception.
  apiError,
}

/// Sealed result hierarchy for Google Drive single-photo proof uploads.
@immutable
abstract class DrivePhotoUploadResult {
  const DrivePhotoUploadResult();

  bool get isSuccess => this is DrivePhotoUploadSuccess;
  bool get isAlreadySynced => this is DrivePhotoUploadAlreadySynced;
  bool get isFailure => this is DrivePhotoUploadFailure;
}

/// Indicates the photo was successfully uploaded to Google Drive.
class DrivePhotoUploadSuccess extends DrivePhotoUploadResult {
  final String fileId;
  final String? revision;
  final String remoteFilename;
  final DateTime uploadedAt;

  const DrivePhotoUploadSuccess({
    required this.fileId,
    this.revision,
    required this.remoteFilename,
    required this.uploadedAt,
  });

  @override
  String toString() =>
      'DrivePhotoUploadSuccess(fileId: $fileId, filename: $remoteFilename, revision: $revision)';
}

/// Indicates the photo was already marked as synced and has a Drive file ID.
class DrivePhotoUploadAlreadySynced extends DrivePhotoUploadResult {
  final String fileId;
  final DateKey dateKey;

  const DrivePhotoUploadAlreadySynced({
    required this.fileId,
    required this.dateKey,
  });

  @override
  String toString() =>
      'DrivePhotoUploadAlreadySynced(dateKey: $dateKey, fileId: $fileId)';
}

/// Indicates the photo upload failed.
class DrivePhotoUploadFailure extends DrivePhotoUploadResult {
  final String message;
  final DrivePhotoUploadErrorType errorType;
  final Object? cause;

  const DrivePhotoUploadFailure(
    this.message, {
    required this.errorType,
    this.cause,
  });

  @override
  String toString() => 'DrivePhotoUploadFailure($errorType: $message)';
}
