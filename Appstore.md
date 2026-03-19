# Gleam — App Store Manual Checklist

Legend: `[NO DEV ACCOUNT NEEDED]` = do this now | `[NEEDS DEV ACCOUNT]` = wait for Apple account

---

> ⚠️ **REMINDER — DO THIS NOW IN XCODE (no dev account needed)**
> **Edit Scheme → Run → Options → StoreKit Configuration → select `Gleam/Configuration/Gleam.storekit`**
> This enables mock IAP purchases in the Simulator. Without it, the Subscribe button silently does nothing.

---

## Start Here — No Dev Account Required

- [x] **Info.plist privacy strings** `[NO DEV ACCOUNT NEEDED]` — done
- [x] **StoreKit2 subscription code** `[NO DEV ACCOUNT NEEDED]` — done
- [x] **Local `.storekit` config** for Simulator testing `[NO DEV ACCOUNT NEEDED]` — done
- [x] **Free tier scan limit** (3/day) `[NO DEV ACCOUNT NEEDED]` — done
- [x] **PaywallView** UI `[NO DEV ACCOUNT NEEDED]` — done
- [x] **Premium gating** in all views `[NO DEV ACCOUNT NEEDED]` — done
- [x] **Version numbers** in xcconfig (1.0.0 / build 1) `[NO DEV ACCOUNT NEEDED]` — done
- [x] **Fastlane setup files** (run on Mac later) `[NO DEV ACCOUNT NEEDED]` — done
- [ ] **Enable local StoreKit testing in Xcode** `[NO DEV ACCOUNT NEEDED]`
  - Edit Scheme → Run → Options → StoreKit Configuration → `Gleam/Configuration/Gleam.storekit`
- [ ] **Test paywall flow in Simulator** `[NO DEV ACCOUNT NEEDED]`
  - Verify 3-scan daily limit triggers paywall
  - Verify mock purchase sets `isPremium = true`
  - Verify Settings shows Pro status after purchase

---

## Phase 1 — Apple Developer Account

