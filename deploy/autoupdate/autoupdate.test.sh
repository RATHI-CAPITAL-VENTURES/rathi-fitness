#!/usr/bin/env bash
#
# Self-test for the auto-update spine and the iOS apply hook.
#
# Every branch here is a decision about when NOT to touch a device, and testing
# them through real merges would cost a push, a build and a device per case. The
# device and Xcode are stubbed; the git half runs against throwaway repos.
#
# Written after two real bugs shipped in the first (untested) version of this:
# a guard that grepped for a bundle id `devicectl` never prints, so it could not
# fire, and a hardcoded launchd PATH that made every branch past the first tool
# unreachable from a test.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPINE="$HERE/autoupdate.sh"
IOS="$HERE/apply.d/ios.sh"
PASS=0; FAIL=0

ok()  { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ok   $3";
        else FAIL=$((FAIL+1)); echo "  FAIL $3 (got '$1', wanted '$2')"; fi; }
says() { if grep -qF "$1" "$LOG"; then PASS=$((PASS+1)); echo "  ok   $2";
         else FAIL=$((FAIL+1)); echo "  FAIL $2 — log has no '$1'"; fi; }
quiet() { if ! grep -qE "APPLIED|FAILED|REFUSING" "$LOG"; then
            PASS=$((PASS+1)); echo "  ok   $1";
          else FAIL=$((FAIL+1)); echo "  FAIL $1 — logged: $(cat "$LOG")"; fi; }

setup() {
    TMP=$(mktemp -d)
    REMOTE="$TMP/remote"; CLONE="$TMP/clone"
    LOG="$TMP/log"; STATE="$TMP/state"; BIN="$TMP/bin"
    mkdir -p "$REMOTE" "$BIN"; : > "$LOG"

    git init -q --bare "$REMOTE"
    git init -q "$TMP/seed"
    (cd "$TMP/seed"
     git config user.email t@t.t; git config user.name t; git config commit.gpgsign false
     mkdir -p app && echo one > app/thing && printf 'x\n' > app/project.yml
     git add -A && git commit -qm one
     git branch -M main && git remote add origin "$REMOTE" && git push -q origin main)
    # Without this the bare repo's HEAD still points at refs/heads/master and
    # the clone comes out empty.
    git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
    git clone -q "$REMOTE" "$CLONE"
    (cd "$CLONE"; git config user.email t@t.t; git config user.name t
     git config commit.gpgsign false)

    cat > "$BIN/xcrun" <<STUB
#!/bin/bash
case "\$*" in
  *"info details"*)   [ -n "\${STUB_REACHABLE:-}" ] || exit 1 ;;
  *"info processes"*) [ -n "\${STUB_RUNNING:-}" ] && echo "9 /x/Thing.app/Thing" ;;
  *"install app"*)    [ -n "\${STUB_INSTALL_FAILS:-}" ] && exit 1; echo "App installed:" ;;
esac
exit 0
STUB
    cat > "$BIN/xcodebuild" <<STUB
