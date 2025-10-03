## Fixes and Refinements

### 1) Home: "Scan your smile" should open the camera ✅
- Implemented shared `ScanSession`, reusable `CameraCaptureView`, and automatic tab routing after capture.
- Simulator fallback via photo picker when camera unavailable.
- Accessibility identifiers preserved.

### 2) Scan tab: show "Take photo" when no image; redirect to Home to capture ✅
- Scan tab now offers "Take photo" when empty and "Take a new photo" alongside library option when an image exists.
- Uses cross-tab flag in `ScanSession` to trigger Home camera sheet.

### 3) History: allow deleting items ✅
- Added `HistoryItem` model, `HistoryStore`, and in-memory repository with async delete support.
- History tab now loads shared store, renders empty state, and supports swipe-to-delete.
- New scan results append to the shared history immediately after analysis.

### 4) Settings: add "Reset onboarding" ✅
- Added destructive Reset onboarding button with confirmation alert in `SettingsView` that clears onboarding flag and scan session.
- `ContentView` now re-presents onboarding whenever the flag flips back to false.
- UI tests reset persisted history when skipping onboarding to guarantee empty state.

### 5) Onboarding: guided capture → preview → loading → Google auth → handoff to Scan
- **Goal**: Replace the static 3-page onboarding with an interactive flow:
  1. Show a large "Scan your smile" button that opens the camera.
  2. After capture, show a preview of the photo and a primary "Make them Gleam" button.
  3. On tap, show a minimal, elegant loading animation while preparing auth.
  4. Prompt the user to sign in with Google (Apple Sign In deferred until developer account available). After success, complete onboarding.
  5. Handoff: ensure the captured image appears in the Scan tab ready for "Analyze".
- **Agent must do**:
  - UI/Flow:
    - Refactor `OnboardingView` into states: `intro → capture → preview → loading → auth`.
    - Reuse `CameraCaptureView` for capture; store data in `ScanSession`.
    - Add a minimalist animation view (e.g., `GleamLoadingView`) matching the app style.
  - Auth integration:
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
    - Google auth succeeds and tokens are sent to backend on analyze/history requests.
    - After onboarding, the captured photo is visible in `ScanView` and "Analyze" works end-to-end.
  - Manual steps:
    - Google Sign-In:
      - In Google Cloud Console, create an iOS OAuth client for the app bundle id and download/update `GoogleService-Info.plist`.
      - In Xcode, add the Reverse Client ID as a URL Scheme (from `GoogleService-Info.plist`).
      - In Firebase Console, enable Google provider under Authentication.
    - Firebase setup:
      - Ensure Firebase is initialized on app launch (requires valid `GoogleService-Info.plist` in the app target).
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

