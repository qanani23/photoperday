import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/models/drive_auth_state.dart';
import 'package:photo_per_day/data/models/drive_auth_status.dart';
import 'package:photo_per_day/data/services/drive_auth_storage.dart';
import 'package:photo_per_day/data/services/google_auth_service.dart';

/// Abstract delegate encapsulating underlying Drive scope checks and requests.
///
/// Enables isolated, deterministic unit and widget testing without native Google APIs.
abstract class GoogleDriveAuthDelegate {
  /// Checks whether the current account has access to the Drive scope.
  Future<bool> canAccessDriveScope();

  /// Prompts the user for incremental Drive scope authorization.
  Future<bool> requestDriveScope();

  /// Retrieves authenticated HTTP headers for the current session.
  Future<Map<String, String>> getAuthHeaders();
}

/// Production implementation of [GoogleDriveAuthDelegate] using [GoogleAuthService].
class DefaultGoogleDriveAuthDelegate implements GoogleDriveAuthDelegate {
  DefaultGoogleDriveAuthDelegate({GoogleAuthService? authService})
    : _authService = authService ?? GoogleAuthService.instance;

  final GoogleAuthService _authService;

  @override
  Future<bool> canAccessDriveScope() async {
    return await _authService.canAccessDriveScope();
  }

  @override
  Future<bool> requestDriveScope() async {
    return await _authService.requestDriveScope();
  }

  @override
  Future<Map<String, String>> getAuthHeaders() async {
    return await _authService.getAuthHeaders();
  }
}

/// Dedicated service responsible exclusively for Google Drive authorization and client access.
///
/// Separation of Concerns:
/// - Identity is managed by [GoogleAuthService].
/// - Drive authorization is managed by [GoogleDriveAuthService].
/// - Local photo store ([PersistentDailyPhotoStore]) and outbox ([SyncQueue]) remain completely
///   independent and unaffected by Drive authorization state.
///
/// Security:
/// - Strictly isolates tokens: zero access tokens or secrets are stored in metadata, outbox, or logs.
/// - Persists only non-sensitive flags via [DriveAuthStorage].
/// - Enforces the narrowest appropriate scope: [GoogleAuthService.driveFileScope].
class GoogleDriveAuthService with ChangeNotifier {
  GoogleDriveAuthService({
    GoogleAuthService? authService,
    GoogleDriveAuthDelegate? delegate,
    DriveAuthStorage? storage,
  }) : _authService = authService ?? GoogleAuthService.instance,
       _delegate =
           delegate ??
           DefaultGoogleDriveAuthDelegate(
             authService: authService ?? GoogleAuthService.instance,
           ),
       _storage = storage ?? DriveAuthStorage();

  static final GoogleDriveAuthService instance = GoogleDriveAuthService();

  final GoogleAuthService _authService;
  GoogleDriveAuthDelegate _delegate;
  DriveAuthStorage _storage;

  DriveAuthStatus _status = DriveAuthStatus.notAuthorized;
  DateTime? _lastAuthorizedAt;
  String? _errorMessage;
  bool _isInitialized = false;

  /// Current Drive authorization lifecycle state.
  DriveAuthStatus get status => _status;

  /// Whether Google Drive access is currently authorized.
  bool get isAuthorized => _status == DriveAuthStatus.authorized;

  /// Whether an authorization request is actively in flight.
  bool get isAuthorizing => _status == DriveAuthStatus.authorizing;

  /// Timestamp when authorization was last confirmed.
  DateTime? get lastAuthorizedAt => _lastAuthorizedAt;

  /// Error message from the most recent failed authorization attempt, if any.
  String? get errorMessage => _errorMessage;

  /// Whether the service has finished startup initialization.
  bool get isInitialized => _isInitialized;

  /// Underlying delegate for testing or customization.
  @visibleForTesting
  set delegate(GoogleDriveAuthDelegate newDelegate) {
    _delegate = newDelegate;
  }

  /// Underlying storage for testing or customization.
  @visibleForTesting
  set storage(DriveAuthStorage newStorage) {
    _storage = newStorage;
  }

