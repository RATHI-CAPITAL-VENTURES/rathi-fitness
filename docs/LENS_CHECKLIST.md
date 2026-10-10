# The lens, worn — a checklist

Meta's mock device has no display, so the part of the glasses face that draws
cannot be unit-tested. `LensHostTests` and `WebLensTests` cover what decides
the screen and which pinch counts; this list covers what only a person wearing
the glasses can see. **Run it on the glasses for every release that touches
`LensHost`, `NativeLens`, `WebLens`, `LensRenderer` or `LensWire`**, in each
lens mode the release touches, and say in the PR which rows were run.

Settings → Glasses → Lens picks the mode. Native is the default until the Web
App has been worn through a real workout and accepted.

## Both modes

| # | Do | Expect |
| --- | --- | --- |
| 1 | Open the app at the gym, lock the phone | Today's list on the lens, what you are part-way through lit first |
| 2 | Pinch a row | Its card: Load, Sets, Rest, where the seat goes; Start lit |
| 3 | Start | READY: the load, *Log set* lit; −1 rep, Back, Music after it |
| 4 | **Log set**, then straight away **Skip** | Log writes one set; Skip is instant (not refused) |
| 5 | **Log → Skip → Log** inside a second | Exactly one set written (check on the phone) |
| 6 | Log, and wait out the rest | The ring cools ember → teal; READY returns with the chime |
| 7 | +30 s during a rest | The clock jumps by 30 s |
| 8 | Music during a rest, then let the rest end | The card shows Rest ticking; at READY it closes itself |
| 9 | Music card: Pause, Next, Back | The player obeys; Back returns to the set, not the list |
| 10 | Finish the last set of a lift | "Next up" card, Start lit |
| 11 | Taken on a card | Up to five stand-ins; pinching one swaps it for today |
| 12 | Open an exercise on the phone mid-rest | The lens mirrors the phone; close it and the driver resumes |
| 13 | Glasses off for 30 s, then on | Back on the same place in the workout within seconds |
| 14 | Close (footer of today's list) | The lens is handed back and stays so until you open the app |
| 15 | Every §4 row of `docs/LENS_WIRE.md` seen at least once | Each draws, nothing clipped |

## Web App only

| # | Do | Expect |
| --- | --- | --- |
| W1 | Settings → Glasses: Pair, scan `bin/pair-phone`'s code | "Relay · 1 lens" once Fitness is open on the glasses |
| W2 | Open Fitness from the glasses' app grid before touching the phone | "No workout live — open Rathi Fitness on your phone" |
| W3 | Phone locked and pocketed for a whole workout | No "Phone not reachable"; every pinch answered |
| W4 | A Siri request with the phone locked mid-rest | The rest carries on; the next pinch is answered without unlocking |
| W5 | A phone call mid-workout | After the call, pinches are answered again without unlocking |
| W6 | Kill the phone's signal for 10 s mid-rest | The clock keeps ticking; it ends in a dimmed READY; Log set works once the phone's READY lands |
| W7 | Open Fitness on a second device too | Both render; Log set is refused until one closes |
| W8 | Switch Settings → Glasses → Lens to Native mid-rest | The page says "Moved to the native lens"; the rest carries on, natively |
| W9 | AirPods triple-press during a set, with music playing | Logs the set, as in Native mode (see the v0.18.0 retro) |
| W10 | Meta's back gesture | Leaves the page (the page is not told); reopen it and the workout is back |
| W11 | Close from the lens, then open the app on the phone | The page leaves "Closed…" and shows today's list (the ticket after `idle` is newer) |
| W12 | Spotify or Music.app playing, Web App mode, let a rest run out | The chime is heard over it (ducked for the cue only) |
| W13 | After the workout ends (or the lens is switched to Native/off) | Spotify / Music.app back at full volume; the phone no longer plays silence |
| W14 | Pair (Settings → Glasses → "Use the Web App: pair with the relay") with the lens on Native | Settings says "Paired. The lens is now the Web App"; Lens reads Web App |
| W15 | Web App on, no workout live (or Close from the lens) | The page says "Start a workout on your phone" (or "Closed from your glasses — start a workout…") |

## The feed in a rest (Phase 2)

| # | Do | Expect |
| --- | --- | --- |
| F1 | In-app music playing, log a set, swipe → into the feed, unmute a Short | The music pauses |
| F2 | Let the rest run out with the Short still sounding | READY pulls the lens back; the Short stops; the music comes back |
| F3 | Unmute a Short, then mute it (or swipe back to WORKOUT) mid-rest | The music comes back at once |
| F4 | Pause the music yourself, then unmute a Short and let the rest end | The music stays paused — it was yours |
| F5 | Unmute a Short, then press play on the phone or AirPods mid-rest, then pause again | READY leaves it paused |
| F6 | Unmute a Short and take a call mid-rest | Nothing restarts into the call or after it; the next rest's Short pauses the music again |
| F6b | Unmute a Short, ask Siri something short mid-rest, let the rest end | The music comes back at READY (the owner's rule). Read Settings → Glasses "last audio interruption" before and after: write down whether Siri arrived as an interruption (`began · default`) or not at all |
| F7 | Phone locked in a pocket throughout F1–F3 | Every pinch is answered: the phone stays awake while the music is paused |
| F8 | No feed pinch ever logs anything | Check the set count on the phone after a rest spent in the feed |
