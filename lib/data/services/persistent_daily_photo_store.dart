import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/daily_photo_rule.dart';
import 'package:photo_per_day/data/services/local_storage_calculator.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';

/// Production implementation of [DailyPhotoStore] delivering persistent local storage
/// for a 100% offline, local-only personal photo diary.
///
/// Features (Milestone 58):
/// - Day-level storage model ([DayEntry]) supporting multiple photos per local calendar day.
/// - One editable daily reflection note per calendar day.
/// - In-memory synchronous cache for instantaneous UI queries.
/// - Two-layer storage: app-controlled photo files directory + atomic JSON metadata registry (Schema 2).
/// - Non-destructive multi-photo additions (same-day capture never replaces existing photos).
/// - Stable photo identification, independent file references, and reordering.
/// - Safe deletion of individual photos (pruning day if last photo) or caller-confirmed day deletion.
/// - Graceful handling of missing files, database corruptions, and cold app restarts.
/// - Serialized async queueing preventing race conditions across concurrent operations.
/// - Completely offline: zero cloud network dependencies, sign-ins, or remote services.
class PersistentDailyPhotoStore extends ChangeNotifier
    implements DailyPhotoStore {
  PersistentDailyPhotoStore({
    PhotoFileManager? fileManager,
    PhotoMetadataStorage? metadataStorage,
  }) : _fileManager = fileManager ?? PhotoFileManager(),
       _metadataStorage = metadataStorage ?? PhotoMetadataStorage(),
       _hasCustomDependencies = fileManager != null || metadataStorage != null;

  final bool _hasCustomDependencies;

  static PersistentDailyPhotoStore? _testInstance;

  /// The active singleton or test instance.
  static PersistentDailyPhotoStore get instance =>
      _testInstance ?? _defaultInstance;

  static final PersistentDailyPhotoStore _defaultInstance =
      PersistentDailyPhotoStore();

  @visibleForTesting
  static void setTestInstance(PersistentDailyPhotoStore testStore) {
    _testInstance = testStore;
  }

  @visibleForTesting
  static void resetTestInstance() {
    _testInstance = null;
  }

  PhotoFileManager _fileManager;
  PhotoMetadataStorage _metadataStorage;

  /// In-memory cache of day entries keyed by normalized DateKey.
  final Map<DateKey, DayEntry> _dayEntries = {};

  bool _isInitialized = false;
  Future<void>? _activeOp;

  int _version = 0;

  /// Monotonically increasing version counter incremented on every store mutation.
  /// Used by dependent services (e.g. streaks, statistics) for zero-cost cache validation.
  int get version => _version;

  List<PhotoEntry>? _cachedAllEntries;
  List<DateKey>? _cachedRecordedDates;
  List<PhotoEntry>? _cachedChronologicalEntries;
  List<PhotoEntry>? _cachedChronologicalAscendingEntries;
  List<DayEntry>? _cachedAllDayEntries;
  List<DayEntry>? _cachedChronologicalDayEntries;
  List<DayEntry>? _cachedChronologicalAscendingDayEntries;

  void _invalidateCaches() {
    _version++;
    _cachedAllEntries = null;
    _cachedRecordedDates = null;
    _cachedChronologicalEntries = null;
    _cachedChronologicalAscendingEntries = null;
    _cachedAllDayEntries = null;
    _cachedChronologicalDayEntries = null;
    _cachedChronologicalAscendingDayEntries = null;
  }

  /// Whether the store has completed loading its persisted records from disk.
  bool get isInitialized => _isInitialized;

  /// The underlying [PhotoFileManager] used by this store.
  PhotoFileManager get fileManager => _fileManager;

  /// The underlying [PhotoMetadataStorage] used by this store.
  PhotoMetadataStorage get metadataStorage => _metadataStorage;

  /// Lightweight sequential FIFO executor ensuring that persistent mutations
  /// never race against each other, even under rapid consecutive calls.
  Future<T> _runSequential<T>(Future<T> Function() operation) async {
    final previous = _activeOp;
    final completer = Completer<void>();
    final currentFuture = completer.future.catchError((_) {});
    _activeOp = currentFuture;

    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // Continue even if previous operation had an issue
      }
    }

    try {
      final result = await operation();
      completer.complete();
      return result;
    } catch (e, stack) {
      completer.completeError(e, stack);
      rethrow;
    } finally {
      if (identical(_activeOp, currentFuture)) {
        _activeOp = null;
      }
    }
  }

  /// Awaits completion of all currently active or queued disk operations.
  Future<void> flush() async {
    final current = _activeOp;
    if (current != null) {
      try {
        await current;
      } catch (_) {}
    }
  }

  /// Initializes the file directory and restores persisted photo metadata from disk.
  Future<void> init({Directory? customBaseDir}) async {
    if (!_hasCustomDependencies && customBaseDir != null) {
      _fileManager = PhotoFileManager(customBaseDir: customBaseDir);
      _metadataStorage = PhotoMetadataStorage(customBaseDir: customBaseDir);
    }

    await _fileManager.init();
    await _metadataStorage.init();

    final loaded = await _metadataStorage.loadDays();
    _dayEntries.clear();
    _dayEntries.addAll(loaded);

    _isInitialized = true;
    _invalidateCaches();
    notifyListeners();
  }

  // ==========================================
  // Day-Level Multi-Photo API
  // ==========================================

  /// Retrieves the day entry for the specified [DateKey], or null if unrecorded.
  DayEntry? getDay(DateKey key) => _dayEntries[key];

  /// Retrieves the day entry for the specified calendar [date], or null.
  DayEntry? getDayByDate(DateTime date) =>
      _dayEntries[DateKey.fromDateTime(date)];

  /// Returns true if a day entry exists for [key].
  bool hasDay(DateKey key) => _dayEntries.containsKey(key);

  /// Returns true if a day entry exists for calendar [date].
  bool hasDayByDate(DateTime date) =>
      _dayEntries.containsKey(DateKey.fromDateTime(date));

  /// Total count of unique recorded calendar days.
  int get totalDays => _dayEntries.length;

  /// Total count of individual photos across all recorded days.
  @override
  int get totalPhotos =>
      _dayEntries.values.fold<int>(0, (sum, day) => sum + day.photoCount);

  /// Total count of stored photos (alias for [totalPhotos]).
  int get count => totalPhotos;

  /// Unmodifiable view of all recorded DateKeys.
  List<DateKey> get recordedDates =>
      _cachedRecordedDates ??= List.unmodifiable(_dayEntries.keys);

  /// Unmodifiable view of all day entries.
  List<DayEntry> get allDayEntries =>
      _cachedAllDayEntries ??= List.unmodifiable(_dayEntries.values);

  /// Chronological day entries ordered newest-to-oldest (descending).
  List<DayEntry> get chronologicalDayEntries {
    if (_cachedChronologicalDayEntries != null) {
      return _cachedChronologicalDayEntries!;
    }
    final sorted = _dayEntries.values.toList()
      ..sort((a, b) => b.dateKey.compareTo(a.dateKey));
    return _cachedChronologicalDayEntries = List.unmodifiable(sorted);
  }

  /// Chronological day entries ordered oldest-to-newest (ascending).
  List<DayEntry> get chronologicalAscendingDayEntries {
    if (_cachedChronologicalAscendingDayEntries != null) {
      return _cachedChronologicalAscendingDayEntries!;
    }
    final sorted = _dayEntries.values.toList()
      ..sort((a, b) => a.dateKey.compareTo(b.dateKey));
    return _cachedChronologicalAscendingDayEntries = List.unmodifiable(sorted);
  }

  /// Unmodifiable view of all individual photo entries across all days.
  List<PhotoEntry> get allEntries {
    if (_cachedAllEntries != null) return _cachedAllEntries!;
    final list = _dayEntries.values.expand((d) => d.photos).toList();
    return _cachedAllEntries = List.unmodifiable(list);
  }

  /// Chronological photos ordered newest-to-oldest (descending).
  List<PhotoEntry> get chronologicalEntries {
    if (_cachedChronologicalEntries != null) {
      return _cachedChronologicalEntries!;
    }
    final list = _dayEntries.values.expand((d) => d.photos).toList()
      ..sort((a, b) {
        final cmp = b.dateKey.compareTo(a.dateKey);
        if (cmp != 0) return cmp;
        return a.order.compareTo(b.order);
      });
    return _cachedChronologicalEntries = List.unmodifiable(list);
  }

  /// Chronological photos ordered oldest-to-newest (ascending).
  List<PhotoEntry> get chronologicalAscendingEntries {
    if (_cachedChronologicalAscendingEntries != null) {
      return _cachedChronologicalAscendingEntries!;
    }
    final list = _dayEntries.values.expand((d) => d.photos).toList()
      ..sort((a, b) {
        final cmp = a.dateKey.compareTo(b.dateKey);
        if (cmp != 0) return cmp;
        return a.order.compareTo(b.order);
      });
    return _cachedChronologicalAscendingEntries = List.unmodifiable(list);
  }

  // ==========================================
  // Multi-Photo Storage Operations
  // ==========================================

  /// Adds a photo to a day without replacing existing photos.
  ///
  /// Guarantees:
  /// - Unique persistent image file generated via [PhotoFileManager].
  /// - Stable unique ID assigned to the photo.
  /// - Preserves all existing photos on that date.
  /// - Atomicity: metadata committed before in-memory state is updated; rollback on failure.
  Future<PhotoEntry> addPhotoToDay({
    required DateKey dateKey,
    required PhotoEntry photo,
    String? sourceTempPath,
  }) async {
    return await _runSequential(() async {
      final existingDay = _dayEntries[dateKey];
      String? persistentPath = photo.imagePath;

      final pathToPersist = sourceTempPath ?? photo.imagePath;
      if (pathToPersist != null && pathToPersist.isNotEmpty) {
        final sourceFile = File(pathToPersist);
        if (!sourceFile.existsSync()) {
          throw FileSystemException(
            'Source photo file does not exist',
            pathToPersist,
          );
        }
        final length = sourceFile.lengthSync();
        if (length == 0) {
          throw FileSystemException(
            'Source photo file is empty (0 bytes)',
            pathToPersist,
          );
        }

        if (_isInitialized && !_fileManager.isManagedPath(pathToPersist)) {
          persistentPath = await _fileManager.persistPhotoFile(
            sourcePath: pathToPersist,
            dateKey: dateKey,
          );
        }
      }

      final stableId = photo.id.isNotEmpty
          ? photo.id
          : 'photo_${dateKey.format()}_${DateTime.now().microsecondsSinceEpoch}_${existingDay?.photoCount ?? 0}';

      final savedPhoto = photo.copyWith(
        id: stableId,
        order: existingDay?.photoCount ?? 0,
        imagePath: persistentPath,
        syncStatus: SyncStatus.localOnly,
        lastModifiedAt: DateTime.now().toUtc(),
        clearSyncError: true,
      );

      final DayEntry updatedDay;
      if (existingDay != null) {
        updatedDay = existingDay.addPhoto(savedPhoto);
      } else {
        updatedDay = DayEntry(
          dateKey: dateKey,
          photos: [savedPhoto],
          note: '',
          createdAt: photo.date.toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );
      }

      // Two-Phase Commit: Prepare tentative entries map for disk write
      final tentative = Map<DateKey, DayEntry>.from(_dayEntries);
      tentative[dateKey] = updatedDay;

      if (_isInitialized) {
        try {
          await _metadataStorage.saveDays(tentative);
        } catch (e) {
          if (persistentPath != null &&
              !_fileManager.isManagedPath(pathToPersist ?? '')) {
            await _fileManager.deletePhotoFile(persistentPath);
          }
          rethrow;
        }
      }

      _dayEntries[dateKey] = updatedDay;
      _invalidateCaches();
      notifyListeners();
      return savedPhoto;
    });
  }

  /// Saves a photo entry for its calendar day without replacing existing photos.
  ///
  /// If [entry] has an [id] matching an existing photo on that date, it updates
  /// that photo's metadata (and image file, if [sourceTempPath] is provided) in place.
  /// Otherwise, appends the photo to the day.
  Future<PhotoEntry> savePhoto({
    required PhotoEntry entry,
    String? sourceTempPath,
  }) async {
    final key = entry.dateKey;
    final existingDay = _dayEntries[key];

    // Check if updating an existing photo with matching ID in this day
    if (existingDay != null &&
        entry.id.isNotEmpty &&
        existingDay.hasPhotoId(entry.id)) {
      return await _runSequential(() async {
        String? persistentPath = entry.imagePath;
        final pathToPersist =
            sourceTempPath ??
            (entry.imagePath != null &&
                    !_fileManager.isManagedPath(entry.imagePath!)
                ? entry.imagePath
                : null);

        String? oldManagedPath;
        final oldPhoto = existingDay.getPhotoById(entry.id);
        if (oldPhoto != null &&
            oldPhoto.imagePath != null &&
            _fileManager.isManagedPath(oldPhoto.imagePath!)) {
          oldManagedPath = oldPhoto.imagePath;
        }

        if (pathToPersist != null && pathToPersist.isNotEmpty) {
          final sourceFile = File(pathToPersist);
          if (!sourceFile.existsSync()) {
            throw FileSystemException(
              'Source photo file does not exist',
              pathToPersist,
            );
          }
          final length = sourceFile.lengthSync();
          if (length == 0) {
            throw FileSystemException(
              'Source photo file is empty (0 bytes)',
              pathToPersist,
            );
          }

          if (_isInitialized && !_fileManager.isManagedPath(pathToPersist)) {
            persistentPath = await _fileManager.persistPhotoFile(
              sourcePath: pathToPersist,
              dateKey: key,
            );
          }
        }

        final updatedPhotos = existingDay.photos.map((p) {
          if (p.id == entry.id) {
            return entry.copyWith(
              id: p.id,
              order: p.order,
              imagePath: persistentPath ?? p.imagePath,
              lastModifiedAt: DateTime.now().toUtc(),
            );
          }
          return p;
        }).toList();

        final updatedDay = existingDay.copyWith(
          photos: updatedPhotos,
          updatedAt: DateTime.now().toUtc(),
        );

        final tentative = Map<DateKey, DayEntry>.from(_dayEntries);
        tentative[key] = updatedDay;

        if (_isInitialized) {
          try {
            await _metadataStorage.saveDays(tentative);
          } catch (e) {
            if (persistentPath != null &&
                persistentPath != oldManagedPath &&
                !_fileManager.isManagedPath(pathToPersist ?? '')) {
              await _fileManager.deletePhotoFile(persistentPath);
            }
            rethrow;
          }
        }

        // Clean up old replaced photo file if a new file was persisted
        if (persistentPath != null &&
            oldManagedPath != null &&
            persistentPath != oldManagedPath) {
          await _fileManager.deletePhotoFile(oldManagedPath);
        }

        _dayEntries[key] = updatedDay;
        _invalidateCaches();
        notifyListeners();
        return updatedDay.getPhotoById(entry.id)!;
      });
    }

    return addPhotoToDay(
      dateKey: key,
      photo: entry,
      sourceTempPath: sourceTempPath,
    );
  }

  /// Explicitly replaces an individual photo in a day by its stable ID.
  ///
  /// Preserves other photos in the day and the daily note intact.
  Future<PhotoEntry> replacePhotoInDay({
    required DateKey dateKey,
    required String targetPhotoId,
    required PhotoEntry newPhoto,
    String? sourceTempPath,
  }) async {
    final photoWithTargetId = newPhoto.copyWith(
      id: targetPhotoId,
      date: dateKey.toDateTime(),
    );
    return savePhoto(entry: photoWithTargetId, sourceTempPath: sourceTempPath);
  }

  /// Removes an individual photo by stable ID.
  ///
  /// If [preserveNoteOnlyDay] is true and the day has a non-empty note,
  /// the day entry is retained as a note-only day when its last photo is removed.
  /// Otherwise, removes the empty day entry completely (returning null).
  Future<DayEntry?> removePhotoById({
    required DateKey dateKey,
    required String photoId,
    bool preserveNoteOnlyDay = false,
  }) async {
    return await _runSequential(() async {
      final day = _dayEntries[dateKey];
      if (day == null) return null;

      final targetPhoto = day.getPhotoById(photoId);
      if (targetPhoto == null) return day;

      final updatedDay = day.removePhoto(photoId);

      final shouldRetainDay =
          updatedDay.isNotEmpty || (preserveNoteOnlyDay && updatedDay.hasNote);

      final tentative = Map<DateKey, DayEntry>.from(_dayEntries);
      if (shouldRetainDay) {
        tentative[dateKey] = updatedDay;
      } else {
        tentative.remove(dateKey);
      }

      if (_isInitialized) {
        await _metadataStorage.saveDays(tentative);
        if (targetPhoto.hasRealImage) {
          await _fileManager.deletePhotoFile(targetPhoto.imagePath);
        }
      }

      if (shouldRetainDay) {
        _dayEntries[dateKey] = updatedDay;
      } else {
        _dayEntries.remove(dateKey);
      }

      _invalidateCaches();
      notifyListeners();
      return shouldRetainDay ? updatedDay : null;
    });
  }

  /// Reorders photos for [dateKey] according to [orderedPhotoIds].
  Future<DayEntry> reorderPhotos({
    required DateKey dateKey,
    required List<String> orderedPhotoIds,
  }) async {
    return await _runSequential(() async {
      final day = _dayEntries[dateKey];
      if (day == null) {
        throw StateError('No day entry found for date key $dateKey');
      }

      final updatedDay = day.reorderPhotos(orderedPhotoIds);

      final tentative = Map<DateKey, DayEntry>.from(_dayEntries);
      tentative[dateKey] = updatedDay;

      if (_isInitialized) {
        await _metadataStorage.saveDays(tentative);
      }

      _dayEntries[dateKey] = updatedDay;
      _invalidateCaches();
      notifyListeners();
      return updatedDay;
    });
  }

  /// Reads and updates the day's note.
  ///
  /// Supports creating a note for an empty day (note-only day).
  /// If the note is cleared on a note-only day, the entry is cleanly pruned.
  Future<DayEntry> updateDayNote({
    required DateKey dateKey,
    required String note,
  }) async {
    return await _runSequential(() async {
      final day = _dayEntries[dateKey];
      if (day == null) {
        if (note.trim().isEmpty) {
          return DayEntry(dateKey: dateKey, photos: const [], note: '');
        }
        final newDay = DayEntry(
          dateKey: dateKey,
          photos: const [],
          note: note,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );
        final tentative = Map<DateKey, DayEntry>.from(_dayEntries);
        tentative[dateKey] = newDay;
        if (_isInitialized) {
          await _metadataStorage.saveDays(tentative);
        }
        _dayEntries[dateKey] = newDay;
        _invalidateCaches();
        notifyListeners();
        return newDay;
      }

      // If clearing note on an entry with no photos, prune it completely
      if (day.photos.isEmpty && note.trim().isEmpty) {
        final tentative = Map<DateKey, DayEntry>.from(_dayEntries)
          ..remove(dateKey);
        if (_isInitialized) {
          await _metadataStorage.saveDays(tentative);
        }
        _dayEntries.remove(dateKey);
        _invalidateCaches();
        notifyListeners();
        return DayEntry(dateKey: dateKey, photos: const [], note: '');
      }

      final updatedDay = day.updateNote(note);

      final tentative = Map<DateKey, DayEntry>.from(_dayEntries);
      tentative[dateKey] = updatedDay;

      if (_isInitialized) {
        await _metadataStorage.saveDays(tentative);
      }

      _dayEntries[dateKey] = updatedDay;
      _invalidateCaches();
      notifyListeners();
      return updatedDay;
    });
  }

  /// Deletes an entire day entry with explicit caller-controlled confirmation.
  Future<bool> deleteDayEntry({
    required DateKey dateKey,
    required bool confirmed,
  }) async {
    if (!confirmed) return false;

    return await _runSequential(() async {
      final day = _dayEntries[dateKey];
      if (day == null) return false;

      final tentative = Map<DateKey, DayEntry>.from(_dayEntries)
        ..remove(dateKey);

      if (_isInitialized) {
        await _metadataStorage.saveDays(tentative);
        for (final photo in day.photos) {
          if (photo.hasRealImage) {
            await _fileManager.deletePhotoFile(photo.imagePath);
          }
        }
      }

      _dayEntries.remove(dateKey);
      _invalidateCaches();
      notifyListeners();
      return true;
    });
  }

  // ==========================================
  // Backward Compatibility DailyPhotoStore APIs
  // ==========================================

  @override
  PhotoEntry? getPhoto(DateTime date) => getDayByDate(date)?.primaryPhoto;

  @override
  PhotoEntry? getPhotoByKey(DateKey key) => getDay(key)?.primaryPhoto;

  @override
  bool hasPhoto(DateTime date) => hasDayByDate(date);

  @override
  bool hasPhotoByKey(DateKey key) => hasDay(key);

  /// Atomically updates metadata (title, location) for an existing photo entry.
  Future<PhotoEntry> updatePhotoMetadata({
    required DateKey dateKey,
    String? title,
    String? location,
    bool clearLocation = false,
  }) {
    return _runSequential(
      () => _updatePhotoMetadataInternal(
        dateKey: dateKey,
        title: title,
        location: location,
        clearLocation: clearLocation,
      ),
    );
  }

  Future<PhotoEntry> _updatePhotoMetadataInternal({
    required DateKey dateKey,
    String? title,
    String? location,
    bool clearLocation = false,
  }) async {
    final day = _dayEntries[dateKey];
    if (day == null || day.isEmpty) {
      throw StateError('No photo entry found for date key $dateKey');
    }

    final existing = day.primaryPhoto!;
    final trimmedTitle = title?.trim();
    final effectiveTitle = (trimmedTitle != null && trimmedTitle.isNotEmpty)
        ? trimmedTitle
        : existing.title;

    final String? effectiveLocation;
    if (clearLocation) {
      effectiveLocation = null;
    } else if (location != null) {
      final trimmedLoc = location.trim();
      effectiveLocation = trimmedLoc.isEmpty ? null : trimmedLoc;
    } else {
      effectiveLocation = existing.location;
    }

    final updated = existing.copyWith(
      title: effectiveTitle,
      location: effectiveLocation,
      clearLocation:
          clearLocation || (location != null && effectiveLocation == null),
      lastModifiedAt: DateTime.now().toUtc(),
    );

    final updatedPhotos = List<PhotoEntry>.from(day.photos);
    updatedPhotos[0] = updated;
    final updatedDay = day.copyWith(
      photos: updatedPhotos,
      updatedAt: DateTime.now().toUtc(),
    );

    final tentative = Map<DateKey, DayEntry>.from(_dayEntries);
    tentative[dateKey] = updatedDay;

    if (_isInitialized) {
      await _metadataStorage.saveDays(tentative);
    }

    _dayEntries[dateKey] = updatedDay;
    _invalidateCaches();
    notifyListeners();
    return updated;
  }

  /// Convenience method for replacing or saving a photo for a specific date.
  ///
  /// If the date already has photos and [newEntry.id] is not explicitly specified,
  /// replaces the day's primary photo.
  Future<PhotoEntry> replacePhotoAsync(
    DateTime date,
    PhotoEntry newEntry, {
    String? sourceTempPath,
  }) async {
    final key = DateKey.fromDateTime(date);
    final day = _dayEntries[key];
    String targetId = newEntry.id;
    if (targetId.isEmpty && day != null && day.photos.isNotEmpty) {
      targetId = day.primaryPhoto!.id;
    }
    return savePhoto(
      entry: newEntry.copyWith(id: targetId, date: date),
      sourceTempPath: sourceTempPath,
    );
  }

  @override
  void setPhoto(PhotoEntry entry) {
    final key = entry.dateKey;
    final existingDay = _dayEntries[key];

    final DayEntry updatedDay;
    if (existingDay != null) {
      final matchesExisting = existingDay.photos.any(
        (p) =>
            (p.id.isNotEmpty && entry.id.isNotEmpty && p.id == entry.id) ||
            p.effectiveId == entry.effectiveId,
      );
      if (matchesExisting ||
          (existingDay.photos.length == 1 && entry.id.isEmpty)) {
        updatedDay = existingDay.updatePhoto(entry);
      } else {
        updatedDay = existingDay.addPhoto(entry);
      }
    } else {
      updatedDay = DayEntry.fromSinglePhoto(entry);
    }

    _dayEntries[key] = updatedDay;
    _invalidateCaches();
    notifyListeners();

    if (_isInitialized) {
      _runSequential(() async {
        final tentative = Map<DateKey, DayEntry>.from(_dayEntries);
        await _metadataStorage.saveDays(tentative);
      }).catchError((e) {
        debugPrint('Background metadata save error, rolling back: $e');
        if (existingDay != null) {
          _dayEntries[key] = existingDay;
        } else {
          _dayEntries.remove(key);
        }
        _invalidateCaches();
        notifyListeners();
      });
    }
  }

  @override
  void removePhoto(DateTime date) {
    removePhotoByKey(DateKey.fromDateTime(date));
  }

  @override
  void removePhotoByKey(DateKey key) {
    final day = _dayEntries[key];
    if (day == null) return;

    _dayEntries.remove(key);
    _invalidateCaches();
    notifyListeners();

    if (_isInitialized) {
      _runSequential(() async {
        final tentative = Map<DateKey, DayEntry>.from(_dayEntries);
        await _metadataStorage.saveDays(tentative);
        for (final photo in day.photos) {
          if (photo.hasRealImage) {
            await _fileManager.deletePhotoFile(photo.imagePath);
          }
        }
      });
    }
  }

  /// Removes photo asynchronously and flushes pending writes to disk.
  Future<void> removePhotoAsync(DateTime date) async {
    await removePhotoByKeyAsync(DateKey.fromDateTime(date));
  }

  /// Removes photo by key asynchronously and flushes pending writes to disk.
  Future<void> removePhotoByKeyAsync(DateKey key) async {
    await deleteDayEntry(dateKey: key, confirmed: true);
  }

  /// Whether a key has a pending deletion. In local-only mode, deletions are immediate.
  bool hasPendingDeletion(DateKey key) => false;

  /// Reconciles local photo files on disk against the metadata registry.
  Future<List<String>> reconcileOrphanFiles() async {
    if (!_isInitialized) return [];

    try {
      final referencedPaths = _dayEntries.values
          .expand((day) => day.photos)
          .where((entry) => entry.hasRealImage)
          .map((entry) => entry.imagePath!)
          .toSet();

      return await _fileManager.pruneUnreferencedPhotos(referencedPaths);
    } catch (e) {
      debugPrint('reconcileOrphanFiles encountered non-critical error: $e');
      return [];
    }
  }

  @override
  void clear() {
    _dayEntries.clear();
    LocalStorageCalculator.clearCache();
    _invalidateCaches();
    notifyListeners();
    if (_isInitialized) {
      _runSequential(() async {
        await _metadataStorage.clear();
        await _fileManager.clearAll();
      }).catchError((e) {
        debugPrint('Clear storage error: $e');
      });
    }
  }

  /// Asynchronously clears all photo entries and photo files.
  Future<void> clearAsync() {
    return _runSequential(() async {
      _dayEntries.clear();
      LocalStorageCalculator.clearCache();
      _invalidateCaches();
      if (_isInitialized) {
        await _metadataStorage.clear();
        await _fileManager.clearAll();
      }
      notifyListeners();
    });
  }

  /// Permanently removes all local diary data from the device:
  /// - All local photo files in managed storage
  /// - All local photo metadata
  Future<void> deleteLocalDiary() async {
    await clearAsync();
  }

  bool _isDisposed = false;

  /// Whether this store instance has been disposed.
  bool get isDisposed => _isDisposed;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }
}
