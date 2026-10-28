# Pickup prompt: 06-account-deletion-compliance

**Status: pending.** Pickup owner: Files/account owner + Apps.

Read HANDOFF.md and TASK_INDEX.json beside this prompt first. Use the existing isolated app checkout `/Users/home/CZURImages/khajistan-apps-receiver-macos-20261013`, branch `codex/apps-receiver-macos-20261013`. Its source HEAD before handover documents is `52c0a63bf9210f22d791d888538fdaf02d8b5261`. Check LOCAL_COMMIT.json in the owner-local handover folder for the later documentation commit.

Read the root AGENTS.md, TEAM.md, task rules and targeted COORDINATION.md entries before taking a claim. Other lanes own the shared root and archive. Preserve their changes; do not switch their branches, broad-stage, force-push or reset them. Commit only explicit owned paths with an isolated index. Never print or commit credentials, customer data or signed URLs.

This handover authorizes preparation and safe pickup planning. It does not authorize new publishing, production mutations, purchases, customer messages, deletion or paid inference. Verify Dropbox custody before clearing anything. Do not restart paused lanes or duplicate their workers. Use independent code review and focused meaningful tests for any future implementation.

The audit found website signup but no customer deletion control or endpoint. Sign-out is not account deletion. Confirm current backend state and read Apple's 5.1.1(v) guidance plus `docs/apps/APP_STORE_PACK.md:121` before implementation.

Prepare a narrow reviewed design covering authentication, personal-data deletion, lawful order/content retention and explicit user confirmation. Respect single-owner edge-function rules and verify live versions before deployment. This handover does not authorize deleting any real account or deploying a sensitive endpoint.

Test only with an explicitly disposable synthetic account after approval. Preserve receipts. Do not mark compliance complete based only on a support-email link.
