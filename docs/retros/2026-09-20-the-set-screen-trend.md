# Retro — v0.11.0, the set-screen trend (2026-09-20)

**Scope:** v0.11.0. One ask, from the gym with a screenshot: put the trend graph
at the bottom of each exercise. One new view, one extraction, and two bugs in
the Trends tab that the extraction exposed.

## What went well

- **The chart was moved, not rewritten.** The Trends chart computes its own
  floor because an area mark anchored at zero renders a 5 lb increase as a flat
  line — a fix that is invisible until it is missing. A second chart written
  for the set screen would have had to rediscover it. `TrendChart` is the old
  drawing with its comment intact, and both screens use it.
- **Pulling the series into a pure function is what found the bugs.** Inline in
  a view, `sets.map(\.weight).max()` reads as obviously fine. As a function
  with a name and a doc comment, the first question is "max of WHAT, and is max
  right for every exercise" — and it was not.
- **Worked in a worktree.** The previous milestone left the live checkout on a
  feature branch for two hours, which broke RIA's gym tool and paused the phone
  installer. This one never touched it.
- **Looked at it.** The UI test screenshots the set screen with the chart on it,
  and the one spacing change came from reading that screenshot, not from
  guessing.

## What was hard to understand

- **The same series was computed in three places** — the Trends chart, the
  working-weight table, and the snapshot's `working_weight` — and they did not
  agree. The snapshot reported the LEAST help on an assisted machine (its doc
  says so); the app's chart and table both took `.max()`, the most. Nothing
  compared them, so the phone and `gym lifts` could show different numbers for
  one lift on one day and neither looked wrong alone.
- **`workoutKey` was a file-private function in `TrendsView.swift`.** The right
  grouping for "one point per workout" already existed and was unreachable from
  anywhere else, which is how a second screen ends up grouping by day again.
- **I wrote "a caller cannot label miles lb" about a design whose first caller
  did.** The measure travelled with the points as far as `TrendsView`, which
  kept the points and dropped it. A property of a type is not a property of its
  call sites, and the sentence was written from the type.
- **…and then I did it again in the correction.** "The chart asks the measure,
  it does not branch on the screen" replaced the withdrawn sentence, about the
  same call site, while that call site still had three `selection == .body`
  branches in it. Twice in one milestone: a claim about the code written from
  the design instead of from the file. The fix was to make it true rather than
  to soften it a second time.
- **The bump-level guard asks about capability and I answered about files.**
  First pass: PATCH plus `patch-intentional`, argued from "it is an extraction".
  The guard's own message says "genuinely not new user-visible capability", and
  the hatch is label-only so that a commit cannot excuse itself. It took the
  guard failing to make me read the question.

## Gaps found

| Gap | Kind | Follow-up | Status |
| --- | --- | --- | --- |
| The set screen showed the last three sessions and no shape | feature | `ExerciseTrend` under "last three", today included | landed here |
| The chart lived inside `TrendsView` and could not be reused | structure | `TrendChart`; `SetEntry.workoutKey` made shared | landed here |
| An assisted machine's trend and working-weight table plotted the MOST help — the worst set — and disagreed with the snapshot | correctness | `Tally.liftTrend`, least help when assisted; chart and table both read it | landed here |
| The Trends headline coloured taking help off as a loss | correctness | direction read from the exercise's `assisted` | landed here |
| A warm-up could be the day's point on a chart | correctness | working sets only in `liftTrend` | landed here |
| Cardio had no trend anywhere in the app | feature | `Tally.cardioTrend`: miles, else minutes, never a mix | landed here |
| "1 days" beside the chart on a two-a-day — the count clamped, the plural not (review) | correctness | summary moved to `Tally.Trend.summary`, where it can be tested | landed here |
| A bodyweight lift drew a flat line at 0 lb on an axis from −5 to 5 (review) | correctness | `.reps` measure: best working set per workout | landed here |
| The Trends tab discarded the measure and labelled an assisted lift "lb" — contradicting this milestone's own DECISIONS entry (review) | consistency | `TrendsView` reads `trend.measure`; table rows tagged "help" / "reps" | landed here |
| One chart padding for miles and minutes, wrong for both (review) | correctness | `TrendMeasure.minimumPad`, `isStepped` | landed here |
| The table's progress colour read `Exercise.assisted`, not the measure: a graduated assisted machine showed "+4" grey beside "+4 reps" teal (second review) | correctness | `Row.lowerIsBetter` from `measure.lowerIsBetter` | landed here |
| The table sorted a rep count among pound values under "Working weight" (second review) | correctness | `TrendMeasure.sortGroup`: pounds, help, reps | landed here |
| Body weight was `.weight` plus three call-site checks — a `Trend` wrong about its own shape, padding and direction (second review) | structure | `TrendMeasure.bodyWeight`; the checks deleted | landed here |
| `[SetEntry].trend(for:)` and `workoutKey` — the code that moved — had no tests (review) | testing | three model-backed cases, incl. the two-a-day | landed here |
| The snapshot's `working_weight` is still its own computation, not `Tally.liftTrend` | consistency | none | blocked: it picks the same SET (least help, working sets) but groups by day where `liftTrend` groups by session, so on a two-a-day the two can differ; and `SnapshotTests` pin its values; swapping the implementation under a wire contract is a change to make with the CLI fixtures open, not as a rider on a chart. Named here so the third copy is known to exist. |

## Follow-ups landed in this milestone

- Everything in the table marked `landed here`.

## Follow-ups blocked (and why)

- **One series, three callers — two done.** The chart and the table now share
  `Tally.liftTrend`. The snapshot builder still computes `working_weight`
  itself. It is correct, and tested, so this is duplication rather than a bug;
  it is written down because the last time three copies of this logic existed,
  two of them were wrong for a month.
