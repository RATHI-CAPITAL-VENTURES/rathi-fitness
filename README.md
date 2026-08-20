# Rathi Fitness

A personal gym app. iPhone-first, RIAKit's design language, readable by RIA.

Status: **design only.** Four screens exist as a mockup; no Swift has been
written yet. See `design/ios-first-pass.html`.

## What it does

| Ask | Where it lives |
| --- | --- |
| Log an exercise + current body weight, see trends over time | Trends tab — body weight chart, working weight table |
| Store QR codes | Pass tab — check-in code at full brightness, plus guest/punch passes |
| A checklist for each day showing what to do | Today tab — the day's plan, one live row at a time |
| Set / cooldown counter per exercise | The set screen, pushed from a Today row |

## Shape

- `app/` — SwiftUI iPhone app. Source of truth. SwiftData + CloudKit.
- `cli/` — the `gym` binary. Reads the iCloud snapshot, prints for a human.
- `docs/` — decisions and architecture.
- `design/` — the UI mockup and its renders.

## Why the data path is shaped the way it is

The phone owns the data, because a gym app has to work in a basement with no
signal. CloudKit syncs it between devices.

But a CloudKit **private** database cannot be read from a Mac command line —
there is no app context to authenticate as — so `gym today` on the Mac would
have nothing to talk to, and RIA would be blind. The app therefore also writes
a JSON snapshot into an iCloud Drive container, which on macOS is an ordinary
file that syncs itself. `gym` reads that file; `tools/gym.py` in ria-2.0 shells
out to `gym`, the same shape as every other RIA tool.

Writes go the other direction through an `inbox/` folder the app drains on
launch. Not built yet — RIA is read-only until there is a reason.

## Not decided yet

- Whether the Blink check-in code is static (storable) or rotating (not).
  Needs the real card, not a guess.
- Whether the cooldown hue ramp survives contact with an actual workout.
- Watch app. The set/cooldown screen is the obvious candidate and is designed
  so its state reads as colour, which survives a 45mm face.
