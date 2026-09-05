# The snapshot — the contract between the phone and the Mac

The app owns the data. This file is how everything else reads it.

    ~/Library/Mobile Documents/iCloud~com~rathi~fitness/Documents/snapshot.json

Written by the app (on launch, and ~2s after any change), read by `gym` and by
RIA's `tools/gym.py`. `$GYM_SNAPSHOT` overrides the path for testing.

## Why a file and not CloudKit

A CloudKit **private** database has no Mac command-line read path — there is no
app context to authenticate as. iCloud Drive is the same sync fabric exposed as
ordinary files, so the Mac can read it with `open()`. This is the reason the
CLI can exist at all.

## Rules

### Schema history

| Version | Change |
| --- | --- |
| 1 | The original contract. |
| 2 | Set kinds. `volume`, `top_weight` and `sets` mean **working** sets — warm-ups contribute to none of them and are counted separately as `warmup_sets`. Each performed set carries `kind`, `rpe` (nullable — not recorded is not "easy") and `note`. Each exercise carries `primary_muscle` and `secondary_muscles`. |
| 4 | Assisted machines. `assisted: true` on an exercise **inverts what its numbers mean**: `working_weight` is how much help you needed, so lower is better and a negative `change_30d` is progress; `best` is the least help ever needed; assistance is excluded from `volume` and from `top_lifts`. A reader that does not know the flag will congratulate you for getting weaker, which is why this is a bump and not an addition. |
| 6 | **Time away.** `time_away[]` records stretches he declared himself away for — `from`, `to` (both `YYYY-MM-DD`, `to` **inclusive**) and an optional `note`. Anything reading `sessions[]` to judge consistency must subtract these first: a fortnight abroad is not a fortnight of not bothering, and the app's own band leaves those weeks out of its percentage entirely rather than counting them as met. |
| 5 | **Sessions, not days.** A `sessions[]` entry is one *workout*, not one date, so **two entries can share a `date`** — a reader that keys on `date` alone will merge a two-a-day back together, or overwrite one with the other. `started_at` and `ended_at` (`HH:mm`, 24-hour; `ended_at` absent while a workout is in progress) and `ordinal` (which workout of that day, from 1) are what tell them apart. `day` is now the workout's **recorded** name rather than a guess from the weekday, so it is right on a day you trained out of order. |
| 3 | Cardio and machine settings. Two additions and one **changed meaning**, which is what forces the bump: an exercise may be `modality: "cardio"`, and on one of those `volume`, `working_weight` and `best` are absent or zero and **mean nothing** — a treadmill has no tonnage. Cardio numbers live in `cardio` blocks (`bouts`, `seconds`, `distance`, `average_incline`, `average_speed`) and in `sessions[].cardio_minutes`. `machine_settings[]` on an exercise says where the seat goes. |

- **`schema` is checked, not assumed.** `gym` refuses a version it does not
  know rather than misreading a field that changed meaning. Bump it whenever a
  field changes meaning; adding a field does not need a bump.
- **Keys are snake_case.** Note `change_30d`: Swift's `convertToSnakeCase`
  splits on capitals and *not* on digits, so this one needs explicit
  `CodingKeys` or it silently ships as `change30d` and every reader sees null.
  There is a test pinning it.
- **Numbers are rounded before they leave the app.** `176.4 - 178.2` is
  `-1.799999999999983` in binary floating point, and RIA may read it aloud.
- **Ordering is total.** Every list has a deterministic sort including tie-
  breaks. Dictionary iteration order in Swift is seeded per process, so without
  this the file's bytes differ between identical writes and it churns in iCloud
  forever.
- **Writes are atomic.** The Mac may be reading while the phone writes.
- **Zero is a number; "not recorded" is not.** Every optional cardio metric is
  nullable rather than defaulted to 0, for the same reason `rpe` already was.
  A treadmill bout with no grade entered is not a bout at 0% grade, and a reader
  averaging the column would be told every flat walk was measured. The same rule
  is why a cardio exercise's `working_weight` is `null` rather than `0` — a
  0 lb bench press is indistinguishable from a real one once it is in a mean.
