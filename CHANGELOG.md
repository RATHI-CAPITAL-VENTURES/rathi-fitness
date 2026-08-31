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

## 0.3.2 — 2026-08-30

### Fixed

- **The cooldown ping could not be heard over your own music.** Three defects,
  and they only line up when music is playing, which is why nothing caught them.

  1. **You cannot duck yourself.** `MusicController` uses
     `ApplicationMusicPlayer`, which renders through the app's *own* audio
     session, and `AudioHub` sets `.duckOthers` — which ducks **other apps**. A
     podcast dropped under the ping; our own track did not, so a 45 ms sine at
     gain 0.30 sat far under it. Cues are now normalised on render and get a
     separate, much louder render while our own music is playing.
  2. **The notification was suppressed exactly when it was needed.** There was no
     `UNUserNotificationCenterDelegate`, so iOS showed nothing while the app was
     frontmost — which is where you are during a rest. It is presented now, but
     only when the app cannot make the sound itself.
  3. **The gate asked the wrong question.** `content.sound` was decided by
     `isHoldingRemoteControl`, which is `false` precisely when music is playing
     (`arm()` only holds silence when nothing real is). It asks
     `AudioHub.willSoundCues` now — "will the app actually chime" — so exactly
     one channel speaks.

- **A cue after connecting AirPods was silent.** `engineRunning` was a stored
  flag set once and cleared only at teardown, and nothing watched
  `AVAudioEngineConfigurationChange`. A route change stops the engine; the flag
  kept saying `true`, so every later cue was scheduled into a dead engine. The
  engine's own `isRunning` is the truth now, and the engine is rebuilt on a
  configuration change and after a call interruption.

- **`restOver` clipped on a loud setting.** Its second and third notes overlap
  and summed past 0.8 before the user's volume was applied. Normalising fixed it
  as a side effect, and the test that claimed "renders without clipping" now
  measures instead of only checking that `play` did not throw.

## 0.3.1 — 2026-08-30

Clears every follow-up v0.3.0's retro left `blocked:`. All three were readable
as "I'd rather do it later", which is the one thing `blocked:` is not for.

### Fixed

- **`gym today` on the Mac disagreed with the phone in your pocket.**
  `Snapshot.today` picked the planned day whose `weekday` matched, which is only
  right in `.weekday` mode; on a rotation the phone uses `Rotation.index` and the
  pairing drifts on purpose. It had been wrong since rotations shipped. It also
  indexed into an **unsorted** `PlannedDay` fetch, so the first rotation-aware
  version was still wrong — caught by a test rather than by reading. A workout in
  progress now beats the cycle's guess, which is also how the second half of a
  two-a-day reads correctly.

- **A two-a-day was one point on every Trends chart**, taking the heavier of the
  two workouts and hiding the other. Both charts already said "one point per
  session" in their own comments and grouped by `startOfDay`, because a day was
  all there was to group by.

- **The swipe-back pager showed a day, not a workout** — two workouts' exercises
  run together on one page with their volumes added. `PastDayView` takes a
  `Session` now, which also deleted the code that guessed the workout's name from
  its exercises: it is recorded when you do it.

- **The launch backfill ran before the demo-history loader**, so sample data got
  no sessions — and a set with no session is invisible to the pager and to
  Trends. It now runs after everything that writes sets at launch, with a note
  saying why the order matters.

- **`cli/gym`'s own tests were left on schema 4** by the v0.3.0 bump. CI caught
  it; I had changed `cli/gym` without running them. The fixture is schema 5 and
  now carries a real two-a-day.

- **"1 sessions"** in the volume table, which has read that way since the command
  shipped.

## 0.3.0 — 2026-08-29

### Added

- **Two workouts in a day.** There was no way to say that: a session was
  *inferred* by grouping `SetEntry.date` on `startOfDay`, in around thirty
  places. `Session` is now a real record — when it started, when it ended, and
  which workout it was — and a set belongs to one.

  A session opens on the first set logged against a given planned day, and
  opening one closes any other. **Deterministic, not a clock.** A gap heuristic
  was rejected: it is wrong in both directions on exactly the days that matter —
  a long workout with a break in it splits, a lift straight into cardio merges.

  Today says "workout 2" when it is, and the calendar menu offers **Finish
  &lt;workout&gt;** once one is open — which is also how you do the *same*
  workout twice, since sessions are keyed by the planned day.

### Fixed

- **Two-a-days reached Apple Health as one twelve-hour workout**, min→max across
  every lifting set on the date, with a pace and a calorie figure computed over
  the eleven hours you were at work. Two workouts now go over as two.
- **The rotation advanced once for two workouts**, so the next day offered the
  one you had already done. It counts sessions now — while twenty sets in a
  single workout still advance it once, which is the property the old
  day-counting had right.
- **An evening lift continued the morning's set numbering** — set 5 of 4, pips
  overflowing, and a record judged against a bout that finished eight hours
  earlier.
- **The second workout opened with the first one's checklist already ticked**
  wherever the two shared an exercise.
- **`sessions[].day` was guessed from the weekday**, so a workout done out of
  order was labelled with whatever the plan had on that weekday. It is the name
  recorded when you did it.

### Changed

- **Snapshot schema 4 → 5.** `sessions[]` is one *workout*, not one date, so
  **two entries can share a `date`** — a reader keying on `date` alone merges a
  two-a-day back together. `started_at` / `ended_at` (`HH:mm`) and `ordinal` tell
  them apart. `cli/gym` reads 5 and shows the time and ordinal when there is
  more than one.
- Existing history is backfilled at launch, one workout per day — exactly the
  assumption the old code made, so nothing is invented — named from whichever
  planned day its exercises best match, or `Workout` when nothing does.
  Idempotent, so it is a launch step rather than a flag that can be lost.
- A set that somehow has no session (CloudKit can deliver rows from a device on
  an older build) still reaches the snapshot, grouped by day. Dropping it would
  lose a day of training from the Mac's view silently.

## Earlier

- [0.2](./docs/changelog/0.2.md)
- [0.1](./docs/changelog/0.1.md)
