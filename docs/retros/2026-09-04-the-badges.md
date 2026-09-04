# Retro — v0.8.0, the journey and its badges (2026-09-04)

**Scope:** v0.8.0. A journey screen, fifteen generated badges, and two fixes
that came out of looking at the result.

## What went well

- **The data was already there.** "When did I pass a blue whale" has an exact
  answer inside the session volumes, and nothing had ever asked it. `journey`
  is twenty lines and needed no new storage, no migration and no schema bump.
- **One prompt, reused verbatim.** Fifteen badges drawn to a single style
  sentence read as a set. The two rounds it took to get there were cheap because
  the first was a single probe image, not fifteen.
- **Reviewing the sheet caught four defects before they shipped.** Two badges
  came back on grey rather than black, the blue whale came back a different
  colour and scale, and the 250 lb "piano lid" rendered as a whole piano — which
  would have sat directly above the 1,000 lb whole piano.
- **The guard caught the version.** A new screen is capability-shaped; the
  `bump-level` guard refused the PATCH and asked for a MINOR and a retro, which
  is exactly right and is why this file exists.

## What was hard to understand

- **"Pure black" is not the same as "no background".** The badges were asked for
  a black field, and they got one — and then drew fifteen visible black squares
  down a list, because this app's background is a tinted `RoomBackground` rather
  than `#000`. The image was correct, the layout was correct, and the screen was
  wrong.
- **Nothing testable was broken.** `UIImage(named:)` resolved, the asset catalog
  was valid, the frame was right. The only signal was a screenshot.
- **The picker had been wrong since the day it shipped.** `.prefix(3)` looked
  deliberate — "the lifts with the most history" — and read as a design choice
  rather than a limit, while the table twelve rows below listed all twenty-four.

## Gaps found

| Gap                                                             | Kind        | Follow-up                                                            | Status      |
| --------------------------------------------------------------- | ----------- | -------------------------------------------------------------------- | ----------- |
| The ladder knew when each tier was crossed and never said so    | feature     | `Tally.journey`, dated per session, and a screen for it              | landed here |
| `tortoise.fill` stood in for rhino, hippo and elephant          | design      | fifteen generated badges, one prompt                                  | landed here |
| Opaque badges drew black squares on a tinted background          | design      | clamped to transparent with a feathered rim                           | landed here |
| Trends offered 4 tiles against 24 logged lifts                   | correctness | `.prefix(3)` removed; the row already scrolled                        | landed here |
| `2250.0 tons` — precision nobody has                             | polish      | one decimal under a thousand tons, none above, never `70.0`           | landed here |
| A missing or misnamed badge would render blank and silently      | testing     | a test asserts every tier's artwork resolves in the bundle            | landed here |

## Follow-ups landed in this milestone

**The lesson is that some defects are only visible.** Three of the five fixes
here — the black squares, the duplicate piano, the four tiles — were found by
rendering the screen and looking at it. Every test passed through all of them,
and would have kept passing.

So the test that *was* added is deliberately narrow: it asserts every tier names
artwork that resolves in the bundle, which catches a typo or a deleted asset.
It does not pretend to check that the artwork is any good. Claiming otherwise
would be the more dangerous outcome — a green suite that implies the visuals
were reviewed when nobody looked.

The habit worth keeping from this milestone: **render it, export the screenshot,
and look**, on anything visual. It cost one UI test run per iteration and caught
what the other 290 tests could not.
