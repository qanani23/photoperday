# DARIA — GOOGLE PLAY STORE DEPLOYMENT & RELEASE GUIDE

This is your master handover document for releasing **Daria** to the Google Play Store and maintaining future updates. All deliverables, configurations, security precautions, and Google Play Console requirements are documented here.

---

## 1. Android App Signing Credentials

| Item | Status | Value / Location | Secure Access Guidance |
|---|---|---|---|
| **Upload Keystore Status** | **ACTIVE & CONFIGURED** | Exists on disk | Ready for signing release bundles |
| **Keystore File Location** | **LOCAL DISK** | `android/app/upload-keystore.jks` | Ignored in `.gitignore`; backed up securely |
| **Keystore Properties File**| **LOCAL DISK** | `android/key.properties` | Ignored in `.gitignore`; loaded by Gradle |
| **Keystore Alias** | **ACTIVE** | `photoaday` | Configured in `key.properties` |
| **Keystore & Key Password** | **SECURELY STORED** | Stored in `android/key.properties` | *Never committed to Git or printed in logs* |
| **Key Algorithm** | **2048-bit RSA** | `SHA256withRSA` | Standard Google Play upload key algorithm |
| **Key Validity** | **VALID** | Until **February 16, 2054** | Valid for 28 years |
| **Certificate SHA-1** | **VERIFIED** | `F6:BA:67:99:09:5F:32:67:BA:C4:4C:17:03:CB:ED:4E:A5:F0:5C:21` | Register if using Google Play App Signing |
| **Certificate SHA-256** | **VERIFIED** | `B4:0B:97:B7:17:01:0C:34:91:55:2B:A6:4C:0D:A3:78:D6:C6:ED:14:47:FB:37:1E:A4:0B:02:5D:06:4F:3D:EC` | Register for Play App Signing & API keys |
| **Google Play App Signing** | **READY TO ENROLL** | Google Play Console | Select "Use Google-generated key" or upload existing key on first release |

> [!CAUTION]
> **Credential Security:** Never commit `upload-keystore.jks` or `key.properties` to version control. Keep an encrypted backup in a secure vault (e.g., 1Password, Bitwarden, or encrypted offline drive).

---

## 2. Application Technical Identifiers & Build Specs

| Parameter | Current Value | Notes |
|---|---|---|
| **Application ID (Package)**| `com.photoaday.photo_per_day` | **Permanent ID**; must remain unchanged for future updates |
| **Display Name (App Title)**| `Daria` | User-visible name in launcher, headers, and store |
| **Version Name** | `1.0.0` | Specified in `pubspec.yaml` (`1.0.0+1`) |
| **Version Code** | `1` | Monotonically increasing integer (increment by 1 per release) |
| **Minimum SDK (`minSdk`)** | `24` | Android 7.0 Nougat (covers 95%+ of active devices worldwide) |
| **Target SDK (`targetSdk`)** | `36` | Exceeds Google Play requirement (Target API 34+ required) |
| **Compile SDK (`compileSdk`)**| `36` | Android 16 Preview / Android 15 toolchain |
| **Supported ABIs** | `arm64-v8a`, `armeabi-v7a`, `x86_64` | 64-bit compliant (Mandatory for Play Store) |
| **Java / JDK Version** | OpenJDK 17.0.19 (LTS) | Modern AGP 8.7 compatible runtime |
| **AAB Output Location** | `release_deliverables/bundle/Daria-release.aab` | Signed and ready for Play Console upload |
| **APK Output Location** | `release_deliverables/bundle/Daria-release.apk` | Signed and ready for local device verification |
| **Release Signing Status** | **SIGNED WITH UPLOAD KEY** | Verified via `keytool -printcert` (Not debug signed) |

---

## 3. Google Play Console Requirements & Checklist