- [ ] **Enroll in Apple Developer Program** `[NEEDS DEV ACCOUNT]`
  - [developer.apple.com/programs](https://developer.apple.com/programs) — $99/year
  - Requires Apple ID with 2FA enabled
  - Takes 24–48 hours to activate

- [ ] **Create App ID** `[NEEDS DEV ACCOUNT]`
  - App Store Connect → Identifiers → "+"
  - Bundle ID: `com.gleam.app` (must match Xcode project exactly)

- [ ] **Create App in App Store Connect** `[NEEDS DEV ACCOUNT]`
  - My Apps → "+" → iOS
  - Name: "Gleam: Smile Whitening Tracker"
  - SKU: `gleam-ios-001`

---

## Phase 2 — In-App Purchases

- [ ] **Create Subscription Group** `[NEEDS DEV ACCOUNT]`
  - My Apps → Gleam → In-App Purchases → Subscriptions
  - Group name: "Gleam Pro"

- [ ] **Create Monthly product** `[NEEDS DEV ACCOUNT]`
  - Product ID: `com.gleam.pro.monthly` ← must match the code exactly
  - Duration: 1 Month | Price: $4.99 (Tier 5)

- [ ] **Create Yearly product** `[NEEDS DEV ACCOUNT]`
  - Product ID: `com.gleam.pro.yearly` ← must match the code exactly
  - Duration: 1 Year | Price: $34.99 (Tier 35)

- [ ] **Bank & Tax info** `[NEEDS DEV ACCOUNT]`
  - App Store Connect → Agreements, Tax, and Banking
  - Required before any paid IAP can go live

---

## Phase 3 — Firebase Production Setup

- [ ] **Create production Firebase project** `[NO DEV ACCOUNT NEEDED]`
  - Firebase Console → new project (e.g. `gleam-prod`)
  - Enable: Auth (Google), Firestore, Storage, Cloud Functions

- [ ] **Download production `GoogleService-Info.plist`** `[NO DEV ACCOUNT NEEDED]`
  - Firebase Console → Project Settings → iOS app → download
  - Add to Xcode target (replace dev plist for Release builds)

- [ ] **Set production `API_BASE_URL`** `[NO DEV ACCOUNT NEEDED]`
  - Update `Config/Release.xcconfig`: `API_BASE_URL = https://REGION-PROJECT.cloudfunctions.net`

- [ ] **Deploy Firebase Cloud Functions** `[NO DEV ACCOUNT NEEDED]`
  ```bash
  firebase use gleam-prod
  firebase deploy --only functions
  ```

- [ ] **Set OpenAI API key** `[NO DEV ACCOUNT NEEDED]`
  ```bash
  firebase functions:secrets:set OPENAI_API_KEY
  ```

- [ ] **Review Firestore & Storage security rules** `[NO DEV ACCOUNT NEEDED]`

---

## Phase 4 — Xcode Signing & Build (on your Mac)

- [ ] **Configure signing** `[NEEDS DEV ACCOUNT]`
  - Target → Signing & Capabilities → select your Team
  - Enable "Automatically manage signing"

- [ ] **Archive and upload** `[NEEDS DEV ACCOUNT]`
  ```bash
  bundle exec fastlane beta   # TestFlight
  # or
  bundle exec fastlane release  # App Store
  ```

---

## Phase 5 — Store Listing & Privacy

- [ ] **App Store listing copy** `[NEEDS DEV ACCOUNT]`
  - Pre-filled in `fastlane/metadata/en-US/` — review and edit before uploading
  - Upload with: `bundle exec fastlane metadata`

- [ ] **Screenshots** `[NEEDS DEV ACCOUNT]`
  - Run: `bundle exec fastlane screenshots` (needs Mac + Xcode)
  - Required: 6.7" (iPhone 16 Pro Max) and 6.1" (iPhone 16)

- [ ] **App Icon** — verify all sizes in `Assets.xcassets/AppIcon.appiconset` including 1024×1024

- [ ] **Privacy Policy URL** — already set to existing URL in `fastlane/metadata/en-US/privacy_url.txt`; update if needed

---

## Phase 6 — Privacy Questionnaire

Fill in App Store Connect → App Privacy:

- [ ] **Contact info:** email (via Google Sign-In) — linked to identity `[NEEDS DEV ACCOUNT]`
- [ ] **Identifiers:** User ID (Firebase UID) — linked to identity `[NEEDS DEV ACCOUNT]`
- [ ] **Photos:** scan photos — not linked to identity (Firebase Storage) `[NEEDS DEV ACCOUNT]`
- [ ] **Usage data:** scan frequency, scores — linked to identity (Firestore) `[NEEDS DEV ACCOUNT]`
- [ ] No location, health, financial, or ad data collected `[NEEDS DEV ACCOUNT]`

---

## Phase 7 — TestFlight & Review

- [ ] **Internal TestFlight testing** `[NEEDS DEV ACCOUNT]`
  - Upload build, add yourself, test on real iPhone
  - Create Sandbox Apple ID in App Store Connect → Users → Sandbox Testers
  - Test the full IAP purchase/restore flow with sandbox credentials

- [ ] **Submit for App Review** `[NEEDS DEV ACCOUNT]`
  - Fill review notes: "App uses camera for smile analysis. No demo account required."
  - Confirm age rating (4+)

---

## Phase 8 — Post-Launch

- [ ] **Monitor crashes** in Xcode Organizer
- [ ] **Monitor subscriptions** in App Store Connect → Sales & Trends
- [ ] **Respond to App Store reviews**
- [ ] **Watch Firebase costs** — OpenAI API charges per scan; backend rate-limiting for free tier is recommended post-launch

---

## Automation Summary

| Task | Tool | Account needed? |
|---|---|---|
| IAP code + PaywallView | Claude (done) | No |
| Local StoreKit testing | Xcode `.storekit` config (done) | No |
| Screenshots | `bundle exec fastlane screenshots` | No (Xcode/Mac only) |
| Metadata upload | `bundle exec fastlane metadata` | Yes |
| TestFlight upload | `bundle exec fastlane beta` | Yes |
| Full release | `bundle exec fastlane release` | Yes |

**To use Fastlane on your Mac:**
```bash
gem install bundler
bundle install   # reads Gemfile in project root
bundle exec fastlane [lane]
```
