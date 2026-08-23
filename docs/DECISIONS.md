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
