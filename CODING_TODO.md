# Gleam — Coding TODO (Claude can implement these)

Everything below can be coded directly. Items are ordered by priority.

---

## 1. Freemium / Subscription Infrastructure

### 1.1 StoreKit 2 Subscription Manager
**File to create:** `Gleam/Core/CoreDomain/SubscriptionManager.swift`

- `SubscriptionManager` class (ObservableObject) that:
  - Loads products from App Store on init: `com.gleam.pro.monthly`, `com.gleam.pro.yearly`
  - Exposes `isPremium: Bool` (verified via `Transaction.currentEntitlements`)
  - `purchase(_ product: Product) async throws` method
  - `restorePurchases() async throws` method
  - Listens to transaction updates with `Transaction.updates` task
  - Server-side receipt optional (Firebase Cloud Function can verify later)
- Inject via `@StateObject` in `GleamApp.swift` and pass as `@EnvironmentObject`

### 1.2 StoreKit Configuration File (for Xcode testing)
**File to create:** `Gleam/Configuration/Gleam.storekit`

- Define two auto-renewable subscription products:
  - `com.gleam.pro.monthly` — $4.99/month, display name "Gleam Pro Monthly"
  - `com.gleam.pro.yearly` — $34.99/year, display name "Gleam Pro Yearly"
- Attach to the Gleam scheme in Xcode (`Edit Scheme → Run → Options → StoreKit Config`)

### 1.3 Free Tier Scan Limit Enforcement
**File to modify:** `Gleam/Core/CoreDomain/HistoryStore.swift` (or new `ScanLimitManager.swift`)

Free tier: **3 scans per calendar day**

- Add `dailyScanCount: Int` computed from today's `@AppStorage` key (reset each day)
- Add `canScanToday: Bool` — `isPremium || dailyScanCount < 3`
- Increment counter after a successful scan
- Expose `scansRemainingToday: Int` for UI display

### 1.4 Paywall View
**File to create:** `Gleam/Features/PaywallFeature/PaywallView.swift`

- Full-screen sheet/modal shown when a free-tier user hits a gated action
- Shows:
  - App icon + headline ("Unlock Gleam Pro")
  - Feature list (unlimited scans, AI plan, full history)
  - Monthly vs. yearly toggle with savings badge ("Save 40%")
  - Primary CTA button (calls `SubscriptionManager.purchase`)
  - "Restore Purchases" text button
  - "Maybe Later" dismiss button
  - Loading/error states
- Trigger points: scan limit reached, personalized plan tapped, history beyond 10 items

### 1.5 Premium Gating
**Files to modify:**
- `Gleam/Features/ScanFeature/ScanView.swift` — show remaining free scans banner; block + show paywall on limit
- `Gleam/Features/HomeFeature/HomeView.swift` — gate "Personalized Plan" behind premium; show paywall if free user taps it
- `Gleam/Features/HistoryFeature/HistoryView.swift` — cap free history display at 10 items with upsell row at bottom
- `Gleam/Features/SettingsFeature/SettingsView.swift` — add "Gleam Pro" status row + "Manage Subscription" deep-link (`UIApplication.openSettingsURL`) + "Restore Purchases" button

---

## 2. Info.plist — Required Privacy Strings

**File to modify:** `Gleam/Info.plist`

Add the following keys (App Store Review will reject without these):

```xml
<key>NSCameraUsageDescription</key>
<string>Gleam uses your camera to capture a photo of your smile for whitening analysis.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Gleam lets you pick a photo from your library to analyze your smile whitening.</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>Gleam may save your scan photos to your photo library.</string>
```

---

## 3. App Version & Build Configuration

**Files to modify:** `Config/Debug.xcconfig`, `Config/Release.xcconfig`

- Set `MARKETING_VERSION = 1.0.0`
- Set `CURRENT_PROJECT_VERSION = 1`
- Ensure `API_BASE_URL` placeholder is documented clearly in both configs
- Add `BUNDLE_ID = com.gleam.app` (update to match App Store Connect)

---

