import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';

/// Result summary of a photo import operation.
class PhotoImportResult {
  const PhotoImportResult({
    required this.importedPhotos,
    required this.importedCount,
    this.failedFiles = const [],
    this.errorMessage,
    this.isCancelled = false,
  });

  factory PhotoImportResult.cancelled() => const PhotoImportResult(
    importedPhotos: [],
    importedCount: 0,
    isCancelled: true,
  );

  factory PhotoImportResult.failure(
    String message, [
    List<String> failed = const [],
  ]) => PhotoImportResult(
    importedPhotos: const [],
    importedCount: 0,
    failedFiles: failed,
    errorMessage: message,
  );

  final List<PhotoEntry> importedPhotos;
  final int importedCount;
  final List<String> failedFiles;
  final String? errorMessage;
  final bool isCancelled;

  bool get isSuccess => importedCount > 0 && !isCancelled;
}

/// Abstract platform delegate decoupling native file picking and gallery APIs.
abstract class PhotoImportPlatformDelegate {
  Future<List<String>> pickPhotoFiles({bool allowMultiple = true});
}

/// Windows and desktop file selection delegate utilizing [FilePicker].
class WindowsPhotoImportPlatformDelegate
    implements PhotoImportPlatformDelegate {
  const WindowsPhotoImportPlatformDelegate();

  static const List<String> supportedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'bmp',
  ];

  @override
  Future<List<String>> pickPhotoFiles({bool allowMultiple = true}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: allowMultiple
            ? 'Select Photographs to Import'
            : 'Select Photograph to Import',
        type: FileType.custom,
        allowedExtensions: supportedExtensions,
        allowMultiple: allowMultiple,
      );

      if (result == null || result.files.isEmpty) {
        return const [];
      }

      return result.paths
          .whereType<String>()
          .where((path) => path.trim().isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('WindowsPhotoImportPlatformDelegate error: $e');
      return const [];
    }
  }
}

/// Mobile device photo library delegate utilizing [ImagePicker].
class MobilePhotoImportPlatformDelegate implements PhotoImportPlatformDelegate {
  MobilePhotoImportPlatformDelegate({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  @override
  Future<List<String>> pickPhotoFiles({bool allowMultiple = true}) async {
    try {
      if (allowMultiple) {
        final List<XFile> picked = await _imagePicker.pickMultiImage(
          imageQuality: 95,
        );
        return picked.map((f) => f.path).toList();
      } else {
        final XFile? file = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 95,
        );
        if (file == null) return const [];
        return [file.path];
      }
    } catch (e) {
      debugPrint('MobilePhotoImportPlatformDelegate error: $e');
      return const [];
    }
  }
}

/// Service managing cross-platform photo selection, format validation,
/// safe persistent copying into app storage, and metadata updates.
class PhotoImportService {
  PhotoImportService({
    PhotoImportPlatformDelegate? platformDelegate,
    PersistentDailyPhotoStore? store,
  }) : _delegate = platformDelegate ?? defaultDelegate(),
       _store = store ?? PersistentDailyPhotoStore.instance;

  final PhotoImportPlatformDelegate _delegate;
  final PersistentDailyPhotoStore _store;

  static PhotoImportPlatformDelegate defaultDelegate() {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return const WindowsPhotoImportPlatformDelegate();
    }
    return MobilePhotoImportPlatformDelegate();
  }

  static const Set<String> _allowedExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
  };

  /// Validates that [filePath] exists, has non-zero size, has an allowed extension,
  /// and contains valid image header magic bytes without loading the entire image into memory.
  bool validateImageFile(String filePath) {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return false;
      final size = file.lengthSync();
      if (size <= 0) return false;

      final ext = p.extension(filePath).toLowerCase();
      if (!_allowedExtensions.contains(ext)) return false;

      // Verify magic header bytes without full decode
      final bytes = file.openSync(mode: FileMode.read);
      try {
        final header = bytes.readSync(12);
        if (header.length < 4) return false;

        // JPEG: 0xFF, 0xD8
        if (header[0] == 0xFF && header[1] == 0xD8) return true;

        // PNG: 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
        if (header.length >= 8 &&
            header[0] == 0x89 &&
            header[1] == 0x50 &&
            header[2] == 0x4E &&
            header[3] == 0x47) {
          return true;
        }

        // BMP: 'B', 'M' (0x42, 0x4D)
        if (header[0] == 0x42 && header[1] == 0x4D) return true;

        // WEBP: 'RIFF'....'WEBP'
        if (header.length >= 12 &&
            header[0] == 0x52 &&
            header[1] == 0x49 &&
            header[2] == 0x46 &&
            header[3] == 0x46 &&
            header[8] == 0x57 &&
            header[9] == 0x45 &&
            header[10] == 0x42 &&
            header[11] == 0x50) {
          return true;
        }

        return false;
      } finally {
        bytes.closeSync();
      }
    } catch (e) {
      debugPrint('Error validating image file $filePath: $e');
      return false;
    }
  }

  /// Prompts user to select photos from their system and imports them for [dateKey].
  ///
  /// If [explicitPaths] is provided, imports those files directly without opening a picker.
  /// If the user cancels the picker, returns [PhotoImportResult.cancelled()] without creating empty entries.
  ///
  /// Each valid photo is copied into the app's persistent storage via [_store.addPhotoToDay],
  /// preserving existing memories, stable IDs, and shared daily notes.
  Future<PhotoImportResult> importPhotosForDay({
    required DateKey dateKey,
    List<String>? explicitPaths,
    bool allowMultiple = true,
  }) async {
    final List<String> paths;
    if (explicitPaths != null) {
      paths = explicitPaths;
    } else {
      paths = await _delegate.pickPhotoFiles(allowMultiple: allowMultiple);
    }

    if (paths.isEmpty) {
      return PhotoImportResult.cancelled();
    }

    final List<PhotoEntry> imported = [];
    final List<String> failed = [];

    for (final rawPath in paths) {
      if (!validateImageFile(rawPath)) {
        failed.add(rawPath);
        continue;
      }

      final now = DateTime.now();
      final period = now.hour >= 12 ? 'PM' : 'AM';
      final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
      final minuteFormatted = now.minute.toString().padLeft(2, '0');
      final formattedTime = '$hour12:$minuteFormatted $period';

      final newPhoto = PhotoEntry(
        date: dateKey.toDateTime(hour: now.hour, minute: now.minute),
        title: imported.isEmpty ? 'Daily Capture' : 'Photo Memory',
        location: kIsWeb || (!Platform.isAndroid && !Platform.isIOS)
            ? 'Imported from Computer'
            : 'Photo Library',
        timeFormatted: formattedTime,
        imagePath: rawPath,
        gradientColors: [AppColors.accent, AppColors.surfaceDark],
      );

      try {
        final savedPhoto = await _store.addPhotoToDay(
          dateKey: dateKey,
          photo: newPhoto,
          sourceTempPath: rawPath,
        );
        imported.add(savedPhoto);
      } catch (e) {
        debugPrint('Failed to persist imported photo $rawPath: $e');
        failed.add(rawPath);
      }
    }

    if (imported.isEmpty && failed.isNotEmpty) {
      return PhotoImportResult.failure(
        'Unable to import selected file(s). Files may be corrupted, empty, or unsupported format.',
        failed,
      );
    }

    return PhotoImportResult(
      importedPhotos: imported,
      importedCount: imported.length,
      failedFiles: failed,
    );
  }
}
