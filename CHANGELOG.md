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

## 0.11.0 — 2026-09-20

### Added

- **The trend, at the foot of every exercise.** Under "last three" on the set
  screen: the same stepped line the Trends tab draws, one point per workout,
  with "+10 lb · 3 weeks" beside it. Today's workout is a point on it, so the
  line moves when you log the set. Cardio plots miles if the machine records
  them and minutes if it does not. Absent until there are two workouts to join.
  The chart was lifted out of `TrendsView` into `TrendChart` rather than
  redrawn, and both screens read one series (`Tally.liftTrend` /
  `cardioTrend`).

### Fixed

- **An assisted machine's trend plotted your worst set.** The Trends chart and
  the working-weight table each took `.max()` of the day's weights — on an
  assisted pull-up that is the MOST help you needed, so the line rose as you got
  weaker, and the table disagreed with the snapshot, which has always reported
  the least. Both now plot the least help, and taking help off is drawn as
  progress rather than in the colour of a bad month.
- **A warm-up could be the day's point on a chart.** The same `.max()` counted
  every set. Working sets only now.

## Earlier

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
