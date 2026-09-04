#!/usr/bin/env bash
#
# Self-test for rf-autoinstall.sh, against throwaway repos and stub tools.
#
# The same argument the guards' self-test makes: every branch here is a
# decision about when NOT to touch the phone, and testing them through real
# merges would cost a push, a build and a device per case. The device and
# Xcode are stubbed through RF_XCRUN / RF_XCODEBUILD, which exist for this.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/rf-autoinstall.sh"
PASS=0; FAIL=0

ok()  { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ok   $3";
        else FAIL=$((FAIL+1)); echo "  FAIL $3 (got '$1', wanted '$2')"; fi; }
says() { if grep -qF "$2" "$LOG"; then PASS=$((PASS+1)); echo "  ok   $3";
         else FAIL=$((FAIL+1)); echo "  FAIL $3 — log has no '$2'"; fi; }
silent() { if [ ! -s "$LOG" ]; then PASS=$((PASS+1)); echo "  ok   $1";
           else FAIL=$((FAIL+1)); echo "  FAIL $1 — logged: $(cat "$LOG")"; fi; }

setup() {
    TMP=$(mktemp -d)
    REMOTE="$TMP/remote"; CLONE="$TMP/clone"
    LOG="$TMP/log"; STATE="$TMP/state"; BIN="$TMP/bin"
    mkdir -p "$REMOTE" "$BIN"
    : > "$LOG"                 # `says` greps it; a missing file is not a pass

    git init -q --bare "$REMOTE"
    git init -q "$TMP/seed"
    (cd "$TMP/seed"
     git config user.email t@t.t; git config user.name t; git config commit.gpgsign false
     mkdir -p app && echo one > app/thing
     git add -A && git commit -qm "one"
     git branch -M main && git remote add origin "$REMOTE" && git push -q origin main)
    # The bare repo's HEAD still points at refs/heads/master, so a clone comes
    # out empty and every later `git -C "$CLONE"` reads a repo with no commits.
    git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
    git clone -q "$REMOTE" "$CLONE"
    (cd "$CLONE"; git config user.email t@t.t; git config user.name t
     git config commit.gpgsign false)

    # Stubs. `reachable` and `running` are set per case.
    cat > "$BIN/xcrun" <<STUB
#!/bin/bash
case "\$*" in
  *"info details"*)   [ -n "\${STUB_REACHABLE:-}" ] && echo "• Identifier: X" ;;
  *"info processes"*) [ -n "\${STUB_RUNNING:-}" ] && echo "9 /x/RathiFitness.app/RathiFitness" ;;
  *"install app"*)    [ -n "\${STUB_INSTALL_FAILS:-}" ] && exit 1; echo "App installed:" ;;
esac
exit 0
STUB
    cat > "$BIN/xcodebuild" <<STUB
#!/bin/bash
[ -n "\${STUB_BUILD_FAILS:-}" ] && { echo "error: nope"; exit 1; }
mkdir -p "\$(echo "\$@" | sed 's/.*-derivedDataPath //;s/ .*//')/Build/Products/Debug-iphoneos/RathiFitness.app"
exit 0
STUB
    cat > "$BIN/xcodegen" <<'STUB'
#!/bin/bash
exit 0
STUB
    chmod +x "$BIN"/*
    export PATH="$BIN:$PATH"
}
teardown() { rm -rf "$TMP"; unset STUB_REACHABLE STUB_RUNNING STUB_BUILD_FAILS STUB_INSTALL_FAILS; }

run() {
    RF_REPO="$CLONE" RF_LOG="$LOG" RF_STATE="$STATE" \
    RF_DERIVED="$TMP/derived" RF_XCRUN="$BIN/xcrun" RF_XCODEBUILD="$BIN/xcodebuild" \
    RF_PATH="$BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "$SCRIPT"
    echo $?
}

push_new_commit() {
    (cd "$TMP/seed"; echo two >> app/thing; git commit -qam "two"; git push -q origin main)
}

echo "rf-autoinstall"

setup
  code=$(run)
  ok "$code" "0" "nothing new exits cleanly"
  silent "and says nothing about it"
teardown

setup
  (cd "$CLONE"; git checkout -qb feature)
  push_new_commit
  code=$(run)
  ok "$code" "0" "a feature branch is left alone"
  silent "silently — it is not an error to be working"
teardown

setup
  (cd "$CLONE"; echo dirty >> app/thing)
  push_new_commit
  code=$(run)
  ok "$code" "0" "a dirty tree is left alone"
  silent "silently"
teardown

setup
  push_new_commit
  STUB_REACHABLE=1 STUB_RUNNING=1
  export STUB_REACHABLE STUB_RUNNING
  run > /dev/null
  says "" "not interrupting a workout" "an open app is never interrupted"
  ok "$(cat "$STATE" 2>/dev/null || echo none)" "none" "and nothing is recorded as installed"
teardown

setup
  push_new_commit
  export STUB_REACHABLE=1
  run > /dev/null
  says "" "INSTALLED" "a new commit with the app closed installs"
  ok "$(cd "$CLONE" && git rev-parse HEAD)" "$(cat "$STATE")" "the installed commit is recorded"
teardown

setup
  push_new_commit
  export STUB_REACHABLE=1 STUB_BUILD_FAILS=1
  run > /dev/null
  says "" "BUILD FAILED" "a build failure is reported"
  ok "$(cat "$STATE" 2>/dev/null || echo none)" "none" "and the phone is left alone"
teardown

setup
  push_new_commit
  # unreachable: no STUB_REACHABLE
  run > /dev/null
  if grep -qE "INSTALLED|FAILED|REFUSING" "$LOG"; then
      FAIL=$((FAIL+1)); echo "  FAIL an unreachable phone is not an error"
  else
      PASS=$((PASS+1)); echo "  ok   an unreachable phone is not an error"
  fi
teardown

setup
  push_new_commit
  export STUB_REACHABLE=1
  run > /dev/null                       # installs
  : > "$LOG"
  run > /dev/null                       # nothing new now
  silent "a second run with nothing new does nothing"
  ok "$(cd "$CLONE" && git rev-parse HEAD)" "$(cat "$STATE")" "and the record still matches"
teardown

setup
  # History rewritten UNDER the clone: amending the commit it is sitting on is
  # what makes local no longer an ancestor of origin. Adding a commit and then
  # amending THAT still fast-forwards, which is how this case first passed for
  # the wrong reason.
  (cd "$TMP/seed"; git commit -q --amend -m "one, rewritten"; git push -qf origin main)
  run > /dev/null
  says "" "REFUSING" "a diverged origin is refused rather than reset"
teardown

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
