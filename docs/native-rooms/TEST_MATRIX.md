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
TEST_RUNNER_KJ_SITE=http://127.0.0.1:8831 xcodebuild test -project tvos/KhajistanTV.xcodeproj -scheme KhajistanTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' -only-testing:KhajistanTVUITests/RoomsLayoutUITests -only-testing:KhajistanTVUITests/ReceiverGuideUITests
```

`RoomsLayoutUITests` walks the TV Rooms door and its four rooms in each skin (it seeds a film place
with `-kj.filmPlaces`, so Up Next and Resume show without an entitled account) and keeps a
screenshot of every screen; `ReceiverGuideUITests` opens a live Indus channel, the guide, tunes from
it, closes it with Left, and opens a radio station's Now Playing, in each skin. DEBUG builds of the
TV app also take `-kjroom <screening|bazaar|madrassa|databases>`.

`KJ_SITE` is a local server of the site checkout (`python3 scripts/dev_server.py 8831 --directory archive`
in the machinery repo). Most room data is behind the site password until launch; without `KJ_SITE` the
tests check the locked note instead.

## Last measured (2026-10-28, the gaps closed)

TV Reading Room title page and Continue; Persian-handle film saves; Pics/Vids collections.

| Suite | Result |
|---|---|
| TV core | 150 passed, 2 skipped (new: films in any script, collection requests) |
| iOS core | 74 passed, 1 skipped |
| Apple TV `ReadingRoomUITests` + Rooms | 4 passed, 1 skipped (no account-open title on the shelf today); Rooms 1 of 1. The free-title walk reads to p. 2, sees Continue · p. 2, walks up to the Continue card and reopens at p. 2, in all three skins |
| iPhone UI | 19 of 19 |
| iPad UI | 19 of 19 |
| iOS package | 8 passed |
| Builds | Mac Catalyst, iPhone `KJ_APP_STORE` and tvOS `KJ_APP_STORE` all build |

Not covered: creating or filling a collection, and saving a Persian-handle film, against the live
table with a real account (none is held); the request shapes are core-tested and the grants were
read from the live database.

## Last measured (2026-10-27, Apple TV reference-app layouts)

Measured on the TV layouts diff before it was committed; the rows below this table are the
earlier phone run.

| Suite | Result |
|---|---|
| TV core (real site data, Bazaar fixture) | 149 passed, 2 skipped (unchanged; no Core file changed) |
| iOS core | 74 passed, 1 skipped |
| iOS package | 8 passed |
| Apple TV `RoomsLayoutUITests` (local site) | 3 of 3 (Day, Grove, Smut) after the refute fixes |
| Apple TV `ReceiverGuideUITests` (live channels) | 3 of 3 after the refute fixes |
| Apple TV Rooms remote test | passed |
| Apple TV regression set | 9 of 9: rights-held title, both film tests, two caption tests, region shelves, radio dancer, a press mid-flight, Rooms |
| iPhone UI (iPhone 17, `KJ_SITE`) | 19 of 19 on a run alone; a first run beside the TV suite lost `testMapTapChoosesARegion` to a 10 s timeout and it passed on its own |
| iPad UI (iPad Pro 11-inch (M5), `KJ_SITE`) | 19 of 19 |
| Builds | Mac Catalyst, iPhone `KJ_APP_STORE` and tvOS `KJ_APP_STORE` all build |

## Earlier (2026-10-27, phone reference-app layouts)

| Suite | Result |
|---|---|
| TV core (real site data, Bazaar fixture) | 149 passed, 2 skipped (a camera shard absent from the checkout; the full RR grouping fixture) |
| iOS core | 74 passed, 1 skipped |
| iOS package | 8 passed |
| iPhone UI (iPhone 17, `KJ_SITE`) | 19 of 19 after the reference-app layouts and their review fixes (one test now scrolls to the database it opens) |
| iPad UI (iPad Pro 11-inch (M5), `KJ_SITE`) | 19 of 19, same build |
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
- The Databases Sort and Filter are menus; on Mac Catalyst their items are menu items, so the
  iPhone database test would need its own Catalyst path if one is written.
- Scrubbing the Receiver map between stations (the press-and-drag that plays the hiss) is not in a
  UI test. On a simulator with no audio device, the first hiss opens the device and can abort the
  app (the CI failure of 2026-10-27). A test that adds it needs the runner to have audio, or a flag
  that keeps the hiss silent.
