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

## 0.7.0 — 2026-09-04

### Fixed

- **Showing up counted against the wrong thing, and changing your schedule
  rewrote your past.** Two bugs; the second only became visible because the
  first was reported.

  **The target came from the plan, not the schedule.** v0.5.0 made it the number
  of workouts in your plan. On a rotation those are different quantities: you
  cycle N workouts across however many days you train, and with four workouts
  trained three days a week **a full week was unreachable** — the fourth was
  never going to happen, because there is no fourth day to do it on. The number
  could only ever be 75%.

  It comes from the schedule again, capped by the plan, so neither can ask for
  the impossible: four training days against a three-workout plan targets three,
  not a fourth workout that does not exist.

- **A schedule change re-scored every finished week.** Moving from three days a
  week to four turned weeks you had already trained *and already completed* into
  3-of-4 misses, because the target was read live from the one `Schedule`.

  `ScheduleEpoch` records what you were asking of yourself and from when,
  append-only, and each week is scored against whatever was in force while it
  was happening. Editing the schedule writes a row rather than replacing one.

  Only the weekly **count** is kept, because that is all the metric uses —
  showing up is deliberately day-agnostic, so *which* three days is not a fact
  it needs.

### Added

- **Settings › What you were asking of yourself** — the recorded history, each
  target editable.

  Editable is load-bearing, not a convenience: a schedule changed *before* this
  shipped was never recorded, so the oldest entry is a guess made from whatever
  was on disk at migration — which is the new schedule, i.e. exactly the wrong
  one for anybody who just changed it. Nothing in code can know, so it can be
  corrected.

## Earlier

- [0.6](./docs/changelog/0.6.md)
- [0.5](./docs/changelog/0.5.md)
- [0.4](./docs/changelog/0.4.md)
- [0.3](./docs/changelog/0.3.md)
- [0.2](./docs/changelog/0.2.md)
- [0.1](./docs/changelog/0.1.md)
