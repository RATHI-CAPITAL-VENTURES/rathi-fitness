# Retro — the lens drives, v0.14.0 (2026-09-21)

**Scope:** the glasses run the workout with the phone locked — today's list, a
card, the set-and-rest loop, what is next, "Taken". To allow it, the workout's
logic moved out of `TodayView` and `SetView` into `Workout`. Stacked on v0.13.0
(the mirror), which has not merged yet.

## What went well

- **The independent review earned its place before this milestone started.** It
  found that v0.13.0 could write sets nobody lifted, three ways, none of which
  the author's own tests looked for — and the fix (`LensGate`: a pinch belongs
  to the screen it was drawn on, once) is what made it safe to give the lens
  *more* buttons here. Driving without it would have multiplied the hole.
- **Moving the logic instead of copying it.** The lens needed "which day is it",
  "what weight", "write a set". Copying ~120 lines out of two views would have
  been faster and would have passed every test on day one. The views now call
  `Workout`, lost ~70 lines, and the 471 tests that existed before passed
  unchanged — which is the evidence that it was a move.
- **Rows as arguments.** `Workout`'s functions take the sets and sessions they
  reason over rather than fetching them. The views pass `@Query` arrays, the
  driver passes a fetch, and nothing in the shared code can disagree with a
  screen about what the store contains. It also made the driver testable end to
  end against a real in-memory store with no view anywhere.
- **The first nineteen driver tests passed on their first run.** Not luck: every
  rule they check was already one function, tested, in `Workout` or `Swaps`. It
  was also not proof — the second review found two bugs they did not look for.
- **The hardware answers were already in hand.** A tall list scrolls, the first
  row arrives lit, "back" leaves the app — all measured by the spike before
  v0.13.0. Phase 2 needed no new trip to the glasses to be designed.

- **Wearing it found what two reviews could not.** Skip refused straight after
  Log; no way to close it from the glasses; no way back to the list from a rest;
  nothing on the lens at all the first time. None is a logic error a reader
  would spot. All four were reported within an hour of the first real use, and
  all four are fixed and tested in this milestone.
- **The second review found the two that mattered most**, both of which wrote
  wrong data and both of which the author's nineteen passing tests sailed past: a
  pinch crossing from one layer to the other across an `await`, and a weight
  held in hand going stale when the phone logged a set.

## What was hard to understand

- **How much of the app's behaviour lived in views.** `TodayView` decides which
  day it is; `SetView` decides what a logged set does to next week's plan. None
  of that was discoverable from `Model/`. It was found by reading 1,450 lines of
  two views looking for the word `private`.
- **Why `SetView`'s handlers are armed and disarmed with the screen.** It reads
  as an accident of SwiftUI until you find the comment explaining that a squeeze
  on the Trends tab must never log a phantom set. That comment is the reason the
  driver is a separate layer *under* the screen rather than a replacement.
- **When the lens should be ours at all.** Nothing in Meta's material says a
  display session is exclusive in a way that matters; it is one line in their
  overview. The consequence — an app that shows your workout whenever the
  glasses are on is an app you uninstall — had to be reasoned out, and the
  attention window is a guess at the right number, not a measurement.
- **"Can I open it from the glasses" has two different answers.** For a native
  app, no — and for a Web App, yes, at the cost of everything that makes this
  app work in a basement. It took a second pass through Meta's docs to find the
  Web Apps path at all; the display docs do not link to it.

## Gaps found

