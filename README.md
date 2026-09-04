# Rathi Fitness

A personal gym app. iPhone-first, RIAKit's design language, readable by RIA.

Status: **shipped and installed.** The signed build has been on the phone since
2026-08-20, with iCloud sync and Health on. `design/ios-first-pass.html` is the
original mockup and is now a historical record, not a spec — the app has moved
past it. (This line said "design only, no Swift written yet" for two months
after the app shipped, which is exactly the kind of stale note that makes a
reader distrust the rest of the file.)

## What it does

| Ask | Where it lives |
| --- | --- |
| Log an exercise + current body weight, see trends over time | Trends tab — body weight chart (and where you log a weigh-in), working weight table |
| Store QR codes | Pass tab — check-in code at full brightness, plus guest/punch passes. Scan with the camera **or pull the code out of a screenshot you already have**. QR, Code 128, PDF417 and Aztec. |
| A checklist for each day showing what to do | Today tab — the day's plan, one live row at a time |
| Look back at past sessions | Swipe left on Today. Read-only summaries, newest first — see below. |
| Set / cooldown counter per exercise | The set screen, pushed from a Today row |
| Schedule | Settings → When you train. Fixed weekday, **rotating on chosen days**, or every N days. |
| Edit the programme | Settings → Edit the plan, or the calendar button on Today. Create/rename/reschedule/delete days, add-remove-reorder exercises, edit targets and rest, create new exercises. |
| Cardio | Treadmill, bike, rower, elliptical, stairs and the rest — their own screen, with time, distance, incline, speed, resistance and heart rate. Each machine offers only the numbers its console has. **Progresses like the weights do** — "try 2.1 mi, you covered the distance last time" — one dimension at a time. |
| Assisted machines | Pull-up/dip assist, where the weight makes it **easier**. Records, progression, the trend arrow and the suggestion all run the other way, and tonnage counts **bodyweight − help** rather than nothing. Toggle it on any exercise. |
| Machine settings | "2 on the leg press" — kept with the exercise, shown at the top of its screen, and readable from the Mac with `gym machines`. |
| Music | Today and the set screen — cover art, one solid play/pause in the room's current colour, and skip. Your **Apple Music library playlists**, played by this app. |
| Defaults | Settings → New exercises. Sets, reps, rest and cardio length a new plan slot opens on, so you stop correcting 3 × 10 every time. |
| Reset every rest | Settings → New exercises → **Apply rest to the whole plan**. Pushes the Rest dial through every strength slot on every day, with a confirmation that names the count. Cardio is left alone — its "rest" is the gap between intervals. |
| Hands-free | AirPods: press = play/pause, double = next track, **triple = log the set**. Settings → AirPods to remap. No narration — a ping, not a sentence. |
| Apple Health | Weigh-ins come **from** Health (your scale writes there); finished sessions go back as workouts. Needs the entitlement — see below. |
| Everything you have lifted | Trends — lifetime tonnage against a ladder of things that weigh a known amount (a grand piano, a rhinoceros, a blue whale, the Statue of Liberty), plus workouts, reps and records as lifetime totals. |
| Every day you trained | Trends — twenty-six weeks as squares, shaded by how much you moved. Deliberately **not** a streak: nothing resets, and a blank fortnight is visible rather than a failure state. |
| Records, kept | Trends — the records you have actually set, newest first. The app used to tell you a set was a record and never mention it again. |
| Showing up | Today, under the workout — twelve weeks as twelve marks, and how much of your plan you **covered** each week. Four workouts in the plan, four to get round to; which weekday you did them on is not the question. Deliberately not a streak: nothing resets. |

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

## CI — what will fail your PR

The shipping guards come from the shared template at `~/RIA/templates/ci`, so
this repo did not invent them: `bootstrap` installed them and
`bootstrap --check` reports when the template has moved on. `guards.conf` holds
the facts about *this* project; the shared logic is never edited here.

Run them yourself before pushing:

```
BASE_SHA=$(git merge-base HEAD origin/main) HEAD_SHA=$(git rev-parse HEAD) \
  bash .github/scripts/guards.sh all
bash .github/scripts/guards.d.test.sh    # this project's own guards
```

