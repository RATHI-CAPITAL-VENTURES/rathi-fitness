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

## 0.6.0 — 2026-09-02

Three things a competitor does well, built in this app's voice rather than
copied: a reason for the tonnage number to mean something, a calendar, and a
record book.

### Added

- **Everything you have lifted.** Lifetime tonnage against a ladder of things
  that weigh a known amount — a grand piano at 1,000 lb, a rhinoceros at 5,000,
  an African elephant at 13,000, a blue whale at 330,000, the Statue of Liberty
  at 450,000, a Space Shuttle at launch at 4.5 million.

  **A number this large means nothing on its own.** "184,800 lb" is not a
  feeling; "past a blue whale, 40 tons short of the Statue of Liberty" is. The
  masses are real and rounded, which is the honest version of a game mechanic —
  330,000 lb is a blue whale because a blue whale weighs about that, not because
  it made a nice curve.

  A registry, not a tier per branch: adding one is a row, and what you have
  passed, what is next and how far are all computed from the table. Progress is
  measured **between** tiers rather than from zero — from 875,000 toward
  2,000,000 a fraction-of-target bar would sit at 44% for a year and look broken.

- **Lifetime totals**: workouts, reps, records.

- **Every day you trained.** Twenty-six weeks as squares, shaded by how much you
  moved, four steps rather than a gradient because a 10pt square cannot carry
  one. **Deliberately not a streak** — `docs/RESEARCH.md` refused those and the
  consistency band replaced them. This shows the same history without a counter
  that resets, so a blank fortnight is visible and is not a failure state.

- **The records you have set, kept.** `records(for:history:)` answers "did this
  set beat anything" at the moment you log it, and then the answer was thrown
  away — the app could tell you something was a record and never mention it
  again. `recordBook` replays history per lift, asking the same question of each
  set against only what came before it.

  **A first-ever set is not a record**, which is a deliberate departure from what
  `records` says in the moment. With no history there is nothing heavier, so it
  reports a best — fine when you are standing there, wrong in a book, where it
  would make adding an exercise worth a badge and a fresh install worth
  thirty-seven of them. Same argument as the tie rule already in `records`: a
  record you get for free teaches you to disbelieve the rest.

### Fixed

- **Counts were formatted as weights.** `Fmt.weight` was doing duty for reps and
  workouts; it is fine at 2,990 and renders twelve thousand as "12300".
  `Fmt.count` groups them.

### Not built, on purpose

- **A streak.** Asked for and declined for the third time — see
  `docs/RESEARCH.md` and the v0.4.0 retro. The heatmap is the honest version.
- **A strength score** ("Intermediate I"). It needs published strength standards
  by bodyweight to mean anything, and a curve invented here would be a number
  with a confident face and nothing behind it.

## Earlier

- [0.5](./docs/changelog/0.5.md)
- [0.4](./docs/changelog/0.4.md)
- [0.3](./docs/changelog/0.3.md)
- [0.2](./docs/changelog/0.2.md)
- [0.1](./docs/changelog/0.1.md)
