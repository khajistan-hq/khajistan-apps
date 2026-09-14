# Khajistan for iOS

Native SwiftUI application for https://khajistan-archive.pages.dev, targeting iPhone and iPad on iOS 17+. Open **Khajistan.xcodeproj** in Xcode 16 or newer. No CocoaPods, npm packages, XcodeGen installation, API keys, or new backend services are required.

## What is implemented

| Surface | Implementation |
|---|---|
| Explore | Native house palette, pigeon mark, section directory, archive search entry |
| Archive content | Live Reading Room, Publications, Screening Room, Canvas, Bazaar, Madrassa, Human Desk and Chat in WKWebView |
| Passport | Existing website email/password sign-in, account and download pages; persistent WebKit website storage |
| Radio | Native searchable/filterable receiver catalogue, AVPlayer, background audio configuration, lock-screen commands, AirPlay, interruption/headphone handling, reconnection |
| Library | Device-local bookmarks, bounded recent history, filtering, swipe removal and clear-history confirmation |
| Files | Website-initiated WKDownload transfers, collision-safe file storage, Quick Look, native share/export, deletion |
| Navigation | Browser back/forward, interactive back gesture, reload, pull-to-refresh, loading/error states, page sharing, URL deep links |
| Accessibility | Native labels, Dynamic Type, real buttons and native list/navigation controls; web pages retain their own accessibility |

Readers, films, commerce and account pages remain the live website. This is a hybrid implementation with native navigation/library/audio; it does not reimplement the website's readers as native views. The site's authentication, rights restrictions and entitlements remain authoritative. No database queries, privileged credentials, archive visibility changes, or production deployments were made.

The native radio client reads the same public receiver, denylist, off-air and health feeds as the website. It fetches current controls again before resolving every station and stops a station removed on directory refresh. It does not continuously poll for withdrawal while listening. Native audio requires an HTTPS carrier. A failing/insecure carrier has an error state and the full web receiver remains reachable.

Bookmarks store links, not offline books. Only files the website explicitly delivers as downloads are stored for offline use. Subscription page images are not cached into a new offline reader, and no new offline license is created.

## Source repository and build previews

The canonical source is `ios/` on branch `codex/ios-app-20260914` in the private `khajistan/khajistan-archive` repository. The local feature worktree is `.worktrees/ios-app/ios`; the original `filmart/ios` location points to it, so there is one editable copy. Both website deployment paths exclude the app source.

The **iOS app** GitHub Actions workflow builds and runs simulator tests, then saves screenshots, Xcode logs, test results and an unsigned simulator app in the `khajistan-ios-simulator` artifact. A simulator app is not an iPhone IPA and cannot be uploaded to TestFlight. The workflow has no signing secrets and does not deploy the website.

## Run on a simulator

1. Install full Xcode and its iOS Simulator runtime; open Xcode once to finish installation.
2. Open `Khajistan.xcodeproj`, choose the **Khajistan** scheme and an iPhone simulator.
3. Run with **⌘R**. The simulator does not need a paid signing team.
4. Run the included UI smoke test with **⌘U**. It checks native navigation, the reader webview mount, Library and Passport. It does not prove reader content, checkout, entitlement enforcement or playback.

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

The first command compiles and executes eight Foundation-only behavior tests: exact origins/deep links, Urdu search encoding, sensitive URL exclusion, bookmarks/history, disk persistence/corruption, download paths/Unicode length, radio withdrawals and stream identifier encoding. It deliberately requires no XCTest or Swift Testing runtime, which are absent from this machine's command-line installation.

An optional live network integration check uses the **same RadioService compiled into the app**:

From the `ios/` directory:

```sh
mkdir -p .build
swiftc -swift-version 5 Khajistan/Core/*.swift Khajistan/Radio/RadioService.swift \
  scripts/VerifyLiveReceiver.swift -o .build/verify-live-receiver
.build/verify-live-receiver
```

The live check retrieves all four public feeds, resolves three Pakistani stations, and reads a small range of each signal. It does not authenticate, publish, buy anything, request captions or perform OCR. Station availability changes over time.

The committed Xcode project can be reproduced after adding/removing Swift sources with `python3 scripts/generate-project.py`. Reproduce the typographic app icon with `swift scripts/make-icon.swift Khajistan/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

## Device acceptance still required

This source was created on a Mac with Apple Command Line Tools and **no full Xcode / iOS SDK / Simulator**. Core Swift compilation, behavioral tests, syntax parsing and live network integration have run. The complete iOS target has **not** been SDK type-checked or launched; there is no signed IPA, TestFlight upload or App Store submission.

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
