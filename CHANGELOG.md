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

## 0.6.4 — 2026-09-04

### Fixed

- **The auto-update agent could not read its own config.** The spine sources
  `autoupdate.conf` and runs the apply hook as a **child process**, and a plain
  `.` leaves values set but not exported — so every `AU_IOS_*` value stayed in
  the spine's shell. The hook died on its first required variable and the agent
  logged `APPLY FAILED` for v0.6.3, which was a perfectly good commit.

  Fixed upstream in RIA's template (**1.0.0 → 1.0.1**, RIA v2.41.3) and pulled
  in here, which is the point of it being a template. Caught within the hour, by
  the agent it was written for, on its first real run.

## 0.6.3 — 2026-09-04

### Changed

- **Auto-update now comes from the shared template.** v0.6.1 built it here; the
  generic half is upstream in RIA's `templates/autoupdate` (v2.41.2), so this
  repo keeps `autoupdate.conf` — its device ids, its scheme, its log path — and
  nothing else. `bin/rf-autoinstall.sh` and its test are gone.

  The split the template makes: the **spine** is the git safety, the logging and
  the record of what is live, identical in every project. What "apply" means is
  a hook. `apply.d/ios.sh` builds and installs to a paired device and returns
  **"not now"** when the device is away or the app is open, and the spine
  believes it — same refusal as before, now written once.

  Verified on a second project on the way: `rathi-budgeting` took the same
  template and installed to the phone on its first run.

  `make autoinstall-install` / `-uninstall` / `-status` / `-test` are unchanged.
  The log moved to `~/Library/Logs/rathi-fitness/autoupdate.log`.

## 0.6.2 — 2026-09-04

### Changed

- **`make test` uses two parallel workers, not four.** Four was measured on a
  quiet machine (4:40) and then flaked on a real one: a UI test that takes 21s
  alone took **67s** under four simulator clones and blew its
  `waitForExistence`, and three different tests failed across two runs. Two
  workers ran green twice at 5:19 and 5:21 on a Mac also running a camera app,
  a browser and Spotlight — which is what this machine actually looks like.

  A suite that flakes costs more than the three minutes it saves: every red run
  has to be re-run to find out whether it meant anything, and shipping v0.5.x
  spent two doing exactly that. The default is the number that is reliable under
  load, and `WORKERS=4` is still there for a quiet machine.

- **Shipping guards upgraded to template 1.1.0** (RIA `templates/ci`). This
  project's copy was the source of the fix — `pr-title` printed a `✓` and
  checked nothing outside CI — and is now identical to the template again
  rather than a fork of it. `guards.conf` is untouched; only shared logic moved.

## 0.6.1 — 2026-09-04

### Changed

- **The training week starts on Monday.** Both the heatmap and the consistency
  band took `Calendar.current`, which is Sunday-first in the US — so the week
  was cut through the middle of a weekend and a Saturday-and-Sunday pair landed
  in two different weeks. Nobody thinks about their training week that way.

  Forced inside `Tally.activity` and `Tally.consistency` rather than left to the
  caller, because the failure is silent: hand either one a plain `Calendar` and
  everything still computes, against the wrong seven days. Only `firstWeekday`
  is overridden — the timezone and locale that come in are the user's.

  **Showing Up percentages will shift slightly**, because the weeks they are
  counted in have moved.

- **The heatmap says which row is which day** — M T W T F S S down the side. A
  grid of squares with no labels is a texture: you cannot tell "always trains
  Monday" from "always trains Thursday" by looking at it.

### Added

- **Auto-install to the phone.** `make autoinstall-install` turns on a launchd
  agent that polls `origin/main` every ten minutes and, when it moves, builds
  and installs over Wi-Fi.

  This is the `app/` half of what RIA's auto-deploy does for the server, and it
  exists because that one deliberately does not touch native faces — an `app/`
  change could be merged, green, and still not on the phone.

  **It never interrupts a workout.** If the app is open on the phone it skips
  and tries again: installing over a running app terminates it, and losing a set
  to a background job is a much worse bug than being one commit behind. It acts
  only on a clean `main`, refuses a diverged remote rather than resetting, and
  builds before touching the device so a broken commit leaves the phone with the
  build it had.

  Sixteen self-tests against a throwaway repo and stub tools —
  `make autoinstall-test`. Two of them found real bugs while being written: the
  running-app check grepped for the bundle id, which `devicectl` never prints
  (it lists executable paths), so the guard could not fire; and the script's
  hardcoded launchd `PATH` made everything past `xcodegen` unreachable from a
  test.

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
