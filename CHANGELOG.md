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

## 0.12.0 — 2026-09-20

### Added

- **Today only.** A strip under the day's header for what you need to know
  today and not tomorrow: **Locker**, **Parking**, a **Note**, and **Other**
  with your own heading (Towel, Guest, Key). What you have set is a filled chip
  that reads as itself — "Locker 214" — because the point is to glance at it
  holding a towel; what you have not is an outline to tap. A note is a line of
  its own rather than a chip that truncates it. Tap anything to change it;
  clearing the field, or *Remove*, takes it away. On rest days too.
- **Tomorrow it is blank, and nothing had to run for that to be true.** Each
  entry is a `DayNote` row that belongs to a day. The alternative — one
  editable block that something clears at midnight — fails silently the day the
  clearing does not run, and leaves Tuesday's locker on screen on Thursday,
  confidently wrong. The past keeps what you wrote: swipe back to a workout and
  it shows what you noted that day.
- **Same as last time.** The sheet offers your last locker, parking spot, or
  the last value under a heading you have used. Never a note — yesterday's
  "knee is sore" offered back as today's is the app putting words in your mouth.
- **`gym today` prints them**, on a rest day too, so RIA can answer "what's my
  locker number". The snapshot's `day_notes` block carries `until`, the instant
  the phone's day ends, and `gym` drops a block past it: a snapshot is only as
  fresh as the last time the app ran, and a wrong locker is worse than none.
  An instant, not a date — phone in Tokyo and Mac in New York agree on "the
  21st" for thirteen hours after the locker became yesterday's. Two devices
  writing a locker for one day show as one, latest wins.
- **It redraws when the day changes.** Leave the app open past midnight and
  Today — header, plan and strip — now moves to the new day on
  `NSCalendarDayChanged`, and on becoming active on a new day. The rows never
  needed clearing; the screen still needed telling. (All of Today had this, for
  as long as it has read the clock in `body`.)
- **There is no chip for the lock's combination, on purpose.** Everything here
  reaches a file any process on the Mac can read.
- Day notes are in the CSV export (`day-notes-….csv`).

### Changed

- The small outlined/filled pill was written out twice, once per set screen,
  and was about to be written a third time. One `Chip` in `Components` now.

## Earlier

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
