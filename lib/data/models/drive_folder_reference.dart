import 'package:flutter/foundation.dart';

/// Immutable non-sensitive record of the resolved "Photo a Day" Google Drive folder.
///
/// Contains ONLY public/non-sensitive identifiers:
/// - [folderId]: The Google Drive folder identifier.
/// - [folderName]: The name of the folder (e.g., "Photo a Day").
/// - [authorizedEmail]: The email address of the account owning this folder.
/// - [resolvedAt]: The UTC timestamp when this folder was discovered or created.
///
/// Under no circumstances are OAuth tokens, authorization headers, or secrets
/// stored in or attached to this reference.
@immutable
class DriveFolderReference {
  final String folderId;
  final String folderName;
  final String? authorizedEmail;
  final DateTime resolvedAt;

  const DriveFolderReference({
    required this.folderId,
    required this.folderName,
    this.authorizedEmail,
    required this.resolvedAt,
  });

  /// Creates a reference from a JSON map (e.g. from drive_folder_state.json).
  factory DriveFolderReference.fromJson(Map<String, dynamic> json) {
    return DriveFolderReference(
      folderId: json['folderId'] as String,
      folderName: json['folderName'] as String,
      authorizedEmail: json['authorizedEmail'] as String?,
      resolvedAt: DateTime.parse(json['resolvedAt'] as String).toUtc(),
    );
  }

  /// Serializes to a JSON-compatible map for persistence.
  Map<String, dynamic> toJson() {
    return {
      'folderId': folderId,
      'folderName': folderName,
      'authorizedEmail': authorizedEmail,
      'resolvedAt': resolvedAt.toUtc().toIso8601String(),
    };
  }

  DriveFolderReference copyWith({
    String? folderId,
    String? folderName,
    String? authorizedEmail,
    DateTime? resolvedAt,
  }) {
    return DriveFolderReference(
      folderId: folderId ?? this.folderId,
      folderName: folderName ?? this.folderName,
      authorizedEmail: authorizedEmail ?? this.authorizedEmail,
      resolvedAt: resolvedAt ?? this.resolvedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DriveFolderReference &&
          runtimeType == other.runtimeType &&
          folderId == other.folderId &&
          folderName == other.folderName &&
          authorizedEmail == other.authorizedEmail &&
          resolvedAt.isAtSameMomentAs(other.resolvedAt);

  @override
  int get hashCode => Object.hash(
    folderId,
    folderName,
    authorizedEmail,
    resolvedAt.millisecondsSinceEpoch,
  );

  @override
  String toString() =>
      'DriveFolderReference(id: $folderId, name: $folderName, account: $authorizedEmail, resolvedAt: ${resolvedAt.toIso8601String()})';
}
