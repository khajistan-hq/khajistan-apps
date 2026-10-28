# Handoff — native rooms, 2026-10-27

**For the next agent.** Read this file whole, then `DECISIONS.md` (the rules this work keeps),
`CONTRACTS.md` (what each room reads), `STAGES.md` (the ledger) and `TEST_MATRIX.md` (how to
prove it). Do not re-derive what is written here; check it against the code, then continue.
Release, store and compliance work is a separate set: `docs/handoffs/2026-10-13-apps-lane/`.

## Where the work is

| | |
|---|---|
| Repository | `khajistan-hq/khajistan-apps` (public: no private material in commits) |
| Branch | `codex/khajistan-native-rooms`, pushed; the Apple TV layouts are the commit after `4f2d627` |
| Pull request | draft PR 8 against `main`; Auto-fix is on for it |
| Worktree | `/Users/home/CZURImages/khajistan-apps-native-rooms` |
| Base | `origin/main` 513b617 with PR 1 (the Mac app) merged in |
| Released | **TestFlight build 1.0 (3)** for iOS, Mac and tvOS from `6151b85` (the app the owner approved on the Apple TV, with the Reading Room speed-up `a7a1983`; build 2 from `bc8cc38` before it), internal testing only (owner: "i am ready do whatever you need to get t uplaoding testfllight and deployinge veyrthing", 2026-10-28); no App Store submission. Website: `/activate` and `/sb/` live. Receipts: `filmart/reports/app-distribution-20261028/` |

The website and the machinery live in the separate private repo `/Users/home/CZURImages/filmart`
(the site checkout is `filmart/archive`). Native-app work never edits the site.

## What the owner asked for, in order (2026-10-27)

1. A long staged brief: build the iPhone/iPad, Mac (Catalyst) and Apple TV apps into native
   rooms (Screening Room, Bazaar, Pics/Vids, Madrassa, the eight databases, Reading Room, live TV),
   keep the live radio, Transmission and the Receiver map, never publish.
2. "Build the missing Mobbin pieces": film watchlist, Pics/Vids saved collections, Madrassa
   contents and article save, database sort, Mac thumbnail rail in the reader, a compact radio
   player while browsing. Done (44444f7, review fixes 65c729b).
3. "Copy the workflow and UX/UI of the apps we landed on": every room laid out like its reference
   app. Done for iPhone, iPad and Mac (f7e9c0f). Approved by the owner: "Looks right."
4. "Make sure CC shows in the receiver": done (a plain CC key, f7e9c0f).
5. "Carry the same reference-app layouts to the Apple TV app next, same tests and review", then
   **"actually stop"**. Resumed on the owner's word the same day and **done** (the commit after
   4f2d627): the Rooms door, its four rooms, the Receiver guide and radio Now Playing. Not yet
   seen by the owner.

## The reference apps (DECISIONS 17)

The research shortlist is the owner's own (a Mobbin pass; the guide is owner-local, not in this
repo). A Mobbin subscription is not bought and is not needed: the patterns below are the brief.

| Room | Copy this app | Built as (phone/iPad/Mac) |
|---|---|---|
| Home | Apple Books Home + Apple TV Up Next | Continue (covers + progress), Up Next (posters), room tiles incl. Chat, Opened lately |
| Reading Room | Apple Books shelf; Google Arts & Culture zoom | large title, search field, Continue carousel, language chips, shelves "Name ›" opening a grid (`RoomRoute.readingShelf`), book page with one Read/Continue |
| Screening Room | Apple TV app | Up Next, Your watchlist, a poster row per country; film page: poster, one Play/Resume, Watchlist · Preview · Website icons, Information |
| Bazaar | Etsy item page; On filters and checkout | listing grid on soft plates, bag icon with count, price first, option chips, one Add to bag, bag summary with steppers and one Checkout |
| Pics/Vids | Cosmos (Pinterest for scanning) | chips, rounded masonry tiles with a video badge, bookmark → Saved (masonry, collection chips) |
| Madrassa | Wikipedia entries; The Atlantic essays | entry rows with a thumbnail, serif titles and body, Save beside the date |
| Databases | Notion table filter/sort | Filter and Sort menus, filter pills that remove themselves, hairline rows, property page (label column + value) |
| Receiver list | YouTube TV live guide; DAZN live entry | guide rows: medium mark on a plate, name, place, LIVE on the playing one |
| Small player | Sonos | floating band-coloured bar: mark, name and state, play/pause, off |
| App chrome | iOS conventions | icon tab bar, "‹ Back", large titles as written, rounded search fields, Rooms as a grouped list with icons |

