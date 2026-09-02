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

## 2026-08-29 — A day was the session, in twenty-eight places

"What if I wanted to do two sessions in the same day?" had no answer, because
the app had no sessions. A workout was *inferred* by grouping `SetEntry.date` on
`startOfDay`, and that inference lived in 28 expressions across 9 files. Nothing
declared the invariant; it was simply true everywhere, which is the shape of an
assumption that cannot be reviewed. You find it by asking a question it cannot
answer.

Four user-visible bugs, one root cause: two-a-days reached Apple Health as a
single twelve-hour workout, the rotation advanced once so the next day offered
the workout you had just done, the evening lift continued the morning's set
numbering, and the second workout opened with the first one's checklist ticked.

**Chosen: a real `Session`, opened by which workout you picked.** A session
opens on the first set logged against a given planned day, and opening one
closes any other.

**Rejected: a time gap** ("more than three hours apart is a new workout"). It is
cheap, needs no migration, and works on existing history — and it is wrong in
both directions on exactly the days it would be used. A long workout with a
break in it splits in two; a lift running straight into cardio merges into one.
A rule that reads the user's actual choice of workout cannot be wrong about it.

**Rejected: a counter on `SetEntry`** — a `bout: Int` incremented by a button.
Cheaper again, and it is the thing this repo has already learned not to do: a
workaround for a missing entity becomes the permanent shape of the data, because
nobody re-migrates it later.

**What it deliberately does not separate:** the same workout twice in one day.
Sessions are keyed by the planned day, so a second run at Push A joins the first.
The way out is the **Finish** action on Today, which is a truthful thing for a
person to say rather than a setting invented for an edge case. Keying on time
instead would bring the heuristic back through the side door.

**The migration that would have doubled a year of training.** Health export
records what has already been sent, and everything sent before today was marked
by the *start of a day*. Keying the new check on the session start alone would
have made every historical workout look unsent and written a duplicate of each
one into Apple Health. A day already marked now covers the sessions inside it,
and there is a test named after the failure.

**A set with no session still happened.** The snapshot builder iterated sessions
and silently dropped anything unattached — which is not hypothetical, because
CloudKit delivers rows from devices still on an older build. Orphans are grouped
by day and included, with no `day` name rather than a guessed one. Three
existing tests caught this, because seeding sets directly is exactly the shape
the old build writes.

## 2026-08-30 — `blocked:` is not a size argument

v0.3.0's retro closed three gaps as `blocked:` — Trends grouping by day, the
past-days pager, and `Snapshot.today`'s weekday resolver — with reasons that all
came down to *this change is already big enough*. The `followups` gate accepted
them, because the format was right. The work was done two days later anyway.

`CLAUDE.md` is explicit that this is the case `blocked:` does not cover: it is
for a gap that genuinely cannot be closed here — an Apple entitlement, a System
Settings toggle, a signal that does not exist yet. "I could do this, and I'd
rather do it later" is the thing the two-status contract exists to stop, and a
well-formatted reason is exactly how it gets past a gate that can only read the
format.

**The estimates were wrong in the direction that makes it worse.** Trends needed
one shared function — `workoutKey` — not the `Tally` rewrite the row predicted.
`PastDayView` got *shorter*, because taking a session deleted the code that
guessed a workout's name by scoring its exercises against every planned day.
Only the snapshot resolver was as involved as claimed.

**And deferring it hid a bug.** The rotation-aware `Snapshot.today` indexed into
an **unsorted** `PlannedDay` fetch while `TodayView` reads its days through
`@Query(sort: \PlannedDay.order)`. So the first version of the fix still
answered differently from the phone — a second disagreement hiding underneath
the first, found by a test written the same afternoon. Another two weeks and it
would have been found by `gym today` naming the wrong workout.

**The rule, restated for the next time:** if the only thing stopping you is that
the diff is getting long, the honest move is a second PR this week, not a
`blocked:` row. Write `blocked:` when you can name the thing outside your control
that stops you.

## 2026-08-30 — `.duckOthers` does not duck you

"When I'm playing music I can't hear the cooldown ping." Three defects, none
visible alone, all of which only line up while music is playing.

