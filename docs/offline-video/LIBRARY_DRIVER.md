# Local offline-library implementation — provider/device gates remain closed

This follow-on branch is `codex/offline-library-local`, based on the separately reviewed
`965f279` app candidate. It does not change the two prepared draft-PR commits. No branch has
been pushed, provider configured, sale activated or app released by this work.

## Implemented composition

- `OfflineFilmCatalogue`: AES-GCM authenticated index bound to account/device, private Library
  storage, no signed manifests/tokens/key blobs in the index. The encryption key and device
  identity live in a non-synchronizing, device-only Keychain item. Atomic writes apply file
  protection before replacement. Corruption and unsafe paths fail closed.
- Per-index locks serialize different catalogue objects in the app process. A shared session
  fence blocks old reads/writes after logout. Operation and revision identifiers reject reused
  IDs, stale completions and obsolete updates. No extension/other process may write this index.
- `OfflineFilmLibrary`: authenticated authorization contract, suspended task binding before
  start, pause/resume/cancel, durable removal tombstones, retryable cleanup and restoration.
  Ready requires a protected, offline-playable package and a usable device key. Late destinations,
  failed task-binding writes, interrupted inspection and missing final callbacks are handled.
- Reconnection uses an injected entitlement service with monotonic backoff and at most six
  starts per hour, including foreground requests and network flaps. Every explicit denial stops in-process
  access immediately; an independent Keychain denial record survives failed catalogue writes.
  Cleanup attempts continue for all denied titles. A transient transport failure does not extend
  the existing license or erase purchase ownership. Simultaneous failure of all durable storage
  remains a device fault requiring recovery; no unconditional persistence guarantee is claimed.
- `OfflineHLSDownloadDriver`: actual AVAssetDownloadURLSession background tasks; HTTPS manifests
  only on an explicit approved-host set, protected-content preflight before task creation,
  persistent FPS key before resume, system-managed packages never moved. Background delegate
  events are buffered during restoration; completion notification waits for buffered replay.
  Local playback selects downloaded audio/subtitle options and uses a replay-only key service.
- `OfflineFilmRuntime`: single installed account runtime, local Keychain identity, account-stop
  hook, reconnection observer, stable background-session routing and private AVPlayer. Playback
  stops on account change, known revocation, unreadable catalogue, key failure, clock rollback or
  advisory expiry; FairPlay must independently enforce authoritative license policy.
- Conditional controls: Save in app on a film, Offline films under You, private play/pause/resume/
  remove. No share/export/Quick Look or raw URL. External playback is disabled on the offline
  player. Controls are absent because `AppModel.offlineFilms` defaults to nil.

## Provisioning boundary

The app does **not** install a provider by default. An approved authenticated launch bootstrap
must construct exactly one `OfflineFilmRuntime` with a real offline authorization service, FPS
license service, public application certificate and approved media hosts, assign it to the model,
and await `restore()`. A cold background launch must perform this bootstrap in time to route the
matching URLSession callback; this is not verified by the existing nil-default path. Do not enable
controls by substituting `vod-token`, a signed streaming URL, MP4 export or a mock grant.

The Keychain material is WhenUnlockedThisDeviceOnly. Temporarily inaccessible items defer
verification until protected data becomes available. Locked-device relaunch/first-unlock behavior,
background completion and simulator-versus-device FPS differences need physical-device tests.
The adapter checks system package/cache properties; real provider package layout and downloaded
language selections also need device verification. Mac Catalyst construction additionally requires
an explicit `catalystValidated` value; a successful Catalyst build alone does not justify it.

Renewal/key rotation, server first-play reconciliation, device registration/limits, licence-server
authorization, DRM certificate provisioning and the final production bootstrap require the actual
provider contract. These are still open. Prices, SKUs, reconnection period and customer promises
remain unchanged. An unsigned collector agreement is not title clearance.

## Local evidence and limits

The shared package has 62 passing tests, including 9 catalogue, 18 controlled library lifecycle
and 3 bounded reconciliation policy tests. The transport fixtures make no network request and cannot create a real media asset or FPS
key. They cover account changes, removal during inspection/verification, pause before task creation,
late completion, cleanup retry, storage substitution, task-binding write failure, revoked-key
restart and batch revocation with a failing first cleanup. Actual AuthStore lifecycle coverage is
separate. Native builds establish SDK integration only.

`OfflineLibraryUITests` exercises real row controls with DEBUG-only synthetic rows, including
Day/Grove/Smut and accessibility text sizing. It does not exercise licensed playback. The fixture
cannot construct a runtime, key request or download; it is absent from Release builds. Device
VoiceOver, real download progress/background execution and owner TestFlight review remain open.

Independent review findings were fixed iteratively: shared locking, operation identity, account
fencing, atomic protection, failed/late cleanup, active playback on revocation, task binding,
background-event ordering, pause during inspection, batched denial and persistent denial after
an index failure, missed reconnects and temporarily locked Keychain access. The final review found no further concrete defect in that reviewed scope; it
did not certify FairPlay, provider integration, renewal or release readiness.

## Release gates (all ten required; no subjective score)

| Gate | Evidence required beyond local implementation |
| --- | --- |
| 1. Encrypted delivery | Provider-confirmed persistent FPS; actual encrypted staging asset and KSM |
| 2. Account/device isolation | Real account switch, device binding, logout and delayed request tests |
| 3. Rental/purchase rights | 30-day start, full 48-hour playback, permanent account ownership verified end-to-end |
| 4. Download lifecycle | Device offline launch, lock/relaunch, interruption, repeated actions and storage pressure |
| 5. Revocation/renewal | Refund/revocation after reconnect, rotation and bounded offline validity |
| 6. Private playback | No raw export, shared destination or external-playback path; actual FPS enforcement |
| 7. Platform coverage | iPhone/iPad physical devices; Catalyst separately; browser/tvOS streaming-only |
| 8. Accessibility | Three skins/text sizes plus actual VoiceOver and device input review |
| 9. Quality gates | Final-head aggregates, independent review, candidate CI and owner TestFlight acceptance |
| 10. Rights/product/release | Executed/title-specific legal basis, product decisions and explicit release approval |

Local tests/builds cannot mark the blocked provider/device/legal gates passed. The protected offline
product remains unreleased. Reading Room's encrypted performance cache remains distinct from a
licensed offline document library, whose server entitlement/package contract is still missing.
