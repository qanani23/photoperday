/// Strongly typed synchronization state representing a photo's cloud-backup lifecycle.
///
/// Note: This model defines local synchronization metadata without invoking
/// any remote APIs or cloud services.
enum SyncStatus {
  /// The photo exists safely on device and has never been backed up to the cloud.
  localOnly,

  /// The photo has local changes (new capture, metadata edit, or replacement)
  /// awaiting synchronization with the remote store.
  pending,

  /// The local photo and remote copy are identical and fully in sync.
  synced,

  /// A previous synchronization attempt failed; the local photo remains 100%
  /// usable and holds a concise failure description in [syncError].
  failed;

  /// Serializes the status enum to its string name.
  String toJson() => name;

  /// Safely deserializes a string value into a [SyncStatus], falling back
  /// to [SyncStatus.localOnly] if null or unrecognized.
  static SyncStatus fromJson(String? value) {
    if (value == null) return SyncStatus.localOnly;
    return SyncStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => SyncStatus.localOnly,
    );
  }
}
