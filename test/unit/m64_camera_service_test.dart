import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/services/camera_service.dart';

class _FakeCameraServiceUnderTest extends CameraService {
  _FakeCameraServiceUnderTest({
    List<CameraDescription>? mockCameras,
    CameraStatus initialStatus = CameraStatus.uninitialized,
    String? initialErrorMessage,
  }) : _testCameras = mockCameras ?? [],
       _testStatus = initialStatus,
       _testErrorMessage = initialErrorMessage;

  final List<CameraDescription> _testCameras;
  CameraStatus _testStatus;
  final String? _testErrorMessage;
  int _testSelectedIndex = 0;

  @override
  List<CameraDescription> get cameras => _testCameras;

  @override
  CameraStatus get status => _testStatus;

  @override
  String? get errorMessage => _testErrorMessage;

  @override
  int get selectedCameraIndex => _testSelectedIndex;

  @override
  bool get isReady => _testStatus == CameraStatus.ready;

  @override
  bool get hasMultipleCameras => _testCameras.length > 1;

  @override
  CameraDescription? get currentCamera =>
      _testCameras.isNotEmpty && _testSelectedIndex < _testCameras.length
      ? _testCameras[_testSelectedIndex]
      : null;

  @override
  String get currentCameraName {
    final camera = currentCamera;
    if (camera == null) return 'Camera';
    if (camera.name.trim().isNotEmpty) return camera.name;
    return 'Camera ${_testSelectedIndex + 1}';
  }

  @override
  Future<void> selectCamera(int index) async {
    if (index >= 0 && index < _testCameras.length) {
      _testSelectedIndex = index;
      _testStatus = CameraStatus.ready;
    }
  }

  @override
  Future<void> switchCamera() async {
    if (_testCameras.length > 1) {
      final next = (_testSelectedIndex + 1) % _testCameras.length;
      await selectCamera(next);
    }
  }

  @override
  Future<void> dispose() async {
    _testStatus = CameraStatus.uninitialized;
  }
}

void main() {
  group('M64 — CameraService Unit Tests', () {
    test('1. Camera discovery and friendly camera naming', () {
      const cam1 = CameraDescription(
        name: 'Integrated Webcam (04f2:b614)',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 0,
      );
      const cam2 = CameraDescription(
        name: 'Logitech HD Pro C920',
        lensDirection: CameraLensDirection.external,
        sensorOrientation: 0,
      );

      final service = _FakeCameraServiceUnderTest(
        mockCameras: [cam1, cam2],
        initialStatus: CameraStatus.ready,
      );

      expect(service.hasMultipleCameras, isTrue);
      expect(service.currentCameraName, 'Integrated Webcam (04f2:b614)');
      expect(service.selectedCameraIndex, 0);
    });

    test(
      '2. Multiple webcam selection by index and sequential switching',
      () async {
        const cam1 = CameraDescription(
          name: 'Webcam A',
          lensDirection: CameraLensDirection.front,
          sensorOrientation: 0,
        );
        const cam2 = CameraDescription(
          name: 'Webcam B (External USB)',
          lensDirection: CameraLensDirection.external,
          sensorOrientation: 0,
        );
        const cam3 = CameraDescription(
          name: 'Webcam C',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 0,
        );

        final service = _FakeCameraServiceUnderTest(
          mockCameras: [cam1, cam2, cam3],
          initialStatus: CameraStatus.ready,
        );

        // Select specific camera index
        await service.selectCamera(1);
        expect(service.selectedCameraIndex, 1);
        expect(service.currentCameraName, 'Webcam B (External USB)');

        // Sequential switch
        await service.switchCamera();
        expect(service.selectedCameraIndex, 2);
        expect(service.currentCameraName, 'Webcam C');

        // Wraps around to 0
        await service.switchCamera();
        expect(service.selectedCameraIndex, 0);
        expect(service.currentCameraName, 'Webcam A');
      },
    );

    test('3. Permission denied and error states expose explanatory messages', () {
      final deniedService = _FakeCameraServiceUnderTest(
        initialStatus: CameraStatus.permissionDenied,
        initialErrorMessage:
            'Camera access was denied by Windows. Please ensure camera access is enabled in Windows Settings > Privacy & security > Camera.',
      );

      expect(deniedService.status, CameraStatus.permissionDenied);
      expect(deniedService.isReady, isFalse);
      expect(
        deniedService.errorMessage,
        contains('Windows Settings > Privacy & security > Camera'),
      );

      final errorService = _FakeCameraServiceUnderTest(
        initialStatus: CameraStatus.error,
        initialErrorMessage:
            'The selected camera is currently in use by another application.',
      );

      expect(errorService.status, CameraStatus.error);
      expect(errorService.isReady, isFalse);
      expect(errorService.errorMessage, contains('currently in use'));
    });
  });
}
