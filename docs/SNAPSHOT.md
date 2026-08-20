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
| `body_weight` | `current`, `current_date`, `change_30d`, `trend_per_week`, `history[]` |
| `today` | the day's plan and what has been done — **absent on a rest day**, not empty |
| `exercises[]` | `slug`, `name`, `loading`, `working_weight`, `best`, `change_30d`, `recent[]` |
| `plan[]` | the rotation: each day and its target sets/reps/weight/rest |
| `passes[]` | metadata only, see above |
| `sessions[]` | one row per training day: counts, volume, top lifts |

`slug` is the stable identifier. Names can be edited; slugs are what RIA and the
CLI refer to.
