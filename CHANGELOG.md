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

## 0.5.0 — 2026-09-02

Everything here came from two weeks of actually using the app. Nine reports,
and the pattern in them is worth naming: **five were features that existed,
worked in isolation, had tests, and were wired up wrong or answered the wrong
question.** None was found by the suite.

### Fixed

- **The pull-up assist told you to add help for a good session.** `Tally.nextTarget`
  took `assisted` as a parameter defaulting to `false`, and `SetView` never
  passed it — so three of this plan's exercises got the loaded-machine branch
  and progressed the wrong way, every session, since assisted machines shipped.

  The logic was right the whole time; the call site dropped the flag. It is
  **derived from the sets** now and cannot be passed at all. `Tally.Set` has
  carried `assisted` since v0.2.0 for exactly this reason — "no caller can
  forget to apply it" — and there was already a test named
  `testTheConverterCarriesTheFlagSoNoCallSiteCanForgetIt`, passing, while the
  call site forgot it.

- **Assisted work counted for nothing in tonnage.** It was excluded outright to
  kill a worse bug (counting the *help* as the load, so more help read as a
  better session). The old note called converting it "the same invention that
  keeps push-ups out of tonnage".

  Half right. Guessing is still refused — **no weigh-in, no tonnage** — but
  where a weigh-in exists there is nothing to guess: an assisted pull-up moves
  **bodyweight − help**, measured. Valued at the most recent weigh-in *on or
  before that set*, so last month's tonnage does not move when you step on the
  scale today.

- **"Moved today" compared against the wrong thing**, three ways at once: it
  grouped past sets by calendar **day** rather than by `Session` — the exact
  unit v0.3.1 established everywhere else — matched them by exercise *slug*, so
  Push B's bench counted as "last time you did Push A", and excluded everything
  dated today, leaving the second half of a two-a-day nothing to compare with.

- **Workouts never reached Apple Health.** `sessionsReadyToExport` skipped
  anything dated today, on the reasoning that you might still be in the gym.
  Right question, wrong gate: a workout finished at 09:00 is finished, and the
  only caller ran at **cold launch**, so it landed only if you happened to cold-
  start the app on some later day. The gate is `endedAt != nil` now, and
  finishing a workout syncs immediately.

- **Health synced once per cold launch and never again.** No `scenePhase`
  observer, nothing on finishing a workout — which is why two weigh-ins were on
  record against a scale that writes daily. Both directions now run on
  foreground and on finish, as one `syncNow`.

- **The Mac could not read the snapshot.** The write was `.atomic` into an
  iCloud ubiquity container with **no `NSFileCoordinator`** — atomic replace
  makes a new inode every time, which iCloud sees as delete-then-create, and
  uncoordinated that leaves the other end holding a stale reference or an
  unmaterialised placeholder. Coordinated now. `gym` also handles an evicted
  file instead of reporting it as missing: it finds the `.icloud` stub, runs
  `brctl download`, waits, and says which of the two it actually is.

### Changed

- **Showing up measures coverage, not attendance.** v0.4.0 counted sessions
  against a target derived from the schedule's training weekdays, which on a
  four-workout plan answered a question nobody asked and sat near half of
  whatever you did. It now asks the question you would ask: **how many of your
  workouts did you get round to this week.** Distinct workouts, against the size
  of the plan. Shoulders twice on a Tuesday is one of four — you have not done
  Leg Day by doing Shoulders again — and which weekday you did it on is not a
  fact about consistency.

- **Body weight is a Trends number.** It sat under the workout on Today, where
  it is not something you act on while deciding what to put on the bar. Logging
  a weigh-in moved with it.

### Added

- **Cardio progresses like the weights do.** "Try 2.1 mi — you covered the
  distance last time." Overload stopped at the barbell; a treadmill slot showed
  the same prescription for ever.

  **One dimension at a time.** A treadmill offers four ways to be harder, and
  raising several at once is a different workout rather than progression —
  nothing could be attributed to any of them. It pushes what the plan measures
  you by: distance, else duration, else speed, else grade. Increments are what a
  console actually offers — 0.1 mi, a minute, 0.1 mph, 0.5% — because a
  suggestion you cannot dial in is one you ignore. Miss the target and it
  repeats it rather than raising it.

## Earlier

- [0.4](./docs/changelog/0.4.md)
- [0.3](./docs/changelog/0.3.md)
- [0.2](./docs/changelog/0.2.md)
- [0.1](./docs/changelog/0.1.md)
