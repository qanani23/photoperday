# Google Play Console — Step-by-Step Deployment Checklist for Daria

This checklist guides you through every step to publish Daria to the Google Play Store using the prepared deliverables.

---

## Task Distinction: What Is Prepared vs. Your Manual Actions

| Task Area | Status | Location / Deliverable |
|---|---|---|
| **App Bundle (AAB)** | **DONE (Ready)** | `release_deliverables/bundle/Daria-release.aab` |
| **Local Test APK** | **DONE (Ready)** | `release_deliverables/bundle/Daria-release.apk` |
| **512x512 App Icon** | **DONE (Ready)** | `release_deliverables/store_assets/daria_play_store_icon_512x512.png` |
| **1024x500 Feature Graphic** | **DONE (Ready)** | `release_deliverables/store_assets/daria_feature_graphic_1024x500.png` |
| **Screenshots Guide** | **DONE (Ready)** | `release_deliverables/store_assets/SCREENSHOTS_GUIDE.md` |
| **Store Listing Copy** | **DONE (Ready)** | `release_deliverables/metadata/STORE_LISTING.md` |
| **Privacy Policy Draft** | **DONE (Ready)** | `release_deliverables/policy/PRIVACY_POLICY.md` |
| **Data Safety Questionnaire** | **DONE (Ready)** | `release_deliverables/policy/GOOGLE_PLAY_DATA_SAFETY.md` |
| **Google Play Developer Account** | **NEEDS YOUR ACTION** | Register / log in at [play.google.com/console](https://play.google.com/console) |
| **Host Privacy Policy URL** | **NEEDS YOUR ACTION** | Host `PRIVACY_POLICY.md` on GitHub Pages, Notion, or personal domain |
| **Console Submission** | **NEEDS YOUR ACTION** | Upload AAB, enter metadata, and submit for review |

---

## Step-by-Step Google Play Console Guide

### Step 1: Create the Application in Google Play Console
1. Open the [Google Play Console](https://play.google.com/console).
2. Click **Create app** (top right).
3. **App name:** `Daria` (or `Daria - Daily Photo Diary`).
4. **Default language:** English (United States) — `en-US`.
5. **App or game:** `App`.
6. **Free or paid:** `Free`.
7. Accept the Declarations (Developer Program Policies, US Export Laws).
8. Click **Create app**.

---

### Step 2: Set Up Store Listing & Graphics
1. Go to **Grow users > Store presence > Main store listing**.
2. **App name:** `Daria`
3. **Short description:** Copy from `release_deliverables/metadata/STORE_LISTING.md`:
   > *Capture your journey one photo a day with streaks, memories, and reflections.*
4. **Full description:** Copy the complete description from `release_deliverables/metadata/STORE_LISTING.md`.
5. **App icon:** Upload `release_deliverables/store_assets/daria_play_store_icon_512x512.png`.
6. **Feature graphic:** Upload `release_deliverables/store_assets/daria_feature_graphic_1024x500.png`.
7. **Phone screenshots:** Upload 4–8 phone screenshots captured following `SCREENSHOTS_GUIDE.md`.
8. Click **Save**.

---

### Step 3: Complete App Content & Declarations (Policy)
Navigate to **Policy and programs > App content** and complete each section:

1. **Privacy Policy:**
   - Host `release_deliverables/policy/PRIVACY_POLICY.md` on the web (e.g., GitHub Pages: `https://<username>.github.io/daria-privacy/`).
   - Paste the public URL into the **Privacy policy** field.
2. **Ads:**
   - Select: **No, my app does not contain ads**.
3. **App Access:**
   - Select: **All functionality is available without special access** (no login or credentials needed).
4. **Content Ratings:**
   - Click **Start questionnaire**.
   - Category: **Utility, Productivity, Communication, or Other**.
   - Violence, sex, language, drugs: Answer **No** to all.
   - Result: Rated **Everyone / PEGI 3**. Click **Save** and **Submit**.
5. **Target Audience and Content:**
   - Select: **18 and over** (Recommended to simplify verification).
   - Does your app appeal to children?: **No**.
6. **Data Safety:**
   - Follow the field-by-field answers in `release_deliverables/policy/GOOGLE_PLAY_DATA_SAFETY.md`.
   - Data collection: **No**.
   - Data sharing: **No**.
   - All data is stored locally on the device.
7. **Government Apps:**
   - Select: **No**.
8. **Financial Features:**
   - Select: **My app doesn't provide any financial features**.

---

### Step 4: Configure App Signing & Upload the Release AAB
1. Navigate to **Release > Production** (or **Testing > Closed testing** for initial beta testing).
2. Click **Create new release**.
3. Under **Play App Signing**:
   - Ensure Google Play App Signing is enabled (default recommended option).
4. Under **App bundles**:
   - Drag and drop `release_deliverables/bundle/Daria-release.aab`.
   - Google Play will verify the bundle signature (matches `upload-keystore.jks`).
5. **Release name:** `1.0.0 (1)`
6. **Release notes:** Copy the release notes from `release_deliverables/metadata/STORE_LISTING.md`.
7. Click **Next**.

---

### Step 5: Review Pre-Launch Report & Testing Track
1. Google Play automatically runs automated testing on Firebase Test Lab virtual devices.
2. Verify there are zero crashes, ANRs, or critical security vulnerabilities.
3. *Note for Personal Developer Accounts created after Nov 13, 2023:* Google Play requires testing with at least 14 testers for 14 continuous days on a **Closed Testing** track before applying for production access. If your account has this requirement, start on Closed Testing first.

---

### Step 6: Submit for Review
1. Return to **Publishing overview**.
2. Click **Review and roll out release**.
3. Confirm rollout.
4. Google will begin review (typically takes 1 to 5 business days).

