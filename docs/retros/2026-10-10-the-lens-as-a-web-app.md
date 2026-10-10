# Retro — v0.18.0, the lens as a Web App (2026-10-10)

**Scope:** v0.18.0, Phase 1 (phone side) of "the Rathi Fitness lens as a Meta
Web App": the workout on the web, no feed. `LensHost` / `NativeLens` /
`WebLens` split out of `GlassesFace`; rest timing as data (`RestClock`, the
clock-free projection); `AudioHub.holdForLens`; Settings → Glasses → Lens and
pairing; the wire contract (`docs/LENS_WIRE.md`, `wire/fixtures/`) and its two
guards. The relay room and the page are being built in ria-ar-feed against the
same contract, in parallel.

## What went well

- **The spike came first, and it changed the design.** The plan assumed the
  in-app music already held the process awake. The spike's first 45-minute run
  showed Siri breaking exactly that — a player state change, not an
  interruption, so nothing noticed — and the keep-alive that ships here is the
  one that then survived five Siri requests with the phone locked. Building
  `holdForLens` from the plan's description would have shipped the gap.
- **Moving the host out made it testable for the first time.** Meta's mock
  device has no display, so every rule in `GlassesFace` was covered only by
  reasoning and by wearing it. With the transport behind a protocol, a fake
  lens can hold a send in the air, and the two epoch guards and `gate.accept`
  each have a test that fails without them.
- **The rules are plain values.** `ClockOffset`, `TickWatch` and `SeenInputs`
  came from the spike already tested; `WebLens.judge` is a list of guards in the
  order LENS_WIRE.md documents, with one refusal code each, so a refused pinch
  says why in its `ack`.
- **Mutation-checked, not just green.** Seven mutants, each restored before the
  next: removing the transport-epoch guard fails
  `testADropMidSendNeverMarksTheScreenShowing`; the layer-epoch guard,
  `testArmingMidSendNeverMarksTheOldScreenShowing`; `gate.accept`, eight host
  tests; the frozen check before reading the socket,
  `testATickGapClosesTheGateBeforeTheSocketIsRead`; the late check,
  `testALatePinchIsRefused`; the epoch check,
  `testTheWrongEpochSeqOrActionIsRefused`; the one-lens rule,
  `testTwoLensesRefuseTheWriteButNotNavigation`.

- **Two independent reviews, two different questions.** One compared the old
  `GlassesFace` line by line with `LensHost` + `NativeLens` and found the move
  behaviour-preserving for the native lens (five LOW timing differences, all
  fixed or documented). The other attacked the web path — "can it write a set
  nobody lifted?" — found no such path, and found one HIGH and four MEDIUM
  problems the author's passing tests had not looked for (the gaps below).

## What was hard to understand

- **"Is it showing" lived in two places.** `GlassesFace.endSession` did both
  the SDK teardown and the host's bookkeeping (epoch, pacer, gate, music), and
  it was called from both directions — by the host ("nothing to show") and by
  the SDK ("glasses off"). Split, the host does its own bookkeeping when *it*
  lets go, and the native lens reports `.lost` when the SDK does. Named in
  `LensEvent`.
- **The plan's presence rule could not carry the plan's clock.** §3 wanted the
  phone's ping answered by `setWebSocketAutoResponse` (cheap, wakes nothing)
  *and* every pong to carry `roomNow` (for the late-pinch rule). An
  auto-response is a fixed string. The phone sends an app-level ping; the room
  judges presence by the last message. Written at the top of LENS_WIRE.md so
  the relay can follow.
- **§3 had no way to say "nothing to show".** Closing the workout from the lens
  would have read on the page as "phone not reachable" — the wrong advice. The
  `idle` message is the addition.
- **A test run reported failures at line numbers the file no longer had** — the
  build had picked up the test sources a moment before an edit landed. Re-run
  before believing a failure that does not match the code.

## Gaps found

