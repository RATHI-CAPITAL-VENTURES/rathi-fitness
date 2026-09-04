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

## 0.8.0 — 2026-09-04

### Added

- **Your journey — the whole ladder, and when you crossed each tier.** Tap the
  legacy line on Trends. Passed tiers are lit with **the date you passed them**;
  the next one says how far; the rest are dimmed.

  The date is the **session that took you past it**, which is the only honest
  answer — a tier is not crossed on the day you happened to open the app.
  Sessions rather than sets, because a tier crossed mid-workout belongs to that
  workout, and splitting a session across the line would date a milestone to a
  set nobody remembers.

  Locked tiers are dimmed rather than hidden or silhouetted: seeing what a Space
  Shuttle badge looks like is most of the reason to want one. Only the *next*
  one quotes a distance — every locked tier naming how far away it is turns a
  ladder into a list of things you have failed to do.

- **Fifteen generated badges**, one per tier, replacing the SF Symbols —
  `tortoise.fill` had been standing in for a rhinoceros, a hippopotamus and an
  elephant.

  Drawn to one prompt so they read as a set, then post-processed: the model was
  asked for pure black and gave several a faint grey field, so anything that
  dark is clamped and **made transparent**. Opaque black would have been worse
  than the symbols — the app's background is a tinted `RoomBackground`, so each
  badge drew its own black square on top of it. That is exactly what shipped in
  the first pass, and it is visible in a screenshot in a way no test would catch.

### Fixed

- **The Trends picker offered four tiles when there were twenty-four lifts.**
  `featured` was `.prefix(3)` plus Body, so all but three logged exercises were
  unreachable — while the working-weight table below listed every one of them.
  The row is a horizontal `ScrollView`; it could always have held them.

- **`2250.0 tons`.** A tenth of a ton is 200 lb. It is a real distinction at
  184.8 and a decimal point pretending to mean something at 2,250, so tonnage
  keeps one place under a thousand tons and drops it above — and never renders a
  whole number as `70.0`.

## Earlier

- [0.7](./docs/changelog/0.7.md)
- [0.6](./docs/changelog/0.6.md)
- [0.5](./docs/changelog/0.5.md)
- [0.4](./docs/changelog/0.4.md)
- [0.3](./docs/changelog/0.3.md)
- [0.2](./docs/changelog/0.2.md)
- [0.1](./docs/changelog/0.1.md)
