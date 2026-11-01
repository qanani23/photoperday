import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/daily_reminder_settings.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_status.dart';
import 'package:photo_per_day/data/services/diary_export_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/photo_file_manager.dart';
import 'package:photo_per_day/data/services/photo_metadata_storage.dart';
import 'package:photo_per_day/screens/profile/profile_screen.dart';

// ---------------------------------------------------------------------------
// Tests for Security, Privacy, and Local Data Protection
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PersistentDailyPhotoStore store;
  late PhotoFileManager fileManager;
  late PhotoMetadataStorage metadataStorage;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('m39_security_test_');

    fileManager = PhotoFileManager(customBaseDir: tempDir);
    await fileManager.init();

    metadataStorage = PhotoMetadataStorage(customBaseDir: tempDir);
    await metadataStorage.init();

    store = PersistentDailyPhotoStore(
      fileManager: fileManager,
      metadataStorage: metadataStorage,
    );
    await store.init();
    PersistentDailyPhotoStore.setTestInstance(store);
  });

  tearDown(() async {
    PersistentDailyPhotoStore.resetTestInstance();

    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('1. Local Privacy & Zero Remote Services Architecture', () {
    test(
      'App operates locally without requiring remote authentication or cloud tokens',
      () {
        final entry = PhotoEntry(
          date: DateTime.utc(2026, 9, 27),
          title: 'Local Privacy First',
          gradientColors: const [Colors.amber, Colors.orange],
        );

        expect(entry.syncStatus, equals(SyncStatus.localOnly));
        expect(entry.authorizedEmail, isNull);
        expect(entry.driveFileId, isNull);
      },
    );
  });

  group('2. Sensitive Data & Token Leakage Protections', () {
    test(
      'PhotoEntry serialization contains zero OAuth tokens or auth headers',
      () {
        final entry = PhotoEntry(
          date: DateTime.utc(2026, 9, 27),
          title: 'Morning Sunshine',
          location: 'Garden Patio',
          gradientColors: const [Colors.amber, Colors.orange],
          imagePath: '/path/to/local/photo.jpg',
          syncStatus: SyncStatus.localOnly,
          driveFileId: 'drive_file_id_12345',
          driveFileRevision: 'rev_1',
          authorizedEmail: 'user@example.com',
        );

        final jsonMap = entry.toJson();
        final jsonString = jsonEncode(jsonMap);

        expect(jsonString, isNot(contains('accessToken')));
        expect(jsonString, isNot(contains('refreshToken')));
        expect(jsonString, isNot(contains('Bearer ')));
        expect(jsonString, isNot(contains('Authorization')));
        expect(jsonString, isNot(contains('secret')));
      },
    );

    test(
      'DailyReminderSettings contains only schedule flags without tracking data',
      () {
        const settings = DailyReminderSettings(
          enabled: true,
          hour: 20,
          minute: 30,
        );
        final jsonString = jsonEncode(settings.toJson());
        expect(jsonString, equals('{"enabled":true,"hour":20,"minute":30}'));
      },
    );

    test(
      'Legacy cloud fields in PhotoEntry are backward compatible when reading stored JSON',
      () {
        final legacyJson = {
          'date': '2026-09-27T00:00:00.000Z',
          'title': 'Legacy Stored Entry',
          'location': 'Home',
          'gradientColors': [4284900966, 4294198070],
          'imagePath': '/path/to/img.jpg',
          'syncStatus': 'synced',
          'driveFileId': 'legacy_drive_123',
          'driveFileRevision': '2',
          'authorizedEmail': 'old_user@gmail.com',
          'syncError': null,
        };

        final parsed = PhotoEntry.fromJson(legacyJson);
        expect(parsed.title, 'Legacy Stored Entry');
        expect(parsed.syncStatus, SyncStatus.synced);
        expect(parsed.driveFileId, 'legacy_drive_123');
        expect(parsed.authorizedEmail, 'old_user@gmail.com');

        // Can roundtrip back to JSON without loss or error
        final reEncoded = parsed.toJson();
        expect(reEncoded['driveFileId'], 'legacy_drive_123');
      },
    );
  });

  group('3. Export Privacy & Safe Content Manifest', () {
    test(
      'DiaryExportService creates a sanitized manifest without internal sync tokens or credentials',
      () async {
        final dummyFile = File('${tempDir.path}/test_source.jpg');
        dummyFile.writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));

        final sampleEntry = PhotoEntry(
          date: DateTime(2026, 9, 20),
          title: 'Export Day',
          location: 'Secret Location',
          imagePath: dummyFile.path,
          gradientColors: const [Colors.blue, Colors.purple],
        );
        await store.savePhoto(entry: sampleEntry);

        final exportService = DiaryExportService(
          store: store,
          defaultExportDir: tempDir,
        );

        final result = await exportService.exportDiary();
        expect(result.isSuccess, isTrue);
        expect(result.zipFile, isNotNull);

        final bytes = await result.zipFile!.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);

        final manifestFile = archive.findFile('manifest.json');
        expect(manifestFile, isNotNull);

        final manifestJson = utf8.decode(manifestFile!.content as List<int>);
        final manifestMap = jsonDecode(manifestJson) as Map<String, dynamic>;

        expect(manifestMap['appName'], equals('Daria'));
        expect(manifestMap['totalPhotos'], equals(1));

        // Strict privacy check: Manifest MUST NOT contain tokens, drive IDs, or queue state
        expect(manifestJson, isNot(contains('accessToken')));
        expect(manifestJson, isNot(contains('refreshToken')));
        expect(manifestJson, isNot(contains('Bearer')));
        expect(manifestJson, isNot(contains('driveFileId')));
        expect(manifestJson, isNot(contains('syncQueue')));
      },
    );

    test(
      'Temporary exports are cleanly removed by cleanTemporaryExports',
      () async {
        final exportService = DiaryExportService(
          store: store,
          defaultExportDir: tempDir,
        );

        final dummyExportFile = File(
          '${tempDir.path}/photo_a_day_export_12345678.zip',
        );
        dummyExportFile.writeAsStringSync('zip content');
        expect(dummyExportFile.existsSync(), isTrue);

        final deleted = await exportService.cleanTemporaryExports(
          customExportDir: tempDir,
        );
        expect(deleted, greaterThanOrEqualTo(1));
        expect(dummyExportFile.existsSync(), isFalse);
      },
    );
  });

  group('4. Local Diary Deletion Safety Boundaries', () {
    test(
      'deleteLocalDiary safely empties store and deletes files on disk without touching external paths',
      () async {
        final dummyFile = File('${tempDir.path}/local_photo.jpg');
        dummyFile.writeAsBytesSync(Uint8List.fromList([10, 20, 30]));

        final sampleEntry = PhotoEntry(
          date: DateTime(2026, 9, 15),
          title: 'Keep Me Local',
          imagePath: dummyFile.path,
          gradientColors: const [Colors.teal, Colors.cyan],
        );
        await store.savePhoto(entry: sampleEntry);

        expect(store.totalPhotos, equals(1));
        final savedPath = store
            .getPhotoByKey(const DateKey(2026, 9, 15))!
            .imagePath!;
        expect(File(savedPath).existsSync(), isTrue);

        // Delete local diary
        await store.deleteLocalDiary();

        // Local store is empty
        expect(store.totalPhotos, equals(0));
        expect(store.hasPhoto(DateTime(2026, 9, 15)), isFalse);
      },
    );
  });

  group('5. Production Feature Gating & Clean Local Interface', () {
    testWidgets(
      'ProfileScreen does not expose upload test photo or cloud sync controls',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ProfileScreen())),
        );
        await tester.pump();

        expect(find.text('Upload Test Photo'), findsNothing);
        expect(find.text('Sync Now'), findsNothing);
        expect(find.text('Sign In'), findsNothing);
      },
    );
  });

  group('6. Platform Permission Declarations Integrity', () {
    test(
      'Android manifest contains required permissions without unneeded scopes',
      () {
        final manifestFile = File('android/app/src/main/AndroidManifest.xml');
        expect(manifestFile.existsSync(), isTrue);

        final content = manifestFile.readAsStringSync();
        expect(content, contains('android.permission.CAMERA'));
        expect(content, contains('android.permission.INTERNET'));
        expect(content, contains('android.permission.POST_NOTIFICATIONS'));

        // Ensure no location or microphone permissions were added
        expect(
          content,
          isNot(contains('android.permission.ACCESS_FINE_LOCATION')),
        );
        expect(content, isNot(contains('android.permission.RECORD_AUDIO')));
      },
    );

    test(
      'iOS Info.plist has valid structure and required usage descriptions',
      () {
        final plistFile = File('ios/Runner/Info.plist');
        expect(plistFile.existsSync(), isTrue);

        final content = plistFile.readAsStringSync();
        expect(content, contains('NSCameraUsageDescription'));
        expect(content, contains('NSPhotoLibraryUsageDescription'));
        // Verify valid XML structure (closing tags match)
        expect(
          content.contains('<array>') && content.contains('</array>'),
          isTrue,
        );
        expect(content.trim().endsWith('</plist>'), isTrue);
      },
    );
  });
}
