## Gleam MVP Roadmap

### Objectives
- **Deliver an MVP SwiftUI app** that analyzes teeth photos and returns whitening recommendations using a secure backend that calls OpenAI `gpt-4o-mini` vision via Chat Completions.
- **Ship TDD-first** with XCTest and SwiftUI Previews; enforce tests in CI via `xcodebuild mcp` against the `Iphone17ProSimulator`.
- **Follow agent.md best practices** for architecture, naming, modularity, and SwiftUI conventions.
- **Privacy-first**: no API keys on-device, images private by default, explicit user consent, simple data-deletion flow.

### Non-Goals (MVP)
- Native on-device ML analysis (use OpenAI backend only).
- Localization beyond English.
- Multi-platform beyond iOS.

## Guiding Principles (from agent.md)
- **Module-first architecture**: feature packages with clear boundaries; shared core modules for domain, networking, auth, persistence, UI kit.
- **TDD discipline**: red → green → refactor on every slice; avoid building UI without tests.
- **Swift Concurrency** first (async/await); Combine only if explicitly advised by agent.md patterns.
- **Dependency injection** via protocols and environment composition; side effects isolated in adapters.
- **Accessibility and performance** as first-class requirements.

## Architecture Overview
### Targets & Packages
- `GleamApp` (iOS App)
- `Features/AuthenticationFeature` (Sign in with Apple + email/password UI + flows)
- `Features/HomeFeature` (CTA, last result card)
- `Features/ScanFeature` (camera, overlay, import/retake, compression/crop)
- `Features/ResultsFeature` (score ring, shade, issues, plan, improvement)
- `Features/HistoryFeature` (list + detail + share/export)
- `Features/SettingsFeature` (profile, theme, privacy, terms, delete data, logout)
- `Core/CoreDomain` (models, value types, `ScanResult`, errors)
- `Core/CoreNetworking` (HTTP client, request builders, response decoding, retries)
- `Core/CoreAuth` (Apple + Firebase auth abstraction, keychain session)
- `Core/CoreStorage` (Firestore/Storage repositories, caching)
- `Core/CoreUI` (design tokens, gradients, buttons, sparkle/shine, ring)
- `Support/TestSupport` (mocks, fixtures, test drivers)
- `Support/PreviewSupport` (preview providers, sample data)

### Layering
- **UI (SwiftUI)** → **Feature Interactors/ViewModels** → **Use Cases** → **Repositories (Auth/Scan/History)** → **Adapters (Firebase/Backend)** → **HTTP/Storage Clients**.
- All external services behind protocols; test with fakes/mocks.

### Project Structure (illustrative)
```
Gleam.xcodeproj / Gleam.xcworkspace
├─ App/
│  └─ GleamApp.swift
├─ Features/
│  ├─ AuthenticationFeature/
│  ├─ HomeFeature/
│  ├─ ScanFeature/
│  ├─ ResultsFeature/
│  ├─ HistoryFeature/
│  └─ SettingsFeature/
├─ Core/
│  ├─ CoreDomain/
│  ├─ CoreNetworking/
│  ├─ CoreAuth/
│  ├─ CoreStorage/
│  └─ CoreUI/
├─ Support/
│  ├─ TestSupport/
│  └─ PreviewSupport/
└─ Tests/
   ├─ Unit/
   ├─ Integration/
   └─ UITests/
```

## Backend & Security (never call OpenAI from client)
- Implement a minimal backend (Firebase Cloud Functions or Cloud Run) with endpoints:
  - `POST /analyze` – accepts image (multipart or base64 JSON), calls OpenAI `chat.completions` with `gpt-4o-mini`, returns validated JSON per `ScanResult` and a signed preview URL.
  - `GET /scans/:id` – returns stored analysis for authorized user.
  - `GET /storage/signed-url?path=...` – issues time-bound signed URL for private images.
- **Secrets**: Store OpenAI API key only in backend secret manager (e.g., GCP Secret Manager). Never ship to client.
- **Auth**: Verify Firebase ID tokens on backend; authorize per-user data access.
- **Storage**: Firebase Storage paths per-user namespace (`users/{uid}/scans/{scanId}/`), original and compressed preview. Enforce size/type limits server-side.
- **Rules**: Firestore/Storage Security Rules to restrict to owner; indexes for list views.

