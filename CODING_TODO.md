# Gleam — Coding TODO

Legend: `[DONE]` = implemented | `[NO DEV ACCOUNT NEEDED]` = can build/test now | `[NEEDS DEV ACCOUNT]` = must wait

---

> ⚠️ **DO THIS BEFORE TESTING — NO DEV ACCOUNT NEEDED**
> In Xcode: **Edit Scheme → Run → Options → StoreKit Configuration → select `Gleam/Configuration/Gleam.storekit`**
> Without this, IAP purchase buttons will silently do nothing in the Simulator.

---

## ✅ Already Implemented (this session)

| # | Task | Status |
|---|---|---|
| A | Info.plist privacy strings (Camera, Photo Library) | `[DONE]` |
| B | `SubscriptionManager.swift` — StoreKit2 wrapper | `[DONE]` |
| C | `Gleam.storekit` — local IAP test config for Xcode Simulator | `[DONE]` |
| D | `ScanLimitManager.swift` — 3 scans/day free tier enforcement | `[DONE]` |
| E | `PaywallView.swift` — monthly/yearly paywall with feature list | `[DONE]` |
| F | Premium gating in `ScanView`, `HomeView`, `HistoryView`, `SettingsView` | `[DONE]` |
| G | `GleamApp.swift` — inject `SubscriptionManager` + `ScanLimitManager` | `[DONE]` |
| H | `Config/*.xcconfig` — version numbers (1.0.0 / build 1) | `[DONE]` |
| I | Fastlane setup (`Fastfile`, `Appfile`, `Deliverfile`, `Snapfile`, metadata) | `[DONE]` |

---

## To Do Next (No Dev Account Needed)

### 1. Onboarding Upsell Screen `[NO DEV ACCOUNT NEEDED]`
**File:** `Gleam/Features/IntroFeature/OnboardingView.swift`

Add a final onboarding step after Google Sign-In:
- Shows the 3 Pro features
- "Start Free" (dismiss) and "Try Pro" (opens PaywallView) buttons
- Shown once only on first launch

### 2. Firebase Subscription Verification (Server-side) `[NO DEV ACCOUNT NEEDED]`
**File:** `functions/src/index.ts`

Add a `verifySubscription` callable function:
- Accepts Apple transaction ID
- Calls Apple's App Store Server API to confirm active subscription
- Stores status in Firestore `users/{uid}/subscription`
- Lets backend enforce premium (e.g., only generate personalized plan for Pro users)
> For MVP, client-side `Transaction.currentEntitlements` is sufficient. Add post-launch.

### 3. App Tracking Transparency (ATT) `[NO DEV ACCOUNT NEEDED]`
**File:** `Gleam/GleamApp.swift` + `Gleam/Info.plist`

- Add `NSUserTrackingUsageDescription` to Info.plist
- Call `ATTrackingManager.requestTrackingAuthorization` on first launch
- Only needed if using Firebase Analytics (which is already integrated via Firebase)

---

## To Do After Getting Dev Account

### 4. Create IAP Products in App Store Connect `[NEEDS DEV ACCOUNT]`
- Create Subscription Group "Gleam Pro"
- Product 1: `com.gleam.pro.monthly` — $4.99/month
- Product 2: `com.gleam.pro.yearly` — $34.99/year
- These Product IDs must match the code and `Gleam.storekit` exactly

### 5. Real Sandbox Testing `[NEEDS DEV ACCOUNT]`
- In Xcode: Edit Scheme → Run → Options → StoreKit Configuration → `Gleam.storekit`
- Create Sandbox tester in App Store Connect → Users → Sandbox Testers
- Test purchase flow on real device with sandbox credentials

### 6. Signing & Provisioning `[NEEDS DEV ACCOUNT]`
- Open `Gleam.xcodeproj` → Target → Signing & Capabilities → set Team
- Enable "Automatically manage signing"

### 7. TestFlight Upload `[NEEDS DEV ACCOUNT]`
```bash
bundle exec fastlane beta
```

### 8. Screenshots `[NEEDS DEV ACCOUNT]`
```bash
bundle exec fastlane screenshots
```
(Needs a macOS machine with Xcode + Simulator)

### 9. App Store Submission `[NEEDS DEV ACCOUNT]`
```bash
bundle exec fastlane release
```

---

## Freemium Tier Reference

| Feature | Free | Gleam Pro |
|---|---|---|
| Scans/day | 3 | Unlimited |
| Scan history | Last 10 | Full |
| Personalized AI Plan | ❌ | ✅ |
| Achievements & Flow | ✅ | ✅ |
| Share results | ✅ | ✅ |

**Product IDs (must match App Store Connect exactly):**
- `com.gleam.pro.monthly` — $4.99/month
- `com.gleam.pro.yearly` — $34.99/year

---

## ⚠️ Xcode Setup — Do Before Testing (No Dev Account Needed)

To enable local StoreKit testing without a dev account:
1. Open `Gleam.xcodeproj`
2. Product → Scheme → **Edit Scheme**
3. **Run → Options → StoreKit Configuration** → select `Gleam/Configuration/Gleam.storekit`
4. Build and run on Simulator — purchases will use local test products, no Apple account needed

Once set, you can test the full paywall flow:
- Use up 3 scans to trigger the paywall
- Tap Subscribe — Xcode will prompt with a fake purchase sheet
- After "purchase", `isPremium` becomes `true` and all limits are lifted
- Check Settings to confirm Pro status is shown
