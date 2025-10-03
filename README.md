# Gleam - Teeth Whitening Analysis App

SwiftUI iOS app that analyzes teeth photos using OpenAI's GPT-4o-mini vision model via a secure Firebase backend.

**Architecture:** See [AGENT.md](AGENT.md) for patterns and practices  
**Next Steps:** See [TODO.md](TODO.md) for remaining integration tasks

---

## Quick Start

### Prerequisites
- Xcode 16.0+ with iOS 18.0 SDK
- iOS Simulator: `Iphone16Sim` (UUID: `7A11EA66-5190-41ED-80B7-DBEB5CE9050B`)
- Firebase project with Functions, Firestore, Storage enabled
- OpenAI API key (stored in Firebase Functions secret)

### Build & Run

```bash
# Open project
open Gleam.xcodeproj

# Or build via CLI
xcodebuild -scheme Gleam \
  -destination 'platform=iOS Simulator,id=7A11EA66-5190-41ED-80B7-DBEB5CE9050B' \
  build
```

### Current State
- ✅ Complete UI/UX (Onboarding, Scan, Results, History, Settings)
- ✅ RemoteScanRepository wired to Firebase Functions backend
- ✅ OpenAI-powered analysis results persisted to Firestore
- 🔜 Optional hardening (auth, regression checklist) tracked in `TODO.md`

---

## Architecture

### Structure
```
Gleam/
├── Core/
│   ├── CoreDomain/      # Models, repositories, config
│   ├── CoreNetworking/  # HTTP client
│   └── CoreUI/          # Design tokens, components
├── Features/
│   ├── HomeFeature/     # Main dashboard
│   ├── ScanFeature/     # Photo capture & upload
│   ├── ResultsFeature/  # Analysis display
│   ├── HistoryFeature/  # Past scans
│   └── SettingsFeature/ # User preferences
└── Support/
    ├── PreviewSupport/  # Sample data for previews
    └── TestSupport/     # Test fixtures
```

### Key Patterns (from AGENT.md)
- **Repository pattern** for data access
- **Environment-based DI** for testability  
- **Protocol-first design** for abstractions
- **Swift Concurrency** (async/await)
- **TDD discipline** (tests first)

---

## Backend Integration

- Cloud Functions source lives in [`functions/src/index.ts`](functions/src/index.ts) (TypeScript, deployed via `firebase deploy`).
- Secrets such as `OPENAI_API_KEY` are stored with `firebase functions:secrets:set` and injected at runtime.
- The iOS app uses `RemoteScanRepository` + `DefaultHTTPClient` to call `/analyze` and `/history/latest`; stubs are in `Core/CoreDomain`.
- Detailed setup and deployment checklist is maintained in [`TODO.md`](TODO.md).

---

## Testing

```bash
# Run all tests
xcodebuild test -scheme Gleam \
  -destination 'platform=iOS Simulator,id=7A11EA66-5190-41ED-80B7-DBEB5CE9050B'

# Or in Xcode: Cmd+U
```

**Test Coverage:**
- Unit: `GleamTests/` (model serialization, business logic)
- UI: `GleamUITests/` (navigation, accessibility)
- Previews: All views have SwiftUI previews

---

## Security

- ✅ OpenAI API key in backend only (Firebase Functions config)
- ✅ No secrets in iOS app or version control
- ✅ User data isolated per-user in Firestore/Storage
- ✅ Signed URLs for image access
- ✅ ID token validation on backend

---

## Data Models

### ScanResult
```swift
struct ScanResult: Codable, Equatable {
  let whitenessScore: Int        // 0-100
  let shade: String              // VITA classical shade
  let detectedIssues: [DetectedIssue]
  let confidence: Double         // 0-1
  let recommendations: Recommendations
  let referralNeeded: Bool
  let disclaimer: String
  let planSummary: String
}
```

### DetectedIssue
```swift
struct DetectedIssue: Codable, Equatable {
  let key: String      // staining|plaque|tartar|gingivitis_risk|...
  let severity: String // low|medium|high
  let notes: String
}
```

### Recommendations
```swift
struct Recommendations: Codable, Equatable {
  let immediate: [String]
  let daily: [String]
  let weekly: [String]
  let caution: [String]
}
```

---

## Troubleshooting

**Build Errors:**
- Clean build folder: `Cmd+Shift+K`
- Ensure iOS 18.0 SDK installed

**Simulator Issues:**
```bash
# Boot simulator manually
xcrun simctl boot 7A11EA66-5190-41ED-80B7-DBEB5CE9050B

# Erase if corrupted
xcrun simctl erase 7A11EA66-5190-41ED-80B7-DBEB5CE9050B
```

**API Errors:**
- Check `APIConfiguration.swift` has correct Firebase Functions URL
- Verify OpenAI key set in Functions: `firebase functions:config:get`
- Check Cloud Functions logs: `firebase functions:log`

---

## Next Steps

See [TODO.md](TODO.md) for remaining integration tasks.

Key items:
1. Finish Phase 3 regression checklist (see `TODO.md`).
2. Wire up optional authentication once backend enforces per-user access.

---

For architecture details and coding patterns, see [AGENT.md](AGENT.md).
