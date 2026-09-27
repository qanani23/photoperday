import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_per_day/data/models/date_key.dart';

/// Manages persistent, app-owned photo files in the local filesystem.
///
/// Ensures temporary camera/gallery files are copied into a protected app directory,
/// uses deterministic collision-safe filenames, handles replacement cleanup safely,
/// and prevents orphan files.
class PhotoFileManager {
  PhotoFileManager({this.customBaseDir});

  final Directory? customBaseDir;
  Directory? _photosDir;

  /// Returns the persistent directory where photos are stored.
  Directory get photosDir {
    if (_photosDir == null) {
      throw StateError(
        'PhotoFileManager has not been initialized. Call init() first.',
      );
    }
    return _photosDir!;
  }

  /// Initializes the storage directory, creating it if it does not yet exist.
  Future<void> init() async {
    if (customBaseDir != null) {
      _photosDir = Directory(p.join(customBaseDir!.path, 'photos'));
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      _photosDir = Directory(p.join(docDir.path, 'photos'));
    }

    if (!await _photosDir!.exists()) {
      await _photosDir!.create(recursive: true);
    }
  }

  /// Pattern matching app-managed photo files: `YYYY-MM-DD_<timestamp>.<ext>`
  static final RegExp appPhotoFilePattern = RegExp(
    r'^\d{4}-\d{2}-\d{2}_\d+\.[a-zA-Z0-9]+$',
  );

  /// Copies a temporary or external photo [sourcePath] into app-controlled persistent storage.
  ///
  /// Validates that the source file exists and contains valid data before copying.
  /// Returns the absolute path of the newly copied persistent photo file.
  Future<String> persistPhotoFile({
    required String sourcePath,
    required DateKey dateKey,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('Source photo file does not exist', sourcePath);
    }

    final fileSize = await sourceFile.length();
    if (fileSize == 0) {
      throw FileSystemException(
        'Source photo file is empty (0 bytes)',
        sourcePath,
      );
    }

    final ext = p.extension(sourcePath).isNotEmpty
        ? p.extension(sourcePath)
        : '.jpg';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '${dateKey.format()}_$timestamp$ext';
    final targetPath = p.join(photosDir.path, fileName);
    final targetFile = File(targetPath);

    try {
      // Copy source file to app storage
      await sourceFile.copy(targetFile.path);

      // Verify copy completed and is non-empty
      if (!await targetFile.exists() || await targetFile.length() == 0) {
        throw FileSystemException(
          'Failed to verify persistent photo copy',
          targetPath,
        );
      }
    } catch (e) {
      try {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
      } catch (_) {}
      rethrow;
    }

    return targetFile.path;
  }

  /// Safely deletes a photo file by its path.
  ///
  /// Returns true if deleted, false if the file was already missing or deletion failed.
  /// Never throws an exception on missing files.
  Future<bool> deletePhotoFile(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return false;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (e) {
      debugPrint('PhotoFileManager safe deletion warning: $e');
    }
    return false;
  }

  /// Clears all files in the photos directory.
  Future<void> clearAll() async {
    if (_photosDir == null || !await _photosDir!.exists()) return;
    try {
      final entities = _photosDir!.listSync();
      for (final entity in entities) {
        if (entity is File) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('PhotoFileManager clearAll error: $e');
    }
  }

  /// Checks if a file path is located within the app's managed photos directory.
  bool isManagedPath(String filePath) {
    if (_photosDir == null) return false;
    return p.isWithin(photosDir.path, filePath);
  }

  /// Scans the managed photos directory and safely removes any unreferenced photo files.
  ///
  /// Strict safety rules:
  /// - Only files matching the app's deterministic naming pattern (`YYYY-MM-DD_<timestamp>.<ext>`)
  ///   are ever considered. Unfamiliar or non-matching files are never touched.
  /// - If the file's normalized absolute path is in [referencedAbsolutePaths], it is preserved.
  /// - Returns the list of pruned file paths.
  Future<List<String>> pruneUnreferencedPhotos(
    Set<String> referencedAbsolutePaths,
  ) async {
    if (_photosDir == null || !await _photosDir!.exists()) return [];

    final pruned = <String>[];
    final normalizedReferenced = referencedAbsolutePaths
        .map((path) => p.normalize(File(path).absolute.path))
        .toSet();

    try {
      final entities = _photosDir!.listSync();
      for (final entity in entities) {
        if (entity is File) {
          final fileName = p.basename(entity.path);
          // Only consider files conforming to our app's photo naming pattern
          if (appPhotoFilePattern.hasMatch(fileName)) {
            final normalizedPath = p.normalize(entity.absolute.path);
            if (!normalizedReferenced.contains(normalizedPath)) {
              try {
                entity.deleteSync();
                pruned.add(entity.path);
                debugPrint('Pruned orphan photo file: ${entity.path}');
              } catch (e) {
                debugPrint(
                  'Failed to delete orphan photo file ${entity.path}: $e',
                );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('PhotoFileManager pruneUnreferencedPhotos error: $e');
    }

    return pruned;
  }
}
