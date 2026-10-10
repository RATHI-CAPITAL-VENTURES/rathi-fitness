# The lens wire — phone ⇄ relay room ⇄ Web App

Wire version: 1

The contract between this app (the phone, the only source of truth) and the
Fitness Web App on the glasses, through the relay room in **ria-ar-feed**
(`LensRoom`, a Durable Object at `wss://feed-api.ishanrathi.com/room`). This
repo owns it: the Swift side is `app/RathiFitness/Model/LensWire.swift`, the
examples are `wire/fixtures/*.json`, and this page is the prose. ria-ar-feed's
CI fetches the fixtures at a pinned commit (`bin/sync-wire --check`, no token —
this repo is public) and tests the page and the relay against them.

Three things hold it together here: `LensWireTests` encodes every screen below
to its fixture byte for byte; the `wire-schema` guard makes the version above,
`LensWire.version` and every fixture's `"v"` agree; and the
`wire-fixtures-synthetic` guard keeps the fixtures made up (Catalogue names,
the loads 45/95/135/185/225, time counted from zero — this repo is public).

Plan of record: the reviewed plan's §3 (protocol), §4 (renderer parity) and
§6 (phone). Where this page and the plan differ, this page wins, and the
differences are listed first so the other side can follow them.

## Changes from plan §3

Everything here is **additive** inside v1. Nothing in §3 was removed.

1. **`idle` (phone → room → lens) is new.** §3 had no way to say "nothing of
   ours belongs on the lens" — the workout was closed from the lens, it is a
   rest day, or the phone switched to the native lens or off. Without it the
   page could only show "phone not reachable", which is the wrong advice. The
   phone sends it and then closes its socket. **The room should forward it to
   lenses like a `screen`, and keep it as the last screen** (so a page that
   reconnects is told the same thing). Shape below.
2. **`repaint` (room → phone) is named.** §3 says the room "asks the phone to
   repaint (fresh ticket)" on a lens `resume`, without naming the message. The
   phone treats `{type:"repaint"}` — and a forwarded `{type:"resume"}`, if the
   room passes that through instead — as "draw again with a fresh ticket".
3. **The phone's ping is app-level and carries more.** `{v, type:"ping", id, t,
   epoch, seq}` every 5 s. The room should answer `pong {roomNow, id, t}`
   (echoing `id` and `t` lets the phone match a pong to its ping; without `id`
   it matches the oldest outstanding one, which is also correct because pongs
   come back in order). §3 also wanted phone presence judged from
   `setWebSocketAutoResponse` timestamps — but an auto-response pair is a fixed
   string and cannot carry `roomNow`. **The phone sends no fixed auto-response
   string**, so judge phone presence by the time of the last message on the
   phone's socket (one arrives at least every 5 s while it is up). The
   10 s staleness rule is unchanged.
4. **`hello` (phone → room) is specified:** `{v, type:"hello", version}`, the
   app's marketing version. The phone reads `hello-ok {roomNow, peerVersion,
   lenses?}` — `lenses`, when present, saves waiting for the first `presence`.
5. **`ack` carries `why`.** `{v, type:"ack", id, accepted, why}`; `why` is
   `null` when accepted, else one of the refusal codes below.
6. **A spec is `{label, value}` or `{label, rest}`, never both.** A running
   clock (the music card's Rest) has no `value`.
7. **A set screen always has a `rest` key** (`null` when not resting), and
   `hero` is omitted exactly when `rest` is present.
8. **List row `progress` is rounded to three places** (or `null`: no ring).
9. **An inbound message with no `v` is read as v1**; any other `v` is refused.
   (The room's own replies may omit `v`.)
10. **The pairing QR is `rflens1:<FITNESS_PHONE_KEY>`**, optionally followed by
    `#<fragment>` — the Web App's own URL fragment (`k=…&lk=…`). §3 said only
    "a terminal QR holding the phone key". The fragment, when present, lets
    Settings offer "Add to glasses" with the same encoding as
    `bin/glasses-url`; without it that row is not shown. A bare key is also
    accepted.
