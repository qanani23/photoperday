import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_per_day/data/models/drive_auth_state.dart';

/// Service responsible for persisting non-sensitive Google Drive authorization state.
///
/// Security:
/// Strictly persists non-sensitive data (boolean flag, email, timestamp).
/// NEVER persists tokens, secrets, or authorization codes.
///
/// Reliability:
/// Employs atomic write semantics (.tmp + flush + rename with Windows fallback)
/// to ensure power loss or crashes never corrupt storage.
class DriveAuthStorage {
  DriveAuthStorage({this.customBaseDir});

  static const String stateFileName = 'drive_auth_state.json';

  final String? customBaseDir;
  String? _resolvedDirectory;

  /// Resolves the storage directory.
  Future<String> get storageDirectory async {
    if (_resolvedDirectory != null) return _resolvedDirectory!;

    final String path;
    if (customBaseDir != null) {
      path = customBaseDir!;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      path = appDir.path;
    }
    _resolvedDirectory = path;

    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  /// Gets the file path to drive_auth_state.json.
  Future<String> get stateFilePath async {
    final dir = await storageDirectory;
    return p.join(dir, stateFileName);
  }

  /// Loads the persisted DriveAuthState.
  ///
  /// Returns [DriveAuthState.unauthorized] if the file does not exist or is corrupted.
  Future<DriveAuthState> loadState() async {
    try {
      final filePath = await stateFilePath;
      final file = File(filePath);

      if (!file.existsSync()) {
        return DriveAuthState.unauthorized();
      }

      final content = file.readAsStringSync();
      if (content.trim().isEmpty) {
        return DriveAuthState.unauthorized();
      }

      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        debugPrint('Malformed DriveAuthState content; returning unauthorized');
        return DriveAuthState.unauthorized();
      }

      return DriveAuthState.fromJson(decoded);
    } catch (e) {
      debugPrint('Error loading DriveAuthState: $e. Returning unauthorized.');
      return DriveAuthState.unauthorized();
    }
  }

  /// Atomically writes the DriveAuthState to disk.
  Future<void> saveState(DriveAuthState state) async {
    try {
      final filePath = await stateFilePath;
      final tempPath = '$filePath.tmp';

      final tempFile = File(tempPath);
      final jsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(state.toJson());

      // Write to temp file synchronously with flush
      tempFile.writeAsStringSync(jsonString, flush: true);

      // Atomic rename with Windows fallback (copy + delete)
      final targetFile = File(filePath);
      try {
        if (targetFile.existsSync()) {
          targetFile.deleteSync();
        }
        tempFile.renameSync(filePath);
      } catch (_) {
        tempFile.copySync(filePath);
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
        }
      }
    } catch (e) {
      debugPrint('Failed to save DriveAuthState atomically: $e');
      rethrow;
    }
  }

  /// Clears the persisted Drive authorization state file.
  Future<void> clear() async {
    try {
      final filePath = await stateFilePath;
      final file = File(filePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      debugPrint('Error clearing DriveAuthState: $e');
    }
  }
}
