# Khajistan for iOS

Native SwiftUI application for https://khajistan-archive.pages.dev, targeting iPhone and iPad on iOS 17+. Open **Khajistan.xcodeproj** in Xcode 26 or newer (required for current TestFlight uploads). No CocoaPods, npm packages, XcodeGen installation, API keys, or new backend services are required.

## What is implemented

Redesigned 2026-10-05 after the owner opened the app: *"its UX/UI needs work make it work smoothly and have all that's on website on the app the bottom 'radio' 'explore' are in generic design everything needs to be in khajistan house style"*. The house style is the Apple TV app's (`tvos/DESIGN.md` on `app/tvos-pigeon`), measured from the website, set for a phone in `Khajistan/Views/Theme.swift`.

| Door | Native or web | What it carries |
|---|---|---|
| HOME | native menu, web rooms | the website's own menu door by door (kj-chrome.js SITEMAP/DOORS), the site's search, and Reading Room All Access (the site's checkout, `?join=monthly` / `annual`, no price in the app) |
| RECEIVER | native | LIVE: the region map from `region-shapes.json` (tap a region, or its name in the strip), the "Beyond the atlas" switch, the region's television, radio and cameras with a filter; TRANSMISSION: Khajistan TV's two channels on the station clock, now and up next, sign-in and the preview password; KHAJISTAN RADIO: the 22 mixes of `data/radio/mixtapes.json` |
| PICS/VIDS | native | the Born Digital stream as `/browse-archive.html` reads it, the site's adult notice, kind and region filters, a two-column stream at each object's own shape, a full-screen viewer |
| ACCOUNT | native, web links | the skin control, All Access, the account Transmission plays under, saved pages, recent pages and downloaded files on this device, links to Your Khajistan and Your downloads on the website |

Every other room (Reading Room, Publications, Screening Room, Bazaar, Chat, Wall, About, Map...) is the live website in the house browser: a bar with back, the page's name under its door, share, save and close; the load as an accent rule; the page's alerts as house panels. The web view is created at launch and kept, so it opens warm, and a new page shows the ground until it commits rather than flashing the previous one.

Players (receiver channel, Transmission, mix, Pics/Vids video) are full screen with the status band and a panel that hides 2.6 s into playback. A swipe up or down changes channel behind the website's wing-wipe pigeon (`Resources/Media/wipe-in.mov`, `wipe-out.mov`, from the TV app): the old sound fades out, the wing covers the screen, the new channel tunes behind it, the new sound fades in. Reduce Motion keeps the fades and leaves the bird out. Radio keeps playing with the screen locked; the lock screen's play and pause reach whichever player started last.

**Skins** follow the website exactly (`Core/Sky.swift`, a port of KJSky in `kj-theme-boot.js`): Day with the sun above +6°, Smut between ±6°, Grove below, read from the device's time zone and tzdata's coordinate for it, hour bands where the zone is not in the table. Automatic, Day, Grove or Smut is chosen on the ACCOUNT page and stored under the site's own keys (`kj:theme`, `kj:theme:band`); a pick holds until the sky moves to another band. The same keys are written into every in-app web page before the site's scripts run, so the website opens in the app's skin. `-kjskin grove` on the command line forces a skin for screenshots and is never stored.

No system tab bar, navigation bar, alert or grey panel is drawn by the app. What iOS still draws itself: the status bar (black glyphs on Day, white on Grove and Smut, as iOS offers only those two; white there is the owner's ruling of 2026-10-05, recorded in `.claude/rules/frontend.md` §2), the keyboard, the share sheet and Quick Look.

## Source repository and build previews

The canonical source is `ios/` on branch `codex/ios-app-20260914` in the private `khajistan/khajistan-archive` repository. The local feature worktree is `.worktrees/ios-app/ios`; the original `filmart/ios` location points to it, so there is one editable copy. Both website deployment paths exclude the app source.

The **iOS app** GitHub Actions workflow builds and runs simulator tests, then saves screenshots, Xcode logs, test results and an unsigned simulator app in the `khajistan-ios-simulator` artifact. A simulator app is not an iPhone IPA and cannot be uploaded to TestFlight. The workflow has no signing secrets and does not deploy the website.

## Run on a simulator

1. Install full Xcode and its iOS Simulator runtime; open Xcode once to finish installation.
2. Open `Khajistan.xcodeproj`, choose the **Khajistan** scheme and an iPhone simulator.
3. Run with **⌘R**. The simulator does not need a paid signing team.
4. Run the UI tests with **⌘U**. They walk every door in each of the three skins (`-kjskin`), tap the map, play a channel and swipe to the next, play a mix, open and swipe the Pics/Vids viewer, pick and clear a skin, and keep a saved page across a relaunch, attaching a screenshot of each screen. They do not prove paid-reader access, checkout or physical-device audio behavior.

For a physical device, select your Apple development team under **Signing & Capabilities**, use an available bundle identifier, connect the phone and choose it as the run destination. No signing identity is stored in this project.

Command-line build after full Xcode is selected:

```sh
xcodebuild -project Khajistan.xcodeproj -scheme Khajistan \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

The app uses `com.khajistan.archive` as its default bundle identifier. Change it if the owner's team already uses another identifier.

## Verify without Xcode

```sh
./scripts/test-core.sh
swift build
```

The script builds two Foundation-only executables. `verify-core` runs the iPhone's own tests: origins and deep links, search encoding, private pages kept out of history, bookmarks and their file, download names, the skin against the website's own KJSky on 6,992 zone-and-instant cases (`Tests/Fixtures/sky-fixture.json`, regenerated with `node scripts/sky-fixture.mjs`) plus a check that the comparison can fail, the pick-lapses-with-the-band rule with its negative cases, the script written into web pages, and the join and native-room URLs. `ported-core` runs the Apple TV app's 72 core tests over the same ported files (station clock and Pics/Vids URLs against the site's JS, receiver eligibility, the map, auth, transmission routes, mixes); its "Real ..." tests read the archive's data files from `KJ_ARCHIVE` (default: the filmart `archive/` checkout) and skip when it is absent.

The committed Xcode project can be reproduced after adding/removing Swift sources with `python3 scripts/generate-project.py`. Reproduce the typographic app icon with `swift scripts/make-icon.swift Khajistan/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

## Device acceptance still required

This source was created on a Mac with Apple Command Line Tools and **no full Xcode / iOS SDK / Simulator**. Core Swift compilation, behavioral tests, syntax parsing and live network integration have run. The complete iOS target has now compiled and run through GitHub’s Xcode 16.4/iPhone 16 Pro simulator (see VALIDATION.md). Local Xcode setup and physical-device testing remain pending. There is no signed IPA, TestFlight upload or App Store submission.

Before distribution, run these on an actual iPhone and iPad:

- Browse a public archive item, use search, open/zoom a Reading Room page, and confirm a restricted page stays restricted.
- Sign in using email/password, relaunch, confirm the session persists, then sign out. Website magic links currently return to HTTPS in the system browser; they do not automatically transfer that browser's session into WKWebView. Use password sign-in in the app after email confirmation/reset.
- Play radio, lock the phone, switch audio outputs, interrupt with a call, remove headphones, pause/reconnect and switch stations rapidly. Verify audible playback rather than only network reachability.
- Open a film using an entitled account. Verify actual playback, fullscreen, Picture in Picture and entitlement failure using that account's existing permissions.
- Download an authorized file, view it offline, export via the native share sheet, and delete it. Cross-origin links that the website does not mark as downloads may open Safari and use Safari's download handling instead.
- Check contributions/file selection and Canvas editing/sharing. Confirm failed requests show actionable errors, including loss of connectivity.
- Test VoiceOver, largest text sizes, rotation and compact iPhone widths.

## Distribution and remaining integration boundaries

Existing checkout links open the system browser. This preserves the website's billing integration but does **not** establish App Store reader-app eligibility or worldwide payment compliance. Review the actual embedded pages and links against Apple's current [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) before submitting. The earlier project cost plan remains at `../docs/app/NATIVE_APP_COST_PLAN.md`; this iOS-specific implementation uses SwiftUI and incurs no additional platform service fees from dependencies.

No native StoreKit subscriptions, APNs push delivery, universal-link association, automatic magic-link return, or licensed offline subscription reader are implemented. Those require distinct backend/signing/entitlement work; none is represented by a nonworking control. The custom link format `khajistan://open?url=<percent-encoded HTTPS archive URL>` works through `onOpenURL`; only the two exact archive hosts are accepted. Ordinary archive HTTPS links require an owner-hosted AASA association and signed Associated Domains capability before iOS will route them directly to the app.

The privacy manifest describes native-code API use. App Store privacy answers must also account for the live first-party website, sign-in, contributions, payment destinations and broadcaster requests. The app does not install analytics SDKs. It declares camera/microphone/photo usage strings for user-initiated web contributions; it does not request those permissions on launch.

`library.json` lives under Application Support. Completed downloads live under Documents/Downloads, have iOS file protection and are excluded from device backup. Partial files remain in a private temporary folder until completion. Transfers do not implement background completion or resume after termination; retry from the originating page if interrupted. The local bookmark/history directory is also excluded from OS backups. Unknown query parameters and credential-like URLs are excluded from bookmarks/history. The app shares the site's persistent WebKit data store and never copies service keys from the workspace.
