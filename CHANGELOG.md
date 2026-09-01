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
