import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Lightweight local disk persistence for onboarding status.
///
/// Follows project persistence conventions:
/// - Persists strictly local preferences (`onboarding_settings.json`).
/// - Employs atomic write semantics (`.tmp` + flush + rename with Windows fallback).
/// - Supports custom base directory injection for deterministic tests.
class OnboardingStorage {
  OnboardingStorage({this.customBaseDir});

  static const String onboardingFileName = 'onboarding_settings.json';

  final String? customBaseDir;
  String? _resolvedDirectory;

  /// Resolves the storage directory.
  Future<String> get storageDirectory async {
    if (_resolvedDirectory != null) return _resolvedDirectory!;

    String path;
    if (customBaseDir != null) {
      path = customBaseDir!;
    } else {
      try {
        final appDir = await getApplicationDocumentsDirectory().timeout(
          const Duration(milliseconds: 300),
        );
        path = appDir.path;
      } catch (_) {
        path = Directory.systemTemp.path;
      }
    }
    _resolvedDirectory = path;

    final dir = Directory(path);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return path;
  }

  /// Gets the full path to onboarding_settings.json.
  Future<String> get onboardingFilePath async {
    final dir = await storageDirectory;
    return p.join(dir, onboardingFileName);
  }

  /// Loads onboarding completion status. Defaults to false if file is missing/empty/corrupt.
  Future<bool> loadCompleted() async {
    try {
      final filePath = await onboardingFilePath;
      final file = File(filePath);

      if (!file.existsSync()) {
        return false;
      }

      final content = file.readAsStringSync();
      if (content.trim().isEmpty) {
        return false;
      }

      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map) {
        debugPrint('Malformed onboarding_settings.json; returning false.');
        return false;
      }

      return decoded['completed'] == true;
    } catch (e) {
      debugPrint('Error loading OnboardingStorage: $e. Returning false.');
      return false;
    }
  }

  /// Atomically writes onboarding status to disk.
  Future<void> saveCompleted({required bool completed}) async {
    try {
      final filePath = await onboardingFilePath;
      final tempPath = '$filePath.tmp';

      final tempFile = File(tempPath);
      final jsonString = const JsonEncoder.withIndent('  ').convert({
        'completed': completed,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      // Write to temp file synchronously with flush
      tempFile.writeAsStringSync(jsonString, flush: true);

      // Atomic rename with Windows fallback
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
      debugPrint('Failed to save OnboardingStorage atomically: $e');
      rethrow;
    }
  }

  /// Clears persisted onboarding state.
  Future<void> clear() async {
    try {
      final filePath = await onboardingFilePath;
      final file = File(filePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      debugPrint('Failed to clear OnboardingStorage: $e');
    }
  }
}
