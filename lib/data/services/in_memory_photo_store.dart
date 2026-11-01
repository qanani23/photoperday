import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/daily_photo_rule.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';

/// Legacy bridge / facade delegating directly to the authoritative [PersistentDailyPhotoStore].
///
/// Ensures zero duplicate or competing sources of truth, while maintaining full
/// backward compatibility with existing screen listeners and references.
class InMemoryPhotoStore extends ChangeNotifier implements DailyPhotoStore {
  InMemoryPhotoStore._() {
    // Forward change notifications from the persistent store
    PersistentDailyPhotoStore.instance.addListener(notifyListeners);
  }

  static final InMemoryPhotoStore instance = InMemoryPhotoStore._();

  PersistentDailyPhotoStore get _store => PersistentDailyPhotoStore.instance;

  // Day-level delegations
  DayEntry? getDay(DateKey key) => _store.getDay(key);
  DayEntry? getDayByDate(DateTime date) => _store.getDayByDate(date);
  bool hasDay(DateKey key) => _store.hasDay(key);
  bool hasDayByDate(DateTime date) => _store.hasDayByDate(date);
  int get totalDays => _store.totalDays;
  List<DayEntry> get allDayEntries => _store.allDayEntries;
  List<DayEntry> get chronologicalDayEntries => _store.chronologicalDayEntries;

  Future<PhotoEntry> addPhotoToDay({
    required DateKey dateKey,
    required PhotoEntry photo,
    String? sourceTempPath,
  }) => _store.addPhotoToDay(
    dateKey: dateKey,
    photo: photo,
    sourceTempPath: sourceTempPath,
  );

  Future<DayEntry?> removePhotoById({
    required DateKey dateKey,
    required String photoId,
    bool preserveNoteOnlyDay = false,
  }) => _store.removePhotoById(
    dateKey: dateKey,
    photoId: photoId,
    preserveNoteOnlyDay: preserveNoteOnlyDay,
  );

  Future<DayEntry> reorderPhotos({
    required DateKey dateKey,
    required List<String> orderedPhotoIds,
  }) =>
      _store.reorderPhotos(dateKey: dateKey, orderedPhotoIds: orderedPhotoIds);

  Future<DayEntry> updateDayNote({
    required DateKey dateKey,
    required String note,
  }) => _store.updateDayNote(dateKey: dateKey, note: note);

  Future<bool> deleteDayEntry({
    required DateKey dateKey,
    required bool confirmed,
  }) => _store.deleteDayEntry(dateKey: dateKey, confirmed: confirmed);

  Future<PhotoEntry> replacePhotoInDay({
    required DateKey dateKey,
    required String targetPhotoId,
    required PhotoEntry newPhoto,
    String? sourceTempPath,
  }) => _store.replacePhotoInDay(
    dateKey: dateKey,
    targetPhotoId: targetPhotoId,
    newPhoto: newPhoto,
    sourceTempPath: sourceTempPath,
  );

  Future<PhotoEntry> replacePhotoAsync(
    DateTime date,
    PhotoEntry newEntry, {
    String? sourceTempPath,
  }) =>
      _store.replacePhotoAsync(date, newEntry, sourceTempPath: sourceTempPath);

  @override
  void setPhoto(PhotoEntry entry) => _store.setPhoto(entry);

  /// Replaces or sets a photo entry for a specific date.
  void replacePhoto(DateTime date, PhotoEntry newEntry) =>
      setPhoto(newEntry.copyWith(date: date));

  @override
  PhotoEntry? getPhoto(DateTime date) => _store.getPhoto(date);

  @override
  PhotoEntry? getPhotoByKey(DateKey key) => _store.getPhotoByKey(key);

  @override
  bool hasPhoto(DateTime date) => _store.hasPhoto(date);

  @override
  bool hasPhotoByKey(DateKey key) => _store.hasPhotoByKey(key);

  @override
  void removePhoto(DateTime date) => _store.removePhoto(date);

  @override
  void removePhotoByKey(DateKey key) => _store.removePhotoByKey(key);

  @override
  int get totalPhotos => _store.totalPhotos;

  /// Alias for [totalPhotos].
  int get count => _store.count;

  /// Unmodifiable view of all stored photo entries.
  List<PhotoEntry> get allEntries => _store.allEntries;

  /// Unmodifiable view of all recorded DateKeys.
  List<DateKey> get recordedDates => _store.recordedDates;

  @override
  void clear() => _store.clear();
}