  /// Initializes the Drive authorization service.
  ///
  /// Offline Guarantee:
  /// Performs non-blocking restoration. If the user was previously authorized for the
  /// active account, restores authorized status without requiring an immediate network call.
  Future<void> init() async {
    if (_isInitialized) return;

    _authService.addListener(_handleAuthServiceChange);

    try {
      final persisted = await _storage.loadState();
      final currentEmail = _authService.currentUser?.email;

      if (_authService.isSignedIn &&
          persisted.hasAuthorizedDrive &&
          persisted.authorizedEmail != null &&
          persisted.authorizedEmail == currentEmail) {
        _status = DriveAuthStatus.authorized;
        _lastAuthorizedAt = persisted.lastAuthorizedAt;
        _errorMessage = null;
      } else {
        _status = DriveAuthStatus.notAuthorized;
      }
    } catch (e) {
      debugPrint('Error loading Drive authorization state on init: $e');
      _status = DriveAuthStatus.notAuthorized;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Listens to GoogleAuthService state changes.
  ///
  /// Automatically resets Drive authorization in memory if the user signs out.
  void _handleAuthServiceChange() {
    if (!_authService.isSignedIn) {
      if (_status != DriveAuthStatus.notAuthorized) {
        _status = DriveAuthStatus.notAuthorized;
        _errorMessage = null;
        notifyListeners();
      }
    } else {
      // If user is signed in and we are notAuthorized, check persisted state for this user
      if (_status == DriveAuthStatus.notAuthorized) {
        _checkPersistedStateForCurrentUser();
      }
    }
  }

  Future<void> _checkPersistedStateForCurrentUser() async {
    try {
      final persisted = await _storage.loadState();
      final currentEmail = _authService.currentUser?.email;

      if (persisted.hasAuthorizedDrive &&
          persisted.authorizedEmail != null &&
          persisted.authorizedEmail == currentEmail) {
        _status = DriveAuthStatus.authorized;
        _lastAuthorizedAt = persisted.lastAuthorizedAt;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Explicitly requests incremental Google Drive authorization.
  ///
  /// Requires an active Google Sign-In session.
  /// Transitions through [DriveAuthStatus.authorizing] -> [authorized] | [denied] | [error].
  Future<bool> authorizeDrive() async {
    if (!_authService.isSignedIn) {
      _status = DriveAuthStatus.notAuthorized;
      _errorMessage =
          'Sign in to a Google account before enabling Drive backup.';
      notifyListeners();
      return false;
    }

    _status = DriveAuthStatus.authorizing;
    _errorMessage = null;
    notifyListeners();

    try {
      final granted = await _delegate.requestDriveScope();

      if (granted) {
        _status = DriveAuthStatus.authorized;
        _lastAuthorizedAt = DateTime.now().toUtc();
        _errorMessage = null;

        await _storage.saveState(
          DriveAuthState(
            hasAuthorizedDrive: true,
            authorizedEmail: _authService.currentUser?.email,
            lastAuthorizedAt: _lastAuthorizedAt,
          ),
        );

        notifyListeners();
        return true;
      } else {
        _status = DriveAuthStatus.denied;
        _errorMessage = 'Google Drive access was not granted.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = DriveAuthStatus.error;
      _errorMessage = _cleanErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// Verifies whether the active account has Google Drive authorization.
  Future<bool> checkAuthorization() async {
    if (!_authService.isSignedIn) {
      _status = DriveAuthStatus.notAuthorized;
      notifyListeners();
      return false;
    }

    try {
      final hasScope = await _delegate.canAccessDriveScope();
      if (hasScope) {
        _status = DriveAuthStatus.authorized;
        _lastAuthorizedAt ??= DateTime.now().toUtc();
        await _storage.saveState(
          DriveAuthState(
            hasAuthorizedDrive: true,
            authorizedEmail: _authService.currentUser?.email,
            lastAuthorizedAt: _lastAuthorizedAt,
          ),
        );
      } else {
        _status = DriveAuthStatus.notAuthorized;
      }
      notifyListeners();
      return hasScope;
    } catch (e) {
      debugPrint('Error checking Drive authorization: $e');
      return false;
    }
  }

  /// Client seam for Milestone 21+: Returns authenticated HTTP headers for Google Drive API.
  ///
  /// Throws [StateError] if Google Drive is not authorized or if the user is signed out.
  Future<Map<String, String>> getAuthHeaders() async {
    if (!_authService.isSignedIn) {
      throw StateError('Cannot retrieve auth headers: user is not signed in.');
    }
    if (_status != DriveAuthStatus.authorized) {
      throw StateError(
        'Cannot retrieve auth headers: Google Drive is not authorized.',
      );
    }

    return await _delegate.getAuthHeaders();
  }

  /// Clears local Drive authorization state without revoking the Google account session.
  Future<void> clearAuthorization() async {
    _status = DriveAuthStatus.notAuthorized;
    _lastAuthorizedAt = null;
    _errorMessage = null;
    await _storage.clear();
    notifyListeners();
  }

  /// Sanitizes error messages to protect against credential leakage.
  String _cleanErrorMessage(Object error) {
    final str = error.toString();
    if (str.contains('network_error') || str.contains('SocketException')) {
      return 'Network connection unavailable. Please check your internet connection.';
    }
    if (str.contains('sign_in_canceled') || str.contains('CANCELED')) {
      return 'Drive authorization was cancelled.';
    }
    if (str.contains('DEVELOPER_ERROR') || str.contains('api_not_connected')) {
      return 'Google Drive service configuration error. Please verify OAuth setup.';
    }
    return 'Unable to authorize Google Drive. Please try again.';
  }

  @override
  void dispose() {
    _authService.removeListener(_handleAuthServiceChange);
    super.dispose();
  }
}
