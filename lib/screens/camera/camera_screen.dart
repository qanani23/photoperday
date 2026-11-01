import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/services/camera_service.dart';

/// Full-screen minimal camera capture and photo review screen for "Photo a Day".
///
/// Supports cross-platform live preview, webcam switching, capture,
/// review before saving, retry/retake, and safe cancellation.
///
/// Returns the captured image file path as a [String] upon successful capture,
/// or `null` if the user cancels or navigates back.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.cameraService});

  /// Optional injected camera service for unit/widget testing.
  final CameraService? cameraService;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  late final CameraService _cameraService;
  bool _isCapturing = false;
  XFile? _capturedFile;
  bool _isReviewing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cameraService = widget.cameraService ?? CameraService();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    await _cameraService.initialize();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraService.controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _cameraService.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (!_isReviewing) {
        _initializeCamera();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    if (_isCapturing || !_cameraService.isReady) return;

    setState(() {
      _isCapturing = true;
    });

    HapticFeedback.mediumImpact();

    try {
      final XFile? file = await _cameraService.takePicture();
      if (file != null && mounted) {
        setState(() {
          _capturedFile = file;
          _isReviewing = true;
        });
        return;
      }
      if (file == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera capture failed. Please try again.'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error during capture: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to capture photo. Please try again.'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  void _retakePhoto() {
    if (_capturedFile != null) {
      try {
        final f = File(_capturedFile!.path);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } catch (_) {}
    }
    setState(() {
      _capturedFile = null;
      _isReviewing = false;
    });
  }

  void _confirmPhoto() {
    if (_capturedFile != null && mounted) {
      Navigator.of(context).pop(_capturedFile!.path);
    }
  }

  void _cancelCamera() {
    if (_capturedFile != null) {
      try {
        final f = File(_capturedFile!.path);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } catch (_) {}
    }
    if (mounted) {
      Navigator.of(context).pop(null);
    }
  }

  Future<void> _requestPermissionAgain() async {
    if (!kIsWeb && Platform.isWindows) {
      try {
        await Process.run('cmd', ['/c', 'start', 'ms-settings:privacy-webcam']);
      } catch (_) {}
      await _initializeCamera();
    } else {
      final status = await Permission.camera.request();
      if (status.isGranted) {
        _initializeCamera();
      } else if (status.isPermanentlyDenied) {
        await openAppSettings();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_isReviewing) {
            _retakePhoto();
          } else {
            _cancelCamera();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  // Main Camera Preview or Captured Review
                  Positioned.fill(
                    child: _isReviewing
                        ? _buildReviewBody()
                        : _buildCameraBody(),
                  ),

                  // Top Controls Header
                  Positioned(
                    top: 12.0,
                    left: AppSpacing.pageHorizontal,
                    right: AppSpacing.pageHorizontal,
                    child: _buildTopBar(),
                  ),

                  // Bottom Controls
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _isReviewing
                        ? _buildReviewBottomBar()
                        : (_cameraService.isReady
                              ? _buildBottomBar()
                              : const SizedBox.shrink()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraBody() {
    switch (_cameraService.status) {
      case CameraStatus.uninitialized:
      case CameraStatus.initializing:
        return _buildLoadingState();
      case CameraStatus.permissionDenied:
        return _buildPermissionDeniedState();
      case CameraStatus.error:
        return _buildErrorState();
      case CameraStatus.ready:
        return _buildCameraPreview();
    }
  }

  /// Live Camera Preview with Viewfinder Framing
  Widget _buildCameraPreview() {
    final controller = _cameraService.controller;
    if (controller == null || !controller.value.isInitialized) {
      return _buildLoadingState();
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        // Camera Texture
        Center(child: CameraPreview(controller)),

        // Subtle Viewfinder Focus Corners
        _buildViewfinderGuide(),
      ],
    );
  }

  /// Reviewing Captured Photo Before Saving
  Widget _buildReviewBody() {
    if (_capturedFile == null) {
      return const SizedBox.shrink();
    }
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Image.file(
        File(_capturedFile!.path),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(
            Icons.broken_image_rounded,
            color: Colors.white54,
            size: 48,
          ),
        ),
      ),
    );
  }

  /// Minimalist Viewfinder Framing
  Widget _buildViewfinderGuide() {
    return Center(
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24.0),
          decoration: BoxDecoration(
            borderRadius: AppRadii.card,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  /// Top Bar with Cancel / Lens Flip / Webcam Switch
  Widget _buildTopBar() {
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Cancel / Back Button
        Semantics(
          label: 'Close camera and return',
          button: true,
          child: Tooltip(
            message: 'Cancel',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _cancelCamera,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 48.0,
                  minHeight: 48.0,
                ),
                child: Center(
                  child: Container(
                    width: 44.0,
                    height: 44.0,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 0.8,
                      ),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 22.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Review Header indicator
        if (_isReviewing)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 6.0,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20.0),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 0.8,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.remove_red_eye_outlined,
                  color: Colors.white,
                  size: 16,
                ),
                SizedBox(width: 6),
                Text(
                  'Review Photo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

        // Camera Switcher / Flip Button (if multiple cameras available)
        if (!_isReviewing &&
            _cameraService.hasMultipleCameras &&
            _cameraService.isReady)
          isDesktop
              ? _buildDesktopCameraSelector()
              : _buildMobileCameraFlipper(),
      ],
    );
  }

  /// Dropdown menu for selecting webcams by hardware name on desktop
  Widget _buildDesktopCameraSelector() {
    return PopupMenuButton<int>(
      key: const ValueKey('camera_switch_button'),
      tooltip: 'Select Webcam',
      initialValue: _cameraService.selectedCameraIndex,
      onSelected: (int index) async {
        await _cameraService.selectCamera(index);
        if (mounted) setState(() {});
      },
      color: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      itemBuilder: (context) {
        return [
          for (int i = 0; i < _cameraService.cameras.length; i++)
            PopupMenuItem<int>(
              value: i,
              child: Row(
                children: [
                  Icon(
                    i == _cameraService.selectedCameraIndex
                        ? Icons.check_circle_rounded
                        : Icons.videocam_outlined,
                    size: 18.0,
                    color: i == _cameraService.selectedCameraIndex
                        ? AppColors.accent
                        : Colors.white70,
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    _cameraService.cameras[i].name.isNotEmpty
                        ? _cameraService.cameras[i].name
                        : 'Webcam ${i + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.0,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ];
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20.0),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_rounded, color: Colors.white, size: 16.0),
            const SizedBox(width: 6.0),
            Text(
              _cameraService.currentCameraName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4.0),
            const Icon(
              Icons.arrow_drop_down_rounded,
              color: Colors.white70,
              size: 18.0,
            ),
          ],
        ),
      ),
    );
  }

  /// Flip button for mobile cameras
  Widget _buildMobileCameraFlipper() {
    return Semantics(
      label: 'Flip camera lens',
      button: true,
      child: Tooltip(
        message: 'Flip Camera',
        child: GestureDetector(
          key: const ValueKey('camera_switch_button'),
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            HapticFeedback.selectionClick();
            await _cameraService.switchCamera();
            if (mounted) setState(() {});
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48.0, minHeight: 48.0),
            child: Center(
              child: Container(
                width: 44.0,
                height: 44.0,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 0.8,
                  ),
                ),
                child: const Icon(
                  Icons.flip_camera_ios_outlined,
                  color: Colors.white,
                  size: 20.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Shutter Bar
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.only(top: 20.0, bottom: 44.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
        ),
      ),
      child: Center(
        child: Semantics(
          label: 'Take daily photo',
          button: true,
          child: GestureDetector(
            key: const ValueKey('camera_shutter_button'),
            behavior: HitTestBehavior.opaque,
            onTap: _takePhoto,
            child: Container(
              width: 80.0,
              height: 80.0,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 4.0,
                ),
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _isCapturing ? 54.0 : 64.0,
                  height: _isCapturing ? 54.0 : 64.0,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: _isCapturing
                      ? Center(
                          child: SizedBox(
                            width: 24.0,
                            height: 24.0,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Review Action Bar (Retake vs Use Photo)
  Widget _buildReviewBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 44.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.90), Colors.transparent],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Retake Button
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('camera_retake_button'),
                  onPressed: _retakePhoto,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(vertical: 14.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 20.0),
                  label: const Text(
                    'Retake',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16.0),

              // Confirm / Use Photo Button
              Expanded(
                child: ElevatedButton.icon(
                  key: const ValueKey('camera_use_photo_button'),
                  onPressed: _confirmPhoto,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.check_rounded, size: 20.0),
                  label: const Text(
                    'Use Photo',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Clean Loading State
  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32.0,
            height: 32.0,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          ),
          SizedBox(height: AppSpacing.md),
          Text(
            'Opening camera...',
            style: TextStyle(
              fontSize: 14.0,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  /// Minimalist Permission Denied Card
  Widget _buildPermissionDeniedState() {
    final isWindows = !kIsWeb && Platform.isWindows;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440.0),
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.card,
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16.0,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60.0,
                height: 60.0,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(
                  Icons.no_photography_outlined,
                  size: 28.0,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Camera Access Required',
                style: TextStyle(
                  fontSize: 17.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8.0),
              Text(
                isWindows
                    ? 'Windows camera permission is turned off. To allow access:\n1. Open Windows Settings > Privacy & security > Camera.\n2. Turn on "Camera access" and "Let apps access your camera".'
                    : 'Photo a Day needs camera access to capture your single photo memory each day.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              Semantics(
                button: true,
                label: 'Grant camera permission',
                child: ElevatedButton(
                  onPressed: _requestPermissionAgain,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryButtonBackground,
                    foregroundColor: AppColors.primaryButtonForeground,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 13.0,
                    ),
                    minimumSize: const Size(48.0, 48.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    isWindows ? 'Grant Permission' : 'Grant Permission',
                    style: const TextStyle(
                      fontSize: 14.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Semantics(
                button: true,
                label: 'Cancel and return',
                child: TextButton(
                  onPressed: _cancelCamera,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48.0, 48.0),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Minimalist Camera Error State
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440.0),
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.card,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 36.0,
                color: Colors.redAccent,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Camera Unavailable',
                style: TextStyle(
                  fontSize: 17.0,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6.0),
              Text(
                _cameraService.errorMessage ??
                    'Unable to initialize camera preview.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 13.0,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Semantics(
                    button: true,
                    label: 'Cancel and return',
                    child: OutlinedButton(
                      onPressed: _cancelCamera,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20.0,
                          vertical: 11.0,
                        ),
                        minimumSize: const Size(48.0, 48.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.0),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Semantics(
                    button: true,
                    label: 'Retry opening camera',
                    child: ElevatedButton(
                      onPressed: _initializeCamera,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryButtonBackground,
                        foregroundColor: AppColors.primaryButtonForeground,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20.0,
                          vertical: 11.0,
                        ),
                        minimumSize: const Size(48.0, 48.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.0),
                        ),
                        elevation: 0,
                      ),
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
