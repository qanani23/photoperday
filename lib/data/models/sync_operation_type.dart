/// Represents the type of remote synchronization operation queued in the outbox.
enum SyncOperationType {
  /// Initial upload/create of a photo on Google Drive.
  upload,

  /// Update of photo metadata or image replacement for an existing remote photo on Google Drive.
  update,

  /// Deletion of a remote photo on Google Drive.
  delete;

  /// Serializes the enum to a JSON string representation.
  String toJson() => name;

  /// Safely parses a JSON value into a [SyncOperationType], defaulting to [upload] if unrecognized or null.
  static SyncOperationType fromJson(dynamic json) {
    if (json is String) {
      for (final value in SyncOperationType.values) {
        if (value.name == json) return value;
      }
    }
    return SyncOperationType.upload;
  }
}
