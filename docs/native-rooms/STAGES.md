# Stage ledger

Worktree `/Users/home/CZURImages/khajistan-apps-native-rooms`, branch `codex/khajistan-native-rooms`.
Pushed as draft PR 8; nothing uploaded. Update this file at the end of every stage.

| Stage | State | Evidence |
|---|---|---|
| 0 Baseline | complete | PR 1 merged into main locally; Mac Catalyst build fixed (StaticNoise); TV parity tests now read `KJ_ARCHIVE` |
| 1 Shell and routing | complete | five doors; Rooms stack (phone) and sidebar (iPad/Mac); `-kjroom`; iPhone UI suite green |
| 2 Adapters and persistence | complete | `SiteFeed` (locked/failed/ready), `Resume` places in `library.json` (old files decode), `BagStore` |
| 3 Reading Room | complete on phone/Mac; TV unchanged (already native) | UI test: free title read p1→p2, Continue offered, members' title stops at the preview with no page behind it; RTL direction parity-tested |
| 4 Screening Room | complete on phone/Mac; TV gains a full-room view under Rooms | catalogue verified against local `vod.json` (32 films); full film needs an account the server entitles — not verifiable without one |
| 5 Receiver / Transmission / radio | preserved, not reworked | existing receiver UI tests pass unchanged |
| 6 Pics/Vids | preserved; moved into Rooms; store-build exclusion re-tested | `testPicsVidsChatAndWallAreLeftOutOfStoreBuildsOnly` (own-build half run here) |
| 7 Bazaar | complete on phone/Mac; TV browse + "buy on khajistan.com" | 1,335 shelf placements match the site's own code; live Storefront variants; cart → checkout host khajistan.com (no order placed) |
| 8 Madrassa | complete on phone/Mac; TV browse + full reading | 15 entries from the page itself; 13 essays reach the screen whole (word-count check); dictionary 829 / 151 set apart |
| 9 Databases | complete on phone/Mac; TV compact browse + record | 11 files decode at the site's stated counts; censor scans open the native reader |
| 10 Library / Search | complete on phone/Mac | Search answers by room and names rooms it could not search; Library lists places on this device and account saves |
| 11 Mac | partial | builds; sidebar + room layout captured from the running app; Cmd-1…5, Cmd-F, Cmd-[ and Esc wired; keyboard/pointer not driven |
| 12 Apple TV | complete for the new rooms | Rooms door; remote test passes on live register data |
| 13 Release candidate | partial | refute pass run and its ten findings fixed; HANDOFF.md written; no upload (owner-only) |
| Mobbin pieces | complete on phone/Mac | watchlist, Pics/Vids saves + collections (read only), Madrassa contents + save, database sort, reader rail, now-playing bar; second refute pass, its findings fixed; iPad found the RR catalogue load cancelled by a rebuilt screen — the store now owns its load |
| Reference-app layouts | built on iPhone/iPad/Mac | every native room restyled to its reference app (DECISIONS 17); CC key; see TEST_MATRIX for the runs |
| Reference-app layouts on Apple TV | complete (2026-10-27, resumed on the owner's word) | Rooms door as tiles + Up Next; Screening Room with Up Next, watchlist and a film page (one Play/Resume); Bazaar showcase (price first, option chips, buy-on-khajistan.com); Madrassa in serif with pictures; databases as a Notion table and property page; Receiver guide (strip's Guide control, LIVE row) and radio Now Playing. `RoomsLayoutUITests` and `ReceiverGuideUITests` pass in Day, Grove and Smut; Fable refute pass run, its findings fixed or dismissed in the commit. `-kjtab reading` launch checked: it opens the Reading Room (the earlier home-screen landing did not recur) |

| Gaps closed (2026-10-27, owner: "resolve the gaps") | complete | TV Reading Room: title page with the cover large and one Read/Continue, a Continue shelf from this device's places (`kj.readingPlaces`); Persian-handle films saved as hex refs; Pics/Vids collections created and filled from the iPhone viewer. Fable advised on both save gaps; no migration |
| TV index search (2026-10-28) | complete | every TV database table has a search bar (owner: "the indexes should have a search bar for people to search metadata and name of song"); the phone already had one. `testIndexSearchFindsASongByTitleAndArtist` passes in three skins |
| Sign in on the TV from a phone | live 2026-10-27 (table, function, /activate); first real approval is the owner's | TV QR + code + polling, iPhone Sign in on a TV (scan or type), `/activate` page, `tv-sign-in` function and migration on `apps/tv-sign-in` branches; Fable security pass, six fixes made; QR decoded from the screenshots in all three skins |

| Receiver choices on the phone (2026-10-28) | built; background sound not yet heard on a device | Keep playing on other pages (small player also in the reader) and Play with the app closed (DECISIONS 24). `testNowPlayingBarStaysOverTheReader`, `testLeavingTheReceiverStopsItWhenKeepPlayingIsOff` and `testNowPlayingBarFollowsTheReceiverAcrossDoors` pass on the iPhone 17 simulator; tvOS builds |

| Apple TV load speed (2026-10-27) | complete; proxy live | Cause measured on the owner's TV: the home network drops connections to the project host. Site `/sb/` proxy live (archive b96a2b2f3, deployed by the sign-in session); apps route through it and fail fast (DECISIONS 22); the Reading Room opens from the shelf kept on the device (DECISIONS 23). Owner's TV, Release: before, 45.7 s then failure; now 1.36–1.44 s to the shelf and 1.65–1.73 s to the first cover, 2.9 s on the first open after an install; Pics/Vids opens |

| Mobbin gaps on Apple TV (2026-10-28) | complete | Every gap measured on build 3 built on the TV, adapted to the remote: Rooms door with Chat tile, Continue (covers, or names kept on the device) and Opened lately (`kj.openedLately`); Reading Room search and "Name ›" whole-shelf grid (zoom was already 6x); film Website as a QR; Madrassa Save beside the date and Contents; databases Filter and Sort panels with self-removing pills; Sonos-style radio bar under every screen; Bazaar bag, steppers and Checkout as a QR of the shop's cart (owner: "Bag + QR checkout"; `BagStore` now one file for both apps); Pics/Vids Save, Collection, Saved and collection shelves, region shelves kept (owner: "Saves, keep shelves"). DECISIONS 25. Codes and the bag draw in place: a third full-screen cover closed with Menu looped SwiftUI in Day under accessibility. Two review passes, findings fixed. TV UI: RoomsLayout (3 skins + index search), ReceiverGuide (3 skins), ReadingRoom, PicsVids, Rooms all pass on the final build |
| Picture-first room tiles (2026-10-28, owner: "picture first … like how apple tv has photos or images for section") | built; not yet in a TestFlight build | Real archive pictures, bundled (`Room*` imagesets, no download): iPhone Home grid and Rooms list rows, TV Rooms door as picture cards; descriptions shown whole (the "…" fixed). Screenshots in three skins on iPhone 18 Pro and Apple TV 4K simulators; refute pass run, its findings fixed |

## Resume here

Read `HANDOFF.md` first, then this file, `DECISIONS.md` and `git log --oneline -20`; rebuild with
the commands in `TEST_MATRIX.md`, and continue the first stage not marked complete.
