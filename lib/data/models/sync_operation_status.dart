/// Represents the lifecycle status of an operation queued in the synchronization outbox.
enum SyncOperationStatus {
  /// Operation is pending in the queue and waiting to be processed.
  pending,

  /// Operation is actively being executed.
  ///
  /// Interrupted operations (due to app termination or crash) are automatically
  /// recovered back to [pending] upon queue startup.
  inProgress,

  /// Operation encountered an error during execution and is awaiting retry.
  failed,

  /// Operation successfully completed and can be pruned.
  completed;

  /// Serializes the enum to a JSON string representation.
  String toJson() => name;

  /// Safely parses a JSON value into a [SyncOperationStatus], defaulting to [pending] if unrecognized or null.
  static SyncOperationStatus fromJson(dynamic json) {
    if (json is String) {
      for (final value in SyncOperationStatus.values) {
        if (value.name == json) return value;
      }
    }
    return SyncOperationStatus.pending;
  }
}
