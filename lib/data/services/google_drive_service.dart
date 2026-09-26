import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/models/drive_auth_status.dart';
import 'package:photo_per_day/data/models/drive_folder_reference.dart';
import 'package:photo_per_day/data/models/drive_folder_result.dart';
import 'package:photo_per_day/data/models/drive_folder_status.dart';
import 'package:photo_per_day/data/services/drive_api_adapter.dart';
import 'package:photo_per_day/data/services/drive_folder_storage.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';
import 'package:photo_per_day/data/services/google_drive_auth_service.dart';

/// Orchestrates Google Drive folder discovery, creation, and state management.
///
/// Principles:
/// - Narrow focus: Deals strictly with root folder setup ("Photo a Day").
/// - Decoupled: Interacts with Google Drive exclusively through [DriveApiAdapter].
/// - Idempotent: Discovers existing folders before creating; repeated calls return the same reference.
/// - Non-sensitive: Never handles or persists access tokens or credentials.
/// - Local authority: Does NOT upload photos, does NOT consume the SyncQueue.
class GoogleDriveService extends ChangeNotifier {
  GoogleDriveService({
    DriveApiAdapter? adapter,
    DriveFolderStorage? storage,
    GoogleAuthService? authService,
    GoogleDriveAuthService? driveAuthService,
  }) : _adapter = adapter ?? const GoogleApisDriveAdapter(),
       _storage = storage ?? DriveFolderStorage(),
       _injectedAuthService = authService,
       _injectedDriveAuthService = driveAuthService;

  static const String targetFolderName = 'Photo a Day';

  static GoogleDriveService? _instance;

  /// The active singleton instance.
  static GoogleDriveService get instance {
    return _instance ??= GoogleDriveService();
  }

  @visibleForTesting
  static void setTestInstance(GoogleDriveService service) {
    _instance = service;
  }

