# Khajistan for Apple TV

Native SwiftUI application for the Khajistan Receiver and Khajistan Transmission, targeting tvOS 17 and later. Open **tvos/KhajistanTV.xcodeproj** in Xcode 26 or newer. The app has no third-party dependencies and uses no keys beyond the public Supabase anon key.

It is drawn in the house style measured from the website, recorded in [`DESIGN.md`](DESIGN.md): the yellow ground and green bands of the day skin, grove at night and smut at dawn and dusk, the system font at the website's weights, and focus drawn as the website's hover, a green plate with yellow text.

## What v1 carries

**The chrome.** The animated pigeon and KHAJISTAN head every screen, with RECEIVER, TRANSMISSION and ACCOUNT beside them. There is no system tab bar.

**The Receiver.** The front is the region map, drawn from the website's own geometry and colour rules, with the four live figures and the "Beyond the atlas" switch beside it. A strip of the regions with channels runs under the map, west to east, and the remote walks it; the focused region is outlined on the map and carries its plate with the native name and live count. The switch adds the Islamicate extensions, including the two Indian doors the website keeps behind it. A region opens on its figures and a grid of television, radio and cameras. The lists come from the public files the website's receiver reads: the receiver index, the per-region shards, the denylist, and the off-air and health feeds. Each stream is resolved through `/api/frequency` at tune time and played by AVPlayer, under the status band (KHAJISTAN RECEIVER, BROADCASTING FROM …). The grooming pigeon stands in for CONNECTING… while a signal tunes, and the wing wipe plays at a channel change.

**Khajistan Transmission.** A station page shows both channels and what each is carrying now. Channel 1 and Channel 2 are tuned by the station clock, which runs on Pakistan Standard Time, the same clock as the website. Once per launch the player signs on with the wing and the ident, as the website does.

- Tuning joins the programme on air at the point it has reached.
- A handover starts the next programme inside the slot's roster.
- A channel with nothing on shows an off-air state that names when the channel returns.
- The status band carries the slot and what is up next; the panel carries the show's line, kind, origin, and the custodian and transfer lines.
- Playback needs a free account, signed in with email and password. `tv-play` refuses anonymous requests (owner ruling 2026-09-09, recorded in the function's source). INTENT §5 still says Khajistan TV is open with no account; the server decides. Accounts made on the website with a password sign in here. An account that has only ever signed in through emailed links has no password, and no public page on the website sets one.
- Until launch the schedule sits behind the site's preview password, which the app asks for.

**Assets.** The pigeon master GIF is a byte-identical copy of the website's. The channel change uses one pigeon, flying, over the skin's own colour: two HEVC-with-alpha flights rendered by `scripts/make-pigeon-flight.py` from the Higgsfield masters. The old sound fades out and the new one in. The pigeon is used only where the owner's ruling of 2026-10-04 allows it: waiting states and changeovers.

## What it does not carry

- **The Screening Room.** Its films are paid and gated by entitlement. Apple's in-app-purchase rules for it are the open question in INTENT §6.
- **Subtitles.** `subtitle_url` is not loaded.
- **Interstitials and idents.** The station-id audio, the ads and the sign-on ident stay on the website.
- **The rainbow TV bug.** It is not used on the live site and has no ruling for a new surface.
- **A Top Shelf extension.** The brand assets carry the two static top shelf images only.
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
- The models decode the real feed files.
- The carrier and auth requests have the expected shapes.

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

Redraw the app icon and top shelf images from the pigeon mark:

```sh
swift tvos/scripts/make-brand-assets.swift \
  tvos/KhajistanTV/Resources/Assets.xcassets/Pigeon.imageset/pigeon.png \
  tvos/KhajistanTV/Resources/Assets.xcassets
```

The app icon is a two-layer stack: the pigeon on a transparent front layer over a solid house-yellow back layer, at 400×240 (with a 2x) and at the 1280×768 App Store size. The two top shelf images, 1920×720 and 2320×720 (each with a 2x), are the same pigeon on the same yellow.

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
