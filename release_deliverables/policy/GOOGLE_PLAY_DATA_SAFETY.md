# Google Play Console — Data Safety Form Guide for Daria

When submitting Daria to the Google Play Console, you will be required to complete the **Data safety** questionnaire under **App content > Data safety**.

Use the answers below, which are derived directly from Daria's codebase audit.

---

## Section 1: Data Collection and Security

### Question 1.1: Does your app collect or share any of the required user data types?
- **Answer:** **No**
- **Explanation:** Daria operates strictly offline as a local-first photo diary. Photos, notes, and diary metadata are stored locally in the device's private app directory and are never uploaded, collected, or transmitted to any external server.

### Question 1.2: Is all of the user data collected by your app encrypted in transit?
- **Answer:** **Yes / Not Applicable**
- If prompted: Any external web navigation (such as user-initiated feedback via Tally.so) uses standard HTTPS encryption.

### Question 1.3: Do you provide a way for users to request that their data be deleted?
- **Answer:** **Yes**
- **Details:** Since all data is stored locally on the device, users can delete individual photos, notes, or entries directly within the app at any time, or permanently delete all data by clearing app storage in Android settings or uninstalling the app.

---

## Section 2: Data Types Breakdown

| Data Category | Data Type | Collected? | Shared? | Purpose / Handling |
|---|---|---|---|---|
| **Location** | Approximate / Precise | **No** | **No** | Not requested or accessed |
| **Personal Info** | Name, Email, Phone, User IDs | **No** | **No** | No account required |
| **Financial Info** | Payment, Credit, Bank | **No** | **No** | No payments or monetization |
| **Health & Fitness** | Health / Fitness data | **No** | **No** | Not applicable |
| **Messages** | SMS, Emails, In-app messages | **No** | **No** | Not accessed |
| **Photos and Videos** | Photos / Videos | **No (Local Only)** | **No** | Stored locally only; never transmitted off the device |
| **Audio Files** | Voice / Sound recordings | **No** | **No** | Not accessed |
| **Files and Docs** | Files / Docs | **No (Local Only)** | **No** | Local backup (`.padbackup`) and PDF exports stay on device |
| **Calendar** | Calendar events | **No** | **No** | In-app calendar is self-contained |
| **Contacts** | Contacts | **No** | **No** | Not requested |
| **App Activity** | App interactions, Search history | **No** | **No** | No analytics SDK |
| **Web Browsing** | Browsing history | **No** | **No** | Not collected |
| **App Info & Performance** | Crash logs, Diagnostics | **No** | **No** | No crashlytics SDK |
| **Device or Other IDs** | Device ID, Advertising ID | **No** | **No** | No advertising or tracking IDs |

---

## Section 3: Third-Party SDK & External Service Summary

- **Ad Networks:** None. (Daria is 100% ad-free).
- **Analytics / Tracking:** None. (No Google Analytics, Firebase, Mixpanel, etc.).
- **Cloud Databases:** None. (No Firebase Firestore, Supabase, AWS, etc.).
- **External Feedback (Tally.so):**
  - Triggered **only** when the user manually taps "Report a Bug", "Suggest a Feature", or "General Feedback" in Settings.
  - Opens in the user's external default web browser (not an in-app data harvesting bridge).
  - Subject to user choice and Tally.so privacy policy.

---

## Section 4: Other Google Play Console Declarations

1. **Target Audience and Content:**
   - Target age: **18 and over** (or 13+ depending on your developer preference; selecting 18+ avoids COPPA family policy verification overhead).
   - Does your app appeal to children?: **No**.
2. **Ads:**
   - Does your app contain ads?: **No**.
3. **App Access:**
   - Are all parts of your app accessible without credentials?: **All functionality is available without special access**. (No login required).
4. **Government Apps:**
   - Is your app developed by or on behalf of a government?: **No**.
5. **Financial Features:**
   - Does your app provide financial features?: **No**.
6. **Health Features:**
   - Does your app declare health features?: **No**.

