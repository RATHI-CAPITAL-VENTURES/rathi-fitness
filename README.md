# Rathi Fitness

A personal gym app. iPhone-first, RIAKit's design language, readable by RIA.

Status: **design only.** Four screens exist as a mockup; no Swift has been
written yet. See `design/ios-first-pass.html`.

## What it does

| Ask | Where it lives |
| --- | --- |
| Log an exercise + current body weight, see trends over time | Trends tab — body weight chart, working weight table |
| Store QR codes | Pass tab — check-in code at full brightness, plus guest/punch passes. Scan with the camera **or pull the code out of a screenshot you already have**. QR, Code 128, PDF417 and Aztec. |
| A checklist for each day showing what to do | Today tab — the day's plan, one live row at a time |
| Set / cooldown counter per exercise | The set screen, pushed from a Today row |
| Edit the programme | Settings → Edit the plan, or the calendar button on Today. Create/rename/reschedule/delete days, add-remove-reorder exercises, edit targets and rest, create new exercises. |
| Apple Health | Weigh-ins come **from** Health (your scale writes there); finished sessions go back as workouts. Needs the entitlement — see below. |

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

## Installing on the phone

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
at the permission sheet. One signed build turns on Health and sync together.

## The app icon

`python3 design/make_icon.py` renders it — the cooldown ring, ember to teal, on
the RIAKit ground. The colours come from the same ramp the app draws with rather
than from an eyedropper, so retuning the mechanic and re-running keeps the icon
honest. It deliberately does *not* sample the full hue ramp: the app shows one
value at a time, an icon shows all of them at once, and the yellow-green stretch
between orange and teal would become a third colour the product does not have.

## Not decided yet

- Whether the Blink check-in code is static (storable) or rotating (not).
  Needs the real card, not a guess.
- Whether the cooldown hue ramp survives contact with an actual workout.
- Watch app. The set/cooldown screen is the obvious candidate and is designed
  so its state reads as colour, which survives a 45mm face.