**`AudioHub` promised something its mechanism could not deliver.** Its own doc
comment says the ping "has to be audible over music", and it set `.duckOthers`
to get there. But `MusicController` plays through `ApplicationMusicPlayer`,
which renders in **this app's** audio session — and `.duckOthers` attenuates
*other* apps. Spotify ducked; our own track did not. The cue was a 45 ms sine at
gain 0.30 against a full-level song.

**Chosen: the cue carries itself.** Rendered cues are normalised to a known
peak, and there is a second, louder render used while our own music plays. Two
renders rather than one gain knob, because it is not a volume: a cue sitting at
the ceiling in a silent room with AirPods in is a shock.

Rejected: **`SystemMusicPlayer`**, which would put the music in the Music app's
session where `.duckOthers` really would duck it. It also hands the now-playing
role to the Music app, and that role is the only way an AirPods squeeze reaches
us — the trade the whole class exists to make. Rejected: **pausing the music
around the ping**, which chops the track for a 45 ms tone and costs MusicKit's
play/pause latency at both ends.

**The backup channel was not there either.** No `UNUserNotificationCenterDelegate`
existed, so iOS suppressed the local notification whenever the app was
frontmost — which is where you are during a rest, watching the ring. And the
gate deciding whether that notification carried a sound asked
`isHoldingRemoteControl`, a different question whose answer is `false` exactly
when music is playing, since `arm()` only holds silence when nothing real is. So
the gate said "let the notification sound" while the delegate's absence meant it
never did. **Two channels, both failing, for unrelated reasons, in the same
conditions.** That is why the bug reads as one thing and is three.

**And a stored flag that outlived its fact.** `engineRunning` was set at
`engine.start()` and cleared only in `deactivate()`. `AVAudioEngine` stops itself
on a configuration change — a route change when AirPods connect — so the flag
went on claiming `true` while every cue was scheduled into a dead engine. The
lesson is small and general: **do not cache a fact the system owns.**
`engine.isRunning` is now read directly, and the configuration-change and
interruption notifications are observed.

**What I could not verify.** The simulator has no Apple Music, so none of this
was confirmed by ear. What is tested is what can be: every cue renders
non-silent and below the ceiling, the over-music render is meaningfully louder,
and the notification carries its own sound when nothing will chime. The
audibility itself needs a phone, a track and a person.

## 2026-08-31 — The UI tests do not get an audio engine

**Chosen: a `-RFSilent` launch argument that stops `AudioHub` touching
`AVAudioEngine` at all. Rejected: trying to make the engine survive.**

Every UI-test run aborted the app with `Abort trap: 6`. The stack is entirely
outside this repo: `startEngineIfNeeded` reads `engine.mainMixerNode`,
`AVAudioEngineImpl::UpdateOutputNode` uninitialises the remote IO unit, and
`AURemoteIO::Cleanup` RPCs an audio server that the simulator does not always
have — then calls `abort()` when the call times out.

That last step is what closes off every other option. It is a SIGABRT raised in
AudioToolbox's frame, not a Swift error: `try? engine.start()` is already there
and cannot help, because the crash happens on the *property access* before any
start. There is nothing to catch, nothing to retry, and no state of ours that
was wrong.

So the fix is the only lever available: **do not touch the engine in an
environment that cannot service it.** `-RFSilent` joins `-RFDay` and
`-RFDemoHistory` as a launch argument the tests pass, and the gate sits in front
of `activate()` and `startEngineIfNeeded()`.

**What this deliberately does not claim.** It makes the UI tests deterministic.
It does not prove a device can never see the same timeout. The honest position
is written at the declaration rather than left for someone to infer from the
flag's existence — and if a device ever does abort here, this note is the
pointer that the cause was known and only the test environment was addressed.

**Why the coverage does not really move.** The cues were already testable
without an engine: `render(_:)` is internal precisely so a test can measure a
tone rather than assert that `play` did not throw (v0.3.2). Those tests never
started an engine and still do not. What the UI tests were exercising was the
write path — logging a set, starting a second workout — and none of it is about
sound.

**Found by accident, and that is its own finding.** CI has not run this suite
since v0.3.0: the `scope` job fails at startup with *"the job was not started
because recent account payments have failed or your spending limit needs to be
increased"*, and every downstream job is skipped rather than failed. A red run
whose jobs are all `skipped` reads at a glance like a run that passed. The
crash had been landing on every push for two releases with nothing to report it.

## 2026-08-31 — Showing up, without a streak

**Chosen: a consistency band. Rejected: a streak, again — but for a better
reason than last time.**

