# Daria — Android Release Signing & Security Guide

## 1. Overview: Upload Key vs. Google Play App Signing

Modern Google Play deployments use **Google Play App Signing**:
1. **Upload Key (Your Key):** Signs the Android App Bundle (`.aab`) locally on your machine before uploading it to the Google Play Console. Google uses this key solely to authenticate that uploads come from you.
2. **App Signing Key (Google's Managed Key):** Google generates or secures this key in its high-security infrastructure. Google uses it to sign the optimized split APKs delivered to user devices from the Play Store.

---

## 2. Daria's Signing Configuration

Daria is fully configured with an official production upload keystore:

- **Keystore File Location:** `android/app/upload-keystore.jks`
- **Configuration File:** `android/key.properties` (loaded dynamically by `android/app/build.gradle.kts`)
- **Key Alias:** `photoaday`
- **Key Algorithm:** 2048-bit RSA (SHA256withRSA)
- **Validity:** Valid until **February 16, 2054** (28-year validity)
- **Owner / Organization:** `CN=Photo a Day, OU=Android Production, O=Photo a Day`
- **Certificate Fingerprints:**
  - **SHA-1:** `F6:BA:67:99:09:5F:32:67:BA:C4:4C:17:03:CB:ED:4E:A5:F0:5C:21`
  - **SHA-256:** `B4:0B:97:B7:17:01:0C:34:91:55:2B:A6:4C:0D:A3:78:D6:C6:ED:14:47:FB:37:1E:A4:0B:02:5D:06:4F:3D:EC`

---

## 3. Git Security and Credential Safeguards

The project's root `.gitignore` strictly protects your signing secrets:
```gitignore
# Keystore and signing credentials
*.keystore
*.jks
*.p12
key.properties
**/key.properties
```

> [!CAUTION]
> Never remove these entries from `.gitignore` or commit `upload-keystore.jks` or `key.properties` to version control. If committed to a public repository, anyone could sign malicious updates.

---

## 4. Keystore Backup & Disaster Recovery

### Safe Backup Procedure:
1. Make a secure, encrypted copy of `android/app/upload-keystore.jks` and `android/key.properties`.
2. Store the backup in a secure password manager or offline encrypted storage (e.g., Bitwarden, 1Password, or an encrypted USB drive).
3. Do not store plain text passwords in cloud notes or send them via unencrypted email.

### What if you ever lose the upload key?
Because Google Play uses Play App Signing, losing your upload key does **not** permanently break your app:
1. In Google Play Console, go to **Setup > App signing**.
2. Click **Request upload key reset**.
3. Generate a new upload key using Java's `keytool`:
   ```bash
   keytool -genkey -v -keystore new-upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias daria-upload
   ```
4. Export the PEM certificate:
   ```bash
   keytool -export -rfc -keystore new-upload-keystore.jks -alias daria-upload -file upload_certificate.pem
   ```
5. Submit `upload_certificate.pem` to Google Play Support. After registration (typically 24–48 hours), you can sign subsequent releases with the new key.

---

## 5. Building Future Releases

To build future releases, simply ensure `android/key.properties` is present, increment the version code in `pubspec.yaml`, and run:
```bash
flutter build appbundle --release
```
Gradle will automatically sign the output AAB with the release key.

