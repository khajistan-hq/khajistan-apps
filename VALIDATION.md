# Validation — 2026-09-14

- Live site read in a browser; main destinations verified against its navigation. No live writes made.
- Apple Swift 6.3.3 on macOS; only Command Line Tools selected. `xcodebuild` and `simctl` report that full Xcode is unavailable.
- Foundation core: `swift build` passed.
- Behavior runner: `scripts/test-core.sh` passed all eight tests.
- App Swift files: `swiftc -frontend -parse` passed. Syntax parsing is **not SDK type checking**.
- Xcode project and both property lists: `plutil -lint` passed.
- App icon: inspected, 1024×1024 PNG with no alpha channel. Existing pigeon asset converted to PNG for the app's native header.
- Live Swift integration: 1,829 radio channels eligible after current receiver controls; AM 1170, City FM89 and Dhanak each resolved and supplied HTTPS stream bytes (HTTP 200). Network bytes are **not proof of audible iOS playback**.
- Negative controls: the same behavior suite correctly failed when the public-query restriction and radio denylist exclusion were separately disabled in temporary copies.
- Scoped secret scan: no credential-pattern matches and no environment files in the app tree.
- Read-only adversarial review found persistence filtering, radio resolution state/withdrawal, HTTP-error lifecycle and Unicode filename issues. Corrected and covered by the final checks where locally executable. Follow-up review confirmed all five repairs and project wiring; an AirPlay audio-category option identified in that pass was also removed to follow Apple’s API contract.
- Complete iOS target build, simulator/UI tests, physical-device audio, account flows, reader/film entitlement behavior, file downloads and store distribution remain unverified because the iOS toolchain and a test device are unavailable.

No production website changes, backend deployments, OCR work, new paid services or App Store submissions were performed.

## Full iOS SDK run — 2026-09-14

GitHub Actions run [34809903319](https://github.com/khajistan/khajistan-archive/actions/runs/34809903319), commit `b21161a979eb9994184e66f8f5740d567a910a9d`, completed successfully using Xcode 16.4 and an iPhone 16 Pro simulator. App compilation, two XCUITests and screenshot export passed. City FM89 reached AVPlayer's playing state and the pause control worked. Six native screenshots and a compiled unsigned simulator application were retrieved and inspected.

This supersedes the earlier **SDK compilation/simulator execution unavailable** limitation for this commit. Local Xcode installation, physical-device testing and Apple signing remain pending. The first browser screenshot was captured during loading; it establishes presentation only and does not prove Reading Room access. A direct anonymous request confirms Reading Room/about currently redirect to the site's password gate. No site password is supplied to GitHub Actions.
