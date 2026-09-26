import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/drive_folder_result.dart';
import 'package:photo_per_day/data/models/drive_photo_upload_result.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/drive_api_adapter.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';

/// Coordinator service responsible for single-photo proof-of-concept uploads to Google Drive.
///
/// Guarantees:
/// - Narrow scope: Uploads exactly ONE photo upon explicit request.
/// - Validates all prerequisites (auth, Drive scope, folder readiness, file existence) before network calls.
/// - Targets the existing "Photo a Day" folder ID directly (`parents: [folderId]`).
/// - Real byte-transfer progress reporting (0.0 to 1.0).
/// - Safe failure handling: local photos and outbox are never deleted or corrupted on failure.
/// - Duplicate prevention: returns typed already-synced result if photo is already synced.
/// - In-flight protection: blocks concurrent duplicate uploads for the same DateKey.
class GoogleDrivePhotoUploadService extends ChangeNotifier {
  GoogleDrivePhotoUploadService({
    DriveApiAdapter? adapter,
    GoogleAuthService? authService,
    GoogleDriveAuthService? driveAuthService,
    GoogleDriveService? driveService,
    PersistentDailyPhotoStore? photoStore,
  }) : _adapter = adapter ?? const GoogleApisDriveAdapter(),
       _injectedAuthService = authService,
       _injectedDriveAuthService = driveAuthService,
       _injectedDriveService = driveService,
       _injectedPhotoStore = photoStore;

  static GoogleDrivePhotoUploadService? _instance;

  /// The active singleton instance.
  static GoogleDrivePhotoUploadService get instance =>
      _instance ??= GoogleDrivePhotoUploadService();

  @visibleForTesting
  static void setTestInstance(GoogleDrivePhotoUploadService service) {
    _instance = service;
  }

