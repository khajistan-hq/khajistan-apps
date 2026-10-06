# Khajistan for Apple TV — house style

The app looks like the website because it is measured from it: the home page, the Receiver
(`/open-frequencies`) and Khajistan Transmission (`/video`), read on 2026-10-05 off the archive
tree with computed styles. Where this file and the website disagree, the website is right and
this file is stale. Rules it inherits: `.claude/rules/frontend.md` §1–§4 and `BRAND.md`'s
"never white" and two-colour rules.

## Tokens, per skin

The skin follows the hour (`Skin.current`: day 08:00–17:00, smut 05:00–08:00 and
17:00–20:00, grove otherwise) unless the viewer holds one in Account. The choice is
**Automatic · Day · Grove · Smut**: the three names are the website switch's own
(`archive/scripts/kj-theme.js`, `LABEL`), and Automatic, the default, names what the site
does without a click. It is kept on the device (`kj.skin`) and applies at once. Every colour
in the app comes from this table and nowhere else.

| token | role | day | grove | smut |
|---|---|---|---|---|
| ground | page | `#F3FB04` | `#186409` | `#C11B6B` |
| ink | text | `#000000` | `#F3FB04` | `#F3FB04` |
| accent | labels, kickers, links | `#186409` | `#F3FB04` | `#F3FB04` |
| faint | secondary text | ink at 62% | ink at 85% | ink at 95% |
| band | status bands, focus plate | `#186409` | `#002800` | `#6E003F` |
| onBand | text on a band | `#F3FB04` | `#F3FB04` | `#F3FB04` |
| lift | pressed / raised plate | `#FFFFA0` | `#004A00` | `#8F1350` |
| mapDeep | map region fill | `#006F00` | `#7E9B45` | `#006F00` |
| mapTint | map region fill, second | `#7E9B45` | `#7E9B45` | `#7E9B45` |

Never white, never grey, never a third hue. No shadows except the one under a focused card (Cards and shelves, below). No borders, frames or boxes; spacing
separates things. One exception: a text field keeps a 2pt ink rule along its bottom, because a
viewer must see where to aim. tvOS draws its own text field as a pill that turns white under
focus, so the system field is kept at 2% opacity under a cover in the plate's colour and the
app draws the entry (bullets for a password). Sign-in opens full screen on the ground, never as
a sheet, which tvOS draws as a rounded, shadowed card.

Inside a focused or pressed control the palette re-skins itself: the ground becomes the band (or
the lift), and ink and accent become onBand. On the day skin the accent and the band are the same
green, so a kicker inside a focused card would otherwise measure 1.0:1. Views inside a button
label read `@Environment(\.palette)` to get the re-skinned values.

## Type

The website sets everything in `system-ui`, so on Apple TV the system font IS the house font.

| style | size (pt) | weight | case | tracking |
|---|---|---|---|---|
| display | 120 | black | UPPER | −0.075 em |
| headline | 72 | black | UPPER | −0.055 em |
| name | 34 | black | as written | −0.03 em |
| stat | 56 | black | — | −0.05 em |
| body | 29 | regular | as written | 0 |
| kicker | 22 | black | UPPER | +0.13 em |
| small | 24 | regular | as written | 0 |

Kickers are the accent colour. Text on a band is a kicker in `onBand`.

## Focus is the website's hover

On the website a hovered nav item, a selected suggestion and the current page all turn into a
**green plate with yellow text**. On a television focus is the hover, so: a focused control is a
`band` plate with `onBand` text, scaled 1.03, no shadow, no outline. An unfocused control sits
on the ground in `ink`. The current section in the top bar is underlined (3pt, the accent), the
way the website marks the brand link.

## Cards and shelves

Owner, 2026-10-06: *"the app should behave like apple tv native films/tv app, similar rows and
movement and clarity and smoothness."* Everything that is browsed is a **shelf**: a title in name
type (38pt) with its count in small type, over a row of fixed-size cards that scrolls sideways.
The page scrolls up and down; a press up or down moves to the nearest card of the next shelf
(each shelf is a focus section); a press left or right walks along one. The row runs past the page
margin to the screen's edge, and a page scrolled under the top bar fades out there (28pt).

