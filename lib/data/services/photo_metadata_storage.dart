import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_tombstone.dart';

/// Manages atomic reading and writing of photo metadata and sync tombstones to local disk.
///
/// Uses an atomic write pattern (write to temporary file, flush, then rename)
/// with sequential operation queueing to prevent partial, corrupted, or
/// colliding metadata records across concurrent calls.
class PhotoMetadataStorage {
  PhotoMetadataStorage({this.customBaseDir});

  final Directory? customBaseDir;
  File? _metadataFile;
  File? _deletionsFile;
  Future<void>? _activeSave;

  static const String _metadataFileName = 'photos_metadata.json';
  static const String _deletionsFileName = 'pending_deletions.json';

  /// Returns the metadata file handle.
  File get metadataFile {
    if (_metadataFile == null) {
      throw StateError(
        'PhotoMetadataStorage has not been initialized. Call init() first.',
      );
    }
    return _metadataFile!;
  }

  /// Returns the pending deletions tombstone file handle.
  File get deletionsFile {
    if (_deletionsFile == null) {
      throw StateError(
        'PhotoMetadataStorage has not been initialized. Call init() first.',
      );
    }
    return _deletionsFile!;
  }

  /// Initializes the storage file handles.
  Future<void> init() async {
    if (customBaseDir != null) {
      _metadataFile = File(p.join(customBaseDir!.path, _metadataFileName));
      _deletionsFile = File(p.join(customBaseDir!.path, _deletionsFileName));
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      _metadataFile = File(p.join(docDir.path, _metadataFileName));
      _deletionsFile = File(p.join(docDir.path, _deletionsFileName));
    }
  }

  /// Loads all persisted photo entries from the local metadata registry.
  ///
  /// Returns a Map keyed by normalized [DateKey]. Gracefully handles missing
  /// files, corrupted JSON, or individual invalid records without crashing.
  Future<Map<DateKey, PhotoEntry>> loadAll() async {
    if (!await metadataFile.exists()) {
      return {};
    }

    try {
      final content = await metadataFile.readAsString();
      if (content.trim().isEmpty) return {};

      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        debugPrint('Metadata file format unexpected: $decoded');
        return {};
      }

      final result = <DateKey, PhotoEntry>{};
      for (final entry in decoded.entries) {
        try {
          final dateKey = DateKey.parse(entry.key);
          final rawJson = entry.value;
          if (rawJson is Map<String, dynamic>) {
            final photoEntry = PhotoEntry.fromJson(rawJson);
            // Ensure unique DateKey indexing
            result[dateKey] = photoEntry;
          }
        } catch (e) {
          debugPrint(
            'Skipping malformed photo entry for key "${entry.key}": $e',
          );
        }
      }
      return result;
    } catch (e) {
      debugPrint('Failed to read photo metadata file: $e');
      return {};
    }
  }

  /// Atomically writes the entire photo map to the local metadata registry.
  ///
  /// Queues saves sequentially to guarantee consistency and prevent file
  /// collisions during rapid consecutive updates.
  Future<void> saveAll(Map<DateKey, PhotoEntry> entries) async {
    final previousSave = _activeSave;
    final completer = Completer<void>();
    _activeSave = completer.future.catchError((_) {});

    if (previousSave != null) {
      try {
        await previousSave;
      } catch (_) {
        // Continue even if previous save had an issue
      }
    }

    try {
      await _writeToDisk(entries);
      completer.complete();
    } catch (e, stack) {
      completer.completeError(e, stack);
      rethrow;
    }
  }

  Future<void> _writeToDisk(Map<DateKey, PhotoEntry> entries) async {
    final parentDir = metadataFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final uniqueSuffix =
        '${DateTime.now().microsecondsSinceEpoch}_${entries.length}';
    final tempFile = File('${metadataFile.path}.$uniqueSuffix.tmp');

    final jsonMap = <String, dynamic>{};
    for (final entry in entries.entries) {
      jsonMap[entry.key.format()] = entry.value.toJson();
    }

    final jsonString = jsonEncode(jsonMap);

    try {
      // Write to temporary file with flush
      await tempFile.writeAsString(jsonString, flush: true);

      // Atomically replace target file
      try {
        if (await metadataFile.exists()) {
          await metadataFile.delete();
        }
        await tempFile.rename(metadataFile.path);
      } catch (_) {
        // Fallback for Windows file rename lock quirks: copy and delete
        await tempFile.copy(metadataFile.path);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    } catch (e) {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }

  /// Loads all pending cloud deletion tombstones from disk.
  Future<List<SyncTombstone>> loadPendingDeletions() async {
    if (!await deletionsFile.exists()) {
      return [];
    }

    try {
      final content = await deletionsFile.readAsString();
      if (content.trim().isEmpty) return [];

      final decoded = jsonDecode(content);
      if (decoded is! List<dynamic>) return [];

      final list = <SyncTombstone>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          try {
            list.add(SyncTombstone.fromJson(item));
          } catch (e) {
            debugPrint('Skipping malformed tombstone: $e');
          }
        }
      }
      return list;
    } catch (e) {
      debugPrint('Failed to load pending deletions: $e');
      return [];
    }
  }

  /// Atomically writes the pending deletion tombstones to disk.
  Future<void> savePendingDeletions(List<SyncTombstone> deletions) async {
    final parentDir = deletionsFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final jsonList = deletions.map((d) => d.toJson()).toList();
    final jsonString = jsonEncode(jsonList);

    final uniqueSuffix =
        '${DateTime.now().microsecondsSinceEpoch}_${deletions.length}';
    final tempFile = File('${deletionsFile.path}.$uniqueSuffix.tmp');

    try {
      await tempFile.writeAsString(jsonString, flush: true);
      try {
        if (await deletionsFile.exists()) {
          await deletionsFile.delete();
        }
        await tempFile.rename(deletionsFile.path);
      } catch (_) {
        await tempFile.copy(deletionsFile.path);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    } catch (e) {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }

  /// Clears all pending deletion records from disk.
  Future<void> clearPendingDeletions() async {
    try {
      if (await deletionsFile.exists()) {
        await deletionsFile.delete();
      }
    } catch (e) {
      debugPrint('Failed to clear pending deletions: $e');
    }
  }

  /// Deletes the metadata file, deletions file, and any temporary files from disk.
  Future<void> clear() async {
    try {
      if (await metadataFile.exists()) {
        await metadataFile.delete();
      }
      if (await deletionsFile.exists()) {
        await deletionsFile.delete();
      }
      final parentDir = metadataFile.parent;
      if (await parentDir.exists()) {
        final files = parentDir.listSync();
        for (final entity in files) {
          if (entity is File &&
              (entity.path.contains('photos_metadata.json') ||
                  entity.path.contains('pending_deletions.json')) &&
              entity.path.endsWith('.tmp')) {
            try {
              entity.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('PhotoMetadataStorage clear error: $e');
    }
  }
}
