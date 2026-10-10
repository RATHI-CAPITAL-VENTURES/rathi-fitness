# Changelog

Every notable change to Rathi Fitness. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/) + [SemVer](https://semver.org/)
(`MAJOR.MINOR.PATCH` in `VERSION`). The `changelog` guard enforces that the top
header equals `VERSION`, is new relative to the base branch, and increases
monotonically; opt out with `changelog-exempt` or `[skip changelog]` for a
genuine no-op.

`VERSION` is mirrored by `MARKETING_VERSION` in `app/project.yml` — that is what
the phone shows and what every snapshot is stamped with, so the `version-sync`
guard makes them agree.

A **MINOR bump is a milestone** and must ship a retro under
[`docs/retros/`](./docs/retros/).

## 0.18.0 — 2026-10-10

### Added

- **The lens can run as a Web App.** Settings → Glasses → Lens: **Native**
  (as before, the default) or **Web App** — the same screens in the Fitness Web
  App the glasses open from their own app grid, through the relay room in
  ria-ar-feed. The phone stays the only source of truth: the page renders what
  the phone sends and sends back which button was pinched. The rest clock ticks
  on the lens itself, so a rest is one message, not ninety. Switching mode
  mid-workout carries the set or rest straight over.
- **Pairing.** Settings → Glasses → Pair scans the code `bin/pair-phone` shows
  on the Mac — with the live camera, never a screenshot — into the Keychain.
  "Add to glasses" opens Meta AI to add the Web App when the code carried its
  link. Settings shows the relay, the lens count, the room's round trip, the
  last pinch's delay and every version in play.
- **The phone keeps itself awake for the Web App lens** while a workout is
  live: a mixing silence loop, a once-a-second watchdog that restores it, and a
  short background window whenever audio is taken — the keep-alive the spike
  proved through Siri with the phone locked (`AudioHub.holdForLens`).
- **`docs/LENS_WIRE.md` and `wire/fixtures/`**: the wire contract (v1) and a
  synthetic fixture for every screen the lens can show, which ria-ar-feed's CI
  tests against. Two guards hold them: `wire-schema` (the version agrees in
  Swift, the doc and every fixture) and `wire-fixtures-synthetic` (Catalogue
  names, fixed loads, no dates or timestamps — this repo is public).
- **`docs/LENS_CHECKLIST.md`**: the worn checklist for any release that touches
  the lens, in both modes.

### Changed

- **`GlassesFace` is three parts.** `LensHost` (what is on the lens and which
  pinch counts), `NativeLens` (Meta's SDK) and `WebLens` (the relay), moved out
  of one 625-line file — moved, not copied. The native lens behaves exactly as
  before.
- **A rest is data in the screen value** (`RestClock`): native screens are
  byte-identical, and the web lens is paced on a clock-free projection.

### Tests

- `LensHostTests` (21) drive the host against a fake lens for the first time,
  holding a send in the air: arm/disarm and a drop mid-send, an owed beat,
  Music's Back against the driver's, pacing per transport, switching lenses.
- `WebLensTests` (20): wrong epoch, seq, action or row; duplicate ids; a pinch
  relayed 3 s ago; a 3 s tick gap closing the gate before the socket is read;
  two lenses refusing a write; reconnect with a fresh ticket; backoff; pings.
- `LensWireTests` (13) and `LensPairingTests` (3): every fixture byte for byte,
  native parity, the clock-free projection, the `bin/glasses-url` encoding.
- Seven mutants — each epoch guard, `gate.accept`, the frozen check, the late
  check, the epoch check, the one-lens rule — each fail the suite.

## Earlier

- [0.17](./docs/changelog/0.17.md)
- [0.16](./docs/changelog/0.16.md)
- [0.15](./docs/changelog/0.15.md)
- [0.14](./docs/changelog/0.14.md)
- [0.13](./docs/changelog/0.13.md)
- [0.12](./docs/changelog/0.12.md)
- [0.11](./docs/changelog/0.11.md)
- [0.10](./docs/changelog/0.10.md)
- [0.9](./docs/changelog/0.9.md)
- [0.8](./docs/changelog/0.8.md)
- [0.7](./docs/changelog/0.7.md)
- [0.6](./docs/changelog/0.6.md)
- [0.5](./docs/changelog/0.5.md)
- [0.4](./docs/changelog/0.4.md)
- [0.3](./docs/changelog/0.3.md)
- [0.2](./docs/changelog/0.2.md)
- [0.1](./docs/changelog/0.1.md)