| Gap | Kind (docs / testing / process / observability) | Follow-up | Status |
| --- | --- | --- | --- |
| A real workout worn in Web App mode, phone locked, every §4 row seen (the Phase 1 "done") | testing | `docs/LENS_CHECKLIST.md`, all rows and W1–W10 | blocked: not yet worn in Web App mode — the relay room and the page are being built in ria-ar-feed and are not deployed yet, so there is nothing for the glasses to open |
| The native checklist after the extraction (the move must change nothing on the glasses) | testing | `docs/LENS_CHECKLIST.md` rows 1–15 in Native mode | blocked: needs the Display glasses on a person; Meta's mock device has no display, and the simulator cannot link a lens |
| AirPods triple-press while the session mixes (`.mixWithOthers` during the Web App hold) | testing | checklist W9; if it fails, release the mix while a set screen holds the AirPods | blocked: needs AirPods and the glasses worn in Web App mode; the now-playing role is not observable in the simulator |
| The Meta-AI-over-Bluetooth path (glasses' Wi-Fi off) for 20+ min with the phone pocketed | testing | wear it; if it drops, the setup rule "glasses join the phone's hotspot" goes in README and Settings | blocked: needs the glasses worn with their Wi-Fi off for a long session; the spike measured only that it connects |
| The cue ducking Music.app or Spotify for its length while held | testing | play a rest out with Music.app playing in Web App mode | blocked: needs a device with another app's music playing; the owner trains to the in-app player, which cannot be ducked at all |
| The page and relay must adopt `idle`, `repaint`, the ping/pong shape and the pairing QR (LENS_WIRE.md "Changes from plan §3") | process | follow-up in ria-ar-feed's Phase 1 PR | blocked: the relay and page live in ria-ar-feed and are another PR in progress; the changes are written where that work reads them |
| `bin/pair-phone` (the QR the phone scans) and ria-ar-feed's `bin/sync-wire --check` | process | `bin/pair-phone` is being built in ria-ar-feed #4, printing `rflens1:<phone>#k=<feed>&lk=<lens>`; `LensPairing` parses exactly that shape (43-char `token_urlsafe` keys), pinned by `testWhatPairPhonePrintsIsRead` | landed here: the phone side is pinned; the script itself ships in ria-ar-feed #4 |
| RIA's `docs/META_GLASSES.md` → "Web App path — measured" and a `fitness` row in `bin/glasses-url` | docs | RIA PR after this merges | blocked: those files are in the RIA repo, not this one |
| `GlassesFace.endSession` did host and SDK bookkeeping at once, from both directions | docs | `LensEvent.lost` vs `LensHost.endTransport`, said in the code | landed here |
| §3's presence-by-auto-response could not carry `roomNow` | docs | LENS_WIRE.md, change 3 | landed here |
| §3 had no "nothing to show" message | docs | `idle`, LENS_WIRE.md change 1, sent and tested | landed here |
| The 2026-09-21 rejection of the Web App path read as current | docs | a pointer to this release in that entry | landed here |
| The host had no test at all (mock has no display) | testing | `LensHostTests` with a fake lens, mutation-checked | landed here |
| `idle` reused the next screen's ticket, so after Close → reopen the page (which renders only what is newer) stayed on "Closed" — review 2, HIGH | testing | `end(…ticket:)` reserved from the gate; `testTheScreenAfterIdleIsNewerThanIt`, `testTheLastWordHasATicketOfItsOwn`; checklist W11 | landed here |
| Forgetting the pairing mid-workout left the keep-alive holding the phone awake indefinitely — review 2 | testing | `keyChanged` lets go; `testForgettingThePairingMidWorkoutLetsThePhoneSleep` | landed here |
| The late rule failed open on an input with no `relayedAt` — a relay change could switch it off silently — review 2 | testing | refused `late`; writes refused before the room clock is known; LENS_WIRE.md change 12; `testAnInputTheRoomDidNotStampIsRefused` | landed here |
| A `deactivate()` swallowed while the lens held the session was never paid back, leaving other apps ducked — review 2 | testing | owed and paid at release; checklist W13 | landed here |
| The cue's duck changed the session after the cue was scheduled, so an engine restart could drop it — review 2 | testing | duck before scheduling; checklist W12 | landed here |
| The last lens leaving did not close the gate; an unknown pong id was matched to the oldest ping; a bare 16-character code (a gym pass) was accepted as a key — review 2 | testing | gate closed on 0 lenses; unknown pong ignored; `rflens1:` prefix required; a test each | landed here |
| `idleReason` cleared after the await (stale text for a beat); a transport swapped mid-await could set the old one's reason; the native retry throttle not reset on re-enable — review 1 | testing | cleared before the await, reason only from the current transport, `wake()` on `use` and reset in `NativeLens.stop` | landed here |
| `LensHostTests` did not cover disarm-with-no-driver, `.ready`, `.lost` closing the music card, `wake` on arm, or `wanted` — review 1 | testing | five tests; the fake's `ensure` now honours `wanted` | landed here |
| The tick and room clock read `Date`, so a backwards wall-clock step could hide a freeze — review 2, LOW | testing | a suspend-aware monotonic clock for `TickWatch` | blocked: `ContinuousClock` cannot be compared with the room's wall-clock `relayedAt`, so the late rule needs `Date` anyway, and a clock step mid-workout has not been seen; changing the tick alone splits the two rules onto different clocks |
| The synthetic-fixture guard reads titles and loads, not every free-text field — review 2, LOW | testing | widen it if a fixture ever needs real-looking text | blocked: every free-text field in the fixtures is built in `LensWireTests` from literals in that file, which the diff review sees; a guard on prose would need a dictionary of what is "real" |
| A rotated key looked like "offline": retry every 5 s for ever, the wrong advice in Settings, the keep-alive held — integration review | testing | close 4001 / HTTP 401 → `refused` (no retry, keep-alive released, "pair again"), 403 → `forbidden`; three tests; mutants: refusal treated as offline, 401 not read as refused | landed here |
| Whether `URLSessionWebSocketTask` sends an Origin header (the room accepts the phone only without one) — integration review | testing | captured the upgrade request against a local listener: no Origin (CFNetwork 3896); noted in LENS_WIRE.md change 16 | landed here |
| Settings' relay version read `peerVersion` (the lens's) — integration review | testing | `roomVersion`; asserted in `testThePongSetsTheRoomClock` | landed here |
| The first clock samples were stamped before the TCP/TLS/upgrade, skewing room time by half the handshake for ~5 s — integration review | testing | first ping on the first frame, `hello-ok.roomNow` not sampled; `testNoClockSampleIsTakenBeforeTheLinkIsUp`, mutation-checked | landed here |
| LENS_WIRE.md implied the page sees the phone's ping — integration review | docs | "for the room only; the page learns presence from `presence`" | landed here |
| `WritePathPlanTests.testAddingAnExerciseFromTheCatalogue` timed out with two UI workers while unit builds ran beside it; passes alone (53 s) | process | none in this release | blocked: untouched by this change (the plan editor), and it is the machine-load flake the Makefile's WORKERS note already records |

## Follow-ups landed in this milestone

- `LensHostTests`, `WebLensTests`, `LensWireTests`, `LensPairingTests` — 57 new
  cases; the suite is 621.
- The two guards and nine cases for them in `guards.d.test.sh`.
- LENS_WIRE.md's "Changes from plan §3", for the relay and the page.

## Follow-ups blocked (and why)

- Everything that needs the glasses on a person, the relay deployed, or another
  repo. The worn checklist is written so the first session in Web App mode
  knows what to look for, W9 first.