- **Card motion** (`HouseCardStyle`): focus lifts the card to 1.08 on a spring (response .34,
  damping .74); a press settles it to 1.03. A soft shadow (30pt blur, 20pt down, the band colour
  at 55%, so it stays in the palette) opens under the card's picture or plate, never under its
  lettering. System card styles are not used: tvOS draws them as white platters.
- **Text cards** (channels, mixes, the two Transmission channels) sit on a `CardPlate`: the lift
  plate at rest, the band plate with onBand text under focus. Square, no border. Channel and mix
  cards are 420x190 and 440x220, so a shelf is the same height from its first card to its last.
- **Picture cards** (films, Pics/Vids): the picture lifts and casts the shadow; the title and
  lines under it keep the ground's ink. A film poster is 420pt high at its own width, never
  cropped; its text box has a fixed height and takes the poster's width, so a long title wraps
  under its own poster. Until a picture arrives a lift plate holds its place and the picture
  fades in over it (0.35s).
- **Pics/Vids stays a grid.** It is an unbounded stream of real-shaped tiles under two filters,
  which is what the website's `place()` lays out; the tiles take the card motion and a 32pt gap.

## Chrome

- **Top bar**, on every root screen: the animated pigeon (72pt) and **KHAJISTAN** (40pt black,
  −0.03 em) with *Media of the Middle World* (small, faint) at left; RECEIVER · TRANSMISSION ·
  READING ROOM · PICS/VIDS · ACCOUNT as kickers at right (READING ROOM and PICS/VIDS are the website's own nav labels). Select moves between sections. No system tab bar: tvOS paints
  its focused tab as a white pill.
- **Status band**: a full-width `band` strip, kickers in `onBand`, leading text and trailing
  text. It heads every player, as the website's console bar does.

## The Receiver

- **Front = the map.** Left: RECEIVER (display), the website's own sentence *Live television,
  live radio and public cameras from the Middle World.*, the four figures (LIVE NOW,
  TELEVISION, RADIO, CAMERAS) from `receiver-index.json`, and the *Beyond the atlas* switch with
  its line *The wider Islamicate, Rumelia to Nusantara*. Right: the map from
  `/data/region-shapes.json` (and `-extended.json` with the switch on), drawn as the website
  draws it — fills from the data (`#050505` → mapTint, `#006F00` → mapDeep), the people's
  regions hatched (9pt stripes at 45°, black at 32%), regions with no channels at 48%, the
  extensions in mapTint at 50%, labels in yellow with a black halo, the native name beneath,
  the live count under that. The map is a picture, not a control: under it runs a strip of
  every region with channels, name and live count, west to east by centroid, so right on the
  remote moves east. The region focused in the strip gains a 3.5pt yellow outline on the map
  and its label sits on a yellow plate with black text. Select opens the region. (Until
  2026-10-05 each label was its own focus point; tvOS moves focus only along the press, and
  on the owner's TV focus stuck on one region.)
- **Shelves under the front.** The sidebar, the map and its strip are the first screen; the page
  scrolls to two full-width shelves under it, as the TV app lays its rows, each peeking at the
  bottom of the first screen. **Khajistan Radio · 22 mixes** appears once the public register
  (`/data/radio/mixtapes.json`) has loaded with a mix that plays: cards in the register's own
  order, each the programme block it aired in as a kicker, the mix's title, and *place · language*
  in small type. Select plays the mix. (The page of mixes that once opened from a row here is
  gone; the shelf holds all of them.) A mix is a finished recording Khajistan made, not a live signal,
  so its player has no LIVE: the band reads KHAJISTAN RECEIVER · the block, and *Khajistan Radio mix*
  at right. The name is display type on the ground, as radio's is; under it the state, the register's
  line for the mix, *place · language · decade*, the position (*12:04 / 1:24:13*) and the attribution
  (*A Khajistan Radio mix, made and carried by Khajistan.*, or *mixed by X and carried by Khajistan.*).
  A recording has a position: left and right move thirty seconds, up and down move to the
  neighbouring mix, and a mix that ends rolls on to the next, stopping at the last.
- **Region**: crumb kicker RECEIVER → INDUS, the name (display) and native name (headline,
  faint), then one shelf for each medium the region carries: Television 39, Radio 40, Cameras 19
  and On Demand (the films filed to it), in that order. Each card is the place as a kicker, the
  name, the broadcaster in small type when it differs. Up and down in the player surf the shelf
  the channel came from. The cameras are fetched on their own and the shelf holds its place with
  the index's count until they land.
- **Player**: the picture full screen. Over it, while waking: the status band (KHAJISTAN
  RECEIVER · BROADCASTING FROM PAKISTAN · ● LIVE TELEVISION) and a ground panel at the bottom
  (state kicker, the name as headline, the place, the attribution line in small type). The
  screen opens on the ground with TUNING and the channel's name, which fades off as the picture
  arrives. Radio shows its name as display type on the ground. A channel change is
  described under Motion.

- **Letterbox**: a picture that does not fill the screen sits on **black**, in every skin
  (owner, 2026-10-05: "background should always remain black and not house skin colors").
  It is the one black in the app, and only around a moving picture; radio, the overlay, the
  tuning ground and every other screen keep the skin.

## Khajistan Transmission

- **Page**: KHAJISTAN TRANSMISSION (display), *N programmes · two scheduled channels · Pakistan
  time (UTC+5)*, then one card per channel, as the website's channel card: CHANNEL 1 · ● ON AIR,
  the channel's own line, the show on now (48pt) with NOW 18:00–18:15 PKT, and UP NEXT: the
  next three strips, time then show, the first set large. Off air the headline is *Off air*,
  then the site's line *Back at 23:00 PKT with The Feature.* and LATER. Show names only:
  programme titles are file names (owner, 2026-09-06). The two cards are text cards (a lift plate, band under focus), 64pt apart for their lift. The cards redraw on the minute. Select
  tunes. The preview-password and sign-in steps live on this page.
- **Player**: once per launch the sign-on: the pigeon flies through and the programme (joined
  where the clock has reached) tunes behind it. Later visits open on the ground with the
  channel's name. Up and down switch channel as under Motion. The
  status band reads KHAJISTAN TRANSMISSION · CHANNEL 1 with ● ON AIR trailing. The panel's
  left column carries NOW 18:00–18:15 PKT, the show as the headline, the show's line, KIND and
  ORIGIN, and the custodian and transfer credits; its right column is UP NEXT, the next three
  strips. Nothing is said twice. In the last minute of a slot, with the overlay hidden, a band
  plate at bottom right reads UP NEXT 18:15 PKT · VINYL RIPS; it goes when the overlay is woken.
  When the slot ends the channel hands over to the next strip, as the website's tuneToNow
  does once a minute. Off air is OFF AIR in display type with the return time.

## The Screening Room

- **Shelf**: **The Screening Room · 32 films on demand**, under Khajistan Radio on the Receiver's
  front: poster cards in vod.json's order, the poster whole at its own ratio and 420pt high (a
  lift plate holds a 2:3 space until it arrives), the title in name type at 28pt, the offer line
  as a kicker, and runtime · languages · country in small type. A region's **On Demand** shelf
  shows the same cards for the films it files.
- **Player**: the preview full screen, on black where it does not fill the screen. The band reads
  KHAJISTAN RECEIVER · ON DEMAND with FILM (or THE FULL FILM) at right; the panel carries the state,
  the title as headline, the record's line, what is showing (*60-second preview · the full film plays
  here*), the offer line, *A film Khajistan owns and distributes.* and *Watch the full film*. A refusal
  adds the site's sentence under the button and, for a sign-in or a purchase, the film page's QR code
  (ink modules on the ground) with its address. The panel stays while that answer is on screen.
  A film is chosen, not tuned: up and down do nothing here, as on the site. Left and right move thirty
  seconds in the full film.

