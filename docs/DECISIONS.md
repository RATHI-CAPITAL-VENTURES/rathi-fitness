# Decisions

Newest last. Each entry records what was chosen, what was rejected, and why —
including the ones that turned out to be wrong, so they are not re-litigated.

## 2026-08-20 — Project opened

**Name: `rathi-fitness`, CLI `gym`.** Personal use only, so brandability was
not worth optimising for; typeability was. `gym today` reads as English and
sits next to `rathi-industries` in `~/RIA/projects/`. Rejected: `RiaFitness`
(implies it is an organ of RIA, which it is not — RIA only reads it), `Iron`
(a name for a product with users).

**iOS: standalone app, RIAKit tokens.** Rejected: a face inside `app/ios`.
Per ria-2.0/CLAUDE.md, auto-deploy ships the server only and never the native
faces — so every gym tweak would have needed a manual Xcode build and install
onto the phone. A separate app has the same problem for itself but does not
drag RIA's release cadence into it, and it gets its own home-screen slot,
which matters for something opened one-handed in a gym.

**Data: the phone owns it (SwiftData + CloudKit), RIA reads a snapshot.**
The correctness constraint is that the app must work with no signal in a
basement. The catch found while designing: a CloudKit *private* database has
no Mac-CLI read path — there is no app context to authenticate as — so the
literal reading of "app owns it, RIA reads" is not implementable. Resolved by
having the app also write a JSON snapshot into an iCloud Drive ubiquity
container, which on macOS is a plain file that syncs itself. This is the whole
reason `gym` can exist. Do not "simplify" it back to talking to CloudKit.

**QR codes: a stored check-in pass, not machine-scanning.** Scope chosen
deliberately: the Pass tab holds membership codes, guest passes and punch
cards, with state (uses left, expiry, punches). Explicitly out for now:
scanning a QR on a machine to open that exercise. It needs a per-gym mapping
built by hand and is worthless until that exists.
Open: some gyms issue a *rotating* code, which no wallet can store. Unknown
for Blink until the real card is checked.

**Cooldown is a temperature.** The rest ring starts ember and cools to teal,
holding warm for the first three quarters and handing over in the last. This
is the port of RIA's "her state is the accent" (DESIGN.md) onto "your state is
the accent". It is the one deliberately risky idea in the first pass; it is a
single hue-ramp function, so rejecting it costs a constant. Second argument
for it: colour survives a shrink to a watch face where an arc and a numeral
do not.

**Rejected during the first design pass:**
- A solid, full-width primary button while resting. The loudest thing on
  screen would have been *Skip to set 4* — the control that undoes what the
  screen is for. It is outlined while the clock runs, solid teal at 0:00.
- Splitting body weight and working weight into separate tabs. They answer one
  question ("am I getting stronger or just heavier"), so they share a screen.
- `+0` as a 30-day delta. A dash means it ended where it started; a zero
  implies a measured change that came out zero. Different facts.

## 2026-08-22 — Sound, music and the AirPods

**The cooldown gets two channels, always.** A haptic pattern *and* a tone, for
every cue, every time. The phone is in a pocket and the AirPods may be out;
either channel alone is one you can miss, and a missed handover is the reason
people stand there watching the ring instead of resting. Three ticks in the
last three seconds so the end is something you arrive at rather than something
that happens to you.

Rejected: the previous behaviour, one `UINotificationFeedbackGenerator`
`.success`. It is the system's pattern, so "rest is over" felt exactly like a
text message arriving — which is the one thing it must not feel like.

Rejected: shipping the chime as a `.caf`. The tones are synthesised from a
short score in `AudioHub.score(for:)`, because a chime nobody can retune
without an audio editor is a chime that stays wrong.

**The app plays the music itself (MusicKit `ApplicationMusicPlayer`).** Not
the obvious choice, and the reason is not about music at all: iOS delivers an
AirPods squeeze to whichever app is *currently now-playing*, and to nobody
else. There is no public API for "control whatever is playing".

So `MPMusicPlayerController.systemMusicPlayer` — three lines, keeps Music's
queue and UI — is permanently deaf to the AirPods, and Spotify's App Remote
has the same problem plus a developer registration. Owning playback is the
only path to hands-free logging, so it won.