  @visibleForTesting
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }

  final DriveApiAdapter _adapter;
  final GoogleAuthService? _injectedAuthService;
  final GoogleDriveAuthService? _injectedDriveAuthService;
  final GoogleDriveService? _injectedDriveService;
  final PersistentDailyPhotoStore? _injectedPhotoStore;

  GoogleAuthService get _effectiveAuth =>
      _injectedAuthService ?? GoogleAuthService.instance;
  GoogleDriveAuthService get _effectiveDriveAuth =>
      _injectedDriveAuthService ?? GoogleDriveAuthService.instance;
  GoogleDriveService get _effectiveDrive =>
      _injectedDriveService ?? GoogleDriveService.instance;
  PersistentDailyPhotoStore get _effectiveStore =>
      _injectedPhotoStore ?? PersistentDailyPhotoStore.instance;

  /// In-flight upload tracking to prevent concurrent duplicates.
  final Set<DateKey> _activeUploads = {};

  /// Whether an upload is actively in flight for the given [dateKey].
  bool isUploading(DateKey dateKey) => _activeUploads.contains(dateKey);

  /// Whether any upload is currently in flight.
  bool get hasActiveUpload => _activeUploads.isNotEmpty;

  /// Generates the deterministic remote filename for a photo memory.
  ///
  /// Pattern: `photo_YYYY-MM-DD.jpg`
  String generateRemoteFilename(DateKey dateKey, String? localImagePath) {
    String ext = '.jpg';
    if (localImagePath != null && localImagePath.isNotEmpty) {
      final fileExt = p.extension(localImagePath).toLowerCase();
      if (fileExt == '.png') {
        ext = '.png';
      } else if (fileExt == '.jpeg' || fileExt == '.jpg') {
        ext = '.jpg';
      }
    }
    return 'photo_${dateKey.format()}$ext';
  }

  /// Resolves the MIME type from the target filename.
  String resolveMimeType(String filename) {
    if (filename.toLowerCase().endsWith('.png')) {
      return 'image/png';
    }
    return 'image/jpeg';
  }

  /// Uploads exactly ONE existing local photo to the user's "Photo a Day" Drive folder.
  ///
  /// Enforces all security, identity, and filesystem preconditions before
  /// initiating the network request.
  Future<DrivePhotoUploadResult> uploadPhoto({
    required PhotoEntry entry,
    DriveUploadProgress? onProgress,
  }) async {
    final auth = _effectiveAuth;
    final driveAuth = _effectiveDriveAuth;
    final drive = _effectiveDrive;
    final store = _effectiveStore;

    // 1. Verify Google Sign-In
    if (!auth.isSignedIn) {
      return const DrivePhotoUploadFailure(
        'Google account sign-in required to upload photos.',
        errorType: DrivePhotoUploadErrorType.notSignedIn,
      );
    }

    // 2. Verify Google Drive Authorization
    if (!driveAuth.isAuthorized) {
      return const DrivePhotoUploadFailure(
        'Google Drive authorization is required to upload photos.',
        errorType: DrivePhotoUploadErrorType.notAuthorized,
      );
    }

    // 3. Verify Drive Folder Readiness
    if (!drive.isReady || drive.currentFolder?.folderId == null) {
      return const DrivePhotoUploadFailure(
        'Google Drive folder "Photo a Day" is not ready.',
        errorType: DrivePhotoUploadErrorType.folderNotReady,
      );
    }

    final folderId = drive.currentFolder!.folderId;

    // 4. Verify PhotoEntry has a local image path
    if (!entry.hasRealImage || entry.imagePath == null) {
      return const DrivePhotoUploadFailure(
        'Photo memory has no local image path to upload.',
        errorType: DrivePhotoUploadErrorType.invalidMetadata,
      );
    }

    // 5. Duplicate Prevention: Check if photo is already synced
    if (entry.driveFileId != null &&
        entry.driveFileId!.isNotEmpty &&
        entry.syncStatus == SyncStatus.synced) {
      return DrivePhotoUploadAlreadySynced(
        fileId: entry.driveFileId!,
        dateKey: entry.dateKey,
      );
    }

    // 6. In-flight Lock: Prevent concurrent duplicate uploads for the same DateKey
    if (_activeUploads.contains(entry.dateKey)) {
      return DrivePhotoUploadFailure(
        'An upload for photo memory ${entry.dateKey.format()} is already in progress.',
        errorType: DrivePhotoUploadErrorType.alreadyInProgress,
      );
    }

    // 7. Verify local image file exists and is non-empty
    final localFile = File(entry.imagePath!);
    if (!localFile.existsSync()) {
      return const DrivePhotoUploadFailure(
        'Local photo file does not exist on disk.',
        errorType: DrivePhotoUploadErrorType.fileMissing,
      );
    }

    final fileLength = localFile.lengthSync();
    if (fileLength == 0) {
      return const DrivePhotoUploadFailure(
        'Local photo file is empty (0 bytes).',
        errorType: DrivePhotoUploadErrorType.fileEmpty,
      );
    }

    // Lock DateKey for upload
    _activeUploads.add(entry.dateKey);
    notifyListeners();

    try {
      // 8. Dynamically retrieve authenticated headers
      final authHeaders = await driveAuth.getAuthHeaders();

      final filename = generateRemoteFilename(entry.dateKey, entry.imagePath);
      final mimeType = resolveMimeType(filename);

      // 9. Execute multipart upload via adapter with byte progress
      final response = await _adapter.uploadPhotoFile(
        file: localFile,
        filename: filename,
        mimeType: mimeType,
        parentFolderId: folderId,
        authHeaders: authHeaders,
        onProgress: onProgress,
      );

      // 10. Update local PhotoEntry to Synced ONLY after confirmed Drive success
      await store.updateSyncStatus(
        dateKey: entry.dateKey,
        status: SyncStatus.synced,
        driveFileId: response.fileId,
        driveFileRevision: response.revision,
        authorizedEmail: auth.currentUser?.email,
      );

      return DrivePhotoUploadSuccess(
        fileId: response.fileId,
        revision: response.revision,
        remoteFilename: response.filename,
        uploadedAt: response.uploadedAt ?? DateTime.now().toUtc(),
      );
    } on DriveApiException catch (e) {
      final errorType = _mapDriveApiError(e.errorType);
      await store.updateSyncStatus(
        dateKey: entry.dateKey,
        status: SyncStatus.failed,
        syncError: e.message,
      );
      return DrivePhotoUploadFailure(
        e.message,
        errorType: errorType,
        cause: e.cause,
      );
    } catch (e) {
      const errorMsg =
          'Unexpected error occurred while uploading photo to Google Drive.';
      await store.updateSyncStatus(
        dateKey: entry.dateKey,
        status: SyncStatus.failed,
        syncError: errorMsg,
      );
      return DrivePhotoUploadFailure(
        errorMsg,
        errorType: DrivePhotoUploadErrorType.apiError,
        cause: e,
      );
    } finally {
      _activeUploads.remove(entry.dateKey);
      notifyListeners();
    }
  }

  DrivePhotoUploadErrorType _mapDriveApiError(DriveFolderErrorType errorType) {
    switch (errorType) {
      case DriveFolderErrorType.notSignedIn:
        return DrivePhotoUploadErrorType.notSignedIn;
      case DriveFolderErrorType.notAuthorized:
        return DrivePhotoUploadErrorType.notAuthorized;
      case DriveFolderErrorType.networkError:
        return DrivePhotoUploadErrorType.networkError;
      case DriveFolderErrorType.unauthorized:
        return DrivePhotoUploadErrorType.unauthorized;
      case DriveFolderErrorType.forbidden:
        return DrivePhotoUploadErrorType.forbidden;
      case DriveFolderErrorType.notFound:
        return DrivePhotoUploadErrorType.notFound;
      case DriveFolderErrorType.malformedResponse:
        return DrivePhotoUploadErrorType.malformedResponse;
      case DriveFolderErrorType.apiError:
        return DrivePhotoUploadErrorType.apiError;
    }
  }
}
