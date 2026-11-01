import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';
import 'package:photo_per_day/services/camera_service.dart';
import 'package:photo_per_day/widgets/app_scaffold.dart';
import 'package:photo_per_day/widgets/bottom_nav_dock.dart';
import 'package:photo_per_day/widgets/photo_source_sheet.dart';

class _MockReviewableCameraService extends CameraService {
  _MockReviewableCameraService({this.capturedPathToReturn});

  final List<CameraDescription> mockCameras = const [
    CameraDescription(
      name: 'HP TrueVision HD Camera',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 0,
    ),
    CameraDescription(
      name: 'OBS Virtual Camera',
      lensDirection: CameraLensDirection.external,
      sensorOrientation: 0,
    ),
  ];
  final String? capturedPathToReturn;
  int _index = 0;

  @override
  List<CameraDescription> get cameras => mockCameras;

  @override
  int get selectedCameraIndex => _index;

  @override
  bool get hasMultipleCameras => mockCameras.length > 1;

  @override
  CameraDescription? get currentCamera =>
      mockCameras.isNotEmpty ? mockCameras[_index] : null;

  @override
  String get currentCameraName => currentCamera?.name ?? 'Camera';

  @override
  CameraStatus get status => CameraStatus.ready;

  @override
  bool get isReady => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> selectCamera(int index) async {
    _index = index;
  }

  @override
  Future<void> switchCamera() async {
    _index = (_index + 1) % mockCameras.length;
  }

  @override
  Future<XFile?> takePicture() async {
    if (capturedPathToReturn != null) {
      return XFile(capturedPathToReturn!);
    }
    return null;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M64 — Desktop Camera, Review, and UI Tests', () {
    late File dummyCapturedFile;

    setUp(() {
      dummyCapturedFile = File('${Directory.systemTemp.path}/test_capture.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]);
    });

    tearDown(() {
      try {
        if (dummyCapturedFile.existsSync()) {
          dummyCapturedFile.deleteSync();
        }
      } catch (_) {}
    });

    testWidgets(
      '1. Camera capture enters review state with Retake and Use Photo actions',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeService = _MockReviewableCameraService(
          capturedPathToReturn: dummyCapturedFile.path,
        );

        String? capturedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  capturedResult = await Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (_) => CameraScreen(cameraService: fakeService),
                    ),
                  );
                },
                child: const Text('Open Camera'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Camera'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(CameraScreen), findsOneWidget);

        // Verify shutter button is present
        final shutterFinder = find.byKey(
          const ValueKey('camera_shutter_button'),
        );
        expect(shutterFinder, findsOneWidget);

        // Tap Shutter
        await tester.tap(shutterFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Should now be in Review Photo mode
        expect(find.text('Review Photo'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('camera_retake_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('camera_use_photo_button')),
          findsOneWidget,
        );

        // Tap Retake
        await tester.tap(find.byKey(const ValueKey('camera_retake_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Returns back to live camera preview
        expect(find.text('Review Photo'), findsNothing);
        expect(shutterFinder, findsOneWidget);

        // Take photo again and confirm
        await tester.tap(shutterFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Review Photo'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('camera_use_photo_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));

        // Screen is popped and result returned
        expect(find.byType(CameraScreen), findsNothing);
        expect(capturedResult, dummyCapturedFile.path);
      },
    );

    testWidgets('2. PhotoSourceSheet renders options and closes on Escape', (
      WidgetTester tester,
    ) async {
      PhotoSource? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selected = await PhotoSourceSheet.show(context);
              },
              child: const Text('Show Sheet'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Add Daily Photo'), findsOneWidget);
      expect(find.text('Take Photo'), findsOneWidget);

      // Dismiss with Escape key
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Add Daily Photo'), findsNothing);
      expect(selected, isNull);
    });

    testWidgets(
      '3. AppScaffold applies responsive desktop constraints to body and bottom dock',
      (WidgetTester tester) async {
        // Set wide desktop monitor resolution (1920x1080)
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: AppScaffold(
              body: Container(
                key: const ValueKey('desktop_body'),
                color: Colors.blue,
                child: const Text('Desktop Content'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Body should be constrained within 840px max width
        final bodyBox = tester.renderObject<RenderBox>(
          find.byKey(const ValueKey('desktop_body')),
        );
        expect(bodyBox.size.width, lessThanOrEqualTo(840.0));

        // Dock should be constrained within 440px max width
        final dockBox = tester.renderObject<RenderBox>(
          find.byType(BottomNavDock),
        );
        expect(dockBox.size.width, lessThanOrEqualTo(440.0));
      },
    );
  });
}
