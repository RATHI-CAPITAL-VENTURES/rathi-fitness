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

## 0.2.1 — 2026-08-27

### Added

- **`guards.d/dead-controls.sh`** — the build now fails on the three shapes that
  produced a button which drew and did nothing: `.allowsHitTesting(false)` in a
  view, an interactive row (`ActionRow`, `ToggleRow`, `ChoiceRow`, `StepperRow`,
  `TogglePill`, `DisclosureRow`) used as another control's label, and an empty
  action closure. Its self-tests run the real broken `PlanView` from `f16e454`
  through it, so the guard is pinned against the bug it was written for rather
  than a synthetic one.

- **`ActionRowLabel`** — an action row's appearance with no button around it,
  for a row that has to sit inside something already interactive. A guard that
  bans a shape without offering the alternative gets an exempt label the first
  time somebody is in a hurry, so the alternative ships with it.

### Changed

- `ActionRow` is now that label wrapped in a `Button`. Identical to draw; the
  point is that the two halves can be used apart.

### Why

"Add a day" was dead in every release through v0.1.1, and it was a *visual*
refactor that killed it — `f16e454` swapped a passive `Label` for an `ActionRow`
without touching the action above it. The action is unchanged and correct in
that diff, and the row renders perfectly, so neither review nor a screenshot
could catch it. Only a finger could.

`docs/DECISIONS.md` records the reviewing question that would have: not "is the
action still right" but "did anything passive become interactive".

## 0.2.0 — 2026-08-27

### Added

- **A write that doesn't land now says so.** `Model/Saving.swift` is the one
  place that decides what a failed save does: a `.fault` to the unified log
  (subsystem `com.rathi.fitness`, category `saves`), a banner over every tab
  telling you which change is gone, and a `false` for any caller with something
  better to do. `SaveFailureBanner` is the user-facing half.

- **`guards.d/silent-saves.sh`** — the build fails if `try? context.save()` or
  `try? Seed.*` comes back. Structural, like the other project guards, and
  narrow: `try?` on the haptic engine, the audio session or a `Task.sleep` is
  correct and is left alone. Six self-test cases in `guards.d.test.sh`.

### Changed

- **All 21 silent saves are named.** `try? context.save()` became
  `context.saveOrReport("adding a day")`, where the phrase completes the
  sentence "save failed while ___" — so the banner says which change you lost
  rather than that "saving" failed. `SavingTests` reads every call site back out
  of the source and fails the build on a phrase that degrades to "saving".

  `try? Seed.deleteAllHistory`, `try? Seed.runIfNeeded`, `try? Seed.loadDemoHistory`,
  `try? Seed.removeDemoData` and `try? Export.write` had the same hole one level
  up and go through `reportingFailure("…") { … }`.

### Why

Reported as "I tried to add a day 4 but it wouldn't let me". The cause was a
dead button (fixed in 0.1.2) — but the natural next step, streaming the phone's
logs while it was pressed, turned out to be impossible: there was nothing on
that path to stream, and a genuine save failure would have been just as quiet.
The button was one bug; having no instrument to find it was another.

See [`docs/retros/2026-08-27-silent-saves.md`](./docs/retros/2026-08-27-silent-saves.md).

## Earlier

- [0.1](./docs/changelog/0.1.md)
