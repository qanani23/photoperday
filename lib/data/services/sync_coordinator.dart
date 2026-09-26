import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:photo_per_day/data/models/auth_status.dart';
import 'package:photo_per_day/data/models/drive_auth_status.dart';
import 'package:photo_per_day/data/models/sync_operation_status.dart';
import 'package:photo_per_day/data/models/sync_run_result.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/sync_queue.dart';
import 'package:photo_per_day/data/services/sync_worker.dart';

/// Identification of the source or event that prompted a synchronization request.
enum SyncTrigger {
  /// The application returned to the foreground from a background/inactive state.
  foreground,

  /// The user successfully authenticated with Google.
  signIn,

  /// Google Drive scope authorization became active.
  driveAuthorization,

  /// Google Drive root folder ("Photo a Day") setup completed.
  folderReady,

  /// A photo was captured, selected, replaced, edited, or deleted (debounced).
  photoChange,

  /// An active exponential backoff timer expired.
  retryTimer,

  /// Explicit user tap on the "Sync Now" button in the Profile screen.
  manual,

  /// Background execution window granted by the host operating system.
  background,
}

/// Abstract contract for performing lightweight network connectivity checks.
abstract class NetworkChecker {
  /// Checks whether internet connectivity to remote services is available.
  Future<bool> isConnected();
}

/// Default production network connectivity checker using lightweight DNS resolution.
///
/// Principles:
/// - Optimization only: Never treated as absolute source of truth.
/// - Zero third-party packages: Uses native [InternetAddress.lookup] to Google API domains.
/// - Fast timeout: 2-second timeout to avoid UI blocking.
class DefaultNetworkChecker implements NetworkChecker {
  const DefaultNetworkChecker({
    this.host = 'www.googleapis.com',
    this.timeout = const Duration(seconds: 2),
  });

  final String host;
  final Duration timeout;

