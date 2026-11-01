# Daria — Google Play Store Deployment Audit Report

**Audit Date:** November 1, 2026  
**Application Name:** Daria  
**Package Name (Application ID):** `com.photoaday.photo_per_day`  
**Version:** `1.0.0+1` (Version Name: `1.0.0`, Version Code: `1`)  
**Target Environment:** Android 7.0+ (API 24 to API 36)  

---

## 1. Executive Summary

A comprehensive, end-to-end audit of the Daria Flutter project was performed across build configuration, security, platform compatibility, privacy policies, branding, and runtime reliability.

All confirmed Google Play publication blockers have been resolved:
- **Blocker Fixed:** Removed `android.permission.USE_EXACT_ALARM` from `AndroidManifest.xml`. (Google Play strictly restricts exact alarms to dedicated timer and alarm clock apps; Daria's reminder engine uses `inexactAllowWhileIdle`, making exact alarms unnecessary and preventing automatic policy rejection).
- **ProGuard / R8 Hardening:** Created `android/app/proguard-rules.pro` with explicit keep rules for Flutter engines and `flutter_local_notifications` to prevent runtime serialization regressions.
- **Release Signing:** Verified production upload key signing using `android/app/upload-keystore.jks` and `android/key.properties`. The generated AAB is signed with a valid 2048-bit RSA key valid through 2054.
- **Store Assets & Policy Documents:** Generated official 512×512 icon, 1024×500 feature graphic, comprehensive Privacy Policy, Data Safety Questionnaire answers, and step-by-step Console guide.

---

## 2. Technical & Configuration Audit

| Component | Verified Setting | Status | Notes |
|---|---|---|---|
| **Flutter SDK** | `3.44.1` (Channel stable) | PASS | Up-to-date stable release |
| **Dart SDK** | `3.12.1` | PASS | Null-safe Dart runtime |
| **Gradle / AGP** | Gradle 8.11, AGP 8.7.0 | PASS | Modern Android build tooling |
| **Java JDK** | OpenJDK 17.0.19 (LTS) | PASS | Android Studio & Gradle compatible |
| **Application ID** | `com.photoaday.photo_per_day` | PASS | Strictly preserved for existing & future users |
| **User-Facing App Name**| `Daria` | PASS | Configured in `AndroidManifest.xml` and UI |
| **Compile SDK** | `36` (Android 16 Developer Preview / Android 15+) | PASS | Above Play Store minimum requirement (34+) |
| **Target SDK** | `36` (Android 16 Developer Preview / Android 15+) | PASS | Exceeds Google Play requirement (Target API 34+) |
| **Min SDK** | `24` (Android 7.0 Nougat) | PASS | Supports 95%+ of active Android devices |
| **64-bit Support** | `arm64-v8a`, `x86_64`, `armeabi-v7a` | PASS | Fully satisfies Google Play 64-bit mandate |
| **Core Desugaring** | `desugar_jdk_libs:2.1.4` | PASS | Enables modern Java 8+ time APIs on older devices |

---

## 3. Manifest & Permissions Audit

| Permission | Declared In Manifest | Purpose in Daria | Google Play Policy Assessment |
|---|---|---|---|
| `android.permission.CAMERA` | YES | Taking daily photos in-app | Granted conditionally; required=false on camera hardware ensures all devices can install |
| `android.permission.READ_EXTERNAL_STORAGE` | YES (`maxSdkVersion="32"`) | Gallery photo import on Android 12 and below | Safely scoped to API <= 32. Android 13+ uses modern Photo Picker |
| `android.permission.INTERNET` | YES | External feedback URL navigation | Standard network permission (normal protection level) |
| `android.permission.POST_NOTIFICATIONS` | YES | Daily reminder notifications (Android 13+) | Standard runtime prompt requested only when user enables reminders |
| `android.permission.RECEIVE_BOOT_COMPLETED` | YES | Reschedule reminders after reboot | Normal permission; required by `flutter_local_notifications` |
| `android.permission.VIBRATE` | YES | Notification vibration | Normal permission |
| `android.permission.USE_EXACT_ALARM` | **REMOVED** | Redundant | **Removed to prevent Google Play policy strike** |
| `android.permission.SCHEDULE_EXACT_ALARM` | **REMOVED** | Redundant | **Removed to prevent Google Play policy strike** |

---

## 4. Privacy, Data Safety & Third-Party Audit

An inspection of `pubspec.yaml` and application data handling confirms:
- **No Advertising SDKs:** Daria contains no AdMob, Unity, AppLovin, or banner SDKs.
- **No Analytics / Tracking SDKs:** No Google Analytics, Firebase Analytics, Mixpanel, or Segment.
- **No Crash Log Uploaders:** No Sentry, Bugsnag, or Crashlytics reporting user device state.
- **Local-First Storage:** All photos and diary notes are written strictly to the local application sandbox (`getApplicationDocumentsDirectory()`).
- **External Network Interaction:** The only network activity initiated by the app occurs when the user explicitly clicks a feedback option in Settings ("Report a Bug", "Suggest a Feature", "General Feedback"), which invokes the system default browser via `url_launcher` to load `https://tally.so/r/perLYE`.

---

## 5. Build Verification Results

- **Android App Bundle (AAB):** Generated at `release_deliverables/bundle/Daria-release.aab` (66.4 MB).
- **AAB Signature:** Signed with release keystore alias `photoaday` (RSA 2048-bit, SHA-256 fingerprint verified, valid until 2054). Not debug-signed.
- **Release APK:** Output generated at `release_deliverables/bundle/Daria-release.apk` for testing on physical devices before publishing.

