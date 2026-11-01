# Reading Room package validation

Candidate: `codex/reading-offline-package-local`, based on `4fbb230`.

Final evidence is for the code after both independent-review crash-recovery fixes.
All tests use local synthetic data or existing local regression fixtures. No paid probes,
production downloads, server mutations or credential requests were run.

| Check | Result / local evidence |
|---|---|
| Full Swift package suite | **76 pass**, including 14 new package-storage tests. `/tmp/rr-offline-package-tests.log` |
| Actual AuthStore synthetic lifecycle | **12 pass**; `/tmp/rr-offline-auth-final.log` |
| iOS own/shared core fixtures | **16 own + 74 shared pass**, 1 missing-fixture skip; `/tmp/rr-offline-ios-core-final.log` |
| tvOS core fixtures | **156 pass**, 2 missing-fixture skips; `/tmp/rr-offline-tv-core-final.log` |
| Unsigned iOS Store build | **Pass**; `/tmp/rr-offline-ios-build-final.log` |
| Unsigned tvOS Store build | **Pass**; `/tmp/rr-offline-tv-build-final.log` |
| Unsigned Catalyst Store build | **Pass**; `/tmp/rr-offline-mac-build-final.log` |
| Independent second-model source review | Two crash recovery findings fixed and rechecked; no further concrete finding in scoped review. Reviewer did not run tests. |
| UI, real licence/provider, physical devices, CI, TestFlight | **Unrun for this branch.** No screens or runtime entry points were added. The feature cannot be activated without the gates in `READING_OFFLINE_PACKAGE.md`. |

The shared core skip is the absent Anatolia camera fixture in both apps. The second tvOS
skip is the optional full Reading Room feed/grouping fixture. AppIntents metadata extraction
warnings in the tvOS/Catalyst builds report that the target has no AppIntents dependency.
All final commands exited successfully; no new test failures remain.

Reproduce the full package suite:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/rr-offline-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/rr-offline-module-cache \
swift test --disable-sandbox --scratch-path /tmp/rr-offline-package-tests \
  --cache-path /tmp/rr-offline-swift-cache --package-path ios
```

The first fixture run exposed Foundation's `/private/var` versus standardized `/var`
representation in the file enumerator; normalizing before containment checks fixed it.
Two preliminary core compiles overlapped the review edits and correctly failed with
“input file was modified during the build”; their output is not counted as final evidence.
No compile inputs changed during the final checks. Project files were regenerated using
both repository scripts. No dependency, entitlement or Info.plist changes were needed.
