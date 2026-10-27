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
| Reference-app layouts on Apple TV | not started (owner said stop, 2026-10-27) | baseline only; the plan and a launch to check first are in HANDOFF.md |

## Resume here

Read `HANDOFF.md` first, then this file, `DECISIONS.md` and `git log --oneline -20`; rebuild with
the commands in `TEST_MATRIX.md`, and continue the first stage not marked complete.
