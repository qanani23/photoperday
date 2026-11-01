import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/data/services/feedback_service.dart';

class MockUrlLauncherDelegate implements UrlLauncherDelegate {
  final List<Uri> launchedUris = [];
  bool shouldSucceed = true;
  Exception? exceptionToThrow;

  @override
  Future<bool> launch(Uri uri) async {
    if (exceptionToThrow != null) {
      throw exceptionToThrow!;
    }
    launchedUris.add(uri);
    return shouldSucceed;
  }
}

void main() {
  late MockUrlLauncherDelegate mockDelegate;
  late FeedbackService feedbackService;

  setUp(() {
    mockDelegate = MockUrlLauncherDelegate();
    feedbackService = FeedbackService(delegate: mockDelegate);
    FeedbackService.setTestInstance(feedbackService);
  });

  tearDown(() {
    FeedbackService.resetTestInstance();
  });

  group('FeedbackCategory Model Tests', () {
    test(
      'Categories have correct query parameter values and display names',
      () {
        expect(FeedbackCategory.bugReport.queryValue, 'bug_report');
        expect(FeedbackCategory.bugReport.displayName, 'Report a Bug');

        expect(FeedbackCategory.featureRequest.queryValue, 'feature_request');
        expect(
          FeedbackCategory.featureRequest.displayName,
          'Suggest a Feature',
        );

        expect(FeedbackCategory.generalFeedback.queryValue, 'general_feedback');
        expect(
          FeedbackCategory.generalFeedback.displayName,
          'General Feedback',
        );
      },
    );
  });

  group('Centralized Tally URL & URI Builder Tests', () {
    test('All feedback options rely strictly on centralized Tally URL', () {
      expect(AppConstants.tallyFeedbackUrl, 'https://tally.so/r/perLYE');

      final baseUri = FeedbackService.buildFeedbackUri();
      expect(baseUri.toString(), 'https://tally.so/r/perLYE');
    });

    test('buildFeedbackUri appends category query parameter accurately', () {
      final bugUri = FeedbackService.buildFeedbackUri(
        category: FeedbackCategory.bugReport,
      );
      expect(bugUri.queryParameters['category'], 'bug_report');
      expect(
        bugUri.toString(),
        'https://tally.so/r/perLYE?category=bug_report',
      );

      final featureUri = FeedbackService.buildFeedbackUri(
        category: FeedbackCategory.featureRequest,
      );
      expect(featureUri.queryParameters['category'], 'feature_request');
      expect(
        featureUri.toString(),
        'https://tally.so/r/perLYE?category=feature_request',
      );

      final generalUri = FeedbackService.buildFeedbackUri(
        category: FeedbackCategory.generalFeedback,
      );
      expect(generalUri.queryParameters['category'], 'general_feedback');
      expect(
        generalUri.toString(),
        'https://tally.so/r/perLYE?category=general_feedback',
      );
    });
  });

  group('External Link Launching & Debounce Tests', () {
    test(
      'launchFeedback opens the external browser with the specified category',
      () async {
        final result = await feedbackService.launchFeedback(
          category: FeedbackCategory.bugReport,
        );

        expect(result, isTrue);
        expect(mockDelegate.launchedUris.length, 1);
        expect(
          mockDelegate.launchedUris.first,
          Uri.parse('https://tally.so/r/perLYE?category=bug_report'),
        );
      },
    );

    test(
      'Rapid repeated taps do not trigger duplicate launch attempts (debounce lock)',
      () async {
        // First tap should succeed
        final firstLaunch = await feedbackService.launchFeedback(
          category: FeedbackCategory.featureRequest,
        );
        expect(firstLaunch, isTrue);
        expect(mockDelegate.launchedUris.length, 1);

        // Immediate second tap (within 600ms cooldown) must be debounced
        final secondLaunch = await feedbackService.launchFeedback(
          category: FeedbackCategory.featureRequest,
        );
        expect(secondLaunch, isFalse);
        expect(mockDelegate.launchedUris.length, 1); // Still 1, no duplicate
      },
    );

    test(
      'Launch failure is returned gracefully without throwing exceptions',
      () async {
        mockDelegate.shouldSucceed = false;

        final result = await feedbackService.launchFeedback(
          category: FeedbackCategory.generalFeedback,
        );

        expect(result, isFalse);
        expect(mockDelegate.launchedUris.length, 1);
      },
    );

    test(
      'Exceptions during launch are caught and handled gracefully',
      () async {
        mockDelegate.exceptionToThrow = Exception('Platform channel failed');

        final result = await feedbackService.launchFeedback(
          category: FeedbackCategory.bugReport,
        );

        expect(result, isFalse);
      },
    );
  });
}
