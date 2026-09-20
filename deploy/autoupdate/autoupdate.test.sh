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
# grep's THREE outcomes, not two. 1 is "not found" — quiet. Anything above is
# grep not having run at all, and `if ! grep` read that as quiet too: on Linux
# a 200 KB environment variable made every exec fail ("Argument list too
# long"), this printed ok, and CI was green about a case that ran nothing.
quiet() { grep -qE "APPLIED|FAILED|REFUSING" "$LOG"; local rc=$?
          if [ "$rc" -eq 1 ]; then PASS=$((PASS+1)); echo "  ok   $1";
          elif [ "$rc" -eq 0 ]; then FAIL=$((FAIL+1)); echo "  FAIL $1 — logged: $(cat "$LOG")";
          else FAIL=$((FAIL+1)); echo "  FAIL $1 — could not even read the log (grep exit $rc)"; fi; }

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
  # As the real tool behaves, which is NOT how this stub used to: it modelled
  # an absent phone as a non-zero exit, the same wrong guess the script made,
  # so the two agreed with each other and with nothing else. A paired phone
  # that is out of reach exits ZERO and says so in the text. STUB_UNKNOWN is a
  # device this Mac has never paired with — the one case that does exit 1.
  *"info details"*)   [ -n "\${STUB_XCRUN_RC:-}" ] && exit "\${STUB_XCRUN_RC}"
                      [ -n "\${STUB_UNKNOWN:-}" ] && exit 1
                      echo "Current device information:"
                      if [ -n "\${STUB_STATE:-}" ]; then echo "    • Device State: \${STUB_STATE}"
                      elif [ -n "\${STUB_REACHABLE:-}" ]; then echo "    • Device State: connected"
                      else echo "    • Device State: unavailable"; fi
                      # A long report is long OUTPUT. It was a 200 KB environment
                      # variable, which Linux refuses per string at 128 KiB — so
                      # on the CI runner nothing in that case could be exec'd.
                      [ -n "\${STUB_LONG:-}" ] && head -c "\${STUB_LONG}" /dev/zero | tr '\0' x
                      ;;
  *"info processes"*) [ -n "\${STUB_RUNNING:-}" ] && echo "9 /x/Thing.app/Thing" ;;
  *"install app"*)    [ -n "\${STUB_INSTALL_FAILS:-}" ] && exit 1; echo "App installed:" ;;
esac
exit 0
STUB
    cat > "$BIN/xcodebuild" <<STUB
#!/bin/bash
d=\$(echo "\$@" | sed 's/.*-derivedDataPath //;s/ .*//')
# BEFORE it can fail, as the real one does. This used to come after the failure
# branch, so with STUB_BUILD_FAILS set the directory could never exist and "no
# build was attempted" — which looks for it — passed while the log beside it
# said BUILD FAILED. An assertion that cannot fail is not one.
mkdir -p "\$d"
[ "\${STUB_NO_DESTINATION:-}" = TIMEOUT ] && {
  echo "xcodebuild: error: Timed out waiting for all destinations matching the provided destination specifier to become available"
  exit 70; }
[ -n "\${STUB_NO_DESTINATION:-}" ] && {
  echo "xcodebuild: error: Unable to find a \${STUB_NO_DESTINATION} matching the provided destination specifier:"
  exit 70; }
# The line shape is copied from a real failed run, `id:` and all — the first
# version of this stub had no id, which is why no test could see that the lock
# check was not scoped to a device. STUB_LOCKED names WHOSE lock screen it is.
[ -n "\${STUB_LOCKED:-}" ] && {
  echo "xcodebuild: error: Timed out waiting for all destinations matching the provided destination specifier to become available"
  echo ""
  echo "	Destinations compatible with the \"Thing\" scheme:"
  echo "		{ platform:iOS, arch:arm64, id:\${STUB_LOCKED}, name:A Device, error:A Device needs to be unlocked to enable development services Please unlock the device. }"
  exit 70; }
