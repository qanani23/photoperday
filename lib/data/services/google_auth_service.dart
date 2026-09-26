import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:photo_per_day/data/models/auth_status.dart';
import 'package:photo_per_day/data/models/auth_user.dart';

/// Abstract delegate encapsulating underlying Google Sign-In SDK calls.
///
/// Enables robust, deterministic testing with test doubles while keeping
/// the production implementation coupled directly to [GoogleSignIn].
abstract class GoogleSignInDelegate {
  /// Attempts silent sign-in. Returns [AuthUser] if session is active, null otherwise.
  Future<AuthUser?> signInSilently();

  /// Initiates interactive sign-in. Returns [AuthUser] upon success, or null if cancelled.
  Future<AuthUser?> signIn();

  /// Signs out of the Google account.
  Future<void> signOut();

  /// Disconnects the Google account and revokes granted permissions.
  Future<void> disconnect();

  /// Checks whether the currently authenticated account has granted the Google Drive scope.
  Future<bool> canAccessDriveScope();

  /// Requests incremental authorization for Google Drive scopes.
  Future<bool> requestDriveScope();

  /// Returns authenticated HTTP headers for the current signed-in account.
  Future<Map<String, String>> getAuthHeaders();
}

/// Production implementation of [GoogleSignInDelegate] using [GoogleSignIn].
class DefaultGoogleSignInDelegate implements GoogleSignInDelegate {
  DefaultGoogleSignInDelegate({GoogleSignIn? googleSignIn})
    : _googleSignIn =
          googleSignIn ?? GoogleSignIn(scopes: GoogleAuthService.defaultScopes);

  final GoogleSignIn _googleSignIn;

  @override
  Future<AuthUser?> signInSilently() async {
    final account = await _googleSignIn.signInSilently();
    if (account == null) return null;
    return _mapAccountToUser(account);
  }

  @override
  Future<AuthUser?> signIn() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null;
    return _mapAccountToUser(account);
  }

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  @override
  Future<void> disconnect() async {
    await _googleSignIn.disconnect();
  }

  @override
  Future<bool> canAccessDriveScope() async {
    return await _googleSignIn.canAccessScopes([
      GoogleAuthService.driveFileScope,
    ]);
  }

  @override
  Future<bool> requestDriveScope() async {
    return await _googleSignIn.requestScopes([
      GoogleAuthService.driveFileScope,
    ]);
  }

  @override
  Future<Map<String, String>> getAuthHeaders() async {
    final account = _googleSignIn.currentUser;
    if (account == null) {
      throw StateError('No Google account is currently signed in.');
    }
    return await account.authHeaders;
  }

  AuthUser _mapAccountToUser(GoogleSignInAccount account) {
    return AuthUser(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
    );
  }
}

/// Dedicated service responsible exclusively for Google account authentication and session state.
///
/// Features:
/// - Reactive authentication state tracking ([AuthStatus.signedOut], [AuthStatus.signingIn], [AuthStatus.signedIn], [AuthStatus.error]).
/// - Safe extraction of non-sensitive public user info ([AuthUser]).
/// - Token isolation: zero OAuth tokens, refresh tokens, or credentials stored in photo metadata or logs.
/// - Silent startup restoration without throwing or blocking offline initialization.
/// - Decoupled from [PersistentDailyPhotoStore] and [SyncQueue], guaranteeing full offline photo diary functionality.
/// - Authorization seam for future Google Drive scopes ([driveFileScope]) in Milestone 19.
class GoogleAuthService with ChangeNotifier {
  GoogleAuthService({GoogleSignInDelegate? delegate})
    : _delegate = delegate ?? DefaultGoogleSignInDelegate();

  static final GoogleAuthService instance = GoogleAuthService();

  /// Google Drive scope planned for user-visible photo backup in Milestone 19.
  ///
  /// Uses [drive.file] (narrowest appropriate scope for user-visible app-created files),
  /// explicitly avoiding [drive.appdata] as required by specifications.
  static const String driveFileScope =
      'https://www.googleapis.com/auth/drive.file';

  /// Standard basic identity scopes used for initial authentication in Milestone 18.
  static const List<String> defaultScopes = ['email'];

  GoogleSignInDelegate _delegate;

  AuthStatus _status = AuthStatus.signedOut;
  AuthUser? _currentUser;
  String? _errorMessage;
  bool _isInitialized = false;

  /// Current authentication lifecycle status.
  AuthStatus get status => _status;

  /// The currently authenticated user's public profile information, or null if signed out.
  AuthUser? get currentUser => _currentUser;

  /// Whether a user is currently authenticated.
  bool get isSignedIn => _status == AuthStatus.signedIn;

