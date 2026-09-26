import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/drive_folder_result.dart';
import 'package:photo_per_day/data/models/drive_photo_upload_result.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_operation.dart';
import 'package:photo_per_day/data/models/sync_operation_status.dart';
import 'package:photo_per_day/data/models/sync_operation_type.dart';
import 'package:photo_per_day/data/models/sync_run_result.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/models/sync_tombstone.dart';
import 'package:photo_per_day/data/services/drive_api_adapter.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_photo_upload_service.dart';
import 'package:photo_per_day/data/services/google_drive_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/sync_queue.dart';

/// Coordinator service managing manual execution of the durable synchronization queue.
///
/// Guarantees:
/// - Manual execution ONLY: Never triggers automatically from app launch, lifecycle, or timers.
/// - Scope: Safely processes upload, update, and delete queue operations.
/// - FIFO ordering: Processes operations in exact chronological outbox order.
/// - Authoritative source of truth: Resolves fresh [PhotoEntry] and tombstones from [PersistentDailyPhotoStore].
/// - Single in-flight worker lock: Prevents concurrent duplicate runs.
/// - Remote file ID safety: Validates file IDs against root, empty, or folder ID confusion.
/// - Drive revision handling: Captures Drive version on update and marks local store synced.
/// - Tombstone lifecycle: Retains tombstones on failure; clears tombstones only upon confirmed Drive delete or 404.
/// - Targeted operation acknowledgement: Acknowledges ONLY the completed operation.
/// - Offline preservation: Never deletes local photos or queue items on upload/update failure.
class SyncWorker with ChangeNotifier {
  SyncWorker({
    SyncQueue? syncQueue,
    PersistentDailyPhotoStore? photoStore,
    GoogleAuthService? authService,
    GoogleDriveAuthService? driveAuthService,
    GoogleDriveService? driveService,
    GoogleDrivePhotoUploadService? uploadService,
    DriveApiAdapter? driveAdapter,
  }) : _injectedSyncQueue = syncQueue,
       _injectedPhotoStore = photoStore,
       _injectedAuthService = authService,
       _injectedDriveAuthService = driveAuthService,
       _injectedDriveService = driveService,
       _injectedUploadService = uploadService,
       _injectedDriveAdapter = driveAdapter;

  static SyncWorker? _instance;

  /// The active singleton instance.
  static SyncWorker get instance => _instance ??= SyncWorker();

  @visibleForTesting
  static void setTestInstance(SyncWorker worker) {
    _instance = worker;
  }

