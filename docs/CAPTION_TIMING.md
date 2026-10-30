# Native Receiver caption timing — 2026-10-30

Applies to Apple TV and the iOS/Mac Catalyst Receiver. Website code and recognition/translation providers are unchanged.

## Behavior

- A closed websocket reconnects with bounded backoff. REST recovery runs independently, so a slow recovery request cannot stop live frames. Quiet or disconnected feeds are checked every two seconds instead of leaving captions in 15–18-second batches.
- Translation has an absolute eight-second deadline, including authentication and response download. Later ready translations stay ordered; an expired result never reappears after newer speech.
- The source timeline stays separate from reading-time padding. Unseen short fragments may share a two-line plate. Original phrase anchors survive compaction and out-of-order recovery. An active caption retains its full readable duration.
- Queue overload removes stale unseen backlog and reports omitted speech instead of dropping the current sentence behind a 30-second queue. Each admitted plate keeps the existing 2–7-second reading rules and 20 characters/second target.
- A caption-triggered seek finishes before rows are mapped again. The source anchor is preserved, rather than clamped to the old playhead. An eight-second watchdog cancels a stalled seek. Turning captions off cancels its outstanding seek; late callbacks cannot affect a new session.
- Fresh REST rows may adjust the hold using server creation time. Old recovered rows cannot rewind playback. Nonseekable streams use approximate arrival-time display.

## Verification

`KJ_ARCHIVE=/path/to/filmart/archive tvos/scripts/test-core.sh` exercises real local catalogue parity and shared caption timing. `ios/scripts/test-core.sh` verifies the phone/Mac shared sources.

`tvos/scripts/test-caption-session.sh` compiles each actual production caption service and shared core against in-memory network and player boundaries. It never contacts a caption provider or starts paid demand. All 32 service scenarios pass (16 per platform), including the MBC dropout follow-up. Both CI workflows run their platform's service tests. `KJ_CAPTION_TEST_PLATFORMS` selects a platform; `KJ_CAPTION_SERVICE_SOURCE` supports mutation checks.

Reconnect, source-clock placement and fresh REST adaptation were also run with deliberately broken implementations. All three checks failed, proving they detect those defects.

Builds checked: tvOS Simulator, Mac Catalyst, and signed physical tvOS Release. The signed app was installed and launched on the owner's connected Apple TV.

## Limits

These tests establish app scheduling and recovery behavior, not speech-recognition accuracy or a measured latency distribution on a live channel. Source segment availability, recognition finalization and translation still add latency. The existing 24-second startup hold is retained; lowering it without measurements can put captions behind the speech. Exact synchronization requires reliable programme timestamps and a seekable carrier. The Mac code is built but its installed application has not been replaced.

## MBC dropout follow-up

The owner identified an MBC channel in Jazirat al-Arab on Apple TV, without remembering which MBC channel. Read-only playlist probes on 2026-10-30 found programme timestamps and approximately 61.4-second windows on the nine MBC television feeds checked (the two radio-name entries were excluded from that statement). No MBC rows remained in the short-lived wire when inspected, so the exact viewing incident cannot be reconstructed.

Two additional client dropout paths are fixed:

- The worker may PATCH English into an existing source row. The client now subscribes to both INSERT and UPDATE, and REST refreshes can also complete a pending translation. Only the same source identity, inside its original absolute deadline, can complete it. Late/duplicate updates cannot replay captions, and uncertain, changed-source or rejected-language updates are refused.
- Fresh speech that cannot be synchronized safely is displayed with an approximate-timing notice instead of being discarded solely for being more than six seconds late. That six-second limit still bounds unseen display backlog. Stale recovery history remains excluded. Freshness is captured on receipt, so waiting for English does not invalidate an otherwise timely REST row.

A failed on-demand translation now waits for the server's original translation until the existing deadline; it does not permanently discard the pending row immediately. This is not a claim of improved recognition accuracy or measured MBC end-to-end performance.