#!/bin/bash
[ -n "\${STUB_BUILD_FAILS:-}" ] && { echo "error: nope"; exit 1; }
d=\$(echo "\$@" | sed 's/.*-derivedDataPath //;s/ .*//')
mkdir -p "\$d/Build/Products/Debug-iphoneos/Thing.app"
exit 0
STUB
    printf '#!/bin/bash\nexit 0\n' > "$BIN/xcodegen"
    printf '#!/bin/bash\necho /usr/bin\n' > "$BIN/xcode-select"
    chmod +x "$BIN"/*
}
teardown() { rm -rf "$TMP"
    unset STUB_REACHABLE STUB_RUNNING STUB_BUILD_FAILS STUB_INSTALL_FAILS; }

run() {
    AU_CONF=/dev/null AU_REPO="$CLONE" AU_LOG="$LOG" AU_STATE="$STATE" \
    AU_APPLY="${APPLY_OVERRIDE:-$IOS}" \
    AU_PATH="$BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    AU_IOS_PROJECT="Thing.xcodeproj" AU_IOS_SCHEME="Thing" \
    AU_IOS_ECID="E" AU_IOS_DEVICE="D" AU_IOS_APP_PROCESS="/Thing.app/" \
    AU_IOS_DERIVED="$TMP/derived" AU_IOS_DEVELOPER_DIR="/usr" \
    AU_XCRUN="$BIN/xcrun" AU_XCODEBUILD="$BIN/xcodebuild" \
    bash "$SPINE"
    echo $?
}
new_commit() { (cd "$TMP/seed"; echo more >> app/thing; git commit -qam two; git push -q origin main); }

echo "autoupdate — the spine"

setup
  ok "$(run)" "0" "nothing new exits cleanly"
  quiet "and says nothing about it"
teardown

setup
  (cd "$CLONE"; git checkout -qb feature); new_commit
  ok "$(run)" "0" "a feature branch is left alone"
  quiet "silently — working is not an error"
teardown

setup
  (cd "$CLONE"; echo dirty >> app/thing); new_commit
  run > /dev/null
  quiet "a dirty tree is left alone"
  ok "$(cat "$STATE" 2>/dev/null || echo none)" "none" "and nothing is recorded"
teardown

setup
  # amend the commit the clone is ON — adding one and amending THAT still
  # fast-forwards, which is how this case first passed for the wrong reason
  (cd "$TMP/seed"; git commit -q --amend -m "one, rewritten"; git push -qf origin main)
  run > /dev/null
  says "REFUSING" "a diverged origin is refused rather than reset"
teardown

echo "autoupdate — the iOS hook"

setup
  new_commit; export STUB_REACHABLE=1 STUB_RUNNING=1
  run > /dev/null
  says "not interrupting" "an open app is never interrupted"
  ok "$(cat "$STATE" 2>/dev/null || echo none)" "none" "and nothing is recorded as applied"
teardown

setup
  new_commit; export STUB_REACHABLE=1
  run > /dev/null
  says "APPLIED" "a new commit with the app closed installs"
  ok "$(cd "$CLONE" && git rev-parse HEAD)" "$(cat "$STATE")" "and the commit is recorded"
teardown

setup
  new_commit                      # no STUB_REACHABLE: device away
  run > /dev/null
  quiet "an absent device is not an error"
  ok "$(cat "$STATE" 2>/dev/null || echo none)" "none" "and nothing is recorded"
teardown

setup
  new_commit; export STUB_REACHABLE=1 STUB_BUILD_FAILS=1
  run > /dev/null
  says "APPLY FAILED" "a build failure is reported"
  ok "$(cat "$STATE" 2>/dev/null || echo none)" "none" "and the device is left alone"
teardown

setup
  new_commit; export STUB_REACHABLE=1 STUB_INSTALL_FAILS=1
  run > /dev/null
  says "APPLY FAILED" "an install failure is reported"
  ok "$(cat "$STATE" 2>/dev/null || echo none)" "none" "and retried next tick"
teardown

setup
  new_commit; export STUB_REACHABLE=1
  run > /dev/null; : > "$LOG"
  run > /dev/null
  quiet "a second run with nothing new does nothing"
teardown

echo "autoupdate — config reaches the hook"

# The path every real project takes. The other cases pass AU_IOS_* as an env
# prefix, which a child process inherits for free — so they could not have
# caught a conf whose values never left this shell, which is exactly what
# shipped once.
setup
  new_commit; export STUB_REACHABLE=1
  cat > "$TMP/conf" <<CONF
AU_REPO="$CLONE"
AU_LOG="$LOG"
AU_STATE="$STATE"
AU_APPLY="$IOS"
AU_PATH="$BIN:/usr/bin:/bin:/usr/sbin:/sbin"
AU_IOS_PROJECT="Thing.xcodeproj"
AU_IOS_SCHEME="Thing"
AU_IOS_ECID="E"
AU_IOS_DEVICE="D"
AU_IOS_APP_PROCESS="/Thing.app/"
AU_IOS_DERIVED="$TMP/derived"
AU_IOS_DEVELOPER_DIR="/usr"
AU_XCRUN="$BIN/xcrun"
AU_XCODEBUILD="$BIN/xcodebuild"
CONF
  AU_CONF="$TMP/conf" bash "$SPINE" > /dev/null
  says "APPLIED" "values from autoupdate.conf reach the apply hook"
  ok "$(cd "$CLONE" && git rev-parse HEAD)" "$(cat "$STATE")" "and the commit is recorded"
teardown

echo "autoupdate — the hook contract"

setup
  new_commit
  printf '#!/bin/bash\nexit 10\n' > "$TMP/hook"; chmod +x "$TMP/hook"
  APPLY_OVERRIDE="$TMP/hook" run > /dev/null
  quiet "a hook saying 'not now' is believed and stays quiet"
  ok "$(cat "$STATE" 2>/dev/null || echo none)" "none" "and nothing is recorded"
  unset APPLY_OVERRIDE
teardown

setup
  new_commit
  printf '#!/bin/bash\nexit 3\n' > "$TMP/hook"; chmod +x "$TMP/hook"
  APPLY_OVERRIDE="$TMP/hook" run > /dev/null
  says "APPLY FAILED" "any other exit code is a failure"
  unset APPLY_OVERRIDE
teardown

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
