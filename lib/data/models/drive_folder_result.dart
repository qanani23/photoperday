import 'package:flutter/foundation.dart';
import 'drive_folder_reference.dart';

/// Categories of failure when resolving or creating the Google Drive folder.
enum DriveFolderErrorType {
  /// The user is not signed in to a Google account.
  notSignedIn,

  /// The user has not granted Google Drive (`drive.file`) authorization.
  notAuthorized,

  /// Network failure, socket error, or connection timeout.
  networkError,

  /// 401 Unauthorized / expired token.
  unauthorized,

  /// 403 Forbidden / insufficient permissions.
  forbidden,

  /// 404 Not Found.
  notFound,

  /// The API response format was invalid or missing required fields.
  malformedResponse,

  /// General platform or Google Drive API exception.
  apiError,
}

/// Sealed result type for Google Drive folder setup operations.
@immutable
abstract class DriveFolderResult {
  const DriveFolderResult();

  bool get isSuccess => this is DriveFolderSuccess;
  bool get isFailure => this is DriveFolderFailure;
}

/// Successful folder resolution or creation.
class DriveFolderSuccess extends DriveFolderResult {
  final DriveFolderReference folder;
  final bool wasCreated;

  const DriveFolderSuccess(this.folder, {required this.wasCreated});

  @override
  String toString() =>
      'DriveFolderSuccess(folder: ${folder.folderId}, wasCreated: $wasCreated)';
}

/// Failure during folder resolution or creation.
class DriveFolderFailure extends DriveFolderResult {
  final String message;
  final DriveFolderErrorType errorType;
  final Object? cause;

  const DriveFolderFailure(this.message, {required this.errorType, this.cause});

  @override
  String toString() => 'DriveFolderFailure($errorType: $message)';
}
