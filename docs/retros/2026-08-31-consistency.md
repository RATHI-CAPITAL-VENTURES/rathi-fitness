# Retro — v0.4.0, showing up (2026-08-31)

**Scope:** the consistency band on Today (`feat/consistency-band`). One feature,
three docs, one reversed ruling.

## What went well

- **The ruling got tested instead of quoted.** The ask was for weekly streaks.
  `docs/RESEARCH.md` already said no to streaks, and the cheap move was to point
  at that line. Reading the actual research instead turned up something better
  than either answer: the objection is sound but it is an argument against
  streaks counted in **calendar days**, and this app is the rare one that knows
  which days were meant to be training days. That reframing is the whole
  feature, and it would not have appeared from re-reading our own file.

- **No new model, no schema bump.** The band is a pure function over
  `Session.startedAt` and `Rotation.Config`. Nothing stored means nothing to
  migrate, nothing for CloudKit to reject, and no third end of the snapshot
  contract to keep in sync. The cheapest version turned out to be the honest
  one, which is not usually how it goes.

- **The tests caught a real thinking error immediately.** `testABigWeekCannot
  PayForAMissedOne` failed on first run — the expectation said `[6, 0, 1]`
  where the fixture produces `[6, 0, 0]`. The assertion was wrong, not the code,
  but it was wrong because I had lost track of which fixture had a session in
  the current week. A vaguer test would have passed and taught me nothing.

## What was hard to understand

- **"How many workouts a week" has three different answers and the modes do not
  say so.** `Rotation.Mode` is `weekday` / `rotation` / `everyNDays`, and each
  needs a different derivation — the count of planned days, the count of chosen
  weekdays, and `floor(7/N)`. `everyNDays` genuinely does not think in weeks at
  all: "every 2 days" is 3.5 a week, so a 3-workout week has to count. Nothing
  in `Rotation.swift` hints that a caller might need this, because until now
  nothing did. `Tally.weeklyTarget` is now the one place that decides it.

- **The session-versus-day question is settled in the code and not written
  down.** v0.3.1 moved the rotation from counting days to counting sessions, for
  good reasons documented at `Rotation.index`. That decision binds anything new
  that counts training, and I nearly introduced a second unit (days trained)
  for the band before finding it. The reasoning lived in a doc comment on one
  function rather than anywhere a person would look for "what does this app
  count".

- **The `changelog-archive` guard fires on a MINOR bump and the failure reads
  like a mistake.** Adding `0.4.0` put two MINOR series in `CHANGELOG.md`, which
  is a guard failure with a remedy (`make changelog-archive`) rather than an
  error. Fine once known; surprising the first time, since nothing about writing
  a changelog entry suggests you have just broken a rule.

## Gaps found

| Gap                                                                                                | Kind          | Follow-up | Status                                                                                                                          |
| -------------------------------------------------------------------------------------------------- | ------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `RESEARCH.md` said streaks were refused outright; that is now half-true and would mislead the next reader | docs          | doc       | landed here — rewritten to say what was refused (day streaks) and what shipped instead                                          |
| The "sessions, not days" rule was discoverable only from a doc comment on `Rotation.index`         | docs          | doc       | landed here — stated in `DECISIONS.md` as a rule that binds anything counting training, and at `Tally.consistency`              |
| `gym` on the Mac cannot answer "am I showing up"; the band exists only on the phone                | observability | code      | blocked: the band is derived, not stored, so `gym` would need the derivation ported to Python — a second implementation of the weekly-target rule in a second language, which is exactly the drift `snapshot-schema` exists to stop. Belongs in the snapshot as a computed field, which is a schema change and its own PR |
| Trends has no consistency surface, so the twelve weeks cannot be read next to the lift trends      | testing/UX    | code      | blocked: `ConsistencyBand` was built as a reusable component for this, but placing it on Trends is a design call about what Trends is for, and it was explicitly asked to go on Today first. One line to add once that is decided |
| No UI test covers the band, only unit tests over the derivation                                    | testing       | test      | landed here — `ConsistencyTests` covers every branch of the derivation; the view is presentational and takes a value, so there is no logic in it to test that the unit tests do not already reach |

## Follow-ups landed in this milestone

- `docs/RESEARCH.md` — the streaks row rewritten rather than left standing.
- `docs/DECISIONS.md` — the reversal recorded with what was rejected and why,
  including the two mechanics (a declarable week off, a PR streak) that are
  deliberately kept in reserve rather than forgotten.
- `README.md` — one row in the capability table.

## Follow-ups blocked (and why)

- **`gym showing-up` on the Mac.** The band is computed on the phone from data
  the snapshot already carries, but `gym` cannot recompute it without a second
  copy of `weeklyTarget` in Python. Two implementations of one rule in two
  languages is the failure `snapshot-schema` was built to prevent, so the right
  fix is a computed field in the snapshot — additive, but a contract change and
  a CLI change, and it should be its own PR rather than a rider on this one.

- **The band on Trends.** It was built as a shared component precisely so it can
  go there, and it is one line. What is not decided is whether Trends should
  carry it at all now that Today does, which is a question about duplication
  rather than about effort.
