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

## 0.17.0 — 2026-10-08

### Added

- **An optional day.** On a day the schedule has nothing, Today offers
  **Start <workout>** — the next workout in the rotation (in weekday mode, the
  next weekday's). Do it and it counts like any workout: the rotation moves on,
  so the next training day gets the one after it. Skip it and nothing moves —
  no miss, no mark, the training days keep the workouts they had. The header
  says "optional day", past workouts say so, and the session is stored as
  `optional`. It does not restart the every-N-days clock: training days stay
  the days they were.
- **Add cardio, on a lifting day.** A **+ Add cardio** under the plan picks a
  treadmill, bike or rower — your machines, the catalogue's, or a new name — and
  logs it on the usual cardio screen. It goes into the workout as an **extra**:
  its own section, never in "N of N done" or the sets planned, never in tonnage,
  always in cardio minutes and miles.
- **Cardio on its own, on a day off.** The same **+** on a rest day starts a
  cardio-only session named for the machine. It moves nothing — not the
  rotation, not the every-N-days clock, not "showing up" — so lifting days keep
  their workouts. A second machine joins the same visit ("Treadmill + Rower").
- **`gym today` on a day off** says what is on offer — "Rest day — optional: Leg
  Day" — and lists cardio done on its own. A workout on a day off reads
  "· optional day"; extra cardio is its own block. `gym sessions` marks
  "(optional)" and "(cardio only)"; `gym volume` reads "4 workouts + 1
  optional".
- **The glasses follow an optional day**, including after the phone relaunches,
  and on a day off Settings → Glasses says what the optional day would be. Cardio
  of either kind is mirrored on the lens the way slot cardio already was.
- **Snapshot (schema stays 8, all additions):** `today.optional`,
  `today.extras[]`, `today.cardio_alone[]`, `rest_day { date, optional,
  cardio[] }`, `sessions[].kind`. `today.optional` reads the session's stored
  kind.
  The CSV export gains `extra` and `workout` columns, at the end.

### Fixed

- **(Review) A ride mid-workout no longer splits the workout.** Logging
  cardio "on its own" while a lifting workout was open closed that workout;
  the next lift opened a second one and the rotation advanced twice. Where a
  bout goes is now one model function (`Workout.cardioHome` / `logBout`), and
  with a workout open the bout joins it as an extra.
- **(Review) "Add cardio" with nothing lifted no longer advances the
  rotation**, and no longer counts as a workout in "showing up" or Trends.
- **(Review) A morning ride stays in `today`** (`cardio_alone`) and in
  `gym today`'s cardio minutes after an evening lift.
- **(Review) Trends' lifetime "workouts" leaves out cardio-only sessions.**
  Their minutes still count.

- **The snapshot had a `today` on a rotation's day off.** It resolved the
  rotation by index and never asked whether today was a training day, so on a
  Saturday `gym today` showed the workout the phone was calling a rest day —
  against SNAPSHOT.md's own "absent on a rest day". It now asks the phone's
  question (`Workout.current`).
- **"Moved today: nothing yet" under a workout that had only cardio in it.**
  Now that a workout can open on an extra bout, the tonnage waits for a lift.

## Earlier

- [0.16](./docs/changelog/0.16.md)
- [0.15](./docs/changelog/0.15.md)
- [0.14](./docs/changelog/0.14.md)
- [0.13](./docs/changelog/0.13.md)
- [0.12](./docs/changelog/0.12.md)
- [0.11](./docs/changelog/0.11.md)
- [0.10](./docs/changelog/0.10.md)
- [0.9](./docs/changelog/0.9.md)
- [0.8](./docs/changelog/0.8.md)
- [0.7](./docs/changelog/0.7.md)
- [0.6](./docs/changelog/0.6.md)
- [0.5](./docs/changelog/0.5.md)
- [0.4](./docs/changelog/0.4.md)
- [0.3](./docs/changelog/0.3.md)
- [0.2](./docs/changelog/0.2.md)
- [0.1](./docs/changelog/0.1.md)
