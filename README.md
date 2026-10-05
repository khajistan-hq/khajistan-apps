# Khajistan for Apple TV

Native SwiftUI application for the Khajistan Receiver and Khajistan Transmission, targeting tvOS 17 and later. Open **tvos/KhajistanTV.xcodeproj** in Xcode 26 or newer. The app has no third-party dependencies and uses no keys beyond the public Supabase anon key.

It is drawn in the house style measured from the website, recorded in [`DESIGN.md`](DESIGN.md): the yellow ground and green bands of the day skin, grove at night and smut at dawn and dusk, the system font at the website's weights, and focus drawn as the website's hover, a green plate with yellow text.

## What v1 carries

**The chrome.** The animated pigeon and KHAJISTAN head every screen, with RECEIVER, TRANSMISSION, PICS/VIDS and ACCOUNT beside them. There is no system tab bar.

**The skin.** Account offers Automatic, Day, Grove and Smut. Day, Grove and Smut are the names on the website's switch; Automatic follows the hour and is the default. The choice is kept on the Apple TV and applies at once.

**The Receiver.** The front is the region map, drawn from the website's own geometry and colour rules, with the four live figures and the "Beyond the atlas" switch beside it. A strip of the regions with channels runs under the map, west to east, and the remote walks it; the focused region is outlined on the map and carries its plate with the native name and live count. The switch adds the Islamicate extensions, including the two Indian doors the website keeps behind it. A region opens on its figures and a grid of television, radio and cameras. The lists come from the public files the website's receiver reads: the receiver index, the per-region shards, the denylist, and the off-air and health feeds. Each stream is resolved through `/api/frequency` at tune time and played by AVPlayer, under the status band (KHAJISTAN RECEIVER, BROADCASTING FROM …). A channel change is carried by the house pigeon in flight over the skin's colour; a slow signal gets a longer flight.

**Khajistan Transmission.** A station page shows both channels, the show each is carrying now with its hours, and the next three strips on each, in Pakistan time. Off air, a card says when the channel is back and with what. Channel 1 and Channel 2 are tuned by the station clock, which runs on Pakistan Standard Time, the same clock as the website. Once per launch the player signs on with the wing and the ident, as the website does.

- Tuning joins the programme on air at the point it has reached.
- A handover starts the next programme inside the slot's roster.
- A channel with nothing on shows an off-air state that names when the channel returns.
- The panel carries what is on now, its hours and the show's line, kind, origin, and the custodian and transfer lines, beside the next three strips. In the last minute of a slot a notice names what is up next. When a slot ends the channel moves to the next one, as the website does.
- Playback needs a free account, signed in with email and password. `tv-play` refuses anonymous requests (owner ruling 2026-09-09, recorded in the function's source). INTENT §5 still says Khajistan TV is open with no account; the server decides. Accounts made on the website with a password sign in here. An account that has only ever signed in through emailed links has no password, and no public page on the website sets one.
- Until launch the schedule sits behind the site's preview password, which the app asks for.

**Khajistan Radio.** The 22 mixes of `data/radio/mixtapes.json`, the public register, open from a row under the region strip on the Receiver's front. The website folded the mixes into its receiver as one of its media (owner, 2026-08-16) and, on 2026-08-21, made them programmes on Khajistan TV's sound channel, keeping the register as the record of what a mix is. The app lists the register itself, in its order, and plays each mix's public mp3 in AVPlayer with the old receiver's labels (*Khajistan Radio mix*, the programme block, *made and carried by Khajistan*) and its position bar's time format. A mix with `hidden` set, or an address that is not a public https one, is dropped, as the old receiver dropped it.

**Pics/Vids.** The website's PICS/VIDS door (`/browse-archive.html`, Born Digital Media). It reads the same Supabase view and function the page reads, with the anon key: `pnv_accounts` for the roster of vetted accounts, `pnv_media` for rows of those accounts only (ordered `feed_rank`, then `corpus`, 60 to a page), and `rpc('pnv_facets')` for the summary line. The filters are the page's Everything / Pictures / Videos and its regions, which the page reaches through the atlas map. Rows become URLs by `kj-media.js`'s rules (Supabase storage, R2, and Khajistan TV's poster bucket and `tv-play`), tested against that file. The entry notice is the site's, in its words, with its three states. Khajistan TV rows show their poster to anyone; their video needs the same account `tv-play` asks for on the Transmission page, and the viewer opens the sign-in sheet in place.

