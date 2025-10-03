# Gleam - Teeth Whitening Analysis App

SwiftUI iOS app that analyzes smile photos using a Firebase-backed GPT-4o-mini workflow.

For architecture guidance and contributor conventions, see [AGENT.md](AGENT.md).

---

## Implemented Features

- **Guided Onboarding:** Intro → capture → preview → loading → Google sign-in, with Scan tab hand-off and captured photo prefill.
- **Camera Capture Everywhere:** Home “Scan your smile” button opens the camera; simulator falls back to the photo picker.
- **Scan Tab Enhancements:** Contextual call-to-action when no image, state preserved after capture, and easy retake/library options.
- **History Management:** Swipe-to-delete, persistent storage via `PersistentHistoryRepository`, and automatic empty-state handling in tests.
- **Settings Reset:** Destructive reset onboarding action that clears the walkthrough flag, resets the scan session, and re-presents onboarding immediately.

---

## Project Structure

```
Gleam/
├── Core/
│   ├── CoreDomain/      # Models, repositories, configuration
│   ├── CoreNetworking/  # HTTP client abstractions
│   └── CoreUI/          # Shared styles and components
├── Features/
│   ├── HomeFeature/
│   ├── ScanFeature/
│   ├── ResultsFeature/
│   ├── HistoryFeature/
│   └── SettingsFeature/
└── Support/
    ├── Camera/          # CameraCaptureView and helpers
    ├── PreviewSupport/  # Sample data for SwiftUI previews
    └── TestSupport/     # Fixtures for tests
```

Key patterns (detailed in `AGENT.md`): repository-driven data access, environment-based dependency injection, async/await concurrency, and protocol-oriented design.

---

## Build & Run

Prerequisites:
- Xcode 16.0+ with iOS 18 SDK
- Firebase project configured with Functions, Firestore, and Storage
- `GoogleService-Info.plist` included in the app target with Google Sign-In enabled

```bash
# Build for the default simulator
xcodebuild -scheme Gleam \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

The app automatically configures Firebase at launch when the plist is present.

---

## Backend Integration

- Cloud Functions source lives in [`functions/src/index.ts`](functions/src/index.ts); deploy via `firebase deploy`.
- Secrets (e.g., `OPENAI_API_KEY`) are managed with `firebase functions:secrets:set` and never shipped with the client.
- `RemoteScanRepository` attaches Firebase ID tokens to requests and calls `/analyze` plus `/history/latest` for the latest result.

---

## Testing

```bash
xcodebuild test -scheme Gleam \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

- Unit tests cover repositories, storage, and core models (`GleamTests`).
- UI tests verify navigation, onboarding resets, and empty-state handling (`GleamUITests`).

---

## Data Model Snapshot

`ScanResult` encapsulates the whitening analysis, including shade, confidence, detected issues, recommendations, and messaging. Supporting structs (`DetectedIssue`, `Recommendations`) live in `CoreDomain` and are encoded/decoded via `Codable`.

---

## Support

- For architecture and contribution rules, read [AGENT.md](AGENT.md).
- Firebase and Google Sign-In configuration must be completed before shipping (ID token validation occurs in backend code).
