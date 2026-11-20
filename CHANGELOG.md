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

## 0.20.0 — 2026-11-19

### Added

- **Max weight.** Each exercise can say the heaviest it goes (Exercise editor → "Heaviest
  it goes"). Hit every rep at the max and the suggestion keeps the weight and asks for one
  more rep, counted from your weakest set, instead of 5 lb the machine doesn't have. A step
  that would overshoot lands on the max, and the set screen's + stops there. Today's rows
  and `gym today` follow, because they read the same suggestion. The snapshot carries
  `exercises[].max_weight` (additive) and `gym exercise` prints it. Assisted machines
  ignore it: there, harder means less help.

## Earlier

- [0.19](./docs/changelog/0.19.md)
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
