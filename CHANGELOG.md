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

## 0.8.2 — 2026-09-04

### Fixed

- **The Eiffel Tower was eight times too light, and in the wrong place.**
  Entered at 2,000,000 lb and sitting *below* the Space Shuttle. The tower's
  puddle iron is about 7,300 tonnes — roughly **16 million lb** — so it belongs
  above it. A ladder whose whole premise is that the masses are real cannot
  carry a figure that wrong.

### Changed

- **The ladder no longer ends.** It stopped at a Space Shuttle, which at four
  sessions a week is about **eighteen months** — after which the screen said
  "you have lifted everything on the list" and had nothing further to say, for
  the rest of your training life. Measured against this plan's real rate of
  ~2.7M lb a year, nine of the fifteen tiers were already passed and the top was
  a year and a half out.

  Five more, and the heavy end is deliberately absurd and still real: the
  Titanic, a Nimitz-class carrier, the Empire State Building, the Golden Gate
  Bridge, and the Great Pyramid of Giza — some four thousand years away at that
  rate. Nobody reaches it, which is the point.

  **Rejected: a generated tail.** Once the named tiers ran out it could have
  counted in multiples — "two Great Pyramids", "three Great Pyramids" —
  provably infinite and pure filler. A made-up rung is exactly what this ladder
  refuses to be, and nobody gets there to see it either way.

  Five new badges in the locked style.

### Added

- **`docs/LADDER.md`** — the three rules (every mass is real, it never ends, it
  only ever climbs), how to add a tier, the badge prompt and why the artwork
  must be post-processed to transparency, and the full table with what each
  figure actually refers to.

  Also three new tests: fifty years of training must not exhaust the ladder, the
  Eiffel Tower must outweigh a Space Shuttle, and no step below a million pounds
  may be more than a 10× jump — a rung you cannot aim at is not a rung.

## 0.8.1 — 2026-09-04

### Fixed

- **The auto-update agent could collide with itself.** launchd fires on a
  schedule whether or not the last run finished, and an Xcode build outruns a
  ten-minute tick easily. Two instances shared a derived-data path and
  `xcodebuild` died with *"database is locked … two concurrent builds running in
  the same filesystem location"* — reported as `APPLY FAILED` for v0.8.0, which
  was a perfectly good commit.

  Fixed upstream (RIA template **1.0.1 → 1.0.2**, RIA v2.41.4): an atomic lock
  holding the owner's pid, so a second instance stands down quietly and a stale
  one is taken over rather than blocking the agent for ever.

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
