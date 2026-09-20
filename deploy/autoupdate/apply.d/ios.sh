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
#
# What xcodebuild has actually been seen to say, and where the evidence is —
# because a stub can only ever agree with whatever this file believes (README,
# third bug), so every string matched below is labelled by how it is known:
#
#   ON DISK   "Timed out waiting for all destinations matching the provided
#             destination specifier to become available" — a LOCKED phone,
#             2026-09-20 11:43, Xcode 26 beta. In this project's job log.
#   SEEN, ARTIFACT LOST   "Unable to find a destination matching the provided
#             destination specifier" — an AWAY phone, same morning 11:21, read
#             out of the build log in a terminal. That file was overwritten by
#             the next run, and the job log kept only `tail -5`, which cut the
#             header off. Nothing on this Mac can now show it.
#   RECORDED EARLIER   "Unable to find a device matching…" — CLAUDE.md's
#             wording for the ECID/UUID swap, from an older Xcode.
#
# That the middle one cannot be pointed at is why failures now log their first
# `error:` line and quiet exits keep a copy of the build log (below).
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
# The EXIT CODE does not answer this, which is what this line used to trust.
# `devicectl device info details` exits 0 for a paired phone that is miles away:
# it prints what it remembers, with `Device State: unavailable` in the middle.
# So an absent device sailed through, xcodebuild had nothing to build FOR and
# died in eight seconds with "Unable to find a destination", and the log said
# BUILD FAILED / APPLY FAILED — every ten minutes, for as long as he was out —
# about code that was fine. Exit 10 is "not now", and deliberately silent.
#
# Matched on the state observed, not on an allow-list of good ones: a state
# nobody has seen yet falls through to a build attempt, which fails loudly,
# rather than into a silent "not now" that would stall installs for ever.
details=$("$XCRUN" devicectl device info details --device "$DEVICE" 2>/dev/null)
rc=$?
# Not "the device is away" but "the TOOL is away", and swallowing that as "not
# now" would stall installs for ever without a word. Measured on this Mac:
#   72   xcrun ran and could not find devicectl — DEVELOPER_DIR pointing at
#        CommandLineTools, which is THE trap here (xcode-select's default)
#   127  $XCRUN itself does not exist
# `1` stays quiet: it is what a never-paired device returns, and also what a
# bogus DEVELOPER_DIR returns, and the two cannot be told apart.
case "$rc" in
    0) ;;
    72|127) log "devicectl unavailable (exit $rc) — check AU_IOS_DEVELOPER_DIR"; exit 1 ;;
    *) exit 10 ;;
esac
# A herestring, not `printf | grep -q`. Under `pipefail` a grep that exits on
# its first match leaves printf writing into a closed pipe; past 64 KiB of
# output printf dies of SIGPIPE, the pipeline is non-zero, `&& exit 10` does
# not fire, and the absent phone gets built for again. Measured, not guessed:
# status 141 at exactly 65536 bytes.
grep -qiE 'Device State:[[:space:]]*unavailable' <<<"$details" && exit 10

# Whether the phone SAYS it is here. Used for one thing only, further down:
# deciding whether "no destination" may be believed as absence. An allow-list
# is safe for THAT question, because its failure direction is loud.
present=0
grep -qiE 'Device State:[[:space:]]*(connected|available)' <<<"$details" && present=1

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

# Per scheme, like DERIVED. It was one fixed path in /tmp for every project on
# this template — harmless while it only fed `tail -5`, not now that it decides
# loud versus silent: two projects build concurrently by design, and one could
# read the other's "no destination" and go quiet about a real failure.
mkdir -p "$DERIVED"
BUILD_LOG="${AU_IOS_BUILD_LOG:-$DERIVED/autoupdate-build.log}"

# A quiet exit is a string match against a tool that has already changed its
# wording once, and "quiet" means it leaves no trace in the job log. The next
# run truncates $BUILD_LOG — so keep one generation of what we decided to stay
# silent about. If a quiet path ever misfires, this is the only evidence.
keep_quiet_evidence() { cp "$BUILD_LOG" "$BUILD_LOG.last-quiet" 2>/dev/null || true; }

if ! "$XCODEBUILD" -project "$PROJECT" -scheme "$SCHEME" \
        -destination "id=$ECID" -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates build >"$BUILD_LOG" 2>&1; then
    # A LOCKED phone. Observed 2026-09-20: devicectl says `connected`, and
    # xcodebuild lists the device as "needs to be unlocked to enable
    # development services". That is "not now" in the plainest sense — it is
    # locked all night — and nothing here can fix it but waiting.
    #
    # Scoped to OUR device. xcodebuild lists every paired device, each on its
    # own line with its own `id:` — the real one, from that morning:
    #   { platform:iOS, arch:arm64, id:00008120-…, name:…, error:… needs to be
    #     unlocked to enable development services Please unlock the device. }
    # Unscoped, the iPad asleep in the kitchen matched this for a job aimed at
    # the iPhone, and a wrong ECID went quiet for ever by way of someone
    # else's lock screen.
    # (`${ECID}` braced and delimited: real ECIDs are [0-9A-F-], so nothing to
    # escape, and an invalid ERE makes grep exit 2 → not quiet → loud.)
    if grep -qE "id:${ECID}[,}[:space:]][^}]*needs to be unlocked" "$BUILD_LOG"; then
        keep_quiet_evidence; exit 10
    fi
    # "No destination" is absence ONLY if the phone did not just tell us it is
    # here. A phone reporting itself present with no destination is a wrong
    # ECID — the ECID/UUID swap at the top of this file — and waiting will
    # never fix that, so it must stay loud. This is the permanent silent stall
    # the deny-match above exists to refuse, and the first version of this
    # fallback let it back in.
    if [ "$present" = 0 ] && grep -qE \
        "(Unable to find a (destination|device)|Timed out waiting for all destinations) matching the provided destination specifier" \
        "$BUILD_LOG"; then keep_quiet_evidence; exit 10; fi
    log "BUILD FAILED — device left with the build it had"
    # The FIRST error line, then the tail. `tail -5` alone kept the end of a
    # destination list and threw away the one line that said what was wrong —
    # twice, on the morning that line was needed.
    grep -m1 -E "error:" "$BUILD_LOG" >> "${AU_LOG:-/dev/null}"
    tail -5 "$BUILD_LOG" >> "${AU_LOG:-/dev/null}"
    exit 1
fi

app="$DERIVED/Build/Products/Debug-iphoneos/$SCHEME.app"
[ -d "$app" ] || { log "built, but no .app at $app"; exit 1; }

"$XCRUN" devicectl device install app --device "$DEVICE" "$app" >>"${AU_LOG:-/dev/null}" 2>&1 \
    || { log "install failed — will retry"; exit 1; }
