# Retro — v0.5.0, the first report from the gym (2026-09-02)

**Scope:** v0.5.0. Nine items, all from two weeks of using the app to actually
train, none from the test suite.

## What went well

- **The model layer was right almost every time.** `Tally.nextTarget` handled
  assisted machines correctly; `Tally.consistency` already counted per week and
  was already day-agnostic; `HealthSync` already keyed exports on the session
  rather than the day. Five of the nine fixes changed a call site, a gate, or a
  question — not an algorithm. Pure functions in `Tally` and `HealthSync`, kept
  out of the views, meant every fix had somewhere obvious to land and a test
  that could be written in seconds.
- **`Session` paid for itself again.** Three of these ("moved today", the Health
  export, coverage-per-week) were fixed by using the session that v0.3.1 already
  introduced, in places that had been left grouping by calendar day.
- **The snapshot was the fastest diagnostic tool available.** Reading
  `snapshot.json` gave the real plan, the real session dates and the three real
  assisted exercises in one command, and turned "Showing Up is wrong" from a
  guess into arithmetic.

## What was hard to understand

- **A defaulted parameter hid a wrong answer.** `nextTarget(…, assisted: Bool = false)`
  reads as a convenience. It is a trapdoor: the one caller that forgot it got a
  plausible, confident, wrong suggestion for months, and the flag it needed was
  sitting on the values already being passed in. Nothing about reading either
  file suggested a problem.
- **The tests agreed with the bug.** Every assisted test passed the flag by
  hand, so they proved the branch worked while never exercising how it was
  reached. There was even a test called
  `testTheConverterCarriesTheFlagSoNoCallSiteCanForgetIt`, green throughout.
- **Two comments argued the wrong thing convincingly.** The tonnage exclusion
  ("the same invention that keeps push-ups out of tonnage") and the export gate
  ("tomorrow it goes over complete") were both well-written, both reasoned, and
  both wrong in the specific case. A confident comment is harder to re-examine
  than an absent one.
- **`Set` means two things.** Inside `Tally`, a bare `Set` is `Tally.Set`, not
  `Swift.Set` — counting distinct workouts compiled into something else entirely
  until it was spelled out.

## Gaps found

| Gap                                                                                  | Kind          | Follow-up                                                            | Status       |
| ------------------------------------------------------------------------------------ | ------------- | -------------------------------------------------------------------- | ------------ |
| `nextTarget` took `assisted` as a defaulted parameter; the only caller never passed it | testing       | derived from the sets; parameter removed so it cannot be passed wrong | landed here  |
| Assisted work contributed nothing to tonnage                                          | correctness   | `bodyweight − help`, valued at the weigh-in on or before the set      | landed here  |
| "Moved today" grouped by calendar day and matched by slug                             | correctness   | compares the previous **session** of the same workout                 | landed here  |
| Showing Up measured attendance against a weekday-derived target                       | correctness   | distinct workouts covered, against the size of the plan               | landed here  |
| Apple Health export skipped anything dated today                                      | correctness   | gate is `endedAt != nil`; finishing a workout syncs                   | landed here  |
| Health synced only at cold launch                                                     | observability | `scenePhase` + on finish, both directions via `syncNow`               | landed here  |
| Snapshot written to iCloud without `NSFileCoordinator`                                | correctness   | coordinated write; `gym` materialises an evicted file                 | landed here  |
| Cardio had no progression suggestion                                                  | feature       | `nextCardioTarget`, one dimension at a time                           | landed here  |
| Body weight sat on Today                                                              | design        | moved to Trends with its logging button                               | landed here  |
| No test reaches a suggestion the way a screen does                                    | testing       | see below — the class of bug that caused two of these                 | landed here  |
| Sparse weigh-ins make assisted tonnage patchy for older sessions                       | data          | fixed by the Health sync above; nothing to invent for pre-first-weigh-in sets | landed here  |

## Follow-ups landed in this milestone

**The lesson worth keeping is not "check your call sites".** It is that a
parameter with a default is a place a caller can be silently wrong, and that a
test which constructs the input by hand cannot notice. Two of the nine bugs were
exactly this shape, in two different files.

So the fixes are structural rather than diligent:

- `nextTarget` **cannot** be told about `assisted` any more; it reads the flag
  off the sets, which have carried it since v0.2.0.
- `SetEntry.tally(bodyWeight:)` takes its parameter with **no default**, so the
  compiler makes all eleven call sites state whether they need a bodyweight.
  Passing `nil` is fine and explicit; forgetting is not possible.
- `AssistedTests.testTheDirectionIsRightWithNobodyPassingAFlag` asserts the
  whole contract with nobody passing anything, which is the case the old tests
  could not express.

Still true and worth saying plainly: **the suite did not find any of this, and
would not have.** These were wrong questions and wrong wiring, not wrong
arithmetic, and the only thing that surfaced them was training with the app for
two weeks. Where a fix could be pinned to a value the tests now pin it; where it
was a question ("is coverage the right metric?") no test would have helped.
