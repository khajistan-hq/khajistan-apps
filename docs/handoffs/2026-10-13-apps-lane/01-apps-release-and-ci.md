# Pickup prompt: 01-apps-release-and-ci

**Status: pending.** Pickup owner: Apps / pickup owner to claim.

Read HANDOFF.md and TASK_INDEX.json beside this prompt first. Use the existing isolated app checkout `/Users/home/CZURImages/khajistan-apps-receiver-macos-20261013`, branch `codex/apps-receiver-macos-20261013`. Its source HEAD before handover documents is `52c0a63bf9210f22d791d888538fdaf02d8b5261`. Check LOCAL_COMMIT.json in the owner-local handover folder for the later documentation commit.

Read the root AGENTS.md, TEAM.md, task rules and targeted COORDINATION.md entries before taking a claim. Other lanes own the shared root and archive. Preserve their changes; do not switch their branches, broad-stage, force-push or reset them. Commit only explicit owned paths with an isolated index. Never print or commit credentials, customer data or signed URLs.

This handover authorizes preparation and safe pickup planning. It does not authorize new publishing, production mutations, purchases, customer messages, deletion or paid inference. Verify Dropbox custody before clearing anything. Do not restart paused lanes or duplicate their workers. Use independent code review and focused meaningful tests for any future implementation.

Check PR #1: https://github.com/khajistan-hq/khajistan-apps/pull/1. Source commits `8dd939a`, `fed7df2`, `530a903` and `52c0a63` are already pushed; the PR is not merged. Latest source iOS CI passed in 16m1s. TV CI was pending at handover.

The earlier full TV suite completed 44 tests, 4 skips and zero failures with TEST SUCCEEDED. Its 60-minute job cancelled during cleanup; the reviewed limit is now 75 minutes. Read `tv-fed7df2-ci-full.log` and `tv-final-ci-jobs.json` in the parent report folder.

Refresh current checks once. Do not rerun tests or reupload successful build 1 merely because older notes say pending. Preserve receipts. Resolve the public-release holds in the other prompts before requesting owner approval to merge or submit.
