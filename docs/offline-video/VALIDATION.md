# Candidate validation — 2026-10-31

This is a draft preparation change, **not a publish-ready offline library**. See
`RELEASE_GATES.md`, `SERVER_CONTRACT.md` and `READING_ROOM.md` for incomplete integration,
provider, entitlement, legal, product and device acceptance gates.

Initial source baseline was `d33027313652d95c04c4ba0cd6cc28a0a6d963b2`. The parent branch then
advanced to `cc429a9` with only a Receiver UI-test timeout/comment change; it is retained when
this candidate is rebased. No parent production source changed. All results below exercise this
candidate's production sources. No paid account, purchased asset, physical device or production
configuration was used or changed.

| Check | Result |
|---|---|
| Swift package | 32 passed, 0 failed |
| Actual iOS and tvOS AuthStore with synthetic URLProtocol/Keychain harness | 12 scenarios passed; logout/late refresh, latest sign-in, single-flight refresh, transient refusal, malformed/identity/redirect answers, explicit invalid session |
| iOS own core | 16 passed |
| iOS shared core with archive fixtures | 74 passed, 1 skipped |
| tvOS core with archive/Bazaar fixtures | 156 passed, 2 skipped |
| Unsigned iOS Store, tvOS Store and Mac Catalyst Release builds | All succeeded |
| iPhone 17 reader | Free title and members-preview gate passed; page-turn/chrome/bookmark persistence passed in Day, Grove and Smut |
| iPad Pro 11-inch reader | Portrait/landscape spread, page grid, return-to-page, issue end/next issue, free title and members-preview gate: 2 tests passed |
| iPhone Receiver regression | Cameras, Transmission and Live appear under the dock on one tap: passed with the original stricter three-second frame wait |
| Visual review | Actual page/chrome screenshots inspected in all three phone skins, and actual tablet portrait/RTL landscape spread |
| Independent source review | Film/auth lifecycle findings fixed and re-reviewed; Reading Room cache/permission diff reviewed separately from its author |
| Whitespace | `git diff --check` passed |

Commands: `swift test --disable-sandbox --package-path ios --scratch-path /tmp/kj-offline-swiftbuild`
with writable module caches; `sh ios/scripts/test-auth-lifecycle.sh`; both documented core scripts
with `KJ_ARCHIVE` and the TV Bazaar fixture; `xcodebuild` for the three platforms with
`CODE_SIGNING_ALLOWED=NO` and `SWIFT_ACTIVE_COMPILATION_CONDITIONS=KJ_APP_STORE`.
Targeted XCTest names are `testReadingRoomReadsAFreeTitleAndStopsAMembersTitleAtThePreview`,
`testReaderTapZonesChromeAndBookmarkAcrossRelaunch`, `testReaderSpreadGridBackAndEndOfIssue`
and `testReceiverPartsComeUpUnderTheDockedSet`.

The core skips are the absent Anatolia camera shard (both platforms) and the optional full
Reading Room grouping feed (TV). They are not passes. Existing HomeShelves closure-style and
AppIntents metadata warnings remain; the new FairPlay delegate concurrency warning was resolved.

Initial reader test attempts exposed assumptions about lazy/offscreen title cards. The helper
now scrolls past Continue and uses title search before opening a card. The final phone and tablet
reader cases pass. One Receiver run was interrupted when an earlier Xcode diagnostic cleanup
shut down its simulator; it was rerun alone and passed. No timeout was increased by this branch.

Local result bundles/logs are under `/tmp/kj-offline-*` and `/tmp/kj-receiver-final.xcresult`.
They are diagnostic evidence, not distributable media. Full current-candidate CI, physical-device
FairPlay, Keychain/backup/storage-pressure behavior, paid/refunded/revoked entitlements,
background download restoration, license renewal/rotation, Catalyst playback/accessibility and
owner TestFlight review remain unrun or blocked as specified in the release gates. A successful
build or policy test does not establish these properties.
