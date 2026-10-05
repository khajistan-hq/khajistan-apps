# Khajistan for Apple TV — house style

The app looks like the website because it is measured from it: the home page, the Receiver
(`/open-frequencies`) and Khajistan Transmission (`/video`), read on 2026-10-05 off the archive
tree with computed styles. Where this file and the website disagree, the website is right and
this file is stale. Rules it inherits: `.claude/rules/frontend.md` §1–§4 and `BRAND.md`'s
"never white" and two-colour rules.

## Tokens, per skin

The skin follows the hour exactly as before (`Skin.current`). Every colour in the app comes
from this table and nowhere else.

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

Never white, never grey, never a third hue. No shadows. No borders, frames or boxes; spacing
separates things. One exception: a text field keeps a 2pt ink rule along its bottom, because a
viewer must see where to aim.

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

## Chrome

- **Top bar**, on every root screen: the animated pigeon (72pt) and **KHAJISTAN** (40pt black,
  −0.03 em) with *Media of the Middle World* (small, faint) at left; RECEIVER · TRANSMISSION ·
  PICS/VIDS · ACCOUNT as kickers at right (PICS/VIDS is the website's own nav label). Select moves between sections. No system tab bar: tvOS paints
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
- **Khajistan Radio** is the last row of the map area, under the strip: *KHAJISTAN RADIO · 22 mixes*,
  as wide as the map so that a press down from any region lands on it. It appears once the public
  register (`/data/radio/mixtapes.json`) has loaded with a mix that plays. Select opens the mixes:
  crumb RECEIVER → KHAJISTAN RADIO, the name (display), *22 mixes*, then four columns of cards in the
  register's own order, each the mix's title, the programme block it aired in as a kicker, and
  *place · language* in small type. A mix is a finished recording Khajistan made, not a live signal,
  so its player has no LIVE: the band reads KHAJISTAN RECEIVER · the block, and *Khajistan Radio mix*
  at right. The name is display type on the ground, as radio's is; under it the state, the register's
  line for the mix, *place · language · decade*, the position (*12:04 / 1:24:13*) and the attribution
  (*A Khajistan Radio mix, made and carried by Khajistan.*, or *mixed by X and carried by Khajistan.*).
  A recording has a position: left and right move thirty seconds, up and down move to the
  neighbouring mix, and a mix that ends rolls on to the next, stopping at the last.
- **Region**: crumb kicker RECEIVER → INDUS, the name (display) and native name (headline,
  faint), the region's figures, the medium switch (TELEVISION 39 · RADIO 40 · CAMERAS 19 as
  focusable kickers, the current one underlined), then the channel grid: four columns, each card
  the name, the place as a kicker, the broadcaster in small type when it differs.
- **Player**: the picture full screen. Over it, while waking: the status band (KHAJISTAN
  RECEIVER · BROADCASTING FROM PAKISTAN · ● LIVE TELEVISION) and a ground panel at the bottom
  (state kicker, the name as headline, the place, the attribution line in small type). Tuning
  and buffering show the grooming pigeon over CONNECTING…, as the website's receiver does.
  Radio shows its name as display type on the ground. A channel change plays the wing wipe.

## Khajistan Transmission

- **Page**: KHAJISTAN TRANSMISSION (display), *N programmes · two scheduled channels · Pakistan
  time (UTC+5)*, then one card per channel: CHANNEL 1 kicker, the channel's own line from the
  schedule, and what is on now (show, programme, hours) or when it returns. Select tunes it.
  The preview-password and sign-in steps live on this page.
- **Player**: once per launch the sign-on — wing in, the ident, wing out — then the programme
  joined where the clock has reached. Up and down switch channel through the wing wipe. The
  status band reads KHAJISTAN TRANSMISSION · CHANNEL 1 · 18:00–18:15 PKT · MEHFIL ON TAPE with
  UP NEXT 18:15 VINYL RIPS trailing; the panel carries the slot kicker, the title, the show's
  line, KIND and ORIGIN, and the custodian and transfer credits. Off air is OFF AIR in display
  type with the return time.

## Pics/Vids

The website's PICS/VIDS door, `/browse-archive.html` ("Born Digital Media"), read on 2026-10-05
off `scripts/kj-browse-archive.js`, `kj-media.js` and `kj-adult-notice.js`.

- **Page**: BORN DIGITAL MEDIA (headline), the site's summary line (*99,474 pictures and videos ·
  81 accounts · 6 regions*), then two rows of tabs: Everything / Pictures / Videos, and All plus the
  regions the roster carries, west to east (Maghreb, Mashriq, Anatolia, Persia, Khorasan, Indus).
  The current tab is underlined; focus is the band plate. Under them the exact count of what the
  filters leave, then the stream.
- **Stream**: four columns, the shortest column taking the next tile (the site's `place()`), each
  tile the object's own shape inside a house-lift plate, never cropped. A video's tile carries
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

Only the content moves: the pigeon mark, the grooming loop while waiting, and the wing at a
changeover (owner ruling 2026-10-04 on the Higgsfield pigeon: loading states and transitions
only). Reduced Motion stills the mark and the loop and cuts the wipes; the ident still plays and
is skippable. Overlays hide 2.6 seconds into playback.

## Assets

Bundled from `archive/assets`, unmodified: `khajistan-pigeon.gif` (the 1080px master; owner:
the master everywhere), the grooming loop (`home-pigeon/grooming.webp`, which ImageIO animates
as Safari does), `tv/khajistan-signon-ident.mp4`,
`tv/khajistan-wing-wipe-in.mp4` and `-out.mp4`. The rainbow TV bug is NOT used: it is not on
the live site and has no ruling for a new surface.
