#!/bin/bash
# Apply hook — build the iOS app and install it on a paired device.
#
# Contract (see autoupdate.sh):
#   0   installed
#   10  not now — try again later, silently
#   1   failed
#
# Two identifiers, and they are NOT interchangeable. `-destination` wants the
# ECID; `devicectl --device` wants the CoreDevice UUID. Passing one where the
# other belongs gives "Unable to find a device matching the provided
# destination specifier", which reads like the phone is unplugged when it is
# sitting there paired.
set -uo pipefail

log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "${AU_LOG:-/dev/null}"; }

REPO="${AU_REPO:?}"
APP_DIR="${AU_IOS_APP_DIR:-$REPO/app}"
PROJECT="${AU_IOS_PROJECT:?AU_IOS_PROJECT (e.g. RathiFitness.xcodeproj)}"
SCHEME="${AU_IOS_SCHEME:?AU_IOS_SCHEME}"
ECID="${AU_IOS_ECID:?AU_IOS_ECID — xcodebuild -showdestinations}"
DEVICE="${AU_IOS_DEVICE:?AU_IOS_DEVICE — xcrun devicectl list devices}"
# The PROCESS path, not the bundle id. `devicectl device info processes` lists
# executables — ".../Foo.app/Foo" — and never prints a bundle id, so a grep for
# one matches nothing and the "don't interrupt" guard below silently never
# fires. That bug shipped once and was caught only by running the command while
# the app happened to be open.
APP_PROCESS="${AU_IOS_APP_PROCESS:?AU_IOS_APP_PROCESS — e.g. /RathiFitness.app/}"
DERIVED="${AU_IOS_DERIVED:-/tmp/autoupdate-$SCHEME}"
# `xcode-select -p` is often CommandLineTools, which cannot build an iOS app at
# all and fails with "tool 'xcodebuild' requires Xcode" — which reads as Xcode
# being missing when it is installed and merely unselected.
export DEVELOPER_DIR="${AU_IOS_DEVELOPER_DIR:-$(xcode-select -p)}"
XCRUN="${AU_XCRUN:-xcrun}"
XCODEBUILD="${AU_XCODEBUILD:-xcodebuild}"

# ------------------------------------------------- is the device even here?
"$XCRUN" devicectl device info details --device "$DEVICE" >/dev/null 2>&1 || exit 10

# ------------------------------------------------- never interrupt a session
# Installing over a running app terminates it. For a workout logger that means
# losing a set to a background job, which is a far worse bug than being one
# commit behind. So: open app means wait, for ever if necessary.
if "$XCRUN" devicectl device info processes --device "$DEVICE" 2>/dev/null \
        | grep -qF "$APP_PROCESS"; then
    log "skipped: the app is open on the device — not interrupting it"
    exit 10
fi

# ------------------------------------------------------------------ build
cd "$APP_DIR" || exit 1
# Regenerate first when the project is generated rather than committed; a file
# that is not in the project compiles nowhere.
if [ -f project.yml ] && command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null 2>&1 || { log "xcodegen failed"; exit 1; }
fi

if ! "$XCODEBUILD" -project "$PROJECT" -scheme "$SCHEME" \
        -destination "id=$ECID" -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates build >/tmp/autoupdate-build.log 2>&1; then
    log "BUILD FAILED — device left with the build it had"
    tail -5 /tmp/autoupdate-build.log >> "${AU_LOG:-/dev/null}"
    exit 1
fi

app="$DERIVED/Build/Products/Debug-iphoneos/$SCHEME.app"
[ -d "$app" ] || { log "built, but no .app at $app"; exit 1; }

"$XCRUN" devicectl device install app --device "$DEVICE" "$app" >>"${AU_LOG:-/dev/null}" 2>&1 \
    || { log "install failed — will retry"; exit 1; }
