# AGENTS.md

Guide for agents editing Gleam. Keep terse. Preserve project contracts over prose.

## Identity

- Product: Gleam, SwiftUI iOS app for smile capture, AI teeth-whitening analysis, history, achievements, brushing habits, personalized plans.
- Xcode project/scheme/target: `Gleam.xcodeproj` / `Gleam` / `Gleam`.
- Bundle id: `baludev.Gleam`. Deployment target: iOS `26.0`. Swift: `5.0`.
- Backend: Firebase Functions v2 in `functions/`, TypeScript, OpenAI `gpt-4o-mini`.
- Public pages: `public/index.html`, `public/privacy.html`, `public/terms.html`.

## Workflow

- Start with `git status --short`. Repo often has user edits. Never revert user changes unless asked.
- Use XcodeBuildMCP for Apple work. First call `session_show_defaults`; if missing/wrong, set project `/Users/andreibalu/CODE/xcode/Gleam/Gleam.xcodeproj`, scheme `Gleam`, device below.
- Default hardware from Andrei prefs: build/run/test on Andrei's iPhone 15 Pro, identifier `00008130-000471A80C81001C`, UDID `BAE98D59-834B-5B20-8E9A-8943DCE6F7FD`. Use simulator only if user asks or device workflow is impossible.
- Test command preference: XcodeBuildMCP `test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]`. Mac cannot handle parallel destinations reliably.
- Build only after Swift/project changes likely to affect compile, before handoff on meaningful app edits, or when user asks. Do not build for docs-only edits.
- Run focused tests for behavior/model/repository/store changes. Run full tests before PR/commit or broad/shared changes. Do not run tests for pure copy/docs unless requested.
- CLI fallback only if MCP unavailable:
  - `xcodebuild -project Gleam.xcodeproj -scheme Gleam -destination 'platform=iOS,id=00008130-000471A80C81001C' build`
  - `xcodebuild -project Gleam.xcodeproj -scheme Gleam -destination 'platform=iOS,id=00008130-000471A80C81001C' -parallel-testing-enabled NO test`

## Layout

- `Gleam/GleamApp.swift`: Firebase setup, root stores/dependencies.
- `Gleam/ContentView.swift`: tab shell, onboarding/history routing.
- `Gleam/Core/CoreDomain/`: models, repository protocols, stores, persistence.
- `Gleam/Core/CoreNetworking/HTTPClient.swift`: async JSON HTTP helper.
- `Gleam/Core/CoreUI/`: design tokens, theme, shared components, haptics.
- `Gleam/Features/HomeFeature/`: dashboard, plan, achievements, brushing card.
- `Gleam/Features/ScanFeature/`: capture/library, Vision validation, analysis flow.
- `Gleam/Features/ResultsFeature/`: score/detail UI.
- `Gleam/Features/HistoryFeature/`: history list, averages, deletion, image loading.
- `Gleam/Features/IntroFeature/`: onboarding capture, Google sign-in.
- `Gleam/Features/SettingsFeature/`: theme, account, onboarding reset.
- `Gleam/Features/FlowFeature/`: guided 2-minute brushing.
- `Gleam/Support/Camera/`: UIKit/PHPicker bridge.
- `Gleam/Support/PreviewSupport/`, `Gleam/Support/TestSupport/`: previews/fixtures.
- `GleamTests/`: unit tests. `GleamUITests/`: UI/launch tests.
- `functions/src/index.ts`: HTTPS functions + OpenAI prompts.

`HomeView.swift` and `ScanView.swift` are large. Prefer private local subviews/helpers before new files. Add files only for real reuse/ownership gain.

## App Architecture

- `GleamApp` configures Firebase outside XCTest; creates `FirebaseAuthRepository`, `RemoteScanRepository`, `PersistentHistoryRepository`, `HistoryStore`, `AchievementManager`, `BrushingHabitStore`, `ScanSession`; injects repositories via custom `EnvironmentValues`, stores via `@EnvironmentObject`.
- XCTest path uses no-op repositories/stores. New unit tests use doubles, never Firebase/OpenAI.
- `ContentView` tabs: Home, Scan, History, Settings. Onboarding uses `@AppStorage("didCompleteOnboarding")`.
- UI tests pass `--uitest-skip-onboarding`; `HistoryStore.load()` uses that flag to reset persistent history once per app run.
- Domain access is repository-driven: `ScanRepository` for analyze/latest/plan/history/delete remote; `HistoryRepository` for local list/delete; `AuthRepository` for Firebase/Google auth, token, sign-out, account deletion.

## Scan Contract

- `CameraCaptureView`: simulator uses `PHPickerViewController`; device uses front `UIImagePickerController`. Images compressed to max 1024px JPEG quality `0.7`.
- `ScanView`: Vision validates face + visible smile/teeth before repository call; crops mouth/teeth for API when possible; saves original compressed image data for history.
- Client sends selected stain tags as prompt keywords, plus max 5 previous takeaways + 5 recent tag-history entries.
- Backend maps keywords to canonical tag ids. Client stores/displays by id through `StainTag.defaults`.
- Backend `whitenessScore` is `0...100`; UI usually displays `0...10` via `/ 10.0`.
- `ScanResult` decodes legacy `planSummary` into `personalTakeaway`.

## Persistence

