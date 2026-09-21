# Lens spike

A throwaway app that answers seven questions about putting the set screen on
Meta Ray-Ban Display glasses. **Not part of Rathi Fitness, and not meant to be
merged** — it lives on `chore/lens-spike` and its only output is a log file.

It is a separate app (`com.rathi.fitness.lensspike`) because linking Meta's
closed-source framework and new background modes into the app you train with,
before knowing any of it works, is the wrong order.

Pinned to Meta's DAT SDK **0.9.0**, in Developer Mode (`MetaAppID = 0`), with
Meta's crash reporting opted out.

## Build and install

```
cd spike/lens
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodegen generate

# Build does not need the phone. `generic/platform=iOS` works while it is
# locked; `id=<ECID>` times out with "needs to be unlocked".
xcodebuild -project LensSpike.xcodeproj -scheme LensSpike \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/lens-spike-build \
  -allowProvisioningUpdates build

# Install DOES need it unlocked — "The device is currently locked" otherwise.
xcrun devicectl device install app --device 861545F5-1AB5-53A8-91C7-E956FDF93FD4 \
  /tmp/lens-spike-build/Build/Products/Debug-iphoneos/LensSpike.app
```

## Before the first run

In the **Meta AI** app, both of these — they are different switches:

1. Settings → App Info → tap the version five times → **Developer Mode** on.
2. Settings → *your glasses* → **Developer Mode** on. Meta staff say this is the
   one that "installs the developer DAT app on your glasses". If it is off, the
   likely symptom is `datAppOnTheGlassesUpdateRequired` (their issue #180).

Then in Lens Spike: **Register with Meta AI**, approve it there, come back, and
**Connect**.

## The seven questions

| # | Question | How | What decides it |
| - | -------- | --- | --------------- |
| 1 | Does a session start at all on these glasses? | Button 1 | "Bench Press" appears in the lens. If instead the log says `datAppOnTheGlassesUpdateRequired` and the orange update button does not cure it, **stop — the project waits on Meta.** |
| 2 | Does it survive the phone locked in a pocket? | Pocket test, 10 min. **Run it twice: silent-audio switch off, then on.** Lock the phone, pocket it, pinch now and then. | `RESULT` lines at the end. `no late ticks` and a healthy `locked:` row is a pass. `GAP` lines mean iOS suspended the app. |
| 3 | What does one send cost? | Button 3, phone in hand | Median for `text` vs `image`. Under ~150 ms allows a true per-second clock. |
| 4 | Does the lens sleep through a 90 s rest? | Button 4, then **watch the lens** | What you tap under *What you saw*: did it go dark, and did "Rest over" bring it back? |
| 5 | What does a notification do? | During a pocket test, text yourself | `session` / `display` state lines and `send FAILED` around that time, plus what you saw. |
| 6 | Does a list taller than the lens scroll? | Button 6 | Can you reach row 8 with a thumb swipe? Pinch it — the log names the row. |
| 7 | Which button is lit first, and what does "back" do? | Button 7, then middle finger to thumb | Note which was lit. After the back tap: are you still in the app? Watch for `display stopped` in the log. |

The phone cannot see the lens. For 4, 5, 6 and 7 the evidence is **you**: tap the
matching chip under *What you saw* and it is stamped into the log with the time.

## Reading the log

```
14:02:31.482 | bg | LOCKED   | audio on  | send ok | tick 40 · 38 ms
             app   phone       switch      event     detail
```

`fg` front, `bg` background, `in` transitioning. The phone reads `LOCKED` about
ten seconds after the screen goes off, not instantly.

Get the file with **Send the log** in the app, from Files → On My iPhone → Lens
Spike, or from the Mac:

```
xcrun devicectl device copy from --device 861545F5-1AB5-53A8-91C7-E956FDF93FD4 \
  --domain-type appDataContainer --domain-identifier com.rathi.fitness.lensspike \
  --source Documents/lens-spike.log --destination ./lens-spike.log
```

## What is where

| File | |
| ---- | - |
| `Glasses.swift` | Registration, session, lens. Follows Meta's DisplayAccess sample step for step, so a failure is theirs and not ours. |
| `LensScreens.swift` | The screens, in Meta's UI vocabulary, plus the hand-drawn clock image. |
| `Experiments.swift` | One method per question. |
| `SpikeLog.swift` | The deliverable. |
| `SilentAudio.swift` | The switch that makes question 2 a comparison. |

`Glasses.swift`, `LensScreens.swift` and `Experiments.swift` deliberately do not
import SwiftUI: Meta's module exports `Text`, `Button` and `Image` too.
