import 'package:flutter/foundation.dart';

/// Immutable model representing the authenticated Google account's public profile information.
///
/// Intentionally excludes all OAuth tokens, refresh tokens, access credentials,
/// and secrets to prevent token leakage or unauthorized persistence.
@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  /// The unique Google user ID.
  final String id;

  /// The user's Google account email address.
  final String email;

  /// The user's display name if available.
  final String? displayName;

  /// The URL to the user's avatar image if available.
  final String? photoUrl;

  /// Returns user's initials for avatar placeholder display.
  String get initials {
    if (displayName != null && displayName!.trim().isNotEmpty) {
      final parts = displayName!
          .trim()
          .split(' ')
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
        return parts[0][0].toUpperCase();
      }
    }
    if (email.isNotEmpty) {
      return email[0].toUpperCase();
    }
    return 'G';
  }

  /// Copies this model with optional updated fields.
  AuthUser copyWith({
    String? id,
    String? email,
    String? displayName,
    String? photoUrl,
  }) {
    return AuthUser(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          email == other.email &&
          displayName == other.displayName &&
          photoUrl == other.photoUrl;

  @override
  int get hashCode => Object.hash(id, email, displayName, photoUrl);

  @override
  String toString() =>
      'AuthUser(id: $id, email: $email, displayName: $displayName)';
}
