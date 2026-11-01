import 'dart:io';
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
/// flash settings, lens flipping, webcam selection, and photo capture across Android and Windows.
class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  CameraStatus _status = CameraStatus.uninitialized;
  String? _errorMessage;

  CameraController? get controller => _controller;
  List<CameraDescription> get cameras => _cameras;
  int get selectedCameraIndex => _selectedCameraIndex;
  CameraStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isReady =>
      _status == CameraStatus.ready &&
      _controller != null &&
      _controller!.value.isInitialized;
  bool get hasMultipleCameras => _cameras.length > 1;

  CameraDescription? get currentCamera =>
      _cameras.isNotEmpty && _selectedCameraIndex < _cameras.length
      ? _cameras[_selectedCameraIndex]
      : null;

  String get currentCameraName {
    final camera = currentCamera;
    if (camera == null) return 'Camera';
    if (camera.name.trim().isNotEmpty) return camera.name;
    return 'Camera ${_selectedCameraIndex + 1}';
  }

  CameraLensDirection get currentLensDirection {
    if (_cameras.isEmpty || _selectedCameraIndex >= _cameras.length) {
      return CameraLensDirection.back;
    }
    return _cameras[_selectedCameraIndex].lensDirection;
  }

  /// Discovers available cameras and initializes the default camera.
  Future<void> initialize() async {
    _status = CameraStatus.initializing;
    _errorMessage = null;

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _status = CameraStatus.error;
        _errorMessage = !kIsWeb && Platform.isWindows
            ? 'No webcam or camera hardware detected. Please connect a USB webcam and retry.'
            : 'No camera hardware found on this device.';
        return;
      }

      // Default to back camera on mobile if present, otherwise first available (e.g. webcam on Windows)
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
    } catch (e) {
      _status = CameraStatus.error;
      _errorMessage = 'Failed to initialize camera preview: $e';
    }
  }

  void _handleCameraException(CameraException e) {
    final isWindows = !kIsWeb && Platform.isWindows;
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
      case 'cameraNotFound':
      case 'noAvailableCameras':
        _status = CameraStatus.permissionDenied;
        _errorMessage = isWindows
            ? 'Camera access was denied by Windows. Please ensure camera access is enabled in Windows Settings > Privacy & security > Camera.'
            : 'Camera access was denied. Please grant permission in settings to take photos.';
        break;
      case 'CameraInUse':
      case 'cameraInUse':
        _status = CameraStatus.error;
        _errorMessage =
            'The selected camera is currently in use by another application. Please close other camera apps and retry.';
        break;
      default:
        _status = CameraStatus.error;
        _errorMessage =
            e.description ?? 'Camera initialization failed (${e.code}).';
        break;
    }
  }

  /// Switches to the specific camera at [index].
  Future<void> selectCamera(int index) async {
    if (index < 0 || index >= _cameras.length) return;
    if (_selectedCameraIndex == index && isReady) return;

    _selectedCameraIndex = index;
    _status = CameraStatus.initializing;
    try {
      await _initController(_cameras[_selectedCameraIndex]);
    } catch (e) {
      _status = CameraStatus.error;
      _errorMessage = 'Failed to switch camera: $e';
    }
  }

  /// Switches between available cameras sequentially.
  Future<void> switchCamera() async {
    if (_cameras.length <= 1) return;
    final nextIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await selectCamera(nextIndex);
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
