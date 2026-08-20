# What the other gym apps do, and what we're missing

Researched 2026-08-20 against Hevy, Strong, Boostcamp, Jefit, Fitbod,
StrengthLog and Liftlog+. Sources at the bottom.

This is a gap list, not a roadmap. Rathi Fitness is a personal app for one
person, so "everyone else has it" is an argument, not a verdict — several rows
below are things we should deliberately never build.

## The shape of the market

Three postures, and it's worth knowing which one we're in:

- **Loggers** (Strong, Hevy) — you already know your programme; the app's job
  is to get out of the way while you record it. Strong is generally judged the
  more polished logging surface; Hevy the more generous free tier plus a social
  feed and leaderboards.
- **Programme libraries** (Boostcamp, 11,000+ free programmes; Jefit) — the app
  supplies the training, with automatic progression.
- **Coaches** (Fitbod) — the app decides today's session from muscle-freshness
  scores and your history.

**We are a logger**, and should stay one. The programme is Ishan's; the app's
job is the twenty seconds between racking the bar and picking it back up.

## Table stakes we do not have

Ranked by how often they'd bite in a real session.

| Gap | Who has it | Why it matters here |
| --- | --- | --- |
| **Set types** — warm-up, drop set, failure, and per-set notes | Hevy, Strong, Boostcamp | Every set we record counts identically toward volume and records. A warm-up set of 135 currently pollutes both. This is the biggest correctness gap, not a nicety. |
| **RPE / RIR per set** | Hevy (6–10 scale), Boostcamp, Fitbod | How hard a set was is the input to what you do next week. Without it, "185 × 8" from a session where you had nothing left reads the same as one you sailed through. |
| **Supersets** | Hevy (first-class, shared rest timer), Boostcamp | Our rest timer assumes one exercise at a time. A superset makes the cooldown ring wrong, not just missing. |
| **Sets per muscle group per week** | Hevy, Jefit (7d/14d/1m/12m/lifetime), StrengthLog, Fitbod | The standard hypertrophy question. Needs a muscle mapping per exercise — a table we do not have and would have to build once. |
| **Rest timer as a Live Activity / Dynamic Island** | Hevy | Ours only counts while the app is open, backed by a local notification. On the lock screen it would be a glance instead of an unlock. Our cooldown *colour* is designed for exactly this and currently can't be seen from there. |
| **Apple Watch app** | Hevy, Strong, Fitbod, most | The phone lives in a pocket or on a bench. The set screen is the obvious candidate, and the colour-coded cooldown survives a shrink to 45mm where an arc and a numeral would not. |
| **Exercise library** | Hevy 400+, Jefit thousands | We ship 16, from the seeded plan. Adding a lift means typing its name — fine for one user, but every new exercise starts with no history and no muscle mapping. |
| **Progressive-overload prompt** — "beat last week" | Track Your Lifts, Boostcamp (auto-progression) | We *show* the last three sessions on the set screen, which is most of the value, but we never suggest the next number. |
| **CSV / data export** | Strong, Hevy, StrengthLog | We have something better for one user — the snapshot the Mac and RIA read — but nothing you could hand to a spreadsheet. |
| **Body measurements + progress photos** | Jefit, StrengthLog, Hevy | We track one number, body weight. Waist and arms are the two people actually use. |

## Landed since the research

| Was missing | Now |
| --- | --- |
| Total volume / tonnage per session | On Today, compared to the last time you did that same day; `gym volume` for weekly totals |
| PR detection | The set screen announces the one record a set beat — heaviest, best e1RM, or most reps at that weight |
| Estimated 1RM | Epley, capped at 12 reps, used for the e1RM record |
| **Set types** | Warm-up / working / drop / to-failure. Warm-ups are excluded from tonnage, records, muscle counts, the next-target suggestion and the CSV's volume column — this was the correctness gap, not a nicety |
| **RPE per set** | 6–10 in half steps, labelled by reps in reserve. `0` means not recorded, which is deliberately different from "easy" |
| **Per-set notes** | Kept with the set, exported in the CSV |
| **Supersets** | Link an exercise to the next; between them the timer gives 20s to walk over and says "Move", and the real cooldown waits for the end of the round. The pairing had to exist in the model because otherwise the ring is not missing, it is *wrong* |
| **Sets per muscle per week** | On Trends. Primary movers count 1, secondary 0.5 — the usual convention, stated in the code so nobody has to guess why totals are fractional |
| **Exercise library** | 80-entry catalogue with loading and muscles, searchable by name or muscle. Picking a lift now means picking one, not describing one |
| **Progressive overload prompt** | One sentence on the set screen from the last session: hit every rep → the weight goes up; stalled → hold it; just short → one more rep and it goes up |
| **CSV export** | Sets (with type, RPE, note) and body data, shareable from Settings. The reason leaving is possible |
| **Body measurements** | Waist, chest, hips, thighs, arms, calf, neck, shoulders — on Trends, with the change since the previous reading |

