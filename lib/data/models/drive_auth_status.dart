/// Strongly typed lifecycle state for Google Drive authorization in Photo a Day.
enum DriveAuthStatus {
  /// User has not yet granted Google Drive access, or authorization has not been requested.
  notAuthorized,

  /// Asynchronous Drive authorization request is currently in progress.
  authorizing,

  /// User explicitly granted the drive.file scope for the active Google account.
  authorized,

  /// User cancelled or explicitly denied the Drive authorization consent prompt.
  denied,

  /// An error occurred during authorization (e.g. network failure, configuration issue).
  error,
}