| Requirement | Type | Description / Location | Your Action Needed |
|---|---|---|---|
| **Google Play Developer Account** | **Mandatory** | Registered account at [play.google.com/console](https://play.google.com/console) | Pay \$25 one-time registration fee; complete identity verification |
| **App Title** | **Mandatory** | `Daria` (or `Daria - Daily Photo Diary`) | Enter in Store Listing |
| **Short Description** | **Mandatory** | Up to 80 chars (`release_deliverables/metadata/STORE_LISTING.md`) | Paste in Store Listing |
| **Full Description** | **Mandatory** | Complete copy in `release_deliverables/metadata/STORE_LISTING.md` | Paste in Store Listing |
| **App Icon (512x512 PNG)**| **Mandatory** | `release_deliverables/store_assets/daria_play_store_icon_512x512.png` | Upload in Store Listing |
| **Feature Graphic (1024x500)**| **Mandatory** | `release_deliverables/store_assets/daria_feature_graphic_1024x500.png` | Upload in Store Listing |
| **Phone Screenshots** | **Mandatory** | At least 4 screenshots (Capture guide in `SCREENSHOTS_GUIDE.md`) | Capture from device/emulator and upload |
| **Privacy Policy URL** | **Mandatory** | `release_deliverables/policy/PRIVACY_POLICY.md` | Host online (e.g. GitHub Pages) and enter URL |
| **Data Safety Questionnaire**| **Mandatory** | Field-by-field answers in `GOOGLE_PLAY_DATA_SAFETY.md` | Complete form in Play Console |
| **Content Rating** | **Mandatory** | Questionnaire in Play Console (utility / productivity) | Complete questionnaire (Rated Everyone / PEGI 3) |
| **Ads Declaration** | **Mandatory** | Declare: "No ads" | Select "No" |
| **App Access Declaration** | **Mandatory** | Declare: "All functionality available without special access" | Select "No restricted access" |
| **Target Audience & Age** | **Mandatory** | Target: 18+ (or 13+) | Select target age group |
| **Closed Testing (if required)**| **Conditional** | Required for personal developer accounts created after Nov 13, 2023 | Run 14-day closed test with 14 testers |
| **Production Rollout** | **Mandatory** | Create release in Production track, attach AAB, submit | Review and confirm rollout |

---

## 4. Privacy, Data Safety & Codebase Audit Findings

A rigorous audit of Daria's codebase, native platform code, and packages confirmed:

1. **Local-First Architecture:**
   - All captured daily photos are stored in private app storage via `path_provider`.
   - All notes, calendar dates, and diary entries are persisted in local files/SQLite.
   - **Zero personal data leaves the device.**
2. **Third-Party SDKs:**
   - **0 Advertising SDKs:** No AdMob, Unity, AppLovin, or banners.
   - **0 Tracking / Analytics SDKs:** No Google Analytics, Firebase, Mixpanel, or Segment.
   - **0 Crashlytics Frameworks:** No background telemetry uploaders.
3. **Permissions Safety:**
   - `android.permission.CAMERA`: Used strictly for in-app photo capture. Hardware camera is marked `required="false"` so devices without rear cameras can still install.
   - `android.permission.READ_EXTERNAL_STORAGE`: Scoped with `maxSdkVersion="32"`. On Android 13+ (API 33+), the official Android Photo Picker is used with zero extra permissions.
   - `android.permission.USE_EXACT_ALARM`: **Removed during this audit.** Daria's reminders use `inexactAllowWhileIdle`, eliminating the risk of Play Store rejection under Google's Exact Alarm Policy.
   - `android.permission.POST_NOTIFICATIONS`: Requested only when the user turns on daily reminders in Settings.
4. **External Feedback Integration:**
   - When the user taps "Report a Bug", "Suggest a Feature", or "General Feedback", Daria opens the public Tally form (`https://tally.so/r/perLYE`) in the user's external default web browser using `url_launcher`. No background telemetry or user identifiers are attached.

---

## 5. Future Releases & Maintenance Strategy

When releasing updates (e.g., version 1.1.0):

1. **Update Version in `pubspec.yaml`:**
   ```yaml
   version: 1.1.0+2
   ```
   *Note:* The number before `+` is `versionName` (user-facing); the number after `+` is `versionCode` (must increase by at least 1 every single release).
2. **Build the New Release Bundle:**
   ```bash
   flutter build appbundle --release
   ```
3. **Verify Bundle Signing:**
   The build automatically uses `android/key.properties` and signs with `android/app/upload-keystore.jks`.
4. **Upload to Play Console:**
   Create a new release under **Production** (or **Closed Testing**), upload the new `.aab`, write What's New notes, and submit.
5. **Never Change:**
   - Never change the `applicationId` (`com.photoaday.photo_per_day`).
   - Never delete or overwrite `upload-keystore.jks`.

---

## 6. Final Deployment Readiness Table

| Requirement | Status | Where to find it / How to obtain it | My action needed |
|---|---|---|---|
| **Android Application ID** | **READY** | `com.photoaday.photo_per_day` in `build.gradle.kts` | None (Preserved) |
| **Android App Name** | **READY** | `Daria` in `AndroidManifest.xml` | None (Verified) |
| **Upload Keystore & Key** | **READY** | `android/app/upload-keystore.jks` | Back up safely to an offline encrypted drive |
| **Signing Config (`key.properties`)** | **READY** | `android/key.properties` (ignored in Git) | Keep file present locally on your build machine |
| **Release AAB (Signed)** | **READY** | `release_deliverables/bundle/Daria-release.aab` | Upload to Google Play Console release track |
| **Release APK (Local Testing)** | **READY** | `release_deliverables/bundle/Daria-release.apk` | Install on your phone for final manual verification |
| **Exact Alarm Policy Fix** | **READY** | Removed `USE_EXACT_ALARM` from `AndroidManifest.xml` | None (Resolved) |
| **ProGuard Rules** | **READY** | `android/app/proguard-rules.pro` | None (Configured) |
| **App Icon (512x512 PNG)** | **READY** | `release_deliverables/store_assets/daria_play_store_icon_512x512.png` | Upload to Main store listing |
| **Feature Graphic (1024x500 PNG)**| **READY** | `release_deliverables/store_assets/daria_feature_graphic_1024x500.png`| Upload to Main store listing |
| **Screenshots Checklist** | **READY** | `release_deliverables/store_assets/SCREENSHOTS_GUIDE.md` | Capture 4–8 screenshots from device and upload |
| **Store Listing Copy** | **READY** | `release_deliverables/metadata/STORE_LISTING.md` | Copy title, short description, and full description |
| **Privacy Policy Document** | **READY** | `release_deliverables/policy/PRIVACY_POLICY.md` | Publish online (GitHub Pages/Notion) to get public URL |
| **Data Safety Questionnaire** | **READY** | `release_deliverables/policy/GOOGLE_PLAY_DATA_SAFETY.md` | Fill out Google Play Console questionnaire |
| **Google Play Developer Account** | **NEEDS MY ACTION** | [play.google.com/console](https://play.google.com/console) | Register/log in and verify identity |
| **Play Console Store Submission** | **NEEDS MY ACTION** | Google Play Console | Follow `release_deliverables/DEPLOYMENT_CHECKLIST.md` |

