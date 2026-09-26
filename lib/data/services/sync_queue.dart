import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/sync_operation.dart';
import 'package:photo_per_day/data/models/sync_operation_status.dart';
import 'package:photo_per_day/data/models/sync_operation_type.dart';
import 'package:photo_per_day/data/services/sync_queue_storage.dart';

/// Manages a durable, local, persistent synchronization outbox.
///
/// Responsible for:
/// - Enqueueing remote sync intents (upload, update, delete).
/// - Deduplication and coalescing of redundant operations on the same [DateKey].
/// - Surviving process crashes and app restarts with automatic inProgress recovery.
/// - FIFO ordering and deterministic retry scheduling.
///
/// NOTE: The synchronization queue is NOT the authoritative source of truth
/// for photo content or metadata. The local [PhotoEntry] and [PersistentDailyPhotoStore]
/// remain authoritative.
class SyncQueue with ChangeNotifier {
  SyncQueue({SyncQueueStorage? storage})
    : _storage = storage ?? SyncQueueStorage();

  final SyncQueueStorage _storage;
  final List<SyncOperation> _operations = [];
  bool _isInitialized = false;
  Future<void>? _activeOp;

  /// Whether the queue has finished loading persisted operations from disk.
  bool get isInitialized => _isInitialized;

  /// The underlying [SyncQueueStorage] instance.
  SyncQueueStorage get storage => _storage;

  /// All operations currently in the queue in FIFO order.
  List<SyncOperation> get operations => List.unmodifiable(_operations);

  /// Operations that are currently pending execution or eligible for retry.
  List<SyncOperation> get pendingOperations => List.unmodifiable(
    _operations.where(
      (op) =>
          op.status == SyncOperationStatus.pending ||
          op.status == SyncOperationStatus.failed,
    ),
  );

  /// Total count of operations in the queue.
  int get count => _operations.length;

  /// Whether the queue is empty.
  bool get isEmpty => _operations.isEmpty;

  /// Whether the queue has any non-completed operations.
  bool get isNotEmpty => _operations.isNotEmpty;

  /// FIFO sequential execution helper ensuring atomic mutations.
  Future<T> _runSequential<T>(Future<T> Function() operation) async {
    final previous = _activeOp;
    final completer = Completer<void>();
    _activeOp = completer.future.catchError((_) {});

    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }

