import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';

/// Manages atomic reading and writing of photo metadata to local disk.
///
/// Uses an atomic write pattern (write to temporary file, flush, then rename)
/// with sequential operation queueing to prevent partial, corrupted, or
/// colliding metadata records across concurrent calls.
class PhotoMetadataStorage {
  PhotoMetadataStorage({this.customBaseDir});

  final Directory? customBaseDir;
  File? _metadataFile;
  Future<void>? _activeSave;

  static const String _metadataFileName = 'photos_metadata.json';

  /// Returns the metadata file handle.
  File get metadataFile {
    if (_metadataFile == null) {
      throw StateError(
        'PhotoMetadataStorage has not been initialized. Call init() first.',
      );
    }
    return _metadataFile!;
  }

  /// Initializes the storage file handle.
  Future<void> init() async {
    if (customBaseDir != null) {
      _metadataFile = File(p.join(customBaseDir!.path, _metadataFileName));
    } else {
      Directory docDir;
      try {
        docDir = await getApplicationDocumentsDirectory();
      } catch (_) {
        docDir = Directory.systemTemp;
      }
      _metadataFile = File(p.join(docDir.path, _metadataFileName));
    }
  }

  /// Checks whether a persisted metadata file already exists on disk.
  static const int currentSchemaVersion = 2;
  static const String backupV1FileName = 'photos_metadata.v1.bak';

  /// Checks whether a persisted metadata file already exists on disk.
  Future<bool> hasPersistedRecords() async {
    return _metadataFile != null && await _metadataFile!.exists();
  }

