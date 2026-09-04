# Retro — v0.7.0, the denominator (2026-09-04)

**Scope:** v0.7.0. Two bugs in one number, both found by using the app, neither
findable by reading it.

## What went well

- **The report was a diagnosis, not a symptom.** "This is measuring against
  number of workouts in the plan, not days I workout" named the defect exactly.
  The follow-up — "it was 3, I just changed it, so we need to keep history" —
  turned a one-line fix into the right feature, and it arrived before the
  one-line fix had shipped.
- **The coverage half of v0.5.0 survived.** Distinct workouts per week was the
  right numerator and stayed; only the denominator moved. Splitting the two made
  that possible to see.
- **The data answered the question.** Reading the real snapshot gave 2, 3, 3
  workouts over three weeks, which is 5-of-8 at target 4 and 5-of-6 at target 3
  — the exact numbers on the screen and in the report. No guessing about whose
  arithmetic was wrong.

## What was hard to understand

- **The bug hid behind equal numbers.** The plan has four workouts and the
  schedule had four days, so plan-size and schedule-days agreed and every test
  passed. v0.5.0 was written and verified on the one configuration where the
  distinction is invisible.
- **"Keep history" was the whole design, stated in nine words.** The obvious
  reading of the first message is a one-line change to the denominator. That fix
  would have been correct and would have silently re-scored every past week the
  next time the schedule moved.
- **The migration cannot know what it needs to know.** A schedule changed before
  the feature existed left no trace, so the first epoch is a guess from the
  *new* schedule — the wrong one, for exactly the person who reported it.

## Gaps found

| Gap                                                                        | Kind        | Follow-up                                                                     | Status      |
| -------------------------------------------------------------------------- | ----------- | ----------------------------------------------------------------------------- | ----------- |
| Target came from plan size, so 4 workouts on a 3-day schedule capped at 75% | correctness | `Rotation.weeklyTarget(config, plannedWorkouts:)`, capped both ways            | landed here |
| A schedule change re-scored every finished week                            | correctness | `ScheduleEpoch`, append-only; each week scored by what was in force           | landed here |
| Pre-feature history has no recorded target                                 | data        | seeded at migration and **editable** in Settings, because nothing can know it | landed here |
| v0.5.0 was verified on the one config where the two numbers agree          | testing     | tests now use 4 workouts against a 3-day schedule explicitly                   | landed here |
| Only the weekly count is stored, not which days                            | design      | deliberate — the metric is day-agnostic; recorded in DECISIONS                | landed here |

## Follow-ups landed in this milestone

**The lesson is about verifying on the wrong data.** v0.5.0's denominator was
changed and tested against a plan where workouts-in-plan and training-days were
both 4. Every test passed, the screen looked right, and the metric was wrong for
any other configuration — including the one this user moved to a week later.

The tests now state the distinction rather than happening to satisfy it: four
workouts against a three-day schedule targets three, and a four-day schedule
against a three-workout plan also targets three. Neither passes by coincidence.

The second lesson is smaller and sharper: **a number that changes retroactively
is not a record.** Nothing in the original design was wrong about the current
week — it was wrong about the ones already behind it, which is the half nobody
looks at until it moves.
