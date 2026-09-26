import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';

/// Small, reusable domain service encapsulating the "One Day = One Photo" rule.
///
/// Provides normalized calendar date resolution, same-day equivalence checks,
/// and conflict resolution rules (replacing an existing photo for that day
/// instead of creating a second photo).
abstract final class DailyPhotoRule {
  /// Normalizes any [DateTime] into a standard [DateKey].
  static DateKey normalize(DateTime dateTime) {
    return DateKey.fromDateTime(dateTime);
  }

  /// Checks if two [DateTime] instances occur on the exact same local calendar day.
  static bool isSameDay(DateTime a, DateTime b) {
    return DateKey.fromDateTime(a) == DateKey.fromDateTime(b);
  }

  /// Formats a [DateTime] as a standardized ISO date key 'YYYY-MM-DD'.
  static String formatKey(DateTime dateTime) {
    return DateKey.fromDateTime(dateTime).format();
  }

  /// Normalizes a [DateTime] to local midnight (00:00:00.000) of that calendar day.
  static DateTime toMidnight(DateTime dateTime) {
    return DateKey.fromDateTime(dateTime).toDateTime();
  }

  /// Determines whether adding [incoming] will replace an [existing] photo entry.
  static bool isReplacement({
    required PhotoEntry? existing,
    required PhotoEntry incoming,
  }) {
    if (existing == null) return false;
    return normalize(existing.date) == normalize(incoming.date);
  }
}

/// Abstract contract for a photo store adhering to the one-photo-per-day rule.
abstract interface class DailyPhotoStore {
  /// Retrieves the single photo recorded for the specified calendar [date], or null.
  PhotoEntry? getPhoto(DateTime date);

  /// Retrieves the single photo recorded for the specified [DateKey], or null.
  PhotoEntry? getPhotoByKey(DateKey key);

  /// Returns true if a photo exists for the specified calendar [date].
  bool hasPhoto(DateTime date);

  /// Returns true if a photo exists for the specified [DateKey].
  bool hasPhotoByKey(DateKey key);

  /// Stores or replaces the single photo entry for its normalized calendar date.
  void setPhoto(PhotoEntry entry);

  /// Removes the photo entry for the specified calendar [date].
  void removePhoto(DateTime date);

  /// Removes the photo entry for the specified [DateKey].
  void removePhotoByKey(DateKey key);

  /// Total count of unique daily photos stored.
  int get totalPhotos;

  /// Clears all stored daily photos.
  void clear();
}