**The Top Shelf.** While the icon has focus, tvOS shows a carousel the extension in `TopShelf/` draws from live data, in the skin of the hour: the receiver's live count over its map, and what Channel 1 and Channel 2 are carrying now (or, without the schedule, the station's own description). Each slide opens the app at its screen through a `khajistan://` link. When the extension cannot draw a slide, tvOS shows the static masthead. DESIGN.md has the layout and the reasons.

**The Screening Room.** The films of `data/khajistan-tv/vod.json`, read as the website's receiver reads them (`filmChannel()`, `marqueeOffer()`, `broadcastRegionFor()` in `scripts/open-frequencies.js`). They open from a row under Khajistan Radio on the Receiver's front, and a region that files films carries them as **On Demand** in its medium switch, as the site's switch calls it: Indus 11, Persia 19, and the two Spasial programmes, which carry no region, on the full shelf only. Each card is the poster at its own shape, the title, the offer line the site builds from the film's record (*Rent $N · 48 hours to finish* where the record carries a rent, else *Institutional licence · by inquiry on the film's page* where it carries a licence, else nothing; since the owner took the films off sale on 2026-10-05 no film carries a rent, so 24 show the licence line and 8 show none), and runtime, languages and country where the record has them. A film opens on its public sixty-second preview from Cloudflare Stream; a preview that ends stops there. *Watch the full film* asks the `vod-token` function with the viewer's session, as the site does, and plays the token it mints; a refusal is shown in the site's own words, with a code for the film's own page (`/film/<handle>`), where a film is rented or licensed. `vod.json` is in `LAUNCH_RESTRICTED` in `_worker.js`, before launch and after it, so the films appear only once the preview password has been entered on the Transmission page. Without it the site's receiver hides them too.

**Assets.** The pigeon master GIF is a byte-identical copy of the website's. The channel change is one of five flights of the same pigeon over the skin's own colour, generated in Higgsfield and rendered as HEVC with alpha by `scripts/flights/` (see DESIGN.md, Motion). The old sound fades out and the new one in. The pigeon is used only where the owner's ruling of 2026-10-04 allows it: waiting states and changeovers.
**The dancer.** The website's dancer, ported from `kj-scope.js`, dances full screen over the ground to receiver radio and to Khajistan Transmission's sound-only programmes, all of channel 2 included, when what is playing carries a beat. He reads the real signal and is never shown on a recitation channel, over a picture, on an HLS carrier or with Reduce Motion on. A live radio mount is played by the app itself so its samples can be read. The rules are in [`DESIGN.md`](DESIGN.md) under The dancer.

**Subtitles and live captions.** One caption view draws all three, as the site's `kj-captions.css` draws its plate: semibold type at 2.7% of the frame, centred, one opaque plate in the skin's caption colours (black on yellow by day, yellow on `#002800` in grove and on `#6E003F` in smut). Each line is laid out on its own direction, so Urdu, Persian and Arabic read right to left. It sits above the strip or the film's panel while that is up and drops when it hides.

- *Khajistan Transmission*: a programme's `subtitle_url` (WebVTT), read through the site's gate as the schedule is, timed to the programme's file, on by default as `video.html` has it.
- *The Screening Room*: the tracks the film's HLS manifest announces, one per language, labelled from `subtitle_languages`, starting on the remembered choice, then the device's language, then English, else none (the receiver's `desiredSubtitle()`). A Subtitles button in the panel cycles them and Off.
- *Live captions on receiver television, radio and cameras*: `kj-captions-live.js` on the television. A signed-in, confirmed account; info@ and saad@ uncapped, everyone else ten minutes once, which `request-captions` enforces and the app only reports, in the site's words. Start, a heartbeat inside the 90-second lease, stop on leaving; lines arrive on the realtime subscription to `live_caption_wire` with the site's thirty-second REST read as recovery, English only, and are placed on the media clock with the picture held back. Khajistan's own channels, the mixes and the films never ask. Rows the site places by HLS fragment number are placed by the clock here, because AVPlayer does not expose fragment numbers.
- *The control* is the last thing in the strip: right moves to it, left leaves it, Select turns it over. It becomes a button only when reached, so up and down still change channel; Play/Pause and Select on the picture keep their jobs.

## What it does not carry

- **Pics/Vids search, the account and hashtag lists, Shuffle and the makers.** Search needs a keyboard, and the lists run to 81 accounts and 300 hashtags. Make a GIF, Make an emoji, Make a sticker and Save to the Wall are browser tools with nowhere to go on a television.
- **Buying a film in the app.** The Screening Room's films are listed and play here (above), but renting, buying and licensing happen on the film's own web page, which the app offers as a code. Apple's in-app-purchase rules for that are the open question in INTENT §6 and `STORE.md`.
- **From the site's captions menu:** the spoken-language picker, "Not this language?" (a vote is a write), "How accurate?" and "Get an hour of captions · $5". The hour is bought on the website.
- **Interstitials and idents.** The station-id audio, the ads and the sign-on ident stay on the website.
- **The rainbow TV bug.** It is not used on the live site and has no ruling for a new surface.
- **Open Sans.** The system font is used.
- **Magic-link sign-in.** The Supabase magic-link email template carries no `{{ .Token }}` code, so a television cannot complete it. Adding that token to the template is a one-line change that would enable "email me a code".

## Source and publish doors

The source is `tvos/` on branch `app/tvos-20261004` of the private `khajistan/khajistan-archive` repository. The local worktree is `/Users/home/CZURImages/filmart/.worktrees/tvos-app`.

Both publish doors leave `tvos/` out of the website. `.gitattributes` marks it `export-ignore`, which covers the `git archive` export that `deploy.sh` publishes, and the rsync in `.github/workflows/deploy-pages.yml` carries `--exclude '/tvos/'`. The app ships nothing to the website.

The INTENT sections cited here are in `INTENT.md` at the filmart root, outside this repository.

## Build and run

Building needs full Xcode 26 or newer with the tvOS simulator runtime. The Command Line Tools alone cannot build the app.

1. Open `tvos/KhajistanTV.xcodeproj` in Xcode.
2. Choose the **KhajistanTV** scheme and an Apple TV simulator.
3. Run with **⌘R**. The simulator needs no paid signing team.
4. Run the UI tests with **⌘U**.

The command-line equivalent, from the repository root:

```sh
xcrun simctl list devices available | grep 'Apple TV'
xcodebuild test -project tvos/KhajistanTV.xcodeproj -scheme KhajistanTV \
  -configuration Debug -destination 'platform=tvOS Simulator,id=<UDID from the list>' \
  -derivedDataPath tvos/.ci/DerivedData CODE_SIGNING_ALLOWED=NO
```

`xcodebuild build` with `-destination 'generic/platform=tvOS Simulator'` builds without running the tests.

### Core tests

```sh
sh tvos/scripts/test-core.sh
```

The script compiles the Foundation-only core and runs its checks:

- The Swift station clock agrees with the website's `kj-station-clock.js` on roughly 500 instants, taken from a fixture that Node generates (`tvos/scripts/station-clock-fixture.mjs`).
- The mixes register decodes and every mix in it plays; the refusals (hidden, http, localhost, private ranges) and the clock format have negative cases.
- The Pics/Vids URL builders agree with the site's `kj-media.js` on 44 rows, 36 of them real rows of the view, taken from a fixture that Node generates (`tvos/scripts/pnv-media-fixture.mjs`).
- The models decode the real feed files.
- The carrier and auth requests have the expected shapes.
- A skin choice resolves: Automatic follows the hour, Day, Grove and Smut hold at every hour, and an unknown stored value is Automatic.
- What is up next walks the schedule across midnight and stops where the month's grid ends, and the countdown to a slot's end is nil once the slot is over.
- The WebVTT reader takes the site's seven prepared files cue for cue and skips malformed timing; the caption plate matches `kj-captions.css`; live-caption eligibility, the server's refusals in the site's words, the request shapes, the English gate, the 42-character blocks, the clock and the realtime frames each have negative cases.

UI tests that need the schedule run without the preview password: a DEBUG build takes `-kjschedulefile <path>` and reads the month from the checkout's `data/khajistan-tv/`, and opens the Transmission player with no account and no picture. `-kjskin` sets the skin, `-kjhandoverlead` stretches the up-next notice's lead and `-kjsubtitlefile <path>` gives whatever is on air that WebVTT file. None of these exist in a Release build.

### Typecheck without Xcode

```sh
sh tvos/scripts/typecheck-catalyst.sh
```

The script typechecks the SwiftUI layer as Mac Catalyst against the UIKit and SwiftUI interfaces in the Command Line Tools SDK, which catches most compile errors before a CI run. It does not build for tvOS. An API that exists on iOS but not on tvOS passes it, and the UI tests are not checked. The script's header lists its two stand-ins.

### Generated files

After adding or removing Swift files, regenerate the Xcode project:

```sh
python3 tvos/scripts/generate-project.py
```

Redraw the app icon from the pigeon mark:

```sh
swift tvos/scripts/make-brand-assets.swift \
  tvos/KhajistanTV/Resources/Assets.xcassets/Pigeon.imageset/pigeon.png \
  tvos/KhajistanTV/Resources/Assets.xcassets
```

The app icon is a two-layer stack: the pigeon on a transparent front layer over a solid house-yellow back layer, at 400×240 (with a 2x) and at the 1280×768 App Store size.

Redraw the two static top shelf images, 1920×720 and 2320×720 (each with a 2x), with the extension's own drawing code; `--slides <dir>` draws the carousel slides from this checkout's data files in all three skins, for review:

```sh
sh tvos/scripts/make-top-shelf.sh
sh tvos/scripts/make-top-shelf.sh --slides /tmp/slides
```

## CI

The **tvOS app** workflow (`.github/workflows/tvos.yml`) runs on a GitHub macOS runner (`macos-26`). It starts on pushes to `main` and `app/tvos-*` and on pull requests that touch `tvos/`, and it can be started by hand. It runs the core tests, boots an Apple TV simulator, builds the app, runs the UI tests, and uploads the `khajistan-tvos-simulator` artifact for 14 days: screenshots exported from the test results, the xcodebuild log, the test result bundle and the unsigned simulator app.

The workflow holds no signing secrets and never deploys the website. A simulator app cannot be installed on a physical Apple TV or uploaded to App Store Connect.

This Mac has no Xcode, so the app is checked here in two ways before CI. `sh tvos/scripts/test-core.sh` runs the core. `sh tvos/scripts/typecheck-catalyst.sh` typechecks the SwiftUI layer as Mac Catalyst against the real UIKit and SwiftUI interfaces in the Command Line Tools SDK, with stand-ins only for `@State` (a macro whose plugin ships with Xcode) and the tvOS-only remote and focus modifiers listed in the script's header; a planted wrong member and a planted missing unwrap were both reported. APIs that exist on iOS but not on tvOS were checked for by name. Neither check builds for tvOS. The first build passed on 2026-10-05, in run 37310699348: Xcode 26.6, an Apple TV 4K (3rd generation) simulator on tvOS 26.5, three UI tests, and no compiler warnings from the app's sources. Its screenshots show the region list, the Indus channel grid, ABN Urdu playing with its attribution line, the Khajistan TV preview-password screen and the Account tab.

## Cost plan (INTENT §6)

- **Apple Developer Program:** US$99 a year. One membership covers iOS and tvOS. It is needed for a physical Apple TV and for the App Store, and is not needed for the simulator or this CI.
- **Xcode:** free. About 12 GB, plus about 4 GB for the tvOS simulator runtime. This Mac had 80 GB free on 2026-10-05.
- **In-app purchase:** none in v1, because broadcast is free (INTENT §5), so Apple's commission does not arise. If the Screening Room ever comes to the television, Apple requires its in-app purchase for digital content, at 15% under the Small Business Program (under US$1M a year) or 30% above. This app does not answer that question.
- **App Review:** Apple says most submissions are reviewed within 24 hours. Allow a few days per cycle. tvOS submissions need the layered icon, the top shelf images, a privacy policy URL and an age rating.
- **CI minutes:** the archive repository is private, so a macOS runner minute counts as 10 included minutes. The repository belongs to the user account `khajistan`; GitHub Free includes 2,000 minutes a month and Pro 3,000, and the CLI token here cannot read which plan the account is on. The iOS workflow's passing run on 2026-09-14 took 8 minutes, which is 80 included minutes, so the Free allowance covers about 25 runs a month across both apps. The default spending limit is US$0, so an exhausted allowance stops runs and bills nothing.
- **Hosting:** streams come from the broadcasters' own servers and Khajistan TV's existing carriers through tv-play, so there is no new hosting line.
- **Not costed here:** the iOS/Android plan of INTENT §6 (push, offline reading, subscriptions) is a different app.

## Owner follow-ups

- Install Xcode on this Mac to run the app in the Apple TV simulator.
- Join the Apple Developer Program when the app should go on a physical Apple TV.
- Add `{{ .Token }}` to the Supabase magic-link email template to allow sign-in by emailed code.
- At launch, the launch switch makes the schedule public and the preview-password step disappears.
