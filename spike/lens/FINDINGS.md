# Lens spike — findings

What the hardware actually said, as it said it. Glasses: Meta Ray-Ban Display.
Phone: iPhone 14 Pro Max, iOS 27.0. SDK: Meta DAT 0.9.0, Developer Mode
(`MetaAppID = 0`). Every claim below is from `lens-spike.log` on 2026-09-21
unless marked otherwise.

## Answered

### 1 · Does a session start at all? — YES

```
13:54:27.259  session  starting
13:54:27.293  session  started
13:54:27.875  display  started
13:54:27.992  send ok  hello · 34 ms
```

Connect to first content in ~0.7 s, and the card was seen in the lens. Neither
of the two Meta bugs feared in the plan applies here: not #180
(`datAppOnTheGlassesUpdateRequired`), not #292 (`Device unavailable` from a
rejected trust record). Firmware reports `compatible`.

### 3 · What does one send cost? — about 50 ms, as text

Two-minute countdown, one whole-screen send per second, 118 sends, 0 failed:

| Phone | Sent | Median | p95 |
| ----- | ---- | ------ | --- |
| front | 91 | 49 ms | 65 ms |
| locked | 15 | 61 ms | 181 ms |
| background (unlocked) | 12 | 52 ms | one 1.1 s outlier, at the moment of locking |

A true per-second clock is comfortably affordable as text. And back to back,
twenty of each, phone in hand:

| Frame | Median | p95 |
| ----- | ------ | --- |
| text clock | 47 ms | 64 ms |
| image clock (552×220, 10 KB as PNG) | 155 ms | 201 ms |

**An image frame costs about three times a text frame and is still a sixth of
the one-second budget.** So drawing the clock ourselves — Fraunces, the app's
own green — is affordable, and "Meta's look or ours" stops being a technical
question. It is a taste question with a known price: ~110 ms a tick, and
whatever that does to the glasses' battery over an hour, which is not measured.

### Pinches arrive — YES

```
13:58:23.092  PINCH  Skip
13:58:43.826  PINCH  Skip
```

Index-to-thumb on a lens `Button` reaches the app's `onClick`. Input works end
to end, and it worked on a screen whose last send was half a minute old — tap
handlers outlive the experiment that sent them.

### 4 · Silence does NOT kill a session — a hypothesis that was wrong

Three sessions were ended by the glasses in the first ten minutes
(`unexpectedError("Session ended by device")`): 7.7 s after a lone send, 23.6 s
into a session that had sent nothing, and 1.6 s after a pinch. Set beside a
two-minute run at one send per second that lived, that read as an idle timer,
and this file said so for about ten minutes: "activity keeps it alive, and
silence kills it within seconds."

**It is not an idle timer.** The gap ladder — send, stay silent for N seconds,
send again — survived every rung:

```
14:01:47  send · then 2 s of silence   … 3, 4, 5, 6, 7, 8, 10, 12, 15, 20 …
14:03:20  send · then 30 s of silence
14:03:50  RESULT  never died · longest silence tried and survived: 30 s
```

Twelve sends in two minutes, no teardown. So a static *Ready* screen does not
need a heartbeat to stay connected, at least up to 30 s. Beyond that is untested,
and a 90 s rest with a once-a-second clock never goes silent anyway.

**What ended them: the glasses came off.** Asked afterwards, the wearer had
taken them off around each drop — four in all, the last at 14:05:13 with the
phone locked. The three had no send-pattern in common, which is what pointed
away from the phone and at the person. It fits the SDK's own changelog, which
talks about sessions stopping when the device is "doffed" or the hinges close.
(Reported from memory rather than logged at the time, so: well supported, not
proven. Putting them on and taking them off on purpose, once, would prove it.)

The consequence for the real feature:

- `Session ended by device` arrives as an *error*, on a healthy link, and the
  next `connect` succeeds in ~0.7 s. Taking your glasses off between exercises
  is ordinary gym behaviour, so this is routine: reconnect when they come back
  and re-send where you were. Never show it as a failure.
- Nothing tells the app the glasses are back on. The link stays `connected`
  throughout, so "reconnect" needs a trigger — the next logged set, the rest
  timer starting, or a retry on a slow timer. Untested which is best.

### 6 · Does a tall list scroll? — YES

Eight rows, built the way Meta's sample builds its menu (a column of tappable
`FlexBox` cards). A thumb swipe scrolled it to the bottom rows. So today's plan
is a plain column; no "More…" paging is needed. (Wearer's report — no row was
pinched, so the log has no line for it.)