On top of the template's eleven — docs, tests, changelog, version-sync,
bump-level, retro, follow-ups and the rest — three are specific to this app and
each exists because it broke:

| Guard | Fails when |
| --- | --- |
| `snapshot-schema` | `Snapshot.currentSchema`, `SCHEMA_SUPPORTED` in `cli/gym` and the history table in `docs/SNAPSHOT.md` disagree. The contract has three ends in two languages and they cannot be derived from each other; when they drifted, `gym` went blind on the Mac and nothing failed until the next `gym today`. |
| `house-style` | A stock `Form` appears in `Views/`, or a colour is declared outside `RFDesign`. Settings and the plan editor were the only screens that did not look like the app, and the diagnosis was a grep. `List` is still allowed — `onMove` and `onDelete` are real features. |
| `icon-ladder` | The icon set is missing any of the thirteen iOS sizes. A lone 1024 renders a correct home screen and a **blank notification icon**, and this app notifies you when a rest ends. |

The build itself is `ci.yml`: the `gym` CLI tests on Ubuntu, and the Swift build
and test suite on `macos-15` — the latter gated on `app/` having changed,
because macOS minutes bill at **10x** on a private repo and a docs-only change
should not spend them.

## Installing on the phone

**Automatically, from `main`.** `make autoinstall-install` turns on a launchd
agent that polls `origin/main` every ten minutes and, when it moves, builds and
installs over Wi-Fi. `make autoinstall-uninstall` turns it off,
`make autoinstall-status` says what it last did, and the log is at
`~/Library/Logs/rathi-fitness/autoinstall.log`.

This is the `app/` half of what RIA's auto-deploy does for the server, and it
exists because that one deliberately does not touch native faces: an `app/`
change could be merged, green in CI, and still not on the phone for weeks.

It never interrupts a workout — if the app is open on the phone it skips and
tries again later, because installing over a running app terminates it. It also
only acts on a clean `main`, refuses a diverged remote rather than resetting
anything, and builds before it touches the device, so a broken commit leaves the
phone with the build it already had. `make autoinstall-test` runs its sixteen
cases against a throwaway repo and stub tools.

### By hand


Two builds, and the difference matters.

**Full build — needs an Apple ID signed into Xcode.** This is the one that
syncs and that RIA can read.

```
cd app && xcodegen generate
xcodebuild -project RathiFitness.xcodeproj -scheme RathiFitness \
  -destination 'id=<device-id>' -derivedDataPath /tmp/rf-device \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device <coredevice-uuid> \
  /tmp/rf-device/Build/Products/Debug-iphoneos/RathiFitness.app
```

**The two device IDs are different and are not interchangeable.**
`xcodebuild -destination id=` wants the hardware ECID
(`xcodebuild -showdestinations`); `devicectl` wants the CoreDevice UUID
(`xcrun devicectl list devices`). Passing one where the other belongs gets you
"Unable to find a device matching the provided destination specifier", which
reads like the phone is unplugged.

The full build is the one installed as of 2026-08-20, and it works: the
entitlements are in the binary, the container exists, and `gym today` on the Mac
reads the phone's real sessions out of
`~/Library/Mobile Documents/iCloud~com~rathi~fitness/Documents/snapshot.json`.

**Local-only build — works with no developer account.** Signs against the
wildcard team profile by claiming no capabilities:

```
xcodebuild ... CODE_SIGN_ENTITLEMENTS=RathiFitness/RathiFitnessLocal.entitlements \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) RF_LOCAL_ONLY' build
```

This is a real app on the phone — log sets, track weight, run the cooldown,
store passes — but **no CloudKit sync and no snapshot**, so `gym` on the Mac
sees nothing and RIA is blind to it. `RF_LOCAL_ONLY` is a compile flag rather
than just stripped entitlements, and that is load-bearing: on a real device you
*are* signed into iCloud, so the runtime check would say CloudKit is available
and walk straight into the trap it exists to avoid.

To upgrade a local-only install to the full one: sign into Xcode
(Settings → Accounts → +, your Apple ID), then run the full build above. Xcode
registers the App ID, creates the `iCloud.com.rathi.fitness` container and
regenerates the profile. Nothing in the code changes.

