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

## 0.19.0 — 2026-10-10

### Added

- **A Short's sound pauses the music, and READY brings it back.** In Web App
  mode, unmuting a Short in the rest's feed pauses the in-app workout music;
  when the rest ends on the phone (or the Short is muted, or you leave the
  feed) the music resumes — **only if the Short paused it**. Music you paused
  stays paused; pressing play yourself mid-feed hands it back to you; a call
  or Siri is never fought for. The phone stays awake throughout (`FeedAudio`,
  `LensWire` change 17).

### Changed

- **Pairing switches the lens to the Web App** and Settings says so. The
  owner paired, the lens stayed on Native, and the glasses said "No workout".
- **The lens's "no workout" sentence is written for the lens**: "Start a
  workout on your phone." instead of Settings' "Open the app…" (LensWire
  change 18).

### Fixed (review)

- **Off then on inside MusicKit's play latency** no longer leaves the music
  playing over the Short: a sound that comes on while our resume is on its way
  takes the claim and pauses as the play lands.
- **A Siri query no longer cancels "music back at READY".** Only a phone call
  drops the claim (and nothing is resumed while one is active); interruptions
  for suspension or a route change do not count. Settings shows the last
  interruption, for the worn check.
- **Pairing is reachable from Native and with the glasses off** ("Use the Web
  App: pair with the relay"), so pairing really can switch the lens.
- The READY chime is rendered over-music when the music is about to resume; a
  passed deadline is not a rest; nothing is started from scratch when nothing
  is queued; `feedAudio` needs exactly one lens and is ignored when over 5 s
  old; "Paired." when already on the Web App; the pairing note clears.
- The READY and playback pipelines are functions with tests
  (`FeedAudio.readyPublisher`, `.playbackPublisher`).

### Tests

- `FeedAudioTests` (23) and `LensKeepAliveTests` (1): pause and resume,
  sound-off, user-paused music never resumed, the user's play drops the claim,
  off→on inside the play latency, calls vs Siri, interruption reasons, the
  READY pipeline with a real `RestTimer`, the playback mapping, nothing queued,
  through the wire, pairing → Web App, and the keep-alive held and playing
  while the music is paused.
- `WebLensTests`: `feedAudio` only from one lens and fresh; the idle text.
  `WorkoutDriverTests`: the lens's wording. UI: pairing offered outside Web App
  mode.
- Mutants, each failing the suite: resume without the claim; claim un-played
  music; the user's play not dropping the claim; no resuming window; no pause
  when the play lands; every interruption dropping the claim; the reason
  ignored; resume into a call; the READY filter loosened; playback not
  deduped; `feedAudio` from two lenses; pairing leaving the lens; the lens
  text ignored. Two survivors showed unreachable code, which was removed.

## Earlier

- [0.18](./docs/changelog/0.18.md)
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
