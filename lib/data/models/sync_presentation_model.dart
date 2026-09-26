import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_operation_status.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/sync_queue.dart';
import 'package:photo_per_day/data/services/sync_worker.dart';

/// User-facing presentation state for a photo memory's cloud-backup lifecycle.
enum PhotoSyncDisplayState {
  /// Photo is saved locally on device only and has not been queued or uploaded.
  localOnly,

  /// Photo has pending local changes awaiting upload or update.
  pending,

  /// Photo is currently actively transferring bytes to Google Drive.
  backingUp,

  /// Photo is confirmed and fully synchronized with Google Drive.
  synced,

  /// Previous synchronization attempt failed; local photo remains safe on device.
  failed,
}

/// Rich UI presentation model representing a photo's sync status with user-facing labels,
/// icons, colors, and semantic accessibility descriptions.
class PhotoSyncPresentation {
  const PhotoSyncPresentation({
    required this.state,
    required this.label,
    required this.detailLabel,
    required this.semanticLabel,
    required this.icon,
    required this.color,
  });

  /// The high-level display state.
  final PhotoSyncDisplayState state;

  /// Short concise label suitable for badges and calendar tooltips (e.g. "Backed up").
  final String label;

  /// Detailed descriptive label suitable for photo detail view (e.g. "Backed up to Google Drive").
  final String detailLabel;

  /// Full accessibility screen-reader label (e.g. "Photo backed up to Google Drive").
  final String semanticLabel;

  /// Representational icon matching the design system.
  final IconData icon;

  /// The accent color associated with this state.
  final Color color;

  /// Whether this state indicates an active in-flight transfer.
  bool get isBackingUp => state == PhotoSyncDisplayState.backingUp;

  /// Whether this state indicates a failure requiring user retry.
  bool get isFailed => state == PhotoSyncDisplayState.failed;

  /// Resolves the user-facing presentation for a given [PhotoEntry].
  ///
  /// Inspects [SyncWorker.instance] to check if this photo is actively being
  /// processed, falling back to [entry.syncStatus].
  static PhotoSyncPresentation forEntry(
    PhotoEntry entry, {
    bool? isSyncing,
    SyncWorker? worker,
  }) {
    final activeWorker = worker ?? SyncWorker.instance;
    final activelySyncing =
        isSyncing ??
        (activeWorker.isSyncing && activeWorker.activeDateKey == entry.dateKey);

    if (activelySyncing) {
      return const PhotoSyncPresentation(
        state: PhotoSyncDisplayState.backingUp,
        label: 'Backing up...',
        detailLabel: 'Backing up to Google Drive...',
        semanticLabel: 'Photo backup in progress',
        icon: Icons.cloud_sync_rounded,
        color: AppColors.accent,
      );
    }

    switch (entry.syncStatus) {
      case SyncStatus.localOnly:
        return const PhotoSyncPresentation(
          state: PhotoSyncDisplayState.localOnly,
          label: 'On this device',
          detailLabel: 'On this device',
          semanticLabel: 'Photo stored on this device only',
          icon: Icons.phone_iphone_rounded,
          color: AppColors.textMuted,
        );

      case SyncStatus.pending:
        return const PhotoSyncPresentation(
          state: PhotoSyncDisplayState.pending,
          label: 'Waiting to back up',
          detailLabel: 'Waiting to back up',
          semanticLabel: 'Photo waiting to be backed up',
          icon: Icons.schedule_rounded,
          color: AppColors.accent,
        );

      case SyncStatus.synced:
        return const PhotoSyncPresentation(
          state: PhotoSyncDisplayState.synced,
          label: 'Backed up',
          detailLabel: 'Backed up to Google Drive',
          semanticLabel: 'Photo backed up to Google Drive',
          icon: Icons.cloud_done_rounded,
          color: AppColors.statDaysGreen,
        );

      case SyncStatus.failed:
        return const PhotoSyncPresentation(
          state: PhotoSyncDisplayState.failed,
          label: 'Backup failed',
          detailLabel: 'Backup failed',
          semanticLabel: 'Photo backup failed',
          icon: Icons.error_outline_rounded,
          color: AppColors.error,
        );
    }
  }

