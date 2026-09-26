import 'dart:async';
import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:photo_per_day/data/models/drive_folder_reference.dart';
import 'package:photo_per_day/data/models/drive_folder_result.dart';
import 'package:photo_per_day/data/models/drive_photo_upload_response.dart';

/// Callback reporting upload progress as a double from 0.0 (started) to 1.0 (completed).
typedef DriveUploadProgress = void Function(double progress);

/// Exception thrown by [DriveApiAdapter] operations containing a typed error classification.
class DriveApiException implements Exception {
  final String message;
  final DriveFolderErrorType errorType;
  final Object? cause;

  const DriveApiException(this.message, {required this.errorType, this.cause});

  @override
  String toString() => 'DriveApiException($errorType: $message)';
}

/// Abstract contract for Google Drive folder and file operations.
///
/// Decouples higher-level services from raw googleapis/network classes,
/// allowing 100% hermetic unit testing via fake adapters without network calls.
abstract class DriveApiAdapter {
  /// Searches for an existing non-trashed folder with [folderName]
  /// in the user's visible Drive space (`spaces: 'drive'`).
  ///
  /// Returns a [DriveFolderReference] if found, or null if no matching folder exists.
  Future<DriveFolderReference?> findFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  });

  /// Creates a user-visible folder in My Drive with the given [folderName].
  ///
  /// Returns the newly created [DriveFolderReference].
  Future<DriveFolderReference> createFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  });

  /// Uploads a photo file directly into [parentFolderId].
  ///
  /// Stream progress is tracked based on actual bytes transferred.
  Future<DrivePhotoUploadResponse> uploadPhotoFile({
    required File file,
    required String filename,
    required String mimeType,
    required String parentFolderId,
    required Map<String, String> authHeaders,
    DriveUploadProgress? onProgress,
  });

  /// Updates an existing photo file in Google Drive identified by [fileId].
  ///
  /// Can update file content via [file] stream, [filename], and/or [description].
  Future<DrivePhotoUploadResponse> updatePhotoFile({
    required String fileId,
    required Map<String, String> authHeaders,
    File? file,
    String? filename,
    String? mimeType,
    String? description,
    DriveUploadProgress? onProgress,
  });

  /// Trashes (soft deletes) an existing photo file in Google Drive identified by [fileId].
  ///
  /// Uses Drive `files.update(drive.File(trashed: true))` to safely move the file
  /// to trash without permanent destruction.
  Future<void> trashPhotoFile({
    required String fileId,
    required Map<String, String> authHeaders,
  });
}

/// Production implementation of [DriveApiAdapter] using the official Google Drive API v3.
class GoogleApisDriveAdapter implements DriveApiAdapter {
  const GoogleApisDriveAdapter();

