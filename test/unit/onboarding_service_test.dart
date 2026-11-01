import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/services/onboarding_service.dart';
import 'package:photo_per_day/data/services/onboarding_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late OnboardingStorage storage;
  late OnboardingService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('onboarding_test_');
    storage = OnboardingStorage(customBaseDir: tempDir.path);
    service = OnboardingService(storage: storage);
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
    OnboardingService.resetTestInstance();
  });

  group('OnboardingStorage Unit Tests', () {
    test('1. Default state is false when no storage file exists', () async {
      final completed = await storage.loadCompleted();
      expect(completed, isFalse);
    });

    test('2. Saving completed=true persists atomically to disk', () async {
      await storage.saveCompleted(completed: true);
      final completed = await storage.loadCompleted();
      expect(completed, isTrue);

      final filePath = await storage.onboardingFilePath;
      expect(File(filePath).existsSync(), isTrue);
    });

    test('3. Persisted status survives new storage instance', () async {
      await storage.saveCompleted(completed: true);

      // Re-instantiate storage with the exact same directory
      final reloadedStorage = OnboardingStorage(customBaseDir: tempDir.path);
      final completed = await reloadedStorage.loadCompleted();
      expect(completed, isTrue);
    });

    test('4. Corrupted file content falls back safely to false', () async {
      final filePath = await storage.onboardingFilePath;
      File(filePath).writeAsStringSync('{ bad json corrupt content !@# }');

      final completed = await storage.loadCompleted();
      expect(completed, isFalse);
    });

    test('5. Empty file falls back safely to false', () async {
      final filePath = await storage.onboardingFilePath;
      File(filePath).writeAsStringSync('');

      final completed = await storage.loadCompleted();
      expect(completed, isFalse);
    });

    test('6. Clear method deletes storage file', () async {
      await storage.saveCompleted(completed: true);
      expect(await storage.loadCompleted(), isTrue);

      await storage.clear();
      expect(await storage.loadCompleted(), isFalse);
    });
  });

  group('OnboardingService Domain Tests', () {
    test('7. init() sets hasCompletedOnboarding to storage value', () async {
      expect(service.isInitialized, isFalse);
      await service.init();
      expect(service.isInitialized, isTrue);
      expect(service.hasCompletedOnboarding, isFalse);
    });

    test('8. completeOnboarding() sets status to true and persists', () async {
      await service.init();
      expect(service.hasCompletedOnboarding, isFalse);

      bool notified = false;
      service.addListener(() => notified = true);

      await service.completeOnboarding();
      expect(service.hasCompletedOnboarding, isTrue);
      expect(notified, isTrue);

      final reloaded = await storage.loadCompleted();
      expect(reloaded, isTrue);
    });

    test('9. resetOnboarding() reverts status to false and persists', () async {
      await service.init();
      await service.completeOnboarding();
      expect(service.hasCompletedOnboarding, isTrue);

      await service.resetOnboarding();
      expect(service.hasCompletedOnboarding, isFalse);

      final reloaded = await storage.loadCompleted();
      expect(reloaded, isFalse);
    });

    test('10. setCompletedInMemory() updates status without disk I/O', () {
      service.setCompletedInMemory(true);
      expect(service.hasCompletedOnboarding, isTrue);

      service.setCompletedInMemory(false);
      expect(service.hasCompletedOnboarding, isFalse);
    });

    test('11. Global singleton setTestInstance and resetTestInstance work', () {
      final custom = OnboardingService(storage: storage);
      OnboardingService.setTestInstance(custom);
      expect(identical(OnboardingService.instance, custom), isTrue);

      OnboardingService.resetTestInstance();
      expect(identical(OnboardingService.instance, custom), isFalse);
    });
  });
}
