# Retro — v0.6.0, borrowing well (2026-09-02)

**Scope:** v0.6.0. Three features taken from screenshots of a competitor app —
the lifetime tonnage ladder, the activity heatmap, the record book — plus the
two that were declined.

## What went well

- **The model layer already had it.** `Tally.records(for:history:)` had been
  answering "did this set beat anything" since the first version; the record
  book is that function in a loop. Tonnage was already computed everywhere.
  Nothing new had to be measured — only kept and given a shape. Three features
  landed in one file plus one screen because the arithmetic was already honest.
- **Looking at the screen caught what tests could not.** The reps tile read
  `2990` because `Fmt.weight` was doing duty for a count. Every test passed; it
  is a formatter, and it is only wrong to a person.
- **The empty state was right by construction.** Every new section guards on
  having something to show, so a fresh install sees none of them — verified by
  accident when the first screenshot run launched without demo history.

## What was hard to understand

- **`Set` means two things.** Inside `Tally`, a bare `Set` is `Tally.Set`, so
  `Set(names).count` compiles into something quite different from a count of
  distinct names. It cost a build to notice, in the same file, for the second
  time in two days.
- **A function can be right in one context and wrong in another.**
  `records(for:history:)` reporting a personal best for a first-ever set is
  correct on the set screen and wrong in a book. Nothing about reading it
  suggests that; only using it twice does.
- **The reference app is not a spec.** Its ladder is branded illustrations and
  a 1,207,918.8 lb "SpaceX Rocket" — a number with a decimal place and no
  provenance. Deciding which parts were the good idea (a number given a size)
  and which were theirs (the art, the exact tiers) took longer than the code.

## Gaps found

| Gap                                                                     | Kind        | Follow-up                                                          | Status      |
| ----------------------------------------------------------------------- | ----------- | ------------------------------------------------------------------ | ----------- |
| Lifetime tonnage existed but was never shown, and means nothing unshaped | feature     | the milestone ladder, from a registry of real masses                | landed here |
| Records were computed and discarded                                     | feature     | `recordBook` replays history per lift and keeps them                | landed here |
| `records` calls a first-ever set a record — wrong for a book            | correctness | the book requires a non-empty history; both rules documented        | landed here |
| `Fmt.weight` was formatting reps and workouts                           | correctness | `Fmt.count`, with a test at twelve thousand                         | landed here |
| No way to see the shape of training over months                         | feature     | 26-week heatmap, four shades                                        | landed here |
| A streak was asked for a third time                                     | process     | declined again; the heatmap answers the appeal, recorded in DECISIONS | landed here |
| A strength score was asked for                                          | data        | blocked: needs published strength standards by bodyweight, age and sex; a curve invented here would be a confident number with nothing behind it | blocked: no source dataset |

## Follow-ups landed in this milestone

**The lesson is about borrowing.** Every one of these came from a screenshot of
someone else's app, and the useful question was never "what does it look like"
but "what does it know that we do not". The answer three times was **nothing** —
the app already had the tonnage, the dates and the records. What it lacked was a
reason for them to mean anything to a person: a size for the number, a shape for
the calendar, a memory for the records.

That is why the ladder uses real masses and the streak stayed declined. Copying
the mechanic would have been faster and would have imported a decision this app
had already made twice, on evidence, in the opposite direction.