11. **All times are milliseconds**: `endsAt` (phone clock), `relayedAt` and
    `roomNow` (room clock), `t` (sender's clock).

## Connecting

`wss://feed-api.ishanrathi.com/room`, subprotocols **`fitness.v1`** and
**`k.<FITNESS_PHONE_KEY>`** — the key is never in a URL. The room checks the
key before upgrading (401 otherwise), takes the role from which key matched,
and echoes only `fitness.v1`. The phone has no Origin header, which the room
accepts only with the phone key.

The phone connects only while something of ours belongs on the lens — a
workout is live (`WorkoutDriver.isLive`) or a set screen is open — and only
when paired. It reconnects with backoff 0.5 → 1 → 2 → 4 → 5 s (capped), and
treats 12 s with no message of any kind as a dead socket.

## Messages the phone sends

Every message is one JSON object with `v` and `type`. Keys are sorted and the
text is compact (that is what makes the fixtures byte-comparable); a reader
must not depend on either.

### `screen`

```jsonc
{ "v":1, "type":"screen", "epoch":"3f9a1c0e", "seq":412,
  "screen": { "kind":"set", … } }
```

- `epoch` — this run of the phone app (new per launch, 8 hex characters).
- `seq` — the screen's ticket (`LensGate`), increasing within an epoch.
- The lens renders `(epoch, seq)` only if it is newer; a new epoch always wins.
- A new screen goes out only when the **clock-free** screen changes
  (`LensScreen.clockFree`): a rest ticking down is not a change, extending it
  is. So while resting the page ticks the clock itself.

### `idle`

```jsonc
{ "v":1, "type":"idle", "epoch":"3f9a1c0e", "seq":413,
  "reason":"idle" | "moved" | "off", "text":"Closed from your glasses. Open the app to bring the workout back." }
```

`reason` is the category; `text` is the phone's own sentence, to show as is.
`moved` means the phone switched to the native lens; `off` that the glasses
were switched off in Settings. Only the phone reopens the workout.

### `ping` — every 5 s

```jsonc
{ "v":1, "type":"ping", "id":17, "t":1700000000000, "epoch":"3f9a1c0e", "seq":412 }
```

The liveness beat. It carries the ticket on the lens so the page knows the
phone is still behind it — and it is **not** a re-sent screen, so the ticket
never moves under a finger.

### `hello`, `ack`

```jsonc
{ "v":1, "type":"hello", "version":"0.18.0" }
{ "v":1, "type":"ack", "id":"<input id>", "accepted":false, "why":"late" }
```

## Screens

### `kind: "set"` — one exercise, ready, resting or done

| Field | Type | Notes |
| --- | --- | --- |
| `eyebrow` | string | "PUSH · SET 2 OF 4", "RESTING" |
| `title` | string | the exercise |
| `hero` | string | "185 × 8", "20:00", "Done". **Omitted while resting** |
| `detail` | string | |
| `tone` | `"ready"` \| `"resting"` \| `"done"` | picks the colour |
| `rest` | object \| `null` | `{endsAt, totalMs, remainingMsAtSend}` while resting |
| `actions` | action[] | in order; the **first is lit** |

### `kind: "list"` — today's plan, or what could stand in

| Field | Type | Notes |
| --- | --- | --- |
| `eyebrow` | string | |
| `rows` | `{title, trailing, done, progress, action}`[] | `progress` 0…1 or `null` (no ring); `action` is `{"open": n}` |
| `footer` | action[] | after the rows: `close` on today's list, `back` on a swap list |

One focus stop per row, the first row focused.

### `kind: "card"` — one thing, and what you can do about it

| Field | Type | Notes |
| --- | --- | --- |
| `eyebrow`, `title` | string | |
| `specs` | `{label, value}` or `{label, rest}`[] | a ledger with dotted leaders. Only the music card's Rest is a `rest`; an exercise card's Rest is the planned length, text |
| `lines` | string[] | |
| `actions` | action[] | |

### Rest timing

`rest = {endsAt, totalMs, remainingMsAtSend}`. `endsAt` is the phone's clock —
identity and diagnostics only. The lens computes its own deadline as
`receivedAt + remainingMsAtSend − age`, where `age` is what the room adds when
it **replays** a stored screen (`now − storedAt`; a live forward has `age: 0`).
Ring progress is `1 − remaining / totalMs`; the colour is `coolHue`/
`coolSaturation` of that, checked against `wire/fixtures/coolhue.json`.

When the local clock reaches zero before the phone's READY arrives, the page
shows READY **dimmed, with Log set inert** until it does.

### Actions

All fourteen `LensAction`s are on the wire, none excluded: `"logSet"`,
`"skipRest"`, `"extendRest"`, `"fewerReps"`, `{"open": n}`, `"start"`,
`"taken"`, `"back"`, `"list"`, `"close"`, `"music"`, `"play"`, `"pause"`,
`"nextTrack"`. An action the page does not know renders as a disabled button
reading "update the phone app". Labels are the page's (they match
`LensAction.label`).

