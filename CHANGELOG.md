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

## 0.14.0 — 2026-09-21

### Added

- **The lens runs the workout.** With no exercise open on the phone, your
  glasses show **today's exercises as a list**. Swipe your thumb to move, pinch
  to open one. What you are part-way through comes first, then what is left in
  the plan's order, then what is done — because the first row is the one that
  arrives lit, so the usual case is a pinch and no swipe.
- **A card before the first set**: what to lift, how many sets, the rest, and
  **where the seat goes** — the thing you need before you start. *Start ·
  Taken · Back.*
- **Then the loop the phone has**, without the phone: *Log set*, the rest clock,
  and after the last set **what is next, already lit**. It skips to the next
  unfinished lift and wraps, so passing on a busy rack and coming back works.
- **−1 rep.** The lens cannot type, but "I got seven, not eight" is the
  correction a set most needs. It is about the set in hand; the next one opens
  on the plan again.
- **Taken.** The machine is busy: the lens offers what could stand in — what you
  usually do instead first, then anything that does the same job — the same
  ranking the phone's picker uses. Today only; the plan is untouched.
- **The phone still wins.** Open an exercise on it and the lens mirrors that;
  close it and the list comes back, caught up on what you logged.
- **Close**, at the foot of the list, hands the lens back — until you next open
  the app on the phone. Without it the only way out was quitting the app: Meta's
  own back gesture leaves, and the next repaint a second later returned.
- **Today**, on the rest screen, goes back to the list without cancelling the
  rest. A rest is when you look for the next machine.
- **Settings → Glasses says why the lens is empty** when it is: nothing planned,
  closed from the glasses, or waiting for you to open the app.
- **The calendar button on Today reaches the lens.** Pick a workout off-schedule
  and the glasses show that one.

### Changed

- **The workout's logic moved out of the views**, into `Workout`. Which day it
  is, what is done, what weight to open on and how a set is written were private
  functions inside `TodayView` and `SetView`; a locked phone has no views, and
  the lens needs the same answers. The views now call the shared functions —
  they were moved, not copied, so the lens and the phone cannot disagree about
  how a set is written. No behaviour change on the phone.

### Notes

- **It takes the lens only around a workout.** A display session is the whole
  lens, so the list shows for fifteen minutes after you touch the app, or while
  a workout is open and its last set is under half an hour old. Otherwise the
  lens is handed back. Opening the app at the gym is how you say you are there.
- **Lifts only from the lens.** A treadmill's numbers come off its console and
  the lens cannot type; "log as planned" would write a run you may not have
  run. A machine's card sends you to the phone, where it still mirrors.
- **No icon on the glasses.** A native app cannot have one — the phone drives
  the lens. Meta's Web Apps can, but they need the internet, hold 5 MB, and
  cannot talk to the phone's store. Written up in `docs/DECISIONS.md`.

## Earlier

- [0.13](./docs/changelog/0.13.md)
- [0.12](./docs/changelog/0.12.md)
- [0.11](./docs/changelog/0.11.md)
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
