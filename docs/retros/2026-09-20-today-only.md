# Retro — v0.12.0, today only (2026-09-20)

**Scope:** v0.12.0. One ask: a temporary section on each day for things like a
note or a locker number.

## What went well

- **The hard question had already been answered the day before.** "Temporary"
  invites a block that gets cleared, and `Swap` had just been through exactly
  that argument: anything that clears is a rule that fails silently. A dated
  row was the first design, not the second.
- **The snapshot's staleness was caught at the desk, not in the gym.** Exporting
  "today's notes" sounded complete until the question "today according to
  whom?" — the file is as old as the app's last run. The block carries its date
  and `gym` refuses any other; there is a test for Tuesday's locker on Thursday.
- **A third copy of the chip was refused.** It existed twice already, once per
  set screen. `Chip` went into `Components` and both call sites moved to it in
  the same change, rather than "later".
- **Looked at it.** The UI test screenshots the strip filled in, and the
  judgement that a note must be a line rather than a chip was made from the
  picture.

## What was hard to understand

- **A tappable line of text is a button, and XCUITest says so.** The first UI
  run failed looking for the note as static text. The strip was correct — the
  hierarchy dump showed the locker chip and the note exactly as intended — and
  the test was asking the wrong question. Same family as yesterday's context
  menu: a failing UI test is evidence about the test first.
- **What "one per day" means for `other`.** Locker is singular; "Towel" and
  "Guest" must coexist. The key is (kind) for named kinds and (kind, heading)
  for `other`, compared case-insensitively — and that makes the heading
  un-renameable in place, which had to be decided rather than discovered.
- **Privacy ran the opposite way to passes.** `docs/SNAPSHOT.md` is emphatic
  that pass codes never reach the file. These values must, or the feature's
  best use is gone. The line that holds both positions is the combination: not
  offered, and pinned by a test.

## Gaps found

| Gap | Kind | Follow-up | Status |
| --- | --- | --- | --- |
| Nowhere to put something true for one gym visit | feature | `DayNote` + `DayNotesStrip` on Today, rest days included | landed here |
| A cleared-at-midnight block would show stale values the day clearing failed | design | dated rows; nothing clears | landed here |
| A stale snapshot would report an old locker as today's | correctness | `day_notes.date`; `gym` drops any other day | landed here |
| The obvious next chip — the combination — would put a secret in a world-readable file | security | no such kind; a test fails if one is added; the sheet says where notes go | landed here |
| The outlined/filled chip was duplicated across both set screens | structure | `Chip` in `Components`; both moved | landed here |
| The CSV export would have silently omitted a new table | completeness | `day-notes-….csv` | landed here |
| RIA's `gym_log` does not yet say that `today` answers "what's my locker" | docs | none | blocked: that text lives in the RIA repo (`tools/gym.py`), a separate PR there — the CLI output already carries the notes, so she sees them whenever she calls `today`; only the routing hint is missing. |
| Editing a past day's notes | feature | none | blocked: past days are read-only by design (`PastDayView` — logging writes `Date.now`, and an editable yesterday is how entries land on the wrong day). Reasoned in DECISIONS. |

## Follow-ups landed in this milestone

- Everything in the table marked `landed here`.

## Follow-ups blocked (and why)

- **The RIA routing hint.** One line in another repo; being opened as its own
  PR alongside this one.
- **Editing the past.** Deliberate, and the same rule as the rest of that screen.