Shared building blocks: `ios/Khajistan/Views/Shelves.swift` (`LargeTitle`, `SearchField`,
`ChipRow`/`ChipStyle`, `ShelfHeader`, `RoomLink`, `ProgressLine`, `SolidActionStyle`, `IconAction`,
`InfoRow`).

**What stays the house's whatever the reference does.** Check every change against these:

- Three skins (Day yellow, Grove green, Smut pink) from `Palette` tokens only. Never white, never
  a hardcoded colour. Text on the ground is `ink`; on a band `onBand`.
- Artwork is fitted whole, never cropped (`.fit`, never `.fill`), at its own shape.
- No outlined boxes. Filled plates, chips and form fields are allowed under the owner's
  copy-the-apps instruction; strokes around cards are not. Horizontal hairlines between list rows
  are allowed (owner ruling 2026-09-10).
- Home shows only this device's history and the rooms, never a pick or a ranking.
- **Every Supabase download is billed.** Home must not start the Reading Room catalogue load
  (~3 MB); it shows covers only if the shelf is already loaded, text otherwise.
- `KJ_APP_STORE` builds leave out Pics/Vids, Chat and the Wall; every new route goes through
  `AppModel.open(_:at:)`, which checks `StoreBuild.includes`.
- Inside a room, push with `NavigationLink(value:)`; from Home or Library (not on the room's stack)
  use `RoomLink(route:in:)`, which opens the room at that place. A bare `NavigationLink` on Home is
  disabled and draws dimmed.

## The Apple TV layouts (done 2026-10-27)

**What was built** (written up in `tvos/DESIGN.md`, "Rooms" and "The Receiver"):

- **Rooms door**: four tiles (mark, count only if the list is already loaded, name, line) and Up
  Next from this device. It starts no download of its own.
- **Screening Room**: Up Next (`kj.filmPlaces`, seconds by handle, kept by `FilmPlayerView` when a
  full film stops part-way, forgotten at its end), Your watchlist, a poster shelf per country. A
  poster opens `TVFilmPage`: poster, one solid Play or *Resume from 20:00*, Preview, Watchlist,
  Information. Play opens the player asking for the full film at once (`startsFull`). The
  Receiver's own film shelves still open a film on its preview.
- **Bazaar**: price first under each object on its soft plate; the object's page has the shop's
  live price, option chips that change it, the description, and the khajistan.com address.
- **Madrassa**: serif titles and text, entry pictures, writing cards with their lead picture; a
  piece ends *Continue on your phone, or on the website*.
- **Databases**: a grid of systems; a table with hairlines and two property columns; a record as a
  property page.
- **Receiver**: channel cards lead with the medium's mark; the player's strip gains **Guide**
  after CC and Like (armed with Right, never focused, like them): every channel of the shelf,
  numbered, LIVE on the playing one; Select tunes behind the pigeon; Left or Menu closes.
  Radio shows Now Playing (mark, NOW PLAYING · LIVE RADIO, name, place and broadcaster).
- **Shared fix**: the focus shadow now falls under the card as one shape (`compositingGroup`);
  before, each piece on a plate cast its own, a halo under lettering and marks in Smut.
- **`-kjtab reading`** opens the Reading Room; the home-screen landing of the baseline did not
  recur (most likely the previous launch still terminating).

**Then, same day ("resolve the gaps")**: the TV Reading Room's title page (cover large, one
Read/Continue) and Continue shelf. Pics/Vids source identity was already there (`@account` on every
card). Direct channel entry by number is not built: the Siri Remote has no digits; the guide
numbers its rows instead.