## Scheduling: fixed days, rotating content

The first model bound a workout to a weekday — `Push A = Wednesday`. That cannot
express the common case, which is Ishan's: **you train on fixed days and the
content rotates.** Three sessions a week (Tue/Thu/Sat) through a four-workout
rotation means the pairing drifts every week:

    Tue  Thu  Sat  │ Tue  Thu  Sat  │ Tue
     1    2    3   │  4    1    2   │  3

No day-to-weekday mapping is right for more than seven days. So there are three
modes (Settings → When you train):

- **Same workout each weekday** — the original, right for a fixed weekly split.
- **Rotating, on chosen days** — pick the weekdays; the workouts cycle in plan
  order.
- **Rotating, every N days** — counted from the last session you actually did,
  not from the calendar.

**Position in the rotation is derived, never stored.** A cursor incremented on
completion goes wrong the first time you log a session late, delete one, or
train twice in a day — and nothing tells you it has. Counting the sessions you
have actually logged is self-correcting: skip a week and you pick up exactly
where you left off, which is what a rotation is for. `RotationTests` walks three
real weeks and asserts the drift.

## The cooldown ping, and why the app plays your music

Two of these features are the same feature wearing different hats, and the
reason is worth stating once.

**The ping.** The last three seconds of a rest tick — a light haptic and a soft
blip each — and then the handover is a rising two-note chime plus a haptic
swell. Both channels fire every time, because the phone is in a pocket and the
AirPods might be out; either one alone is a cue you can miss, which is the
whole reason people stand there staring at the screen while they rest. The
patterns are authored in `Haptics.swift` and the tones are *synthesised* in
`AudioHub.swift` rather than shipped as audio files, so retuning a chime is
changing two numbers rather than opening an editor.

The old behaviour — one `UINotificationFeedbackGenerator` success buzz — was
indistinguishable from a text message arriving.

**Why the app plays the music.** iOS delivers an AirPods squeeze to whichever
app is *currently now-playing*, and to nobody else. There is no public API for
"control whatever is playing", and there is no way to receive a gesture while
the Music app or Spotify holds that role. So:

- remote-controlling the Music app (`MPMusicPlayerController.systemMusicPlayer`)
  is three lines and permanently deaf to the AirPods, and
- playing the music ourselves (`ApplicationMusicPlayer`, MusicKit) makes this
  app the now-playing app, which is the only way a triple-press ever arrives.

The second was chosen because hands-free logging is the point. The cost is
real: the queue lives in this app rather than in Music, and the App ID needs
the MusicKit service. Without it — and on the local-only build — the music bar
reports itself unavailable rather than failing at a button, the same shape as
the Health message.

When hands-free is armed and no music is playing, the app loops a buffer of
**silence** to keep the now-playing role. That is a trick and it is written
down as one in `AudioHub.holdRemoteControl`: it is the documented cost of
hearing a squeeze, it puts the workout on the Lock Screen so the role is not
invisible, and it stops the moment you leave the set screen.

## AirPods: three gestures, one of them yours

iOS gives an app a press, a double press and a triple press — that is the whole
vocabulary, and press-and-hold is noise control which never reaches an app.
The default mapping keeps the two everybody already knows:

    press   → play / pause
    double  → next track
    triple  → log the set, and start the cooldown

Triple gets the workout because it is the gesture nobody performs by accident.
While the cooldown is *already* running there is no set to log, so the same
squeeze skips the rest instead — the two things the screen offers at those two
moments. Every mapping is editable in Settings → AirPods, because whether a
triple-press is comfortable through a hoodie depends on the hoodie.

**Gestures only do workout things on a set screen.** `RemoteControls.Handlers`
is filled in by `SetView` when it appears and cleared when it leaves, so a
squeeze from the Trends tab controls music and nothing else. A phantom set
logged from a screen that does not know which exercise you are on would be
worse than having no gestures at all, and `HandsFreeTests` asserts it cannot
happen.

