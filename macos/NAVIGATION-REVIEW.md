# Website navigation in the Mac app

Prepared November 1, 2026 on `codex/macos-website-navigation-20261101` from
`app/simple-nav` at `cc429a9` (distributed build 10 source `106914e` plus two
UI-test corrections). The separate local preview has been tested; no installed app or distribution build was replaced.
It is separate from machinery PR #104.

## What changes

The Mac Khajistan menu now offers every website section directly, while keeping
Command-1 through Command-5 and Command-F. Rooms on the Mac follows the website's
section grouping. Existing native Reading Room, Madrassa, Screening Room,
Receiver, Pics/Vids, Chat, Bazaar and account destinations keep their native
screens. Menu navigation switches the single browser/Chat presentation when selecting a
destination, or closes it for a native destination or tab. Navigation commands are
disabled while a native reader, player, sign-in/TV form or QuickLook preview is
presented; close the modal first. UUID-based ownership keeps nested modals from
unlocking one another.

Eleven missing routes open the existing in-app website browser:

| Section | Destination | Route |
| --- | --- | --- |
| Databases | Databases | `/databases.html` |
| Databases | Pakistani Music Database | `/pakistan-music-index.html` |
| Databases | National Broadcast Register | `/national-broadcasts.html` |
| Databases | Logos of the Middle World | `/logos.html` |
| Databases | Cinema of the Middle World | `/cinema/` |
| Databases | Television of the Middle World | `/television/` |
| Databases | Arabic Music Index | `/arabic-music-index.html` |
| Databases | Persian Music Index | `/persian-music-index.html` |
| Databases | Film Censor Certificates | `/censor-certificates.html` |
| Databases | American War Propaganda Leaflets | `/leaflets.html` |
| Life | Life / 4Corners | `/life` |

The website routes come from the production `scripts/kj-chrome.js` read at
23:39 UTC, November 1. The test fixture records the current menu and related About
routes. Retired legacy sitemap entries are not treated as visible navigation.
All eleven destination pages also exist in the current archive checkout.

## Access and platform behavior

The website browser now answers the archive's HTTP Basic preview challenge with
the preview password the user already entered in You. It answers only an initial
HTTPS Basic challenge on the two existing allowed archive hosts at port 443,
never a proxy or external host, and never persists the URL credential. Native
account tokens are not injected into web pages. Website account sign-in,
membership and page permissions remain enforced by the website.

Life enters through its existing `/life` page. The website requires account
sign-in and hands off to the separate `khajistan-life.pages.dev` game in the
system browser, following the app's existing external-origin policy. The game
has its own preview gate. No new cross-origin credential sharing is added.

The existing `KJ_APP_STORE` build restriction still excludes Pics/Vids, Chat and
Wall, including browser aliases. `StoreBuild.swift` records the owner's October 6
policy: unscreened Pics/Vids corpus, and moderation prerequisites for Chat/Wall.
Development builds include those existing rooms. Full release parity for those
three sections needs a separate decision and the moderation/distribution work;
this navigation change does not bypass that policy.

## Verification

- Core regression suite: 20 passed, including the live navigation snapshot,
  preview credential host/scheme/port/method/proxy/retry boundaries and regional
  selection after global Surf.
- Shared core suite: 74 passed, zero failed; one data-fixture check skipped because
  `data/open-frequencies/regions/anatolia-camera.json` is absent locally.
- Universal Mac Catalyst Debug build: passed (arm64 and x86_64). Local ad-hoc
  signing required clearing Finder metadata from the generated bundle; no source
  or installed-app metadata was changed. A separate preview identifier,
  `com.khajistan.archive.navigationpreview`, was built successfully.
- Both development and `KJ_APP_STORE` navigation policy checks passed: 30 and
  27 destinations respectively; the same three store exclusions remain.
- Independent source review: no remaining required findings after modal routing
  and command availability were corrected.
- Native UI walkthrough completed November 2 in the separate preview with
  `DEBUG KJ_NAVIGATION_FIXTURE`: signed out, autoplay off. The fixture registers
  its defaults before constructing the app model; normal builds omit it.
- All eleven new web destinations were selected through the Mac menu. Each
  displayed the existing password gate with the exact expected `next` path.
  Protected page content and the game were not entered; no credentials were used.
- Sign In rendered its empty form. All 34 navigation commands were disabled while
  it was open, and re-enabled when closed. The same command guard was verified
  while the free Baba Sharu reader was open in its loading state; page-image
  rendering was not asserted.
- Browser → Chat → native Reading Room and Chat → browser transitions passed.
  The public Reading Room title shelf loaded and remained selected after closing
  the browser. Native Search opened after the reader closed. No chat message,
  account change, paid caption probe or protected-content request was submitted.
- The walkthrough found a real Sign In crash: the sheet could not find AppModel
  in its presentation environment. SignInView and the modal guard now take the
  existing model explicitly, and the window root supplies it to descendants.
  The repaired sheet and transitions passed the same walkthrough.
- The isolated preview was quit after testing; the existing menu-bar helper
  remained running. No installed app bundle was replaced or modified; main-app
  process continuity was not verified. No TestFlight build was submitted or released.
- Shared iOS Simulator build after the sheet fix: passed.
- The focused account Sign In open/cancel UI regression passed in the first
  GitHub iOS run, alongside the earlier manual Mac check.

### Receiver issues found during CI

The initial iOS run at `b76f6ad` executed 32 UI cases: 30 passed and two existing
Receiver cases failed before the job reached its time limit. This was not a
timeout-only failure. The new Sign In case passed.

- A region tap while global Surf was already playing that region stepped the
  global pool, sometimes jumping from Maghreb to Indus. Region tuning now loads
  the chosen region's eligible catalogue and steps/wraps only within that list.
  It preserves the existing medium choice/fallback and rejects a late load after
  newer playback, Surf, region or stop intent. Explicit region selection also
  invalidates an older automatic-opening continuation. Global Surf is unchanged.
- The Off recording showed a successful stop: the idle device moved back into
  the scrolled catalogue, above the viewport. The test now reveals it before
  retaining its `Standing by` assertion and additionally checking an empty
  channel identity. It does not press Off again to mask a failure.
- The original map UI test is unchanged. Both failed cases passed on a new,
  isolated iPhone 17 simulator with iOS 27 (2/2, zero failures). GitHub uses iOS
  26, so its full run remains a separate check. The temporary simulator was shut
  down after testing; no physical device was used.
- The new pure regional-selection regressions passed. In the isolated checkout,
  app core was 20/20 and shared core was 64 passed, zero failed, 11 skipped because
  the archive data fixtures are absent. The earlier 74/1 shared result above used
  the local archive fixtures.
- The final regional fix compiled for both Mac Catalyst architectures. No repeat
  of the eleven password-gate walkthroughs was needed; that code is unchanged.
- CI retains all tests and now allows 45 minutes instead of 35, leaving room for
  the full suite and artifact export after a successful base run took 33m40s.
  The final draft PR records the completed CI outcome.

The initial preview-signing approval hold was resolved by explicit approval on
November 2. The approved retry succeeded. Generated bundles are signed in `/tmp`
to avoid Finder metadata reappearing in the Documents build directory.
