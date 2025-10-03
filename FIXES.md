## Fixes and Refinements

### 1) Home: "Scan your smile" should open the camera
- **Current**: `HomeView` button just switches tab via `onScanTapped` → Scan tab; no camera capture.
- **Agent must do**:
  - Add a SwiftUI camera wrapper (e.g., `CameraCaptureView`) using `UIImagePickerController` or `AVFoundation`.
    - Files: add `Gleam/Support/Camera/CameraCaptureView.swift` (SwiftUI `UIViewControllerRepresentable`).
    - Ensure `NSCameraUsageDescription` is present in the Gleam target `Info.plist`.
  - Update `HomeView` to present the camera modally when the button is tapped and store the captured image in a shared session object.
    - Introduce `ScanSession: ObservableObject` holding `capturedImageData`.
    - Provide it at the app root (in `GleamApp` or `ContentView`) via `.environmentObject`.
  - After successful capture, switch to the Scan tab and prefill the image so "Analyze" is enabled.
    - `ContentView`: on camera success, set `selectedTab = 1` and let `ScanView` read `ScanSession.capturedImageData`.
  - Simulator fallback: if camera is unavailable, fall back to `PhotosPicker` (photo library).
  - Accessibility: keep `home_scan_button` identifier; add an identifier for the camera sheet.
  - Manual steps:
    - In Xcode, add `NSCameraUsageDescription` to the target `Info.plist` with a user-facing reason.
    - If testing on a real device, grant Camera permission in iOS Settings after first prompt.

### 2) Scan tab: show "Take photo" when no image; redirect to Home to capture
- **Current**: `ScanView` shows placeholder + `PhotosPicker("Choose Photo")` when `selectedImageData == nil`.
- **Agent must do**:
  - In `ScanView`, when no image is selected, add a primary "Take photo" button.
  - On tap, set a cross-screen flag and navigate to Home:
    - Use `@AppStorage("pendingCameraCapture")` or a flag in `ScanSession` (e.g., `shouldOpenCamera = true`) and programmatically set `selectedTab = 0`.
    - `HomeView` (or `ContentView`) should observe that flag and automatically present the camera, then reset the flag.
  - Keep `PhotosPicker` as an alternate path via a secondary button/link.
  - Accessibility: add an identifier for the new button (e.g., `scan_take_photo_button`).
  - Manual steps:
    - None beyond those in Fix 1 (camera permission). Ensure simulator fallback uses photo library.

### 3) History: allow deleting items
- **Current**: `HistoryView` displays an in-memory array; no delete. `HistoryRepository` only supports `list()`; `ScanResult` lacks a stable id/timestamp.
- **Agent must do**:
  - Data model: introduce a stable identifier and timestamp for history entries.
    - Option A: extend `ScanResult` with `id: String` and `createdAt: Date`.
    - Option B: create `HistoryItem { id, createdAt, result: ScanResult }` and use that in history flows.
  - Protocols:
    - Update `HistoryRepository` to include `delete(id: String) async throws`.
    - Implement `RemoteHistoryRepository` for list/delete (Firestore path `users/{uid}/history/{id}`) or Functions endpoints (`/history/list`, `/history/delete/:id`).
  - UI:
    - `HistoryView`: bind list to repository data, add swipe-to-delete via `.onDelete(perform:)`, call repository `delete` and update local state.
    - Add an empty state view when history is empty.
  - Backend:
    - If using Functions: add `historyList` and `historyDelete` HTTP functions; require Firebase ID token; validate server-side with `firebase-admin`.
  - QA/Acceptance:
    - Deleting removes the item locally and remotely; pull-to-refresh (if added) reflects server state.
    - Unauthorized attempts return a clear error and do not modify UI state.
  - Manual steps:
    - Enable Firebase Authentication in the Firebase Console.
    - Deploy updated Functions (`firebase deploy --only functions`).
    - If using Firestore directly, deploy updated security rules (`firebase deploy --only firestore:rules`).
    - Confirm Firestore collections exist or are auto-created: `users/{uid}/history`.

### 4) Settings: add "Reset onboarding"
- **Current**: `SettingsView` only has Appearance/Privacy; onboarding tracked by `@AppStorage("didCompleteOnboarding")`.
- **Agent must do**:
  - Add a new section to `SettingsView` with a destructive-styled "Reset onboarding" button.
    - Action: set `didCompleteOnboarding = false`; optionally clear `ScanSession.capturedImageData`.
    - Present a confirmation alert.
  - `ContentView`: when `didCompleteOnboarding` becomes false, present `OnboardingView` via the existing fullScreenCover.
  - QA: reopening app or toggling the flag immediately shows onboarding.
  - Manual steps:
    - None.

