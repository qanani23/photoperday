/// Operational state of Google Drive folder discovery and initialization.
enum DriveFolderStatus {
  /// No Drive folder has been resolved yet, or the user is not signed in / authorized.
  uninitialized,

  /// Actively querying or creating the user-visible "Photo a Day" Drive folder.
  settingUp,

  /// "Photo a Day" folder has been verified or created and is ready.
  ready,

  /// Folder resolution failed due to network, permissions, or API error.
  error,
}
