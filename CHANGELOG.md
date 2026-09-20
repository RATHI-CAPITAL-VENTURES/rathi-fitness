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

## 0.11.1 — 2026-09-20

### Fixed

- **The auto-installer reported an absent phone as a build failure.** v0.11.0
  merged green while the phone was out of the house, and eight seconds later
  the log said `BUILD FAILED` / `APPLY FAILED` — and would have said it again
  every ten minutes until he got home. The installer's "is the device even
  here?" check trusted the exit code of `devicectl device info details`, which
  is 0 for a paired phone that is miles away; the text says
  `Device State: unavailable`. It reads that now and waits silently, which is
  what the design always said an absent device should do. The code was never
  the problem and the phone was never touched. Shared template 1.0.2 → 1.0.3
  (`deploy/autoupdate`, installed by `bootstrap`); the template's test stub had
  the same wrong assumption as the script, and is fixed with it. If xcodebuild
  itself answers "Unable to find a destination", that is treated as absence
  too, whatever word `devicectl` used; a missing `devicectl` is loud rather
  than silently "not now" for ever; and the state is read in a way that cannot
  lose its answer on a long device report (review found the first version of
  this fix could, past 64 KiB).

## 0.11.0 — 2026-09-20

### Added

- **The trend, at the foot of every exercise.** Under "last three" on the set
  screen: the same stepped line the Trends tab draws, one point per workout,
  with "+10 lb · 3 weeks" beside it. Today's workout is a point on it, so the
  line moves when you log the set. Cardio plots miles if the machine records
  them and minutes if it does not; a bodyweight lift, logged at 0 lb, plots its
  best set of reps rather than a flat line along zero. Absent until there are two workouts to join.
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
  every set. Working sets only now — which also means a lift you have only ever
  warmed up on drops out of the working-weight table instead of listing its
  warm-up as a working weight.
- **The Trends tab labelled everything "lb".** An assisted pull-up read "80 lb"
  there and "lb help" on its own screen. The unit, the chart's padding and
  whether the line steps all come from what is being measured now
  (`Tally.TrendMeasure`), on both screens — body weight included, which was
  three special cases at the call site. The working-weight table judges
  progress by the measure too, and sorts pounds, then help, then reps, rather
  than ranking 25 push-ups against a 30 lb row.

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
