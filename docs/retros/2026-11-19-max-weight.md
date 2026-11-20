# Retro — v0.20.0, max weight (2026-11-19)

**Scope:** v0.20.0. One owner ask: "I'm starting to get to the max weight
possible — need a way to add a max weight (increase only reps)."
`Exercise.maxWeight`, carried on `Tally.Set`, read by `Tally.nextTarget`; a row
in the exercise editor; the set screen's + clamped; `exercises[].max_weight` in
the snapshot and in `gym exercise`.

## What went well

- **`assisted` had already built the door.** The flag travels on `Tally.Set`
  from `SetEntry.tally` / `Exercise.tally`, precisely so `nextTarget` derives
  it and no caller can forget it. The max went through the same door. All three
  suggestion call sites (set screen, Today row, snapshot stand-in) picked it up
  with no change to any of them.
- **One function decides the next target.** Today's row weight, the set
  screen's opening numbers and `gym today` all come from `nextTarget`, so the
  behaviour changed in one place and they cannot disagree.

## What was hard to understand

- **Where the limit belongs: the exercise or the plan slot.** The machine's
  stack is a property of the machine, not of a day's programme, and a stand-in
  carries its own exercise. So it is on `Exercise`, and a swap to a different
  machine gets that machine's limit.
- **Which set the extra rep counts from.** "One more than your best" asks you to
  repeat a set you already did. "One more than your weakest" asks every set to
  reach a number one of them has not yet hit, which is what progress at a fixed
  weight looks like.

## Gaps found

| Gap | Kind (docs / testing / process / observability) | Follow-up | Status |
| --- | ----------------------------------------------- | --------- | ------ |
| At the top of the stack the suggestion kept adding 5 lb the machine doesn't have | testing | `MaxWeightTests` | landed here |
| "and it goes up" was promised on a set that cannot go up | testing | `testShortOfTheTargetAtTheMaxDoesNotPromiseMoreWeight` | landed here |

## Follow-ups landed in this milestone

- Both rows above.

## Follow-ups blocked (and why)

- None.
