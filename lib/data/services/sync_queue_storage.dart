import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_per_day/data/models/sync_operation.dart';
import 'package:photo_per_day/data/models/sync_operation_status.dart';

/// Manages atomic reading and writing of synchronization outbox operations to local disk.
///
/// Uses an atomic write pattern (write to temporary file, flush, then rename)
/// with sequential operation queueing to prevent corrupted, partial, or collided records.
class SyncQueueStorage {
  SyncQueueStorage({this.customBaseDir});

  final Directory? customBaseDir;
  File? _queueFile;
  Future<void>? _activeSave;

  static const String _queueFileName = 'sync_queue.json';

  /// Returns the queue file handle.
  File get queueFile {
    if (_queueFile == null) {
      throw StateError(
        'SyncQueueStorage has not been initialized. Call init() first.',
      );
    }
    return _queueFile!;
  }

  /// Initializes the storage file handle.
  Future<void> init() async {
    if (customBaseDir != null) {
      _queueFile = File(p.join(customBaseDir!.path, _queueFileName));
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      _queueFile = File(p.join(docDir.path, _queueFileName));
    }
  }

  /// Loads all persisted operations from the local synchronization outbox file.
  ///
  /// Crash Recovery Guarantee:
  /// Any operation found with [SyncOperationStatus.inProgress] is automatically
  /// reset to [SyncOperationStatus.pending] to prevent operations from becoming
  /// permanently stuck after an unexpected app crash or process kill.
  ///
  /// Gracefully handles missing files, empty files, or individual corrupt items.
  Future<List<SyncOperation>> loadQueue() async {
    if (!await queueFile.exists()) {
      return [];
    }

    try {
      final content = await queueFile.readAsString();
      if (content.trim().isEmpty) return [];

      final decoded = jsonDecode(content);
      if (decoded is! List) {
        debugPrint('Sync queue file format unexpected (not a list): $decoded');
        return [];
      }

      final operations = <SyncOperation>[];
      final seenIds = <String>{};
      for (final item in decoded) {
        if (item is Map) {
          try {
            final op = SyncOperation.fromJson(Map<String, dynamic>.from(item));
            if (seenIds.contains(op.id)) continue;
            seenIds.add(op.id);
            // Automatic crash recovery: reset interrupted inProgress operations to pending
            if (op.status == SyncOperationStatus.inProgress) {
              operations.add(op.copyWith(status: SyncOperationStatus.pending));
            } else {
              operations.add(op);
            }
          } catch (e) {
            debugPrint('Skipping malformed sync queue operation: $e');
          }
        }
      }
      return operations;
    } catch (e) {
      debugPrint('Failed to read sync queue file: $e');
      return [];
    }
  }

  /// Atomically writes the entire list of queued operations to disk.
  ///
  /// Queues saves sequentially to guarantee consistency and prevent file
  /// collisions during rapid consecutive updates.
  Future<void> saveQueue(List<SyncOperation> operations) async {
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
      await _writeToDisk(operations);
      completer.complete();
    } catch (e, stack) {
      completer.completeError(e, stack);
      rethrow;
    }
  }

  Future<void> _writeToDisk(List<SyncOperation> operations) async {
    final parentDir = queueFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final uniqueSuffix =
        '${DateTime.now().microsecondsSinceEpoch}_${operations.length}';
    final tempFile = File('${queueFile.path}.$uniqueSuffix.tmp');

    final jsonList = operations.map((op) => op.toJson()).toList();
    final jsonString = jsonEncode(jsonList);

    try {
      // Write to temporary file with disk flush
      await tempFile.writeAsString(jsonString, flush: true);

      // Atomically replace target file
      try {
        if (await queueFile.exists()) {
          await queueFile.delete();
        }
        await tempFile.rename(queueFile.path);
      } catch (_) {
        // Fallback for Windows file rename lock quirks: copy and delete
        await tempFile.copy(queueFile.path);
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

  /// Clears the queue file and any temporary files from disk.
  Future<void> clear() async {
    try {
      if (await queueFile.exists()) {
        await queueFile.delete();
      }
      final parentDir = queueFile.parent;
      if (await parentDir.exists()) {
        final files = parentDir.listSync();
        for (final entity in files) {
          if (entity is File &&
              entity.path.contains(_queueFileName) &&
              entity.path.endsWith('.tmp')) {
            try {
              entity.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('SyncQueueStorage clear error: $e');
    }
  }
}
