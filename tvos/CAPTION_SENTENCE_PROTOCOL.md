# Native sentence captions

The integrated candidate retains the complete deployed PR11 native timing/reconnect repair (`60c002a1ee5be040fb3200a27a618d917fcfc3ba`) on main base `7cd114fece0abb980d749e35ccbc2d611c3a5518`.

Both apps accept additive sentence metadata on legacy/enforced wire rows. Previews are text-free in English mode. Terminal source waits for the worker's exact-row English UPDATE inside the existing eight-second deadline; sentence rows never start paid client translation. Sentence identity/status survives paging and queue compaction. Unfinished speech and potentially incomplete English are labelled without adding punctuation. Existing film/programme captions keep their default rendering.

The apps wait for explicit positive legacy/enforced billing admission before opening the wire. Atomic and unknown modes stop visibly; full atomic native networking is outside this implementation. Signed-out/new-account callbacks stop captions synchronously, and stale login/refresh results cannot replace newer authentication. Both wall and monotonic lease deadlines guard reception and paint, in addition to the existing timer.

A recognized missing-column response can fall back to older schema projection. Its captured projection remains bound to the request even if a concurrent Realtime event upgrades capability. Rows from metadata-omitting requests cannot trigger paid fallback. A strict same-source UPDATE can promote an unexpired pending row to the new metadata while preserving queue position and deadline. Every new session reprobes; malformed REST rows are skipped individually. Preview notices preserve stronger warnings, change to unfinished after nine seconds, and expire with the bounded ledger.

Validation uses the actual services with synthetic socket/HTTP/player boundaries and the real AuthStore with synthetic HTTP/keychain boundaries. The shared iOS caption core remains a symlink to tvOS. Run:

```sh
sh tvos/scripts/test-caption-session.sh
sh tvos/scripts/test-auth-session.sh
sh tvos/scripts/test-core.sh
sh ios/scripts/test-core.sh
```

The two platform workflows run the corresponding service and auth tests. Local tvOS Simulator and Mac Catalyst builds are unsigned; they do not install, publish or establish real-device acoustic accuracy. Live testing and spending authorization are separate release gates. Rollback should first stop producing sentence revisions; retain compatible readers while existing rows drain. Reverting this new commit must preserve all five PR11 native repair commits.
