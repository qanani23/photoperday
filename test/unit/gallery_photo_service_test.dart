import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_per_day/services/gallery_photo_service.dart';

class FakeImagePicker extends ImagePicker {
  FakeImagePicker({
    this.mockResultPath,
    this.mockPlatformException,
    this.mockGenericException,
  });

  final String? mockResultPath;
  final PlatformException? mockPlatformException;
  final Exception? mockGenericException;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    if (mockPlatformException != null) {
      throw mockPlatformException!;
    }
    if (mockGenericException != null) {
      throw mockGenericException!;
    }
    if (mockResultPath != null) {
      return XFile(mockResultPath!);
    }
    return null;
  }
}

void main() {
  group('GalleryPhotoService', () {
    test('returns file path on successful gallery selection', () async {
      final fakePicker = FakeImagePicker(
        mockResultPath: '/storage/emulated/0/DCIM/Camera/IMG_20260315.jpg',
      );
      final service = GalleryPhotoService(imagePicker: fakePicker);

      final path = await service.pickPhoto();
      expect(path, '/storage/emulated/0/DCIM/Camera/IMG_20260315.jpg');
    });

    test('returns null when user cancels gallery picker', () async {
      final fakePicker = FakeImagePicker(mockResultPath: null);
      final service = GalleryPhotoService(imagePicker: fakePicker);

      final path = await service.pickPhoto();
      expect(path, isNull);
    });

    test(
      'catches PlatformException (e.g. permission denied) and returns null safely',
      () async {
        final fakePicker = FakeImagePicker(
          mockPlatformException: PlatformException(
            code: 'photo_access_denied',
            message: 'The user denied photo library access.',
          ),
        );
        final service = GalleryPhotoService(imagePicker: fakePicker);

        final path = await service.pickPhoto();
        expect(path, isNull);
      },
    );

    test('catches unexpected exceptions and returns null safely', () async {
      final fakePicker = FakeImagePicker(
        mockGenericException: Exception('Disk read error'),
      );
      final service = GalleryPhotoService(imagePicker: fakePicker);

      final path = await service.pickPhoto();
      expect(path, isNull);
    });
  });
}