**It does not narrate.** The first cut read the set back to you when a squeeze
logged it and named the lift when the cooldown ended. That was wrong: a rest
ending is one bit of information arriving while you are catching your breath,
and a sentence about it is the app talking over your music to say what the
chime already said. The ping is the whole message. The one thing that still
speaks is the "say where I am" gesture, which speaks because you squeezed to
ask.

## Settings and the plan editor are drawn by hand now

They used to be the only two screens built out of a stock `Form`, and they were
the only two that did not look like this app. That was measurable rather than a
matter of taste: between them they used **zero** of `rfEyebrow`,
`RFDesign.figure`, `RFDesign.title` or the hairline, while Today alone used
twelve.

`.scrollContentBackground(.hidden)` hides a list's background and nothing else.
The rows keep their own corner radius, their own separators inset from the
margin, and San Francisco — in an app whose one typographic rule is that the
serif is your numbers. The container was the problem, so the container went.

`Views/SettingsKit.swift` is the replacement: `SettingsSection`, `SettingRow`,
`StepperRow`, `ToggleRow`, `ChoiceRow`, `ActionRow`, `DisclosureRow`,
`StatusLine` and `SettingsScaffold`. Every value comes from `RFDesign`, and any
screen written after these two gets them for free.

Three things came out of it beyond the typeface:

- **Settings opens on what is true right now** — Health, Music, hands-free, the
  snapshot — before anything you can change. It had grown to eleven sections,
  all of them things you set once, and the question you actually open it with
  is "is Health still connected".
- **The plan item is a workbench.** Sets, reps, weight and rest are tappable
  Fraunces figures with a stepper under the selected one. Editing the plan is
  the same act as logging a set — you are setting a number — so it gets the
  same treatment, and the commonest edit in the app stops being four screens
  deep.
- **`List` survives in exactly two places**, and on purpose: the day list and
  the exercise list inside a day, because `onMove` and `onDelete` are real
  features and reimplementing drag-to-reorder to win a typeface is a bad trade.
  Both are stripped of their background, row fills, separators and insets, so
  what is left is the app's own row on the app's own ground.

## Swiping back is read-only, on purpose

Swipe left on Today to walk backwards through the days you actually trained.

**Past days are summaries, not checklists, and that is the design rather than a
shortcut.** Today is live: tapping a row opens the set screen, and logging
writes `Date.now`. Make yesterday swipeable in that same form and the first
thing that happens is a set logged into the wrong day — silently, because the
screen you were looking at said Tuesday. So a past day shows what you did, what
it added up to, and offers no way to add to it.

**The paging unit is sessions, not calendar days.** Most days are rest days;
swiping through them would mostly show nothing. It caps at sixty, because
nobody thumbs back three months.

Which workout a past day *was* is worked out from the exercises logged, not
from the weekday — the programme rotates, so "Push A is Tuesday" is wrong
within a fortnight. `PastDayView` matches the logged lifts against each planned
day's contents, and says nothing rather than guessing when an improvised
session matches none of them.

## Cardio is measured in minutes, not pounds

A treadmill has its own screen (`CardioSetView`), because it shares almost
nothing with a bench: no plate math, no rep target, and a clock rather than a
weight as the headline figure. One screen doing both would have been a column
of `if isCardio` and two half-designs.

**Each machine offers only the numbers its own console has.** A rower has no
incline and a treadmill has no damper, so `Exercise.metrics` is a per-machine
list from `CardioMetric` — time, distance, speed, incline, resistance, heart
rate. Offering every field on every machine is how a logging screen becomes one
you skip. Absent on purpose: calories (the console's guess and the watch's
measurement land in the same ring and disagree — the same argument that keeps a
burn out of the Health export), watts and cadence (nothing in a normal gym
reports them).

**It records; it does not time you.** The machine in front of you already has a
clock, a distance and a grade on a display the size of a laptop. An app racing
it would be a second number that disagrees. You copy the console over when you
step off — which is the actual gap, because otherwise that number exists
nowhere ten seconds later.

