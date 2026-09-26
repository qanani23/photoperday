import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Lightweight service abstracting photo gallery picking.
///
/// Encapsulates [ImagePicker] to allow clean separation between UI widgets
/// and native platform photo picker APIs, supporting dependency injection for tests.
class GalleryPhotoService {
  GalleryPhotoService({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  /// Prompts the user to select one photo from their device photo library.
  ///
  /// Returns the selected file path [String], or `null` if the user cancels
  /// or no photo is selected. Handles permission rejections and platform errors
  /// gracefully without throwing or crashing.
  Future<String?> pickPhoto() async {
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
}