## The Reading Room

The website's READING ROOM door, `/reading-room.html`, read on 2026-10-06 off
`scripts/reading-room-app.js`. The app asks what the site asks and shows what the site shows to the
same visitor.

- **Shelf.** Heading *Reading Room* and the site's line *Magazines, books and printed matter from
  the Middle World, page by page.* A tab per language and a row per shelf inside it, in the
  module index's own order (`data/rr-modules.json`, behind the site password, so it comes with the
  preview password); without it, one tab of every title and a row per region. Each tab states
  the room's three figures with rights-held titles named beside them, as `rrDepthLine` does.
- **Card.** The real scanned cover (never a product photo), the title, *region · N issues*, and
  the access line in the shelf's words: *Free — read in full*, *Free — sign in to read*, *Members*,
  *Rights pending*. The access line is the page server's own answer to an anonymous request for a
  page past the free preview; the app keeps no list of free titles.
- **Title.** Its issues as covers, with *N issues · M pages*. A rights-held title shows the
  *Preserved · not published* banner, its covers inert, and a code for the page where researchers
  ask for supervised access.
- **Reader.** One page at a time, full screen on the ground. Right turns to the next page, left to
  the one before, Select zooms to 2x and the remote moves the page, Select or Menu zooms out, Menu
  leaves. The next page is fetched while this one is read. The band (title, issue, `p. 3 / 76`) hides
  after 2.6 seconds.