### 7 · Focus and the back gesture

```
14:04:50.376  PINCH  button · Taken
14:04:52.373  PINCH  button · Start
```

- **The first button is lit when a screen appears.** So the action you want
  nine times in ten goes first, and the usual case is a pinch with no swipe —
  which is what the plan's lens mock-ups assumed.
- **Swipe moves the highlight between buttons, pinch selects** — two different
  buttons chosen, two seconds apart.
- **Middle-finger-to-thumb leaves the app.** It is Meta's system "back" and the
  SDK gives the app no callback for it. So every screen needs its own Back
  button, and the app has to put you back where you were when you return.
  *Not yet known:* whether leaving ends the session or only hides it, and how
  you get back into our app from Meta's menu.

## Setup traps — each cost real time

1. **`LSApplicationQueriesSchemes: fb-viewapp` is required and neither Meta
   sample has it.** Their setup guide lists it; `samples/DisplayAccess` and
   `samples/CameraAccess` both omit it, and this spike was copied from the
   sample. Symptom: registration reads `unavailable` from launch, Register
   switches to Meta AI, and Meta AI shows nothing at all. No error anywhere.
2. **Developer Mode has to be switched on while the glasses are connected.**
   Until it was, registration *succeeded* and every session died in ~0.2 s with
   `Device unavailable` (or went `starting → stopped` with no error at all) —
   which looks exactly like Meta's open bug #292 and is not. Meta's debugging
   note has the symptom right: "Registration completes but device never
   connects." The glasses restart when it is enabled; the link drops for a
   minute or two and `noEligibleDevice` in that window just means "not back yet".
3. **There is one Developer Mode toggle, not two.** Meta AI → Settings → App
   Info → tap the version five times. Older guidance (and a Meta staff comment
   from May) says "Settings → Your glasses → Developer Mode"; the current setup
   page does not, and no such second switch was found.
4. **Registering twice is an error**, not a no-op: `User is already registered
   when attempting to register again`.
5. **`RegistrationState` is an Objective-C enum** and prints as
   `RegistrationState(rawValue: 0)`. Every other SDK state describes itself.
6. **`isProtectedDataAvailable` and `canOpenURL` both lie during early launch**
   — the first reads "locked" on a phone in someone's hand, the second reads
   "Meta AI not reachable" with Meta AI installed. Both settle within a second.
7. **The SDK logs through `os_log`, not stderr**, so
   `devicectl … launch --console` shows ExternalAccessory chatter and nothing
   from Meta. Useful for seeing the accessory attach; useless for SDK errors.

8. **The `processing` background mode is not needed.** Meta's DisplayAccess
   sample declares it; Apple wants BGTaskScheduler identifiers alongside it,
   which a gym app has no use for. Removed from this spike and re-run: link,
   session, display, send and a pinch all still work
   (`14:26:04 session started … 14:26:14 PINCH Log set`). The real app carries
   `bluetooth-central`, `bluetooth-peripheral` and `external-accessory` only.

## Seen, not yet a verdict

- **iOS relaunches the app in the background when the glasses connect**, with
  the phone locked (`13:53:54 | bg | LOCKED | link | connected`). That is the
  `external-accessory` / `bluetooth-central` modes doing their job, and it is
  good news for the pocket question.
- **Locked, with silent audio OFF, sends kept landing** for the ~27 s the phone
  was locked mid-run. Promising; 27 seconds is not ten minutes.

## Still open

| # | Question | State |
| - | -------- | ----- |
| 2 | Survives ten minutes locked in a pocket? Audio off vs on? | 27 s locked, audio off: fine. Full run not done. |
| 4 | Does the lens visibly dim or go dark during a 30 s silence, even though the session lives | not observed — the phone cannot see it |
| 5 | What a notification does | not run |
| 7 | After the back tap: is the session ended or hidden, and how do you return to our app | not run |
| — | What should trigger a reconnect once the glasses are back on | not run |

**Question 2 is the one that was called make-or-break, and it is still open.**
Everything seen so far leans the right way — sends landed while locked with
audio off, and iOS relaunched the app in the background by itself when the
glasses connected — but the longest locked stretch on record is 27 seconds. The
real app holds an `audio` background mode anyway, which is the stronger of the
two mechanisms, so the risk is low. It is not zero, and ten minutes in a pocket
is what retires it.
