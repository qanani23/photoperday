import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_per_day/services/photo_import_service.dart';

/// Lightweight service abstracting photo gallery and desktop file picking.
///
/// Encapsulates [PhotoImportService] and [ImagePicker] to allow clean separation
/// between UI widgets and native platform photo picker APIs, supporting dependency
/// injection for tests and cross-platform Windows/Android execution.
class GalleryPhotoService {
  GalleryPhotoService({
    ImagePicker? imagePicker,
    PhotoImportService? importService,
  }) : _imagePicker = imagePicker,
       _importService =
           importService ??
           PhotoImportService(
             platformDelegate: imagePicker != null
                 ? MobilePhotoImportPlatformDelegate(imagePicker: imagePicker)
                 : PhotoImportService.defaultDelegate(),
           );

  final ImagePicker? _imagePicker;
  final PhotoImportService _importService;

  PhotoImportService get importService => _importService;

  /// Prompts the user to select one photo from their device photo library or computer.
  ///
  /// Returns the selected file path [String], or `null` if the user cancels
  /// or no photo is selected. Handles permission rejections and platform errors
  /// gracefully without throwing or crashing.
  Future<String?> pickPhoto() async {
    if (_imagePicker != null) {
      try {
        final XFile? selectedFile = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 95,
        );

        if (selectedFile == null) {
          debugPrint('Gallery photo selection cancelled by user.');
          return null;
        }

        return selectedFile.path;
      } on PlatformException catch (e) {
        debugPrint(
          'PlatformException while picking photo from gallery: ${e.code} - ${e.message}',
        );
        return null;
      } catch (e) {
        debugPrint('Unexpected error while picking photo from gallery: $e');
        return null;
      }
    }

    final photos = await pickPhotos(allowMultiple: false);
    return photos.isNotEmpty ? photos.first : null;
  }

  /// Prompts the user to select one or multiple photos from their device photo library or computer.
  Future<List<String>> pickPhotos({bool allowMultiple = true}) async {
    if (_imagePicker != null) {
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
        debugPrint('Error picking photos: $e');
        return const [];
      }
    }

    final delegate = PhotoImportService.defaultDelegate();
    return await delegate.pickPhotoFiles(allowMultiple: allowMultiple);
  }
}