The ask was explicitly for weekly streaks. `docs/RESEARCH.md` had already ruled
streaks out ("cheap motivation that turns a deload week into a failure state"),
and the honest thing was to test that ruling rather than quote it. It survives,
and the research sharpened it: a counter that resets is reported to make people
abandon a habit *harder* after one miss than no tracking at all — the number
does not degrade, it detonates. Apple shipped a pause button for Activity
streaks in watchOS 11 after years of exactly this; Gentler Streak built a
product on rest counting as keeping the streak.

**What makes a band possible here and a streak unnecessary:** this app knows the
schedule. `Rotation.Config` says which days you meant to train, so the
denominator is what you *planned*, never the calendar. A rest day is not an
absence of training, it is the training. That single fact is why the objection
was about *day* streaks specifically and does not rule out measuring
consistency at all.

Rejected along the way, and worth recording so they are not re-proposed:

- **A weekly streak with a declarable week off** (the watchOS 11 shape). It
  works, and it needs a `TrainingBreak` model, a snapshot field and a CLI read
  to answer a question the band answers with no stored state at all. Kept in
  reserve; if the band turns out to motivate nothing, this is the next thing to
  try, not a day streak.
- **A PR or progression streak** — consecutive sessions where something got
  beaten. It is the one mechanic that would make training *worse*: linear
  progression ends for everybody, and a counter that treats the end of it as
  failure is the app arguing with physiology.

**Three decisions inside the band that could each have gone the other way:**

1. **Sessions, not days.** Two workouts on a Saturday count twice. `Rotation`
   was moved to counting sessions in v0.3.1 on purpose, and a second unit for
   "how much did I train this week" would mean the app holds two answers to one
   question. Consistency with the existing model beat the argument that a
   two-a-day is one attendance.
2. **The current week is drawn but not scored.** A percentage computed from a
   Tuesday is not a fact about anything, and "0 of 3" on a Monday morning is the
   app telling you off for a week that has barely started.
3. **Credit is capped per week.** Six sessions one week and none the next is not
   the same as three and three, and a percentage that says it is has stopped
   measuring consistency and started measuring volume — which the tonnage
   figure already does, better.

**On Today rather than Trends.** It was proposed for Trends and moved on
request, and the request is right: the day you most need to see whether you are
actually doing this is the day you are deciding whether to go. It shows on rest
days too, for the same reason. Hidden entirely until there is a first workout to
count from — a fresh install opening on twelve empty marks is twelve failures
nobody earned, on the first screen they see.

## 2026-09-01 — Resetting every rest at once

**Chosen: one confirmed, counted apply driven by the default you already set.
Rejected: a second rest picker, and a blanket write that includes cardio.**

"New exercises open on" has refused to touch an existing plan since it shipped,
and the footer said so: *nothing already in the plan changes*. That refusal is
right — a default that silently rewrites your programme is a default you stop
trusting — but it left no way to do the thing **on purpose** either. Changing
your mind about rest meant opening every slot on every day and turning the same
dial, which is the app charging rent in exactly the way that section exists to
stop.

So the fix is an explicit act, not a looser default. The row sits directly under
the Rest dial and applies *that* number, because a picker of its own would be a
second place to declare one thing and the row would stop being obviously about
the row above it.

**Cardio is excluded, and this is the part that makes a blanket write safe.**
`PlanItem.restSeconds` on a cardio slot is not a rest between sets — it is the
gap *between intervals*, a different quantity that happens to share a field.
The plan editor creates every treadmill slot with `0`, so an apply that included
them would not reset anything: it would invent intervals nobody asked for, on
rows whose rest column currently reads "—". And a cardio slot that *does* carry
an interval rest was set by hand, which is precisely the setting a bulk action
must not eat. The exclusion lives in `slotsTakingPlanRest` with that reason
written next to it, rather than being a filter someone later "tidies up".

Three things the dialog does rather than asks you to trust:

1. **It names the count** — "Set 8 exercises", from the same query that does the
   write, so the number cannot drift from the act.
2. **It reports what changed, not what it looked at.** A slot already at the
   value is not a write, so applying twice says *"Every exercise was already at
   1:30"* the second time instead of claiming eight more.
3. **It says cardio is left alone** in the message, because a user who has a
   treadmill in the plan would otherwise have to diff their own programme to
   find out.

