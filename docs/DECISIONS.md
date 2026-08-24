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
