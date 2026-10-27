# Stage ledger

Worktree `/Users/home/CZURImages/khajistan-apps-native-rooms`, branch `codex/khajistan-native-rooms`.
Nothing pushed, nothing uploaded. Update this file at the end of every stage.

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
| 11 Mac | builds; layouts are the iPad ones with keyboard commands | not yet exercised by hand with keyboard and pointer |
| 12 Apple TV | Rooms door added; remote UI test written | see TEST_MATRIX.md |
| 13 Release candidate | not started | — |

## Resume here

Read this file, `DECISIONS.md` and `git log --oneline -20`, rebuild with the commands in
`TEST_MATRIX.md`, and continue the first stage not marked complete.