Stated costs, so nobody re-litigates this as a simplification: the queue lives
in this app rather than in Music, the App ID needs the MusicKit service, and
the Apple Music *catalogue* is deliberately absent — a gym app plays the list
you already made. Without the service the music bar reports `.unavailable`
rather than failing at a button, the same shape as the Health message.

**Holding the now-playing role with silence.** When hands-free is armed and no
music is playing, `AudioHub.holdRemoteControl` loops a silent buffer to keep
the role so a squeeze still arrives. This is a trick and it is documented as
one at the call site: it is the price of hearing a triple-press, it publishes
the workout to the Lock Screen so the role is not invisible, and it is dropped
the moment the set screen goes away.

**Triple-press logs the set; the same squeeze skips the rest while resting.**
Three gestures exist and no more (press-and-hold is noise control and never
reaches an app). Press and double keep what everyone already knows; triple gets
the workout because it is the one nobody performs by accident. It is
context-sensitive in exactly one way — mid-rest there is no set to log — and
those two meanings are the two buttons the screen is offering at those two
moments.

Rejected: making every gesture context-sensitive. Ambiguity you cannot see is
worse hands-free than a mapping you can learn.

**Handlers belong to the screen, not to the app.** `RemoteControls.Handlers`
is filled in by `SetView` on appear and cleared on disappear, so a squeeze from
the Trends tab controls music and nothing else. A phantom set logged by a
screen that does not know which exercise you are on would be a worse bug than
having no gestures at all; `HandsFreeTests` asserts the refusal.

## 2026-08-22 — The ping does not talk