### 5) Onboarding: guided capture → preview → loading → auth → handoff to Scan
- **Goal**: Replace the static 3-page onboarding with an interactive flow:
  1. Show a large "Scan your smile" button that opens the camera.
  2. After capture, show a preview of the photo and a primary "Make them Gleam" button.
  3. On tap, show a minimal, elegant loading animation while preparing auth.
  4. Prompt the user to sign in (Apple and Google). After success, complete onboarding.
  5. Handoff: ensure the captured image appears in the Scan tab ready for "Analyze".
- **Agent must do**:
  - UI/Flow:
    - Refactor `OnboardingView` into states: `intro → capture → preview → loading → auth`.
    - Reuse `CameraCaptureView` for capture; store data in `ScanSession`.
    - Add a minimalist animation view (e.g., `GleamLoadingView`) matching the app style.
  - Auth integration:
    - Add Sign in with Apple using `AuthenticationServices`.
      - Enable the capability in the target; handle nonce and token exchange.
    - Add Google Sign-In (SPM) and Firebase Auth (SPM) for unified auth.
      - Add SPM deps: `FirebaseAuth`, `GoogleSignIn` (or `GoogleSignInSwift`), initialize Firebase in `GleamApp`.
      - Acquire ID token and persist session; expose via `AuthRepository` (`currentUserId`, `authToken`).
    - Update backend Functions to validate Firebase ID tokens on all protected endpoints.
  - Handoff to Scan:
    - When onboarding completes, set `didCompleteOnboarding = true`, switch to Scan tab, and prefill image from `ScanSession` so Analyze is enabled.
  - Privacy/Permissions:
    - Ensure `NSCameraUsageDescription` exists; if using photo library fallback, include `NSPhotoLibraryAddUsageDescription` if saving.
  - QA/Acceptance:
    - Capture works on device; simulator falls back gracefully.
    - Auth (Apple/Google) succeeds and tokens are sent to backend on analyze/history requests.
    - After onboarding, the captured photo is visible in `ScanView` and "Analyze" works end-to-end.
  - Manual steps:
    - Apple Sign In:
      - In Apple Developer portal, enable Sign in with Apple for the app’s bundle identifier.
      - In Xcode, add the "Sign in with Apple" capability to the target.
    - Google Sign-In:
      - In Google Cloud Console, create an iOS OAuth client for the app bundle id and download/update `GoogleService-Info.plist`.
      - In Xcode, add the Reverse Client ID as a URL Scheme (from `GoogleService-Info.plist`).
      - In Firebase Console, enable Google provider under Authentication.
    - Firebase setup:
      - Ensure Firebase is initialized on app launch (requires valid `GoogleService-Info.plist` in the app target).
      - In Firebase Console, enable Apple provider under Authentication.
    - Backend auth enforcement:
      - Update and deploy Cloud Functions to verify Firebase ID tokens on protected endpoints.
      - If using Firestore direct access, update and deploy security rules to require authentication.

---

## File/Module Touchpoints
- `Gleam/GleamApp.swift`: provide `ScanSession` environment, initialize Firebase (for Auth).
- `Gleam/ContentView.swift`: tab routing, onboarding presentation, camera trigger plumbing.
- `Gleam/Features/HomeFeature/HomeView.swift`: present camera; pass captured image to session.
- `Gleam/Features/ScanFeature/ScanView.swift`: show "Take photo" when empty; prefill from session; analyze.
- `Gleam/Features/HistoryFeature/HistoryView.swift`: list + swipe-to-delete.
- `Gleam/Features/SettingsFeature/SettingsView.swift`: add "Reset onboarding".
- `Gleam/Features/IntroFeature/OnboardingView.swift`: implement new capture → preview → loading → auth flow.
- `Gleam/Core/CoreDomain/Repositories.swift`: extend `HistoryRepository`; add `AuthRepository` if needed.
- `Gleam/Core/CoreDomain/RemoteScanRepository.swift`: attach `Authorization: Bearer <idToken>` header if available.
- `functions/src/index.ts`: add history list/delete endpoints; verify Firebase ID tokens.

## Acceptance Checklist
- [ ] Home button opens camera; captured photo routes to Scan.
- [ ] Scan tab shows "Take photo" when empty and redirects to capture.
- [ ] History supports swipe-to-delete and persists deletions.
- [ ] Settings includes "Reset onboarding" that works immediately.
- [ ] Onboarding implements capture → preview → loading → auth (Apple + Google) → handoff.
- [ ] Backend validates ID tokens; iOS sends tokens on protected requests.

