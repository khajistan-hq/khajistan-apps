# Test matrix

## Commands

```sh
KJ_ARCHIVE=<site checkout> sh ios/scripts/test-core.sh
KJ_ARCHIVE=<site checkout> sh tvos/scripts/test-core.sh
node tvos/scripts/bazaar-shelf-fixture.mjs <site checkout> /tmp/bazaar.json   # then KJ_BAZAAR_EXPECTED=/tmp/bazaar.json for the TV core run
swift test --package-path ios
xcodebuild test -project ios/Khajistan.xcodeproj -scheme Khajistan -destination 'platform=iOS Simulator,name=iPhone 17'
TEST_RUNNER_KJ_SITE=http://127.0.0.1:8831 xcodebuild test ... -only-testing:KhajistanUITests/KhajistanUITests/testMadrassaDatabasesAndBazaarReadTheSiteData
xcodebuild test -project tvos/KhajistanTV.xcodeproj -scheme KhajistanTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' -only-testing:KhajistanTVUITests/RoomsUITests
```

`KJ_SITE` is a local server of the site checkout (`python3 scripts/dev_server.py 8831 --directory archive`
in the machinery repo). Most room data is behind the site password until launch; without `KJ_SITE` the
tests check the locked note instead.

## Last measured (2026-10-27)

| Suite | Result |
|---|---|
| TV core (real site data, Bazaar fixture) | 148 passed, 2 skipped (a camera shard absent from the checkout; the full RR grouping fixture) |
| iOS core | 74 passed, 1 skipped |
| iOS package | 8 passed |
| iPhone UI (iPhone 17, live site) | 17 of 17 passed across the last two runs (the locked-room path was fixed and re-run alone) |
| iPhone UI, site-data walk (iPhone 18 Pro, `KJ_SITE`) | passed, again after the review fixes |
| iPad UI (iPad Pro 11-inch) | 17 of 17 (two tests made layout-aware and re-run) |
| `KJ_APP_STORE` iPhone build and its exclusion test | builds; exclusion test passed, Chat test skipped as designed |
| Apple TV Rooms remote test (live register) | passed, again after the review fixes |
| Mac Catalyst | builds; launched and the Madrassa room captured; not driven by input |
| Builds | iOS simulator, tvOS simulator, Mac Catalyst: all succeed |

## Not covered

- Mac Catalyst not driven by a UI test; keyboard and pointer not exercised by hand.
- Full-film playback with an entitled account (no test account held).
- `KJ_APP_STORE` tvOS build not compiled in this branch.
- Physical devices: none.
