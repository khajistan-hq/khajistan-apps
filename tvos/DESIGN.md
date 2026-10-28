# Khajistan for Apple TV — house style

The app looks like the website because it is measured from it: the home page, the Receiver
(`/open-frequencies`) and Khajistan Transmission (`/video`), read on 2026-10-05 off the archive
tree with computed styles. Where this file and the website disagree, the website is right and
this file is stale. Rules it inherits: `.claude/rules/frontend.md` §1–§4 and `BRAND.md`'s
"never white" and two-colour rules.

## Tokens, per skin

The skin follows the sun (`Skin.current`, the website's KJSky: day with the sun above +6°,
smut between ±6°, grove below, at the coordinate tzdata gives the device's time zone, and
the site's hour bands for a zone the table lacks) unless the viewer holds one in Account. The choice is
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
| kicker | 24 | black | UPPER | +0.13 em |
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
- **Text cards** (channels, the two Transmission channels) sit on a `CardPlate`: the lift
  plate at rest, the band plate with onBand text under focus. Square, no border. Channel
  cards are 420x190, so a shelf is the same height from its first card to its last. A channel
  card leads with its medium's mark (an ink square, the glyph in the ground's colour), as a live
  guide's row does.
- **Picture cards** (films, Pics/Vids): the picture lifts and casts the shadow; the title and
  lines under it keep the ground's ink. A film poster is 420pt high at its own width, never
  cropped; its text box has a fixed height and takes the poster's width, so a long title wraps
  under its own poster. Until a picture arrives a lift plate holds its place and the picture
  fades in over it (0.35s).
- **Pics/Vids is shelves by region** (owner, 2026-10-06; see Pics/Vids below). Its tiles are
  picture cards at a fixed 300pt height.

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
- **Shelf under the front.** The sidebar, the map and its strip are the first screen; the page
  scrolls to the Screening Room's full-width shelf under it, as the TV app lays its rows, peeking
  at the bottom of the first screen. The Khajistan Radio mixes are not on the TV (owner,
  2026-10-06): they play as programmes on Transmission's channel 2, the website's sound channel.
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
  arrives. Radio shows its Now Playing on the ground: the radio mark large, ● NOW PLAYING · LIVE
  RADIO, the station's name in display type, and its place and broadcaster. A channel change is
  described under Motion.
