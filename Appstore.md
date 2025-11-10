### App Store Ship Checklist (Gleam)

- [ ] Enroll in Apple Developer Program (create Apple ID, enable 2FA)
- [ ] Create App in App Store Connect (Bundle ID, platforms, SKU)
- [ ] Configure signing/certificates in Xcode (team, automatic signing)
- [ ] Add Info.plist usage strings: NSCameraUsageDescription, NSPhotoLibraryUsageDescription
- [ ] Verify Firebase prod `GoogleService-Info.plist` (Release), URL scheme matches
- [ ] Set production API base URL (Info.plist/xcconfig `API_BASE_URL`)
- [ ] App Privacy: fill questionnaire + Privacy Nutrition Label
- [ ] Store listing: name, subtitle, description, keywords, support URL
- [ ] Screenshots (6.7", 6.1", iPad if applicable) + optional preview video
- [ ] Versioning: set Marketing Version and Build number
- [ ] Archive and upload via Xcode Organizer (or Transporter)
- [ ] TestFlight internal testing; optional external testing
- [ ] Submit for App Review
- [ ] Backend: confirm endpoints live and auth works with production project

### Quick notes
- The app will be fully functional without your laptop once published, as long as the backend is deployed and `GoogleService-Info.plist` + `API_BASE_URL` point to production.
- Current project: add missing Info.plist usage strings and confirm production Firebase/URL config before upload.