**Cardio never becomes tonnage.** Volume is weight × reps and a treadmill has
neither; a pounds-equivalent means inventing a rate nobody measured. So a bout
contributes *minutes*, minutes are reported as minutes, and cardio is kept out
of the working-weight table and out of `top_lifts` — "Treadmill 0" is what
happens when it is not. Trends grows a cardio block; `gym cardio` is the same
answer on the Mac.

Health gets each bout as its own workout of its own type (running, cycling,
rowing…) with a distance sample where Health has one for it. A thirty-minute
run filed as `traditionalStrengthTraining` — which is what a day used to become
— gets no distance, no pace, the wrong icon in Fitness, and is read as lifting
by Apple's own trends. A stair climber and a jump rope write no distance at all
rather than an invented walking one.

## Machines where the weight makes it easier

An assisted pull-up machine counterweights you: 100 lb of help is a much easier
set than 40, and getting stronger means the number going **down**.

Every piece of arithmetic in the app assumed the opposite, and none of the
failures looked like failures — they all produced plausible numbers pointing the
wrong way:

- a 100 lb assist registered as a **heaviest-ever personal best**;
- hitting all your reps suggested **adding** help next time;
- the assistance counted as **tonnage moved**, so the more help you needed the
  better the session looked — 100 lb × 8 reads as 800 lb "moved";
- the 30-day arrow on Trends went teal when the help went **up**;
- `best` in the snapshot exported the day you needed the most help, and RIA
  reads that file out loud.

So `Exercise.assisted` is a flag on the exercise, and everything with an opinion
about the number checks it. A record becomes the least help you have ever
needed (and "Unassisted — no help at all" when it reaches zero). Progression
takes help off and floors at zero. Assistance is excluded from tonnage entirely,
for the same reason bodyweight movements are: converting it to
bodyweight-minus-assistance means storing a bodyweight per set and guessing for
every day you did not weigh yourself.

Two smaller decisions inside it:

- **A flag, not a signed weight.** Storing assistance as −100 would put a minus
  sign into every display, stepper and chart that then has to explain it, and
  one forgotten `abs()` would drop a negative into a total.
- **The rep record is stricter here than for lifts.** The exact mirror would be
  "most reps at this help or less", which is true and awful: adding help almost
  always buys reps, so every deload would manufacture a record and the app would
  cheer each step backwards. It only counts at your hardest setting to date.

`SetEntry.tally` exists because of this. Nine call sites built `Tally.Set` by
hand and every one of them would have silently defaulted the flag to false —
one converter means a rule added to the value is a change in one place.

## "2 on the leg press"

The seat position is a real thing you have to remember every week, and it was
nowhere in a set log — so you rediscover it by sitting down and finding out it
is wrong.

It belongs to the **exercise**, not to a set: the seat does not change between
Tuesday and Thursday, and recording it per set would make you re-enter it four
times an evening. It sits at the top of the exercise's screen, is editable from
there or from the plan, and rides along in the snapshot so `gym machines` can
tell you where the pin goes before you leave the house.

The dials are an enum (`MachineSettingKind` — seat, back pad, seat depth, chest
pad, leg pad, thigh pad, foot plate, handle, grip, pulley, lever arm, range
limiter, bench angle, rack pins, safety bars, headrest, other) rather than free
text, so you cannot end up with "seat" and "Seat height" as two different
things — which is exactly how a notes field for this would have decayed. The
*value* is free text, because dials are not all numbers: "2", "hole 12", "30°",
"wide".

**One editor, presented two ways.** You set the seat standing in front of the
machine and you edit the programme sitting at home, so `MachineSettingsEditor`
appears as a sheet from the chips on the set screen and as a pushed screen from
the plan. It was briefly a pushed screen whose only trick was opening the
sheet — a modal on top of a push, to change one number.

## Apple Health

Body mass is read from Health once connected — the scale is the source of truth
and typing a number here is the fallback. Weigh-ins entered in the app are
written back, and finished sessions (whole past days only) go over as
`HKWorkout`s so they land in Fitness and on the watch.

Workouts carry a **duration and no calorie estimate**. A MET formula would let
us write a burn, and it would be a guess landing in the same ring as the watch's
measured numbers.

