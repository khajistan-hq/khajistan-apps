# Whole-atlas Surf without repeats

Prepared November 2, 2026 on top of the caption integration commit `6f7e34d`.
Local implementation only; no build has been installed, uploaded or released.

The default Apple TV Surf reads every main-atlas region. Previously its
four-second deadline discarded slower shards as soon as a fast region answered,
and each new Surf press forgot earlier selections. The app now waits for every
requested shard to answer or fail, and keeps a stable-channel-ID visit cycle for
each explicit media/atlas selection. Closing and reopening Surf preserves that
cycle for the app session. Both remote directions in Surf choose another
unvisited channel. A completed cycle reshuffles and avoids immediately repeating
its last channel when another choice exists.

New catalogue IDs join before old channels repeat; withdrawn IDs leave the
available pool. Duplicate IDs across regions appear once. A failed region is
explicitly incomplete: after the available channels are visited, the app asks
the viewer to return to Surf and retry instead of creating a short regional loop.
Failed playback attempts count as visits; they do not reset the cycle.

TV-only, radio-only and Beyond the atlas remain explicit choices. Cameras remain
in their existing separate section. A channel selected manually from a region
retains that region's ordinary next/previous navigation. Guide choices are
explicit and can revisit a channel; subsequent automatic Surf steps remember
that visit. Radio's small-player handoff preserves its Surf context.

Surf history is in memory for this app session, not a stored viewing log. Region
catalogues refresh through the existing ReceiverStore cache policy. Individual
network resources are capped at 30 seconds; this is not a promise that the entire
multi-stage Surf load takes at most 30 seconds. Cancelled filter/navigation
requests cannot present an old selection, consume history or replace known
withdrawal controls with cancelled-read results.

The shared all-shard loader also compiles for iOS. Persistent visit-cycle state
and its remote navigation integration are Apple TV changes.

## Verification

- Actual caption/preference harness: **13/13 groups passed**, including six new
  Surf groups. Tests cover a region responding after the old four-second cutoff,
  three complete cross-region cycles, duplicate IDs, reopening Surf, rollover,
  new/removed/returning channels, partial/empty/single-channel catalogues,
  publication/health/denylist/media/atlas filters, and captions remaining active
  while controls expire after five seconds throughout a full Surf cycle.
- tvOS `build-for-testing` and iOS Simulator build passed. Neither was launched.
- Native core: **155 passed, one pre-existing database-count group failed,
  three skipped**. See `CAPTION-INTEGRATION-REVIEW.md` for the unchanged build-10
  reproduction. Surf core groups pass.
- Independent source review found no remaining blocking issue after fixing
  stale completion when filters or navigation change during loading.

Evidence: `evidence/tvos-surf-caption-preference-tests.log`,
`evidence/tvos-surf-build-for-testing.log`, `evidence/ios-surf-shared-build.log`,
and `evidence/tvos-surf-core-tests.log` in the task workspace.

Physical remote playback across the actual full atlas remains unverified.
After an approved distribution build is installed, select default Surf, step
through channels across regions, exit and reopen Surf, then test TV-only/radio
and a filter change during loading. Caption preference and five-second controls
should remain intact. No live provider-to-device success is implied by these
fixtures.
