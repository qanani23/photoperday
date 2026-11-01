import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';

/// Represents a single diary entry for one local calendar date.
///
/// Encapsulates:
/// - A normalized [DateKey] defining the local calendar date.
/// - An ordered list of independently identifiable [PhotoEntry] instances.
/// - One editable daily [note] (initially empty).
/// - Creation and update timestamps.
@immutable
class DayEntry {
  DayEntry({
    required this.dateKey,
    List<PhotoEntry>? photos,
    this.note = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : photos = List.unmodifiable(photos ?? const <PhotoEntry>[]),
       createdAt = createdAt ?? dateKey.toDateTime().toUtc(),
       updatedAt = updatedAt ?? DateTime.now().toUtc();

  /// Normalized calendar date key for this diary day.
  final DateKey dateKey;

  /// Ordered, unmodifiable list of photos captured for this day.
  final List<PhotoEntry> photos;

  /// Single editable reflection or note for this day.
  final String note;

  /// UTC timestamp of when this day entry was initially created.
  final DateTime createdAt;

  /// UTC timestamp of the most recent modification to this day entry.
  final DateTime updatedAt;

  /// Whether this day has no photos.
  bool get isEmpty => photos.isEmpty;

  /// Whether this day has at least one photo.
  bool get isNotEmpty => photos.isNotEmpty;

  /// Whether this day has at least one photo.
  bool get hasPhotos => photos.isNotEmpty;

  /// Whether this day has a non-empty daily note.
  bool get hasNote => note.trim().isNotEmpty;

  /// Whether this day contains only a note without photos.
  bool get isNoteOnly => photos.isEmpty && note.trim().isNotEmpty;

  /// Total count of photos associated with this day.
  int get photoCount => photos.length;

  /// Primary photo representing this day (the first photo in display order),
  /// or `null` if no photos exist.
  PhotoEntry? get primaryPhoto => photos.isNotEmpty ? photos.first : null;

  /// Finds an individual photo by its unique [id] or [effectiveId].
  PhotoEntry? getPhotoById(String id) {
    for (final photo in photos) {
      if (photo.effectiveId == id || photo.id == id) {
        return photo;
      }
    }
    return null;
  }

  /// Checks whether a photo with the given [id] exists in this day.
  bool hasPhotoId(String id) => getPhotoById(id) != null;

  /// Creates a copy of this [DayEntry] with a new photo appended at the end.
  DayEntry addPhoto(PhotoEntry photo) {
    final updatedList = List<PhotoEntry>.from(photos);
    final nextOrder = updatedList.length;
    final photoWithOrder = photo.order == nextOrder
        ? photo
        : photo.copyWith(order: nextOrder);
    updatedList.add(photoWithOrder);
    return DayEntry(
      dateKey: dateKey,
      photos: updatedList,
      note: note,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  /// Updates an existing photo matching [photo.effectiveId] or [photo.id].
  /// If no matching photo exists, appends [photo] via [addPhoto].
  DayEntry updatePhoto(PhotoEntry photo) {
    final targetId = photo.id.isNotEmpty ? photo.id : photo.effectiveId;
    final index = photos.indexWhere(
      (p) => (p.id.isNotEmpty && p.id == targetId) || p.effectiveId == targetId,
    );
    if (index >= 0) {
      final updatedList = List<PhotoEntry>.from(photos);
      updatedList[index] = photo.copyWith(order: index);
      return DayEntry(
        dateKey: dateKey,
        photos: updatedList,
        note: note,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
      );
    }
    return addPhoto(photo);
  }

  /// Creates a copy of this [DayEntry] with the specified photo removed.
  ///
  /// Re-indexes the [order] of all remaining photos to maintain consistent 0-based ordering.
  DayEntry removePhoto(String photoId) {
    final filtered = photos
        .where((p) => p.effectiveId != photoId && p.id != photoId)
        .toList();
    final reindexed = <PhotoEntry>[];
    for (int i = 0; i < filtered.length; i++) {
      reindexed.add(filtered[i].copyWith(order: i));
    }
    return DayEntry(
      dateKey: dateKey,
      photos: reindexed,
      note: note,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  /// Creates a copy of this [DayEntry] with photos reordered according to [orderedPhotoIds].
  ///
  /// Stable: Photo identities and metadata are strictly preserved.
  DayEntry reorderPhotos(List<String> orderedPhotoIds) {
    final photoMap = <String, PhotoEntry>{};
    for (final photo in photos) {
      photoMap[photo.effectiveId] = photo;
      if (photo.id.isNotEmpty) {
        photoMap[photo.id] = photo;
      }
    }

    final reordered = <PhotoEntry>[];
    final seenIds = <String>{};

    for (final id in orderedPhotoIds) {
      final photo = photoMap[id];
      if (photo != null && seenIds.add(photo.effectiveId)) {
        reordered.add(photo.copyWith(order: reordered.length));
      }
    }

    // Append any photos not explicitly listed in orderedPhotoIds to preserve them
    for (final photo in photos) {
      if (seenIds.add(photo.effectiveId)) {
        reordered.add(photo.copyWith(order: reordered.length));
      }
    }

    return DayEntry(
      dateKey: dateKey,
      photos: reordered,
      note: note,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  /// Creates a copy of this [DayEntry] with updated note text.
  DayEntry updateNote(String newNote) {
    return DayEntry(
      dateKey: dateKey,
      photos: photos,
      note: newNote,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  /// Creates a [DayEntry] wrapping a single legacy [PhotoEntry].
  factory DayEntry.fromSinglePhoto(
    PhotoEntry photo, {
    String note = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DayEntry(
      dateKey: photo.dateKey,
      photos: [photo],
      note: note,
      createdAt: createdAt ?? photo.date.toUtc(),
      updatedAt: updatedAt ?? photo.effectiveLastModifiedAt,
    );
  }

  /// Converts this [DayEntry] into a JSON-serializable Map (Schema Version 2).
  Map<String, dynamic> toJson() {
    return {
      'dateKey': dateKey.format(),
      'note': note,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'photos': photos.map((p) => p.toJson()).toList(),
    };
  }

  /// Reconstructs a [DayEntry] from a JSON map with full resilience.
  factory DayEntry.fromJson(Map<String, dynamic> json) {
    final rawKey = json['dateKey']?.toString() ?? '';
    DateKey dateKey;
    try {
      dateKey = DateKey.parse(rawKey);
    } catch (_) {
      // Fallback from createdAt or today
      final rawCreated = json['createdAt']?.toString();
      final dt = rawCreated != null ? DateTime.tryParse(rawCreated) : null;
      dateKey = dt != null ? DateKey.fromDateTime(dt) : DateKey.today();
    }

    final note = json['note']?.toString() ?? json['caption']?.toString() ?? '';

    final rawCreated = json['createdAt']?.toString();
    final createdAt =
        (rawCreated != null ? DateTime.tryParse(rawCreated) : null)?.toUtc() ??
        dateKey.toDateTime().toUtc();

    final rawUpdated = json['updatedAt']?.toString();
    final updatedAt =
        (rawUpdated != null ? DateTime.tryParse(rawUpdated) : null)?.toUtc() ??
        createdAt;

    final photos = <PhotoEntry>[];
    final rawPhotos = json['photos'];
    if (rawPhotos is List) {
      for (int i = 0; i < rawPhotos.length; i++) {
        final item = rawPhotos[i];
        if (item is Map) {
          try {
            var photo = PhotoEntry.fromJson(Map<String, dynamic>.from(item));
            if (photo.order != i && item['order'] == null) {
              photo = photo.copyWith(order: i);
            }
            photos.add(photo);
          } catch (e) {
            debugPrint('Failed to parse photo in DayEntry: $e');
          }
        }
      }
    } else if (json['imagePath'] != null || json['title'] != null) {
      // Legacy single-photo entry encoded directly
      try {
        final photo = PhotoEntry.fromJson(json);
        photos.add(photo);
      } catch (e) {
        debugPrint('Failed to parse legacy single photo in DayEntry: $e');
      }
    }

    return DayEntry(
      dateKey: dateKey,
      photos: photos,
      note: note,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  DayEntry copyWith({
    DateKey? dateKey,
    List<PhotoEntry>? photos,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DayEntry(
      dateKey: dateKey ?? this.dateKey,
      photos: photos ?? this.photos,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DayEntry &&
          runtimeType == other.runtimeType &&
          dateKey == other.dateKey &&
          note == other.note &&
          listEquals(photos, other.photos);

  @override
  int get hashCode => Object.hash(dateKey, note, Object.hashAll(photos));

  @override
  String toString() =>
      'DayEntry(dateKey: $dateKey, photos: ${photos.length}, note: "${note.length > 20 ? "${note.substring(0, 20)}..." : note}")';
}
