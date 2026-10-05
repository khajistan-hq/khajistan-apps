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
  ACCOUNT as kickers at right. Select moves between sections. No system tab bar: tvOS paints
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
- **Region**: crumb kicker RECEIVER → INDUS, the name (display) and native name (headline,
  faint), the region's figures, the medium switch (TELEVISION 39 · RADIO 40 · CAMERAS 19 as
  focusable kickers, the current one underlined), then the channel grid: four columns, each card
  the name, the place as a kicker, the broadcaster in small type when it differs.
- **Player**: the picture full screen. Over it, while waking: the status band (KHAJISTAN
  RECEIVER · BROADCASTING FROM PAKISTAN · ● LIVE TELEVISION) and a ground panel at the bottom
  (state kicker, the name as headline, the place, the attribution line in small type). The
  screen opens on the ground with TUNING and the channel's name; the pigeon flies up off it as
  the picture arrives. Radio shows its name as display type on the ground. A channel change is
  described under Motion.

## Khajistan Transmission

- **Page**: KHAJISTAN TRANSMISSION (display), *N programmes · two scheduled channels · Pakistan
  time (UTC+5)*, then one card per channel: CHANNEL 1 kicker, the channel's own line from the
  schedule, and what is on now (show, programme, hours) or when it returns. Select tunes it.
  The preview-password and sign-in steps live on this page.
- **Player**: opens on the ground with the channel's name, and the pigeon flies off it as the
  programme, joined where the clock has reached, arrives; that is the sign-on. Up and down
  switch channel as under Motion. The
  status band reads KHAJISTAN TRANSMISSION · CHANNEL 1 · 18:00–18:15 PKT · MEHFIL ON TAPE with
  UP NEXT 18:15 VINYL RIPS trailing; the panel carries the slot kicker, the title, the show's
  line, KIND and ORIGIN, and the custodian and transfer credits. Off air is OFF AIR in display
  type with the return time.

## Motion

Only the content moves: the pigeon mark, and the flying pigeon at a changeover (owner ruling
2026-10-04 on the Higgsfield pigeon: loading states and transitions only). **One pigeon in the
apps, the flying one, on the skin's colours** (owner, 2026-10-05: "we have to choose one"); the
grooming loop and the sign-on ident, which opens on it and is on black, are not in the apps.

A channel change: the old sound fades to nothing (0.45 s, eased); the skin's ground comes up
over the picture (0.35 s) while the pigeon flies at the viewer; the ground holds with TUNING and
the incoming channel's name until the signal plays or fails (8 s at most); then the ground
lifts (0.7 s) as the pigeon flies up and away over the new picture, whose sound fades in once
it is actually playing (0.9 s). Reduced Motion keeps the fades and leaves the flights out.
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

## Assets

`khajistan-pigeon.gif` is bundled from `archive/assets` unmodified (the 1080px master; owner:
the master everywhere). The two flights, `flight-in.mov` and `flight-out.mov`, are rendered by
`scripts/make-pigeon-flight.py` from the Higgsfield ProRes 4444 masters (Flight-Across and
Flight-Upward V10, 1080×1920, 60 fps) as HEVC with alpha, premultiplied, with the black keying
rim choked out and the side edges feathered; the app draws the ground, so one file serves all
three skins. They are drawn at screen height, never stretched past their pixels. The rainbow TV bug is NOT used: it is not on
the live site and has no ruling for a new surface.