    try {
      final result = await operation();
      completer.complete();
      return result;
    } catch (e, stack) {
      completer.completeError(e, stack);
      rethrow;
    }
  }

  /// Waits for all currently active or queued disk operations to complete.
  Future<void> flush() async {
    while (_activeOp != null) {
      final current = _activeOp;
      try {
        await current;
      } catch (_) {}
      if (identical(_activeOp, current)) {
        break;
      }
    }
  }

  /// Initializes storage, restores persisted operations, and executes crash recovery.
  Future<void> init() async {
    await _storage.init();
    final loaded = await _storage.loadQueue();

    _operations.clear();
    _operations.addAll(loaded);
    _isInitialized = true;

    // If any operations were recovered from inProgress to pending, persist them
    final hadRecoveries = loaded.any(
      (op) =>
          op.status == SyncOperationStatus.pending && op.lastAttemptAt != null,
    );
    if (hadRecoveries) {
      try {
        await _storage.saveQueue(_operations);
      } catch (e) {
        debugPrint('Non-critical error saving recovered queue states: $e');
      }
    }

    notifyListeners();
  }

  /// Enqueues an upload operation for a newly added photo on [dateKey].
  ///
  /// Coalescing Strategy:
  /// - If an upload or update operation already exists for [dateKey], coalesce:
  ///   keep the existing operation without creating duplicate queue items.
  Future<SyncOperation> enqueueUpload(
    DateKey dateKey, {
    String? authorizedEmail,
  }) {
    return _runSequential(() async {
      final existingIndex = _operations.indexWhere(
        (op) =>
            op.dateKey == dateKey &&
            (op.type == SyncOperationType.upload ||
                op.type == SyncOperationType.update),
      );

      if (existingIndex != -1) {
        // Coalesce: reset status to pending and clear error
        final existing = _operations[existingIndex];
        final coalesced = existing.copyWith(
          status: SyncOperationStatus.pending,
          authorizedEmail: authorizedEmail ?? existing.authorizedEmail,
          clearLastError: true,
        );
        _operations[existingIndex] = coalesced;
        if (_isInitialized) await _storage.saveQueue(_operations);
        notifyListeners();
        return coalesced;
      }

      final now = DateTime.now().toUtc();
      final op = SyncOperation(
        id: 'op_${dateKey.format()}_${now.microsecondsSinceEpoch}',
        type: SyncOperationType.upload,
        dateKey: dateKey,
        createdAt: now,
        status: SyncOperationStatus.pending,
        authorizedEmail: authorizedEmail,
      );

      _operations.add(op);
      if (_isInitialized) await _storage.saveQueue(_operations);
      notifyListeners();
      return op;
    });
  }

  /// Enqueues an update operation for an edited or replaced remote photo on [dateKey].
  ///
  /// Coalescing Strategy:
  /// - If a pending upload already exists for [dateKey], the photo has not yet
  ///   been created remotely. Therefore, we coalesce and keep it as an [upload].
  /// - If an update operation already exists, we coalesce and update it in-place.
  Future<SyncOperation> enqueueUpdate(
    DateKey dateKey, {
    String? driveFileId,
    String? authorizedEmail,
  }) {
    return _runSequential(() async {
      // 1. If an upload is pending, keep it as an upload (newest local PhotoEntry will be sent)
      final existingUploadIndex = _operations.indexWhere(
        (op) => op.dateKey == dateKey && op.type == SyncOperationType.upload,
      );
      if (existingUploadIndex != -1) {
        final existing = _operations[existingUploadIndex];
        final updated = existing.copyWith(
          status: SyncOperationStatus.pending,
          authorizedEmail: authorizedEmail ?? existing.authorizedEmail,
          clearLastError: true,
        );
        _operations[existingUploadIndex] = updated;
        if (_isInitialized) await _storage.saveQueue(_operations);
        notifyListeners();
        return updated;
      }

      // 2. If an update already exists, coalesce in-place
      final existingUpdateIndex = _operations.indexWhere(
        (op) => op.dateKey == dateKey && op.type == SyncOperationType.update,
      );
      if (existingUpdateIndex != -1) {
        final existing = _operations[existingUpdateIndex];
        final updated = existing.copyWith(
          status: SyncOperationStatus.pending,
          driveFileId: driveFileId ?? existing.driveFileId,
          authorizedEmail: authorizedEmail ?? existing.authorizedEmail,
          clearLastError: true,
        );
        _operations[existingUpdateIndex] = updated;
        if (_isInitialized) await _storage.saveQueue(_operations);
        notifyListeners();
        return updated;
      }

      // 3. New update operation
      final now = DateTime.now().toUtc();
      final op = SyncOperation(
        id: 'op_${dateKey.format()}_${now.microsecondsSinceEpoch}',
        type: SyncOperationType.update,
        dateKey: dateKey,
        createdAt: now,
        status: SyncOperationStatus.pending,
        driveFileId: driveFileId,
        authorizedEmail: authorizedEmail,
      );

      _operations.add(op);
      if (_isInitialized) await _storage.saveQueue(_operations);
      notifyListeners();
      return op;
    });
  }

  /// Enqueues a remote deletion operation for a previously synced photo with [driveFileId].
  ///
  /// Coalescing Strategy:
  /// - Any pending [upload] or [update] operations for [dateKey] are obsolete
  ///   because the local photo is deleted; they are pruned from the queue.
  /// - If a [delete] operation already exists for this [driveFileId], it is preserved.
  Future<SyncOperation> enqueueDelete(
    DateKey dateKey, {
    required String driveFileId,
    String? authorizedEmail,
  }) {
    return _runSequential(() async {
      // Prune obsolete upload/update operations for this date
      _operations.removeWhere(
        (op) =>
            op.dateKey == dateKey &&
            (op.type == SyncOperationType.upload ||
                op.type == SyncOperationType.update),
      );

      // Check if delete operation already exists for this driveFileId
      final existingDeleteIndex = _operations.indexWhere(
        (op) =>
            op.type == SyncOperationType.delete &&
            op.driveFileId == driveFileId,
      );

      if (existingDeleteIndex != -1) {
        return _operations[existingDeleteIndex];
      }

      final now = DateTime.now().toUtc();
      final op = SyncOperation(
        id: 'op_${dateKey.format()}_${now.microsecondsSinceEpoch}',
        type: SyncOperationType.delete,
        dateKey: dateKey,
        createdAt: now,
        status: SyncOperationStatus.pending,
        driveFileId: driveFileId,
        authorizedEmail: authorizedEmail,
      );

      _operations.add(op);
      if (_isInitialized) await _storage.saveQueue(_operations);
      notifyListeners();
      return op;
    });
  }

  /// Removes any unexecuted upload/update operations for [dateKey].
  ///
  /// Used when a local-only photo is deleted before it has ever been synchronized.
  Future<void> removeOperationsForDate(DateKey dateKey) {
    return _runSequential(() async {
      final countBefore = _operations.length;
      _operations.removeWhere(
        (op) =>
            op.dateKey == dateKey &&
            (op.type == SyncOperationType.upload ||
                op.type == SyncOperationType.update),
      );

      if (_operations.length != countBefore) {
        if (_isInitialized) await _storage.saveQueue(_operations);
        notifyListeners();
      }
    });
  }

  /// Marks an operation as actively [SyncOperationStatus.inProgress].
  Future<SyncOperation?> markInProgress(String operationId) {
    return _runSequential(() async {
      final index = _operations.indexWhere((op) => op.id == operationId);
      if (index == -1) return null;

      final updated = _operations[index].copyWith(
        status: SyncOperationStatus.inProgress,
        lastAttemptAt: DateTime.now().toUtc(),
      );
      _operations[index] = updated;
      if (_isInitialized) await _storage.saveQueue(_operations);
      notifyListeners();
      return updated;
    });
  }

  /// Marks an operation as [SyncOperationStatus.failed], incrementing retryCount
  /// and computing deterministic backoff.
  Future<SyncOperation?> markFailed(
    String operationId, {
    required String error,
    DateTime? nextAttemptAt,
  }) {
    return _runSequential(() async {
      final index = _operations.indexWhere((op) => op.id == operationId);
      if (index == -1) return null;

      final existing = _operations[index];
      final newRetryCount = existing.retryCount + 1;
      final now = DateTime.now().toUtc();
      final nextAttempt =
          nextAttemptAt ?? now.add(SyncOperation.computeBackoff(newRetryCount));

      final updated = existing.copyWith(
        status: SyncOperationStatus.failed,
        retryCount: newRetryCount,
        lastAttemptAt: now,
        nextAttemptAt: nextAttempt,
        lastError: error,
      );

      _operations[index] = updated;
      if (_isInitialized) await _storage.saveQueue(_operations);
      notifyListeners();
      return updated;
    });
  }

  /// Marks an operation as completed and prunes it from the active queue.
  Future<bool> markCompleted(String operationId) {
    return _runSequential(() async {
      final index = _operations.indexWhere((op) => op.id == operationId);
      if (index == -1) return false;

      _operations.removeAt(index);
      if (_isInitialized) await _storage.saveQueue(_operations);
      notifyListeners();
      return true;
    });
  }

  /// Finds a queued operation by its unique [id].
  SyncOperation? getOperation(String id) {
    try {
      return _operations.firstWhere((op) => op.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Finds an active (upload/update/delete) operation for [dateKey].
  SyncOperation? getOperationForDate(DateKey dateKey) {
    try {
      return _operations.firstWhere((op) => op.dateKey == dateKey);
    } catch (_) {
      return null;
    }
  }

  /// Checks if an active operation exists for [dateKey].
  bool hasOperationForDate(DateKey dateKey) {
    return _operations.any((op) => op.dateKey == dateKey);
  }

  /// Clears all operations from memory and disk.
  Future<void> clear() {
    return _runSequential(() async {
      _operations.clear();
      if (_isInitialized) {
        await _storage.clear();
      }
      notifyListeners();
    });
  }
}
