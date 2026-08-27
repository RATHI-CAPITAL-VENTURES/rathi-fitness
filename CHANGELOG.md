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

## 0.2.2 — 2026-08-27

### Added

- **`WritePathUITests` — every control that writes something, pressed by a
  finger.** There were 18 `context.insert`/`delete` sites in `Views/` and the
  suite reached about four of them; "Add a day" was dead in every release
  through v0.1.1 precisely because nothing had ever pressed it, and any of the
  other fourteen could have been in the same state. The set is finite, so it is
  covered rather than sampled. Each test presses the real control and then
  asserts the row is really there — "the sheet closed" and "the data was
  written" are different claims.

- Nudging a cardio metric is now announced. `SettingsKit.StepperRow` has always
  named its ± pair for VoiceOver; `CardioSetView`'s identical control never did,
  so both read as "button". A real gap, found by a test that could not press
  them either.

### Fixed

- **Buttons you could see and mostly could not press.** Under
  `.buttonStyle(.plain)` a button's hit area is the *opaque* part of its label.
  `PrimaryButton(filled: false)` paints its background `Color.clear`, and
  neither it nor `SecondaryButton` set a `contentShape` — so the tappable region
  was the text glyphs and a one-point stroke rather than the 54-point bar on
  screen. It affected **"Skip to set N", "+30s", "Undo"** and the resting
  **"Done"**: every control you reach for mid-set with a bar in your other hand.
  The three set chips (set type, RPE, note) and the cardio note chip had the
  same defect, and unfilled is their default state.

  Found by CI, which tests iPhone 16 / iOS 18, after passing repeatedly on a
  laptop testing iPhone 17 Pro / iOS 26 — it reproduces on the older runtime and
  not the newer one. `guards.d/dead-controls.sh` now fails the build on a
  `Color.clear` fill with no `contentShape` beside it.

- **A machine dial you added did not appear until you left and came back**
  (iOS 18). `MachineSettingsEditor` read `exercise.settings` — a relationship
  traversal — and a relationship read does not reliably republish when the
  inverse side is inserted. It is a `@Query` now, filtered to the exercise, which
  is what `SetView` and `CardioSetView` have always done; this screen was the one
  place still walking the relationship, and the one place with the bug.

- **The notification-permission ask no longer lands on top of a UI test.**
  Logging a set starts the cooldown, and `RestTimer.start` asks for notification
  permission the first time — which puts a *system* alert over the app, and
  every tap after it goes to the alert rather than the button underneath. It
  never showed up before because no test had ever tapped anything after logging
  a set, and it never showed up locally because that simulator answered the
  prompt weeks ago. Skipped under `RF_UITEST`, the switch `Store` already uses.
  Shipping behaviour is unchanged.

### Found, and not a bug

Beyond the three real bugs above, the sweep turned up **no other dead
controls**. Four of the twelve tests failed
on the first run and every one was the test being wrong about the app, which is
worth recording as a negative result rather than quietly fixing:

- a `ChoiceRow`'s tappable element is its `Menu`, whose label is the *current
  value* — the row's own label sits beside it and matches nothing
- swipe-to-delete lands on the cell, not the text inside it
- the machine dial is called "Seat", not "Seat height"
- a single cardio bout **dismisses the screen** (`log()` ends
  `else if isFinished { dismiss() }`), so undo is reached by going back in — a
  deliberate choice, so a cooldown does not strand you beside a treadmill
- a `DisclosureRow`'s tappable element is the label inside it, not a button
- the dials are three levels deep (plan → day → exercise → dials), so one step
  back from them is the exercise

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
