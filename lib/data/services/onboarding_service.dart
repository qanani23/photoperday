import 'package:flutter/foundation.dart';
import 'package:photo_per_day/data/services/onboarding_storage.dart';

/// Central domain service managing onboarding state and completion status.
class OnboardingService extends ChangeNotifier {
  OnboardingService({OnboardingStorage? storage})
    : _storage = storage ?? OnboardingStorage();

  static OnboardingService _instance = OnboardingService();

  /// Global singleton instance.
  static OnboardingService get instance => _instance;

  @visibleForTesting
  static void setTestInstance(OnboardingService testInstance) {
    _instance = testInstance;
  }

  @visibleForTesting
  static void resetTestInstance() {
    try {
      _instance.dispose();
    } catch (_) {}
    _instance = OnboardingService();
  }

  OnboardingStorage _storage;
  bool _hasCompletedOnboarding = true; // Sane default before explicit init
  bool _isInitialized = false;

  /// Whether onboarding has been completed by the user.
  bool get hasCompletedOnboarding => _hasCompletedOnboarding;

  /// Whether the service has been initialized from persistent storage.
  bool get isInitialized => _isInitialized;

  /// Initializes the service from disk. Fresh install defaults to false.
  Future<void> init({OnboardingStorage? storage}) async {
    if (storage != null) _storage = storage;
    _hasCompletedOnboarding = await _storage.loadCompleted();
    _isInitialized = true;
    notifyListeners();
  }

  /// Marks onboarding as completed and persists to disk.
  Future<void> completeOnboarding() async {
    _hasCompletedOnboarding = true;
    await _storage.saveCompleted(completed: true);
    notifyListeners();
  }

  /// Resets onboarding status (e.g. for testing or explicit re-onboarding).
  Future<void> resetOnboarding() async {
    _hasCompletedOnboarding = false;
    await _storage.saveCompleted(completed: false);
    notifyListeners();
  }

  /// In-memory override for unit/widget testing without disk I/O.
  @visibleForTesting
  void setCompletedInMemory(bool completed) {
    _hasCompletedOnboarding = completed;
    notifyListeners();
  }
}