  @visibleForTesting
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }

  final DriveApiAdapter _adapter;
  final DriveFolderStorage _storage;
  final GoogleAuthService? _injectedAuthService;
  final GoogleDriveAuthService? _injectedDriveAuthService;

  GoogleAuthService get _effectiveAuth =>
      _injectedAuthService ?? GoogleAuthService.instance;
  GoogleDriveAuthService get _effectiveDriveAuth =>
      _injectedDriveAuthService ?? GoogleDriveAuthService.instance;

  DriveFolderStatus _status = DriveFolderStatus.uninitialized;
  DriveFolderReference? _currentFolder;
  String? _errorMessage;
  bool _initialized = false;
  String? _lastKnownEmail;

  DriveFolderStatus get status => _status;
  DriveFolderReference? get currentFolder => _currentFolder;
  String? get errorMessage => _errorMessage;
  bool get isReady => _status == DriveFolderStatus.ready;
  bool get isSettingUp => _status == DriveFolderStatus.settingUp;

  /// Initializes the service and restores any locally persisted folder state.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _effectiveAuth.addListener(_onAuthChanged);
    _effectiveDriveAuth.addListener(_onDriveAuthChanged);

    await _syncWithAuthState();
  }

  Future<void> _syncWithAuthState() async {
    final currentEmail = _effectiveAuth.currentUser?.email;
    _lastKnownEmail = currentEmail;

    final stored = await _storage.loadFolderReference();

    if (_effectiveAuth.isSignedIn &&
        _effectiveDriveAuth.isAuthorized &&
        stored != null) {
      // Account safety: verify persisted folder belongs to current account
      final isMatchingAccount = currentEmail != null
          ? stored.authorizedEmail == currentEmail
          : stored.authorizedEmail == null;
      if (isMatchingAccount) {
        _currentFolder = stored;
        _status = DriveFolderStatus.ready;
        _errorMessage = null;
      } else {
        // Account mismatch: invalidate cached folder for previous account
        await _storage.clearFolderReference();
        _currentFolder = null;
        _status = DriveFolderStatus.uninitialized;
        _errorMessage = null;
      }
    } else {
      _currentFolder = null;
      _status = DriveFolderStatus.uninitialized;
      _errorMessage = null;
    }
    notifyListeners();
  }

  void _onAuthChanged() {
    final newEmail = _effectiveAuth.currentUser?.email;
    if (!_effectiveAuth.isSignedIn || newEmail != _lastKnownEmail) {
      // Account switch or sign-out
      _lastKnownEmail = newEmail;
      _currentFolder = null;
      _status = DriveFolderStatus.uninitialized;
      _errorMessage = null;
      notifyListeners();
      if (_effectiveAuth.isSignedIn) {
        _syncWithAuthState();
      }
    }
  }

  void _onDriveAuthChanged() {
    if (_effectiveDriveAuth.status != DriveAuthStatus.authorized) {
      if (_status == DriveFolderStatus.ready ||
          _status == DriveFolderStatus.settingUp) {
        _currentFolder = null;
        _status = DriveFolderStatus.uninitialized;
        _errorMessage = null;
        notifyListeners();
      }
    }
  }

  /// Resolves or creates the user-visible "Photo a Day" Google Drive folder.
  ///
  /// Guarantees:
  /// - Idempotent: Searches existing folder first; never creates duplicates.
  /// - Safe: Aborts immediately if not signed in or not authorized.
  /// - Account-isolated: Attaches active user email and saves to local storage.
  Future<DriveFolderResult> setupFolder() async {
    final auth = _effectiveAuth;
    final driveAuth = _effectiveDriveAuth;

    // 1. Verify user is signed in
    if (!auth.isSignedIn) {
      const errorMsg =
          'Google account sign-in required to set up Drive folder.';
      _status = DriveFolderStatus.error;
      _errorMessage = errorMsg;
      notifyListeners();
      return const DriveFolderFailure(
        errorMsg,
        errorType: DriveFolderErrorType.notSignedIn,
      );
    }

    // 2. Verify Drive authorization
    if (!driveAuth.isAuthorized) {
      const errorMsg = 'Google Drive authorization is required.';
      _status = DriveFolderStatus.error;
      _errorMessage = errorMsg;
      notifyListeners();
      return const DriveFolderFailure(
        errorMsg,
        errorType: DriveFolderErrorType.notAuthorized,
      );
    }

    final currentEmail = auth.currentUser?.email;

    // 3. Check if already resolved and valid for current account
    final isMatchingAccount = currentEmail != null
        ? _currentFolder?.authorizedEmail == currentEmail
        : _currentFolder?.authorizedEmail == null;
    if (_status == DriveFolderStatus.ready &&
        _currentFolder != null &&
        isMatchingAccount) {
      return DriveFolderSuccess(_currentFolder!, wasCreated: false);
    }

    // Check disk cache before making network calls
    final cached = await _storage.loadFolderReference();
    final isCachedMatching = currentEmail != null
        ? cached?.authorizedEmail == currentEmail
        : cached?.authorizedEmail == null;
    if (cached != null && isCachedMatching) {
      _currentFolder = cached;
      _status = DriveFolderStatus.ready;
      _errorMessage = null;
      notifyListeners();
      return DriveFolderSuccess(cached, wasCreated: false);
    }

    // 4. Begin remote folder discovery/creation
    _status = DriveFolderStatus.settingUp;
    _errorMessage = null;
    notifyListeners();

    try {
      final authHeaders = await driveAuth.getAuthHeaders();

      // Search for existing folder
      final existing = await _adapter.findFolder(
        folderName: targetFolderName,
        authHeaders: authHeaders,
        accountEmail: currentEmail,
      );

      if (existing != null) {
        _currentFolder = existing;
        await _storage.saveFolderReference(existing);
        _status = DriveFolderStatus.ready;
        _errorMessage = null;
        notifyListeners();
        return DriveFolderSuccess(existing, wasCreated: false);
      }

      // No existing folder found; create new user-visible folder
      final created = await _adapter.createFolder(
        folderName: targetFolderName,
        authHeaders: authHeaders,
        accountEmail: currentEmail,
      );

      _currentFolder = created;
      await _storage.saveFolderReference(created);
      _status = DriveFolderStatus.ready;
      _errorMessage = null;
      notifyListeners();
      return DriveFolderSuccess(created, wasCreated: true);
    } on DriveApiException catch (e) {
      _status = DriveFolderStatus.error;
      _errorMessage = e.message;
      notifyListeners();
      return DriveFolderFailure(
        e.message,
        errorType: e.errorType,
        cause: e.cause,
      );
    } catch (e) {
      const errorMsg =
          'Unexpected error occurred while setting up Google Drive folder.';
      _status = DriveFolderStatus.error;
      _errorMessage = errorMsg;
      notifyListeners();
      return DriveFolderFailure(
        errorMsg,
        errorType: DriveFolderErrorType.apiError,
        cause: e,
      );
    }
  }

  /// Clears in-memory and local disk folder references.
  ///
  /// Note: This does NOT delete the folder in Google Drive.
  Future<void> clearFolderReference() async {
    _currentFolder = null;
    _status = DriveFolderStatus.uninitialized;
    _errorMessage = null;
    await _storage.clearFolderReference();
    notifyListeners();
  }

  @override
  void dispose() {
    _effectiveAuth.removeListener(_onAuthChanged);
    _effectiveDriveAuth.removeListener(_onDriveAuthChanged);
    super.dispose();
  }
}
