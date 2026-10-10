# The Web App lens's wire contract has three ends, like the snapshot's.
#
# `LensWire.version` in the app, the "Wire version:" line in
# docs/LENS_WIRE.md, and the `"v"` in every committed fixture under
# wire/fixtures/ must agree. The fixtures are what ria-ar-feed's CI fetches to
# test the page and the relay against, so a version that moved in Swift alone
# would let the other side keep passing against a contract the phone no longer
# speaks — the failure would arrive on the glasses, mid-workout, as a screen
# the page cannot read.
cmd_wire_schema() {
  local swift_file="app/RathiFitness/Model/LensWire.swift"
  local doc_file="docs/LENS_WIRE.md"
  local dir="wire/fixtures"
  local rc=0

  for f in "$swift_file" "$doc_file"; do
    [ -f "$f" ] || { echo "::error::$f is missing — the lens wire contract has three ends and this is one of them."; return 1; }
  done
  [ -d "$dir" ] || { echo "::error::$dir is missing — the fixtures are the contract's examples."; return 1; }

  local swift_v="" doc_v=""
  swift_v=$(grep -oE 'static let version = [0-9]+' "$swift_file" | grep -oE '[0-9]+$' | head -1 || true)
  doc_v=$(grep -oE '^Wire version: [0-9]+' "$doc_file" | grep -oE '[0-9]+$' | head -1 || true)
  if [ -z "$swift_v" ] || [ -z "$doc_v" ]; then
    echo "::error::could not read the wire version from $swift_file or $doc_file."
    echo "  Expected 'static let version = N' and a line 'Wire version: N'."
    return 1
  fi
  if [ "$swift_v" != "$doc_v" ]; then
    echo "::error::the app speaks lens wire v$swift_v; $doc_file documents v$doc_v."
    rc=1
  fi

  local count=0 f bad=""
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    count=$((count + 1))
    if grep -oE '"v":[0-9]+' "$f" | grep -qvE "^\"v\":$swift_v\$" || ! grep -qE '"v":[0-9]+' "$f"; then
      bad="$bad  $f\n"
    fi
  done
  if [ "$count" -eq 0 ]; then
    echo "::error::$dir has no fixtures."
    rc=1
  fi
  if [ -n "$bad" ]; then
    echo "::error::fixtures that do not say v$swift_v:"
    printf "%b" "$bad"
    echo "  Re-record them (LensWireTests, TEST_RUNNER_LENS_WIRE_RECORD=1) and read the diff."
    rc=1
  fi

  [ "$rc" -eq 0 ] && echo "✓ lens wire v$swift_v agrees across app, docs and $count fixtures."
  return $rc
}
EXTRA+=(wire-schema)
