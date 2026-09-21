# Retro — the glasses, v0.13.0 (2026-09-21)

**Scope:** Meta Ray-Ban Display glasses as a fourth face. The lens mirrors the
open set screen — what to lift, then the rest counting down — and a Neural Band
pinch logs the set or skips the rest. Plus the throwaway test app that came
first (`chore/lens-spike`, never merged).

## What went well

- **The spike was the right first step, and it paid for itself in an hour.** The
  plan refused to put Meta's binary into the real app until a throwaway one had
  proved the hardware. Six of eight open questions were answered the same
  afternoon, and three of the answers changed the design: the glasses end a
  session when they come off, the first button arrives lit, and a drawn numeral
  costs 155 ms — affordable, which nobody could have known from the docs.
- **The seam already existed.** `RemoteControls` was built for three AirPods
  gestures and turned out to be exactly the interface a lens button needs. The
  whole input path is `remote.run($0.remote)`. No new workout logic was written,
  and "mid-rest, log means skip" was inherited rather than reimplemented.
- **`LensState` as a plain value made the feature testable at all.** Meta's mock
  device has no display, so nothing that touches the SDK can be unit-tested.
  Putting every decision — what to say, in what order, when it is worth the
  radio — on the far side of a struct left 25 tests' worth of logic reachable.
- **Reading the compiled interface instead of the docs.** The docs cover the
  camera. `Image(image: UIImage)` — the thing that lets the numeral be in the
  app's own typeface — is in the `.swiftinterface` and nowhere else.
- **A log that could be pulled from the Mac.** `devicectl device copy from` on
  the spike's Documents folder meant every claim could be checked against
  timestamps without asking for a screenshot. It also caught "all of the
  questions work!!!" being true for six of eight.

## What was hard to understand

- **Meta's samples contradict Meta's setup guide, silently.** The guide lists
  `LSApplicationQueriesSchemes: fb-viewapp` as required; neither sample app has
  it. The spike was copied from the sample. The symptom is *nothing* — Register
  switches to Meta AI and Meta AI shows an ordinary home screen — and the only
  clue was `registration | unavailable` on the first log line.
- **A setup mistake and an open SDK bug look identical.** Before Developer Mode
  had installed its component on the glasses, registration succeeded and every
  session died in 0.2 s with `Device unavailable` — word for word Meta's
  unanswered issue #292. Ten minutes were spent planning an SDK downgrade.
- **Two generations of instructions for one switch.** Older guidance (and a Meta
  staff comment from May) describes a glasses-level Developer Mode toggle. It
  does not exist in the current app. The user was sent looking for it twice.
- **`Session ended by device` arrives as an error on a healthy link.** Nothing in
  the SDK distinguishes "the wearer took them off" from a fault.
- **An idle timer that was not there.** Three early sessions were ended by the
  glasses and it was written down as "silence kills a session within seconds".
  Three data points with no send-pattern in common was the clue that the cause
  was the person, not the phone. A ladder of lengthening silences disproved it
  in two minutes. The wrong sentence sat in `FINDINGS.md` for ten.
- **A size figure written from memory was off by half.** The decision record
  first said Meta's frameworks add "~15 MB". Measured: 30. It was caught only
  because the sentence was about to become permanent.
- **`devicectl … launch` reports success on a locked phone** and launches
  nothing; iOS's own background relaunch then makes the log look as if it
  worked, minus the arguments. And `-autorun hello` needs a `--` before the
  bundle id or `devicectl` parses it as its own `-t`.

## Gaps found

| Gap | Kind (docs / testing / process / observability) | Follow-up | Status |
| --- | ----------------------------------------------- | --------- | ------ |
| The plist key Meta's samples omit, and the four other setup traps, were known only from a chat | docs | Written into `Info.plist` beside the key, `docs/DECISIONS.md` 2026-09-21, and the spike's `FINDINGS.md` | landed here |
| A wrong conclusion ("silence ends a session") was recorded as a finding from three samples | process | Disproved by the gap-ladder experiment; `FINDINGS.md` and `DECISIONS.md` keep the wrong claim and its correction side by side | landed here |
| Whether the app's `processing`-less background modes still work was assumed | testing | Removed from the spike and re-run on the glasses: session, send and pinch all work (`FINDINGS.md`, trap 8) | landed here |
| Whether the auto-installer can build an app with a binary Swift package under launchd's PATH was assumed | testing | Resolved from a cold cache under `env -i` with the script's exact PATH: resolves at 0.9.0 | landed here |
| What the lens is asked to show, and when, had no tests | testing | `LensTests` — 25 cases over `LensState`, `LensPacer`, `LensRenderer` and the `RemoteControls` path a pinch takes | landed here |
| `GlassesFace` — sessions, reconnects, sends — has no unit tests | testing | none possible | blocked: Meta's MockDeviceKit (SDK 0.9.0) has no display support, so no display session can exist off real glasses; the same code was run on the hardware in the spike instead |
| Ten minutes locked in a pocket has not been run; 27 s is the longest locked stretch on record | testing | Spike button "2 · Pocket test", once with silent audio off and once on | blocked: needs a person wearing the glasses for ten minutes with the phone pocketed — the phone cannot observe the lens, and nothing can stand in for the wearer |
| What a notification or a call does to a live lens session is unknown | testing | Text yourself during a pocket test | blocked: needs the wearer to see what the lens did — the SDK reports no event for it |
| The drawn numeral on no card has not been looked at through the lens | testing | Open an exercise with the glasses on | blocked: only the wearer can see the lens; the phone has no way to capture it |
| Nothing tells the app the glasses are back on, so reconnect is a blind 5 s retry | observability | none in SDK 0.9.0 | blocked: the SDK keeps the link `connected` throughout a doff and publishes no wear-state; a retry is the only signal available |

## Follow-ups landed in this milestone

- The setup traps are written down in three places a person will actually look:
  the plist, the decision record, and the spike's findings.
- The gap-ladder experiment, which turned a wrong finding into a right one.
- `processing` verified unnecessary on the hardware before being left out.
- The auto-installer verified against a cold package cache under launchd's PATH.
- 25 tests over everything that does not need glasses.

## Follow-ups blocked (and why)

- **Unit tests for `GlassesFace`.** Meta's mock device cannot present a display,
  so a display session cannot exist in a test. If a later SDK adds it, the
  session logic is already isolated in one file and would be the first thing to
  cover.
- **The pocket test, the notification test, and a look at the numeral.** All
  three need a person wearing the glasses. They are the first things to do with
  the feature at the gym, and the spike app is still on the phone for the first
  two. If the pocket test fails, the fix is known and small: the real app already
  holds the `audio` background mode while hands-free is armed, and the glasses
  face could insist on it.
- **Knowing when the glasses go back on.** Not available from SDK 0.9.0. The
  retry costs nothing measurable, so this is a wart rather than a problem.