**Rejected, hours after shipping it: spoken confirmations.** The first cut of
hands-free read the set back when a squeeze logged it ("set three, one eighty
five for eight, resting ninety seconds") and named the lift when the cooldown
ended.

The reasoning was that a tone tells you *something* happened and only a
sentence tells you *what*. The reasoning was wrong about which question you
have. A rest ending is **one bit of information**, arriving while you are
catching your breath — you already know what you just lifted and what is next,
because you set it up thirty seconds ago. The sentence is the app talking over
your music to say what the chime already said.

So: `AudioHub.say` has exactly one caller left, the `announce` gesture, which
speaks because you squeezed to ask it something. The `cue.speaks` setting is
gone rather than defaulted off — a toggle for a feature nothing uses is a
setting that exists to be explained.

Kept: both channels of the ping itself. Three ticks, then a chime and a haptic
swell. That is a signal, not narration.

## 2026-08-22 — Cardio, and where the seat goes

**Cardio gets its own screen and its own units.** A treadmill shares almost
nothing with a bench — no plate math, no rep target, a clock rather than a
weight as the headline figure — so `CardioSetView` is a second screen rather
than a mode on `SetView`. One screen doing both would have been a column of
`if isCardio` and two half-designs.

**Modality is a separate axis from loading.** `Exercise.loading` is about what
goes on a bar; a treadmill has no loading style and a barbell has no incline.
Folding them into one enum would have made every switch answer two questions at
once. Rejected: adding a `.cardio` case to `Loading`.

**Cardio contributes minutes, never tonnage.** Volume is weight × reps and a
treadmill has neither. A pounds-equivalent would put an invented number into the
one figure on Today that is supposed to be countable, so `Tally.Bout` is a
separate vocabulary from `Tally.Set`, `sessions[].volume` stays lifting-only,
and cardio is excluded from the working-weight table and from `top_lifts`.
"Treadmill 0" is what the alternative looks like.

**Each machine declares its own metrics.** A rower has no incline, a treadmill
no damper. `Exercise.metrics` is a per-machine list from `CardioMetric`, and the
logging screen renders exactly those. Offering every field on every machine is
how a screen becomes one you skip.

Rejected inside `CardioMetric`: **calories** — the console's guess and the
watch's measurement land in the same ring and disagree, which is the argument
that already keeps a burn out of the HealthKit export. **Watts and cadence** —
nothing in a normal gym reports them, and a field nothing fills teaches you to
skip the screen.

**It records; it does not time you.** No in-app stopwatch for cardio. The
machine has a clock on a display the size of a laptop, and a second one that
disagrees is worse than none. The gap being filled is that the console's number
exists nowhere ten seconds after you step off.

**Averages inside a cardio block are weighted by time.** A five-minute flat
walk must not pull a twenty-five-minute climb's grade down as though equal.
Nobody reading "average incline" would guess a plain mean.

**Each bout goes to Health as its own workout of its own type.** A day used to
become one `traditionalStrengthTraining` workout; a run filed that way gets no
distance, no pace, the wrong icon in Fitness, and is read as lifting by Apple's
own trends. Machines with no distance Health understands — stair climber, jump
rope — write none rather than an invented walking distance that would inflate a
ring nobody earned. Heart rate is deliberately not written: what we hold is an
average typed off a console, and a single sample stamped across thirty minutes
would overwrite a watch's real series with one number.

**Machine settings belong to the exercise, not to the set.** The seat does not
change between Tuesday and Thursday, and recording it per set would make you
re-enter it four times an evening.

The *dials* are an enum and the *values* are free text, and both halves matter.
An enum stops "seat" and "Seat height" becoming two different things — which is
exactly how the obvious alternative, a notes field, would have decayed within a
month. Free-text values are because dials are not all numbers: "2", "hole 12",
"30°", "wide". A numeric field would have forced a lie on half of them.

Rejected: keeping it in the exercise's note. A workaround for a missing field
becomes the permanent shape of the data, because nobody re-migrates a notes
field.

## 2026-08-24 — Machines where the weight makes it easier

**`Exercise.assisted`, and everything with an opinion about the number checks
it.** An assisted pull-up machine counterweights you, so 100 lb of help is an
easier set than 40 and progress is the number going down.

This was not a missing feature, it was five live bugs, and the reason none had
been noticed is that every one produced a *plausible* number pointing the wrong
way: a heaviest-ever PR at maximum assistance, a suggestion to add help after a
good session, assistance counted as tonnage (so needing more help improved the
totals), a teal trend arrow for regressing, and `best` exporting the worst day
to the file RIA reads aloud.

**A flag, not a signed weight.** Rejected: storing assistance as −100. It would
put a minus sign into every display, stepper and chart that then has to explain
it, and one forgotten `abs()` puts a negative into a total.

**Assistance is excluded from tonnage rather than converted.** Rejected:
bodyweight-minus-assistance. It needs a bodyweight per set and a guess for every
day you did not weigh yourself — the same invention that already keeps push-ups
out of tonnage. Excluding is honest; converting is a number nobody measured.

**No estimated one-rep max on a counterweight.** Epley applied to assistance is
arithmetic without a meaning, and it would produce a number — which is exactly
the danger.

**The rep record is stricter here than for lifts, on purpose.** The exact mirror
of "most reps at this weight or above" is "most reps at this help or less". It
is technically true and practically awful: adding help almost always buys reps,
so every deload manufactures a record and the app cheers each step backwards —
the precise failure the flag exists to stop. A rep record on an assisted machine
only counts at your hardest setting to date. The asymmetry with the resisted
rule is deliberate and is the one place the mirror was refused.

**`SetEntry.tally` — one door.** Nine call sites constructed `Tally.Set` by
hand, spelling out weight/reps/kind, and every one of them silently defaulted
`assisted` to false. That is exactly how a pull-up assist ends up in tonnage.
One converter means the next rule added to the value is a change in one place
instead of nine.

**Schema 4.** Adding the field is an addition; what forces the bump is that
`working_weight`, `change_30d` and `best` now MEAN something different on those
rows. A CLI that does not know the flag reads them the old way and congratulates
him for getting weaker, so refusing is the correct behaviour.

## 2026-08-24 — The music bar was the worst-looking thing in the app

**Redrawn as a cover tile on a hairline.** The first cut was a filled
`RFDesign.surface` card, which made the only opaque box in a system whose entire
surface treatment is a dark ground with a pool of light on it — and it sat
immediately under the primary button, so the screen ended in two rounded
rectangles of similar width, the second being the one you care about least. Its
three transport glyphs were identical 30×30 targets: under the 44pt minimum, and
giving "skip" exactly the same weight as "pause".

Four directions were drawn in place before choosing: a chromeless rail, the rail
plus a state-tinted level meter, a single centred line with no controls at all
(on the grounds that the AirPods are the transport), and the cover tile. The
tile won on Ishan's call — the artwork is the only photograph anywhere in the
app, and it makes the row read as something *playing* rather than something
configured, without a frame of animation.

What it keeps from the others: **no card**, a `Divider().overlay(hairline)` like
every other division on that screen, and exactly one filled control —
play/pause, drawn in `RFDesign.coolColor(rest.progress())` so the music cools
with the ring and there is no second opinion about what "now" looks like.

**Previous-track was cut from the row**, not forgotten. On this screen it is the
least-wanted of the three and it was taking the same visual weight as pause; it
lives in the sheet and on the AirPods, where the gesture already exists.

**The placeholder is lit, not grey.** A cover that is merely absent looks like a
failed download, so a track with no art gets a tile carrying the room's colour.

## 2026-08-24 — What a new exercise opens on

**`PlanDefaults`: sets, reps, rest and cardio length.** Every new plan slot was
hardcoded to 3 × 10 at 90 seconds. That is a reasonable guess for a stranger and
wrong every single time for the one person using this app — correcting the same
three numbers on every exercise you add is the app charging rent.

**A model, not `@AppStorage`**, for the same reason `Schedule` is one: it belongs
to the training plan and should follow it between devices rather than sit in the
defaults of whichever phone happened to set it. `PlanDefaultsTests` pins that it
is in the schema, so nobody "simplifies" it into `UserDefaults` and quietly
breaks it across devices.

**It never applies retroactively.** Changing the default does not touch anything
already in the plan, and the footer says so. A setting that silently rewrites
your existing programme is a setting you stop trusting — and there is a test
that walks the seeded plan and asserts every item is untouched afterwards.

## 2026-08-24 — Swiping back to past days

**Read-only, and this is the whole design.** Today is a live checklist: tapping
a row opens the set screen and logging writes `Date.now`. Making yesterday
swipeable in that same form means the first mis-swipe logs a set into the wrong
day — silently, because the screen said Tuesday. So `PastDayView` is a summary:
what you did, what it added up to, and no affordance to add to it.

Rejected: reusing `TodayView` with a date parameter. It is the obvious
implementation and it is the bug.

**Paged by sessions, not by calendar days.** Calendar days are the obvious
paging unit and the wrong one — most of them are rest days, so swiping would
mostly show nothing. Capped at sixty; nobody thumbs back three months, and each
page is a view.

**The day's name is derived from the exercises, not the weekday.** The
programme rotates (see `Rotation`), so a weekday lookup is wrong within a
fortnight. Matching logged slugs against each planned day's contents is right
however far the cycle has drifted, and returns nothing rather than a guess when
an improvised session matches nothing — an hour you made up is not "Push A".

**Past days are drawn in `said`, not `ready`.** History should not glow like
the live screen does; the teal is reserved for what is happening now.

## 2026-08-24 — The Form was the problem

**Settings and the plan editor are drawn from `Views/SettingsKit.swift` now.**
They were the only two screens built out of a stock `Form`/`List`, and the only
two that did not look like this app. The diagnosis was a `grep`, not an opinion:
between them they used **zero** of `rfEyebrow`, `RFDesign.figure`,
`RFDesign.title` or the hairline; Today alone used twelve.

`.scrollContentBackground(.hidden)` had been doing the work of "make it fit in",
and it does not: it hides the list's background and leaves the row radius, the
inset separators and San Francisco, in an app whose one typographic rule is that
the serif is your numbers.

Four directions were drawn before choosing. **01, drawing it in the app's own
primitives, was the only one that addressed the cause** — the rest were
restructures on top of the same container. It shipped whole.

**Taken from 02: the status block only.** Settings had grown to eleven sections
and every one is something you set once; the question you actually open it with
is "is Health still connected". Four lines answer that before anything you can
change. Rejected: 02's full restructure into four destinations — burying
set-once sections behind doors trades a scroll for a hunt, and the status block
gets most of the benefit for a fraction of the churn.

**Taken from 03: the plan item only.** Sets, reps, weight and rest are tappable
Fraunces figures with a stepper under the selected one, because editing the plan
is the same act as logging a set — you are setting a number — and it should look
like it. This also removes the fourth navigation level, which was the one you
hit most often. Rejected: 03 applied to Settings, which is genuinely prose in
places (the Health footer, the AirPods explanation) and would have ended up two
idioms in one screen.

**`List` survives in exactly two places and that is deliberate**: the day list
and the exercise list inside a day. `onMove` and `onDelete` are real features,
and reimplementing drag-to-reorder to win a typeface is a bad trade. Both are
stripped of background, row fills, separators and insets, so what remains is the
app's own row at the app's own margin — the type is house, the gesture is
UIKit's, and neither is pretending otherwise.

## 2026-08-27 — A button whose label cannot be hit

"Add a day" in the plan editor drew correctly, highlighted under the finger,
and did nothing. Not a limit on the number of days — there is none, in the
model or the schedule — but a `Button` whose entire label had been made
untappable.

The shape was a `Button` wrapping an `ActionRow`, which is itself a `Button`.
Two buttons in one row is a fight over the tap, and the fix applied at the time
was `.allowsHitTesting(false)` on the inner one. That does not hand the tap to
the outer button; it removes the only hit-testable content the outer button
has, so the outer button has nothing to hit either. Both were silenced.

**Chosen: the row owns its action.** `ActionRow` already takes a closure, and
"Add an exercise" one screen down had always used it that way. The nesting
bought nothing. Rejected: `.contentShape(Rectangle())` on the outer button to
give it a hit region of its own, which would have worked and would have left
two buttons stacked for no reason.

**Why nobody saw it.** There was no test that pressed it, and there is nothing
to see when it fails — the path logs nothing, and the `context.save()` under it
is written `try?`, so a real save failure would have been just as quiet. The
regression test in `app/UITests/PlanEditingUITests.swift` presses the button and
asserts a fourth day exists afterwards, because "it draws" and "it works" were
different facts here and only one of them was being checked.

## 2026-08-27 — `try?` on a save is a decision nobody made

Twenty-one writes went through `try? context.save()`. None of them was a
judgement that the user did not need to know; the first one set the shape and
the other twenty copied it. If SwiftData ever refused a write, the set you just
logged was gone and the screen carried on as though it were not.

It came up sideways. "Add a day" was doing nothing, and the obvious next move
was to stream the phone's logs while it was pressed — at which point there was
nothing to stream. No log line on the path, no thrown error, no banner. The
cause turned out to be a dead button rather than a failed save, but the
investigation had no instrument either way, and an absent instrument does not
announce itself. You find out the thermometer is missing at the moment you reach
for it.

**Chosen: one mechanism, twenty-one phrases.** `Model/Saving.swift` decides what
a failed write does — log at `.fault`, keep it for the banner, return `false`.
Call sites say `context.saveOrReport("adding a day")` and nothing else. The
string completes "save failed while ___", because the user already knows a save
failed; what they need is which one. `SavingTests` reads every call site back
out of the source and fails on a phrase that has decayed to "saving".

**Rejected: `assertionFailure` in DEBUG.** Tempting, and it would catch a
regression in CI. But the UI tests run a Debug build against a real store, so a
single unlucky save turns a behavioural failure into a crash, and the crash is
what gets investigated. Logging loudly costs nothing and does not change control
flow.

**Rejected: an alert.** Modal, and it would land on top of whatever screen
happened to be showing rather than the one that caused it. The banner follows
the precedent `LegacyDataBanner` already set for "the app has to come and find
you", and sits over every tab because the write could have come from any of
them.

**Deliberately not covered:** `try?` on the haptic engine, `AVAudioSession`,
MusicKit and every `Task.sleep`. Those are best-effort by nature — a haptic that
does not fire costs nothing and has no recovery — and none is a lost workout.
The rule is narrower than "never use `try?`": nothing that writes your training
data may fail quietly. `guards.d/silent-saves.sh` enforces exactly that, and its
self-tests include a case asserting the best-effort ones still pass.

**A note on generated projects, learned expensively.** `app/RathiFitness.xcodeproj`
is written by XcodeGen and gitignored. A new test file added without re-running
`xcodegen generate` is not in the target, and the suite then reports
`** TEST SUCCEEDED **` having executed zero tests. A vacuous pass is worse than
a red build: it is a red build that lies. Run `xcodegen generate` after adding
any file.

## 2026-08-27 — A visual refactor can break behaviour without touching it

`f16e454` rebuilt Settings and the plan editor out of `SettingsKit` because
they were the only two screens that did not look like the app. It was the right
call and the guard that keeps it (`house-style`) still stands. It also killed
"Add a day", and the way it did that is worth writing down because the diff
looked clean.

The change was one word. `Label("Add a day", systemImage: "plus")` became
`ActionRow(label: "Add a day", symbol: "plus")`. The action above it — insert
the day, save, open the editor — was not touched, and is still there, still
correct. What changed was that the label stopped being a label: `ActionRow` is
a `Button`. A working one-control row became two controls competing for the
tap, `.allowsHitTesting(false)` went on to settle it, and both went dead.

**The reviewing question for a visual refactor is not "is the action still
right".** It visibly is; that is the trap. It is **"did anything passive become
interactive, or the reverse?"** A swap between a presentation type and a control
type changes the contract of everything around it, and nothing about the diff
says so.

**Chosen: make the correct shape available, then ban the wrong one.**
`ActionRowLabel` is the appearance with no button around it, for when a row has
to live inside something already interactive. `guards.d/dead-controls.sh` fails
the build on the three shapes that produced this — `.allowsHitTesting(false)` in
a view, an interactive row used as another control's label, and an empty action
closure — and its self-tests include the real broken `PlanView` from `f16e454`
plus the correct `ActionRowLabel` shape, so the guard is pinned both ways.

Rejected: banning `.allowsHitTesting(false)` alone. It is the mechanism, not the
cause, and a guard that forbids something without leaving a way to do the
legitimate thing gets an exempt label the first time somebody is in a hurry.

**And: when a control misbehaves, read its history before its code.**
`git log -S'Add a day' -- app/RathiFitness/Views/PlanView.swift` names the
commit in one line. Reading the code first gets you the right fix for a slightly
wrong reason — it looked like a control that had never worked, when it was a
control that had worked and been broken by a refactor. The second story is the
one that tells you to write this guard.

## 2026-08-27 — Press every control that writes something

`Views/` had 18 `context.insert`/`delete` sites and the UI suite reached about
four. "Add a day" was dead in every release through v0.1.1 for exactly one
reason — nothing had ever pressed it — and that reason applied equally to the
other fourteen. There was no argument that they were fine, only that nobody had
looked.

**Chosen: cover the set rather than sample it.** It is finite and enumerable,
which is the same test this repo applies to wrapping an API's fields: if you can
list what you are leaving out, you have already done the hard part of including
it. `WritePathUITests` presses each control and then asserts the row exists,
because "the sheet closed" and "the data was written" are different claims and
only the second one is what the user is relying on.

Rejected: a smoke test that enumerates `app.buttons` and taps everything. It
would have caught this bug, and it would be unreadable when it failed, would
fire destructive actions in an order nobody chose, and would go permanently
amber the first time a tap landed on a confirmation dialog. A named test per
write path costs more to write once and pays every time one breaks.

**The negative result is the interesting half: nothing else was dead.** Four of
the twelve failed on the first run and all four were the test misunderstanding
the app, not the app misbehaving:

- a `ChoiceRow` is a `SettingRow` with a `Menu` in its trailing slot, and the
  Menu's accessible label is the **current value**, not the row's label. Looking
  for "Schedule" finds the static text beside the control.
- swipe-to-delete has to land on the cell; swiping the `staticText` inside it
  does nothing.
- the dial is "Seat" — `MachineSettingKind.seat.label`. "Seat height" is
  `seatDepth`'s neighbour and does not exist.
- **a single cardio bout dismisses the screen.** `log()` ends `else if
  isFinished { dismiss() }` on purpose: intervals rest, one twenty-minute bout
  does not, and a cooldown after the only thing you came to do would strand you
  beside a treadmill for ninety seconds. So cardio's undo is reached by going
  back in, and the test says so rather than asserting the set screen's shape.

Writing those down because each one cost a full simulator run to find, and the
next person to add a UI test here will hit at least two of them.

## 2026-08-27 — A button you can see and cannot press

`testUndoingASet` failed on CI and passed locally, twice, and it took two wrong
explanations to get to the right one. Both wrong ones are worth keeping, because
each was plausible enough to stop the search.

1. **"The tap landed mid-render."** Fitted every symptom, cheap to act on, got a
   retry loop. It failed again with the retries plainly running.
2. **"The notification-permission alert is covering the app."** `RestTimer.start`
   does ask on the first set, that alert is owned by Springboard, and it would
   swallow exactly these taps. It is a real hazard and the guard against it is
   worth keeping — but it was not this. It failed again with the ask suppressed.

The actual cause: **`PrimaryButton` and `SecondaryButton` had no
`contentShape`.** `PrimaryButton(filled: false)` fills its background with
`Color.clear`, and under `.buttonStyle(.plain)` a button's hit area is the
opaque part of its label. So the tappable region was the text glyphs and a
one-point stroke — a 54-point bar you can see and mostly cannot press.

It affects "Skip to set N", "+30s", "Undo" and the resting "Done", which is to
say every control you reach for mid-set with a bar in your other hand.
`log-set` was never affected because `filled: true` paints an opaque background,
which is its own hit area. Every other tappable thing in this app already sets
one — `ActionRowLabel`, `SettingRow`, `stepButton` — these two never did.

Reproduced on iPhone 16 / iOS 18 and not on iPhone 17 Pro / iOS 26. Since CI
tests iOS 18 and the laptop had been testing iOS 26, it looked like flake.

**Chosen: `.contentShape(RoundedRectangle(...))` on both.** The same shape the
button draws, so the thing you can press is the thing you can see.

**What to take from it.**

- **A test that fails only on CI is telling you about state or a version your
  machine does not have.** The fastest route was not more theorising, it was
  `xcodebuild -destination` pointed at the device CI actually uses. That
  reproduced it in one run after two CI cycles of guessing.
- **Do not let a plausible explanation close an investigation.** Twice here a
  good story arrived before the evidence did. What settled it was dumping every
  button on screen at the moment of failure and seeing "Skip to set 2" still
  there — the cooldown had never stopped, so the action had never run.
- **An invisible background is an invisible hit area.** If a control is drawn
  with `Color.clear` or only a stroke, it needs a `contentShape` or it is
  decoration.

**A related trap, found the same afternoon.** After editing a UI test while a
previous `xcodebuild` was still running, the next `test` invocation used a stale
test bundle — the trace showed a helper that is plainly in the source simply not
executing. If a test fails in a way that contradicts the code in front of you,
build into a clean `-derivedDataPath` before believing it.

## 2026-08-27 — Test on the OS your users have, not the one you have

Two bugs in this milestone reproduced on iPhone 16 / iOS 18 and not on
iPhone 17 Pro / iOS 26. Both had been shipped. Both were invisible to a laptop
running the newest runtime, which is what "it passes locally" had meant all
week.

1. **The hit-area bug** — `PrimaryButton`, `SecondaryButton` and the set chips
   painted `Color.clear` with no `contentShape`, so they were tappable only on
   their glyphs. iOS 26 is more forgiving about this than iOS 18.
2. **The dial that did not appear** — `MachineSettingsEditor` read
   `exercise.settings`, and on iOS 18 a relationship read does not republish when
   the inverse side is inserted, so a dial you added stayed invisible until you
   left the screen. `SetView` and `CardioSetView` have always used `@Query` and
   filtered; this was the one screen still traversing.

The deployment target is iOS 17, CI tests iOS 18, and the phone in the room runs
whatever it runs. **The newest simulator is the least representative one
available.** When a test disagrees between CI and the laptop, point
`-destination` at the device CI uses before theorising — it reproduced both of
these in one run each, after several cycles of plausible wrong answers.

The second one also says something narrower and worth keeping: **if two screens
read the same data two different ways, the odd one out is where to look.** The
query-and-filter pattern in `SetView` was not a style choice; it was this bug,
already solved once, in a place nobody thought to copy.

## 2026-08-27 — `make guards` is weaker than CI, in one specific way

The `dead-controls` guard passed locally and died on CI with
`invisible: unbound variable`. Both run the same script with the same
`set -euo pipefail`. The difference is the interpreter: CI is ubuntu with bash 5,
macOS ships **bash 3.2**, and 3.2 does not enforce `set -u` on a variable
declared with a bare `local` and never assigned. Bash 4.4 changed that.

So `local invisible` then `[ -n "$invisible" ]` is silently fine here and fatal
there. **Initialise locals you accumulate into** — `local invisible=""` — and
know that `make guards` going green is a weaker claim than CI going green. There
is no modern bash on this machine to test against, so this is a note rather than
a tool; it is written down in the `Makefile` target too, which is where someone
will be standing when it bites.
