# Reading Room offline storage preparation

2026-10-31. Local branch `codex/reading-offline-package-local`, based on the separately
reviewed `codex/offline-library-local` commit `4fbb230`. No runtime is enabled, no source
assets changed, and no endpoint, credential, production setting or publication is involved.

## Assessment of the existing authority

`ReadingStore.page` obtains a viewer token, asks the page service and checks the account
generation and the returned `RRPagePermission` before returning pixels. `RRPageAnswer`
contains a signed image URL and TTL. Reuse lasts at most eight minutes, shortened for
shorter server TTLs. `RRProtectedPageCache` encrypts a bounded performance cache; neither
the cache nor the signed URL is an offline licence.

The reviewed local page-service source consults active subscriber and purchase-grant
rows, their expiry, scope and tier. It also checks page retirement/visibility, collection
rights holds and reading-window rules. It does not supply an authenticated offline
manifest, a device licence or an offline key lifecycle. This is a local source assessment,
not fresh deployment verification. Reusing the film grant would invent document access
terms and could lose these page-level restrictions, so that integration is blocked.

## Safe local work completed

`RROfflinePackageStore` prepares encrypted storage without inventing an authorization
policy. It has no network client, page-read/export API, licence issuer or caller in the
app. Its only consumers are controlled synthetic tests. It is shared between native
build targets for compilation, but enables no platform capability.

- Ordered page descriptors carry an opaque identity, byte count and SHA-256 digest.
  Issue/version and page identities are metadata, never filesystem paths.
- AES-GCM authenticates canonical structured context: account, device, package ID,
  operation, manifest digest and page ordinal. Each write uses a fresh nonce. Manifest
  encryption binds the account/device/package separately. No raw page, key or signed
  URL is persisted in a metadata record.
- The encrypted root manifest commits before any page directory is created. Each page
  commits atomically. Completion commits only after every ordered page authenticates
  and matches the expected bytes. Reopening checks the actual files; a stored complete
  flag cannot conceal missing or corrupt pages.
- Repeated requests resume the same ID/manifest. Completed versions are immutable;
  replacing a version uses a new package. Removal keeps its encrypted tombstone outside
  the page directory and deletes it last, so partial cleanup can resume after restart.
  Reusing an ID creates a new operation and rejects old callbacks and old cleanup.
- A shared per-directory transaction lock prevents lost concurrent updates within the
  app process. A shared account-generation fence blocks subsequent operations after
  invalidation. This does not remove existing bytes or revoke a server licence by itself.
- Paths reject symlink substitution. The root is excluded from backup. Atomic files use
  complete file protection on iOS/tvOS, applied before replacement. Callers must supply
  an app-private Library root and device-only key. No runtime key source is installed.
- Configurable engineering limits bound pages, each page, package bytes, metadata,
  filesystem entries and all partial/complete files beneath the supplied root. Defaults
  are 5,000 pages, 20 MiB/page, 500 MiB/package, 4 MiB metadata and 1 GiB/root. These are
  resource ceilings, not customer/device/entitlement policy. Writes include atomic
  replacement headroom and reserve room for a deletion marker. There is no silent
  eviction, automatic retry, prefetch, OCR or paid traffic. A device-wide multi-account
  budget remains a future runtime responsibility.

The film catalogue remains separate because its `.movpkg`/FairPlay keys and rental
activation state do not describe documents. The new store follows its encrypted-index,
operation-identity, atomic-write and account-fence patterns without changing it.

Encryption and caller-supplied hashes do not prove authenticity, ownership or legal
permission. This component cannot prevent replay of an older valid package. A future
verified grant/key authority must handle validity and rollback independently. No claim
of copyproof media or instantaneous revocation on a disconnected device is made.

## Independent review and fixtures

A separate model reviewed the concrete storage implementation. It found two crash-order
holes in the first draft: initial directory creation before its manifest, and recursive
removal potentially deleting the tombstone first. Both were fixed with the root manifest
ordering above and deterministic interruption tests. The recheck found no additional
concrete issue in this narrow scope. A suspected test-path issue was retracted because
its helper already resolves the new root manifest location. This is source review, not
provider, device, cryptographic certification or a review of the entire app.

The 14 new fixture tests cover restart/resume, missing pages, encrypted on-disk contents,
wrong account/device/key, metadata substitution, corrupt/truncated/swapped pages,
version/operation substitution, late callbacks, immutable completion, account fencing,
size/hash/ordinal/manifest bounds, aggregate storage and removal headroom, symlink
containment, concurrent store instances, corrupted manifests, entry ceilings, failed
initial commit and interrupted deletion at both recovery boundaries.

The final validation receipt is `READING_OFFLINE_VALIDATION.md`. Synthetic scan bytes are
created in temporary directories; these tests fetch no catalogue assets or live services.

## Exact blocked integration and release gates

| Gate | State / prerequisite |
|---|---|
| 1. Authenticated offline authority | **Blocked.** Backend/delivery owner must provide an approved account/device/issue/version-bound grant and a verifiable manifest with ordered pages, sizes and hashes. Existing signed image answers cannot stand in for this. No production endpoint is assumed or implemented. |
| 2. Rights and scope preservation | **Blocked.** Issuance/reconciliation must preserve page retirement, title rights, subscription/purchase scope, tier and window restrictions. Collector agreement execution and title-specific legal basis remain separate. No rights are granted by this branch. |
| 3. Offline terms | **Decision pending.** Eligible products, licence validity, reconnect period, device allowance and subscription expiry behavior must be approved. Permanent ownership must remain distinct from a renewable offline licence. No defaults are selected here. |
| 4. Encrypted package storage | **Local fixtures pass.** This component verifies integrity, crash recovery, containment, bounds and session fencing. Device Keychain, file protection, locked-device and backup behavior remain unverified in the actual runtime. |
| 5. Download/key delivery | **Blocked.** Approved asset packaging and key delivery/rotation/revocation contract, non-customer fixture licence and secure credentials setup where needed. No key material in chat. Actual transport, cancellation, network resume and logout key disposal are unimplemented. |
| 6. Reader/library integration | **Unimplemented, dependent on 1–5.** ReadingStore does not consume these packages. A verified permission must govern every decoded/visible page, expiry timer, foreground return and account switch. No offline save/read UI is exposed. |
| 7. Reconnection/payment lifecycle | **Unimplemented, dependent on authority.** Complete authoritative reconciliation, bounded retries, cancellation/refund/rights withdrawal, renewal and replay protection need fixture and service evidence. Offline instant revocation cannot be promised. |
| 8. Document/interaction quality | **Open.** Representative real scans, zoom, page map/order, RTL/spreads, OCR/search coverage, VoiceOver and physical iPhone/iPad review remain necessary. No extraction or new provider spend is started. Catalyst is a separate device/runtime gate; browser/tvOS capability is unchanged. |
| 9. Regression/review/acceptance | **Local storage review and build evidence recorded separately.** Full feature runtime/UI tests, current-head CI and owner TestFlight acceptance remain open. This branch has no changed screens to claim visually reviewed. |
| 10. Publication | **Pending authorization.** No push, merge, deploy, store submission, sale activation, domain/SEO change or release. The three earlier reviewed candidates are unchanged. |

Dependent licence/download/reader work stops here until the authority and policy inputs
exist. The local staging implementation is reviewable preparation, not a publish-ready
offline Reading Room and not an aggregate “10/10”.