**What to build** (the research guide's TV column, adapted):

| Room | TV shape |
|---|---|
| Screening Room | the Apple TV app on TV: large poster shelves, Up Next with progress, a film page with one Play/Resume, clear focus |
| Reading Room | shelves of covers as now; a title page with the cover large and one Read/Continue; a Continue shelf from this device's places |
| Live TV / Receiver | direct channel entry and quick switching; a live-guide row style; LIVE on the playing channel |
| Radio | station list and a clear Now Playing |
| Bazaar | an object showcase; buying stays an address on khajistan.com (no checkout on TV) |
| Pics/Vids | region shelves as now; source identity on every card |
| Madrassa | short descriptions; continue reading on the phone |
| Databases | record previews; detailed research stays on phone/Mac |

**TV rules that differ from the phone** (from `tvos/DESIGN.md`; read it whole first): focus is
the website's hover (band plate, onBand text, 1.03); the one sanctioned shadow is under a focused
card; no system card styles (tvOS draws them as white platters); type sizes are the TV table
(display 120, headline 72, name 34, body 29, kicker 24); every shelf is a focus section.

**Constraint found the hard way:** shared Core/Services files are symlinked into the iOS app, so
a TV change there compiles in both apps and must pass both core suites. The sign-in door is named
per app through `KJConfig.signInDoor` ("Account" on TV, "Library" on the phone).

## Known gaps and blockers

- **The owner's home network blocks the database host** (2026-10-27; DECISIONS 22). The apps fall
  back to the site's `/sb/` proxy, live since archive b96a2b2f3 (a88eee3f7 cherry-picked onto the
  live main and deployed by the sign-in session). The website's own pages still call the host
  directly and are stuck on that network; `/activate` falls back to `/sb/` (d98cb687c). Realtime
  (live captions, chat presence) is not proxied, and behind `/sb/` the database sees Cloudflare's
  addresses, not the viewer's (per-IP rate limits, sign-in's same-network flag) — fine for one
  household, needs a signed client-address header before scale.
- **The Reading Room opens from the shelf kept on the device** (DECISIONS 23): on the owner's TV
  1.36–1.44 s to the shelf; the first open after an install still reads the network (2.9 s).
- **Closed 2026-10-27, no migration — Pics/Vids collections**: the table's per-column grants
  (INSERT user_id, name, media_keys; UPDATE name, media_keys) already let an account create and fill
  one; the Backend board note (machinery `04391297`, `COORDINATION.md`) read only table-level grants
  and is wrong. **It still needs correcting on the board** (the file had other sessions' uncommitted
  edits, so it was not touched from here). The iPhone viewer has a Collection menu (DECISIONS 20).
- **Closed 2026-10-27, no migration — the four Persian-handle films** save as `tv:u.<hex>`
  (DECISIONS 19). Not checked against the live table with a real account (none held); the request
  shape is core-tested.
- **Pashto channels cannot be captioned**: the live recogniser does not take Pashto; the
  Receiver says so under the channel.
- **CI on PR 8**: the runs for f7e9c0f were still `pending` at 0 elapsed when this was written,
  which matches the GitHub Actions macOS quota being used up. The two earlier CI failures (an
  audio device opened in `StaticNoise.init`; the TV rights-held test unable to reach a held title)
  are fixed and green locally.
- **Not verified:** Mac keyboard and pointer (control of the window was declined); the Databases
  Sort/Filter menus on Mac Catalyst (they become menu items there); full-film playback for an
  entitled account (no test account); physical devices; scrubbing the Receiver map in a UI test
  (the first hiss opens the audio device, and a simulator without audio can abort).
- Most room data is behind the site password until launch. The UI tests read it from a local
  copy of the site through `-kjsite` / `TEST_RUNNER_KJ_SITE` (see TEST_MATRIX).
- The website menu still reads "The 32 films — on demand" and "…and the Khajistan Radio mixes"
  (site copy, Front lane); the Rooms list repeats the menu word for word.

## How to run and check

1. Start a local site server from the machinery repo: its launch config `archive` (port 8819), or
   `python3 scripts/dev_server.py 8819 --directory archive`. Stop it afterwards **by PID**, never
   with `pkill`.