## Messages the phone reads

| `type` | From | The phone… |
| --- | --- | --- |
| `hello-ok {roomNow, peerVersion, lenses?}` | room | learns the room clock offset and the relay version |
| `presence {lenses, lensVersion?, …}` | room | offers a screen only while `lenses ≥ 1`; a 0 → n change repaints |
| `pong {roomNow, id?, t?}` | room | refines the room clock offset (smallest round trip of the last 12 wins) |
| `input {id, epoch, seq, action, relayedAt}` | lens, stamped by the room | judges it (below) and answers `ack` |
| `repaint` / `resume` | room | draws again with a fresh ticket |
| `feedAudio`, `ack`, `undeliverable` | — | ignored (feed audio is Phase 2) |

### How an `input` is judged

In this order; the first that fails is the `why` in the `ack`:

| `why` | Refused when |
| --- | --- |
| `closed` | nothing honourable is on the lens: no screen yet, or the phone was **frozen** — its 1 Hz tick came more than **2 s** late, which closes the gate **before** the socket is read again |
| `late` | `relayedAt` is more than **1.5 s** old by the phone's estimate of room time |
| `wrongEpoch` | not this run's epoch |
| `wrongSeq` | not the ticket on the lens |
| `notOnScreen` | the action is not on that screen (a row out of range included) |
| `lenses` | a write (`logSet`) while the room counts other than exactly **one** lens |
| `gate` | `LensGate` refused it: already spent, or a write within 1 s of the last honoured pinch |

Honouring spends the ticket, and **the phone always repaints** — after a
refusal too, with a fresh ticket. The phone keeps the last **64** input ids; a
replayed id gets its original `ack` and does nothing. Nothing is ever queued:
an input the phone cannot judge now is not judged later.

## Version skew

Three channels deploy on three schedules: Pages on merge to ria-ar-feed, the
relay by hand, this app when the phone next installs `main`. So:

- Changes inside v1 are additive; unknown fields are ignored on both ends.
- The room passes `screen` (and `idle`) payloads through opaquely and reads
  only the envelope, so most features need no relay deploy.
- A breaking change bumps `LensWire.version`, the line at the top of this page
  and every fixture together (the `wire-schema` guard), and deploys relay
  (accepts both) → Pages (understands both) → phone. Every deploy PR names its
  order.

## Fixtures

`wire/fixtures/screen-<name>.json` is the exact text the phone sends for each
row of plan §4, with `epoch:"fixture0"` and time zero:

| Fixture | §4 row |
| --- | --- |
| `set-strength-ready` | strength READY on the lens (`logSet, fewerReps, back, music`) |
| `set-strength-mirror` | strength READY mirrored from the phone (`logSet, music`), dumbbells ("45 each × 10") |
| `set-strength-resting` | strength RESTING (`skipRest, extendRest, list, music`), ticking locally |
| `set-strength-done` | strength DONE — no actions |
| `set-cardio-clock` / `set-cardio-unset` | cardio clock, `logSet` only when there is something to log |
| `set-cardio-resting` / `set-cardio-done` | cardio RESTING / DONE |
| `list-today` | today's list: rows `open(i)` with rings, footer `close` |
| `list-swap` | "Taken": rows without rings, footer `back` |
| `card-exercise`, `card-exercise-finished`, `card-stand-in` | exercise card: `start, taken, back`; finished: `back, start` |
| `card-machine` | a machine's card: `back` (log it on the phone) |
| `card-next-up` | next up: `start, list` |
| `card-wrap-up`, `card-wrap-up-machine` | wrap-up: `list` |
| `card-music-playing`, `-paused`, `-nothing`, `-no-playlist` | the music card (`pause|play, nextTrack, back`; `play, back`; `back`), its Rest ticking |

`coolhue.json` samples `coolHue`/`coolSaturation` at every 0.05 of a rest for
the page's JS port to match.

To re-record after a deliberate change: run `LensWireTests` with
`TEST_RUNNER_LENS_WIRE_RECORD=1` (e.g. `TEST_RUNNER_LENS_WIRE_RECORD=1 make
test-unit`), read the diff, and say in the PR what moved and in which order it
deploys.
