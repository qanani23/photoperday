import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_per_day/data/models/daily_reminder_settings.dart';

/// Lightweight local disk persistence for user reminder settings.
///
/// Follows project persistence conventions:
/// - Persists strictly local preferences (`daily_reminder_settings.json`).
/// - Employs atomic write semantics (`.tmp` + flush + rename with Windows fallback).
/// - Supports custom base directory injection for deterministic tests.
class DailyReminderStorage {
  DailyReminderStorage({this.customBaseDir});

  static const String settingsFileName = 'daily_reminder_settings.json';

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

  /// Gets the full path to daily_reminder_settings.json.
  Future<String> get settingsFilePath async {
    final dir = await storageDirectory;
    return p.join(dir, settingsFileName);
  }

  /// Loads the persisted [DailyReminderSettings], or default if absent/corrupt.
  Future<DailyReminderSettings> loadSettings() async {
    try {
      final filePath = await settingsFilePath;
      final file = File(filePath);

      if (!file.existsSync()) {
        return DailyReminderSettings.defaultSettings;
      }

      final content = file.readAsStringSync();
      if (content.trim().isEmpty) {
        return DailyReminderSettings.defaultSettings;
      }

      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map) {
        debugPrint(
          'Malformed daily_reminder_settings.json; returning defaults',
        );
        return DailyReminderSettings.defaultSettings;
      }

      return DailyReminderSettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      debugPrint(
        'Error loading DailyReminderSettings: $e. Returning defaults.',
      );
      return DailyReminderSettings.defaultSettings;
    }
  }

  /// Atomically writes the [DailyReminderSettings] to disk.
  Future<void> saveSettings(DailyReminderSettings settings) async {
    try {
      final filePath = await settingsFilePath;
      final tempPath = '$filePath.tmp';

      final tempFile = File(tempPath);
      final jsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(settings.toJson());

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
      debugPrint('Failed to save DailyReminderSettings atomically: $e');
      rethrow;
    }
  }

  /// Clears the persisted settings file.
  Future<void> clearSettings() async {
    try {
      final filePath = await settingsFilePath;
      final file = File(filePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      debugPrint('Error clearing DailyReminderSettings: $e');
    }
  }
}