[ -n "\${STUB_BUILD_FAILS:-}" ] && { echo "error: nope"; exit 1; }
mkdir -p "\$d/Build/Products/Debug-iphoneos/Thing.app"
exit 0
STUB
    printf '#!/bin/bash\nexit 0\n' > "$BIN/xcodegen"
    printf '#!/bin/bash\necho /usr/bin\n' > "$BIN/xcode-select"
    chmod +x "$BIN"/*
}
teardown() { rm -rf "$TMP"
    unset STUB_REACHABLE STUB_RUNNING STUB_BUILD_FAILS STUB_INSTALL_FAILS STUB_UNKNOWN \
          STUB_NO_DESTINATION STUB_STATE STUB_LONG STUB_LOCKED STUB_XCRUN_RC; }

run() {
    AU_CONF=/dev/null AU_REPO="$CLONE" AU_LOG="$LOG" AU_STATE="$STATE" \
    AU_APPLY="${APPLY_OVERRIDE:-$IOS}" \
    AU_PATH="$BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    AU_LOCK="$TMP/lock" \
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
  new_commit                      # no STUB_REACHABLE: paired, and out of reach
  export STUB_BUILD_FAILS=1       # what xcodebuild really does with no device
  run > /dev/null
  quiet "an absent device is not an error"
  ok "$(cat "$STATE" 2>/dev/null || echo none)" "none" "and nothing is recorded"
  ok "$([ -d "$TMP/derived" ] && echo built || echo untouched)" "untouched" \
     "and no build is attempted for a phone that is not there"
teardown

setup
  new_commit; export STUB_UNKNOWN=1 STUB_BUILD_FAILS=1   # never paired: exits 1
  run > /dev/null
  quiet "a device this Mac has never met is not an error either"
teardown

# A state word nobody has seen yet. The deny-match lets it through on purpose;
# xcodebuild then says there is nothing to build for, and THAT is believed.
setup
  new_commit; export STUB_STATE="disconnected" STUB_NO_DESTINATION=destination
  run > /dev/null
  quiet "no destination is absence, whatever devicectl called it"
  ok "$(cat "$STATE" 2>/dev/null || echo none)" "none" "and nothing is recorded"
teardown

# The wording that is actually ON DISK from a real run — and that the first two
# versions of this fallback did not match at all.
setup
  new_commit; export STUB_STATE="disconnected"
  export STUB_NO_DESTINATION="TIMEOUT"
  run > /dev/null
  quiet "'Timed out waiting for all destinations' is absence too"
teardown

# The older wording, which three places in this repo had recorded as THE one.
setup
  new_commit; export STUB_STATE="disconnected" STUB_NO_DESTINATION=device
  run > /dev/null
  quiet "in either of xcodebuild's wordings"
teardown

# The phone says it is HERE and xcodebuild cannot find it: that is a wrong ECID,
# and waiting will never fix it. Silent here is silent for ever.
setup
  new_commit; export STUB_REACHABLE=1 STUB_NO_DESTINATION=destination
  run > /dev/null
  says "BUILD FAILED" "a present phone with no destination is a wrong ECID, and loud"
teardown

# Locked all night, with a commit waiting: not an error, and not a log line
# every ten minutes until morning.
setup
  new_commit; export STUB_REACHABLE=1 STUB_LOCKED=E     # E is AU_IOS_ECID: OUR phone
  run > /dev/null
  quiet "a locked phone is 'not now'"
  ok "$(cat "$STATE" 2>/dev/null || echo none)" "none" "and nothing is recorded"
teardown

# The iPad asleep in the kitchen. Our phone says it is here and xcodebuild
# cannot find it — a wrong ECID — and someone ELSE's lock screen is in the list.
setup
  new_commit; export STUB_REACHABLE=1 STUB_LOCKED=SOME-OTHER-DEVICE
  run > /dev/null
  says "BUILD FAILED" "a wrong ECID stays loud even when ANOTHER device is locked"
  says "Timed out waiting" "and the log keeps the line that says WHY, not just a tail"
teardown

# A quiet exit leaves no line in the job log by design, so it must leave the
# build log somewhere: it is the only evidence if a quiet path ever misfires.
setup
  new_commit; export STUB_REACHABLE=1 STUB_LOCKED=E
  run > /dev/null
  ok "$([ -s "$TMP/derived/autoupdate-build.log.last-quiet" ] && echo kept || echo lost)" \
     "kept" "a quiet exit keeps the build log it decided to stay silent about"
teardown

# DEVELOPER_DIR pointing at CommandLineTools: xcrun runs, finds no devicectl,
# exits 72. The tool is away, not the phone — silent would be silent for ever.
setup
  new_commit; export STUB_XCRUN_RC=72
  run > /dev/null
  says "devicectl unavailable" "a missing devicectl (72) is reported, not waited out"
teardown

setup
  new_commit; export STUB_XCRUN_RC=127
  run > /dev/null
  says "devicectl unavailable" "and so is a missing xcrun (127)"
teardown

# ...but a real build failure on a phone that IS there stays loud.
setup
  new_commit; export STUB_REACHABLE=1 STUB_BUILD_FAILS=1
  run > /dev/null
  says "BUILD FAILED" "a broken build on a present phone is still reported"
teardown

# The state is on line 1 of more than a pipe buffer of output. With
# `printf | grep -q` under pipefail this lost the exit 10 to SIGPIPE.
setup
  new_commit; export STUB_BUILD_FAILS=1 STUB_LONG=200000
  run > /dev/null
  quiet "a long device report cannot lose 'not now' to a closed pipe"
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

echo "autoupdate — one at a time"

# launchd fires on a schedule whether or not the last run finished, and an
# Xcode build outruns a ten-minute tick easily. Two instances sharing a
# derived-data path made xcodebuild die with "database is locked", logged as
# APPLY FAILED for a perfectly good commit.
setup
  new_commit; export STUB_REACHABLE=1
  mkdir -p "$TMP/lock"; echo $$ > "$TMP/lock/pid"      # a live holder: this shell
  run > /dev/null
  quiet "a second instance stands down while one is running"
  ok "$(cat "$STATE" 2>/dev/null || echo none)" "none" "and applies nothing"
teardown

setup
  new_commit; export STUB_REACHABLE=1
  mkdir -p "$TMP/lock"; echo 999999 > "$TMP/lock/pid"  # holder is long gone
  run > /dev/null
  says "APPLIED" "a stale lock is taken over rather than obeyed for ever"
  says "clearing a stale lock" "and it says so"
teardown

setup
  new_commit; export STUB_REACHABLE=1
  run > /dev/null
  if [ -d "$TMP/lock" ]; then
      FAIL=$((FAIL+1)); echo "  FAIL the lock is released when the run finishes"
  else
      PASS=$((PASS+1)); echo "  ok   the lock is released when the run finishes"
  fi
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
