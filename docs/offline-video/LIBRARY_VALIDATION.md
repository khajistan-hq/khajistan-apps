# Offline library follow-on — local validation

All results below are local, at the final source tree of `codex/offline-library-local`.
No production provider, paid media session, remote publication or release was used.

| Check | Result | Local evidence |
| --- | --- | --- |
| Swift package | 62 passed | `/tmp/kj-offline-library-package-final2.log` |
| Actual AuthStore synthetic lifecycle | 12 passed | `/tmp/kj-offline-library-auth-final.log` |
| iOS own core | 16 passed | `/tmp/kj-offline-library-ios-core-final.log` |
| iOS shared core | 74 passed, 1 fixture skip | same log |
| tvOS core | 156 passed, 2 fixture skips | `/tmp/kj-offline-library-tv-core-final.log` |
| iOS Store Release, unsigned | passed | `/tmp/kj-offline-library-ios-head.log` |
| tvOS Store Release, unsigned | passed | `/tmp/kj-offline-library-tvos-final.log` |
| Mac Catalyst Store Release, unsigned | passed | `/tmp/kj-offline-library-catalyst-head.log` |
| iPhone row controls, three actual skins and largest accessibility text | passed | `/tmp/kj-offline-library-phone-isolated.xcresult` |
| iPad row controls, portrait/landscape, three skins and largest accessibility text | passed | `/tmp/kj-offline-library-ipad-isolated.xcresult` |
| Independent read-only source review | findings fixed; no further concrete defect in reviewed scope | `LIBRARY_DRIVER.md` review account |
| Whitespace/diff checks | passed | `git diff --cached --check` |

The core skips are the absent Anatolia-camera fixture and, on TV, the optional full Reading Room
grouping feed. The Bazaar fixture was supplied on the final TV run. Swift macro compilation first
failed under the filesystem sandbox; the same scripts passed with the installed compiler allowed
to launch its macro process. This was an environment restriction, not a passing test result.

All six final screenshots were inspected. They are in
`/tmp/kj-offline-library-phone-isolated-shots` and
`/tmp/kj-offline-library-ipad-isolated-shots`. The tablet landscape image is a full-screen capture
after an asserted landscape frame. Initial runs using invalid skin aliases and an app-only image
during rotation were corrected and superseded. The DEBUG fixture skips ordinary browser warm-up,
storefront observation and backend reachability; it cannot create a media task, runtime or key.

Not run/blocked: actual encrypted media and FPS license issuance; physical iPhone/iPad playback,
protected-data callbacks and cold background relaunch; Catalyst runtime acceptance; renewal and
rotation; server first-play reconciliation; real refunds/payments; real-device VoiceOver; owner
TestFlight; candidate CI; title-specific legal and product approval. No automated row test is
presented as proof of these stages. See the ten release gates in `LIBRARY_DRIVER.md`.
