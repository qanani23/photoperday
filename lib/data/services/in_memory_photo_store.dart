import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/models/date_key.dart';
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
