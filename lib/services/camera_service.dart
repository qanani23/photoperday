import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Status of the camera controller initialization.
enum CameraStatus {
  uninitialized,
  initializing,
  ready,
  permissionDenied,
  error,
}

/// Lightweight service abstracting camera hardware discovery, controller lifecycle,
/// flash settings, lens flipping, and photo capture.
class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  CameraStatus _status = CameraStatus.uninitialized;
  String? _errorMessage;

  CameraController? get controller => _controller;
  List<CameraDescription> get cameras => _cameras;
  CameraStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isReady =>
      _status == CameraStatus.ready &&
      _controller != null &&
      _controller!.value.isInitialized;
  bool get hasMultipleCameras => _cameras.length > 1;

  CameraLensDirection get currentLensDirection {
    if (_cameras.isEmpty || _selectedCameraIndex >= _cameras.length) {
      return CameraLensDirection.back;
    }
    return _cameras[_selectedCameraIndex].lensDirection;
  }

  /// Discovers available cameras and initializes the primary (back) camera.
  Future<void> initialize() async {
    _status = CameraStatus.initializing;
    _errorMessage = null;

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _status = CameraStatus.error;
        _errorMessage = 'No camera hardware found on this device.';
        return;
      }

      // Default to the first back camera if available
      _selectedCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (_selectedCameraIndex == -1) {
        _selectedCameraIndex = 0;
      }

      await _initController(_cameras[_selectedCameraIndex]);
    } on CameraException catch (e) {
      _handleCameraException(e);
    } catch (e) {
      _status = CameraStatus.error;
      _errorMessage =
          'An unexpected error occurred while accessing the camera: $e';
    }
  }

  Future<void> _initController(CameraDescription cameraDescription) async {
    await _controller?.dispose();

    final newController = CameraController(
      cameraDescription,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _controller = newController;

    try {
      await newController.initialize();
      _status = CameraStatus.ready;
      _errorMessage = null;
    } on CameraException catch (e) {
      _handleCameraException(e);
    }
  }

  void _handleCameraException(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        _status = CameraStatus.permissionDenied;
        _errorMessage =
            'Camera access was denied. Please grant permission in settings to take photos.';
        break;
      default:
        _status = CameraStatus.error;
        _errorMessage =
            e.description ?? 'Camera initialization failed (${e.code}).';
        break;
    }
  }

  /// Switches between front and back camera lenses.
  Future<void> switchCamera() async {
    if (_cameras.length <= 1) return;

    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    _status = CameraStatus.initializing;
    try {
      await _initController(_cameras[_selectedCameraIndex]);
    } catch (e) {
      _status = CameraStatus.error;
      _errorMessage = 'Failed to switch camera: $e';
    }
  }

  /// Captures a photo and returns the temporary [XFile] produced by the camera.
  Future<XFile?> takePicture() async {
    if (!isReady || _controller == null) {
      return null;
    }

    if (_controller!.value.isTakingPicture) {
      return null;
    }

    try {
      final XFile photo = await _controller!.takePicture();
      return photo;
    } on CameraException catch (e) {
      debugPrint('Error taking picture: ${e.code} - ${e.description}');
      return null;
    }
  }

  /// Disposes the underlying camera controller.
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
    _status = CameraStatus.uninitialized;
  }
}
