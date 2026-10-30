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

`tvos/scripts/test-caption-session.sh` compiles each actual production caption service and shared core against in-memory network and player boundaries. It never contacts a caption provider or starts paid demand. All 20 service scenarios pass (10 per platform). Both CI workflows run their platform's service tests. `KJ_CAPTION_TEST_PLATFORMS` selects a platform; `KJ_CAPTION_SERVICE_SOURCE` supports mutation checks.

Reconnect, source-clock placement and fresh REST adaptation were also run with deliberately broken implementations. All three checks failed, proving they detect those defects.

Builds checked: tvOS Simulator, Mac Catalyst, and signed physical tvOS Release. The signed app was installed and launched on the owner's connected Apple TV.

## Limits

These tests establish app scheduling and recovery behavior, not speech-recognition accuracy or a measured latency distribution on a live channel. Source segment availability, recognition finalization and translation still add latency. The existing 24-second startup hold is retained; lowering it without measurements can put captions behind the speech. Exact synchronization requires reliable programme timestamps and a seekable carrier. The Mac code is built but its installed application has not been replaced.
