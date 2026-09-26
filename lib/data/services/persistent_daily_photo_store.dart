import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_operation.dart';
import 'package:photo_per_day/data/models/sync_operation_type.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/models/sync_tombstone.dart';
import 'package:photo_per_day/data/services/daily_photo_rule.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/data/services/sync_queue.dart';
import 'package:photo_per_day/data/services/sync_queue_storage.dart';

/// Production implementation of [DailyPhotoStore] delivering persistent local storage,
/// sync-state lifecycle management, and durable local outbox synchronization queueing.
///
/// Features:
/// - In-memory synchronous cache for instantaneous UI queries.
/// - Two-layer storage: app-controlled photo files directory + atomic JSON metadata registry.
/// - Single-photo-per-day enforcement with safe replacement (copy new -> write metadata -> delete old).
/// - Graceful handling of missing files, database corruptions, and cold app restarts.
/// - Serialized async queueing preventing race conditions across concurrent operations.
/// - Synchronization metadata tracking (localOnly, pending, synced, failed) without network coupling.
/// - Pending deletion tombstones and durable local outbox queue for future Google Drive sync.
class PersistentDailyPhotoStore extends ChangeNotifier
    implements DailyPhotoStore {
  PersistentDailyPhotoStore({
    PhotoFileManager? fileManager,
    PhotoMetadataStorage? metadataStorage,
    SyncQueue? syncQueue,
  }) : _fileManager = fileManager ?? PhotoFileManager(),
       _metadataStorage = metadataStorage ?? PhotoMetadataStorage(),
       _syncQueue =
           syncQueue ??
           SyncQueue(
             storage: SyncQueueStorage(
               customBaseDir:
                   fileManager?.customBaseDir ?? metadataStorage?.customBaseDir,
             ),
           );

  static PersistentDailyPhotoStore? _testInstance;

  /// The active singleton or test instance.
  static PersistentDailyPhotoStore get instance =>
      _testInstance ?? _defaultInstance;

  static final PersistentDailyPhotoStore _defaultInstance =
      PersistentDailyPhotoStore();

  @visibleForTesting
  static void setTestInstance(PersistentDailyPhotoStore testStore) {
    _testInstance = testStore;
  }

  @visibleForTesting
  static void resetTestInstance() {
    _testInstance = null;
  }

  PhotoFileManager _fileManager;
  PhotoMetadataStorage _metadataStorage;
  SyncQueue _syncQueue;

  /// In-memory cache of daily photo entries keyed by normalized DateKey.
  final Map<DateKey, PhotoEntry> _entries = {};

  /// In-memory cache of pending remote cloud deletions (tombstones).
  final List<SyncTombstone> _pendingDeletions = [];

  bool _isInitialized = false;
  Future<void>? _activeOp;

  /// Whether the store has completed loading its persisted records from disk.
  bool get isInitialized => _isInitialized;

  /// The underlying [PhotoFileManager] used by this store.
  PhotoFileManager get fileManager => _fileManager;

  /// The durable synchronization outbox used by this store.
  SyncQueue get syncQueue => _syncQueue;

  /// Unmodifiable view of all pending cloud deletion tombstones.
  List<SyncTombstone> get pendingDeletions =>
      List.unmodifiable(_pendingDeletions);

  /// Checks if there is a pending cloud deletion tombstone for [dateKey].
  bool hasPendingDeletion(DateKey dateKey) =>
      _pendingDeletions.any((tombstone) => tombstone.dateKey == dateKey);

  /// Lightweight sequential FIFO executor ensuring that persistent mutations
  /// never race against each other, even under rapid consecutive calls.
  Future<T> _runSequential<T>(Future<T> Function() operation) async {
    final previous = _activeOp;
    final completer = Completer<void>();
    _activeOp = completer.future.catchError((_) {});

    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // Continue even if previous operation had an issue
      }
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

  /// Awaits completion of all currently active or queued disk operations.
  /// Useful for lifecycle shutdowns, synchronization barriers, and deterministic testing.
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
    await _syncQueue.flush();
  }

  /// Initializes the file directory, restores persisted photo metadata,
  /// restores pending deletion tombstones, and initializes the sync outbox queue.
  Future<void> init({Directory? customBaseDir}) async {
    if (customBaseDir != null) {
      _fileManager = PhotoFileManager(customBaseDir: customBaseDir);
      _metadataStorage = PhotoMetadataStorage(customBaseDir: customBaseDir);
      _syncQueue = SyncQueue(
        storage: SyncQueueStorage(customBaseDir: customBaseDir),
      );
    } else {
      final fallbackDir =
          _fileManager.customBaseDir ?? _metadataStorage.customBaseDir;
      if (fallbackDir != null && _syncQueue.storage.customBaseDir == null) {
        _syncQueue = SyncQueue(
          storage: SyncQueueStorage(customBaseDir: fallbackDir),
        );
      }
    }

    await _fileManager.init();
    await _metadataStorage.init();
    await _syncQueue.init();

    final loaded = await _metadataStorage.loadAll();
    _entries.clear();
    _entries.addAll(loaded);

    final loadedDeletions = await _metadataStorage.loadPendingDeletions();
    _pendingDeletions.clear();
    _pendingDeletions.addAll(loadedDeletions);

    // Crash recovery: ensure all restored pending deletions have a corresponding delete op in the queue
    for (final tombstone in _pendingDeletions) {
      final hasOp = _syncQueue.operations.any(
        (op) =>
            op.type == SyncOperationType.delete &&
            op.driveFileId == tombstone.driveFileId,
      );
      if (!hasOp) {
        await _syncQueue.enqueueDelete(
          tombstone.dateKey,
          driveFileId: tombstone.driveFileId,
          authorizedEmail: tombstone.authorizedEmail,
        );
      }
    }

    _isInitialized = true;

    // Clean up any unreferenced orphan files from previous interrupted operations.
    // Non-critical startup cleanup failures must never prevent the app from launching.
    try {
      await reconcileOrphanFiles();
    } catch (e) {
      debugPrint('Non-critical orphan reconciliation error during init: $e');
    }

    notifyListeners();
  }

  @override
  PhotoEntry? getPhoto(DateTime date) {
    return _entries[DateKey.fromDateTime(date)];
  }

  @override
  PhotoEntry? getPhotoByKey(DateKey key) {
    return _entries[key];
  }

  @override
  bool hasPhoto(DateTime date) {
    return _entries.containsKey(DateKey.fromDateTime(date));
  }

  @override
  bool hasPhotoByKey(DateKey key) {
    return _entries.containsKey(key);
  }

  @override
  int get totalPhotos => _entries.length;

  /// Total count of stored photos.
  int get count => _entries.length;

  /// Unmodifiable view of all stored photo entries.
  List<PhotoEntry> get allEntries => List.unmodifiable(_entries.values);

  /// Unmodifiable view of all recorded DateKeys.
  List<DateKey> get recordedDates => List.unmodifiable(_entries.keys);

  /// Saves or replaces a photo with full persistence lifecycle handling:
  /// 1. Pre-validates source photo file (must exist and be non-empty).
  /// 2. Copies the source photo into app-owned storage if needed.
  /// 3. Resolves sync state: preserves Drive ID on replacement, marks [SyncStatus.pending]
  ///    if replacing a synced photo, or uses [SyncStatus.localOnly] for new photos.
  /// 4. Atomically commits metadata to disk with rollback on failure.
  /// 5. Updates in-memory cache and safely cleans up any previous photo file.
  Future<PhotoEntry> savePhoto({
    required PhotoEntry entry,
    String? sourceTempPath,
  }) {
    return _runSequential(
      () => _savePhotoInternal(entry: entry, sourceTempPath: sourceTempPath),
    );
  }

  Future<PhotoEntry> _savePhotoInternal({
    required PhotoEntry entry,
    String? sourceTempPath,
  }) async {
    final key = entry.dateKey;
    final oldEntry = _entries[key];

    String? persistentPath = entry.imagePath;

    final pathToPersist = sourceTempPath ?? entry.imagePath;
    if (pathToPersist != null && pathToPersist.isNotEmpty) {
      final sourceFile = File(pathToPersist);
      if (!sourceFile.existsSync()) {
        throw FileSystemException(
          'Source photo file does not exist',
          pathToPersist,
        );
      }
      final length = sourceFile.lengthSync();
      if (length == 0) {
        throw FileSystemException(
          'Source photo file is empty (0 bytes)',
          pathToPersist,
        );
      }

      if (_isInitialized && !_fileManager.isManagedPath(pathToPersist)) {
        persistentPath = await _fileManager.persistPhotoFile(
          sourcePath: pathToPersist,
          dateKey: key,
        );
      }
    }

    // Resolve synchronization state and remote metadata
    SyncStatus resolvedSyncStatus;
    String? driveFileId = entry.driveFileId;
    String? driveFileRevision = entry.driveFileRevision;
    String? authorizedEmail = entry.authorizedEmail;

    if (oldEntry != null) {
      // Replacement on existing DateKey
      driveFileId ??= oldEntry.driveFileId;
      driveFileRevision ??= oldEntry.driveFileRevision;
      authorizedEmail ??= oldEntry.authorizedEmail;

      if (oldEntry.syncStatus == SyncStatus.synced ||
          oldEntry.syncStatus == SyncStatus.failed) {
        resolvedSyncStatus = SyncStatus.pending;
      } else {
        resolvedSyncStatus = oldEntry.syncStatus;
      }
    } else {
      // Brand new local photo
      resolvedSyncStatus = entry.syncStatus;
    }

    final updatedEntry = entry.copyWith(
      imagePath: persistentPath,
      syncStatus: resolvedSyncStatus,
      lastModifiedAt: DateTime.now().toUtc(),
      driveFileId: driveFileId,
      driveFileRevision: driveFileRevision,
      authorizedEmail: authorizedEmail,
      clearSyncError: true,
    );

    // Two-Phase Commit: Prepare tentative entries map for disk write
    final tentative = Map<DateKey, PhotoEntry>.from(_entries);
    tentative[key] = updatedEntry;

    if (_isInitialized) {
      try {
        await _metadataStorage.saveAll(tentative);
      } catch (e) {
        // Rollback: if a new file was created and is different from oldEntry.imagePath, prune it
        if (persistentPath != null &&
            persistentPath != oldEntry?.imagePath &&
            !_fileManager.isManagedPath(pathToPersist ?? '')) {
          await _fileManager.deletePhotoFile(persistentPath);
        }
        rethrow;
      }

      // Metadata write succeeded. Now clean up old file if different.
      if (oldEntry != null &&
          oldEntry.hasRealImage &&
          oldEntry.imagePath != persistentPath) {
        await _fileManager.deletePhotoFile(oldEntry.imagePath);
      }

      // If this date previously had a pending cloud deletion, clear it now that a new photo exists
      if (_pendingDeletions.any((t) => t.dateKey == key)) {
        _pendingDeletions.removeWhere((t) => t.dateKey == key);
        await _metadataStorage.savePendingDeletions(_pendingDeletions);
      }

      // SyncQueue: Enqueue remote operation if photo needs cloud synchronization
      if (resolvedSyncStatus == SyncStatus.pending) {
        if (oldEntry != null && oldEntry.driveFileId != null) {
          await _syncQueue.enqueueUpdate(
            key,
            driveFileId: oldEntry.driveFileId,
            authorizedEmail: oldEntry.authorizedEmail,
          );
        } else {
          await _syncQueue.enqueueUpload(key, authorizedEmail: authorizedEmail);
        }
      }
    }

    // Update in-memory cache
    _entries[key] = updatedEntry;
    notifyListeners();
    return updatedEntry;
  }

  /// Atomically updates metadata (title, caption, location) for an existing photo entry.
  ///
  /// Guarantees:
  /// - The underlying image file is NOT touched or duplicated.
  /// - The DateKey identity is preserved, preventing duplicate photos for the same date.
  /// - Sync state transitions from [SyncStatus.synced] or [SyncStatus.failed] to [SyncStatus.pending].
  /// - [driveFileId] and [driveFileRevision] are safely preserved.
  /// - If disk write fails, the in-memory cache rolls back and remains uncorrupted.
  Future<PhotoEntry> updatePhotoMetadata({
    required DateKey dateKey,
    String? title,
    String? caption,
    String? location,
  }) {
    return _runSequential(
      () => _updatePhotoMetadataInternal(
        dateKey: dateKey,
        title: title,
        caption: caption,
        location: location,
      ),
    );
  }

  Future<PhotoEntry> _updatePhotoMetadataInternal({
    required DateKey dateKey,
    String? title,
    String? caption,
    String? location,
  }) async {
    final existing = _entries[dateKey];
    if (existing == null) {
      throw StateError('No photo entry found for date key $dateKey');
    }

    SyncStatus resolvedStatus = existing.syncStatus;
    if (existing.syncStatus == SyncStatus.synced ||
        existing.syncStatus == SyncStatus.failed) {
      resolvedStatus = SyncStatus.pending;
    }

    final updated = existing.copyWith(
      title: (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : existing.title,
      caption: caption,
      location: location,
      syncStatus: resolvedStatus,
      lastModifiedAt: DateTime.now().toUtc(),
      clearSyncError: true,
    );

    final tentative = Map<DateKey, PhotoEntry>.from(_entries);
    tentative[dateKey] = updated;

    if (_isInitialized) {
      await _metadataStorage.saveAll(tentative);
      if (resolvedStatus == SyncStatus.pending) {
        await _syncQueue.enqueueUpdate(
          dateKey,
          driveFileId: existing.driveFileId,
          authorizedEmail: existing.authorizedEmail,
        );
      }
    }

    _entries[dateKey] = updated;
    notifyListeners();
    return updated;
  }

  /// Updates synchronization metadata for an existing photo entry.
  ///
  /// Used by future synchronization engines (Milestone 17/18/19) to mark
  /// photos as synced (with remote IDs) or failed (with concise error descriptions).
  Future<PhotoEntry> updateSyncStatus({
    required DateKey dateKey,
    required SyncStatus status,
    String? driveFileId,
    String? driveFileRevision,
    String? syncError,
    String? authorizedEmail,
  }) {
    return _runSequential(() async {
      final existing = _entries[dateKey];
      if (existing == null) {
        throw StateError('No photo entry found for date key $dateKey');
      }

      final updated = existing.copyWith(
        syncStatus: status,
        driveFileId: driveFileId ?? existing.driveFileId,
        driveFileRevision: driveFileRevision ?? existing.driveFileRevision,
        syncError: syncError,
        authorizedEmail: authorizedEmail ?? existing.authorizedEmail,
        clearSyncError: syncError == null && status != SyncStatus.failed,
      );

      final tentative = Map<DateKey, PhotoEntry>.from(_entries);
      tentative[dateKey] = updated;

      if (_isInitialized) {
        await _metadataStorage.saveAll(tentative);
        if (status == SyncStatus.synced) {
          await _syncQueue.removeOperationsForDate(dateKey);
        } else if (status == SyncStatus.failed) {
          final op = _syncQueue.getOperationForDate(dateKey);
          if (op != null) {
            await _syncQueue.markFailed(
              op.id,
              error: syncError ?? 'Sync failed',
            );
          }
        }
      }

      _entries[dateKey] = updated;
      notifyListeners();
      return updated;
    });
  }

  @override
  void setPhoto(PhotoEntry entry) {
    final key = entry.dateKey;
    final oldEntry = _entries[key];

    _entries[key] = entry;
    notifyListeners();

    // Trigger async background persistence with rollback on failure
    if (_isInitialized) {
      _runSequential(() async {
        final tentative = Map<DateKey, PhotoEntry>.from(_entries);
        await _metadataStorage.saveAll(tentative);
        if (oldEntry != null &&
            oldEntry.hasRealImage &&
            oldEntry.imagePath != entry.imagePath) {
          await _fileManager.deletePhotoFile(oldEntry.imagePath);
        }
        if (entry.syncStatus == SyncStatus.pending) {
          if (entry.driveFileId != null) {
            await _syncQueue.enqueueUpdate(
              key,
              driveFileId: entry.driveFileId,
              authorizedEmail: entry.authorizedEmail,
            );
          } else {
            await _syncQueue.enqueueUpload(
              key,
              authorizedEmail: entry.authorizedEmail,
            );
          }
        } else if (entry.syncStatus == SyncStatus.synced) {
          await _syncQueue.removeOperationsForDate(key);
        }
      }).catchError((e) {
        debugPrint('Background metadata save error, rolling back: $e');
        if (oldEntry != null) {
          _entries[key] = oldEntry;
        } else {
          _entries.remove(key);
        }
        notifyListeners();
      });
    }
  }

  /// Convenience replacement method for a specific date.
  Future<PhotoEntry> replacePhotoAsync(
    DateTime date,
    PhotoEntry newEntry, {
    String? sourceTempPath,
  }) async {
    return savePhoto(
      entry: newEntry.copyWith(date: date),
      sourceTempPath: sourceTempPath,
    );
  }

  @override
  void removePhoto(DateTime date) {
    removePhotoByKey(DateKey.fromDateTime(date));
  }

  @override
  void removePhotoByKey(DateKey key) {
    final oldEntry = _entries[key];
    if (oldEntry == null) return;

    _entries.remove(key);
    notifyListeners();

    if (_isInitialized) {
      _runSequential(() async {
        final tentative = Map<DateKey, PhotoEntry>.from(_entries);
        await _metadataStorage.saveAll(tentative);
        if (oldEntry.hasRealImage) {
          await _fileManager.deletePhotoFile(oldEntry.imagePath);
        }

        // If the photo had a remote Google Drive copy, record a tombstone and queue remote delete
        if (oldEntry.driveFileId != null) {
          final tombstone = SyncTombstone(
            dateKey: key,
            driveFileId: oldEntry.driveFileId!,
            deletedAt: DateTime.now().toUtc(),
            authorizedEmail: oldEntry.authorizedEmail,
          );
          _pendingDeletions.add(tombstone);
          await _metadataStorage.savePendingDeletions(_pendingDeletions);
          await _syncQueue.enqueueDelete(
            key,
            driveFileId: oldEntry.driveFileId!,
            authorizedEmail: oldEntry.authorizedEmail,
          );
        } else {
          // Never synced local-only photo: prune any unexecuted upload/update
          await _syncQueue.removeOperationsForDate(key);
        }
      }).catchError((e) {
        debugPrint(
          'Background metadata save after remove error, rolling back: $e',
        );
        _entries[key] = oldEntry;
        notifyListeners();
      });
    }
  }

  /// Asynchronously removes a photo, awaiting metadata update, file deletion,
  /// and recording a [SyncTombstone] if the photo had a remote [driveFileId].
  ///
  /// Safe and idempotent: if no photo exists for [date], this is a clean no-op.
  Future<void> removePhotoAsync(DateTime date) {
    return _runSequential(() => _removePhotoAsyncInternal(date));
  }

  Future<void> _removePhotoAsyncInternal(DateTime date) async {
    final key = DateKey.fromDateTime(date);
    final oldEntry = _entries[key];
    if (oldEntry == null) {
      // Idempotent: nothing to remove
      return;
    }

    final tentative = Map<DateKey, PhotoEntry>.from(_entries);
    tentative.remove(key);

    if (_isInitialized) {
      await _metadataStorage.saveAll(tentative);
      if (oldEntry.hasRealImage) {
        await _fileManager.deletePhotoFile(oldEntry.imagePath);
      }

      // If the photo had a remote Google Drive copy, record a tombstone and queue remote delete
      if (oldEntry.driveFileId != null) {
        final tombstone = SyncTombstone(
          dateKey: key,
          driveFileId: oldEntry.driveFileId!,
          deletedAt: DateTime.now().toUtc(),
          authorizedEmail: oldEntry.authorizedEmail,
        );
        _pendingDeletions.add(tombstone);
        await _metadataStorage.savePendingDeletions(_pendingDeletions);
        await _syncQueue.enqueueDelete(
          key,
          driveFileId: oldEntry.driveFileId!,
          authorizedEmail: oldEntry.authorizedEmail,
        );
      } else {
        // Never synced local-only photo: prune any unexecuted upload/update
        await _syncQueue.removeOperationsForDate(key);
      }
    }

    _entries.remove(key);
    notifyListeners();
  }

  /// Acknowledges and clears a pending cloud deletion tombstone once the remote
  /// file has been deleted in Google Drive. Also removes the corresponding delete
  /// operation from the sync outbox queue.
  Future<void> acknowledgePendingDeletion(String driveFileId) {
    return _runSequential(() async {
      _pendingDeletions.removeWhere((t) => t.driveFileId == driveFileId);
      if (_isInitialized) {
        await _metadataStorage.savePendingDeletions(_pendingDeletions);
        SyncOperation? deleteOp;
        for (final op in _syncQueue.operations) {
          if (op.type == SyncOperationType.delete &&
              op.driveFileId == driveFileId) {
            deleteOp = op;
            break;
          }
        }
        if (deleteOp != null) {
          await _syncQueue.markCompleted(deleteOp.id);
        }
      }
    });
  }

  /// Clears all pending deletion tombstones from disk and memory.
  Future<void> clearPendingDeletions() {
    return _runSequential(() async {
      _pendingDeletions.clear();
      if (_isInitialized) {
        await _metadataStorage.clearPendingDeletions();
      }
    });
  }

  /// Reconciles local photo files on disk against the metadata registry.
  ///
  /// Identifies and safely deletes app-managed photo files that are no longer
  /// referenced by any active photo entry in metadata.
  /// Returns the list of pruned file paths.
  Future<List<String>> reconcileOrphanFiles() async {
    if (!_isInitialized) return [];

    try {
      final referencedPaths = _entries.values
          .where((entry) => entry.hasRealImage)
          .map((entry) => entry.imagePath!)
          .toSet();

      return await _fileManager.pruneUnreferencedPhotos(referencedPaths);
    } catch (e) {
      debugPrint('reconcileOrphanFiles encountered non-critical error: $e');
      return [];
    }
  }

  @override
  void clear() {
    _entries.clear();
    _pendingDeletions.clear();
    notifyListeners();
    if (_isInitialized) {
      _runSequential(() async {
        await _metadataStorage.clear();
        await _fileManager.clearAll();
        await _syncQueue.clear();
      }).catchError((e) {
        debugPrint('Clear storage error: $e');
      });
    }
  }

  /// Asynchronously clears all photo entries, pending deletions, and photo files.
  Future<void> clearAsync() {
    return _runSequential(() async {
      _entries.clear();
      _pendingDeletions.clear();
      if (_isInitialized) {
        await _metadataStorage.clear();
        await _fileManager.clearAll();
        await _syncQueue.clear();
      }
      notifyListeners();
    });
  }
}
