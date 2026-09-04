#!/bin/bash
# Rathi Fitness auto-install — poll origin/main, and when it moves, build the
# app and push it to the phone over Wi-Fi. The `app/` half of what
# ria-autodeploy does for the server.
#
# The gap this closes: RIA's auto-deploy ships the SERVER only. An `app/` change
# is merged, green in CI, and still not on the device — the phone keeps running
# whatever build was last installed by hand, indefinitely. Every release in this
# repo so far has ended with a human running two xcodebuild commands.
#
# Run every ~10 min by com.rathi.fitness.autoinstall (deploy/).
#
# Safety, in order:
#   1. Acts ONLY on a clean `main`. A feature branch or any tracked local change
#      makes it skip, so it never builds over work in progress.
#   2. Fast-forward ONLY. A force-push / history rewrite makes it refuse and log
#      rather than reset someone's checkout.
#   3. NEVER interrupts a workout. If the app is running on the phone, it skips
#      and tries again later — installing over a running app terminates it, and
#      losing a set mid-workout to a background job is a far worse bug than
#      being one commit behind.
#   4. Builds BEFORE it touches the phone. A build failure leaves the device
#      alone with the working copy it already had.
#   5. Skips quietly when the phone is not reachable. It is a phone; being off
#      the network is its normal state, not an error worth shouting about.
#
# Nothing here is destructive. The worst case is a wasted build.

set -uo pipefail

REPO="${RF_REPO:-/Users/ishan/RIA/projects/rathi-fitness}"
LOG="${RF_LOG:-/Users/ishan/Library/Logs/rathi-fitness/autoinstall.log}"
STATE="${RF_STATE:-$REPO/.rf-installed-commit}"
DERIVED="${RF_DERIVED:-/tmp/rf-autoinstall-build}"
# The ECID for -destination and the CoreDevice UUID for --device are DIFFERENT
# identifiers and are not interchangeable; passing one where the other belongs
# gives "Unable to find a device matching the provided destination specifier",
# which reads like the phone is unplugged when it is sitting there paired.
ECID="${RF_ECID:-00008120-000C70441AE2201E}"
DEVICE="${RF_DEVICE:-861545F5-1AB5-53A8-91C7-E956FDF93FD4}"
# The PROCESS path, not the bundle id. `devicectl device info processes` lists
# executables — ".../RathiFitness.app/RathiFitness" — and never prints
# `com.rathi.fitness`, so a grep for the bundle id matches nothing and the
# "don't interrupt a workout" guard below silently never fires. Caught only by
# running the command while the app happened to be open.
APP_PROCESS="${RF_APP_PROCESS:-/RathiFitness.app/}"
# `xcode-select -p` here is CommandLineTools, which cannot build an iOS app at
# all. Same override the Makefile needs, for the same reason.
export DEVELOPER_DIR="${RF_DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
XCRUN="${RF_XCRUN:-xcrun}"
XCODEBUILD="${RF_XCODEBUILD:-xcodebuild}"
# Hardcoded because launchd gives a job almost no PATH — and overridable
# because a hardcoded one cannot be stubbed, so the self-test could not reach
# any branch past `xcodegen`. RIA's deploy script hit this and solved it one
# variable at a time; one variable for the whole PATH is the same fix, smaller.
PATH="${RF_PATH:-/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin}"

mkdir -p "$(dirname "$LOG")"
say() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

cd "$REPO" 2>/dev/null || { say "no repo at $REPO"; exit 1; }

# ---------------------------------------------------------------- 1. clean main
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ "$branch" != "main" ]; then exit 0; fi
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then exit 0; fi

git fetch --quiet origin main 2>/dev/null || { say "fetch failed"; exit 0; }
local_sha=$(git rev-parse HEAD)
remote_sha=$(git rev-parse origin/main)
installed=$(cat "$STATE" 2>/dev/null || echo "")

# Nothing new, and the phone already has what is checked out.
if [ "$local_sha" = "$remote_sha" ] && [ "$installed" = "$local_sha" ]; then exit 0; fi

# --------------------------------------------------------- 2. fast-forward only
if [ "$local_sha" != "$remote_sha" ]; then
    if ! git merge-base --is-ancestor "$local_sha" "$remote_sha"; then
        say "REFUSING: origin/main has diverged from local — a human should look"
        exit 0
    fi
    git pull --ff-only --quiet origin main || { say "pull failed"; exit 0; }
    local_sha=$(git rev-parse HEAD)
    say "pulled $(git log -1 --format='%h %s')"
fi

[ "$installed" = "$local_sha" ] && exit 0

# ------------------------------------------------------ 3. never mid-workout
reachable=$("$XCRUN" devicectl device info details --device "$DEVICE" 2>/dev/null | head -1)
if [ -z "$reachable" ]; then
    # Normal. A phone is not always on the network.
    exit 0
fi

if "$XCRUN" devicectl device info processes --device "$DEVICE" 2>/dev/null \
        | grep -qF "$APP_PROCESS"; then
    say "skipped: the app is open on the phone — not interrupting a workout"
    exit 0
fi

# ------------------------------------------------------------------ 4. build
cd "$REPO/app" || exit 1
if ! command -v xcodegen >/dev/null 2>&1; then
    say "xcodegen missing — cannot regenerate the project"
    exit 0
fi
xcodegen generate >/dev/null 2>&1 || { say "xcodegen failed"; exit 0; }

if ! "$XCODEBUILD" -project RathiFitness.xcodeproj -scheme RathiFitness \
        -destination "id=$ECID" -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates build >/tmp/rf-autoinstall-build.log 2>&1; then
    say "BUILD FAILED for $(git -C "$REPO" log -1 --format='%h %s') — phone left alone"
    tail -5 /tmp/rf-autoinstall-build.log >> "$LOG"
    exit 0
fi

# ---------------------------------------------------------------- 5. install
app="$DERIVED/Build/Products/Debug-iphoneos/RathiFitness.app"
if [ ! -d "$app" ]; then say "built, but no .app at $app"; exit 0; fi

if "$XCRUN" devicectl device install app --device "$DEVICE" "$app" >>"$LOG" 2>&1; then
    echo "$local_sha" > "$STATE"
    say "INSTALLED $(git -C "$REPO" log -1 --format='%h %s')"
else
    say "install failed — will retry"
fi
