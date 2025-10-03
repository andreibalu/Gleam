# TODO: Complete Backend Integration

## Remaining Steps to Make App Functional

### 1. Configure Firebase Functions URL
**File:** `Gleam/Core/CoreDomain/APIConfiguration.swift` (line 14)

Replace:
```swift
static let firebaseFunctionsURL = "YOUR_FIREBASE_FUNCTIONS_URL_HERE"
```

With your actual URL:
```swift
static let firebaseFunctionsURL = "https://us-central1-gleam-prod.cloudfunctions.net"
```

---

### 2. Deploy Firebase Functions with OpenAI Integration

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Initialize Functions
firebase init functions

# Set OpenAI API key (BACKEND ONLY - never in iOS app)
firebase functions:config:set openai.key="sk-your-openai-api-key-here"

# Deploy
firebase deploy --only functions
```

**Required endpoint:** `POST /analyze`
- Accepts image data (base64 or multipart)
- Calls OpenAI GPT-4o-mini vision API
- Returns `ScanResult` JSON

Example implementation in README.md lines 76-109.

---

### 3. Implement Real Repository
Replace `FakeScanRepository` with `RemoteScanRepository` that:
- Uses `HTTPClient` to call Firebase Functions `/analyze`
- Handles authentication tokens
- Processes responses into `ScanResult` model

Wire up in `GleamApp.swift`

---

### 4. Optional: Add Firebase Auth
- Enable Sign in with Apple in Firebase Console
- Implement authentication flow
- Secure backend endpoints with ID token validation

---

## Security Checklist
- [ ] OpenAI API key set in Firebase Functions config (backend only)
- [ ] Never commit API keys to git
- [ ] Firebase Functions URL configured in iOS app
- [ ] Firestore/Storage security rules deployed

---

See **AGENT.md** for architecture patterns and **README.md** for detailed setup.

