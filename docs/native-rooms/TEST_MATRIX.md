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
| TV core (real site data, Bazaar fixture) | 149 passed, 2 skipped (a camera shard absent from the checkout; the full RR grouping fixture) |
| iOS core | 74 passed, 1 skipped |
| iOS package | 8 passed |
| iPhone UI (iPhone 17, `KJ_SITE`) | 19 of 19, one run, after the second review's fixes |
| iPad UI (iPad Pro 11-inch (M5), `KJ_SITE`) | 19 of 19, one run, after the same fixes |
| `KJ_APP_STORE` builds | iPhone and tvOS both build |
| Apple TV Rooms remote test (live register) | passed |
| Apple TV rights-held title (`-kjrrheldfirst`) | passed in all three skins; failed without the flag on the same shelf |
| Mac Catalyst | builds; launched and the Madrassa room captured; not driven by input |
| Builds | iOS simulator, tvOS simulator, Mac Catalyst: all succeed |

The two CI failures on PR 8 at 350a025 were real and are fixed: the app aborted on the runner's
simulator when the Receiver built its tuning hiss (an audio device opened in `init`, crash report
in the run's artifact), and the TV rights-held test could not reach a held title once the comic
reprints left the hold on 2026-10-21 (held titles rank at the end of long rows). The second also failed on
three other branches' runs (`cursor/*`, 2026-10-26).

## Not covered

- Mac Catalyst not driven by a UI test; keyboard and pointer not exercised by hand.
- Full-film playback with an entitled account (no test account held).
- Physical devices: none.
