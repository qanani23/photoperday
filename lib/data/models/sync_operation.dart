import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/sync_operation_status.dart';
import 'package:photo_per_day/data/models/sync_operation_type.dart';

/// An immutable model representing a durable synchronization operation in the local outbox.
///
/// Contains all intent and scheduling metadata required to execute remote
/// cloud operations (upload, update, delete) asynchronously, with resilience
/// against app termination, crashes, and transient failures.
@immutable
class SyncOperation {
  const SyncOperation({
    required this.id,
    required this.type,
    required this.dateKey,
    required this.createdAt,
    this.status = SyncOperationStatus.pending,
    this.retryCount = 0,
    this.lastAttemptAt,
    this.nextAttemptAt,
    this.lastError,
    this.driveFileId,
    this.authorizedEmail,
  });

  /// Unique operation identifier.
  final String id;

  /// The type of remote operation: upload, update, or delete.
  final SyncOperationType type;

  /// The unique date identity of the affected photo.
  final DateKey dateKey;

  /// Creation timestamp in UTC.
  final DateTime createdAt;

  /// Current queue execution status.
  final SyncOperationStatus status;

  /// Number of execution attempts made so far.
  final int retryCount;

  /// Timestamp of the last attempt in UTC.
  final DateTime? lastAttemptAt;

  /// Earliest timestamp in UTC when the next attempt is allowed to run.
  final DateTime? nextAttemptAt;

  /// Description of the error from the most recent failed attempt.
  final String? lastError;

  /// Target Google Drive file identifier (if known for update or delete).
  final String? driveFileId;

  /// The Google account email for which this operation was queued.
  final String? authorizedEmail;

  /// Creates a copy of this operation with modified fields.
  SyncOperation copyWith({
    String? id,
    SyncOperationType? type,
    DateKey? dateKey,
    DateTime? createdAt,
    SyncOperationStatus? status,
    int? retryCount,
    DateTime? lastAttemptAt,
    DateTime? nextAttemptAt,
    String? lastError,
    bool clearLastError = false,
    String? driveFileId,
    bool clearDriveFileId = false,
    String? authorizedEmail,
    bool clearAuthorizedEmail = false,
  }) {
    return SyncOperation(
      id: id ?? this.id,
      type: type ?? this.type,
      dateKey: dateKey ?? this.dateKey,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      driveFileId: clearDriveFileId ? null : (driveFileId ?? this.driveFileId),
      authorizedEmail: clearAuthorizedEmail
          ? null
          : (authorizedEmail ?? this.authorizedEmail),
    );
  }

  /// Calculates deterministic exponential backoff duration based on retry count.
  /// Purely local calculation without any external network dependency.
  static Duration computeBackoff(
    int retryCount, {
    Duration baseDelay = const Duration(seconds: 30),
    Duration maxDelay = const Duration(hours: 24),
  }) {
    if (retryCount <= 0) return baseDelay;
    final exponent = math.min(retryCount, 10);
    final multiplier = math.pow(2, exponent).toInt();
    final delaySeconds = baseDelay.inSeconds * multiplier;
    return Duration(seconds: math.min(delaySeconds, maxDelay.inSeconds));
  }

  /// Serializes the operation to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toJson(),
      'dateKey': dateKey.format(),
      'createdAt': createdAt.toUtc().toIso8601String(),
      'status': status.toJson(),
      'retryCount': retryCount,
      if (lastAttemptAt != null)
        'lastAttemptAt': lastAttemptAt!.toUtc().toIso8601String(),
      if (nextAttemptAt != null)
        'nextAttemptAt': nextAttemptAt!.toUtc().toIso8601String(),
      if (lastError != null) 'lastError': lastError,
      if (driveFileId != null) 'driveFileId': driveFileId,
      if (authorizedEmail != null) 'authorizedEmail': authorizedEmail,
    };
  }

  /// Safely deserializes a JSON map into a [SyncOperation].
  ///
  /// Guarantees safe fallbacks for missing or malformed attributes.
  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    final rawDateKey = json['dateKey'] as String? ?? '1970-01-01';
    DateKey resolvedDateKey;
    try {
      resolvedDateKey = DateKey.parse(rawDateKey);
    } catch (_) {
      resolvedDateKey = const DateKey(1970, 1, 1);
    }

    final rawCreatedAt = json['createdAt'] as String?;
    DateTime resolvedCreatedAt;
    if (rawCreatedAt != null) {
      resolvedCreatedAt =
          DateTime.tryParse(rawCreatedAt)?.toUtc() ?? DateTime.now().toUtc();
    } else {
      resolvedCreatedAt = DateTime.now().toUtc();
    }

    DateTime? lastAttempt;
    final rawLastAttempt = json['lastAttemptAt'] as String?;
    if (rawLastAttempt != null) {
      lastAttempt = DateTime.tryParse(rawLastAttempt)?.toUtc();
    }

    DateTime? nextAttempt;
    final rawNextAttempt = json['nextAttemptAt'] as String?;
    if (rawNextAttempt != null) {
      nextAttempt = DateTime.tryParse(rawNextAttempt)?.toUtc();
    }

    return SyncOperation(
      id:
          json['id'] as String? ??
          'op_${resolvedDateKey.format()}_${resolvedCreatedAt.microsecondsSinceEpoch}',
      type: SyncOperationType.fromJson(json['type']),
      dateKey: resolvedDateKey,
      createdAt: resolvedCreatedAt,
      status: SyncOperationStatus.fromJson(json['status']),
      retryCount: json['retryCount'] as int? ?? 0,
      lastAttemptAt: lastAttempt,
      nextAttemptAt: nextAttempt,
      lastError: json['lastError'] as String?,
      driveFileId: json['driveFileId'] as String?,
      authorizedEmail:
          (json['authorizedEmail'] ?? json['accountEmail']) as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncOperation &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          dateKey == other.dateKey &&
          createdAt == other.createdAt &&
          status == other.status &&
          retryCount == other.retryCount &&
          lastAttemptAt == other.lastAttemptAt &&
          nextAttemptAt == other.nextAttemptAt &&
          lastError == other.lastError &&
          driveFileId == other.driveFileId &&
          authorizedEmail == other.authorizedEmail;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    dateKey,
    createdAt,
    status,
    retryCount,
    lastAttemptAt,
    nextAttemptAt,
    lastError,
    driveFileId,
    authorizedEmail,
  );

  @override
  String toString() =>
      'SyncOperation(id: $id, type: $type, dateKey: $dateKey, status: $status, retries: $retryCount, email: $authorizedEmail)';
}
