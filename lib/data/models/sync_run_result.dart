import 'package:flutter/foundation.dart';

/// Non-sensitive result model representing the outcome of a manual synchronization run.
///
/// Encapsulates operation counters and precondition states without containing
/// any OAuth tokens, credentials, or sensitive network headers.
@immutable
class SyncRunResult {
  const SyncRunResult({
    this.processedCount = 0,
    int? succeededCount,
    this.uploadedCount = 0,
    this.updatedCount = 0,
    this.deletedCount = 0,
    this.failedCount = 0,
    this.skippedCount = 0,
    this.unsupportedCount = 0,
    this.remainingCount = 0,
    this.alreadyRunning = false,
    this.notSignedIn = false,
    this.notAuthorized = false,
    this.folderNotReady = false,
    this.errorMessage,
  }) : succeededCount =
           succeededCount ?? (uploadedCount + updatedCount + deletedCount);

  /// The number of queued operations evaluated and attempted in this run.
  final int processedCount;

  /// The total number of operations successfully completed or acknowledged.
  final int succeededCount;

  /// The number of photo upload operations successfully completed.
  final int uploadedCount;

  /// The number of photo update operations successfully completed.
  final int updatedCount;

  /// The number of photo delete operations successfully completed.
  final int deletedCount;

  /// The number of operations that failed due to missing local files or API errors.
  final int failedCount;

  /// The number of operations skipped due to active retry backoff (`nextAttemptAt > now`).
  final int skippedCount;

  /// The number of operations skipped because their type (update, delete) is not yet supported.
  final int unsupportedCount;

  /// The total number of operations remaining in the queue after this run.
  final int remainingCount;

  /// Whether the run was aborted because another sync operation was already in flight.
  final bool alreadyRunning;

  /// Whether the run was aborted because the user is not signed in to Google.
  final bool notSignedIn;

  /// Whether the run was aborted because Google Drive authorization has not been granted.
  final bool notAuthorized;

  /// Whether the run was aborted because the "Photo a Day" Drive folder is not ready.
  final bool folderNotReady;

  /// Concise error description if the run failed or was aborted.
  final String? errorMessage;

  /// Clean empty outcome when the queue has no operations to process.
  factory SyncRunResult.empty() => const SyncRunResult(
    processedCount: 0,
    succeededCount: 0,
    failedCount: 0,
    skippedCount: 0,
    unsupportedCount: 0,
    remainingCount: 0,
  );

  /// Result when a second concurrent `syncNow()` call is rejected by the in-flight lock.
  factory SyncRunResult.alreadyRunning({int remainingCount = 0}) =>
      SyncRunResult(
        alreadyRunning: true,
        remainingCount: remainingCount,
        errorMessage: 'Synchronization is already in progress.',
      );

  /// Result when Google Sign-In is required.
  factory SyncRunResult.notSignedIn({int remainingCount = 0}) => SyncRunResult(
    notSignedIn: true,
    remainingCount: remainingCount,
    errorMessage: 'Google account sign-in required to sync photo memories.',
  );

  /// Result when Google Drive scope authorization is required.
  factory SyncRunResult.notAuthorized({int remainingCount = 0}) =>
      SyncRunResult(
        notAuthorized: true,
        remainingCount: remainingCount,
        errorMessage:
            'Google Drive authorization required to sync photo memories.',
      );

  /// Result when the "Photo a Day" Drive folder has not yet been resolved.
  factory SyncRunResult.folderNotReady({int remainingCount = 0}) =>
      SyncRunResult(
        folderNotReady: true,
        remainingCount: remainingCount,
        errorMessage:
            'Google Drive folder "Photo a Day" must be set up before syncing.',
      );

  /// Whether the run completed without any operational or precondition failures.
  bool get isSuccess =>
      !alreadyRunning &&
      !notSignedIn &&
      !notAuthorized &&
      !folderNotReady &&
      failedCount == 0;

  /// Whether any operations failed during this synchronization run.
  bool get hasFailures => failedCount > 0;

  /// Whether any precondition (auth, scope, folder) prevented the run.
  bool get isPreconditionFailure =>
      notSignedIn || notAuthorized || folderNotReady;

  /// Whether the run found nothing to sync and had no failures or in-flight locks.
  bool get isEmpty =>
      processedCount == 0 &&
      skippedCount == 0 &&
      unsupportedCount == 0 &&
      !alreadyRunning &&
      !notSignedIn &&
      !notAuthorized &&
      !folderNotReady;

  @override
  String toString() =>
      'SyncRunResult(processed: $processedCount, succeeded: $succeededCount, '
      'failed: $failedCount, skipped: $skippedCount, unsupported: $unsupportedCount, '
      'remaining: $remainingCount, alreadyRunning: $alreadyRunning, '
      'notSignedIn: $notSignedIn, notAuthorized: $notAuthorized, folderNotReady: $folderNotReady)';
}