## Data Model (Firestore)
- Collection `users`: `{ displayName, photoURL, createdAt }`
- Collection `scans`: `{ userId, imagePath, whitenessScore, shade, detectedIssues, confidence, recommendations, disclaimer, referralNeeded, planSummary, createdAt }`
- Collection `feedback`: `{ scanId, userId, usefulness (1–5), notes, createdAt }`

### Swift Models (Codable)
```swift
struct ScanResult: Codable, Equatable {
  let whitenessScore: Int // 0-100
  let shade: String // VITA classical, else "unknown"
  let detectedIssues: [DetectedIssue]
  let confidence: Double // 0-1
  let recommendations: Recommendations
  let referralNeeded: Bool
  let disclaimer: String
  let planSummary: String
}

struct DetectedIssue: Codable, Equatable {
  let key: String // "staining|plaque|tartar|gingivitis_risk|enamel_erosion_suspected|other"
  let severity: String // "low|medium|high"
  let notes: String
}

struct Recommendations: Codable, Equatable {
  let immediate: [String]
  let daily: [String]
  let weekly: [String]
  let caution: [String]
}
```

## OpenAI Vision Integration (Backend)
- Use Chat Completions with:
  - `model: gpt-4o-mini`
  - `messages`:
    - system: "You are an expert cosmetic dental assistant. Always output only valid JSON per schema."
    - user: "Analyze the attached teeth photo for staining/discoloration, estimate shade, build whitening plan. Respond with JSON only." + image
  - `response_format: json_object`
  - `temperature: 0.2`
- **Robustness**: If JSON parse fails, retry with explicit reminder: "Return only valid JSON per the provided schema—no prose."
- **Upload handling**: Accept JPEG/HEIF; compress on client to ≤1024px longest edge, ~0.7 quality. Backend re-validates and normalizes.

## Features & Acceptance Criteria
### Splash + Intro
- Animated gradient splash and 3-slide onboarding (scan, privacy, personalized plan).
- Sparkle/shine effect on app name or CTA.
- Accessibility: VoiceOver labels for slides; dynamic type.

### Auth
- Sign in with Apple and email/password via Firebase Auth.
- Persist session securely (Keychain). Handle logout.
- Error states and loading indicators covered by tests.

### Home
- Primary CTA: "Scan your smile" with subtle animation.
- Shows last result card (score, shade, mini-issues chips) if available.

### Scan
- Camera with oval mouth alignment guide overlay; import from gallery; retake.
- Client-side crop/resize to max 1024px JPEG; preview before upload.
- Upload to backend, receive `ScanResult` and preview URL.

### Results
- Animated score ring (0–100), shade, detected issues, plan sections (immediate/daily/weekly/caution).
- Improvement tracker: compare vs previous scan score.
- Non-medical disclaimer displayed.

### History
- Paginated list of past scans with thumbnails, score, badges.
- Detail view with full analysis and share/export.

### Settings
- Profile, theme toggle, privacy/terms links.
- Data controls: delete account/data flow.
- Logout.

## TDD Strategy & Test Matrix
- Write failing test first for each feature slice; implement minimal passing code; refactor.
- Unit tests: models (Codable round-trip), validators, view models, use cases.
- Integration tests: repository ↔ adapters (mock backend), auth flows, storage paths, Firestore fetch.
- UI tests: screen navigation, accessibility identifiers, critical flows (scan → results).
- Preview tests: ensure previews compile using `PreviewSupport` data.
- Coverage: ≥90% for CoreDomain/CoreNetworking/CoreAuth; track in CI.

## CI with xcodebuild MCP
- Default simulator: `Iphone17ProSimulator` (UUID `7A60F66C-2FAC-4007-A069-81CFEA4C2C02`).
```bash
# Build & test (Debug)
xcodebuild -scheme Gleam -destination 'platform=iOS Simulator,id=7A60F66C-2FAC-4007-A069-81CFEA4C2C02' clean test | xcpretty
```
- Gate PRs on all unit/integration/UI tests passing.
- Artifacts: store test logs and screenshots from UI tests.

