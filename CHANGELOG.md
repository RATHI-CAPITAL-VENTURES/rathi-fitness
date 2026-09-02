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

## 0.4.5 — 2026-09-02

### Changed

- **The sans is Inter, not General Sans — a licence change, not a taste one.**
  General Sans ships under the Fontshare EULA, which says the fonts may not
  *"be distributed, duplicated, loaned, resold or licensed in any way … This
  includes … uploading them in a public server"*. This repo is going public, so
  shipping those three `.ttf` files in it would breach that, and **deleting them
  from the tree would not be enough** — a public repo exposes every blob in
  history, so they are purged from history too.

  Inter is SIL OFL 1.1, redistributable with its licence file, which sits beside
  it in `Resources/Fonts/`. It is also the better face for the job rather than
  merely a legal one: it was drawn for user interfaces at small sizes, and the
  whole of what the sans does here is 11–15pt chrome meant to recede behind the
  numbers. Fraunces is untouched — already OFL, and it is the voice.

  `design/ios-first-pass.html` embedded the same three faces as base64, so it
  was a second copy being published. Re-embedded with Inter, **subset to the 109
  glyphs the mock actually renders** so the file went to 499KB rather than the
  1.8MB a full embed would have cost.

## 0.4.4 — 2026-09-02

### Fixed

