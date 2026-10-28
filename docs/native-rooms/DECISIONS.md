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
17. **Each room copies the layout of the app chosen for it (owner, 2026-10-27: "copy the workflow
    and UX/UI of the apps we landed on").** Reading Room and Home follow Apple Books, the Screening
    Room the Apple TV app, Bazaar Etsy and On, Pics/Vids Cosmos, Madrassa Wikipedia and The
    Atlantic, the databases Notion, the Receiver's list YouTube TV, and the small player Sonos. What
    is copied is layout, hierarchy and flow: large titles as written, search fields, filter chips,
    shelves headed "Name ›", one solid action per screen, icon tab bar, "‹ Back". What stays the
    house's: the three skins' colours (never white), artwork fitted whole and never cropped, no
    outlined boxes (filled plates and form fields only), Home showing only this device's history
    and the rooms. The shared pieces are ios/Khajistan/Views/Shelves.swift.
18. **CC is a text key.** The Receiver's caption control reads "CC" on every live channel, filled
    while captions are on; the shared caption and chat messages name each app's own sign-in door
    (`KJConfig.signInDoor`: Library on the phone, Account on the television).
19. **A film in another script is saved as hex; no migration (2026-10-27).** The saves table's check
    takes Latin ids only, and four Screening Room handles are Persian. The app is the only writer of
    `tv:` rows and the website and dashboard read only their title and href, so such a film is saved
    as `tv:u.<UTF-8 bytes in lowercase hex>` with its real `/film/<handle>` href;
    `PassportSaves.filmHandle(ref:)` reads it back, and only where the decoded handle needed it, so a
    Latin handle that looks like hex is never misread. If Backend later widens the check, these rows
    stay valid. Advised by a Fable pass, which found no reader of the ref past its prefix.
20. **Pics/Vids collections are writable by the account (measured 2026-10-27).** The table grants
    INSERT(user_id, name, media_keys) and UPDATE(name, media_keys) per column, which a table-level
    grant list does not show; the Backend board note of 04391297 read only that list. The app sends
    exactly the website's saveCollection payloads (those columns, never an upsert) under the same
    rules (name 1–120 once trimmed, at most 500 keys of 1–160 characters); a trigger moves updated_at.
21. **Sign in on the TV from a phone, with a QR (owner, 2026-10-27: "allow people to sign in with
    their phone or with a qr code on the app or on the web so they dont have to write in apple tv
    everytime").** This narrows DECISIONS 12's QR ruling, which was about membership: the sign-in
    QR is asked for. The shape is the device-authorization grant: the TV shows a QR and a code for
    the archive's `/activate` page (`/tv` is the Receiver's TV redirect; khajistan.com is the shop);
    a signed-in phone, on that page or in the iPhone app (Library → Sign in on a TV: scan or type),
    approves after being told what asked, when, and whether the TV is on another network; the TV is
    handed a one-time magic-link token hash and makes its own session. No password crosses. Built as
    drafts on the owner's "You build all; I approve deploys", then deployed on "deploy them safely"
    (2026-10-27). Should the function be unreachable, the TV falls back to email and password and
    says phone sign-in is not available.
22. **The database by the site's own address where its host is blocked (owner, 2026-10-27: "Route
    the apps' database calls through a proxy on the website's own address … as a fallback, and make
    the app fail fast with a clear message").** Measured on the owner's Apple TV HD at home: DNS for
    the project host is right, but every TCP connection to its two Cloudflare addresses is dropped
    (−1004 after 6–8 s), while the site, supabase.com and 1.1.1.1 answer in under a second; the
    Reading Room spun 45.7 s and Pics/Vids never opened. The site's worker gains `/sb/<path>`
    (REST, functions, storage objects, auth only; Bearer and the listed headers cross, the site's
    Basic password and cookies never do). `SupabaseRoute` (shared core) asks both ways at launch
    (HEAD, 2.5 s), keeps direct whenever it answers, remembers the choice for the next launch, moves
    every project address (built or handed back, signed pages, stored files, players) onto the
    route, and with neither answering says so at once (`unreachableText`), asking again at most
    every 10 s. Realtime (live captions, chat presence) is not proxied.
23. **The Reading Room opens from the shelf this device last read (owner, 2026-10-27: "load in no
    more than 2 secs").** On the Apple TV HD the network path alone is about 3 s (1.8 s of it opening
    the connection through the proxy). The shelf's inputs (catalogue pages, kept whole under a marker
    written last; rights; custodians; the module index, kept per site and per gate state) and the
    covers (3 days) are kept on the device; the room is built from them at once, and a fresh copy is
    read behind it when the kept one is over 6 hours old (the catalogue is a billed 3 MB), applied on
    the next open so a shelf never reorders under the viewer. Without kept rights the kept shelf is
    not used. Access stays the page server's answer on every page. Measured on the owner's TV:
    1.36–1.44 s to the shelf, 1.65–1.73 s to the first cover; the first open after an install 2.9 s.

24. **The Receiver's two choices on the phone (owner, 2026-10-28: "both options should be there so
    user can choose to play a tv channel as they read"; "play reciever in background even when
    their phone is on home screen").** Two switches on the Receiver page, kept on the device, both on
    by default. *Keep playing on other pages*: on, the small player follows the viewer, now also
    inside the Reading Room reader, which covers the house bar (its name closes the reader and
    opens the Receiver); off, leaving the Receiver turns the channel off. *Play with the app
    closed*: on, the Receiver's picture lets go of its player while the app is in the background,
    so a television channel's sound carries on (radio already did, `UIBackgroundModes audio`); off,
    what is on pauses when the app leaves the screen. Pics/Vids videos and films are not covered:
    the system still pauses them. Chat and the Pics/Vids viewer do not carry the small player yet.
25. **The Apple TV reaches the reference apps too (owner, 2026-10-28: Bazaar "Bag + QR checkout";
    Pics/Vids "Saves, keep shelves").** The TV Bazaar has a bag, steppers and one Checkout; the
    checkout is the shop's own page shown as a QR for the phone, so nothing is paid on the remote.
    This narrows DECISIONS 12: an address and now a code, never a payment form. The bag is the
    phone's `BagStore`, one file for both apps. Pics/Vids keeps its region shelves (2026-10-06
    ruling) and gains Save, Collection, and Saved and collection shelves from the account. A film's
    Website is a QR of its page, the TV having no browser. A radio station closed with Menu plays on
    in a small player under every screen; unlike the phone's (DECISIONS 24) it is not a switch, and
    any other signal stops it.
