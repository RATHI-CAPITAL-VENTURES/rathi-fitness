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

## 0.1.1 — 2026-08-24

### Fixed

- **Health had to be reconnected every time the app closed.** `status` started
  each launch at `.notAsked` and only ever became `.connected` in memory, so
  quitting forgot it. Settings offered "Connect Apple Health" again, and the
  launch sync — gated on `isConnected` — silently stopped importing weigh-ins
  until you tapped the button. The permission was fine the whole time; nothing
  ever asked whether it existed.

  `HealthBridge.resume()` now asks on launch and when Settings opens. It uses
  `getRequestStatusForAuthorization`, which answers "would asking show a sheet"
  rather than "am I authorised" — HealthKit refuses the latter for read types on
  purpose, because the answer would leak what is in your Health app.

## 0.1.0 — 2026-08-24

The first pass, and everything since. Recorded as one entry because the repo
predates this changelog — from here each change gets its own.

### Added

- **The app.** Four screens — Today, Trends, Pass and the set screen — in
  SwiftUI on SwiftData + CloudKit, with the cooldown ring, plate math, records
  and tonnage.
- **Rotating programmes.** Fixed training days with cycling workouts; position
  in the rotation is derived from the sessions you logged, never stored.
- **Set kinds, RPE, supersets and muscles.** A warm-up stopped counting toward
  volume and records.
- **Cardio.** Treadmill, bike, rower and the rest, with time, distance,
  incline, speed, resistance and heart rate — each machine offering only the
  numbers its own console has. Measured in minutes, never converted to tonnage.
- **Machine settings.** "2 on the leg press", kept with the exercise and
  readable from the Mac with `gym machines`.
- **Assisted machines.** Where the weight makes it easier, every judgement
  about the number runs the other way.
- **The cooldown ping.** Authored haptics and synthesised tones, both channels
  every time.
- **Music and hands-free.** Apple Music played by the app, so AirPods gestures
  reach it — triple-press logs the set.
- **Apple Health.** Weigh-ins in, workouts out, cardio as its own activity type.
- **The snapshot** (schema 4) and the `gym` CLI that reads it on the Mac.
- **Swipe left on Today** for past sessions, read-only.

### Changed

- Settings, the plan editor and the machine settings editor are drawn from
  `Views/SettingsKit.swift` rather than a stock `Form` — they were the only
  screens that did not look like the app.
- The icon carries RIA's face, from the shared kit in the RIA repo, and ships
  the full iOS size ladder.
