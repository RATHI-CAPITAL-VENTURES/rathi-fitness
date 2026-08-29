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

## 0.3.0 — 2026-08-29

### Added

- **Two workouts in a day.** There was no way to say that: a session was
  *inferred* by grouping `SetEntry.date` on `startOfDay`, in around thirty
  places. `Session` is now a real record — when it started, when it ended, and
  which workout it was — and a set belongs to one.

  A session opens on the first set logged against a given planned day, and
  opening one closes any other. **Deterministic, not a clock.** A gap heuristic
  was rejected: it is wrong in both directions on exactly the days that matter —
  a long workout with a break in it splits, a lift straight into cardio merges.

  Today says "workout 2" when it is, and the calendar menu offers **Finish
  &lt;workout&gt;** once one is open — which is also how you do the *same*
  workout twice, since sessions are keyed by the planned day.

### Fixed

- **Two-a-days reached Apple Health as one twelve-hour workout**, min→max across
  every lifting set on the date, with a pace and a calorie figure computed over
  the eleven hours you were at work. Two workouts now go over as two.
- **The rotation advanced once for two workouts**, so the next day offered the
  one you had already done. It counts sessions now — while twenty sets in a
  single workout still advance it once, which is the property the old
  day-counting had right.
- **An evening lift continued the morning's set numbering** — set 5 of 4, pips
  overflowing, and a record judged against a bout that finished eight hours
  earlier.
- **The second workout opened with the first one's checklist already ticked**
  wherever the two shared an exercise.
- **`sessions[].day` was guessed from the weekday**, so a workout done out of
  order was labelled with whatever the plan had on that weekday. It is the name
  recorded when you did it.

### Changed

- **Snapshot schema 4 → 5.** `sessions[]` is one *workout*, not one date, so
  **two entries can share a `date`** — a reader keying on `date` alone merges a
  two-a-day back together. `started_at` / `ended_at` (`HH:mm`) and `ordinal` tell
  them apart. `cli/gym` reads 5 and shows the time and ordinal when there is
  more than one.
- Existing history is backfilled at launch, one workout per day — exactly the
  assumption the old code made, so nothing is invented — named from whichever
  planned day its exercises best match, or `Workout` when nothing does.
  Idempotent, so it is a launch step rather than a flag that can be lost.
- A set that somehow has no session (CloudKit can deliver rows from a device on
  an older build) still reaches the snapshot, grouped by day. Dropping it would
  lose a day of training from the Mac's view silently.

## Earlier

- [0.2](./docs/changelog/0.2.md)
- [0.1](./docs/changelog/0.1.md)