- **The `pr-title` guard did nothing locally, which is where it was needed.**
  CI sets `PR_TITLE`; `make guards` does not — so the guard printed
  *"✓ no PR_TITLE in the environment — skipping"* and exited 0 on every local
  run. The one guard covering PR metadata was invisible to the command that
  exists precisely so you do not have to push to find out.

  Three PRs (#9, #11, #12) went out with the version on the **wrong end** of
  the title — `feat: a thing (v0.4.1)` where this repo wants
  `v0.4.1 feat: a thing`. All three were single-commit, so GitHub squashed with
  the commit subject and **the wrong format is on `main` permanently**. The
  guard says exactly this in its own error message; nothing local ever ran it.
  Actions billing was down at the time, so nothing else caught it either.

  It now resolves what GitHub will actually use, in the order those become
  true: an open PR's title, else a single-commit branch's subject — which is
  checkable **before** the PR exists. A multi-commit branch with no PR still
  skips, because nothing has decided the squash subject yet, but it says that
  in those words rather than implying it ran.

  This is the same failure the repo already documented once at v2.30.3 of RIA —
  *registering a guard is not the same as running it* — one level further in:
  the guard was wired into CI **and** into `make guards`, and still could not
  fail on a developer's machine.

  Six new cases in `guards.test.sh`, including the two that matter: no
  `PR_TITLE` catches a bad subject, and no `PR_TITLE` passes a good one.

## 0.4.3 — 2026-09-02

### Changed

- **The suite is 5:39 instead of 7:54, and the inner loop is 53 seconds.**
  `make test-unit` runs the 139 unit tests on their own; `make test-ui` runs the
  22 UI tests in parallel; `make test` runs both, in that order.

  The measurement first, because it changed the plan. The unit bundle is **2.5
  seconds** of actual testing. All of the time is UI, and 311 of those 428
  seconds were in **one class** — `WritePathUITests`, 15 tests. XCTest
  parallelises by CLASS and nothing finer, so simply turning parallelism on made
  it **slower** (>10:00): four simulator clones booted so that three could sit
  idle behind one long class.

  So `WritePathUITests` is now five classes sharing a `WritePathCase` base,
  grouped along the `// MARK:` sections it already had. That is the change that
  makes parallelism pay.

- **The unit and UI bundles no longer run at the same time.** Two `xcodebuild`
  invocations, and that is the fix rather than a preference: with four UI clones
  hammering the audio server, `HandsFreeTests` hits the CoreAudio `abort()` of
  v0.3.3. Marking the unit target `parallelizable: false` does **not** help —
  the contention is machine-wide. Only not overlapping them does.

- **CI runs `make`.** It had its own hand-rolled `xcodebuild test`, so the
  Makefile could grow a split that CI never got. Only the destination, the
  toolchain and `PARALLEL` are overridden now, and unit and UI are separate
  steps so a unit failure reports without waiting for the UI bundle.

- **Parallelism is a knob with a measured default, not a belief.** `PARALLEL=NO`
  on CI. A macos runner has about three cores, and with three clones the UI step
  **alone** took 19:26 — against a whole job, build included, of about 16:00
  before any of this. The same flag on a ten-core Mac takes the suite from 7:54
  to 5:39. The first version of this change shipped `WORKERS=3` to CI and made
  it *slower*; the number above is why it does not any more.

  **Stated plainly rather than sold: CI got slightly slower, 16:00 → 17:36.**
  Two invocations each pay their own simulator boot, and a runner has no cores
  to win it back with. What CI buys for that 1½ minutes is the unit result at
  **3:43 instead of 16:00** — a compile error or a broken assertion no longer
  waits behind thirteen minutes of UI. The local numbers (7:54 → 5:01) are where
  the actual speed is, which is where the complaint was.

### Fixed

- **`AudioHub.say` was the audible path v0.3.3 missed.** That release gated
  `activate`, `play` and `holdRemoteControl` on `isEnabled` and named them;
  `say` reaches `AVSpeechSynthesizer` rather than the engine, so it did not look
  like a fourth. It is.

- **`engineRunning` asked the engine whether it was running.** Reading
  `engine.isRunning` is itself enough to make CoreAudio rebuild the remote IO
  unit — so the guard that `play` and `holdRemoteControl` both sit behind had
  already done the thing it existed to prevent. It checks `isEnabled` first now,
  and `&&` short-circuits.

- **The unit bundle could not be run on its own.** `-only-testing:RathiFitnessTests`
  crashed `HandsFreeTests.testAnnounceUsesTheScreensOwnSentence` and
  `testASqueezeWithNoWorkoutOnScreenLogsNothing` — on `main`, before any of this.
  It was invisible because nothing had ever run that bundle alone: the two tests
  reach `say` and `refuse()`, and both now silence audio the way their
  neighbours in that file already did.

- **A passing run reported as a failure.** `xcode-select -p` here is
  CommandLineTools, which has no `simctl`, and xcodebuild shells out to
  `xcrun simctl` for end-of-run diagnostics. `DEVELOPER_DIR` was set as a command
  prefix, which did not reach that nested `xcrun`; it is exported now.

## 0.4.2 — 2026-09-01

### Fixed

- **The seed dated "six weeks of history" to this morning.**
  `Seed.mostRecent` computed `delta = weekday - today` and shifted back only
  `if delta > 0` — so when the seeded weekday **was** today, `delta` stayed `0`
  and a "historical" workout landed at 06:45 **today**. History that includes a
  session you have not done yet, sitting in the same day as whatever you log
  next.

  It only collides on the three weekdays the plan trains — Monday, Wednesday,
  Friday — so the suite passed four days a week and failed three, and *which*
  you saw depended on the timezone of the machine running it. A Mac on EDT and
  a runner on UTC disagree about the weekday for four hours every night.

  On CI (Wednesday, 02:31 UTC) it broke two tests with arithmetic that names
  the cause exactly: `SnapshotTests.testSetKindsAndRpeReachTheSnapshot` saw
  volume **6660** where it wanted 1480 — the seeded Push A bench is
  `185 × (8+7+7+6) = 5180`, plus the test's own `185 × 8` — and a reps array of
  **5** where it wanted 1, being the 4 seeded sets plus the working one.
  `WorkoutFlowUITests` then opened the set screen on an exercise that was
  already four sets in, so the plate math for 185 was not on screen.

  `>= 0` now, and history means the past.

- **`Seed.run(_:now:)` had a `now` nothing ever passed.** Every caller took the
  default, so the seed was only ever exercised on whichever weekday the run
  landed on — which is why a date bug survived in a covered function. The new
  `SeedTests` pin the date and walk a whole week, so all seven are checked on
  every run rather than one at random.

  The first version of that test built its Wednesday in **UTC**, matching the
  timestamp on the CI failure, and passed against the unfixed code: 02:00 UTC
  Wednesday is 22:00 EDT Tuesday, so `Calendar.current` read it as a Tuesday
  and the assertion agreed with itself about nothing. It builds dates in the
  current calendar now — the same ambiguity as the bug, one level up.

## 0.4.1 — 2026-09-01

### Added

- **Reset every rest at once.** Settings › New exercises › **Apply rest to the
  whole plan** pushes the Rest dial through every strength slot on every day.

  That section has refused to touch an existing plan since it shipped, and the
  footer said so — *nothing already in the plan changes*. The refusal is right:
  a default that silently rewrites your programme is a default you stop
  trusting. But it left no way to do the thing **on purpose** either, so
  changing your mind about rest meant opening every slot on every day and
  turning the same dial. The fix is an explicit act, not a looser default.

  It applies the number set directly above it rather than offering a picker of
  its own — a second place to declare one thing is a second place to forget it.

  **Cardio is left alone, and that is what makes a blanket write safe.**
  `restSeconds` on a cardio slot is the gap *between intervals*, a different
  quantity that happens to share a field, and the plan editor creates every
  treadmill slot with `0`. Including them would not reset a rest; it would
  invent intervals nobody asked for, on rows whose rest column reads "—". A
  cardio slot that *does* carry an interval rest was set by hand, which is
  precisely what a bulk action must not eat. The exclusion lives in
  `slotsTakingPlanRest` with the reason written beside it.

  Three things the confirmation does rather than ask you to trust:

  1. **It names the count** — "Set 8 exercises" — from the same query that does
     the write, so the number cannot drift from the act.
  2. **It reports what changed, not what it inspected.** A slot already at the
     value is not a write, so a second tap says *"Every exercise was already at
     1:30"* instead of claiming eight more.
  3. **It says cardio is excluded** in the message, rather than leaving you to
     diff your own programme to find out.

  Not undoable, and the message says so.

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
