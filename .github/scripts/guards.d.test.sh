#!/usr/bin/env bash
#
# Tests for THIS project's guards — the ones in guards.d/.
#
# Separate from guards.test.sh on purpose: that file belongs to the shared
# template and `bootstrap` replaces it on every upgrade, so anything written
# into it would be lost the first time the template moved.
#
# Each case asserts the exit code AND that the message names the thing that is
# wrong. A guard that fails for the right reason with the wrong explanation is
# one people learn to ignore.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PASS=0; FAIL=0

# Each case runs against a throwaway copy of the tree, so a test can break the
# repo without breaking the repo.
sandbox() {
  local dir; dir=$(mktemp -d)
  mkdir -p "$dir/app/RathiFitness/Model" \
           "$dir/app/RathiFitness/Views" \
           "$dir/app/RathiFitness/Design" \
           "$dir/app/RathiFitness/Assets.xcassets/AppIcon.appiconset" \
           "$dir/cli" "$dir/docs" "$dir/.github/scripts/guards.d"
  cp "$HERE"/guards.sh "$dir/.github/scripts/"
  cp "$HERE"/guards.conf "$dir/.github/scripts/"
  cp "$HERE"/guards.d/*.sh "$dir/.github/scripts/guards.d/"

  printf 'static let currentSchema = 4\n' > "$dir/app/RathiFitness/Model/Snapshot.swift"
  printf 'SCHEMA_SUPPORTED = 4\n' > "$dir/cli/gym"
  printf '| Version | Change |\n| --- | --- |\n| 4 | cardio |\n' > "$dir/docs/SNAPSHOT.md"
  printf 'let x = 1\n' > "$dir/app/RathiFitness/Views/TodayView.swift"
  printf 'public static let ground = Color.black\n' > "$dir/app/RathiFitness/Design/RFDesign.swift"
  for n in 20 29 40 58 60 76 80 87 120 152 167 180 1024; do
    : > "$dir/app/RathiFitness/Assets.xcassets/AppIcon.appiconset/icon-$n.png"
  done
  printf '{"images":[{"filename":"icon-20.png"}]}\n' \
    > "$dir/app/RathiFitness/Assets.xcassets/AppIcon.appiconset/Contents.json"

  # A real git repo, because guards.sh refuses to load without a diff to read.
  # These guards read the working tree rather than the diff, so base == head is
  # the honest setup: "nothing changed, is the tree still coherent?"
  ( cd "$dir"
    git init -q
    git config user.email t@t; git config user.name t
    git add -A >/dev/null; git commit -qm base ) >/dev/null 2>&1
  echo "$dir"
}

# run <sandbox> <guard> -> prints output, returns the guard's exit code
run() {
  ( cd "$1"
    local sha; sha=$(git rev-parse HEAD)
    BASE_SHA="$sha" HEAD_SHA="$sha" bash .github/scripts/guards.sh "$2" 2>&1 )
}

check() {
  local name="$1" want_rc="$2" want_text="$3" out rc
  out=$(run "$SB" "$4"); rc=$?
  if [ "$rc" != "$want_rc" ]; then
    echo "  FAIL $name — exit $rc, wanted $want_rc"; echo "$out" | sed 's/^/       /'
    FAIL=$((FAIL + 1)); return
  fi
  if [ -n "$want_text" ] && ! grep -qi -- "$want_text" <<< "$out"; then
    echo "  FAIL $name — message never mentions '$want_text'"; echo "$out" | sed 's/^/       /'
    FAIL=$((FAIL + 1)); return
  fi
  echo "  ok   $name"; PASS=$((PASS + 1))
}

# --------------------------------------------------------------- snapshot-schema
echo "snapshot-schema"
SB=$(sandbox)
check "agrees across all three" 0 "agrees" snapshot-schema

SB=$(sandbox); printf 'SCHEMA_SUPPORTED = 3\n' > "$SB/cli/gym"
check "app ahead of the CLI is caught" 1 "cli/gym reads 3" snapshot-schema

SB=$(sandbox); printf 'static let currentSchema = 9\n' > "$SB/app/RathiFitness/Model/Snapshot.swift"
printf 'SCHEMA_SUPPORTED = 9\n' > "$SB/cli/gym"
check "a bump with no history row is caught" 1 "no history row" snapshot-schema

SB=$(sandbox); rm "$SB/cli/gym"
check "a missing end of the contract is caught" 1 "missing" snapshot-schema

# ------------------------------------------------------------------- house-style
echo "house-style"
SB=$(sandbox)
check "clean views pass" 0 "house primitives" house-style

SB=$(sandbox); printf 'var body: some View {\n  Form {\n  }\n}\n' > "$SB/app/RathiFitness/Views/Bad.swift"
check "a stock Form is caught" 1 "Form" house-style

SB=$(sandbox); printf '.foregroundStyle(Color(red: 0.1, green: 0.2, blue: 0.3))\n' \
  > "$SB/app/RathiFitness/Views/Bad.swift"
check "a colour literal is caught" 1 "colour is defined outside" house-style

SB=$(sandbox); printf '// Color(red: 0.1, green: 0.2, blue: 0.3) was here\n' \
  > "$SB/app/RathiFitness/Views/Bad.swift"
check "a colour in a comment is not a colour" 0 "" house-style

# ------------------------------------------------------------------- icon-ladder
echo "icon-ladder"
SB=$(sandbox)
check "the full ladder passes" 0 "full iOS icon ladder" icon-ladder

SB=$(sandbox); rm "$SB/app/RathiFitness/Assets.xcassets/AppIcon.appiconset/icon-20.png"
check "the notification size missing is caught" 1 "BLANK notification" icon-ladder

SB=$(sandbox); printf '{"images":[{"filename":"icon-1024.png"}]}\n' \
  > "$SB/app/RathiFitness/Assets.xcassets/AppIcon.appiconset/Contents.json"
check "files present but unreferenced is caught" 1 "has to name them" icon-ladder

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
