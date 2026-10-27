# Handoff — native rooms, 2026-10-27

**For the next agent.** Read this file whole, then `DECISIONS.md` (the rules this work keeps),
`CONTRACTS.md` (what each room reads), `STAGES.md` (the ledger) and `TEST_MATRIX.md` (how to
prove it). Do not re-derive what is written here; check it against the code, then continue.
Release, store and compliance work is a separate set: `docs/handoffs/2026-10-13-apps-lane/`.

## Where the work is

| | |
|---|---|
| Repository | `khajistan-hq/khajistan-apps` (public: no private material in commits) |
| Branch | `codex/khajistan-native-rooms`, head `f7e9c0f`, pushed |
| Pull request | draft PR 8 against `main`; Auto-fix is on for it |
| Worktree | `/Users/home/CZURImages/khajistan-apps-native-rooms` |
| Base | `origin/main` 513b617 with PR 1 (the Mac app) merged in |
| Released | **nothing**: no TestFlight, no App Store, no website deploy. Uploads are the owner's alone |

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
   **"actually stop"**. The TV work had not started: one build and two baseline screenshots, no
   code changed. **This is the open task.**

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

## The open task: the Apple TV app

**State.** The TV app already follows the Apple TV app's shelves and focus rules (owner,
2026-10-06, written in `tvos/DESIGN.md`, "Cards and shelves": shelves with a 38pt title and count,
cards that lift to 1.08 with a band-coloured shadow, posters 420pt high uncropped). So the TV gap
is smaller than the phone's was. What is visibly behind:

- The **Rooms** door (`tvos/KhajistanTV/Views/RoomsTV.swift`, 500 lines) is four text cards
  with no artwork; its rooms (Screening, Bazaar, Madrassa, Databases) are compact browse views.
- Two baseline screenshots were taken on 2026-10-27 (Rooms, and a launch with `-kjtab reading`).
  **The `-kjtab reading` launch landed on the tvOS home screen, not in the app.** It was not
  investigated: it may be a crash at launch, a wrong launch-argument value, or the previous launch
  still terminating. Check first, with the simulator log.

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

- **Named Pics/Vids collections can be read, not made.** `phone_media_collections` grants a
  signed-in account SELECT and DELETE only. Posted to the board for Backend (machinery commit
  `04391297`). Do not apply a migration from this lane.
- **Four films cannot go on a watchlist**: Persian-script handles (`nirt-خسرو-میرزای-دوم`,
  `nirt-جنگ-نوروزی-1357`, `nirt-دنیای-خوب-ما`, `nirt-شبکه-صفر`) fail the saves table's
  Latin-only ref check. The button is disabled and says why. Needs Backend to widen the check.
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

Last measured, 2026-10-27 at f7e9c0f: iPhone UI 19/19, iPad UI 19/19, iOS core 74 passed 1
skipped, TV core 149 passed 2 skipped, package 8, TV Rooms 1/1; Mac, iOS and tvOS `KJ_APP_STORE`
builds succeed.

## Working rules on this machine

- Commit only your own files, by explicit path; never `git add -A`, `-u` or `.`. Read
  `git diff --cached --stat` before every commit.
- Never commit `.env` or print a credential file. The Supabase anon key in `Config.swift` is
  public by design; nothing else secret belongs in this repo.
- A command that deletes or kills is held by a hook until you state what it touches, the
  rollback, and the instruction it serves. Prefer fresh output paths to deleting old ones.
- Report to the owner answer first, in short chunks, with the next action and a recommendation.

## Next actions, ranked

1. **Apple TV layouts** (the open task): check the `-kjtab reading` launch first, then rebuild
   the Rooms door and its four rooms in the Apple TV app's shape, then the Receiver guide and Now
   Playing; same tests and refute review as above. Recommended next.
2. When CI runs again on PR 8, read its result; Auto-fix reports failures.
3. Backend: the `phone_media_collections` grants and the saves table's ref check (two board items;
   not this lane's to apply).
4. Owner: review draft PR 8, and decide on a TestFlight upload (owner-only).
5. Front lane: the two stale website menu lines.