## Still missing, deliberately deferred

| Gap | Why not yet |
| --- | --- |
| **Rest timer as a Live Activity / Dynamic Island** | Needs a widget extension target and an app group. Worth doing — the cooldown *colour* is designed to be caught peripherally and currently cannot be seen from the lock screen at all — but it is a new build target rather than a change to this one |
| **Apple Watch app** | A second target and a second UI. The set screen is the obvious candidate and the colour-coded cooldown is deliberately designed to survive the shrink; nothing about the model is in the way |
| **Progress photos** | Storage, privacy and a picker. Measurements landed; photos are a different shape of problem, and the snapshot-goes-to-iCloud-Drive rule would need thinking about first |

## Things everyone has that we should not build

Saying no is the point of a personal app.

- **A social feed, leaderboards, friends.** Hevy's differentiator. There is one
  user. Even the shape of it is wrong here.
- **Streaks.** Cheap motivation that turns a deload week into a failure state.
  The tonnage comparison does the reinforcement job without punishing rest.
- **AI-generated routines** (HevyGPT, Fitbod's auto-programming). RIA is right
  there and already knows the log — if this ever happens, it happens through
  her, not as a second brain inside the app.
- **A paywall, accounts, onboarding.** Not a product.
- **Calorie estimates on strength workouts.** Deliberately refused already —
  see `HealthSync.bounds`. A MET guess lands in the same ring as the watch's
  measured numbers.

## What we have that they mostly don't

- **The cooldown as a temperature** — the ring and the room cool from ember to
  teal, readable peripherally. Everyone else has a rest timer; nobody encodes
  its state in colour.
- **Stored gym passes**, with state (uses left, punches, expiry), importable
  from a screenshot. This is normally a separate wallet app.
- **A CLI and an assistant that can read the log.** `gym today` on the Mac, and
  RIA answering "how's the bench going" without being asked to open anything.
- **Plate math in real bumper-plate colours**, which most loggers do as plain
  numbers if at all.

## Sources

- [Best Workout Apps 2026 — JEFIT](https://www.jefit.com/blog/best-workout-apps-for-2026-top-7-options-tested-and-reviewed)
- [Strong App Review 2026 — RepReturn](https://repreturn.com/strong-app-review/)
- [Boostcamp vs Strong](https://www.boostcamp.app/vs/strong) · [Alternatives to Hevy](https://www.boostcamp.app/alternatives/hevy)
- [Hevy — exercise programming options](https://www.hevyapp.com/features/exercise-programming-options/) · [workout settings](https://www.hevyapp.com/features/workout-settings/) · [how to calculate RPE](https://www.hevyapp.com/features/how-to-calculate-rpe/) · [sets per muscle group per week](https://www.hevyapp.com/features/sets-per-muscle-group-per-week/) · [gym performance tracking](https://www.hevyapp.com/features/gym-performance/)
- [Hevy on the App Store](https://apps.apple.com/us/app/hevy-workout-tracker-gym-log/id1458862350) · [Strong on the App Store](https://apps.apple.com/us/app/strong-workout-tracker-gym-log/id464254577)
- [Fitbod — tracking volume, intensity, frequency](https://fitbod.me/blog/best-app-for-tracking-weightlifting-volume-intensity-frequency/)
- [Best fitness apps for tracking volume, sets, recovery — JEFIT](https://www.jefit.com/blog/best-fitness-apps-tracking-volume-sets-recovery-2026)
- [StrengthLog](https://www.strengthlog.com/strengthlog-bodybuilding-app/) · [Liftlog+](https://liftlog.plus/)
- [Best strength training apps on Apple Watch 2026](https://www.findyouredge.app/news/best-strength-training-apps-apple-watch-2026)