  @override
  Future<DriveFolderReference?> findFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  }) async {
    final client = _AuthenticatedHttpClient(authHeaders);
    try {
      final driveApi = drive.DriveApi(client);
      final escapedName = folderName.replaceAll("'", "\\'");
      final query =
          "name = '$escapedName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";

      final fileList = await driveApi.files
          .list(
            q: query,
            spaces: 'drive',
            $fields: 'files(id, name, createdTime)',
          )
          .timeout(const Duration(seconds: 15));

      final files = fileList.files;
      if (files == null || files.isEmpty) {
        return null;
      }

      final firstMatch = files.first;
      final folderId = firstMatch.id;
      if (folderId == null || folderId.isEmpty) {
        throw const DriveApiException(
          'API returned folder with missing or empty ID',
          errorType: DriveFolderErrorType.malformedResponse,
        );
      }

      return DriveFolderReference(
        folderId: folderId,
        folderName: firstMatch.name ?? folderName,
        authorizedEmail: accountEmail,
        resolvedAt: firstMatch.createdTime ?? DateTime.now().toUtc(),
      );
    } catch (e, stack) {
      throw _mapError(e, stack, 'Failed searching for Drive folder');
    } finally {
      client.close();
    }
  }

  @override
  Future<DriveFolderReference> createFolder({
    required String folderName,
    required Map<String, String> authHeaders,
    String? accountEmail,
  }) async {
    final client = _AuthenticatedHttpClient(authHeaders);
    try {
      final driveApi = drive.DriveApi(client);
      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';

      final created = await driveApi.files
          .create(folder, $fields: 'id, name, createdTime')
          .timeout(const Duration(seconds: 15));

      final folderId = created.id;
      if (folderId == null || folderId.isEmpty) {
        throw const DriveApiException(
          'Drive API returned created folder without ID',
          errorType: DriveFolderErrorType.malformedResponse,
        );
      }

      return DriveFolderReference(
        folderId: folderId,
        folderName: created.name ?? folderName,
        authorizedEmail: accountEmail,
        resolvedAt: created.createdTime ?? DateTime.now().toUtc(),
      );
    } catch (e, stack) {
      throw _mapError(e, stack, 'Failed creating Drive folder');
    } finally {
      client.close();
    }
  }

  @override
  Future<DrivePhotoUploadResponse> uploadPhotoFile({
    required File file,
    required String filename,
    required String mimeType,
    required String parentFolderId,
    required Map<String, String> authHeaders,
    DriveUploadProgress? onProgress,
  }) async {
    final client = _AuthenticatedHttpClient(authHeaders);
    try {
      final driveApi = drive.DriveApi(client);
      final fileMetadata = drive.File()
        ..name = filename
        ..parents = [parentFolderId];

      final fileLength = await file.length();
      int bytesSent = 0;

      // Real stream progress based on bytes transferred
      final progressStream = file.openRead().transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (data, sink) {
            bytesSent += data.length;
            if (onProgress != null && fileLength > 0) {
              final progress = (bytesSent / fileLength).clamp(0.0, 1.0);
              onProgress(progress);
            }
            sink.add(data);
          },
        ),
      );

      final media = drive.Media(
        progressStream,
        fileLength,
        contentType: mimeType,
      );

      final created = await driveApi.files
          .create(
            fileMetadata,
            uploadMedia: media,
            $fields: 'id, name, version, createdTime',
          )
          .timeout(const Duration(seconds: 45));

      final fileId = created.id;
      if (fileId == null || fileId.isEmpty) {
        throw const DriveApiException(
          'Drive API returned created photo without an ID',
          errorType: DriveFolderErrorType.malformedResponse,
        );
      }

      if (onProgress != null) {
        onProgress(1.0);
      }

      return DrivePhotoUploadResponse(
        fileId: fileId,
        revision: created.version,
        filename: created.name ?? filename,
        uploadedAt: created.createdTime ?? DateTime.now().toUtc(),
      );
    } catch (e, stack) {
      throw _mapError(e, stack, 'Failed uploading photo to Drive');
    } finally {
      client.close();
    }
  }

  @override
  Future<DrivePhotoUploadResponse> updatePhotoFile({
    required String fileId,
    required Map<String, String> authHeaders,
    File? file,
    String? filename,
    String? mimeType,
    String? description,
    DriveUploadProgress? onProgress,
  }) async {
    final client = _AuthenticatedHttpClient(authHeaders);
    try {
      final driveApi = drive.DriveApi(client);
      final fileMetadata = drive.File();
      if (filename != null) {
        fileMetadata.name = filename;
      }
      if (description != null) {
        fileMetadata.description = description;
      }

      drive.Media? uploadMedia;
      if (file != null) {
        final fileLength = await file.length();
        int bytesSent = 0;

        final progressStream = file.openRead().transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleData: (data, sink) {
              bytesSent += data.length;
              if (onProgress != null && fileLength > 0) {
                final progress = (bytesSent / fileLength).clamp(0.0, 1.0);
                onProgress(progress);
              }
              sink.add(data);
            },
          ),
        );

        uploadMedia = drive.Media(
          progressStream,
          fileLength,
          contentType: mimeType ?? 'image/jpeg',
        );
      }

      final updated = await driveApi.files
          .update(
            fileMetadata,
            fileId,
            uploadMedia: uploadMedia,
            $fields: 'id, name, version, modifiedTime',
          )
          .timeout(const Duration(seconds: 45));

      final resolvedId = updated.id ?? fileId;
      if (onProgress != null && uploadMedia != null) {
        onProgress(1.0);
      }

      return DrivePhotoUploadResponse(
        fileId: resolvedId,
        revision: updated.version,
        filename: updated.name ?? (filename ?? ''),
        uploadedAt: updated.modifiedTime ?? DateTime.now().toUtc(),
      );
    } catch (e, stack) {
      throw _mapError(e, stack, 'Failed updating photo in Drive');
    } finally {
      client.close();
    }
  }

  @override
  Future<void> trashPhotoFile({
    required String fileId,
    required Map<String, String> authHeaders,
  }) async {
    final client = _AuthenticatedHttpClient(authHeaders);
    try {
      final driveApi = drive.DriveApi(client);
      final trashMetadata = drive.File()..trashed = true;

      await driveApi.files
          .update(trashMetadata, fileId, $fields: 'id, trashed')
          .timeout(const Duration(seconds: 20));
    } catch (e, stack) {
      throw _mapError(e, stack, 'Failed trashing photo in Drive');
    } finally {
      client.close();
    }
  }

  DriveApiException _mapError(Object error, StackTrace stack, String context) {
    if (error is DriveApiException) return error;

    if (error is drive.DetailedApiRequestError) {
      final status = error.status;
      if (status == 401) {
        return DriveApiException(
          'Unauthorized Drive API request. Please re-authenticate.',
          errorType: DriveFolderErrorType.unauthorized,
          cause: error,
        );
      } else if (status == 403) {
        return DriveApiException(
          'Access forbidden. Check Google Drive permissions.',
          errorType: DriveFolderErrorType.forbidden,
          cause: error,
        );
      } else if (status == 404) {
        return DriveApiException(
          'Target Drive resource not found.',
          errorType: DriveFolderErrorType.notFound,
          cause: error,
        );
      }
      return DriveApiException(
        '$context: (HTTP $status)',
        errorType: DriveFolderErrorType.apiError,
        cause: error,
      );
    }

    if (error is SocketException || error is http.ClientException) {
      return DriveApiException(
        'Network error communicating with Google Drive. Check internet connection.',
        errorType: DriveFolderErrorType.networkError,
        cause: error,
      );
    }

    if (error is TimeoutException) {
      return DriveApiException(
        'Google Drive request timed out. Please try again.',
        errorType: DriveFolderErrorType.networkError,
        cause: error,
      );
    }

    if (error is FormatException) {
      return DriveApiException(
        'Malformed response from Google Drive API.',
        errorType: DriveFolderErrorType.malformedResponse,
        cause: error,
      );
    }

    return DriveApiException(
      '$context: $error',
      errorType: DriveFolderErrorType.apiError,
      cause: error,
    );
  }
}

/// Helper client that attaches provided authorization headers to every outgoing request.
class _AuthenticatedHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final Map<String, String> _headers;

  _AuthenticatedHttpClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
