# Gleam — App Store Manual Checklist

These steps **cannot be automated by Claude** and require your Apple Developer account, Mac with Xcode, or external dashboards.

---

## Phase 1 — Apple Developer Account (do first)

- [ ] **Enroll in Apple Developer Program**
  - Go to [developer.apple.com/programs](https://developer.apple.com/programs)
  - Cost: $99/year
  - Requires Apple ID with 2FA enabled
  - Takes 24–48 hours to activate

- [ ] **Create App ID (Bundle Identifier)**
  - In [App Store Connect → Identifiers](https://appstoreconnect.apple.com)
  - Bundle ID: `com.gleam.app` (or your chosen ID — must match Xcode project exactly)
  - Enable capabilities: Push Notifications (if needed), Sign In with Apple (not needed, using Google)

- [ ] **Create the App in App Store Connect**
  - App Store Connect → My Apps → "+"
  - Platform: iOS
  - Name: "Gleam: Smile Whitening Tracker"
  - Bundle ID: match what you set above
  - SKU: `gleam-ios-001` (any unique internal string)
  - Primary language: English

---

## Phase 2 — In-App Purchases / Subscriptions

- [ ] **Create Subscription Group in App Store Connect**
  - My Apps → Gleam → In-App Purchases → Subscriptions
  - Group name: "Gleam Pro"

- [ ] **Create Monthly Subscription product**
  - Reference Name: "Gleam Pro Monthly"
  - Product ID: `com.gleam.pro.monthly` ← must match the code exactly
  - Subscription Duration: 1 Month
  - Price: $4.99 (Tier 5)
  - Localization: add EN display name + description

- [ ] **Create Yearly Subscription product**
  - Reference Name: "Gleam Pro Yearly"
  - Product ID: `com.gleam.pro.yearly` ← must match the code exactly
  - Subscription Duration: 1 Year
  - Price: $34.99 (Tier 35)
  - Add promotional text: "Save ~40% vs monthly"

- [ ] **Optionally configure a Free Trial**
  - 3-day or 7-day free trial for new subscribers (set in App Store Connect per product)

- [ ] **Bank & Tax info**
  - App Store Connect → Agreements, Tax, and Banking
  - Must be completed before any paid app/IAP can go live

---

## Phase 3 — Firebase Production Setup

- [ ] **Create a production Firebase project** (or promote existing to production)
  - Firebase Console → new project (e.g., `gleam-prod`)
  - Enable: Authentication (Google), Firestore, Storage, Cloud Functions

- [ ] **Download production `GoogleService-Info.plist`**
  - Firebase Console → Project Settings → iOS app → download plist
  - Add to Xcode target (replace dev plist for Release builds, or use build phases)
  - Verify `REVERSED_CLIENT_ID` URL scheme in Info.plist matches

- [ ] **Set production `API_BASE_URL`**
  - Get your Firebase Functions URL from the Functions dashboard
  - Set it in `Config/Release.xcconfig`: `API_BASE_URL = https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net`

- [ ] **Deploy Firebase Cloud Functions to production**
  ```bash
  firebase use gleam-prod
  firebase deploy --only functions
  ```

- [ ] **Set OpenAI API key secret in production**
  ```bash
  firebase functions:secrets:set OPENAI_API_KEY
  ```

- [ ] **Review Firestore security rules** — ensure they're locked down for production (no open reads/writes)

---

## Phase 4 — Xcode Signing & Build (on your Mac)

- [ ] **Configure signing in Xcode**
  - Open `Gleam.xcodeproj`
  - Target → Signing & Capabilities → select your Team
  - Enable "Automatically manage signing"
  - Xcode will generate/download provisioning profiles

- [ ] **Set Marketing Version and Build number**
  - Target → General → Version: `1.0.0`, Build: `1`
  - Or set in `Config/Release.xcconfig` (already prepared by Claude)

- [ ] **Set the StoreKit Configuration for testing** (Xcode only)
  - Edit Scheme → Run → Options → StoreKit Configuration → select `Gleam.storekit`
  - Test subscription purchases in Simulator before real submission

- [ ] **Archive and upload**
  ```
  Product → Archive → Distribute App → App Store Connect → Upload
  ```
  Or with Fastlane (once Claude sets it up):
  ```bash
  bundle exec fastlane release
  ```

---

## Phase 5 — Store Listing & Privacy

- [ ] **App Store listing copy** (fill in App Store Connect)
  - **Name:** Gleam: Smile Whitening Tracker
  - **Subtitle:** AI Teeth Analysis & Care Plans
  - **Description:** (see `fastlane/metadata/en-US/description.txt` once Claude generates it)
  - **Keywords:** teeth whitening, smile analyzer, dental tracker, oral care, whitening tracker
  - **Support URL:** your support page or GitHub issues link
  - **Privacy Policy URL:** required — host a simple privacy policy page

- [ ] **Screenshots** (required sizes)
  - 6.7" — iPhone 16 Pro Max simulator or device
  - 6.1" — iPhone 16 simulator or device
  - Run `bundle exec fastlane screenshots` after Claude sets up Fastlane

- [ ] **App Preview video** (optional but boosts conversion)

- [ ] **App Icon** — verify it's included in `Assets.xcassets/AppIcon.appiconset` at all required sizes (1024×1024 for App Store)

---

## Phase 6 — Privacy Questionnaire (App Store Connect)

- [ ] **Data types collected** — fill in App Store Connect Privacy section:
  - **Contact info:** email (via Google Sign-In) — linked to identity
  - **Identifiers:** User ID (Firebase UID) — linked to identity
  - **Photos/Videos:** user-submitted scan photos — not linked to identity (stored in Firebase Storage)
  - **Usage data:** scan frequency, scores — linked to identity (Firestore)
  - No: precise location, health data, financial info, browsing history

- [ ] **Confirm no third-party ad SDKs** (Gleam uses none currently — clean label)

---

## Phase 7 — TestFlight & Review

- [ ] **TestFlight internal testing**
  - Upload a build, add yourself as internal tester
  - Test full purchase flow with sandbox Apple ID (create at App Store Connect → Users → Sandbox Testers)
  - Test on a real iPhone (camera, Google Sign-In, IAP)

- [ ] **External TestFlight** (optional, recommended)
  - Invite 5–10 beta users before public launch

- [ ] **Submit for App Review**
  - Fill in review notes: "App uses camera for smile analysis. Test account: [provide sandbox credentials if Sign-In is required]"
  - Confirm age rating (likely 4+ or 12+)
  - Submit

---

## Phase 8 — Post-Launch

- [ ] **Monitor crash reports** in Xcode Organizer / Firebase Crashlytics (add Crashlytics if not already)
- [ ] **Monitor subscription metrics** in App Store Connect → Sales & Trends
- [ ] **Respond to App Store reviews**
- [ ] **Set up a privacy policy page** (legally required — can use a free generator like [privacypolicies.com](https://www.privacypolicies.com))
- [ ] **Monitor Firebase usage** — OpenAI API calls cost money per scan; consider rate limiting free tier on the backend

---

## What Claude Can Automate for You

| Task | Tool | Notes |
|---|---|---|
| StoreKit2 code integration | Claude directly | See `CODING_TODO.md` |
| Paywall UI | Claude directly | See `CODING_TODO.md` |
| Fastlane config files | Claude directly | You run on Mac |
| Auto-screenshots | Fastlane `snapshot` | Needs Mac + Xcode |
| Metadata/description upload | Fastlane `deliver` | Needs Apple credentials |
| TestFlight upload | Fastlane `pilot` | Needs Mac + Xcode |
| Full release lane | Fastlane `gym` + `deliver` | Needs Mac + Xcode |
| App Store Connect API | `fastlane` + ASC API key | Can create IAP products via API if you provide the key |

**Fastlane tip:** After Claude sets up the Fastlane files, run `gem install fastlane` on your Mac once, then `bundle exec fastlane [lane]` from the project root. This handles screenshots, upload, and submission automatically.

---

## Quick Notes

- The app runs fully without your laptop once live, as long as Firebase Functions are deployed and `GoogleService-Info.plist` + `API_BASE_URL` point to production.
- Product IDs in code **must exactly match** what you create in App Store Connect: `com.gleam.pro.monthly`, `com.gleam.pro.yearly`
- Sandbox purchases during TestFlight use a **separate Sandbox Apple ID** — create one in App Store Connect → Users → Sandbox Testers
- Free trial (if configured in App Store Connect) requires no extra code — StoreKit2 handles it automatically
