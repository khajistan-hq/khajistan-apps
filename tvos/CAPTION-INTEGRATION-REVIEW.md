# Native caption recovery and Apple TV controls

Prepared November 2, 2026 in `codex/tvos-caption-preference-controls-20261102`.
Baseline: `cc429a9` on `app/simple-nav`, which contains distributed build 10
(`106914e`) plus two existing UI-test corrections. This candidate is local only.

## Behavior

- Apple TV saves the CC preference across channel changes, leaving the player,
  pause and app relaunch. The saved choice is separate from a running caption
  session. Pause/failure/exit still release caption demand; resumed playback
  restores the saved choice. Explicit Off works even on an unavailable channel
  or after an access refusal. Eligibility, account and server lease checks remain.
- Receiver controls hide after five seconds without remote activity. Any new
  interaction resets the deadline and restores hidden controls. Open guide,
  system focus, VoiceOver and Switch Control keep them available. The caption
  layer stays independent. Hidden controls leave accessibility traversal.
- The reviewed caption fixes from PR #11 at `60c002a` are integrated into the
  current tvOS and iOS services: late English UPDATE events, socket reconnection,
  bounded translation waiting, source-clock placement, seek completion/watchdog
  handling, bounded readable queue and the worker's `latin` script label.

This is a selective integration, not an older-branch replacement. Build 10's
navigation, TV keep-awake handling and iOS channel-change carry remain. iOS keeps
its existing session-only carry policy; the new persistent preference is tvOS.
Only the required player seek callbacks and cancellation hooks were added.
No app, backend service, permission, provider setting or spending cap was changed
on a device or live service.

## Verification

- `sh tvos/scripts/test-caption-preference.sh`: **7/7 passed**. The actual tvOS
  service runs against isolated UserDefaults suites and synthetic player/auth/
  network boundaries. Covers repeated retunes, same-channel reconnect, service
  recreation with a fresh defaults object, explicit Off, unsupported/signed-out
  states, resumed/detached players, five-second deadline and interaction holds.
- `sh tvos/scripts/test-caption-session.sh`: **24/24 tvOS and 23/23 iOS passed**.
  These exercise the actual services, including late translation UPDATEs,
  disconnect/reconnect, delayed responses, retune fencing and caption placement.
  The older fixture's explicit-per-channel activation expectation was updated
  to the current carry/persistent-preference requirement.
- tvOS and iOS Simulator builds: **passed**. Final tvOS `build-for-testing`:
  **passed**, including the updated signed-out remote-control UI test source.
  Nothing was installed or launched by this work.
- Shared native core with the existing local archive fixtures: **155 passed,
  1 failed, 3 skipped (159 groups)**. The failure is the unchanged database
  record-count group: the local Arabic Music Index has 5,796 versus an expected
  6,686, and Persian Music Index has 34,072 versus 45,568. Dictionary iteration
  determines which mismatch reports first. The unchanged `cc429a9` baseline
  reproduces this same group failure: **154 passed, 1 failed, 3 skipped**.
  Caption-specific core expectations were updated from PR #11, with a new
  bounded-timeline group. No catalogue or unrelated test was altered.
- Independent source review found no remaining required issue after fixing
  explicit Off while a saved-On session is unavailable.
- The tvOS workflow now runs both synthetic caption harnesses before simulator
  tests and includes the iOS caption-service source in its sparse checkout.
  This workflow edit has not run on GitHub because the branch is unpublished.

Evidence is in the task workspace's `evidence/` directory:
`tvos-caption-preference-tests.log`, `integrated-caption-session-tests.log`,
`tvos-integrated-build.log`, `ios-integrated-build.log`,
`tvos-integrated-build-for-testing.log`, `tvos-integrated-core-tests.log`, and
`tvos-build10-baseline-core-tests.log`.

## Remaining device check

The lifecycle and controls tests use simulated boundaries. An actual app relaunch,
remote/focus/VoiceOver walkthrough and provider-to-physical-Apple-TV delivery
have not been performed. This source change does not resolve a separate live
backend incident by itself, and no new distribution build has been submitted.

After an explicitly approved build reaches the device:

1. Choose a playing live channel and enable CC. Wait five seconds: the controls
   disappear while available caption text remains. Press the remote: controls
   return; another interaction gives a fresh five seconds.
2. Switch repeatedly among eligible channels, including a temporarily unavailable
   one. CC stays selected; unsupported channels explain why they cannot run it.
3. Pause/resume and reconnect playback; captions release demand while stopped
   and resume with playback. Exit and relaunch the app, then choose a channel:
   the saved CC choice returns.
4. Turn CC Off, exit/relaunch and switch channels: it stays Off. Test Off while
   a caption session is refused/unavailable as well.
5. Keep the guide open, then test VoiceOver/Switch Control. Controls remain
   reachable, and begin a fresh timeout only after interaction is released.
