# Gleam - Teeth Whitening Analysis App

SwiftUI iOS app that analyzes teeth photos using OpenAI's GPT-4o-mini vision model via a secure Firebase backend.

**Architecture:** See [AGENT.md](AGENT.md) for patterns and practices  
**Next Steps:** See [TODO.md](TODO.md) for remaining integration tasks

---

## Quick Start

### Prerequisites
- Xcode 16.0+ with iOS 18.0 SDK
- iOS Simulator: `Iphone17ProSimulator` (UUID: `7A60F66C-2FAC-4007-A069-81CFEA4C2C02`)
- Firebase account (for Auth, Firestore, Storage, Cloud Functions)
- OpenAI API key (stored in backend only)

### Build & Run

```bash
# Open project
open Gleam.xcodeproj

# Or build via CLI
xcodebuild -scheme Gleam \
  -destination 'platform=iOS Simulator,id=7A60F66C-2FAC-4007-A069-81CFEA4C2C02' \
  build
```

### Current State
- ✅ Complete UI/UX (Onboarding, Scan, Results, History, Settings)
- ✅ Image compression (1024px @ 0.7 quality)
- ✅ API configuration ready
- ⏳ Uses mock data (backend integration pending)

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

### Firebase Setup

1. **Create Firebase Project**
   - Go to [Firebase Console](https://console.firebase.google.com)
   - Enable Authentication, Firestore, Storage

2. **Firestore Security Rules**
   ```javascript
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /users/{userId} { 
         allow read, write: if request.auth != null && request.auth.uid == userId; 
       }
       match /scans/{scanId} { 
         allow read, write: if request.auth != null && resource.data.userId == request.auth.uid; 
       }
     }
   }
   ```

3. **Storage Security Rules**
   ```javascript
   rules_version = '2';
   service firebase.storage {
     match /b/{bucket}/o {
       match /users/{userId}/{allPaths=**} { 
         allow read, write: if request.auth != null && request.auth.uid == userId; 
       }
     }
   }
   ```

### Cloud Functions with OpenAI

**Deploy Functions:**
```bash
firebase init functions
npm install openai firebase-admin
```

**Implement `/analyze` endpoint** (example):
```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const OpenAI = require('openai');

admin.initializeApp();
const openai = new OpenAI({ apiKey: functions.config().openai.key });

exports.analyze = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');
  
  const { image } = req.body; // Base64 image data
  const userId = req.user.uid; // From verified ID token
  
  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      { 
        role: 'system', 
        content: 'You are a cosmetic dental assistant. Output only valid JSON per ScanResult schema.' 
      },
      { 
        role: 'user', 
        content: [
          { type: 'text', text: 'Analyze teeth photo for whitening recommendations.' },
          { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${image}` } }
        ] 
      }
    ],
    response_format: { type: 'json_object' },
    temperature: 0.2
  });
  
  const result = JSON.parse(response.choices[0].message.content);
  
  // Store in Firestore
  await admin.firestore().collection('scans').add({
    userId,
    ...result,
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  });
  
  res.json({ result });
});
```

**Set OpenAI Key:**
```bash
firebase functions:config:set openai.key="sk-your-openai-api-key"
firebase deploy --only functions
```

**Configure iOS App:**
- Edit `Gleam/Core/CoreDomain/APIConfiguration.swift` line 14
- Replace `YOUR_FIREBASE_FUNCTIONS_URL_HERE` with your Functions URL
- Example: `https://us-central1-gleam-prod.cloudfunctions.net`

---

## Testing

```bash
# Run all tests
xcodebuild test -scheme Gleam \
  -destination 'platform=iOS Simulator,id=7A60F66C-2FAC-4007-A069-81CFEA4C2C02'

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
xcrun simctl boot 7A60F66C-2FAC-4007-A069-81CFEA4C2C02

# Erase if corrupted
xcrun simctl erase 7A60F66C-2FAC-4007-A069-81CFEA4C2C02
```

**API Errors:**
- Check `APIConfiguration.swift` has correct Firebase Functions URL
- Verify OpenAI key set in Functions: `firebase functions:config:get`
- Check Cloud Functions logs: `firebase functions:log`

---

## Next Steps

See [TODO.md](TODO.md) for remaining integration tasks.

Key items:
1. Configure Firebase Functions URL in `APIConfiguration.swift`
2. Deploy Firebase Functions with OpenAI integration
3. Replace `FakeScanRepository` with `RemoteScanRepository`
4. (Optional) Add Firebase Authentication

---

For architecture details and coding patterns, see [AGENT.md](AGENT.md).
