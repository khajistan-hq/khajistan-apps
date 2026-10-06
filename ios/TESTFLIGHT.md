# TestFlight preparation

## App identity

- Display name: Khajistan
- Platform: iOS / iPadOS 17+
- Bundle identifier in the project: `com.khajistan.archive`
- Marketing version: `1.0`
- Initial build number: `1`
- Repository: `khajistan/khajistan-archive`, app under `ios/`
- Website: https://khajistan-archive.pages.dev

Apple Developer membership, the correct team and an App Store Connect app record still need to be verified in the owner's authenticated Apple session. No team, certificate, provisioning profile or App Store Connect record is assumed to exist.

## What is ready for the upload process

The Xcode scheme supports device archives, the bundle has an opaque 1024px icon, and automatic signing is configured. Camera/microphone/photo descriptions are present for explicit web contributions; audio background mode is declared for the native receiver. The GitHub workflow creates **unsigned simulator builds only** and cannot publish anything to Apple.

Use **Xcode 26 or later with the iOS 26 SDK or later** for the device archive. Apple requires this for App Store Connect uploads since April 28, 2026 ([SDK requirement](https://developer.apple.com/news/upcoming-requirements/?id=04282026a)). The earlier Xcode 16.4 simulator evidence is a compatibility check, not an upload-ready build. CI explicitly selects Xcode 26.3 for current checks.

Once signed in to the enrolled Apple team in Xcode:

1. Select the actual team in Khajistan → Signing & Capabilities. Confirm `com.khajistan.archive` belongs to that team; change the identifier if necessary before creating the app record.
2. Run the app on the owner's iPhone and complete the device acceptance cases in README.md. Simulator playback is additional evidence and does not replace testing lock-screen audio, calls, AirPlay or device file sharing.
3. Select Any iOS Device, then Product → Archive. Resolve signing or build errors; do not upload a build that failed verification.
4. In Organizer, validate and choose Distribute App → App Store Connect. Use the internal TestFlight distribution option when offered. Keep public App Store submission separate.
5. Wait for App Store Connect processing and resolve any privacy/export-compliance questions based on the actual app and services. No legal or encryption declarations have been pre-answered here.
6. Enable the processed build for the owner as an internal tester. Invitations to additional people require the owner's specified recipients.

## Beta description draft

Khajistan brings its archive, Reading Room, publications and receiver to iPhone and iPad. Browse the live archive, keep links in a personal library, open downloaded files and listen to radio with native playback controls.

## What to test

- Search and move between archive sections; return using native back navigation.
- Save a public page, relaunch and reopen it from Library.
- Sign in with an existing email/password account, access content that account is entitled to, then sign out and confirm restricted content is unavailable.
- Play radio; pause/reconnect, lock the phone, switch audio outputs and test interruption handling.
- Download an authorized file, view it offline, share it and delete it.
- Check large text, VoiceOver, landscape and iPad layout.

## Known integration limits to disclose to testers

- Readers, films, Canvas, commerce and account content are the live website inside WebKit.
- Website magic links currently open the system browser. Use email/password inside the app after confirming the account; session transfer is not implemented.
- Bookmarks are online links. Offline files are explicit downloads; there is no offline subscription page cache.
- Native radio supports HTTPS carriers and checks withdrawal feeds before tuning and on directory refresh.
- There is no native StoreKit purchase flow, APNs push registration, or universal-link association.
- Background download completion/resume after app termination is not implemented.

The beta must remain labelled with these limits. Device functionality and App Store eligibility are separate checks. Apple account authentication/signing is the remaining prerequisite for an actual TestFlight upload.

Official references: [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds), [TestFlight](https://developer.apple.com/testflight/), [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
