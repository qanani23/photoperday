import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_per_day/data/models/drive_folder_reference.dart';

/// Service responsible for persisting non-sensitive Google Drive folder metadata.
///
/// Security:
/// Persists ONLY non-sensitive folder identifiers (folderId, folderName, email, resolvedAt).
/// Under NO circumstances are tokens, secrets, or authorization headers saved.
///
/// Reliability:
/// Employs atomic write semantics (.tmp + flush + rename with Windows fallback)
/// to guarantee state file integrity across unexpected terminations.
class DriveFolderStorage {
  DriveFolderStorage({this.customBaseDir});

  static const String stateFileName = 'drive_folder_state.json';

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

  /// Gets the file path to drive_folder_state.json.
  Future<String> get stateFilePath async {
    final dir = await storageDirectory;
    return p.join(dir, stateFileName);
  }

  /// Loads the persisted [DriveFolderReference], or null if absent/corrupt.
  Future<DriveFolderReference?> loadFolderReference() async {
    try {
      final filePath = await stateFilePath;
      final file = File(filePath);

      if (!file.existsSync()) {
        return null;
      }

      final content = file.readAsStringSync();
      if (content.trim().isEmpty) {
        return null;
      }

      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        debugPrint('Malformed drive_folder_state.json; returning null');
        return null;
      }

      return DriveFolderReference.fromJson(decoded);
    } catch (e) {
      debugPrint('Error loading DriveFolderReference: $e. Returning null.');
      return null;
    }
  }

  /// Atomically writes the [DriveFolderReference] to disk.
  Future<void> saveFolderReference(DriveFolderReference reference) async {
    try {
      final filePath = await stateFilePath;
      final tempPath = '$filePath.tmp';

      final tempFile = File(tempPath);
      final jsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(reference.toJson());

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
      debugPrint('Failed to save DriveFolderReference atomically: $e');
      rethrow;
    }
  }

  /// Clears the persisted Drive folder state file.
  Future<void> clearFolderReference() async {
    try {
      final filePath = await stateFilePath;
      final file = File(filePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      debugPrint('Error clearing DriveFolderReference: $e');
    }
  }
}
