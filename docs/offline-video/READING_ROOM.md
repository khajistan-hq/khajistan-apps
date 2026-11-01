# Reading Room protection and release evidence

2026-10-31. Native implementation in `codex/protected-offline-video`, based on PR #13
`d33027313652d95c04c4ba0cd6cc28a0a6d963b2`. This is a preparation branch, not a release.
No backend deployment, new entitlement, sale, OCR spend or source-asset change is included.

## Implemented native corrections

- `ReadingStore` captures the auth generation before awaiting token refresh and checks it after
  refresh, signing and image work. Old account work cannot authorize a new account. Memory
  pages and thumbnail answers are cleared when the store observes a new generation.
- A decoded page or thumbnail requires an unexpired server answer on every return. The reader,
  companion page and thumbnail views also check the generation and permission before drawing.
  Account changes clear visible images; continuous-clock timers refresh visible authorization
  at expiry, including across sleep. Wall-clock rollback cannot extend an in-process answer.
- Raw JPEG page-cache writes are replaced by authenticated AES-GCM files. The key is a random
  256-bit device-only Keychain item; ciphertext binds the original storage path and includes an
  encrypted timestamp. There is no plaintext fallback. Only old app-owned hashed JPEG cache
  files are discarded, never original scans or catalogue assets.
- The encrypted cache excludes backup, uses platform file protection, expires after three days
  and enforces its 400 MiB budget after every write. Thumbnail memory has a 16 MiB cost limit.
  The page grid pre-signs the nearest 60 pages, then requests other visible thumbnails lazily.
- iOS page-turn transitions respect Reduce Motion.

This remains a **performance cache**, not a licensed offline library. Its bytes may be reused
between accounts only after a current server answer permits the requested page. Detached image
work can finish writing encrypted bytes after logout; it cannot return those pixels for the
old account. The server answer may be reused for up to eight minutes (less for shorter server
TTLs). Existing online access remains the authority. Refund/revocation is not instantaneous
during an already issued answer, and no instant offline revocation is promised.

## Verification

Aggregate native builds, targeted device-simulator flows and visual review are recorded in
`VALIDATION.md`. The gate table below retains the physical-device and real-entitlement holds.

The following tests use local synthetic fixtures, not paid production requests:

| Check | Evidence |
|---|---|
| Encryption/reopen/wrong key; tamper/truncation/path substitution; timestamp expiry and rollback; write-time/concurrent budget; storage failure; account/permission expiry and continuous deadline | `ReadingProtectionTests`, 7 passing, 0 failing |
| Changed Swift syntax and whitespace | `swiftc -parse` on the five implementation files and `git diff --check`: passing |

Focused native command (writable caches avoid the executor's home-directory restriction):

```sh
CLANG_MODULE_CACHE_PATH=/tmp/rr-review-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/rr-review-swift-module-cache \
swift test --disable-sandbox --package-path ios \
  --scratch-path /tmp/rr-review-swift-build --cache-path /tmp/rr-review-swift-cache \
  --filter ReadingProtectionTests
```

The initial Swift runs failed before test execution because the executor denied a home module
cache write and SwiftPM's nested sandbox. The command above runs inside the executor's existing
sandbox and succeeded. No escalation was requested. The permission helper tests are not a full
native session/network lifecycle test. The coordinating agent owns project regeneration,
aggregate builds/tests and independent review of this change.

## Objective release gates

All gates need evidence at the final candidate commit. No subjective 10/10 is assigned.

| Gate | Current state and remaining evidence |
|---|---|
| 1. Account isolation and authorization expiry | Native correction implemented; pure policy tests pass. Actual delayed-response/logout/switch UI tests and independent review pending. Web reader gap below remains open. |
| 2. Protected local bytes and no consumer export | AES-GCM cache tests pass. Device Keychain, backup, Files/export and storage-pressure behavior still need physical-device review. This is not offline entitlement. |
| 3. Licensed offline documents | Blocked on an authorized server/device grant and encrypted package contract; no download/library UI or backend entitlement activated. |
| 4. Paid access lifecycle | Existing server subscriber/grant checks remain. Real purchase, renewal, cancellation, refund, scope and revoked-account fixtures and verified payment-service tests are still required. |
| 5. Asset completeness and readable zoom | Existing mapping/navigation maintained; representative Iranian scans, largest pages, RTL spreads, missing scans and actual reading quality require asset/device review. No corpus was altered. |
| 6. Search and OCR | Native title search remains metadata search. Full-text discovery, text-layer coverage and OCR accuracy are not established. OCR provider configuration and spend approval are separate prerequisites for new extraction. |
| 7. Error/restart/offline behavior | Corrupt cache/storage failure are unit tested. Interrupted network, repeated actions, restart, offline launch, expired session and reconnection lifecycle need full native integration tests. |
| 8. Supported platforms and accessibility | Native changes cover iOS/iPadOS, Catalyst reader code and tvOS. Physical devices, Catalyst separately, VoiceOver, Dynamic Type, Reduce Motion and all three skins still require verification. |
| 9. Build/CI/review/owner acceptance | Focused tests pass. Both core suites, full package suite, Store builds, Catalyst, relevant UI regression, current-head CI, independent review and owner TestFlight review remain separate gates. |
| 10. Rights and product terms | Collector agreement remains unsigned; title-specific legal basis and product choices are unresolved. No worldwide legal clearance, new prices, sales or legal publication is implied. |

## Work that remains separate

The authenticated web reader is being corrected in its own repository for account-change
invalidation and shorter server TTLs. Its tests and release review are separate from this app
branch. Public commerce/editorial URLs, metadata, locales, discovery feeds and signed-out
indexability must remain intact; no domain cutover is included.

Protected offline documents need account/device/issue/version-bound signed grants, an encrypted
package manifest and page hashes, private key delivery/storage, explicit validity, renewal,
account removal and refund/revocation reconciliation. Existing signed image URLs do not provide
these rights. Offline access promises, device limits and reconnection intervals require product
decisions. Preserve purchased rights; instant revocation of a disconnected device is impossible.

Existing staff-policy, authentication, payment and legal launch work retains its separate
ownership and authorization gates. No production security setting is changed here. Native
search currently covers catalogue name/native/byline metadata. Full text/OCR coverage and
accuracy need source-asset review; new extraction cannot incur spend without approval.

No films, source holdings, Qandeel files or public access rules were changed by this Reading
Room work. The author of these changes cannot serve as their independent reviewer.