  /// Maps a raw [SyncStatus] directly to its baseline presentation when no active worker is attached.
  static PhotoSyncPresentation fromStatus(SyncStatus status) {
    switch (status) {
      case SyncStatus.localOnly:
        return const PhotoSyncPresentation(
          state: PhotoSyncDisplayState.localOnly,
          label: 'On this device',
          detailLabel: 'On this device',
          semanticLabel: 'Photo stored on this device only',
          icon: Icons.phone_iphone_rounded,
          color: AppColors.textMuted,
        );
      case SyncStatus.pending:
        return const PhotoSyncPresentation(
          state: PhotoSyncDisplayState.pending,
          label: 'Waiting to back up',
          detailLabel: 'Waiting to back up',
          semanticLabel: 'Photo waiting to be backed up',
          icon: Icons.schedule_rounded,
          color: AppColors.accent,
        );
      case SyncStatus.synced:
        return const PhotoSyncPresentation(
          state: PhotoSyncDisplayState.synced,
          label: 'Backed up',
          detailLabel: 'Backed up to Google Drive',
          semanticLabel: 'Photo backed up to Google Drive',
          icon: Icons.cloud_done_rounded,
          color: AppColors.statDaysGreen,
        );
      case SyncStatus.failed:
        return const PhotoSyncPresentation(
          state: PhotoSyncDisplayState.failed,
          label: 'Backup failed',
          detailLabel: 'Backup failed',
          semanticLabel: 'Photo backup failed',
          icon: Icons.error_outline_rounded,
          color: AppColors.error,
        );
    }
  }
}

/// Derived aggregate summary of synchronization and outbox state.
///
/// Principles:
/// - Derived state ONLY: Never persists or caches redundant records.
/// - Authoritative: Directly evaluates [PersistentDailyPhotoStore] and [SyncQueue].
/// - Account Safe: Verifies account attribution before declaring a photo backed up.
/// - Queue Accurate: Does not confuse completed historical ops with pending work.
class SyncSummary {
  const SyncSummary({
    required this.totalPhotos,
    required this.backedUpCount,
    required this.waitingCount,
    required this.failedCount,
    required this.localOnlyCount,
    required this.pendingQueueCount,
    required this.isUpToDate,
  });

  /// Total count of photo entries managed on device.
  final int totalPhotos;

  /// Count of photos confirmed backed up to the current authorized Google account.
  final int backedUpCount;

  /// Count of photos with local changes waiting to be backed up.
  final int waitingCount;

  /// Count of photos whose last backup attempt failed.
  final int failedCount;

  /// Count of photos that exist on this device only and have not been queued.
  final int localOnlyCount;

  /// Actual number of pending or retrying operations currently in the SyncQueue.
  final int pendingQueueCount;

  /// Whether all photos are fully backed up and the sync queue has zero pending or failed operations.
  final bool isUpToDate;

  /// Computes a fresh [SyncSummary] from the provided [store] and [queue].
  ///
  /// If [currentAccountEmail] is supplied, only photos backed up to that specific
  /// account are counted as [backedUpCount] to maintain account-switch safety.
  static SyncSummary compute({
    required PersistentDailyPhotoStore store,
    required SyncQueue queue,
    String? currentAccountEmail,
  }) {
    final entries = store.allEntries;
    final total = entries.length;

    int backedUp = 0;
    int waiting = 0;
    int failed = 0;
    int localOnly = 0;

    // Build a map of pending operations by DateKey from the actual SyncQueue
    final pendingOps = queue.pendingOperations;
    final pendingByDateKey = <DateKey, List<SyncOperationStatus>>{};
    for (final op in pendingOps) {
      pendingByDateKey.putIfAbsent(op.dateKey, () => []).add(op.status);
    }

    for (final entry in entries) {
      final opStatuses = pendingByDateKey[entry.dateKey];
      final hasFailedOp =
          opStatuses != null && opStatuses.contains(SyncOperationStatus.failed);
      final hasPendingOp =
          opStatuses != null &&
          opStatuses.contains(SyncOperationStatus.pending);

      if (entry.syncStatus == SyncStatus.failed || hasFailedOp) {
        failed++;
      } else if (entry.syncStatus == SyncStatus.pending || hasPendingOp) {
        waiting++;
      } else if (entry.syncStatus == SyncStatus.synced) {
        // Milestone 24 Account Safety: If signed in, only count as backed up if
        // attribution matches current account.
        if (currentAccountEmail != null &&
            entry.authorizedEmail != null &&
            entry.authorizedEmail != currentAccountEmail) {
          // Attributed to another user account -> treated as local/unbacked up for current user
          localOnly++;
        } else {
          backedUp++;
        }
      } else {
        localOnly++;
      }
    }

    final totalPendingQueue = queue.pendingOperations.length;

    // Up to date requires:
    // 1. Zero pending operations in the SyncQueue
    // 2. Zero failed photos
    // 3. Zero waiting photos
    // 4. At least one photo exists and all photos are synced (or no photos exist)
    final upToDate =
        totalPendingQueue == 0 &&
        failed == 0 &&
        waiting == 0 &&
        (total == 0 || (backedUp == total && localOnly == 0));

    return SyncSummary(
      totalPhotos: total,
      backedUpCount: backedUp,
      waitingCount: waiting,
      failedCount: failed,
      localOnlyCount: localOnly,
      pendingQueueCount: totalPendingQueue,
      isUpToDate: upToDate,
    );
  }
}
