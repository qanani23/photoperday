import 'package:flutter/material.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:url_launcher/url_launcher.dart';

/// Semantic feedback category supported by Daria.
enum FeedbackCategory {
  /// User reporting a malfunction, glitch, or unexpected behavior.
  bugReport('bug_report', 'Report a Bug'),

  /// User proposing an enhancement, new capability, or design improvement.
  featureRequest('feature_request', 'Suggest a Feature'),

  /// User sharing questions, reflections, or general feedback.
  generalFeedback('general_feedback', 'General Feedback');

  const FeedbackCategory(this.queryValue, this.displayName);

  /// The parameter value passed to the Tally form URL query parameter (`?category=...`).
  final String queryValue;

  /// User-facing display title for this feedback option.
  final String displayName;
}

/// Abstract delegate decoupling URL launching mechanism for unit and widget testing.
abstract class UrlLauncherDelegate {
  Future<bool> launch(Uri uri);
}

/// Production implementation of [UrlLauncherDelegate] using `url_launcher`.
class DefaultUrlLauncherDelegate implements UrlLauncherDelegate {
  const DefaultUrlLauncherDelegate();

  @override
  Future<bool> launch(Uri uri) async {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Service managing the Daria Feedback & Support integration with Tally Forms.
///
/// Features:
/// - Centralized Tally Form URL configuration.
/// - Query parameter category pre-filling (`?category=bug_report`, etc.).
/// - Pluggable [UrlLauncherDelegate] for deterministic testing.
/// - In-flight launch debouncing to prevent duplicate browser windows on rapid clicks.
/// - Non-intrusive error surfacing via floating snackbars without interrupting user navigation.
class FeedbackService {
  FeedbackService({UrlLauncherDelegate? delegate})
    : _delegate = delegate ?? const DefaultUrlLauncherDelegate();

  static FeedbackService _instance = FeedbackService();

  /// Global singleton instance.
  static FeedbackService get instance => _instance;

  @visibleForTesting
  static void setTestInstance(FeedbackService testInstance) {
    _instance = testInstance;
  }

  @visibleForTesting
  static void resetTestInstance() {
    _instance = FeedbackService();
  }

  UrlLauncherDelegate _delegate;

  @visibleForTesting
  void setDelegate(UrlLauncherDelegate delegate) {
    _delegate = delegate;
  }

  bool _isLaunching = false;
  DateTime? _lastLaunchTime;

  /// Whether a feedback launch is currently being processed.
  bool get isLaunching => _isLaunching;

  /// Builds the complete [Uri] pointing to the centralized Tally form,
  /// appending the selected [category] query parameter if provided.
  static Uri buildFeedbackUri({FeedbackCategory? category}) {
    final baseUri = Uri.parse(AppConstants.tallyFeedbackUrl);
    if (category == null) {
      return baseUri;
    }
    return baseUri.replace(
      queryParameters: {
        ...baseUri.queryParameters,
        'category': category.queryValue,
      },
    );
  }

  /// Opens the feedback form in the user's default external browser.
  ///
  /// - Passes the [category] as a URL query parameter for Tally hidden field prefilling.
  /// - Debounces rapid repeated calls (cooldown: 600ms).
  /// - If launch fails, displays a calm floating [SnackBar] notifying the user
  ///   without interrupting screen navigation.
  Future<bool> launchFeedback({
    FeedbackCategory? category,
    BuildContext? context,
  }) async {
    final now = DateTime.now();
    if (_isLaunching) {
      debugPrint(
        'Feedback launch already in progress; ignoring duplicate attempt.',
      );
      return false;
    }

    if (_lastLaunchTime != null &&
        now.difference(_lastLaunchTime!).inMilliseconds < 600) {
      debugPrint('Feedback launch debounced; rapid repeated tap ignored.');
      return false;
    }

    _isLaunching = true;
    _lastLaunchTime = now;

    try {
      final uri = buildFeedbackUri(category: category);
      final success = await _delegate.launch(uri);

      if (!success && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open feedback form in browser. Please visit https://tally.so/r/perLYE',
            ),
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return success;
    } catch (e) {
      debugPrint('Error launching feedback form: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open feedback form in browser. Please visit https://tally.so/r/perLYE',
            ),
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    } finally {
      _isLaunching = false;
    }
  }
}
