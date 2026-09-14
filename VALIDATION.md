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