Like CloudKit, HealthKit needs an entitlement a wildcard team profile cannot
carry, so the local-only build reports Health as unavailable rather than failing
at the permission sheet — that is the "no Health entitlement" message, and it
means you are running that build, not that something is broken.

The signed build carries `com.apple.developer.healthkit` and turns Health and
iCloud sync on together. Connect it in Settings → Apple Health.

**The connection survives closing the app**, which it did not at first. `status`
began every launch at `.notAsked` and only ever became `.connected` in memory,
so quitting forgot it: Settings offered "Connect Apple Health" again, and — the
part you would not notice — the launch sync is gated on `isConnected`, so
weigh-ins quietly stopped arriving until you tapped the button. The permission
was never the problem. The app just never asked whether it had one.

`HealthBridge.resume()` asks on launch, and the question matters:
`getRequestStatusForAuthorization` answers *"would asking show a sheet"*, not
*"am I authorised"*. HealthKit will not answer the second for read types on
purpose, since the answer leaks what is in your Health app. `.unnecessary` means
every type has been answered, which is exactly what "connected" has always meant
here.

## The app icon

**RIA's face goes in the middle, and that is a house rule.** Every app in the
RIA family carries her — this app is not an organ of RIA (she only reads it),
but it is hers the way a badge is, and a home screen full of unrelated marks is
how a family of apps stops looking like one.

It is her **face**, not her name. The first cut set the letters "RIA" in
Fraunces, which is a label about her rather than a picture of her. The mark is
the character: `RIAIcon.swift` in the RIA repo renders the live `FacePanel`
rather than a drawing of it, precisely so an icon cannot disagree with the
creature the app runs.

That reasoning crosses repos, which is why this script does not redraw her in
PIL. It uses **`ria_icon`, the shared kit at `~/RIA/app/icons/ria_icon.py`**,
which composites the real transparent render `swift run RIAIcon` produces. A
future satellite app brings its own motif and takes the ground, her light, her
face and the iOS size ladder from the same place. If the kit is not on disk —
it lives in the RIA repo, so only on branches that have it — this script says
so and exits; the committed PNGs are unaffected.

**The whole ladder, not just the 1024.** A lone 1024 renders a correct home
screen and a *blank notification icon*: Xcode derives the 60pt and 76pt
renditions from it and none of the small ones, so the 20pt a notification draws
is simply absent from the bundle. This app pings you when a rest ends, so that
banner is the feature, not a corner case.

`python3 design/make_icon.py` renders it — the cooldown ring, ember to teal, on
the RIAKit ground. The colours come from the same ramp the app draws with rather
than from an eyedropper, so retuning the mechanic and re-running keeps the icon
honest. It deliberately does *not* sample the full hue ramp: the app shows one
value at a time, an icon shows all of them at once, and the yellow-green stretch
between orange and teal would become a third colour the product does not have.

## A note on the toolchain

Xcode reinstalled itself as **`Xcode-beta.app`** (27.0), not `Xcode.app`, and
left `xcode-select` pointing at CommandLineTools. Builds therefore need:

    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

or `sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer` once.

Two tests skip on that runtime: Vision cannot create an inference context in
this simulator, so the code round-trip cannot run there. It works on the device.

**It fails a second way on CI**, which only showed up once the suite ran on a
machine that was not this one: the runner's simulator *does* start Vision, runs
the detection, and finds nothing — surfacing as `Failure.nothingFound` rather
than a refusal. Same environmental problem, different symptom, so the skip
covers both. `nothingFound` is forgiven **only** under
`#if targetEnvironment(simulator)`; on a device it stays a hard failure, because
a pass that renders and cannot be read back is exactly the bug that test exists
to catch.

The cost is worth stating plainly: **the round-trip verifies nothing in CI.** It
is a device property. What CI still covers is that the scanner, the importer and
the renderer agree on the same set of formats — pure logic, and the likelier
regression anyway.

## Not decided yet

- Whether the Blink check-in code is static (storable) or rotating (not).
  Needs the real card, not a guess.
- Whether the cooldown hue ramp survives contact with an actual workout.
- Watch app. The set/cooldown screen is the obvious candidate and is designed
  so its state reads as colour, which survives a 45mm face.
