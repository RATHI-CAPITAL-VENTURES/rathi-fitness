# Retro — v0.10.0, something else today (2026-09-19)

**Scope:** v0.10.0. Three asks from the gym floor in one message: swap an
exercise for the day without touching the plan, total time in the gym from
first log to last, and a 25 lb bar.

## What went well

- **The set screens already took the exercise separately from the slot.**
  `SetView(item:exercise:)` and `CardioSetView(item:exercise:)` were written
  that way for no reason a swap needed, and it meant a stand-in is just a
  different second argument. The whole feature is one resolver
  (`Swaps.exercise(for:)`) in front of three readers.
- **The "no clearing" argument picked the model.** A `standIn` field on
  `PlanItem` was one property and no migration. It lost to a dated row the
  moment the question became "what clears it", because every answer was a rule
  that fails silently — and its failure mode was the bug being fixed.
- **The bar was a registry waiting to happen.** Plate math was generic over the
  bar from day one; the only thing that could not say 25 was four tuples typed
  inline in a view.

## What was hard to understand

- **`item.target…` was read in twenty-odd places across three views**, and a
  stand-in makes about half of them wrong in a way that compiles: 185 lb
  offered on the dumbbells, two treadmill miles asked of a bike. There was no
  single seam, so `Swaps.Prescription` had to become one, and the set screens
  were moved onto it wholesale rather than patched read by read.
- **The log path writes back into the plan** (`Tally.advancedTarget` →
  `item.targetWeight`, 2026-09-02). Nothing about a swap touches that line, and
  it would have quietly turned a heavy stand-in day into next week's target for
  a different lift. Found by reading `logSet` for an unrelated reason.
- **Today already had a gym-time figure**, computed privately beside the row,
  and it had already been wrong once. Adding the figure in three new places
  next to a fourth, different, definition would have been the 0.9.1 bug again
  with a clock instead of a weight.
- **A context menu item exists before it will take a tap.** The first run of
  `SwapUITests` failed with no sheet on screen, which reads exactly like the
  feature being broken. It was not: tapped while the menu was still springing
  open, the touch landed on the dimming view and dismissed the menu, so the
  action never ran. The proof was the one-time hint still sitting on screen —
  the action's first line hides it. This retro's first draft had already
  written the UI test off as `blocked` on a guess about long-presses racing the
  navigation push; the guess was wrong, and it took one attempt to find out.
- **The crossover corners of `Prescription` were wrong in both directions and
  the tests said otherwise.** Independent review found that a lift standing in
  for a treadmill inherited 1 × 0 with no rest, and a rower standing in for a
  squat was prescribed nothing. The one crossover test asserted `.sets == 1`
  and nothing else, so it passed throughout. A test that names a behaviour and
  checks a third of it reads as coverage.
- **"What is in the slot now" is not "what was done in the slot".** The first
  version keyed the checklist on the current exercise, so a swap after two sets
  sent the row from "2 of 4" to "0 of 4". It was even written down as intended
  in a comment — which is how an undesigned case gets to look designed.
- **First log to last log undercounts on exactly his workouts.** A treadmill is
  logged when you step off. The ask was literal; the literal version reads
  twenty minutes short on every day that opens with cardio and zero on a
  cardio-only day.

## Gaps found

| Gap | Kind | Follow-up | Status |
| --- | --- | --- | --- |
| Changing one day's exercise meant editing the plan for every week | feature | `Swap`, dated row per slot per day | landed here |
| A stand-in would have inherited the other machine's weight, miles and grade | correctness | `Swaps.Prescription`; both set screens read it | landed here |
| Logging a stand-in would have advanced the PLANNED lift's target weight | correctness | write-back skipped when `isStandIn` | landed here |
| Today's elapsed time was a private computation with its own definition | consistency | reads `Tally.gymSeconds` | landed here |
| Raw first-to-last span drops an opening cardio bout | correctness | first log pulled back by its own `seconds` | landed here |
| A bar weight not on the menu displayed as "—" while still being subtracted | correctness | `PlateMath.barOptions(including:)` | landed here |
| Bars were an inline list in a view | structure | `PlateMath.bars`, exclusions named in the code | landed here |
| `gym` could not tell a swapped slot from an edited plan | observability | `instead_of` in the snapshot, "· for Treadmill" in `gym today` | landed here |
| The swap is a long-press, which nobody can discover | UX | one-time hint under the rows, gone once used | landed here |
| Swapping from inside the set screen | feature | none | blocked: `SetView` holds its exercise as a `let` and primes its weight once by design; changing it under a pushed screen (possibly to `CardioSetView`) means re-priming state built not to re-prime. Reasoned in DECISIONS 2026-09-19. |
| A lift in a cardio slot got 0 reps, no rest, and ticked done after one set; cardio in a lift slot got no minutes (review) | correctness | both crossovers open on `PlanDefaults`; four `SwapTests` cases | landed here |
| Sets logged before a swap, or on a stand-in later swapped away from, vanished from the checklist (review) | correctness | `Swaps.slugsCounting`; kept rows + latest-wins; Today, both set screens and the snapshot count the slot | landed here |
| `gym today` printed 0 lb for a stand-in the phone showed at 60 (review) | consistency | snapshot emits the weight the row shows | landed here |
| `gym sessions` total drifted hours below the phone's, from minutes truncated per workout (review) | consistency | `gym_seconds`, summed then formatted | landed here |
| Docs called the snapshot change additive when `today.items[]` had changed meaning (review) | docs | schema 7, history row, "Stand-ins" rewritten | landed here |
| Apple Health got the uncorrected span for a workout that opens with cardio (review) — and this table first called it blocked on a migration risk that only applies to rewriting history | consistency | `Sessions.backdate`, forwards only, never across midnight; four `SessionTests` cases | landed here |
| The swap flow had no UI test, and the first draft of this retro called that blocked without trying | testing | `SwapUITests`: menu → picker → catalogue → stand-in row → set screen → back | landed here |

## Follow-ups landed in this milestone

- Everything in the table marked `landed here`.

## Follow-ups blocked (and why)

- **Swapping from the set screen.** Not a missing afternoon — the set screen's
  one-shot priming is a deliberate fix from an earlier release, and a swap
  there would have to undo it. Today is one tap away.