- Local history JSON: `PersistentHistoryRepository`, Application Support by default.
- Achievements reuse `PersistentHistoryRepository` via `AchievementPersisting`; file `achievements.json`.
- Images stored by `LocalImageStorage`, keyed by history item id.
- `HistoryStore.sync(with:)`: merge remote into local without losing photos. Duplicate = matching `ScanResult` and `createdAt` within 120 seconds; remote id wins; local image moves to remote id.
- Delete history: try remote delete first, then always delete local repo data + local image.
- Brushing habits: `UserDefaultsBrushingHabitPersistence`, key `brushing_habit_snapshot`, max 90 days, local-day streak logic.

## Plans + Backend

- Plan constants in Firebase Functions: `PLAN_CONTEXT_SCAN_LIMIT = 10`, `PLAN_MIN_SCANS_FOR_PERSONALIZED_PLAN = 10`, `PLAN_REFRESH_INTERVAL = 10`.
- Before 10 scans: backend returns default plan, metadata reason `insufficient-scans`.
- After 10 scans: `plan` / `planLatest` generate or return cached OpenAI plan. Reuse personalized plan until 10 more scans.
- `HomeView` shows baseline/personalized toggle only when metadata says personalized plan exists.
- All user-data endpoints require `Authorization: Bearer <Firebase ID token>`.
- Endpoints: `analyze POST` body `{ image, tags, previousTakeaways, tagHistory }` returns `{ id, result, contextTags, createdAt, streak }`; `history GET` returns `{ items }`; `history/latest GET` 404 when none; `history DELETE` body/query `id`; `plan POST`; `planLatest/latest GET`.
- Firestore paths: scans at `users/{uid}/scanResults`, plan metadata on `users/{uid}`. Rules only match user doc + `scans/{scanId}`; Admin SDK bypasses, direct client achievement sync may need rules.

## Config + Secrets

- Swift packages resolved by Xcode. Direct app package products: `FirebaseAuth`, `GoogleSignIn`.
- `AchievementManager` imports `FirebaseFirestore` under `#if canImport(FirebaseFirestore)`; sync may compile out.
- `Gleam/GoogleService-Info.plist` required locally, gitignored. Do not delete or commit replacement secrets.
- `OPENAI_API_KEY` belongs only in Firebase Functions secrets.
- `APIConfiguration.swift` reads Info.plist keys first: `API_ANALYZE_URL`, `API_PLAN_URL`, `API_PLAN_LATEST_URL`, `API_HISTORY_LATEST_URL`, `API_HISTORY_URL`.
- If endpoint keys missing, URLs derive from hard-coded Cloud Run analyze URL by replacing host function prefix.
- App code reads per-endpoint Info.plist keys, not `API_BASE_URL`: `API_ANALYZE_URL`, `API_PLAN_URL`, `API_PLAN_LATEST_URL`, `API_HISTORY_LATEST_URL`, `API_HISTORY_URL`.
- `buildServer.json` is intentionally ignored local tooling. Regenerate locally if needed.

## UI Rules

- Current state stack: `ObservableObject`, `@StateObject`, `@EnvironmentObject`, `@Published`, Combine. No broad `@Observable` migration unless asked.
- Keep UI state close to views. Add view model only if it removes real complexity or matches existing store pattern.
- Use `@MainActor` for mutable UI-facing stores/tests.
- Shared styling lives in `Core/CoreUI`: `AppSpacing`, `AppRadius`, `AppColors`, `AppBackground`, `PrimaryButtonStyle`, `SecondaryButtonStyle`, `ToastView`, `AppHaptics`.
- Preserve UI test accessibility ids: `home_scan_button`, `scan_take_photo_button`, `scan_take_new_photo_button`, `camera_sheet`, `plan_mode_toggle`, `plan_progress_banner`.
- Haptics matter. Use `AppHaptics` / `BrushingHaptics`, not scattered generators.
- `SettingsView` sign-out/delete reset onboarding/session; delete also clears local history + brushing habit state.

## Tests

- Covered: Codable compatibility, `RemoteScanRepository`, `HistoryStore`, `PersistentHistoryRepository`, `LocalImageStorage`, achievements, brushing habits, `FlowEngine`, `ScanSession`.
- Some tests intentionally retain store instances in static arrays under `#if DEBUG` to avoid Combine/@Published XCTest teardown crashes. Do not remove without reproducing/fixing.
- UI tests: `GleamUITests.testBasicNavigation` launches with `--uitest-skip-onboarding` and expects clean empty history, Home scan button, Scan photo/library actions, tab nav. `GleamUITestsLaunchTests.testLaunch` does not skip onboarding and keeps screenshot.
- App behavior changes: add/update focused unit tests in `GleamTests/` when practical.
- Backend contract changes update all: `functions/src/index.ts`, `Gleam/Core/CoreDomain/Models.swift`, `Gleam/Core/CoreDomain/RemoteScanRepository.swift`, related tests.
- New persisted fields must decode old local JSON + old backend payloads.

## Backend Commands

- In `functions/`: `npm install`, `npm run lint`, `npm run build`, `npm run serve`, `npm run deploy`.
- `functions/node_modules/` not checked in. Firebase deploy runs lint + TypeScript build via `firebase.json` predeploy.

## Release Gotchas

- `Info.plist` has Google URL scheme. Camera usage text injected through Xcode build settings; review permission strings before release.
- `Appstore.md` is checklist, not proof done.
- Public privacy/terms hosted from `public/`; Settings links point to Firebase Hosting domain.
- Firebase deploy ignores `functions/lib/**/*.js`; hosting rewrites map to `/index.html`.
- Keep secrets out of Swift, docs, commits.
