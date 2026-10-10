# Retro — v0.19.0, music pauses for a Short and comes back at READY (2026-10-10)

**Scope:** v0.19.0, Phase 2's phone side. `FeedAudio` (the Short's sound
against the workout music), pairing switching the lens to the Web App, and a
lens-facing "no workout" sentence. The page side (the rest pager, the rest
band, READY pulling the page back, the Short's sound) is ria-ar-feed's
`feat/rest-feed`, built in parallel against the same contract.

## What went well

- **No wire change was needed.** v0.18.0's contract already had `feedAudio`
  forwarded by the room and `idle` carrying text; Phase 2's phone side is
  behaviour behind existing messages. The page and the phone could be built
  at once without either waiting on a schema.
- **The rule is one bit, and the tests are about when to forget it.** Every
  test reads as a case from the owner's day: paused it myself, pressed play
  myself, took a call, Siri.
- **The mutation check removed code.** "Do not resume during an interruption"
  survived its mutant: the claim is dropped when an interruption begins, so the
  guard could never fire. It was deleted, not kept as reassurance.

## What was hard to understand

- **Siri's interruption never ends.** The spike measured `began` with no
  `ended`; a flag set at `began` and cleared only at `ended` would have turned
  the feature off for the rest of the workout after one "Hey Siri". It clears
  when the music plays again or a rest ends.
- **Settings' sentences were reaching the lens.** `idle.text` was the driver's
  `idleReason`, written for Settings ("…on Today"). On the glasses it read as
  broken. Two audiences, two sentences.

## Gaps found

| Gap | Kind (docs / testing / process / observability) | Follow-up | Status |
| --- | --- | --- | --- |
| The feed's sound worn end to end: pause on unmute, back at READY, the phone awake in a pocket throughout | testing | `docs/LENS_CHECKLIST.md` F1–F8 | blocked: needs the page's rest feed (ria-ar-feed `feat/rest-feed`, in progress) deployed and the glasses worn through a workout |
| Music.app or Spotify as the music source (the plan's non-mixing-session lever) | capability | resume only if paused, through the session | blocked: the owner trains to the in-app player (Phase 0 answer), and another app's player cannot be paused or resumed by a third party except by taking the audio session, which the keep-alive needs mixing — the two cannot both hold |
| Pairing left the lens on Native, so the glasses said "No workout" (owner, first use) | testing | pair → Web App; `testPairingSwitchesTheLensToTheWebApp`, mutation-checked; checklist W14 | landed here |
| Settings' wording reached the lens through `idle.text` | docs | `WorkoutDriver.lensIdle`; LENS_WIRE.md change 18; two tests | landed here |
| An interruption flag that only `ended` clears would stick after Siri | testing | cleared on playback or READY; `testASiriInterruptionThatNeverEndsDoesNotStickForever` | landed here |
| An unreachable guard in `resumeIfOurs` | testing | removed, after its mutant survived | landed here |

## Follow-ups landed in this milestone

- LENS_WIRE.md changes 17 and 18; checklist rows W14, W15, F1–F8.

## Follow-ups blocked (and why)

- Wearing it needs the page's half; Music.app/Spotify control conflicts with
  the keep-alive's mixing session (see the table).
