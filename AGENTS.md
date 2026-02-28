# AGENTS.md

## Cursor Cloud specific instructions

### Codebase overview

Gleam is a teeth-whitening analysis iOS app (SwiftUI) with a Firebase Cloud Functions backend (TypeScript/Node.js 22). The iOS app requires macOS + Xcode and cannot be built on Linux. The Cloud Functions backend in `functions/` is the only component buildable/testable in this environment.

### Backend (`functions/`)

Standard npm scripts — see `functions/package.json`:

- **Lint:** `npm run lint` (ESLint)
- **Build:** `npm run build` (TypeScript → `lib/`)
- **Serve locally:** `firebase emulators:start --only functions --project demo-gleam`

The `--project demo-gleam` flag runs in demo mode (no real Firebase credentials needed). All 4 HTTP functions load: `analyze`, `history`, `plan`, `planLatest`.

### Gotchas

- The ESLint config (`functions/.eslintrc.js`) references `tsconfig.dev.json` in `parserOptions.project`, but this file does not exist. ESLint still works because it falls back to `tsconfig.json`. Do not remove this reference without also updating the eslint config.
- Firebase emulator requires Java (OpenJDK) and `firebase-tools` installed globally (`npm install -g firebase-tools`).
- The iOS app (`Gleam/`, `GleamTests/`, `GleamUITests/`) requires Xcode 16+ on macOS. It cannot be built, tested, or run on Linux.
- `AGENT.md` in the repo root contains SwiftUI architecture guidelines for the iOS app, not backend instructions.
