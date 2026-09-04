#!/bin/bash
# Auto-update — poll origin/main, and when it moves, apply the new commit.
#
# The SPINE only. What "apply" means is a project's business: install a build
# to a phone, restart a launchd service, redeploy a site. That half lives in an
# apply hook (see apply.d/), so the part that is identical everywhere — the git
# safety, the logging, the record of what is live — is written once.
#
# Extracted from rathi-fitness, which needed it because RIA's own auto-deploy
# ships the SERVER only and deliberately never touches a native face: an app/
# change could be merged, green in CI, and still not on the device for weeks.
# Every release there ended with a human running two xcodebuild commands.
#
# Safety, in order:
#   1. Acts ONLY on a clean `main`. A feature branch or any tracked local change
#      makes it skip, so it never applies over work in progress.
#   2. Fast-forward ONLY. A force-push or history rewrite makes it refuse and
#      log, rather than resetting somebody's checkout.
#   3. The apply hook may say "not now" and be believed, for ever. An iOS hook
#      uses this when the app is open on the phone — installing over a running
#      app terminates it, and losing work to a background job is far worse than
#      being a commit behind.
#   4. Nothing is recorded as applied unless the hook succeeded, so a failure
#      retries on the next tick instead of being forgotten.
#
# Config lives in autoupdate.conf beside this script. Every value is overridable
# by env so the flow can be tested against a throwaway repo and stub tools.
#
# Apply-hook contract:
#   exit 0   applied
#   exit 10  not now — try again later, and say nothing (a normal state)
#   other    failed — logged, and NOT recorded as applied

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${AU_CONF:-$HERE/autoupdate.conf}"
# `set -a` so everything the conf defines is EXPORTED, not merely set.
#
# The hook runs as a child process, so a plain `. conf` left every AU_IOS_*
# value in this shell and out of the hook's environment — it died on its first
# `${AU_IOS_PROJECT:?}` and the agent logged APPLY FAILED for a change that was
# perfectly good. The self-test missed it because the harness passes those
# values as an env prefix, which IS inherited; the conf-file path that every
# real project uses was never exercised. There is a case for it now.
set -a
[ -f "$CONF" ] && . "$CONF"
set +a

REPO="${AU_REPO:-}"
LOG="${AU_LOG:-$HOME/Library/Logs/autoupdate.log}"
STATE="${AU_STATE:-$REPO/.autoupdate-applied}"
APPLY="${AU_APPLY:-}"
BRANCH="${AU_BRANCH:-main}"
# launchd gives a job almost no PATH, and a hardcoded one cannot be stubbed —
# which is how the first version of this became untestable past the first tool
# it shelled out to.
PATH="${AU_PATH:-/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin}"
export PATH

mkdir -p "$(dirname "$LOG")" 2>/dev/null
say() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

[ -n "$REPO" ] || { say "no AU_REPO configured"; exit 1; }
[ -n "$APPLY" ] || { say "no AU_APPLY configured"; exit 1; }
cd "$REPO" 2>/dev/null || { say "no repo at $REPO"; exit 1; }

# ------------------------------------------------------------- 1. clean branch
[ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" = "$BRANCH" ] || exit 0
[ -z "$(git status --porcelain --untracked-files=no)" ] || exit 0

git fetch --quiet origin "$BRANCH" 2>/dev/null || { say "fetch failed"; exit 0; }
local_sha=$(git rev-parse HEAD)
remote_sha=$(git rev-parse "origin/$BRANCH")
applied=$(cat "$STATE" 2>/dev/null || echo "")

# Nothing new, and what is checked out is already live.
[ "$local_sha" = "$remote_sha" ] && [ "$applied" = "$local_sha" ] && exit 0

# --------------------------------------------------------- 2. fast-forward only
if [ "$local_sha" != "$remote_sha" ]; then
    if ! git merge-base --is-ancestor "$local_sha" "$remote_sha"; then
        say "REFUSING: origin/$BRANCH has diverged from local — a human should look"
        exit 0
    fi
    git pull --ff-only --quiet origin "$BRANCH" || { say "pull failed"; exit 0; }
    local_sha=$(git rev-parse HEAD)
    say "pulled $(git log -1 --format='%h %s')"
fi

[ "$applied" = "$local_sha" ] && exit 0

# ------------------------------------------------------------------- 3. apply
AU_COMMIT="$local_sha" AU_REPO="$REPO" AU_LOG="$LOG" bash "$APPLY"
case $? in
    0)  echo "$local_sha" > "$STATE"
        say "APPLIED $(git log -1 --format='%h %s')" ;;
    10) : ;;                       # not now. Normal, and deliberately silent.
    *)  say "APPLY FAILED for $(git log -1 --format='%h %s')" ;;
esac
