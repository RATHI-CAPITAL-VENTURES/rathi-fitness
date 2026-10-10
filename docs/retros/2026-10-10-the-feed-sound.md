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

- **What an interruption means.** The first version dropped the claim on any
  interruption and blocked pauses until it "ended" — but Siri never sends
  `ended`, and a Siri query is not a reason to break "music back at READY".
  Review settled it: only a phone call (CXCallObserver) counts, and only a
  plain-reason interruption.
- **Settings' sentences were reaching the lens.** `idle.text` was the driver's
  `idleReason`, written for Settings ("…on Today"). On the glasses it read as
  broken. Two audiences, two sentences.

## Gaps found

| Gap | Kind (docs / testing / process / observability) | Follow-up | Status |
| --- | --- | --- | --- |
| The feed's sound worn end to end: pause on unmute, back at READY, the phone awake in a pocket throughout | testing | `docs/LENS_CHECKLIST.md` F1–F8 | blocked: needs the page's rest feed (ria-ar-feed `feat/rest-feed`, in progress) deployed and the glasses worn through a workout |
| Music.app or Spotify as the music source (the plan's non-mixing-session lever) | capability | resume only if paused, through the session | blocked: the owner trains to the in-app player (Phase 0 answer), and another app's player cannot be paused or resumed by a third party except by taking the audio session, which the keep-alive needs mixing — the two cannot both hold |
| Pairing did not switch the lens to the Web App | testing | pair → Web App; `testPairingSwitchesTheLensToTheWebApp`, mutation-checked; checklist W14 | landed here |
| …and that switch was unreachable: Pair was offered only inside Web App mode — review | testing | "Use the Web App: pair with the relay" in Native/off; UI test `testPairingIsOfferedOutsideWebAppMode` | landed here |
| The owner's "No workout" was misattributed to pairing: the phone was already in Web App mode and the lens showed Settings' idle sentence — review | docs | corrected here and in DECISIONS; the real fix is change 18 | landed here |
| Off → on inside MusicKit's play latency left the music playing over the Short — review | testing | a `resuming` window: an `on` takes the claim and pauses when the play lands; `testOnWhileOurResumeIsInTheAirStillPauses`, mutation-checked | landed here |
| Every interruption dropped the claim, so a Siri query cancelled the owner's "music back at READY"; suspension/route reasons counted too — review | testing | only a plain-reason interruption during an active call (CXCallObserver) drops it; no resume into a call; four tests, mutation-checked | landed here |
| The production READY pipeline was untested — review | testing | `FeedAudio.readyPublisher`/`playbackPublisher`, tested with a real `RestTimer`; a redundant `removeDuplicates` removed after its mutant survived | landed here |
| The READY chime was sized for silence with music about to resume; a passed deadline counted as resting; `play` with nothing queued would start the favourite playlist; `feedAudio` ignored the one-lens rule and staleness — review | testing | over-music cue while the claim is held; `remaining() > 0`; `hasTrack`; one lens and ≤ 5 s; tests for the last three | landed here |
| AudioHub said Siri "tells US nothing" while the observers said Siri is heard only with `object: nil` — review | docs | both measured: depends on whether our session is active; Settings shows the last interruption for F6b | landed here |
| Settings' wording reached the lens through `idle.text` | docs | `WorkoutDriver.lensIdle`; LENS_WIRE.md change 18; two tests | landed here |
| An interruption flag that only `ended` clears would stick after Siri | testing | the flag is gone: interruptions now matter only through an active call | landed here |
| An unreachable guard in `resumeIfOurs` | testing | removed, after its mutant survived | landed here |

## Follow-ups landed in this milestone

- LENS_WIRE.md changes 17 and 18; checklist rows W14, W15, F1–F8.

## Follow-ups blocked (and why)

- Wearing it needs the page's half; Music.app/Spotify control conflicts with
  the keep-alive's mixing session (see the table).
