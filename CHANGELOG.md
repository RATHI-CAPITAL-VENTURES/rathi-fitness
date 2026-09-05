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

## 0.9.0 — 2026-09-05

### Added

- **Time away.** Settings › Time away: declare a trip, before you go or after
  you are back, and any week it touches leaves showing up entirely.

  **Neither counted as done nor counted as missed.** Not marked complete —
  "you did your four workouts" is a claim about something that did not happen,
  and a band full of invented full weeks is worth less than one with honest
  gaps. Just taken out of the reckoning, numerator and denominator both.

  Until now a fortnight abroad read exactly like a fortnight of not bothering,
  and the percentage carried that for three months.

  **Training on holiday still shows, greyed.** It cannot move a number that has
  been set aside, and doing it anyway deserves to be visible — a bonus, not a
  score. Away weeks are drawn grey rather than left empty, because empty reads
  as "you missed it", which is the one thing declaring a trip exists to stop the
  band saying.

  **Per week**, because that is the unit the band measures in. Pro-rating a
  target that counts whole workouts would ask for 2.3 of them, and a
  half-scored week is harder to explain than one that plainly does not count.
  The caption says how many weeks were set aside, so the denominator never
  shrinks for a reason nothing on screen explains.

  This was reserved rather than invented: v0.4.0 rejected "a weekly streak with
  a declarable week off" and noted the week-off half as the next thing to try,
  costing a model, a snapshot field and a CLI read. That is exactly what it
  cost.

### Changed

- **Snapshot schema 5 → 6.** `time_away[]` carries the declared trips, so the
  Mac can subtract them too — anything reading `sessions[]` to judge consistency
  draws the wrong conclusion without them.

### Fixed

- **A CLI test asserted the schema number as a literal**, so every bump broke it
  and the fix was to retype the number — a test that could only ever agree with
  whoever edited it last. It reads `Snapshot.currentSchema` out of the Swift
  now, so bumping one side without the other actually fails.

## Earlier

- [0.8](./docs/changelog/0.8.md)
- [0.7](./docs/changelog/0.7.md)
- [0.6](./docs/changelog/0.6.md)
- [0.5](./docs/changelog/0.5.md)
- [0.4](./docs/changelog/0.4.md)
- [0.3](./docs/changelog/0.3.md)
- [0.2](./docs/changelog/0.2.md)
- [0.1](./docs/changelog/0.1.md)