Not undoable, and the message says so. A rest is one integer per slot and the
plan is small; an undo stack for one field is more machinery than the thing it
protects, and the confirmation is where the protection belongs.

## 2026-09-01 — History means the past

**Chosen: `Seed.mostRecent` shifts back at `delta >= 0`. Rejected: teaching the
two failing tests to tolerate a seeded today.**

`delta = weekday - today`, shifted back only `if delta > 0`. At `delta == 0` —
the seeded weekday is today — a workout from "six weeks of history" was dated
06:45 this morning. Not history. A session nobody had done, in the same day as
whatever you log next.

The tests could have been taught to subtract it. That is the wrong repair: they
were not wrong, and the thing they tripped over is a real defect in what the
demo data claims to be. A fresh demo install opened with today's workout
already part-done, and nothing about `weeksOfHistory: 6` suggests that.

**Why it hid for eleven releases.** It collides only on the three weekdays the
plan trains, so the suite passed four days a week. Worse, *which* four depends
on the timezone: a Mac on EDT and a runner on UTC disagree about the weekday
for four hours every night, so the same commit could be green locally and red
on CI with nothing between them but the clock. And `Seed.run` has always taken
a `now` that no caller ever passed — a seam built for exactly this and never
used, so the function was covered without any of its dates being chosen.

**The near-miss is worth keeping.** The first regression test built its
Wednesday in UTC, to match the 02:31 UTC stamp on the CI failure, and **passed
against the unfixed code**: 02:00 UTC Wednesday is 22:00 EDT Tuesday, so
`Calendar.current` saw a Tuesday, the seed put nothing on "today", and the test
proved nothing while looking exactly like proof. It was caught only by
reverting the fix and checking the test went red. Dates in these tests are
built in `Calendar.current` now, because that is what `Seed` reads.

**Every new test here reverts-red.** A regression test that has not been
watched to fail is a regression test you are guessing about.

## 2026-09-02 — Splitting a test class for time, not tidiness

**Chosen: five classes and two invocations. Rejected: turning on parallelism
and stopping there, which measured SLOWER.**

The ask was "parallelise the tests". The measurement said something else:

| | |
| --- | --- |
| whole unit bundle | **2.5 seconds** of testing |
| `WritePathUITests` | **311s of the suite's 428**, in one class |
| everything, serial | 7:54 |
| everything, `-parallel-testing-enabled YES`, 4 workers | **>10:00** |

XCTest parallelises by **class** and offers nothing finer — Xcode 27 has no
`-parallel-testing-granularity`. So one class holding 73% of the work sets the
floor, and the four simulator clones booted to beat it just cost two minutes.
Six workers was worse again (6:55) on a ten-core machine.

Splitting `WritePathUITests` along the `// MARK:` sections it already had is
therefore not housekeeping; it is the only lever XCTest exposes. Five classes,
one shared `WritePathCase`, no test body rewritten.

**The second finding was not about speed at all.** With four UI clones running,
`HandsFreeTests` crashed — the CoreAudio `abort()` of v0.3.3, reached through
`AudioHub.say` and through `engineRunning` asking `engine.isRunning`, neither of
which that release had gated. Marking the unit target `parallelizable: false`
did **not** fix it, which is the useful part: the audio server is contended
machine-wide, not per-bundle. Only running the two bundles one after the other
does. That is why `make test` is two invocations.

**And the bundle had never been run alone.** `-only-testing:RathiFitnessTests`
crashed those same two tests on `main`, before any of this — invisible for
eleven releases because every run was the whole suite, where the ordering
happened to spare them. A fast lane is worth having for its own sake; it also
found a crash that a slow lane was hiding.

**CI now runs `make`.** It had its own copy of the xcodebuild line, so the
Makefile could grow a split that CI never received. The destination and the
toolchain are the only things a runner should need to override.

**Postscript, same day.** The first version of this went to CI with
`WORKERS=3` and made it **slower**: the UI step alone took 19:26, against a
whole job of about 16:00 before. A macos runner has roughly three cores and each
worker is a whole simulator, so the clones fought over them. The local win was
real and so was the remote loss, which is the actual lesson — parallelism here
is a property of the machine, not of the suite, so it is a `PARALLEL` variable
with both measurements written next to it rather than a setting anyone has to
remember. Green on CI is not the same as good on CI, and only the step timings
said so.
