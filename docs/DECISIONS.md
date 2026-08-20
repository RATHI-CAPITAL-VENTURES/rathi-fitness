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