2. Build and run with the commands in `TEST_MATRIX.md` (its examples say port 8831; any port
   works if `TEST_RUNNER_KJ_SITE` matches). The full set this work was held to, every time: both
   core suites (`KJ_ARCHIVE=<site checkout>`, the Bazaar fixture for TV), `swift test`, the
   iPhone and iPad UI suites with `TEST_RUNNER_KJ_SITE`, the TV Rooms remote test and the
   rights-held test, and builds for Mac Catalyst plus `KJ_APP_STORE` for iPhone and tvOS.
3. Look at every changed screen in all three skins in the simulator before calling it done.
4. **Review**: a second model asked to refute the whole uncommitted diff (Fable, read-only, no
   simulators), each finding checked against the code before it is fixed or dismissed. Write what
   was dismissed and why in the commit message.

Last measured, 2026-10-27, the Apple TV layouts: see TEST_MATRIX's first table (TV walks 3/3
in each new suite, TV regression 9/9, core suites unchanged, iPhone and iPad UI, builds).

## Working rules on this machine

- Commit only your own files, by explicit path; never `git add -A`, `-u` or `.`. Read
  `git diff --cached --stat` before every commit.
- Never commit `.env` or print a credential file. The Supabase anon key in `Config.swift` is
  public by design; nothing else secret belongs in this repo.
- A command that deletes or kills is held by a hook until you state what it touches, the
  rollback, and the instruction it serves. Prefer fresh output paths to deleting old ones.
- Report to the owner answer first, in short chunks, with the next action and a recommendation.

## Sign in on the TV from a phone (2026-10-27, DECISIONS 21) — live

Deployed on the owner's "deploy them safely", each step verified:

| Piece | Live as | Checked |
|---|---|---|
| Table `tv_sign_in_requests` | migrations `20261028031501_tv_sign_in_requests` and `20261028031723_tv_sign_in_requests_service_role_grant` (the project writes no default grants since 2026-10-20; the first live call failed without the second) | RLS on, no policies, no anon/authenticated grant; the checks refuse a bad code, a duplicate live code, approval without an account and a hash on a pending row (rolled-back test) |
| Function `tv-sign-in` | v1, `verify_jwt = false` | start → code + secret; poll pending, slow_down when too fast, expired for an unknown secret; anon peek/approve 401; a caller's label ignored |
| Page `/activate` | archive `main` `dbeb659ec`, deployed by CI (Deploy to Cloudflare Pages, run 40626477415) | 200 signed out, `/activate.html` forwards; `/tv` still the Receiver redirect; dashboard, Reading Room, vod.json still 401; site suite 782 OK; smoke 52/0 against the deployed commit |

Recorded in the machinery repo on `trunk` (`7f91cd89`: migrations as applied, the function as deployed).
**Side door, 2026-10-28** (owner: "use the side door, my apple tv is not showing qr code"): the site's
`/sb/` proxy is live (archive `main` `b96a2b2f3`, the speed session's `a88eee3f7`), and `/activate` asks the
project host for 2.5 s then uses `/sb/` (`d98cb687c`). The owner's Apple TV was reinstalled from the shared
folder as it stood (with the speed session's then-uncommitted routing). Limit: behind `/sb/` every client
reaches the project from Cloudflare's worker IPs, so per-IP rate limits and `same_network` see the worker,
not the person; fine for one household, needs a signed client-IP header before launch.
**Not yet done end to end:** approving a code needs a signed-in account; the owner's first real sign-in
is the last check. The Apple TV installed earlier carries an older build without this screen.

## Next actions, ranked

1. **Owner: try TestFlight build 1.0 (3)** on the iPhone, the Mac and the Apple TV (from `6151b85`;
   the app code is the same as the head's and as what is installed on the owner's Apple TV). Done on
   the TV at home already: Reading Room, Pics/Vids and the QR sign-in work (2026-10-28).
2. **Owner: look at the Apple TV rooms** and say whether they look right, as was done for the phone.
3. When CI runs again on PR 8, read its result; Auto-fix reports failures.
4. Owner: review draft PR 8 and decide when it merges to `main` (owner-only).
5. Front lane: the two stale website menu lines.
