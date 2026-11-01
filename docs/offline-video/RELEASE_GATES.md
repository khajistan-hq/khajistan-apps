# Protected offline film viewing — release gates

Implementation owner: Codex, `codex/protected-offline-video`, isolated checkout.
Baseline: PR #13 `d33027313652d95c04c4ba0cd6cc28a0a6d963b2`, checked 2026-10-31.
No deployment, merge, store submission, sale, provider enrolment, or physical-device installation is included. Isolated simulator tests are permitted.

## Acceptance contract (set before implementation)

A pass requires evidence at the final candidate commit; a policy-unit pass is not a device DRM pass.

1. Only encrypted HLS plus device-bound persistent FairPlay keys can enter the offline film path. A Cloudflare signed URL or raw MP4 is rejected. No raw-file share, export, Quick Look or public download link for films.
2. Download authorization does not invoke `vod-token` or start a rental. Rentals retain 30 days to start and 48 hours after first play. Purchase account access remains permanent; a renewable offline device license is distinct from ownership.
3. Authorization binds account, device, entitlement, film and asset version. All ten Filmfarsi volumes and other Iranian holdings remain present. Rights are title-specific; an unsigned collector agreement is not clearance.
4. Interrupted/repeated downloads, restart, network loss, offline launch, expiry, storage pressure, key rotation and cancellation cannot expose partial content or extend rights.
5. Logout/account change stops playback and invalidates local access before asynchronous work can complete. Refund/revocation is enforced on successful reconnection and by the license's bounded validity offline. No promise of instant offline revocation or copyproof media.
6. iPhone/iPad actual encrypted download/play/expiry tested on devices; Catalyst evaluated independently. Browser/tvOS remain streaming-only. VoiceOver, text size and all three skins checked for any new UI.
7. Both core suites, Swift package tests, iOS/tvOS Store builds, Catalyst build and relevant UI regressions at final head. Failures, skips and external blocks are recorded separately.
8. Independent review, current-head CI, owner TestFlight review and legal/product approval are separate gates. No numeric subjective publishability score.

## Current stop conditions

Cloudflare Stream's documented export creates MP4/M4A, and `vod-token` supplies only a signed manifest token. Neither is a persistent FairPlay license. Provider-specific FPS support for this account is **unverified**, not assumed. No KSM endpoint, FPS certificate, encrypted offline asset fixture or entitlement test account is available to this task. Offline release stays closed until these exist. Independent containment, lifecycle policy and native key-storage work can proceed.

Configuration still requiring owner decisions: prices; individual/ten-volume/bundle/subscription SKUs; device limit; offline reconnection interval; cross-device rental activation behavior. No default has been activated or represented as a customer promise.
