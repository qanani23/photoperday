/// Represents the lifecycle state of Google account authentication.
enum AuthStatus {
  /// No Google account is currently authenticated.
  signedOut,

  /// Interactive sign-in process is actively in progress.
  signingIn,

  /// A Google account is successfully authenticated.
  signedIn,

  /// An error occurred during the most recent authentication attempt.
  error;

  /// Whether the user is actively authenticated.
  bool get isSignedIn => this == AuthStatus.signedIn;

  /// Whether authentication is actively in progress.
  bool get isSigningIn => this == AuthStatus.signingIn;
}
