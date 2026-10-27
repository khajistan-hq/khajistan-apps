# Handoff — native rooms, 2026-10-27

Branch `codex/khajistan-native-rooms`, worktree `/Users/home/CZURImages/khajistan-apps-native-rooms`.
Base: `origin/main` 513b617 with PR 1 (the Mac app) merged in. Pushed as draft PR 8 against `main`.
**Nothing uploaded or published**: no TestFlight, no App Store, no site deploy.

## What works

- **iPhone/iPad/Mac**: Home, Rooms, Receiver, Library, Search. Native Reading Room (shelf, title,
  scan reader with zoom and the site's reading direction), Screening Room (catalogue, film page,
  system player), Bazaar (shelves, live variants, bag, the shop's own checkout), Madrassa (entries,
  essays read whole, Street Dictionary), the eight databases (search, facets, record detail).
  Search answers by room; Library lists places kept on this device and titles saved to the account.
- **Added after the Mobbin review (2026-10-27)**: a film watchlist on the account; Save in the
  Pics/Vids viewer and a Saved screen that also lists the account's named collections; Contents and
  Save on long Madrassa pieces; sort in the databases (as listed, A–Z, newest, oldest); a page
  thumbnail rail in the reader on iPad and Mac; a small now-playing bar under every other door while
  the Receiver plays.
- **Apple TV**: a Rooms door with the Screening Room, Bazaar (browse; buying named as an address on
  khajistan.com), Madrassa (read whole, a block at a time) and the databases.
- Receiver, Transmission, live radio and Pics/Vids are unchanged, and Pics/Vids, Chat and the Wall
  stay out of `KJ_APP_STORE` builds (re-tested).

## What is not done or not verified

- Room data is behind the site password until launch. Without it, each room says so; with it set in
  Library, the rooms read the live files. Verified against a local copy of the site, not live.
- Full-film playback for an entitled account: no test account held, so not exercised.
- Cross-device reading/playback progress: places are on this device only; there is no backend
  contract for synced progress. Account saves (Reading Room titles) are the existing shared ones.
- Mac: built, launched and looked at; not driven by keyboard and pointer in a test (control of the
  window was declined, correctly).
- Physical devices: none.
- **Named Pics/Vids collections can be read, not made.** `phone_media_collections` grants a signed-in
  account SELECT and DELETE only; there is no INSERT or UPDATE grant, so a "new collection" control
  would fail. Posted to the board for Backend (machinery `04391297`). The app shows existing ones.
- **Four films cannot go on a watchlist**: their handles are Persian script
  (`nirt-خسرو-میرزای-دوم`, `nirt-جنگ-نوروزی-1357`, `nirt-دنیای-خوب-ما`, `nirt-شبکه-صفر`) and the
  saves table accepts Latin-script ids only. The button is disabled there and says why.
- **CI on PR 8**: both failures at 350a025 traced and fixed (Receiver hiss opened the audio device
  in `init` and the runner's simulator aborted; the TV rights-held test could not reach a held
  title). Green locally; the runner reruns on this push.
- The website menu still reads "The 32 films — on demand" and "…and the Khajistan Radio mixes"
  (site copy, Front lane); the Rooms list repeats the menu verbatim.

## Next actions

1. Review draft PR 8.
2. Owner: decide whether the TV's seventh door "Rooms" is the grouping wanted.
3. Front lane: refresh the two stale menu lines on the site.
4. Backend: add INSERT/UPDATE grants (own rows) on `phone_media_collections` if collections should be made from the app.
5. Owner-only, later: any TestFlight upload of this branch.
