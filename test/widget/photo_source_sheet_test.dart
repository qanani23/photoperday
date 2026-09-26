import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/widgets/photo_source_sheet.dart';

void main() {
  group('PhotoSourceSheet Widget Tests', () {
    testWidgets('renders header, options, and cancel button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PhotoSourceSheet())),
      );

      expect(find.text('Add Daily Photo'), findsOneWidget);
      expect(
        find.text("Choose how you'd like to capture today's memory"),
        findsOneWidget,
      );
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Choose from Gallery'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('tapping Take Photo returns PhotoSource.camera', (
      WidgetTester tester,
    ) async {
      PhotoSource? selectedSource;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedSource = await PhotoSourceSheet.show(context);
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.byType(PhotoSourceSheet), findsOneWidget);

      await tester.tap(find.text('Take Photo'));
      await tester.pumpAndSettle();

      expect(find.byType(PhotoSourceSheet), findsNothing);
      expect(selectedSource, PhotoSource.camera);
    });

    testWidgets('tapping Choose from Gallery returns PhotoSource.gallery', (
      WidgetTester tester,
    ) async {
      PhotoSource? selectedSource;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedSource = await PhotoSourceSheet.show(context);
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.byType(PhotoSourceSheet), findsOneWidget);

      await tester.tap(find.text('Choose from Gallery'));
      await tester.pumpAndSettle();

      expect(find.byType(PhotoSourceSheet), findsNothing);
      expect(selectedSource, PhotoSource.gallery);
    });

    testWidgets('tapping Cancel dismisses sheet with null', (
      WidgetTester tester,
    ) async {
      PhotoSource? selectedSource = PhotoSource.camera;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedSource = await PhotoSourceSheet.show(context);
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.byType(PhotoSourceSheet), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(PhotoSourceSheet), findsNothing);
      expect(selectedSource, isNull);
    });
  });
}