  @override
  Future<bool> isConnected() async {
    try {
      final addresses = await InternetAddress.lookup(host).timeout(timeout);
      return addresses.isNotEmpty && addresses.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

/// Abstract contract for background synchronization scheduling on mobile operating systems.
abstract class BackgroundSyncScheduler {
  /// Requests a background execution opportunity when pending work exists.
  Future<void> scheduleBackgroundSync();

  /// Cancels any scheduled background execution jobs.
  Future<void> cancelBackgroundSync();

  /// Whether true background task scheduling is supported by the current runtime.
  bool get isSupported;
}

/// Default conservative background sync scheduler.
///
/// Analysis of Mobile OS Restrictions:
/// - Android: Headless background execution (e.g. via WorkManager in a separate Flutter isolate)
///   requires an active Android Activity to retrieve authenticated headers via the Google Sign-In SDK (v6.2.2).
///   In a headless isolate, `GoogleSignIn.currentUser` is null or throws, making token retrieval impossible.
///   Furthermore, multi-isolate concurrent access to `sync_queue.json` without OS-level locks risks file corruption.
/// - iOS: `BGTaskScheduler` similarly requires background refresh entitlements and cannot refresh interactive
///   OAuth sessions without user interaction.
///
/// Therefore, automatic sync safely executes on foreground resume, auth events, and debounced photo changes
/// within the main application isolate, while providing this extensible seam for future native schedulers.
class DefaultBackgroundSyncScheduler implements BackgroundSyncScheduler {
  const DefaultBackgroundSyncScheduler();

  @override
  bool get isSupported => false;

  @override
  Future<void> scheduleBackgroundSync() async {}

  @override
  Future<void> cancelBackgroundSync() async {}
}

/// Orchestrator service responsible for automatic synchronization scheduling.
///
/// Architecture & Guarantees:
/// - Reuses [SyncWorker.instance.syncNow()]: Never creates a second sync engine.
/// - Triggers:
///   1. App returns to foreground (lifecycle resume)
///   2. User successfully signs in
///   3. Google Drive authorization becomes available
///   4. Google Drive folder becomes ready
///   5. Photo mutations (capture, gallery selection, edit, delete) with debouncing
///   6. Expiration of exponential retry backoff timers
/// - Debounce & Coalescing: Multiple rapid photo changes within [debounceDuration] result in exactly one sync.
/// - Duplicate Execution Protection: Guards against simultaneous foreground, background, and manual sync requests.
/// - Backoff Awareness: Respects [SyncOperation.nextAttemptAt]; never creates a busy polling loop.
/// - Offline Preservation: Local photo operations never depend on network; offline deferral preserves queue.
/// - Sign-Out Safety: Stops scheduling and cancels all active timers upon sign-out.
class SyncCoordinator with ChangeNotifier, WidgetsBindingObserver {
  SyncCoordinator({
    SyncWorker? worker,
    SyncQueue? queue,
    GoogleAuthService? authService,
    GoogleDriveAuthService? driveAuthService,
    GoogleDriveService? driveService,
    NetworkChecker? networkChecker,
    BackgroundSyncScheduler? backgroundScheduler,
    this.debounceDuration = const Duration(milliseconds: 2500),
  }) : _injectedWorker = worker,
       _injectedQueue = queue,
       _injectedAuthService = authService,
       _injectedDriveAuthService = driveAuthService,
       _injectedDriveService = driveService,
       _networkChecker = networkChecker ?? const DefaultNetworkChecker(),
       _backgroundScheduler =
           backgroundScheduler ?? const DefaultBackgroundSyncScheduler();

  static SyncCoordinator? _instance;

  /// The active singleton instance.
  static SyncCoordinator get instance => _instance ??= SyncCoordinator();

  @visibleForTesting
  static void setTestInstance(SyncCoordinator coordinator) {
    _instance = coordinator;
  }

  @visibleForTesting
  static void resetInstance() {
    if (_instance != null) {
      final old = _instance;
      _instance = null;
      old?.dispose();
    }
  }

  final SyncWorker? _injectedWorker;
  final SyncQueue? _injectedQueue;
  final GoogleAuthService? _injectedAuthService;
  final GoogleDriveAuthService? _injectedDriveAuthService;
  final GoogleDriveService? _injectedDriveService;
  final NetworkChecker _networkChecker;
  final BackgroundSyncScheduler _backgroundScheduler;
  final Duration debounceDuration;

  SyncWorker get _worker => _injectedWorker ?? SyncWorker.instance;
  SyncQueue get _queue =>
      _injectedQueue ?? PersistentDailyPhotoStore.instance.syncQueue;
  GoogleAuthService get _auth =>
      _injectedAuthService ?? GoogleAuthService.instance;
  GoogleDriveAuthService get _driveAuth =>
      _injectedDriveAuthService ?? GoogleDriveAuthService.instance;
  GoogleDriveService get _drive =>
      _injectedDriveService ?? GoogleDriveService.instance;

  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isRequestingSync = false;
  bool _isPaused = false;
  bool _wasInBackground = false;

  Timer? _debounceTimer;
  Timer? _retryTimer;

  DateTime? _lastSyncAttemptAt;
  DateTime? _lastSyncSuccessAt;
  String? _lastSyncError;

  AuthStatus _lastAuthStatus = AuthStatus.signedOut;
  DriveAuthStatus _lastDriveAuthStatus = DriveAuthStatus.notAuthorized;
  bool _lastDriveReady = false;

  /// Whether the coordinator has finished initialization and registered listeners.
  bool get isInitialized => _isInitialized;

  /// Whether a sync operation is currently in flight (either requested here or in worker).
  bool get isSyncing => _isRequestingSync || _worker.isSyncing;

  /// Whether a photo change is actively debouncing before dispatching sync.
  bool get isDebouncing => _debounceTimer != null && _debounceTimer!.isActive;

  /// Timestamp of the most recent sync attempt.
  DateTime? get lastSyncAttemptAt => _lastSyncAttemptAt;

  /// Timestamp of the most recent fully successful sync run.
  DateTime? get lastSyncSuccessAt => _lastSyncSuccessAt;

  /// Error message from the most recent sync run, if any.
  String? get lastSyncError => _lastSyncError;

  /// Whether automatic sync is currently paused.
  bool get isPaused => _isPaused;

  /// Underlying network checker.
  NetworkChecker get networkChecker => _networkChecker;

  /// Underlying background scheduler.
  BackgroundSyncScheduler get backgroundScheduler => _backgroundScheduler;

  /// Evaluates whether all preconditions are met to execute a sync immediately.
  bool get canSyncNow {
    if (!_auth.isSignedIn) return false;
    if (!_driveAuth.isAuthorized) return false;
    if (!_drive.isReady) return false;
    if (_queue.pendingOperations.isEmpty) return false;

    // Check if at least one pending operation is eligible (not in active backoff)
    final now = DateTime.now().toUtc();
    return _queue.pendingOperations.any((op) {
      if (op.status != SyncOperationStatus.failed) return true;
      if (op.nextAttemptAt == null) return true;
      return !op.nextAttemptAt!.isAfter(now);
    });
  }

  /// Calculates the earliest timestamp among all operations in active backoff.
  DateTime? get earliestRetryTime {
    DateTime? earliest;
    for (final op in _queue.pendingOperations) {
      if (op.status == SyncOperationStatus.failed && op.nextAttemptAt != null) {
        if (earliest == null || op.nextAttemptAt!.isBefore(earliest)) {
          earliest = op.nextAttemptAt;
        }
      }
    }
    return earliest;
  }

  /// Initializes the coordinator, observes app lifecycle, and registers service listeners.
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // In non-widget unit tests, WidgetsBinding may not be attached.
    }

    _auth.addListener(_onAuthChanged);
    _driveAuth.addListener(_onDriveAuthChanged);
    _drive.addListener(_onDriveChanged);
    _queue.addListener(_onQueueChanged);
    _worker.addListener(_onWorkerChanged);

    _lastAuthStatus = _auth.status;
    _lastDriveAuthStatus = _driveAuth.status;
    _lastDriveReady = _drive.isReady;

    _isInitialized = true;
    notifyListeners();
  }

  /// Pauses automatic sync scheduling.
  void pause() {
    _isPaused = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    notifyListeners();
  }

  /// Resumes automatic sync scheduling and evaluates pending operations.
  void resume() {
    _isPaused = false;
    notifyListeners();
    if (canSyncNow) {
      scheduleAutoSync(delay: Duration.zero, trigger: SyncTrigger.foreground);
    } else {
      _scheduleRetryTimerIfNeeded();
    }
  }

  /// Schedules an automatic sync run after a debounced [delay].
  ///
  /// Coalescing: Calling this multiple times before [delay] expires resets the timer
  /// so only one sync attempt is executed for the entire burst of changes.
  void scheduleAutoSync({
    Duration? delay,
    SyncTrigger trigger = SyncTrigger.photoChange,
  }) {
    if (_isDisposed || _isPaused) return;

    if (!_auth.isSignedIn || !_driveAuth.isAuthorized || !_drive.isReady) {
      return;
    }

    if (_queue.pendingOperations.isEmpty) {
      return;
    }

    _debounceTimer?.cancel();
    final effectiveDelay = delay ?? debounceDuration;

    if (effectiveDelay <= Duration.zero) {
      requestSync(trigger: trigger);
    } else {
      _debounceTimer = Timer(effectiveDelay, () {
        if (!_isDisposed && !_isPaused) {
          requestSync(trigger: trigger);
        }
      });
      notifyListeners();
    }
  }

  /// Evaluates preconditions, checks backoff, probes network connectivity,
  /// and requests execution of [SyncWorker.syncNow].
  Future<SyncRunResult> requestSync({required SyncTrigger trigger}) async {
    if (_isDisposed) {
      return SyncRunResult.empty();
    }

    // 1. Concurrency guard: Only ONE synchronization run may be active at any time.
    if (_isRequestingSync || _worker.isSyncing) {
      return SyncRunResult.alreadyRunning(remainingCount: _queue.count);
    }

    _isRequestingSync = true;
    _lastSyncAttemptAt = DateTime.now().toUtc();
    notifyListeners();

    try {
      // 2. Precondition: Google Sign-In
      if (!_auth.isSignedIn) {
        return SyncRunResult.notSignedIn(remainingCount: _queue.count);
      }

      // 3. Precondition: Google Drive Authorization
      if (!_driveAuth.isAuthorized) {
        return SyncRunResult.notAuthorized(remainingCount: _queue.count);
      }

      // 4. Precondition: Google Drive Folder Readiness
      if (!_drive.isReady || _drive.currentFolder?.folderId == null) {
        return SyncRunResult.folderNotReady(remainingCount: _queue.count);
      }

      // 5. Precondition: Queue has pending work
      if (_queue.isEmpty || _queue.pendingOperations.isEmpty) {
        return SyncRunResult.empty();
      }

      // 6. Precondition: Backoff awareness
      final now = DateTime.now().toUtc();
      final hasEligibleOp = _queue.pendingOperations.any((op) {
        if (op.status != SyncOperationStatus.failed) return true;
        if (op.nextAttemptAt == null) return true;
        return !op.nextAttemptAt!.isAfter(now);
      });

      if (!hasEligibleOp) {
        _scheduleRetryTimerIfNeeded();
        return SyncRunResult(
          processedCount: 0,
          uploadedCount: 0,
          updatedCount: 0,
          deletedCount: 0,
          failedCount: 0,
          skippedCount: _queue.count,
          unsupportedCount: 0,
          remainingCount: _queue.count,
        );
      }

      // 7. Network awareness probe: Defer sync if device is offline
      final isOnline = await _networkChecker.isConnected();
      if (!isOnline) {
        debugPrint(
          'Sync deferred: network connectivity probe failed (offline).',
        );
        return SyncRunResult(
          processedCount: 0,
          uploadedCount: 0,
          updatedCount: 0,
          deletedCount: 0,
          failedCount: 0,
          skippedCount: _queue.count,
          unsupportedCount: 0,
          remainingCount: _queue.count,
        );
      }

      final result = await _worker.syncNow();

      if (result.processedCount > 0 && result.failedCount == 0) {
        _lastSyncSuccessAt = DateTime.now().toUtc();
        _lastSyncError = null;
      } else if (result.failedCount > 0) {
        _lastSyncError = 'One or more items failed to synchronize';
        _scheduleRetryTimerIfNeeded();
      }

      return result;
    } catch (e) {
      _lastSyncError = e.toString();
      _scheduleRetryTimerIfNeeded();
      return SyncRunResult(
        processedCount: 0,
        uploadedCount: 0,
        updatedCount: 0,
        deletedCount: 0,
        failedCount: 1,
        skippedCount: 0,
        unsupportedCount: 0,
        remainingCount: _queue.count,
      );
    } finally {
      _isRequestingSync = false;
      notifyListeners();
    }
  }

  /// App lifecycle observer callback.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed || !_isInitialized || _isPaused) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _wasInBackground = true;
        break;

      case AppLifecycleState.resumed:
        if (_wasInBackground) {
          _wasInBackground = false;
          if (canSyncNow) {
            requestSync(trigger: SyncTrigger.foreground);
          }
        }
        break;

      case AppLifecycleState.detached:
        break;
    }
  }

  /// Handles foreground trigger directly (useful for tests and manual lifecycle simulation).
  Future<SyncRunResult> onAppForegrounded() async {
    if (_isDisposed || _isPaused) return SyncRunResult.empty();
    if (canSyncNow) {
      return await requestSync(trigger: SyncTrigger.foreground);
    }
    return SyncRunResult.empty();
  }

  void _onQueueChanged() {
    if (_isDisposed || !_isInitialized || _isPaused) return;

    final pending = _queue.pendingOperations;
    if (pending.isEmpty) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _retryTimer?.cancel();
      _retryTimer = null;
      notifyListeners();
      return;
    }

    final hasPendingReady = pending.any(
      (op) => op.status == SyncOperationStatus.pending,
    );

    if (hasPendingReady) {
      scheduleAutoSync(trigger: SyncTrigger.photoChange);
    } else {
      _scheduleRetryTimerIfNeeded();
    }
  }

  void _onWorkerChanged() {
    if (_isDisposed || !_isInitialized || _isPaused) return;

    // If worker completed and pending operations remain, schedule a follow-up run
    if (!_worker.isSyncing &&
        _queue.pendingOperations.isNotEmpty &&
        canSyncNow) {
      scheduleAutoSync(
        delay: const Duration(seconds: 1),
        trigger: SyncTrigger.photoChange,
      );
    }
  }

  void _onAuthChanged() {
    if (_isDisposed || !_isInitialized) return;

    final currentStatus = _auth.status;
    if (_lastAuthStatus != AuthStatus.signedIn &&
        currentStatus == AuthStatus.signedIn) {
      if (_driveAuth.isAuthorized &&
          _drive.isReady &&
          _queue.pendingOperations.isNotEmpty) {
        scheduleAutoSync(
          delay: const Duration(milliseconds: 500),
          trigger: SyncTrigger.signIn,
        );
      }
    } else if (currentStatus == AuthStatus.signedOut) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _retryTimer?.cancel();
      _retryTimer = null;
    }
    _lastAuthStatus = currentStatus;
  }

  void _onDriveAuthChanged() {
    if (_isDisposed || !_isInitialized) return;

    final currentStatus = _driveAuth.status;
    if (_lastDriveAuthStatus != DriveAuthStatus.authorized &&
        currentStatus == DriveAuthStatus.authorized) {
      if (_auth.isSignedIn &&
          _drive.isReady &&
          _queue.pendingOperations.isNotEmpty) {
        scheduleAutoSync(
          delay: const Duration(milliseconds: 500),
          trigger: SyncTrigger.driveAuthorization,
        );
      }
    }
    _lastDriveAuthStatus = currentStatus;
  }

  void _onDriveChanged() {
    if (_isDisposed || !_isInitialized) return;

    final currentReady = _drive.isReady;
    if (!_lastDriveReady && currentReady) {
      if (_auth.isSignedIn &&
          _driveAuth.isAuthorized &&
          _queue.pendingOperations.isNotEmpty) {
        scheduleAutoSync(
          delay: const Duration(milliseconds: 500),
          trigger: SyncTrigger.folderReady,
        );
      }
    }
    _lastDriveReady = currentReady;
  }

  void _scheduleRetryTimerIfNeeded() {
    _retryTimer?.cancel();
    _retryTimer = null;

    if (_isDisposed ||
        _isPaused ||
        !_auth.isSignedIn ||
        !_driveAuth.isAuthorized) {
      return;
    }

    final earliest = earliestRetryTime;
    if (earliest == null) return;

    final now = DateTime.now().toUtc();
    final delay = earliest.difference(now);

    if (delay <= Duration.zero) {
      scheduleAutoSync(delay: Duration.zero, trigger: SyncTrigger.retryTimer);
    } else {
      _retryTimer = Timer(delay, () {
        if (!_isDisposed && !_isPaused) {
          requestSync(trigger: SyncTrigger.retryTimer);
        }
      });
    }
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;

    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}

    _auth.removeListener(_onAuthChanged);
    _driveAuth.removeListener(_onDriveAuthChanged);
    _drive.removeListener(_onDriveChanged);
    _queue.removeListener(_onQueueChanged);
    _worker.removeListener(_onWorkerChanged);

    super.dispose();
  }
}