  @visibleForTesting
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }

  final SyncQueue? _injectedSyncQueue;
  final PersistentDailyPhotoStore? _injectedPhotoStore;
  final GoogleAuthService? _injectedAuthService;
  final GoogleDriveAuthService? _injectedDriveAuthService;
  final GoogleDriveService? _injectedDriveService;
  final GoogleDrivePhotoUploadService? _injectedUploadService;
  final DriveApiAdapter? _injectedDriveAdapter;

  SyncQueue get _queue =>
      _injectedSyncQueue ??
      (_injectedPhotoStore?.syncQueue ??
          PersistentDailyPhotoStore.instance.syncQueue);
  PersistentDailyPhotoStore get _store =>
      _injectedPhotoStore ?? PersistentDailyPhotoStore.instance;
  GoogleAuthService get _auth =>
      _injectedAuthService ?? GoogleAuthService.instance;
  GoogleDriveAuthService get _driveAuth =>
      _injectedDriveAuthService ?? GoogleDriveAuthService.instance;
  GoogleDriveService get _drive =>
      _injectedDriveService ?? GoogleDriveService.instance;
  GoogleDrivePhotoUploadService get _uploadService =>
      _injectedUploadService ?? GoogleDrivePhotoUploadService.instance;
  DriveApiAdapter get _driveAdapter =>
      _injectedDriveAdapter ?? const GoogleApisDriveAdapter();

  bool _isRunning = false;
  double? _activeProgress;
  String? _activeOperationId;
  DateKey? _activeDateKey;

  /// Whether a synchronization run is actively in flight.
  bool get isSyncing => _isRunning;

  /// Byte-transfer progress (0.0 to 1.0) of the currently uploading/updating photo, or null.
  double? get activeProgress => _activeProgress;

  /// ID of the operation currently being processed, or null.
  String? get activeOperationId => _activeOperationId;

  /// DateKey of the photo currently being processed, or null.
  DateKey? get activeDateKey => _activeDateKey;

  /// Validates that [fileId] is a safe, non-empty Drive file ID not confused with root or folderId.
  bool _isValidFileId(String? fileId, String? folderId) {
    if (fileId == null || fileId.trim().isEmpty) return false;
    final trimmed = fileId.trim();
    if (trimmed == 'root') return false;
    if (folderId != null && trimmed == folderId.trim()) return false;
    return true;
  }

  /// Formats user-visible metadata (title, caption, location) for remote Drive description.
  String? _formatFileDescription(PhotoEntry entry) {
    final parts = <String>[];
    if (entry.title.trim().isNotEmpty) {
      parts.add('Title: ${entry.title.trim()}');
    }
    if (entry.caption != null && entry.caption!.trim().isNotEmpty) {
      parts.add('Caption: ${entry.caption!.trim()}');
    }
    if (entry.location != null && entry.location!.trim().isNotEmpty) {
      parts.add('Location: ${entry.location!.trim()}');
    }
    return parts.isEmpty ? null : parts.join('\n');
  }

  /// Manually triggers processing of the durable synchronization outbox.
  ///
  /// Safely processes [SyncOperationType.upload], [SyncOperationType.update],
  /// and [SyncOperationType.delete] in deterministic FIFO order.
  Future<SyncRunResult> syncNow() async {
    // 1. In-flight concurrency protection
    if (_isRunning) {
      return SyncRunResult.alreadyRunning(remainingCount: _queue.count);
    }

    _isRunning = true;
    _activeProgress = null;
    _activeOperationId = null;
    _activeDateKey = null;
    notifyListeners();

    try {
      // 2. Validate Google Sign-In precondition
      if (!_auth.isSignedIn) {
        return SyncRunResult.notSignedIn(remainingCount: _queue.count);
      }

      // 3. Validate Google Drive authorization precondition
      if (!_driveAuth.isAuthorized) {
        return SyncRunResult.notAuthorized(remainingCount: _queue.count);
      }

      // 4. Validate Google Drive folder readiness precondition
      if (!_drive.isReady || _drive.currentFolder?.folderId == null) {
        return SyncRunResult.folderNotReady(remainingCount: _queue.count);
      }

      // 5. Empty queue check
      if (_queue.isEmpty) {
        return SyncRunResult.empty();
      }

      // 6. Snapshot current queue in FIFO order
      final snapshot = List<SyncOperation>.from(_queue.operations);

      int processedCount = 0;
      int uploadedCount = 0;
      int updatedCount = 0;
      int deletedCount = 0;
      int failedCount = 0;
      int skippedCount = 0;
      int unsupportedCount = 0;

      final now = DateTime.now().toUtc();

      for (final op in snapshot) {
        // Verify operation is still present in queue (not removed by concurrent action)
        if (_queue.getOperation(op.id) == null) {
          continue;
        }

        // Respect retry backoff
        if (op.status == SyncOperationStatus.failed &&
            op.nextAttemptAt != null &&
            op.nextAttemptAt!.isAfter(now)) {
          skippedCount++;
          continue;
        }

        _activeOperationId = op.id;
        _activeDateKey = op.dateKey;
        _activeProgress = 0.0;
        notifyListeners();

        try {
          switch (op.type) {
            case SyncOperationType.upload:
              final uploadSuccess = await _processUpload(op);
              if (uploadSuccess) {
                uploadedCount++;
              } else {
                failedCount++;
              }
              processedCount++;
              break;

            case SyncOperationType.update:
              final updateSuccess = await _processUpdate(op);
              if (updateSuccess) {
                updatedCount++;
              } else {
                failedCount++;
              }
              processedCount++;
              break;

            case SyncOperationType.delete:
              final deleteSuccess = await _processDelete(op);
              if (deleteSuccess) {
                deletedCount++;
              } else {
                failedCount++;
              }
              processedCount++;
              break;
          }
        } catch (e) {
          // Catch unexpected errors so one failure never crashes the worker
          debugPrint('SyncWorker error on operation ${op.id}: $e');
          final currentOp = _queue.getOperation(op.id);
          if (currentOp != null &&
              currentOp.status != SyncOperationStatus.failed) {
            await _queue.markFailed(op.id, error: e.toString());
          }
          failedCount++;
          processedCount++;
        }
      }

      return SyncRunResult(
        processedCount: processedCount,
        uploadedCount: uploadedCount,
        updatedCount: updatedCount,
        deletedCount: deletedCount,
        failedCount: failedCount,
        skippedCount: skippedCount,
        unsupportedCount: unsupportedCount,
        remainingCount: _queue.count,
      );
    } finally {
      _isRunning = false;
      _activeProgress = null;
      _activeOperationId = null;
      _activeDateKey = null;
      notifyListeners();
    }
  }

  /// Processes a single queued [SyncOperationType.upload] operation.
  Future<bool> _processUpload(SyncOperation op) async {
    final currentEmail = _auth.currentUser?.email;

    // Account switch safety check: verify queue operation matches active account
    if (op.authorizedEmail != null &&
        currentEmail != null &&
        op.authorizedEmail != currentEmail) {
      await _queue.markFailed(
        op.id,
        error:
            'Operation was queued for account ${op.authorizedEmail}, not current account $currentEmail',
      );
      return false;
    }

    final entry = _store.getPhotoByKey(op.dateKey);

    // Edge Case: Local PhotoEntry or image file is missing
    if (entry == null || !entry.hasRealImage || entry.imagePath == null) {
      await _queue.markFailed(
        op.id,
        error: 'Local photo memory no longer exists for ${op.dateKey.format()}',
      );
      return false;
    }

    // Account switch safety check: verify photo does not belong to another account
    if (entry.driveFileId != null &&
        entry.authorizedEmail != null &&
        currentEmail != null &&
        entry.authorizedEmail != currentEmail) {
      await _queue.markFailed(
        op.id,
        error:
            'Photo Drive file belongs to account ${entry.authorizedEmail}, not current account $currentEmail',
      );
      return false;
    }

    final localFile = File(entry.imagePath!);
    if (!localFile.existsSync() || localFile.lengthSync() == 0) {
      const errorMsg = 'Local photo file is missing or empty on disk.';
      await _store.updateSyncStatus(
        dateKey: entry.dateKey,
        status: SyncStatus.failed,
        syncError: errorMsg,
      );
      final currentOp = _queue.getOperation(op.id);
      if (currentOp != null && currentOp.status != SyncOperationStatus.failed) {
        await _queue.markFailed(op.id, error: errorMsg);
      }
      return false;
    }

    // Edge Case: Photo already has a Drive file ID
    if (entry.driveFileId != null && entry.driveFileId!.isNotEmpty) {
      if (entry.syncStatus == SyncStatus.synced) {
        await _queue.markCompleted(op.id);
        return true;
      }
      // If photo has driveFileId but status is pending, update instead of uploading duplicate
      return await _processUpdate(op.copyWith(driveFileId: entry.driveFileId));
    }

    // Mark operation in progress
    await _queue.markInProgress(op.id);

    // Execute upload via existing proven GoogleDrivePhotoUploadService
    final uploadResult = await _uploadService.uploadPhoto(
      entry: entry,
      onProgress: (progress) {
        _activeProgress = progress;
        notifyListeners();
      },
    );

    if (uploadResult is DrivePhotoUploadSuccess ||
        uploadResult is DrivePhotoUploadAlreadySynced) {
      await _queue.markCompleted(op.id);
      return true;
    } else if (uploadResult is DrivePhotoUploadFailure) {
      final currentOp = _queue.getOperation(op.id);
      if (currentOp != null && currentOp.status != SyncOperationStatus.failed) {
        await _queue.markFailed(op.id, error: uploadResult.message);
      }
      return false;
    }
    return false;
  }

  /// Processes a single queued [SyncOperationType.update] operation.
  Future<bool> _processUpdate(SyncOperation op) async {
    final currentEmail = _auth.currentUser?.email;

    // Account switch safety check: verify queue operation matches active account
    if (op.authorizedEmail != null &&
        currentEmail != null &&
        op.authorizedEmail != currentEmail) {
      await _queue.markFailed(
        op.id,
        error:
            'Operation was queued for account ${op.authorizedEmail}, not current account $currentEmail',
      );
      return false;
    }

    final entry = _store.getPhotoByKey(op.dateKey);

    if (entry == null) {
      await _queue.markFailed(
        op.id,
        error: 'Photo memory no longer exists for ${op.dateKey.format()}',
      );
      return false;
    }

    // Account switch safety check: verify target remote file belongs to current account
    if (entry.authorizedEmail != null &&
        currentEmail != null &&
        entry.authorizedEmail != currentEmail) {
      await _queue.markFailed(
        op.id,
        error:
            'Photo Drive file belongs to account ${entry.authorizedEmail}, not current account $currentEmail',
      );
      return false;
    }

    final targetFileId = entry.driveFileId ?? op.driveFileId;
    if (!_isValidFileId(targetFileId, _drive.currentFolder?.folderId)) {
      await _queue.markFailed(
        op.id,
        error:
            'Invalid or missing target Drive file ID for update: $targetFileId',
      );
      return false;
    }

    if (!entry.hasRealImage || entry.imagePath == null) {
      await _queue.markFailed(
        op.id,
        error: 'Photo memory has no local image path to update.',
      );
      return false;
    }

    final localFile = File(entry.imagePath!);
    if (!localFile.existsSync() || localFile.lengthSync() == 0) {
      const errorMsg =
          'Local photo file is missing or empty on disk for update.';
      await _store.updateSyncStatus(
        dateKey: entry.dateKey,
        status: SyncStatus.failed,
        syncError: errorMsg,
      );
      final currentOp = _queue.getOperation(op.id);
      if (currentOp != null && currentOp.status != SyncOperationStatus.failed) {
        await _queue.markFailed(op.id, error: errorMsg);
      }
      return false;
    }

    await _queue.markInProgress(op.id);

    final authHeaders = await _driveAuth.getAuthHeaders();
    final filename = _uploadService.generateRemoteFilename(
      entry.dateKey,
      entry.imagePath,
    );
    final mimeType = _uploadService.resolveMimeType(filename);
    final description = _formatFileDescription(entry);

    try {
      final updateResponse = await _driveAdapter.updatePhotoFile(
        fileId: targetFileId!,
        authHeaders: authHeaders,
        file: localFile,
        filename: filename,
        mimeType: mimeType,
        description: description,
        onProgress: (progress) {
          _activeProgress = progress;
          notifyListeners();
        },
      );

      // Update local store sync status only after confirmed Drive success
      await _store.updateSyncStatus(
        dateKey: entry.dateKey,
        status: SyncStatus.synced,
        driveFileId: updateResponse.fileId,
        driveFileRevision: updateResponse.revision,
        authorizedEmail: currentEmail,
      );

      await _queue.markCompleted(op.id);
      return true;
    } on DriveApiException catch (e) {
      // Milestone 23 Section 10: Update 404 handling:
      // If remote Drive file returns 404, DO NOT silently convert update to upload.
      // Mark update operation failed and preserve it in queue with backoff.
      await _store.updateSyncStatus(
        dateKey: entry.dateKey,
        status: SyncStatus.failed,
        syncError: e.message,
      );
      final currentOp = _queue.getOperation(op.id);
      if (currentOp != null && currentOp.status != SyncOperationStatus.failed) {
        await _queue.markFailed(op.id, error: e.message);
      }
      return false;
    } catch (e) {
      final errorMsg = 'Failed updating photo memory in Drive: $e';
      await _store.updateSyncStatus(
        dateKey: entry.dateKey,
        status: SyncStatus.failed,
        syncError: errorMsg,
      );
      final currentOp = _queue.getOperation(op.id);
      if (currentOp != null && currentOp.status != SyncOperationStatus.failed) {
        await _queue.markFailed(op.id, error: errorMsg);
      }
      return false;
    }
  }

  /// Processes a single queued [SyncOperationType.delete] operation.
  Future<bool> _processDelete(SyncOperation op) async {
    final currentEmail = _auth.currentUser?.email;

    // Account switch safety check: verify queue operation matches active account
    if (op.authorizedEmail != null &&
        currentEmail != null &&
        op.authorizedEmail != currentEmail) {
      await _queue.markFailed(
        op.id,
        error:
            'Operation was queued for account ${op.authorizedEmail}, not current account $currentEmail',
      );
      return false;
    }

    String? targetFileId = op.driveFileId;
    SyncTombstone? tombstone;
    if (targetFileId == null || targetFileId.isEmpty) {
      tombstone = _store.pendingDeletions.cast<SyncTombstone?>().firstWhere(
        (t) => t?.dateKey == op.dateKey,
        orElse: () => null,
      );
      targetFileId = tombstone?.driveFileId;
    } else {
      tombstone = _store.pendingDeletions.cast<SyncTombstone?>().firstWhere(
        (t) => t?.driveFileId == targetFileId,
        orElse: () => null,
      );
    }

    // Account switch safety check: verify tombstone matches active account
    if (tombstone?.authorizedEmail != null &&
        currentEmail != null &&
        tombstone!.authorizedEmail != currentEmail) {
      await _queue.markFailed(
        op.id,
        error:
            'Tombstone belongs to account ${tombstone.authorizedEmail}, not current account $currentEmail',
      );
      return false;
    }

    if (!_isValidFileId(targetFileId, _drive.currentFolder?.folderId)) {
      await _queue.markFailed(
        op.id,
        error:
            'Invalid or missing target Drive file ID for deletion: $targetFileId',
      );
      return false;
    }

    await _queue.markInProgress(op.id);

    final authHeaders = await _driveAuth.getAuthHeaders();

    try {
      await _driveAdapter.trashPhotoFile(
        fileId: targetFileId!,
        authHeaders: authHeaders,
      );

      // Confirmed success: acknowledge queue operation and acknowledge/remove tombstone
      await _queue.markCompleted(op.id);
      await _store.acknowledgePendingDeletion(targetFileId);
      return true;
    } on DriveApiException catch (e) {
      if (e.errorType == DriveFolderErrorType.notFound) {
        // Milestone 23 Section 9: HTTP 404 / Already-deleted handling:
        // Considered an idempotent success. Acknowledge delete op and clear tombstone.
        await _queue.markCompleted(op.id);
        await _store.acknowledgePendingDeletion(targetFileId!);
        return true;
      }

      // Delete failure: do NOT acknowledge queue, do NOT remove tombstone, preserve retry state
      await _queue.markFailed(op.id, error: e.message);
      return false;
    } catch (e) {
      final errorMsg = 'Failed deleting remote photo in Drive: $e';
      await _queue.markFailed(op.id, error: errorMsg);
      return false;
    }
  }
}
