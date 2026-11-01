import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Data model representing persisted theme settings.
class ThemeSettingsData {
  const ThemeSettingsData({this.paletteId, this.followSystem = true});

  final String? paletteId;
  final bool followSystem;
}

/// Lightweight local disk persistence for user theme and palette settings.
class AppThemeStorage {
  AppThemeStorage({this.customBaseDir});

  static const String themeFileName = 'app_theme_settings.json';

  final String? customBaseDir;
  String? _resolvedDirectory;

  Future<String> get storageDirectory async {
    if (_resolvedDirectory != null) return _resolvedDirectory!;

    String path;
    if (customBaseDir != null) {
      path = customBaseDir!;
    } else {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        path = appDir.path;
      } catch (_) {
        path = Directory.systemTemp.path;
      }
    }
    _resolvedDirectory = path;

    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  Future<String> get themeFilePath async {
    final dir = await storageDirectory;
    return p.join(dir, themeFileName);
  }

  /// Loads persisted theme configuration.
  ///
  /// If no file exists (fresh install), defaults to `paletteId = 'daria_red_light'`, `followSystem = false`.
  Future<ThemeSettingsData> loadSettings() async {
    try {
      final filePath = await themeFilePath;
      final file = File(filePath);

      if (!file.existsSync()) {
        return const ThemeSettingsData(
          paletteId: 'daria_red_light',
          followSystem: false,
        );
      }

      final content = file.readAsStringSync();
      if (content.trim().isEmpty) {
        return const ThemeSettingsData(
          paletteId: 'daria_red_light',
          followSystem: false,
        );
      }

      final dynamic decoded = jsonDecode(content);
      if (decoded is Map) {
        final paletteId = decoded['paletteId'] as String? ?? 'daria_red_light';
        final followSystem = decoded['followSystem'] as bool? ?? false;
        return ThemeSettingsData(
          paletteId: paletteId,
          followSystem: followSystem,
        );
      }

      return const ThemeSettingsData(
        paletteId: 'daria_red_light',
        followSystem: false,
      );
    } catch (e) {
      debugPrint('Error loading theme settings: $e.');
      return const ThemeSettingsData(
        paletteId: 'daria_red_light',
        followSystem: false,
      );
    }
  }

  /// Atomically writes theme settings to disk.
  Future<void> saveSettings({
    required String paletteId,
    required bool followSystem,
  }) async {
    try {
      final filePath = await themeFilePath;
      final tempPath = '$filePath.tmp';

      final tempFile = File(tempPath);
      final jsonString = const JsonEncoder.withIndent('  ').convert({
        'paletteId': paletteId,
        'followSystem': followSystem,
        'version': 1,
      });

      tempFile.writeAsStringSync(jsonString, flush: true);

      final targetFile = File(filePath);
      try {
        if (targetFile.existsSync()) {
          targetFile.deleteSync();
        }
        tempFile.renameSync(filePath);
      } catch (_) {
        tempFile.copySync(filePath);
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Failed to save theme settings to disk: $e');
    }
  }

  /// Loads the persisted palette ID (defaults to 'linen').
  Future<String> loadPaletteId() async {
    final settings = await loadSettings();
    return settings.paletteId ?? 'linen';
  }

  /// Atomically writes the selected palette ID to disk.
  Future<void> savePaletteId(String paletteId) async {
    await saveSettings(paletteId: paletteId, followSystem: false);
  }

  /// Clears persisted theme settings.
  Future<void> clear() async {
    try {
      final filePath = await themeFilePath;
      final file = File(filePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      debugPrint('Failed to clear theme settings: $e');
    }
  }
}
