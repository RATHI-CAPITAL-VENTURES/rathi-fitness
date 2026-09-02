# Changelog

Every notable change to Rathi Fitness. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/) + [SemVer](https://semver.org/)
(`MAJOR.MINOR.PATCH` in `VERSION`). The `changelog` guard enforces that the top
header equals `VERSION`, is new relative to the base branch, and increases
monotonically; opt out with `changelog-exempt` or `[skip changelog]` for a
genuine no-op.

`VERSION` is mirrored by `MARKETING_VERSION` in `app/project.yml` — that is what
the phone shows and what every snapshot is stamped with, so the `version-sync`
guard makes them agree.

A **MINOR bump is a milestone** and must ship a retro under
[`docs/retros/`](./docs/retros/).

## 0.4.2 — 2026-09-01

### Fixed

- **The seed dated "six weeks of history" to this morning.**
  `Seed.mostRecent` computed `delta = weekday - today` and shifted back only
  `if delta > 0` — so when the seeded weekday **was** today, `delta` stayed `0`
  and a "historical" workout landed at 06:45 **today**. History that includes a
  session you have not done yet, sitting in the same day as whatever you log
  next.

  It only collides on the three weekdays the plan trains — Monday, Wednesday,
  Friday — so the suite passed four days a week and failed three, and *which*
  you saw depended on the timezone of the machine running it. A Mac on EDT and
  a runner on UTC disagree about the weekday for four hours every night.

  On CI (Wednesday, 02:31 UTC) it broke two tests with arithmetic that names
  the cause exactly: `SnapshotTests.testSetKindsAndRpeReachTheSnapshot` saw
  volume **6660** where it wanted 1480 — the seeded Push A bench is
  `185 × (8+7+7+6) = 5180`, plus the test's own `185 × 8` — and a reps array of
  **5** where it wanted 1, being the 4 seeded sets plus the working one.
  `WorkoutFlowUITests` then opened the set screen on an exercise that was
  already four sets in, so the plate math for 185 was not on screen.

  `>= 0` now, and history means the past.

- **`Seed.run(_:now:)` had a `now` nothing ever passed.** Every caller took the
  default, so the seed was only ever exercised on whichever weekday the run
  landed on — which is why a date bug survived in a covered function. The new
  `SeedTests` pin the date and walk a whole week, so all seven are checked on
  every run rather than one at random.

  The first version of that test built its Wednesday in **UTC**, matching the
  timestamp on the CI failure, and passed against the unfixed code: 02:00 UTC
  Wednesday is 22:00 EDT Tuesday, so `Calendar.current` read it as a Tuesday
  and the assertion agreed with itself about nothing. It builds dates in the
  current calendar now — the same ambiguity as the bug, one level up.

## 0.4.1 — 2026-09-01

### Added

- **Reset every rest at once.** Settings › New exercises › **Apply rest to the
  whole plan** pushes the Rest dial through every strength slot on every day.

  That section has refused to touch an existing plan since it shipped, and the
  footer said so — *nothing already in the plan changes*. The refusal is right:
  a default that silently rewrites your programme is a default you stop
  trusting. But it left no way to do the thing **on purpose** either, so
  changing your mind about rest meant opening every slot on every day and
  turning the same dial. The fix is an explicit act, not a looser default.

  It applies the number set directly above it rather than offering a picker of
  its own — a second place to declare one thing is a second place to forget it.

  **Cardio is left alone, and that is what makes a blanket write safe.**
  `restSeconds` on a cardio slot is the gap *between intervals*, a different
  quantity that happens to share a field, and the plan editor creates every
  treadmill slot with `0`. Including them would not reset a rest; it would
  invent intervals nobody asked for, on rows whose rest column reads "—". A
  cardio slot that *does* carry an interval rest was set by hand, which is
  precisely what a bulk action must not eat. The exclusion lives in
  `slotsTakingPlanRest` with the reason written beside it.

  Three things the confirmation does rather than ask you to trust:

  1. **It names the count** — "Set 8 exercises" — from the same query that does
     the write, so the number cannot drift from the act.
  2. **It reports what changed, not what it inspected.** A slot already at the
     value is not a write, so a second tap says *"Every exercise was already at
     1:30"* instead of claiming eight more.
  3. **It says cardio is excluded** in the message, rather than leaving you to
     diff your own programme to find out.

  Not undoable, and the message says so.

## 0.4.0 — 2026-09-01

### Added

- **Showing up — twelve weeks of consistency, on Today.** Under the workout and
  on rest days: the share of *planned* workouts you actually did over the last
  twelve weeks, and a mark for each week — full where you met the plan, short
  where you trained but came up short, empty where you did not, outlined for the
  week in progress.

  **This is deliberately not a streak, and the difference is the whole feature.**
  A streak was asked for and reconsidered honestly rather than refused by
  quotation; see `docs/DECISIONS.md`. There is no counter, so there is no zero to
  fall to and no single miss that makes quitting look like the consistent move.
  What makes it possible here and not in a general habit app: this app knows the
  schedule. `Rotation.Config` says which days you meant to train, so the
  denominator is what you planned and **a rest day cannot be a miss.**

  Three refusals inside it, each tested:

  1. **The current week is drawn but not scored.** A percentage computed from a
     Tuesday is not a fact, and "0 of 3" on a Monday is the app telling you off
     for a week that has barely started.
  2. **A big week cannot pay for a missed one.** Credit is capped at each week's
     target — six sessions then none is not the same as three and three, and a
     number that says it is has stopped measuring consistency.
  3. **Nothing before your first workout counts.** The band is as long as your
     history, up to twelve weeks, so a fresh install does not open on twelve
     failures nobody earned.

  Workouts, not days: two sessions on a Saturday count twice, matching the unit
  `Rotation` has counted since v0.3.1. Every workout mode gets a weekly target —
  a rotation asks for its chosen weekdays, a weekday split for every day it has,
  and every-N-days takes the floor so a 3-workout week on "every 2 days" is not
  a failure.

## Earlier

- [0.3](./docs/changelog/0.3.md)
- [0.2](./docs/changelog/0.2.md)
- [0.1](./docs/changelog/0.1.md)
