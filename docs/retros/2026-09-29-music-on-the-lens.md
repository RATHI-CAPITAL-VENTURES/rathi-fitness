# Retro — v0.15.0, music on the lens (2026-09-29)

**Scope:** v0.15.0. Asked for a Neural Band ping when a rest ends and music
controls on the glasses. The second shipped; the first is not possible.

## What went well

- **The SDK was read before anything was designed.** The band ping was the
  headline ask, and the answer — Meta gives apps no haptics, in 0.9.0 or in the
  1.0.0 released five days earlier — came from the compiled interfaces and the
  changelog, not from a guess. Designing a "band ping" first and finding out
  after would have been an afternoon.
- **The existing seams carried it.** `RemoteControls.run` already knew what
  play/pause and next meant; `LensGate` already bound a pinch to the screen it
  was drawn on; `LensCard` already had specs for the rest clock. The music card
  is one value type and a few lines of routing.
- **The overlay is plain values, so it is tested.** Thirteen new cases in
  `LensTests`, including the one that matters most: the rest ending closes the
  card.

## What was hard to understand

- **Two layers own the lens at different times** — the phone's set screen and
  `WorkoutDriver` — and a feature that belongs to neither has no obvious home.
  `GlassesFace`'s header explains the layering well; what it did not say is
  that `onPinch` is bound at *draw* time, which is what made "whose Back is
  this?" answerable. Now said at the binding.
- **`remote` on `LensAction` is a promise to the mirror**, not just a mapping:
  the mirror forwards anything that has one. Giving music actions a `remote`
  would have been the natural move and a quiet bug. The test that guards it
  (`testNavigationIsNotARemoteAction`) says so, and `drivesPlayer` says why
  music is separate.
- **A toggle is wrong on a screen that repaints before the thing it drives
  answers.** The first draft sent Play and Pause to `togglePlayPause`; an
  independent review found a stale Play could pause. Explicit `play()`/`pause()`
  now, and the AirPods toggle is built from them.

## Gaps found

| Gap | Kind (docs / testing / process / observability) | Follow-up | Status |
| --- | --- | --- | --- |
| Band haptics when a rest ends | capability | none possible in-app | blocked: Meta's SDK has no haptics or band-output API in 0.9.0 or 1.0.0; the band's haptics belong to Meta's OS |
| Whether the time-sensitive "you're up" notification reaches the lens or band during a live display session | testing | wear it in the gym, rest with the phone locked | blocked: needs the glasses on a person, with the phone locked in a pocket — not reachable from a build or a test |
| Four buttons on the driver's READY screen (Log set, −1 rep, Back, Music) never seen on the hardware | testing | wear it; if it does not fit, drop −1 rep from READY | blocked: needs the Display glasses on a person; `ButtonGroup` layout is not observable in the simulator or Meta's mock |
| `make test-unit` failed with "Unable to boot device" when the simulator's data dir had vanished — reads like a build failure | docs | note the cause and `simctl erase` fix beside `SIMULATOR` in the Makefile | landed here |
| Lens Play/Pause went through a toggle, so a stale Play (before MusicKit answered) could pause | testing | explicit `play()`/`pause()` on `MusicController` | landed here |
| Empty card offered Play with no playlist to start; a deleted favourite made Play do nothing | testing | Play hidden without playlists (`testNoPlaylistNoPlay`); favourite falls back to newest | landed here |
| Music card survived the phone's set screen closing, and glasses off/on | testing | `music.close()` in `disarm` and `endSession` | landed here |
| "Nothing queued → start the favourite" lived in `MusicBar`, so an AirPods press with nothing on did nothing | testing | moved into `MusicController.togglePlayPause` | landed here |

## Follow-ups landed in this milestone

- The simulator note in the `Makefile`.
- Play-with-nothing-queued as a controller rule, not a view rule.

## Follow-ups blocked (and why)

- The band cannot be driven by an app at all. The two hardware questions need
  the glasses worn in a gym; both are written in `docs/DECISIONS.md` so the next
  session there knows what to look for.
