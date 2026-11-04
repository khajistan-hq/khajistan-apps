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

## Last measured (2026-10-28, Mobbin gaps on Apple TV and picture-first tiles)

Local site from the machinery repo (`KJ_SITE`/`KJ_FILMS_ORIGIN` = `http://127.0.0.1:8831`), Apple TV 4K (3rd generation) simulator.

| Suite | Result |
|---|---|
| Apple TV `RoomsLayoutUITests` (Day, Grove, Smut + index search) | 4 of 4 on the final build: Chat tile, film Website QR, Opened lately, bag + stepper + Checkout QR, Madrassa Save, Filter value → pill → removed, Sort A–Z |
| Apple TV `ReceiverGuideUITests` (3 skins) | 3 of 3: Menu on a playing station leaves the radio bar; Off stops it. An earlier run lost one skin at "Right three times lights Guide" (before the new code; it moved between skins run to run) |
| Apple TV `ReadingRoomUITests` | 5 of 5, incl. `testWholeShelfAndSearch` (3 skins) |
| Apple TV `PicsVidsUITests` | 5 of 5, incl. `testViewerSaveControls` (3 skins; signed out) |
| Apple TV `RoomsUITests` | 1 of 1 |
| iOS core / TV core | 74 passed, 1 skipped / 151 passed, 3 skipped |
| Builds | tvOS, tvOS `KJ_APP_STORE`, iOS, iOS `KJ_APP_STORE`, Mac Catalyst: all build |

## Full run on the combined branch (2026-10-28, at 422aded; later commits to d04263b are docs only)

Run on a clean checkout of the pushed head, so no session's uncommitted work was in it.

| Suite | Result |
|---|---|
| iOS core | 74 passed, 1 skipped |
| TV core (real site data, Bazaar fixture) | 152 passed, 2 skipped |
| iOS package | 8 passed |
| Apple TV UI (local site): Rooms, RoomsLayout (3 skins + index search), ReceiverGuide (3 skins), ReadingRoom (incl. rights-held), Films, PicsVids | 18 passed, 1 skipped (no account-open title on the shelf today), 0 failed |
| iPhone UI (iPhone 17, `KJ_SITE`) | 19 of 19 (a first attempt never started: the simulator refused to launch the test runner, "Host is down"; the re-run on the same build passed) |
| iPad UI (iPad Pro 11-inch (M5), `KJ_SITE`) | 20 of 20 |
| Builds | Mac Catalyst, iPhone `KJ_APP_STORE` and tvOS `KJ_APP_STORE` all build |

## Last measured (2026-10-28, TV index search)

| Suite | Result |
|---|---|
| Apple TV `RoomsLayoutUITests/testIndexSearchFindsASongByTitleAndArtist` (local site) | 3 skins pass: "dayem pada ghulam" narrows 19,363 records to Ghulam Ali's Dayem Pada Huwa |
| Apple TV Rooms remote test, `RoomsLayoutUITests/testDay` | passed (focus now opens on the search bar) |
| TV core | 150 passed, 2 skipped |
| tvOS `KJ_APP_STORE` build | builds |

## Last measured (2026-10-27, sign in on the TV from a phone)

Run in a clean worktree holding the branch head plus only this change (another session's work was
uncommitted in the shared folder).

| Suite | Result |
|---|---|
| TV core | 150 passed, 3 skipped (new: "TV sign-in from a phone"; the third skip is the Bazaar fixture, not passed in this run) |
| iOS core | 74 passed, 1 skipped (TVSignIn is a shared link) |
| Apple TV `PhoneSignInUITests` | 3 of 3 (Day, Grove, Smut): opens on the QR and code, focus on the way to email and password, there and back |
| iPhone `testSignInOnATVFromThePhone` | passed: a bad code refused in place, a loosely typed one read, what asked said before approving, done |
| QR read back | Apple's own QR reader decodes the address from the Day, Grove and Smut screenshots |
| Builds | tvOS, tvOS `KJ_APP_STORE`, iOS, iOS `KJ_APP_STORE`, Mac Catalyst (no scanner there): all build |
| `tv-sign-in` (Deno) | 4 passed; `deno check` clean |
| Archive `/activate` | `tv_sign_in_page_test` 5 passed; Receiver and gate tests 152 passed |

Not covered: anything against the live project (nothing is deployed, no test account); the SQL was
not run (no local Postgres); a real phone scanning a real TV.

## Last measured (2026-10-28, the shelf kept on the device; DECISIONS 23)

| Check | Result |
|---|---|
| Owner's Apple TV HD, Release, `-kjclock` | first open after install: shelf 2.88 s, first cover 3.19 s; next opens: 1.36 s / 1.65 s and 1.44 s / 1.73 s (shelf / first cover) |
| Owner's Apple TV HD, Pics/Vids | opens with region shelves and pictures (screenshot via `devicectl device capture screenshot`) |
| Owner's check at home (2026-10-28, relayed) | "reading room opens", "born digital works", and on the QR phone sign-in and the 2-second target: "both are good" |
| TV core / iOS core | 152 passed 2 skipped / 74 passed 1 skipped |
| Apple TV `ReadingRoomUITests` + Rooms | 5 passed, 1 skipped (no account-open title today), on the code after the refute fixes |

## Last measured (2026-10-27, the database route; DECISIONS 22)

| Check | Result |
|---|---|
| TV core | 152 passed, 2 skipped (new: the route's rewrites, a proxied tv-play is still tv-play) |
| iOS core | 74 passed, 1 skipped |
| Site worker | `archive/tests/worker_sb_proxy_test.mjs` ok; launch-mode and path-security tests still pass; a live call through the worker code returned the rights list |
| Apple TV simulator, direct blocked (`-kjsbdirect https://10.255.255.1`) + local stand-in proxy (`-kjsbproxy`) | Reading Room shelf ready 1.24 s, first cover 2.35 s; Pics/Vids opens; both ways dead: the message at 2.6 s |
| Apple TV simulator, normal route | ReadingRoom free title, PicsVids 3 of 4, Rooms, Transmission subtitle: pass. `testVideoAndKhajistanTVRow` fails at the sign-in sheet since 2033e0a (the TV sign-in now opens on the phone); passed before it; reported to that session |
| iPhone UI | 20 of 20 |
| Owner's Apple TV HD, Release | before: catalogue 45.7 s then "did not answer"; now: "can't reach its archive" at 2.8 s (proxy not deployed yet) |

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