## 4. Fastlane Setup (user runs on Mac; Claude creates the files)

**Files to create:** `fastlane/Fastfile`, `fastlane/Appfile`, `fastlane/Deliverfile`, `fastlane/metadata/` structure

### 4.1 `fastlane/Appfile`
```ruby
app_identifier "com.gleam.app"
apple_id "YOUR_APPLE_ID@email.com"
team_id "YOUR_TEAM_ID"
```

### 4.2 `fastlane/Fastfile`
Lanes:
- `lane :screenshots` — run `snapshot` to auto-generate screenshots on all required simulator sizes (6.7", 6.1")
- `lane :metadata` — run `deliver` to upload metadata + screenshots without submitting
- `lane :beta` — build + upload to TestFlight (`gym` + `pilot`)
- `lane :release` — build + upload + submit for review (`gym` + `deliver`)

### 4.3 `fastlane/Snapfile`
- Devices: `["iPhone 16 Pro Max", "iPhone 16"]`
- Languages: `["en-US"]`
- Output directory: `fastlane/screenshots`

### 4.4 `fastlane/metadata/en-US/`
Pre-filled markdown files:
- `name.txt` — "Gleam: Smile Whitening Tracker"
- `subtitle.txt` — "AI Teeth Analysis & Care Plans"
- `description.txt` — full store description (generated)
- `keywords.txt` — SEO keywords
- `support_url.txt` — placeholder URL
- `privacy_url.txt` — placeholder URL
- `release_notes.txt` — "Initial release"

---

## 5. Firebase Cloud Function — Subscription Verification (optional but recommended)

**File to modify:** `functions/src/index.ts`

Add an `verifySubscription` callable function that:
- Accepts Apple transaction receipt (or transaction ID with StoreKit2)
- Optionally calls Apple's App Store Server API to verify active subscription
- Stores subscription status in Firestore under `users/{uid}/subscription`
- Backend can then enforce premium features server-side (e.g., allow personalized plan generation only for premium users)

> **Note:** For MVP, client-side `Transaction.currentEntitlements` is acceptable. Server-side verification can be added post-launch.

---

## 6. Onboarding — Add Premium Upsell Screen

**File to modify/create:** `Gleam/Features/IntroFeature/OnboardingView.swift`

Add a final onboarding step (after Google Sign-In) that:
- Shows the 3 key Pro features
- "Start Free" button (dismiss to app)
- "Try Pro Free" button (if Apple offers intro offers, otherwise just continue)
- This is shown once only, after first onboarding

---

## 7. App Tracking Transparency (ATT) — Required for iOS 14.5+

**File to modify:** `Gleam/GleamApp.swift`

- Add `NSUserTrackingUsageDescription` to Info.plist
- Request ATT permission on first launch (`AppTrackingTransparency` framework)
- **Note:** Only needed if using analytics/advertising. If not tracking users cross-app, this can be skipped. For Gleam with Firebase Analytics, add it.

---

## Freemium Tier Summary (reference for implementation)

| Feature | Free | Gleam Pro |
|---|---|---|
| Scans per day | 3 | Unlimited |
| Scan history | Last 10 | Full history |
| Personalized AI Plan | ❌ | ✅ |
| Achievements | ✅ | ✅ |
| Gleam Flow (brushing guide) | ✅ | ✅ |
| Share results | ✅ | ✅ |

**Product IDs (must match App Store Connect exactly):**
- `com.gleam.pro.monthly` — $4.99/month
- `com.gleam.pro.yearly` — $34.99/year (~$2.92/mo, saves ~40%)

---

## Implementation Order

1. `Info.plist` privacy strings — quick win, blocks App Review if missing
2. `SubscriptionManager.swift` + StoreKit config file — foundation for everything
3. `PaywallView.swift` — needed before gating features
4. Free tier limits in `ScanView` + `HomeView` — core freemium logic
5. `HistoryView` capping + Settings subscription row
6. Fastlane setup files — lets user automate screenshots/upload on Mac
7. Onboarding upsell screen — polish
8. Firebase subscription verification — post-launch
