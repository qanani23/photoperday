# Daria — Privacy Policy

**Effective Date:** November 1, 2026  
**Last Updated:** November 1, 2026  
**Application Name:** Daria  
**Package Name:** com.photoaday.photo_per_day  

---

## 1. Introduction

Daria ("we", "our", or "the app") is a personal daily photo diary designed with a strict **local-first, privacy-by-design** philosophy. We believe your private memories, photos, reflections, and thoughts belong exclusively to you. 

This Privacy Policy explains how Daria handles your information when you use our mobile and desktop applications.

---

## 2. Summary of Key Principles

- **Zero Cloud Storage:** Your photos, notes, calendar dates, and diary entries are stored exclusively on your device's local storage.
- **No Account Required:** You do not need to register, log in, or provide an email address, name, or phone number to use Daria.
- **No Tracking or Analytics:** Daria contains no tracking SDKs, no analytics tools, no telemetry collectors, and no third-party advertising frameworks.
- **No Data Monetization:** We never sell, rent, monetize, or broker your personal information.

---

## 3. Information We Access and How It Is Used

Daria requests certain device permissions solely to provide its core features:

### A. Camera (`android.permission.CAMERA`)
- **Purpose:** Used strictly when you choose to take a photo within the app to record your daily memory.
- **Data Handling:** Camera images are saved directly to your device's private application storage. They are never sent to external servers.

### B. Device Storage / Photo Library (`android.permission.READ_EXTERNAL_STORAGE` on Android 12 and below; Android Photo Picker on Android 13+)
- **Purpose:** Used only when you choose to import an existing photo from your gallery into your diary.
- **Data Handling:** Only the photo(s) you explicitly select are copied to your local diary directory. Daria never scans, indexes, or reads other files on your device.

### C. Notifications (`android.permission.POST_NOTIFICATIONS`)
- **Purpose:** Used if you enable daily reminder notifications to remind you to capture your daily photo.
- **Data Handling:** All notifications are scheduled locally on your device via the Android alarm/notification manager. No push notification servers or external messaging tokens are used.

### D. Internet Access (`android.permission.INTERNET`)
- **Purpose:** Used solely when you voluntarily interact with external links (e.g., submitting feedback or reporting a bug).
- **Data Handling:** Daria does not maintain a backend server. If you tap "Report a Bug", "Suggest a Feature", or "General Feedback" in Settings, Daria opens an external web form (hosted on Tally.so) in your device's default web browser. Any feedback you submit through that form is subject to Tally's privacy policy and the details you choose to share.

---

## 4. Data Storage and Backup

- **Local Storage:** All diary data, including image files and metadata, resides in your device's private app sandbox.
- **Backups (`.padbackup`):** If you use the export backup feature, Daria packages your diary into a standalone file saved to a location you choose. You maintain complete custody of this file.
- **PDF Export:** If you export a PDF diary, the document is generated on your device and shared using your system's native share sheet.

---

## 5. Data Retention and Deletion

Because Daria does not store your data on external servers:
- You can delete any individual photo or note directly within the app at any time.
- You can erase all data by clearing the app's storage in your device settings or by uninstalling the application.
- Once deleted locally, your data cannot be recovered by us, as we do not keep remote backups.

---

## 6. Children's Privacy

Daria is suitable for general audiences and does not knowingly collect any personal identifiable information from children under 13 (or under the applicable age of consent in your jurisdiction).

---

## 7. Changes to This Privacy Policy

We may update this Privacy Policy from time to time. Any changes will be posted within the application repository or documentation with an updated effective date.

---

## 8. Contact Us

If you have questions or feedback regarding this Privacy Policy, you can reach out via the in-app Feedback & Support form or contact the developer directly.

