# Gleam iOS App MVP

Gleam is a SwiftUI iOS app that analyzes teeth photos using a secure backend powered by OpenAI's `gpt-4o-mini` vision model to provide personalized whitening recommendations. The frontend MVP implements core features like scanning, results display, history, and settings with a privacy-first approach.

See [AGENT.md](AGENT.md) for development guidelines and architecture patterns. Track progress in [roadmap.md](roadmap.md).

## Prerequisites

- **Xcode**: Version 16.0+ with iOS 18.0 SDK (deployment target: iOS 18.0).
- **iOS Simulator**: Default is `Iphone17ProSimulator` (UUID: `7A60F66C-2FAC-4007-A069-81CFEA4C2C02`). List available with `xcrun simctl list`.
- **Firebase Account**: For Auth, Firestore, Storage, and Cloud Functions.
- **OpenAI Account**: API key for vision analysis (stored in backend secrets only).
- **CocoaPods/Swift Package Manager**: Not required; project uses native dependencies.

## Local Setup

1. **Clone and Open Project**:
   ```
   git clone <your-repo> Gleam
   cd Gleam
   open Gleam.xcodeproj
   ```

2. **Build and Run**:
   - Select the `Gleam` scheme and `Iphone17ProSimulator` destination.
   - Press Cmd+R to build and run.
   - Or via CLI:
     ```
     xcodebuild -scheme Gleam -destination 'platform=iOS Simulator,id=7A60F66C-2FAC-4007-A069-81CFEA4C2C02' build
     xcrun simctl boot 7A60F66C-2FAC-4007-A069-81CFEA4C2C02
     open -a Simulator
     ```

   The app launches with onboarding (first time), then tab-based navigation (Home, Scan, History, Settings). Scan uses PhotosPicker for demo; backend integration pending.

3. **Previews and Hot Reload**: Use Xcode previews for SwiftUI views. No need for `expo start`—this is native iOS.

## Backend Setup

The frontend mocks backend calls. To make it functional:

1. **Create Firebase Project**:
   - Go to [Firebase Console](https://console.firebase.google.com).
   - Create a new project (e.g., "gleam-prod").
   - Enable Authentication (Sign in with Apple, Email/Password).
   - Enable Firestore and Storage.

2. **Firestore/Storage Rules and Indexes**:
   - Firestore Rules (restrict to authenticated users):
     ```
     rules_version = '2';
     service cloud.firestore {
       match /databases/{database}/documents {
         match /users/{userId} { allow read, write: if request.auth != null && request.auth.uid == userId; }
         match /scans/{scanId} { allow read, write: if request.auth != null && resource.data.userId == request.auth.uid; }
         match /feedback/{feedbackId} { allow read, write: if request.auth != null && resource.data.userId == request.auth.uid; }
       }
     }
     ```
   - Storage Rules (per-user paths):
     ```
     rules_version = '2';
     service firebase.storage {
       match /b/{bucket}/o {
         match /users/{userId}/{allPaths=**} { allow read, write: if request.auth != null && request.auth.uid == userId; }
       }
     }
     ```
   - Add indexes for scans list (userId + createdAt).

3. **Deploy Cloud Functions**:
   - Install Firebase CLI: `npm install -g firebase-tools`.
   - Init Functions: `firebase init functions` (choose JavaScript/TypeScript).
   - Implement `/analyze` endpoint (Node.js example):
     ```javascript
     const functions = require('firebase-functions');
     const admin = require('firebase-admin');
     const OpenAI = require('openai');
     admin.initializeApp();

     const openai = new OpenAI({ apiKey: functions.config().openai.key });

     exports.analyze = functions.https.onRequest(async (req, res) => {
       if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');
       const { image } = req.body; // Base64 or multipart
       const userId = req.user.uid; // Verify ID token

       // Validate/Compress image server-side
       // Call OpenAI
       const response = await openai.chat.completions.create({
         model: 'gpt-4o-mini',
         messages: [
           { role: 'system', content: 'You are a cosmetic dental assistant. Output only valid JSON per ScanResult schema.' },
           { role: 'user', content: [{ type: 'text', text: 'Analyze teeth photo for whitening plan.' }, { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${image}` } }] }
         ],
         response_format: { type: 'json_object' },
         temperature: 0.2
       });

       const result = JSON.parse(response.choices[0].message.content);
       // Validate/Store in Firestore/Storage
       await admin.firestore().collection('scans').add({ userId, ...result, createdAt: admin.firestore.FieldValue.serverTimestamp() });
       // Generate signed URL for preview

       res.json({ result, previewUrl: 'signed-url' });
     });
     ```
   - Set OpenAI key: `firebase functions:config:set openai.key="your-key"`.
   - Deploy: `firebase deploy --only functions`.

4. **Integrate Backend**:
   - Update `AppConfig.apiBaseURL` to your Firebase Functions URL (e.g., `https://us-central1-gleam-prod.cloudfunctions.net`).
   - Implement real repositories using Firebase SDKs (add via SPM: Firebase/Auth, Firestore, Storage).
   - Replace fake analyze/fetch with HTTP calls to `/analyze` and Firestore queries.