| Gap | Kind (docs / testing / process / observability) | Follow-up | Status |
| --- | ----------------------------------------------- | --------- | ------ |
| Workout logic lived inside views, unreachable without one | process | Extracted to `Model/Workout.swift`; `TodayView` and `SetView` call it | landed here |
| The driver — the part that writes to the log with nobody looking — had no tests | testing | `WorkoutDriverTests`, 27 cases against an in-memory store: list order, card, log, −1 rep, rest, next-up, Taken, and when the lens is handed back | landed here |
| The list and card renderers had no tests | testing | Five cases in `LensTests`: rows are tappable, each reports its own index, the footer, the lit button | landed here |
| v0.13.0 could log phantom sets from a stale lens button | testing | `LensGate` + seven tests, and the driver's own refusal to log mid-rest or past the last set | landed here |
| Why a native app cannot have an icon on the glasses, and what a Web App would cost, was known only from a chat | docs | `docs/DECISIONS.md`, 2026-09-21, second entry | landed here |
| A pinch could be delivered to the wrong layer: `display.send` is an `await`, a set screen could arm or disarm during it, and the gate was re-opened afterwards with the handler looked up late | testing | `layerEpoch`, and the handler bound when the screen is drawn. Tickets go live as the send starts | landed here |
| The driver's weight in hand went stale when the phone logged a set, and the next lens set was written at the old weight | testing | `screenClosed` re-derives the opening from the store; `testNumbersInHandAreWorkedOutAgainAfterThePhoneHasLoggedASet` | landed here |
| A deliberate Skip straight after a Log was refused | testing | The flurry guard applies only to pinches that write; `testSkipStraightAfterLogIsAllowed`, and `testLogSkipLogInsideASecondWritesOneSet` to show the guard still does its job | landed here |
| The app could not be closed from the glasses | process | `.close` at the foot of the list; three tests, including that only the phone reopens it | landed here |
| No way back to the list from a rest | process | `.list` on the rest screen; `testYouCanGetBackToTheListFromARest` | landed here |
| The driver never started: it was built after the Health and Music awaits, which had not returned | observability | Built before them; Settings → Glasses now says why the lens is empty | landed here |
| The day picked on Today was invisible to the driver | process | `Workout.chosen`, dated to the day it was picked | landed here |
| A second workout of the same planned day could not be logged from the lens | testing | Progress counted by open session, as `SetView` does; `testASecondWorkoutOfTheSameDayCanBeLogged` | landed here |
| The wrap-up card claimed everything was done with a machine untouched | testing | Counts the same slots as the list and names what is left | landed here |
| A rest day refetched the whole store once a second | observability | The empty answer is cached for a minute | landed here |
| Three tests could not fail or did not test what they claimed; one could flake near midnight | testing | Rewritten: a real lens-vs-phone comparison across two stores, a fixed noon clock, an exhaustive action list | landed here |
| The launch task's Health or Music await does not return promptly — the snapshot was six hours stale | observability | none yet | blocked: not reproducible from the Mac — the app has no log, the awaits are Apple's (HealthKit, MusicKit), and finding which one stalls needs the phone's console attached during a cold launch with the owner present |
| Cardio cannot be logged from the lens | process | none — by design | blocked: a bout's numbers come off the machine's console after the fact and Meta's SDK offers no text or number entry; logging the plan's figures would record a run that may not have happened |
| The attention window (15 min) and workout gap (30 min) are guesses | observability | Use it for a few sessions and adjust | blocked: the right values depend on how long this wearer actually goes between sets and between opening the app and lifting, and there is no data yet — there cannot be until the feature has been used |
| Nothing has been seen through the lens for the list, card or swap screens | testing | Open the app at the gym with the glasses on | blocked: only the wearer can see the lens; Meta's mock device has no display and the phone cannot capture it |
| The driver resumes after a set screen closes, but a background launch by iOS does not start it | process | none yet | blocked: SwiftUI does not create the scene — and so never runs the `.task` that builds the driver — on a background launch; starting it from `App.init` needs the store before it is seeded, and doing so would also take the lens with nobody having opened the app, which the attention rule exists to prevent |

## Follow-ups landed in this milestone

- `Workout` — the shared logic, with the views converted to call it.
- 27 driver tests, 5 renderer tests and 7 gate tests, a third of them written
  for something a review or an afternoon of use found.
- The "open it from the glasses" question answered in the decision record, with
  the Web App route priced rather than dismissed.

## Follow-ups blocked (and why)

- **Cardio from the lens.** No input method exists for it. If Meta ever exposes
  number entry, or the app gains a way to read a machine's console, the driver's
  `begin` is the one place that refuses machines.
- **Tuning the two time windows.** Needs real use.
- **Looking at the new screens.** Needs the wearer. The set screen was seen and
  "looks great"; the list, card and swap list are built from the same parts and
  the same sample shape that was seen to scroll, but have not themselves been
  looked at.
- **Starting on a background launch.** Deliberately not done; see the table.
