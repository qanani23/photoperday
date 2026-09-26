import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';
import 'package:photo_per_day/services/camera_service.dart';

class FakeCameraService extends CameraService {
  FakeCameraService({
    this.mockStatus = CameraStatus.permissionDenied,
    this.mockErrorMessage,
  });

  CameraStatus mockStatus;
  String? mockErrorMessage;

  @override
  CameraStatus get status => mockStatus;

  @override
  String? get errorMessage => mockErrorMessage;

  @override
  bool get isReady => mockStatus == CameraStatus.ready;

  @override
  Future<void> initialize() async {
    // Retain mockStatus
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('CameraScreen Widget Tests', () {
    testWidgets('renders loading state while camera initializes', (
      WidgetTester tester,
    ) async {
      final fakeService = FakeCameraService(
        mockStatus: CameraStatus.initializing,
      );

      await tester.pumpWidget(
        MaterialApp(home: CameraScreen(cameraService: fakeService)),
      );

      expect(find.text('Opening camera...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets(
      'renders permission denied card with Grant and Cancel options',
      (WidgetTester tester) async {
        final fakeService = FakeCameraService(
          mockStatus: CameraStatus.permissionDenied,
        );

        await tester.pumpWidget(
          MaterialApp(home: CameraScreen(cameraService: fakeService)),
        );
        await tester.pump();

        expect(find.text('Camera Access Required'), findsOneWidget);
        expect(find.text('Grant Permission'), findsOneWidget);
        expect(find.text('Cancel'), findsWidgets);
      },
    );

    testWidgets(
      'renders camera error card with error message and Retry action',
      (WidgetTester tester) async {
        final fakeService = FakeCameraService(
          mockStatus: CameraStatus.error,
          mockErrorMessage: 'No camera hardware found on this device.',
        );

        await tester.pumpWidget(
          MaterialApp(home: CameraScreen(cameraService: fakeService)),
        );
        await tester.pump();

        expect(find.text('Camera Unavailable'), findsOneWidget);
        expect(
          find.text('No camera hardware found on this device.'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
      },
    );

    testWidgets('cancel button pops camera screen', (
      WidgetTester tester,
    ) async {
      final fakeService = FakeCameraService(
        mockStatus: CameraStatus.permissionDenied,
      );

      bool popped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        CameraScreen(cameraService: fakeService),
                  ),
                );
                popped = true;
              },
              child: const Text('Open Camera'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Camera'));
      await tester.pumpAndSettle();

      expect(find.byType(CameraScreen), findsOneWidget);

      // Tap the Cancel button in the permission denied card
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      expect(find.byType(CameraScreen), findsNothing);
      expect(popped, isTrue);
    });
  });
}
