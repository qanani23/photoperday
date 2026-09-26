import 'package:flutter/foundation.dart';

/// Immutable record of non-sensitive Google Drive authorization state.
///
/// Security:
/// This model explicitly stores NO access tokens, refresh tokens, ID tokens,
/// authorization codes, or client secrets. It records only non-sensitive flags
/// and timestamps used to restore user state cleanly across app restarts.
@immutable
class DriveAuthState {
  const DriveAuthState({
    this.hasAuthorizedDrive = false,
    this.authorizedEmail,
    this.lastAuthorizedAt,
  });

  /// Factory creating default unauthorized state.
  factory DriveAuthState.unauthorized() {
    return const DriveAuthState(
      hasAuthorizedDrive: false,
      authorizedEmail: null,
      lastAuthorizedAt: null,
    );
  }

  /// Whether the user has previously granted Google Drive authorization.
  final bool hasAuthorizedDrive;

  /// The email address of the Google account that authorized Drive access.
  final String? authorizedEmail;

  /// Timestamp when Drive access was authorized.
  final DateTime? lastAuthorizedAt;

  DriveAuthState copyWith({
    bool? hasAuthorizedDrive,
    String? authorizedEmail,
    DateTime? lastAuthorizedAt,
  }) {
    return DriveAuthState(
      hasAuthorizedDrive: hasAuthorizedDrive ?? this.hasAuthorizedDrive,
      authorizedEmail: authorizedEmail ?? this.authorizedEmail,
      lastAuthorizedAt: lastAuthorizedAt ?? this.lastAuthorizedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hasAuthorizedDrive': hasAuthorizedDrive,
      'authorizedEmail': authorizedEmail,
      'lastAuthorizedAt': lastAuthorizedAt?.toIso8601String(),
    };
  }

  factory DriveAuthState.fromJson(Map<String, dynamic> json) {
    return DriveAuthState(
      hasAuthorizedDrive: json['hasAuthorizedDrive'] as bool? ?? false,
      authorizedEmail: json['authorizedEmail'] as String?,
      lastAuthorizedAt: json['lastAuthorizedAt'] != null
          ? DateTime.tryParse(json['lastAuthorizedAt'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DriveAuthState &&
          runtimeType == other.runtimeType &&
          hasAuthorizedDrive == other.hasAuthorizedDrive &&
          authorizedEmail == other.authorizedEmail &&
          lastAuthorizedAt == other.lastAuthorizedAt;

  @override
  int get hashCode =>
      Object.hash(hasAuthorizedDrive, authorizedEmail, lastAuthorizedAt);

  @override
  String toString() =>
      'DriveAuthState(hasAuthorizedDrive: $hasAuthorizedDrive, authorizedEmail: $authorizedEmail, lastAuthorizedAt: $lastAuthorizedAt)';
}