  /// Error message from the most recent failed sign-in attempt, if any.
  String? get errorMessage => _errorMessage;

  /// Whether the service has completed initial silent restoration check.
  bool get isInitialized => _isInitialized;

  /// Underlying delegate for testing or customization.
  @visibleForTesting
  set delegate(GoogleSignInDelegate newDelegate) {
    _delegate = newDelegate;
  }

  /// Initializes the authentication service and attempts silent session restoration.
  ///
  /// Offline Guarantee:
  /// Failure to silently restore a session (e.g. offline device or revoked access)
  /// gracefully defaults to [AuthStatus.signedOut] without throwing or interrupting startup.
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      final user = await _delegate.signInSilently();
      if (user != null) {
        _currentUser = user;
        _status = AuthStatus.signedIn;
        _errorMessage = null;
      } else {
        _currentUser = null;
        _status = AuthStatus.signedOut;
      }
    } catch (e) {
      debugPrint(
        'Silent Google Sign-In check resulted in signed-out state: $e',
      );
      _currentUser = null;
      _status = AuthStatus.signedOut;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Initiates interactive Google Sign-In.
  ///
  /// Returns the authenticated [AuthUser] upon success, or `null` if cancelled or failed.
  /// User cancellation cleanly returns to [AuthStatus.signedOut] without recording an error.
  Future<AuthUser?> signIn() async {
    _status = AuthStatus.signingIn;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _delegate.signIn();

      if (user == null) {
        // User cancelled the interactive sign-in prompt
        _status = AuthStatus.signedOut;
        _currentUser = null;
        _errorMessage = null;
        notifyListeners();
        return null;
      }

      _currentUser = user;
      _status = AuthStatus.signedIn;
      _errorMessage = null;
      notifyListeners();
      return _currentUser;
    } catch (e) {
      _currentUser = null;
      _status = AuthStatus.error;
      _errorMessage = _cleanErrorMessage(e);
      notifyListeners();
      return null;
    }
  }

  /// Signs out of the Google account.
  ///
  /// Clears the authenticated session state. Local photos and queued outbox operations
  /// remain completely intact on device.
  Future<void> signOut() async {
    try {
      await _delegate.signOut();
    } catch (e) {
      debugPrint('Error during Google Sign-Out: $e');
    } finally {
      _status = AuthStatus.signedOut;
      _currentUser = null;
      _errorMessage = null;
      notifyListeners();
    }
  }

  /// Disconnects the Google account and revokes granted OAuth scopes.
  Future<void> disconnect() async {
    try {
      await _delegate.disconnect();
    } catch (e) {
      debugPrint('Error during Google Disconnect: $e');
    } finally {
      _status = AuthStatus.signedOut;
      _currentUser = null;
      _errorMessage = null;
      notifyListeners();
    }
  }

  /// Checks whether the currently authenticated account has granted the Drive scope.
  Future<bool> canAccessDriveScope() async {
    if (!isSignedIn) return false;

    try {
      return await _delegate.canAccessDriveScope();
    } catch (e) {
      debugPrint('Error checking Drive authorization scope: $e');
      return false;
    }
  }

  /// Requests incremental Google Drive authorization scope.
  ///
  /// Requests [driveFileScope] on the currently authenticated account.
  /// Returns true if authorization was granted, false otherwise.
  Future<bool> requestDriveScope() async {
    if (!isSignedIn) return false;

    try {
      return await _delegate.requestDriveScope();
    } catch (e) {
      debugPrint('Error requesting Drive authorization scope: $e');
      return false;
    }
  }

  /// Returns authenticated HTTP headers for the current authenticated account.
  ///
  /// Throws [StateError] if the user is not signed in.
  Future<Map<String, String>> getAuthHeaders() async {
    if (!isSignedIn) {
      throw StateError('Cannot retrieve auth headers: user is not signed in.');
    }
    return await _delegate.getAuthHeaders();
  }

  /// Sanitizes error messages to ensure zero sensitive tokens or codes are exposed.
  String _cleanErrorMessage(Object error) {
    final str = error.toString();
    if (str.contains('network_error') || str.contains('SocketException')) {
      return 'Network connection unavailable. Please check your internet connection.';
    }
    if (str.contains('sign_in_canceled') || str.contains('CANCELED')) {
      return 'Sign-in was cancelled.';
    }
    if (str.contains('sign_in_failed') || str.contains('DEVELOPER_ERROR')) {
      return 'Google Sign-In configuration error. Please verify OAuth setup.';
    }
    return 'Unable to sign in with Google. Please try again.';
  }
}