  /// Loads all persisted day entries from the local metadata registry.
  ///
  /// Supports:
  /// - Schema 2 (multi-photo per day with daily note).
  /// - Schema 1 (legacy single-photo map). Automatically converts to Schema 2
  ///   without data loss, mapping legacy captions to daily notes.
  /// - Idempotent, crash-resilient, and automatically recovers from interrupted writes.
  Future<Map<DateKey, DayEntry>> loadDays() async {
    // If _metadataFile is null (e.g. test fakes overriding loadAll without calling base init),
    // delegate transparently to loadAll().
    if (_metadataFile == null) {
      final legacy = await loadAll();
      return legacy.map((k, v) => MapEntry(k, DayEntry.fromSinglePhoto(v)));
    }

    String content = '';
    bool fileReadSuccess = false;
    if (await metadataFile.exists()) {
      for (int attempt = 0; attempt < 5; attempt++) {
        try {
          content = await metadataFile.readAsString();
          if (content.trim().isNotEmpty) {
            fileReadSuccess = true;
            break;
          }
        } catch (e) {
          if (attempt < 4) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
        }
      }
    }

    dynamic decoded;
    if (fileReadSuccess) {
      try {
        decoded = jsonDecode(content);
        if (decoded is! Map && decoded is! List) {
          decoded = null;
        }
      } catch (_) {
        decoded = null;
      }
    }

    // If metadataFile is missing, empty, or corrupt (e.g. power loss or process kill),
    // attempt automatic crash recovery from temporary write files or safety backups.
    if (decoded == null) {
      final recovered = await _recoverFromTemporaryOrBackupFiles();
      if (recovered != null) {
        decoded = recovered;
      } else {
        return {};
      }
    }

    try {
      final result = <DateKey, DayEntry>{};

      // Check for Schema 2 versioned envelope
      if (decoded is Map &&
          decoded['schemaVersion'] != null &&
          decoded['days'] is Map) {
        final daysMap = Map<String, dynamic>.from(decoded['days'] as Map);
        for (final entry in daysMap.entries) {
          try {
            final dateKey = DateKey.parse(entry.key.toString());
            final rawJson = entry.value;
            if (rawJson is Map) {
              final jsonMap = Map<String, dynamic>.from(rawJson);
              final dayEntry = DayEntry.fromJson(jsonMap);
              result[dateKey] = dayEntry.dateKey == dateKey
                  ? dayEntry
                  : dayEntry.copyWith(dateKey: dateKey);
            }
          } catch (e) {
            debugPrint(
              'Skipping malformed day entry for key "${entry.key}": $e',
            );
          }
        }
        return result;
      }

      // Schema 1 (Legacy unversioned map or list)
      // Create a safety backup before migration if one does not already exist
      try {
        final backupFile = File(
          p.join(metadataFile.parent.path, backupV1FileName),
        );
        if (!await backupFile.exists() && await metadataFile.exists()) {
          await metadataFile.copy(backupFile.path);
        }
      } catch (e) {
        debugPrint('Notice: could not create v1 metadata backup: $e');
      }

      if (decoded is Map) {
        for (final entry in decoded.entries) {
          try {
            final dateKey = DateKey.parse(entry.key.toString());
            final rawJson = entry.value;
            if (rawJson is Map) {
              final jsonMap = Map<String, dynamic>.from(rawJson);
              var photoEntry = PhotoEntry.fromJson(jsonMap);
              if (photoEntry.dateKey != dateKey) {
                photoEntry = photoEntry.copyWith(date: dateKey.toDateTime());
              }

              // Map legacy caption to daily note if present
              String legacyNote = '';
              final rawCaption = jsonMap['caption'];
              if (rawCaption is String && rawCaption.trim().isNotEmpty) {
                legacyNote = rawCaption.trim();
              }

              result[dateKey] = DayEntry.fromSinglePhoto(
                photoEntry,
                note: legacyNote,
              );
            }
          } catch (e) {
            debugPrint(
              'Skipping malformed legacy entry for key "${entry.key}": $e',
            );
          }
        }
      } else if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            try {
              final jsonMap = Map<String, dynamic>.from(item);
              final photoEntry = PhotoEntry.fromJson(jsonMap);
              final dateKey = photoEntry.dateKey;

              String legacyNote = '';
              final rawCaption = jsonMap['caption'];
              if (rawCaption is String && rawCaption.trim().isNotEmpty) {
                legacyNote = rawCaption.trim();
              }

              result[dateKey] = DayEntry.fromSinglePhoto(
                photoEntry,
                note: legacyNote,
              );
            } catch (e) {
              debugPrint('Skipping malformed legacy list item: $e');
            }
          }
        }
      }

      // Persist migrated Schema 2 to disk
      await saveDays(result);
      return result;
    } catch (e) {
      debugPrint('Failed to read photo metadata file: $e');
      return {};
    }
  }

  /// Backward-compatible loader returning a Map of primary [PhotoEntry] per day.
  Future<Map<DateKey, PhotoEntry>> loadAll() async {
    if (_metadataFile == null) return {};
    final days = await loadDays();
    final result = <DateKey, PhotoEntry>{};
    for (final entry in days.entries) {
      final primary = entry.value.primaryPhoto;
      if (primary != null) {
        result[entry.key] = primary;
      }
    }
    return result;
  }

  /// Atomically writes the entire day entry map to the local metadata registry.
  Future<void> saveDays(Map<DateKey, DayEntry> entries) async {
    // If _metadataFile is null (e.g. test fakes overriding saveAll without calling base init),
    // delegate transparently to saveAll().
    if (_metadataFile == null) {
      final legacy = <DateKey, PhotoEntry>{};
      for (final e in entries.entries) {
        if (e.value.primaryPhoto != null) {
          legacy[e.key] = e.value.primaryPhoto!;
        }
      }
      return saveAll(legacy);
    }

    final previousSave = _activeSave;
    final completer = Completer<void>();
    final currentSave = completer.future.catchError((_) {});
    _activeSave = currentSave;

    if (previousSave != null) {
      try {
        await previousSave;
      } catch (_) {
        // Continue even if previous save had an issue
      }
    }

    try {
      await _writeDaysToDisk(entries);
      completer.complete();
    } catch (e, stack) {
      completer.completeError(e, stack);
      rethrow;
    } finally {
      if (identical(_activeSave, currentSave)) {
        _activeSave = null;
      }
    }
  }

  /// Backward-compatible saver writing a map of [PhotoEntry].
  Future<void> saveAll(Map<DateKey, PhotoEntry> entries) async {
    // Preserve existing notes if available
    final existingDays = await loadDays();
    final dayEntries = <DateKey, DayEntry>{};
    for (final entry in entries.entries) {
      final existing = existingDays[entry.key];
      if (existing != null) {
        // Check if photo is already in existing.photos
        final existingPhotos = List<PhotoEntry>.from(existing.photos);
        final index = existingPhotos.indexWhere(
          (p) =>
              (p.id.isNotEmpty &&
                  entry.value.id.isNotEmpty &&
                  p.id == entry.value.id) ||
              p.effectiveId == entry.value.effectiveId,
        );
        if (index >= 0) {
          existingPhotos[index] = entry.value;
        } else if (existingPhotos.length <= 1) {
          existingPhotos.clear();
          existingPhotos.add(entry.value);
        } else {
          existingPhotos.add(entry.value);
        }
        dayEntries[entry.key] = existing.copyWith(photos: existingPhotos);
      } else {
        dayEntries[entry.key] = DayEntry.fromSinglePhoto(entry.value);
      }
    }
    await saveDays(dayEntries);
  }

  Future<void> _writeDaysToDisk(Map<DateKey, DayEntry> entries) async {
    final parentDir = metadataFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final uniqueSuffix =
        '${DateTime.now().microsecondsSinceEpoch}_${entries.length}';
    final tempFile = File('${metadataFile.path}.$uniqueSuffix.tmp');

    final daysJson = <String, dynamic>{};
    for (final entry in entries.entries) {
      daysJson[entry.key.format()] = entry.value.toJson();
    }

    final envelope = <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'days': daysJson,
    };

    final jsonString = jsonEncode(envelope);

    try {
      // Write to temporary file with flush
      await tempFile.writeAsString(jsonString, flush: true);

      // Atomically replace target file without premature deletion
      try {
        await tempFile.rename(metadataFile.path);
      } catch (_) {
        // Fallback for Windows file rename lock quirks: copy directly over destination and delete temp
        try {
          await tempFile.copy(metadataFile.path);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {
          // Final fallback: write directly to metadataFile with flush
          await metadataFile.writeAsString(jsonString, flush: true);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
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

  /// Scans for recent temporary write files (.tmp) or backup files (.bak) to recover
  /// diary metadata after unexpected process termination or corruption.
  Future<dynamic> _recoverFromTemporaryOrBackupFiles() async {
    try {
      final parentDir = metadataFile.parent;
      if (!await parentDir.exists()) return null;

      // 1. Scan for recent .tmp files created during atomic writes
      final entities = parentDir.listSync();
      final tmpFiles = <File>[];
      for (final e in entities) {
        if (e is File &&
            e.path.contains(_metadataFileName) &&
            e.path.endsWith('.tmp')) {
          tmpFiles.add(e);
        }
      }

      // Sort by last modified descending (newest first)
      tmpFiles.sort((a, b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (_) {
          return 0;
        }
      });

      for (final tmp in tmpFiles) {
        try {
          final text = await tmp.readAsString();
          if (text.trim().isEmpty) continue;
          final json = jsonDecode(text);
          if (json is Map || json is List) {
            debugPrint(
              'PhotoMetadataStorage: Successfully recovered metadata from temporary write file: ${tmp.path}',
            );
            await tmp.copy(metadataFile.path);
            return json;
          }
        } catch (_) {}
      }

      // 2. Check for backup files (photos_metadata.pre_restore.bak or photos_metadata.v1.bak)
      final preRestoreBak = File(
        p.join(parentDir.path, 'photos_metadata.pre_restore.bak'),
      );
      if (await preRestoreBak.exists()) {
        try {
          final text = await preRestoreBak.readAsString();
          if (text.trim().isNotEmpty) {
            final json = jsonDecode(text);
            if (json is Map || json is List) {
              debugPrint(
                'PhotoMetadataStorage: Recovered metadata from pre-restore backup.',
              );
              await preRestoreBak.copy(metadataFile.path);
              return json;
            }
          }
        } catch (_) {}
      }

      final v1Bak = File(p.join(parentDir.path, backupV1FileName));
      if (await v1Bak.exists()) {
        try {
          final text = await v1Bak.readAsString();
          if (text.trim().isNotEmpty) {
            final json = jsonDecode(text);
            if (json is Map || json is List) {
              debugPrint(
                'PhotoMetadataStorage: Recovered metadata from v1 backup.',
              );
              await v1Bak.copy(metadataFile.path);
              return json;
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('PhotoMetadataStorage recovery error: $e');
    }
    return null;
  }

  /// Deletes the metadata file and any temporary files from disk.
  Future<void> clear() async {
    try {
      if (await metadataFile.exists()) {
        await metadataFile.delete();
      }
      final parentDir = metadataFile.parent;
      if (await parentDir.exists()) {
        final files = parentDir.listSync();
        for (final entity in files) {
          if (entity is File &&
              entity.path.contains('photos_metadata.json') &&
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