- **Cardio is never converted into tonnage.** Minutes and miles are the only
  honest summary of a treadmill; a pounds-equivalent means inventing a rate
  nobody measured. `sessions[].volume` stays lifting-only and
  `sessions[].cardio_minutes` sits beside it.
- **Averages inside a `cardio` block are weighted by time.** A five-minute flat
  walk must not pull a twenty-five-minute climb's grade down as though the two
  were the same amount of work. Nobody reading "average incline" would guess a
  plain mean, so it is not one.

## Pass codes are not in here, and that is the point

The file lands in a folder any process on the Mac can read. A scannable gym
credential sitting there in cleartext is the same mistake as an access code in
a commit message. So passes export **metadata only**:

    name, location, symbology, member_id_masked, state, expires, expired,
    primary, has_code

`has_code: true` is the whole truth the CLI gets about the payload. The code
lives on the phone, in the CloudKit private database, and is displayed by the
app and nowhere else. `SnapshotTests.testPassCodesNeverReachTheSnapshot` fails
the build if that stops being true.

## Shape

| Key | What |
| --- | --- |
| `schema`, `generated_at`, `app_version` | provenance |
| `time_away[]` | declared trips: `from`, `to` (inclusive), optional `note` |
| `body_weight` | `current`, `current_date`, `change_30d`, `trend_per_week`, `history[]` |
| `today` | the day's plan and what has been done — **absent on a rest day**, not empty |
| `exercises[]` | `slug`, `name`, `loading`, `modality`, `working_weight`, `best`, `change_30d`, `recent[]`, `machine_settings[]`, `cardio_best` |
| `plan[]` | the rotation: each day and its target sets/reps/weight/rest, plus `cardio_target` on a cardio slot |
| `passes[]` | metadata only, see above |
| `sessions[]` | one row per training day: counts, volume, top lifts, `cardio_minutes`, `cardio_distance` |

### Cardio

An exercise with `modality: "cardio"` answers different questions, so read
different fields:

    exercises[].cardio_best        { farthest, longest_seconds, fastest }
    exercises[].recent[].cardio    { bouts, seconds, distance,
                                     average_incline, average_speed }
    today.items[].cardio_target    what the plan asked for — any field may be
                                   null, because "twenty minutes at 3%, speed
                                   as you feel" is a real programme
    today.items[].cardio           what the console actually said today
    today.items[].performed[]      seconds, distance, speed, incline,
                                   resistance, heart_rate — all nullable

`top_lifts` on a session **excludes cardio**: "Treadmill 0" is what happens
when it does not.

### Assisted machines

    exercises[].assisted   true when the weight makes it EASIER

Set on assisted pull-up and dip machines. When true:

- `working_weight` is **assistance**, and the *lowest* of the day rather than
  the highest — the hardest set is the one with the least help.
- `change_30d` is progress when **negative**.
- `best` is the least help ever needed, not the most weight.
- the exercise contributes nothing to `sessions[].volume`, and never appears in
  `top_lifts` — "Assisted Pull-Up 100" would otherwise top the list on the day
  you needed the most help.

`gym lifts` marks these rows with `*` and prints the direction under the table,
because a column that quietly mixes two opposite meanings is worse than one that
omits them.

### Machine settings

    exercises[].machine_settings[] { kind, label, value }

Where the machine goes — seat 2, back pad 4. `kind` is a stable enum raw value
(`seat`, `back`, `seat_depth`, …); `label` is what to show a human; `value` is
free text, because dials are not all numbers ("30°", "hole 12", "wide"). It
belongs to the exercise rather than to a set: the seat does not change between
Tuesday and Thursday. This is in the snapshot specifically so RIA can tell you
where the pin goes *before* you get there.

`slug` is the stable identifier. Names can be edited; slugs are what RIA and the
CLI refer to.
