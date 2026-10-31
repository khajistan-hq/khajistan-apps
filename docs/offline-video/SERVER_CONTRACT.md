# Offline issuance boundary — proposed, not deployed

## Provider evidence and prerequisite

Reviewed 2026-10-31:

- [Cloudflare Stream security](https://developers.cloudflare.com/stream/viewing-videos/securing-your-stream/) describes signed delivery URLs and optional downloadable tokens. [Its download API](https://developers.cloudflare.com/stream/viewing-videos/download-videos/) produces MP4/M4A files. Neither document supplies a persistent FPS license API. Account-specific DRM support remains unverified; get an affirmative technical capability statement and working encrypted test asset before selecting this path. Do not interpret signed delivery as DRM.
- [Apple FPS](https://developer.apple.com/streaming/fps/) requires the Developer Program Account Holder to request production credential approval. The certificate is public; its private key and application secret belong in an approved KSM secret store, never this repository, chat or an app bundle.
- [AVAssetDownloadURLSession](https://developer.apple.com/documentation/avfoundation/avassetdownloadurlsession) supplies background HLS downloads, with a stable session identifier for restoration. It does not independently authorize the viewer or supply DRM.
- [Persistent key updates](https://developer.apple.com/documentation/avfoundation/avcontentkeysessiondelegate/contentkeysession(_:didupdatepersistablecontentkey:forcontentkeyidentifier:)) replace earlier key blobs. Replacement failures must close playback. Rental duration must be enforced by the FPS key policy, not just `Date()` or editable JSON.

Secure setup needed: approved FPS/KSM integration; packaged FairPlay HLS with known content identifiers and asset version; staging origin; public FPS certificate; server-only private keys; real development rental and purchase entitlements for a non-customer test account. No enrolment, charge, private key creation, persistent grant or production configuration was performed. Do not put secrets in a PR, issue, terminal transcript or chat.

## Required service behavior

Use a new read/issue endpoint, separate from `vod-token`. The latter currently mutates a rental's expires_at on playback and must never be called to prepare a download.

1. Authenticate using the existing server-side user verification. Client-supplied account, price, right, purchase state or device counts cannot authorize access. Reuse reviewed staff/access policies without widening staff exceptions; offline entitlement must explicitly allow this title and use.
2. Resolve an immutable order/entitlement identifier, account, film handle, asset version, acquisition kind and offline rights. Preserve each of the ten volumes as a distinct title identity even if a future bundle grants all ten. Keep the other holdings intact.
3. Bind key issue to the FPS device identity in the SPC, an app-generated installation identifier, and the authenticated account. Atomically enforce the approved device limit. Reinstall/restore must not duplicate an unlimited grant. Idempotent request IDs and concurrency tests are required.
4. Return a versioned grant containing `entitlementID`, `accountID`, `deviceID`, `filmHandle`, `assetVersion`, `kind`, `issuedAt`, `refreshBy`, `startBy`, `playbackEndsAt`, `playbackDuration`. `purchase` contains no rental deadlines. Manifest URL, exact allowed media host and `skd` key identifier are separate from local display metadata. Never store a long-lived bearer token or customer email in the film index.
5. Generate the CKC only after checking those bindings. Place hard validity and rental dual-expiry constraints in the FPS response. The current app adapter assumes a single stable content key identifier per version; multi-key/rotating-key provider content needs a separately tested key map, not a silent fallback.
6. `prepare` does not consume the 48-hour window. An unstarted rental retains the original purchase-relative 30-day start deadline, including repeated download/reinstall. An already-started rental inherits its original end. Starting immediately before day 30 must preserve the full promised 48 hours unless the existing contract explicitly says otherwise.
7. Rental first-play synchronization across devices requires an explicit design: offline first-play reports cannot instantly reach another device. Either provider supports secure dual-expiry activation reconciliation, or an approved first-online-activation/device-reservation rule is needed. Do not silently require online first play or shorten sold rights.
8. `reconcile` checks each grant after connectivity resumes. Explicit refund/revocation removes local playable keys and stops playback; 401 stops access; network/5xx failure allows only the still-valid issued offline lease. Partial responses never silently revalidate missing titles. The maximum offline lease is the revocation bound, not instantaneous remote deletion.
9. Permanent purchase account access and a finite renewable device lease are separate concepts. Reconnection renews the lease while the purchase remains valid. Do not expire ownership, reactivate sales, or invent a reconnection duration.
10. Content key/receipt renewal is atomic. Invalid/unknown key IDs, missing permissions, clock rollback, corrupt metadata, storage failure and stale-account responses fail closed. Errors/logs omit keys, SPC/CKC, signed URLs and tokens.

## Implementation boundary

This branch implements app file containment, pure entitlement/lifecycle checks, device-only Keychain record handling and the AVContentKeySession persistent-key delegate path. The provider service protocol has **no production implementation**. No offline Download/Play control is shown. The AVAssetDownloadURLSession transfer coordinator, persisted offline catalogue, reconnection worker and native offline player integration are still required after the provider/asset/activation contract is resolved. The transfer reducer is tested logic for that coordinator, not evidence of a real completed download.

Do not turn on an unencrypted sample or MP4 path to make a demo appear complete. FairPlay device, interrupted-transfer, offline-relaunch, subtitle/audio selections, storage-eviction, license renewal and account-switch acceptance remain release blockers.

## Product choices held

| Choice | Configurable shape to evaluate | Decision status |
|---|---|---|
| Offers | individual title; ten-volume bundle; separate subscription entitlement | Pending; no prices/SKUs invented |
| Devices | server-enforced per account / per grant limit; device removal UI | Pending |
| Reconnect period | finite issued lease with purchase renewal; rental bounded by sold access | Pending; must be disclosed before sale |
| First play | secure offline dual-expiry with cross-device reconciliation | Provider validation required |
| Platforms | iPhone/iPad first; Catalyst separate gate; browser/tvOS streaming | Scoped; no unsupported capability promised |

## Public discovery boundary

Authenticated reading is separate from the public storefront/editorial entrance. This work changes no web URLs, DNS, redirects, canonical rules, indexability, locale routes or feeds. A future proposal must inventory and preserve product/page/blog/collection URLs, canonicals, language hreflang, Product JSON-LD, robots.txt, all sitemap/locale/agent-discovery feeds, and signed-out access to indexable landing pages. An authenticated password gate is not an acceptable replacement for the public entrance. Domain cutover remains separately unauthorized.
