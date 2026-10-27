# Decisions

Each entry: what was chosen, and why, in one or two lines.

1. **Base: `origin/main` 513b617 with PR 1 merged in.** PR 1 carries the Mac Catalyst app and the
   Receiver caption fixes; main carries the live-tune and stall-limit work. They conflicted in one
   function pair (kept both) and the generated project file (regenerated).
2. **Five bar doors on iPhone: Home, Rooms, Receiver, Library, Search** (owner brief). Pics/Vids
   moves inside Rooms; Account becomes part of Library. Old `-kjtab` names (`yours`, `picsVids`)
   still land where they meant to.
3. **A room is native only once its native screen exists.** Until then its door opens the website,
   exactly as before. No placeholder screens.
4. **Rooms layout: one stack on a phone, a sidebar beside the open room in a wide window.** Each
   room keeps its own stack and is kept mounted, so moving between rooms keeps its place.
5. **No system navigation bar.** It paints white and carries the system's chrome; each stack screen
   takes the skin's ground and a house Back row (Cmd-[ on Mac).
6. **Shared logic stays single-copy by symlink** (the existing pattern, checked by
   `ios/scripts/test-core.sh`). New Foundation-only models go in `tvos/KhajistanTV/Core` and are
   linked into the phone.
7. **Room copy is not taken from stale website lines.** The site menu still says "The 32 films — on
   demand" and "the Khajistan Radio mixes"; both are out of date (sales paused 2026-10-05, mixes
   removed). Native room headers use plain accurate lines instead.