- **Refusals**, in the site's words, with a code for the title's page on the website and no purchase
  in the app: *Membership required* (paid, from page 3), *Free to read — sign in to continue*
  (account-open, with the sign-in sheet), *Preserved · not published* (451), a content warning
  (*This page shows …*) held until the viewer asks, and *Page N unavailable — not yet in the archive*.

## Pics/Vids

The website's PICS/VIDS door, `/browse-archive.html` ("Born Digital Media"), read on 2026-10-05
off `scripts/kj-browse-archive.js`, `kj-media.js` and `kj-adult-notice.js`.

- **Page**: BORN DIGITAL MEDIA (headline), the site's summary line (*99,474 pictures and videos ·
  81 accounts · 6 regions*), then two rows of tabs: Everything / Pictures / Videos, and All plus the
  regions the roster carries, west to east (Maghreb, Mashriq, Anatolia, Persia, Khorasan, Indus).
  The current tab is underlined; focus is the band plate. Under them the exact count of what the
  filters leave, then the stream.
- **Stream**: four columns, the shortest column taking the next tile (the site's `place()`), each
  tile the object's own shape on a house-lift plate that holds its place until the picture fades
  in, never cropped; the tile lifts under focus like any card. A video's tile carries
  *▶ Video*, every tile the account as `@name` in small type. Select opens the viewer; the next page
  of 60 loads as the end comes into view; the last line is the site's *N objects · that is all of it*.
- **Notice**: first thing on the page for anyone who has not dismissed it, in the policy file's
  words, with OK and a *Don't ask again* switch. It blocks nothing; the stream loads under it.
- **Viewer**: the picture fitted whole on the ground, or the video in AVPlayer. Over it, while waking,
  the status band (KHAJISTAN PICS/VIDS · @account · PICTURE or VIDEO) and a ground panel with the
  site's meta line (kind · region · date · size) and the caption. Left and right move through the
  stream; a clip loops; a Khajistan TV row opens on its poster and says *Sign in to watch Khajistan
  Transmission.*, and Select opens the sign-in sheet.

## Motion

Only the content moves: the pigeon mark, and the pigeon at a changeover (owner ruling
2026-10-04 on the Higgsfield pigeon: loading states and transitions only).

**A channel change in the Receiver is the pigeon over the live picture, and a hard cut**
(owner, 2026-10-06: "hard cut is ok from one channel to next ... and the pigeon transition on it",
with the flights they starred in Higgsfield). The next channel tunes on a second player, out of
sight and silent, while the old one keeps playing and its sound fades. The bird flies over the
old picture; the channel cuts behind it at the moment it covers the most of the screen (where it
covers half or more: Across, and the closing wing of Swerve and Loop), or the moment the new
channel plays if that is later, and the bird flies on over the new one. Only the sound eases up.
If a flight ends before the channel plays, another short one follows.

| flight | length | | cut |
|---|---|---|---|
| Across | 3.7 s | into the lens, a wing over 70% of the screen | behind the wing |
| Swerve | 4.0 s | from a wing filling the screen, banks round, back into the lens | behind the closing wing |
| Hover | 4.7 s | hangs on its wings, then lifts away | when the channel plays |
| Lift | 4.5 s | hangs, claps its wings, lifts away | when the channel plays |
| Loop | 8.0 s | loops and rolls between two full-screen wings; for slow channels | behind the closing wing |
| Twirl | 9.5 s | loops and a barrel roll across; for slow channels | when the channel plays |

The long two fly only for a channel that took 8 s or more to tune here before (`TuneTimes`, kept
per channel on the device). Each flight is two ordinary H.264 videos, the bird's colour at 1080
and its matte at 540, decoded in hardware and composited on the GPU on a display link of its own
thread (`PigeonOverlay`, `PigeonRenderer`). HEVC with alpha was tried first: the Apple TV HD decodes
it in software and lost a third to two-thirds of the frames while the next channel started.
Measured on the owner's Apple TV HD with the pair: 97-113 frames per flight, at most 2 skipped.

Transmission and its sign-on keep the website's own wing wipe (`wing-wipe-in/out.mp4`): the wing
covers the screen, the programme tunes behind it, the wing leaves, hard cut, sound fades.

**The dancer**: while he dances, what would sit behind him (the station's name on radio, the
programme on a sound-only transmission) moves to the top right, smaller and at full strength,
and back to the centre when he stops (owner, 2026-10-06).

**The player strip** (owner, 2026-10-05: the bar was "too thick and not smooth"): one slim band
along the bottom in the band colour, the name (30pt black), the place or the slot beside it,
the attribution or the show's line under them in small type, the medium at the right, and on
Transmission UP NEXT with its time and show. It rises 40pt and fades in over 0.35 s, and goes
the same way 2.6 s into playback. It waits while a signal tunes: the ground says so.

**Captions** (live, programme and film alike) are one plate, `kj-captions.css`'s: 52pt semibold,
centred, black on `#F3FB04` by day, `#F3FB04` on `#002800` in grove and on `#6E003F` in smut, no
outline, no shadow, each line laid out on its own direction. The plate sits 24pt above the strip
(or the film's panel) while it is up and moves down with it. Its control is the strip's last item,
a kicker in onBand underlined while on; reached with right, it takes the inverted plate (band text
on onBand), which reads on the band in every skin.

**Back** (Menu) on any section but the Receiver returns to the atlas; in the Receiver it pops a
region back to the map, and the map leaves the app as tvOS does.

Overlays hide 2.6 seconds into playback.

## The dancer

Ported from the website's `kj-scope.js` "dancer" and the terms `open-frequencies.js` and
`video.html` run him on: the same 23 moves (Twerk weighted four to one, Kawliya only for the
long-haired figure), the same two figures, the six entrances, six exits and five breaks, the same
proportions and angles. He is drawn in the band colour with ink stripes, head and props: green on
yellow by day, `#002800` on the grove ground, `#6E003F` on smut. What he dances in front of drops
to 26% while he draws.

- **Where.** Full screen over the ground while sound with no picture plays: a receiver radio
  channel, and a Khajistan Transmission programme marked `audio_only` (all of channel 2, and
  channel 1's records). Never over television, a camera or a programme with a picture.
- **Never on recitation.** A channel whose name, native name or broadcaster says Quran, Koran,
  recitation, tilawa or Nida al-Islam (Latin or Arabic), or whose record carries
  `reverent: true` or `visualiser: false`, gets no dancer and no tap.
- **Only to real audio, only to a beat.** He reads the samples of the signal being heard and
  comes on only when the onset envelope carries a beat (the site's comb autocorrelation, on at
  .20 held a second, off under .14 for five seconds). A voice alone never brings him on.
- **Which carriers.** A Transmission file (Supabase storage, a Dropbox link) is tapped on
  AVPlayer. A live MP3 or AAC radio mount is played by the app itself (`LiveRadio.swift`, the
  site's Safari player), because AVPlayer exposes nothing to tap on one. HLS carries no readable
  samples: no dancer, and nothing in his place.
- **Reduce Motion:** no dancer, and radio plays on AVPlayer as before.

## Top Shelf

The banner tvOS draws above the app row while the Khajistan icon has focus, before the app is
opened. Owner, 2026-10-05: *"make beautiful apple tv like banner when app is hovered on but not
clicked yet you can use higgsfield but it has to be very khajistan in house style"*.

- **Static images**, shown when the extension has nothing: `Top Shelf Image Wide` (2320×720) and
  `Top Shelf Image` (1920×720), each with a 2x. The masthead on the day ground: the pigeon master,
  KHAJISTAN in black type at −0.03 em, and *Media of the Middle World* as a kicker in the accent.
  tvOS shows the wide image 784 points high across the screen's 1920, so about 280 points of each
  side are cut off; the group sits inside that. Drawn by `scripts/make-top-shelf.sh` with the
  extension's own drawing code, never by hand.
- **The carousel**, `TopShelf/`, a `TVTopShelfContentProvider` in the carousel style `.actions`.
  Carousel, not sectioned: each slide is a full-screen picture the extension draws, so the banner
  is in the house style edge to edge; sectioned rows are system posters under system titles. In
  `.actions` tvOS adds only its own controls (Play, More Info, the arrows, the page dots and
  "Swipe up for full screen"), drawn in its own white. The slides follow the skin of the hour:
  - **Receiver**: KHAJISTAN RECEIVER, the live count (`totals.live` in the public
    `receiver-index.json`), LIVE NOW, the website's sentence, and the core map from
    `region-shapes.json` drawn as the app draws it, without labels. More Info opens the receiver.
  - **Channel 1, Channel 2**: what the station clock has on each now (show, programme, hours in
    PKT, the show's line, up next), or OFF AIR and when it returns; the pigeon at right. Play
    tunes the channel, More Info opens the station page. The schedule is asked for without a
    password first, then with the preview password, which the app keeps in the keychain group
    `$(AppIdentifierPrefix)com.khajistan.tv.shared` that it shares with the extension. Keychain
    sharing needs only the team prefix, so a free Apple ID's signing carries it.
  - **Transmission**, in place of the two channels when no schedule can be read: the website's
    own description of the station, and the pigeon.
  - A slide that cannot be fetched is left out. With nothing at all, tvOS shows the static image.
  - Everything sits above 740 points (the app row covers the slide from 784, and the opened
    carousel puts its buttons at the bottom centre) and between 200 and 1720 (its arrows).
- **Links**: `khajistan://receiver`, `khajistan://receiver/<region id>`,
  `khajistan://transmission`, `khajistan://transmission/<1 or 2>` (`Core/DeepLink.swift`).
  Anything else is ignored.
- **Higgsfield** was offered for this banner by the owner in chat on 2026-10-05, which widens the
  2026-10-04 pigeon ruling (loading states and transitions) to the Top Shelf, for the house pigeon
  only and never presented as an archive holding. It is not used: the pigeon master is the
  brand's own mark and reads better on a still banner than a frame of the photoreal bird. Nothing
  was spent.
- Pics/Vids has no section on this branch and no slide.

## Assets

`khajistan-pigeon.gif` is bundled from `archive/assets` unmodified (the 1080px master; owner:
the master everywhere). The flights, `flight-<name>-<720|1080|2160>.mov`, are rendered by
`scripts/flights/render_flight.py` from the Higgsfield masters (owner-local, `output/Higgsfield
Assets/Khajistan Flights 2026-10-05/`): the backdrop plate per pixel, alpha unmixed against it,
the generator's colourless shadows and its bright edge halo removed, colour premultiplied. The
app draws the ground, so one file serves all three skins. The rainbow TV bug is NOT used: it is not on
the live site and has no ruling for a new surface.