## Environment Configuration

- **API_BASE_URL**: Set in `Info.plist` (key: `API_BASE_URL`, value: your backend URL) or use `.xcconfig`:
  ```
  // Debug.xcconfig
  API_BASE_URL = https://us-central1-gleam-dev.cloudfunctions.net
  ```
  - Reference in code: `Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL")`.

- **Feature Flags**: Add to `Info.plist` (e.g., `ENABLE_MOCKS = YES` for dev).

- **No Client Secrets**: OpenAI key stays in backend. Use Firebase config for anon keys if needed.

## Running the App

- **Simulator**: Boot with `xcrun simctl boot 7A60F66C-2FAC-4007-A069-81CFEA4C2C02`.
- **Build/Run CLI**:
  ```
  xcodebuild -scheme Gleam -destination 'platform=iOS Simulator,id=7A60F66C-2FAC-4007-A069-81CFEA4C2C02' build
  ```
- **Debug**: Attach debugger, use Xcode console. App mocks backend—scan returns sample data.

- **Onboarding**: First launch shows 3-slide intro (scan, privacy, plan). Dismiss with "Get Started".

## Testing

1. **Unit Tests**:
   - Run via Xcode (Cmd+U) or CLI:
     ```
     xcodebuild test -scheme Gleam -destination 'platform=iOS Simulator,id=7A60F66C-2FAC-4007-A069-81CFEA4C2C02'
     ```
   - Current: Codable round-trip for `ScanResult`. Add more for models, HTTP client.

2. **UI Tests**:
   - Run via Xcode or CLI (same as above).
   - Current: Basic tab navigation and button existence. Expand for flows (scan → results).

3. **Previews**: Use Xcode previews for SwiftUI views (Cmd+Opt+P).

4. **CI Setup** (GitHub Actions example in `.github/workflows/ci.yml`):
   ```
   name: CI
   on: [push, pull_request]
   jobs:
     test:
       runs-on: macos-14
       steps:
       - uses: actions/checkout@v4
       - run: xcodebuild test -scheme Gleam -destination 'platform=iOS Simulator,name=iPhone 15' -enableCodeCoverage YES
       - run: xcrun xccov view --report --only-targets --json Coverage.xcresult > coverage.json
   ```
   - Update simulator to `iPhone 15` or match your UUID.

## Next Steps

To make functional (per roadmap.md Progress section):

1. **Backend**: Deploy Cloud Functions with OpenAI integration. Update repositories to call `/analyze`.
2. **Auth**: Add Firebase Auth. Implement `AuthenticationFeature` with Sign in with Apple/email. Wire to repositories.
3. **Storage**: Use Firestore for scans/history, Storage for images with signed URLs.
4. **Data Controls**: Add delete account/data in Settings (call backend endpoints).
5. **Animations/Accessibility**: Polish score ring animation, add VoiceOver labels, respect Reduce Motion.
6. **CI/CD**: Set up GitHub Actions for tests/coverage. Gate PRs on passing tests.
7. **Beta**: Archive build (Product > Archive), upload to App Store Connect.

See [roadmap.md](roadmap.md) for milestones and remaining features.

## Troubleshooting

- **Build Errors**: Ensure iOS 18 SDK. Clean build folder (Cmd+Shift+K).
- **Simulator Issues**: Boot manually: `xcrun simctl boot 7A60F66C-2FAC-4007-A069-81CFEA4C2C02`. Erase if needed: `xcrun simctl erase 7A60F66C-2FAC-4007-A069-81CFEA4C2C02`.
- **Photos Permissions**: App requests on first scan. Test denied state in simulator (Settings > Privacy > Photos).
- **API Errors**: Check console for `AppConfig.apiBaseURL`. Mock mode uses fake data—no backend needed.
- **Firebase Auth**: Enable providers in console. Handle token refresh in adapters.
- **Hot Laptop**: Run builds in Xcode (faster than CLI). Close other apps during long compiles.

For architecture questions, refer to [AGENT.md](AGENT.md). Report issues or PRs welcome!
