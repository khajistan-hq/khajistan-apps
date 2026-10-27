# Decisions

Each entry: what was chosen, and why, in one or two lines.

1. **Base: `origin/main` 513b617 with PR 1 merged in.** PR 1 carries the Mac Catalyst app and the
   Receiver caption fixes; main carries the live-tune and stall-limit work. They conflicted in one
   function pair (kept both) and the generated project file (regenerated).
2. **Five bar doors on iPhone: Home, Rooms, Receiver, Library, Search** (owner brief). Pics/Vids
   moves inside Rooms; Account becomes part of Library. Old `-kjtab` names (`yours`, `picsVids`)
   still land where they meant to.
3. **A room is native only once its native screen exists.** Until then its door opens the website,
   exactly as before. No placeholder screens.
4. **Rooms layout: one stack on a phone, a sidebar beside the open room in a wide window.** Each
   room keeps its own stack and is kept mounted, so moving between rooms keeps its place.
5. **No system navigation bar.** It paints white and carries the system's chrome; each stack screen
   takes the skin's ground and a house Back row (Cmd-[ on Mac).
6. **Shared logic stays single-copy by symlink** (the existing pattern, checked by
   `ios/scripts/test-core.sh`). New Foundation-only models go in `tvos/KhajistanTV/Core` and are
   linked into the phone.
7. **Room copy is not taken from stale website lines.** The site menu still says "The 32 films — on
   demand" and "the Khajistan Radio mixes"; both are out of date (sales paused 2026-10-05, mixes
   removed). Native room headers use plain accurate lines instead.
8. **Gated data is read with the preview password, or the room says it is locked.** Almost every
   room file is behind the site password until launch (measured: only
   `data/signal-room/national-services.json` answers without it). `SiteFeed` never turns a 401 into
   an empty room.
9. **The Storefront token is the website's own public token**, copied by script from
   `kj-storefront-config.js` into both configs (it is read-and-cart-only and shipped to every
   visitor). Checkout opens on the shop's own host; the app never takes payment details.
10. **Madrassa's entries are evaluated out of `madrassa.html` with JavaScriptCore**, so the page stays
    the only list. The evaluation has no bridge to the app: plain data in, JSON out.
11. **Essays are drawn natively from the feed's HTML** (headings, paragraphs with links, transcript
    rows, pictures); an embedded player is named and sent to the website. A core test checks that no
    words are lost.
12. **On Apple TV the new rooms share one "Rooms" door**; the bar keeps seven items. Buying is named
    as an address on khajistan.com; there is no QR code (the owner removed QR codes from the TV on
    2026-10-06 for membership, and a product code was not asked for).
13. **Films use the system player on phone and Mac** (scrubber, manifest subtitles, PiP, AirPlay);
    starting a film turns the Receiver off so one source plays.
14. **Saves use the website's own `passport_saves` rows**, so the website and the app show one list:
    films `tv:<handle>`, Pics/Vids `pnv:<key>` with no title or picture kept, Madrassa pieces
    `page:<path>`. A ref the table's check refuses is disabled in the app, never sent.
15. **A shared store owns its own loads.** A screen awaits the load; it does not run it. A screen
    rebuilt mid-load (iPad does this when a room opens on a pushed route) must not cancel what
    every other screen is waiting on.
16. **Nothing opens an audio device until it makes a sound.** The Receiver's tuning hiss wires its
    engine on the first sound; SwiftUI builds a view's state object on every rebuild, and a device
    with no audio output hung and aborted in `init`.