- **Guide** (2026-10-27, after YouTube TV's live guide): Guide is the strip's third control, after
  CC and Like, reached with Right. Select opens it over the left of the picture, which plays on:
  every channel of the shelf the viewer came from, numbered, each row the medium's mark, the name
  and the place, hairlines between, ● LIVE on the one playing. Up and down light a row (the focus
  plate, 1.03), Select tunes it behind the pigeon, Left or Menu closes it. Like CC and Like it is
  lit by the remote and never takes focus, so presses keep reaching the player.
- **Small player** (2026-10-28, after Sonos): Menu on a radio station that is playing leaves it
  playing. Under every section of the top bar (the gap was "while browsing other tabs"), below the
  page, a band plate (a full-screen page opened over a section covers it until Menu comes back): the radio mark on an onBand tint, the
  station's name and *Radio · On air* (Paused, Tuning…), then Play/Pause and Off. Its controls are
  onBand on the band and swap colours under focus (the onBand plate, band text, 1.03); it is its own
  focus section, so Down from a page reaches it. Select on the name opens the station full screen
  again. Off stops it. Any other signal (a channel, Transmission, a film, a Pics/Vids video) stops it
  as it starts: one signal at a time. Television stops with its screen, as before.

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

## Sign in

Owner, 2026-10-27: "sign in with their phone or with a qr code". Sign-in opens on **Sign in with
your phone**: at left the QR for `khajistan-archive.pages.dev/activate?code=…` on a 520pt plate,
dark modules on a light plate in every skin (ink on the ground by day; the ground's colour on an ink
plate in Grove and Smut, because a camera reads an inverted QR badly; checked by decoding the
screenshots); at right the address, the code in 96pt monospaced black, how long it lasts, and
**Use email and password instead**, where focus starts. The TV asks every five seconds; once a
phone approves, it says *Signed in as …* for a moment and closes. A code that runs out offers
**Get a new code**. When the function cannot be reached the password form opens and says so. The
password form keeps **Sign in with your phone instead**. DEBUG: `-kjsigninfixture`.

## Rooms

The Screening Room, the Bazaar, the Madrassa and the databases under one door (DECISIONS 12),
each laid out after the app chosen for it on the phone (DECISIONS 17), adapted to the remote.

- **Door** (the TV's Home; Apple Books Home and the Apple TV app's Up Next): ROOMS (headline) and its
  line, then the tiles in one row, **picture first** (owner, 2026-10-28: "picture first … like how
  apple tv has photos or images for section"): a picture card, one of the archive's own pictures
  fitted whole on the lift plate (365 wide, 310 when Chat makes five; 1.2 times as high), which
  lifts and casts the shadow; under it the name, a count where the room's list is already on the
  device (nothing is fetched for it), and the room's line whole. The pictures are bundled
  (`Room*` in the asset catalogue, a few hundred KB), so the door downloads nothing for them:
  Screening Room a house poster (*Kalak Nazan Khoshgele*), Bazaar a Khajistan fridge magnet from
  the shop's own cut-outs, Madrassa an Urdu booklet, Databases a Lollywood film booklet, Chat a
  Pics/Vids clip of musicians round a drum. The phone's Home and Rooms list carry the same set. **Chat** is the fifth tile and opens the Chat
  section, in builds that carry it. Under them: **Continue**, the titles read on this device
  (`kj.readingPlaces`), as covers when the Reading Room's shelf is already in hand and otherwise as
  text cards with the name and page this device kept, so the door never starts the catalogue load;
  either opens the Reading Room at the reader on its page. Then Up Next from this device when the
  Screening Room's catalogue is already loaded. Then **Opened lately**: the last eight things opened
  on this device (`kj.openedLately`, newest twelve kept: a title's page, a film's page, a writing,
  an object, a database), as text cards with the room as kicker; Select opens it again, asking for
  that room's list only then. Only this device's history, never a pick. DEBUG builds take
  `-kjroom <name>`.
- **Screening Room** (the Apple TV app): Up Next (films whose full film stopped part-way on this
  device, `kj.filmPlaces`, with a progress line on the poster and *Stopped at 20:00*), Your
  watchlist when signed in, then a poster shelf per country. A poster opens the **film's page**:
  the poster whole at left (720pt high); the title, its line, one solid **Play** (or *Resume from
  20:00*) with Preview, Watchlist and **Website** beside it, then Information, label beside value.
  The TV has no browser, so Website shows the film's page as a QR (dark modules on a light plate,
  as the sign-in screen's) and its address, in place over the page (Menu or Back closes it): the
  page opens on the phone. Codes and the bag are drawn in place over the page. (A third
  full-screen cover that tvOS closed on Menu once sent SwiftUI into a layout loop in Day under
  accessibility. The cause was `.preferredColorScheme` handed down through nested hosting
  controllers; the skin's style is now set once on the window, and deep covers are safe.) Play asks
  vod-token in the player; a refusal is the site's words there. A solid action is the lift plate
  at rest and the focus plate under focus. The Receiver's own film shelves still open a film on
  its preview, as under The Screening Room below.
- **Bazaar** (Etsy; On's bag and checkout): a **Bag · N** control heads the room; a shelf per
  category; a card is the object fitted whole on a lift plate (340pt square), the price first under
  it, then the name. The object's page: the picture on its plate, the shop's live price (stat
  type), the options as chips that change the price shown, one solid **Add to bag** for the option
  chosen (with *Bag · N* beside it once something is in it), the description, and *Or buy it on
  your phone or computer at khajistan.com/products/…*. The **bag** (owner, 2026-10-28: "Bag + QR
  checkout"): a row per line, the name, option and unit price, then − count + (− is a bin at one),
  hairlines between; the subtotal, *Delivery and taxes · At checkout*; one solid **Checkout**. It
  asks the shop for a cart of the lines and shows the shop's checkout page as a QR, *Point your
  phone's camera at the code to pay on khajistan.com. Nothing is paid on the TV.* The bag is the
  phone's own store (`BagStore`, `kj.bag`), one file for both apps.
- **Madrassa** (Wikipedia and The Atlantic): titles and text in the system serif. Reference cards
  carry the entry's short description and its picture beside it; writing cards are the lead
  picture on a plate, the date, the title and the summary. A writing opens with its section, the
  headline, then the date with **Save** beside it (on the account, with the website's saves; signed
  out it opens sign-in), then **Contents** where it has three headings or more: a line per heading,
  Select moves the remote to that heading and the page follows. It reads whole, block by block,
  and ends *Continue on your phone, or on the website: …*.
- **Databases** (Notion): the systems as a grid of text cards; a system is a table under a
  search bar (owner, 2026-10-28: the indexes should search song names and metadata; the house text
  field, hint *Song, artist, album, label, year* on the music indexes; every word must be in the
  title or a property, as on the phone; applied once typing pauses for 0.3 s), then Notion's
  toolbar: **Filter** and **Sort**, each opening a panel on the ground. Filter lists the properties
  with a choice to make down the left (tabs) and the chosen one's values with counts beside them
  (*All* first, a tick on the one in force); Select applies and closes. Sort lists *As listed*,
  *A–Z*, and *Newest*/*Oldest* where the records carry a year. Each filter in force is a pill
  after them, *Name: value ✕*; Select on it takes it off. Then the count, hairlines between rows, the title and the first two properties in columns; a record
  is a property page, label column beside value, each row a focus stop.

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
- **Continue** (2026-10-27, after Apple Books): above the language tabs, the titles read on this
  device, newest first (`kj.readingPlaces`: per title the issue and page, kept when the reader
  closes on a page), each opening the reader at its page. Rights-held titles are left out.
- **Title.** The cover large at left (360x490), and beside it the title, its figures and one solid
  action: *Read*, or *Continue · issue · p. N* where this device stopped; a rights-held title has
  none. Then its issues as covers, with *N issues · M pages*. A rights-held title shows the
  *Preserved · not published* banner, its covers inert, and a code for the page where researchers
  ask for supervised access.
- **Search** (Apple Books): the house text field over the shelf, hint *Titles, in any script*.
  Typing replaces Continue, the tabs and the shelves with a count and a grid of the titles whose
  name, native name or byline holds what is typed, from the shelf already held.
- **Whole shelf.** Each row's heading is *Name ›* with its count, a focus stop above its covers;
  Select opens the shelf whole, as a grid under its name, and a cover opens the title.
- **Reader.** One page at a time, full screen on the ground. Right turns to the next page, left to
  the one before, Select zooms a step at a time, 2x, 3x, 4x and 6x (the website's ceiling, as the
  phone), and the remote moves the page; Menu zooms out a step, and leaves from the whole page. The next page is fetched while this one is read. The band (title, issue, `p. 3 / 76`) hides
  after 2.6 seconds.
- **Refusals**, in the site's words, with a code for the title's page on the website and no purchase
  in the app: *Membership required* (paid, from page 3), *Free to read — sign in to continue*
  (account-open, with the sign-in page), *Preserved · not published* (451), a content warning
  (*This page shows …*) held until the viewer asks, and *Page N unavailable — not yet in the archive*.

## Pics/Vids

The website's PICS/VIDS door, `/browse-archive.html` ("Born Digital Media"), read on 2026-10-05
off `scripts/kj-browse-archive.js`, `kj-media.js` and `kj-adult-notice.js`.

- **Page**: BORN DIGITAL MEDIA (headline), the site's summary line (*99,474 pictures and videos ·
  81 accounts · 6 regions*), then one row of tabs, Everything / Pictures / Videos, the page's one
  control: the current one is underlined, focus is the band plate, and the choice applies to every
  shelf below. The website's region tabs are gone; the shelves are the regions.
- **Shelves** (owner, 2026-10-06: "Pics/Vids as shelves, grouped by region"): one for each region
  the roster carries, west to east (Maghreb, Mashriq, Anatolia, Persia, Khorasan, Indus), titled
  with the region and its exact count under the current filter. Each is its own stream
  (`PicsVidsStore.feeds`): it asks for its first page of 60 when it comes on screen, and for the
  next when focus is within eight cards of its end. A region with nothing under the filter has no
  shelf. Picking a filter starts every shelf over.
- **Cards**: the object's own shape at a fixed 300pt height (the width follows the row's own
  dimensions, so nothing moves when the picture arrives), on a house-lift plate that holds its
  place until the picture fades in, never cropped; lifts under focus like any card. A video's
  card carries *▶ Video*, every card the account as `@name`, cut to the card's width. Select
  opens the viewer.
- **Notice**: first thing on the page for anyone who has not dismissed it, in the policy file's
  words, with OK and a *Don't ask again* switch. It blocks nothing; the shelves load under it.
- **Viewer**: the picture fitted whole on the ground, or the video in AVPlayer. Over it, while waking,
  the status band (KHAJISTAN PICS/VIDS · @account · PICTURE or VIDEO) and a ground panel with the
  site's meta line (kind · region · date · size), the caption, and **Save** and **Collection** on a
  band strip (owner, 2026-10-28: "Saves, keep shelves"). They are lit by the remote, as the
  Receiver's strip is: *↓ Save* says Down lights Save, Right lights Collection, Select works the
  one lit, Up or Menu lets go. Save is the account's (`pnv:` refs, as the website's heart); signed
  out it says where to sign in. Collection opens a panel of the account's collections, a tick
  where the object is in one (Select puts it in or takes it out), and a field to make a new one
  with the object in it.
- **Saved** (signed in): above the regions, a shelf of what the account saved and one per
  collection, newest first, the newest hundred each, read through the gated public view (an object
  taken off the shelf is not drawn). Its viewer steps through that shelf. Left and right move through the
  shelf it came from (loading that shelf's next page at its end); a clip loops; a Khajistan TV row opens on its poster and says *Sign in to watch Khajistan
  Transmission.*, and Select opens the sign-in page.

## Motion

Only the content moves: the pigeon mark, and the pigeon at a changeover (owner ruling
2026-10-04 on the Higgsfield pigeon: loading states and transitions only).

**A channel change in the Receiver is the pigeon over the live picture, and a hard cut**
(owner, 2026-10-06: "hard cut is ok from one channel to next ... and the pigeon transition on it",
with the flights they starred in Higgsfield). The next channel tunes on a second player, out of
sight and silent, while the old one keeps playing and its sound fades. The bird flies over the
old picture; the channel cuts the moment the new channel plays, and the bird flies on over the
new one. No flight fills the screen: Swerve and Loop, which closed on a wing filling the frame,
were retired on 2026-10-08 (owner: "remove the one where pigeon fully covers the full screen with
the wing and just leave the other one on"). Only the sound eases up. One press is one
flight: if the bird has gone before the channel plays, the channel cuts in at once and shows its
own tuning state (owner, 2026-10-06: the pigeons "keep playing/looping"). Transmission switches
channel the same way.

| flight | length | | cut |
|---|---|---|---|
| Hover | 4.7 s | hangs on its wings, then lifts away | when the channel plays |
| Twirl | 9.5 s | loops and a barrel roll across; for slow channels | when the channel plays |

**The flight is timed to the channel** (owner, 2026-10-06: "use appropriate timed transitions"):
the shortest flight that outlasts what the channel has taken to tune on this device, plus half a
second (`TuneTimes`, kept per channel, learned even when the cut came first). Transmission's
channel 1 comes off Dropbox in 5.5-6.7 s on the Apple TV HD and gets Twirl; its channel 2
(0.7 s) and most live channels get Hover. Across and Lift were retired the same day:
Across's darker bird broke the one mascot, and Lift repeated Hover. Each flight is two ordinary H.264 videos, the bird's colour at 1080
and its matte at 540, decoded in hardware and composited on the GPU on a display link of its own
thread (`PigeonOverlay`, `PigeonRenderer`). HEVC with alpha was tried first: the Apple TV HD decodes
it in software and lost a third to two-thirds of the frames while the next channel started.
Measured on the owner's Apple TV HD with the pair: 97-228 frames per flight, at most 2 skipped.

Transmission's sign-on is the skin's colour with the channel's name and a flight over it while the
programme tunes behind, then the cut; its channel switch is the Receiver's. The website's wing wipe
is retired in the app.

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