## Accessibility Plan
- Dynamic Type across all text; minimum contrast ratios.
- VoiceOver labels, Traits, and focus order verified in UI tests.
- Motion-reduced alternatives for animations (respect Reduce Motion).

## Animation Plan
- Native SwiftUI: spring/interpolating animations for CTA and transitions.
- Sparkle/shine: either lightweight Lottie or native mask gradient sweep; fall back to static if Reduce Motion.
- Results score ring with animated trim.

## Milestones
- **M0 (Day 0–1)**: Workspace + modules, CI skeleton, TestSupport/PreviewSupport.
- **M1 (Day 2–3)**: Auth (Apple + email), persistence, tests.
- **M2 (Day 4–5)**: Scan flow (camera, overlay, import, compress/crop), tests.
- **M3 (Day 6–7)**: Backend `/analyze`, OpenAI integration, repositories, integration tests.
- **M4 (Day 8)**: Results UI (score ring, shade, plan), improvement tracker; tests.
- **M5 (Day 9)**: History list/detail, share/export; tests.
- **M6 (Day 10)**: Settings (theme, privacy/terms, delete data), tests.
- **M7 (Day 11)**: Accessibility polish + animations; perf pass.
- **M8 (Day 12)**: README/docs, QA sweep, beta build.

## Risks & Mitigations
- **JSON non-determinism**: strict schema validation + retry with stricter instruction; property presence checks.
- **Privacy & compliance**: opt-in consent; do-not-save option; deletion endpoint; secure rules; signed URLs only.
- **Binary size & performance**: avoid heavy dependencies; lazy image loading; compress previews.
- **Auth edge cases**: offline mode, token refresh, Apple revocation; comprehensive integration tests.
- **Camera permissions**: clear copy, graceful fallbacks; tests for denied state.

## Environment & Configuration
- Use `.xcconfig` for `API_BASE_URL` (dev/staging/prod) injected at build time.
- Feature flags via Info.plist or compile-time flags for experimental UI.
- No secrets in client. Backend uses secrets manager.

## Definition of Done (MVP)
- All acceptance criteria met for each feature.
- Unit/integration/UI tests passing in CI on `Iphone17ProSimulator`.
- Accessibility checks pass (contrast, VoiceOver, Dynamic Type, Reduce Motion).
- README documents setup, CI commands, environment config, privacy/terms.
- No API keys or secrets shipped in the client.

## README Checklist (to produce alongside MVP)
- Xcode and workspace setup steps; link to `AGENT.md`.
- Backend setup: deploy functions/service, configure OpenAI key in secrets manager.
- Firebase: enable Auth providers, Firestore/Storage rules and indexes.
- Environment: `.xcconfig` keys (`API_BASE_URL`), sample `.env` for backend.
- Testing: commands to run unit/integration/UI tests via `xcodebuild`.
- Troubleshooting: Sign in with Apple, camera/storage permissions, animation performance.



## Progress (Oct 1, 2025)
- Implemented CoreDomain models and errors
- CoreNetworking HTTP client scaffolded
- Repositories protocols + FakeScanRepository
- CoreUI tokens + PrimaryButton
- Features: Home, Scan (PhotosPicker + compression to 1024px @0.7), Results (score ring, plan, ShareLink), History, Settings
- App root navigation (TabView + NavigationStacks) and environment wiring
- Onboarding (3 slides) with `didCompleteOnboarding` flag
- Unit test: Codable round-trip for `ScanResult`
- Updated CI docs to use `Iphone17ProSimulator` (UUID `7A60F66C-2FAC-4007-A069-81CFEA4C2C02`)

Remaining (MVP):
- Backend endpoints and integration (mock currently)
- Auth (Sign in with Apple + email/password) and secure persistence
- History data from storage (currently preview data)
- CI workflow file and coverage tracking
- README with setup/backends, Firebase rules/indexes, `.xcconfig`
- Accessibility verification and animations polish
- Data controls in Settings (delete account/data)