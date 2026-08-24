# The snapshot is a contract between two codebases in two languages, and it has
# three ends. This guard exists because it broke twice in one afternoon.
#
# `Snapshot.currentSchema` in the app, `SCHEMA_SUPPORTED` in cli/gym, and the
# history table in docs/SNAPSHOT.md all have to move together. They cannot be
# derived from each other — one is Swift on a phone, one is Python on a Mac —
# so the only thing that can hold them together is a check.
#
# The failure mode is quiet and total: the CLI refuses a version it does not
# know, so RIA goes blind to the gym log until someone notices. Bumping the app
# alone does not fail any test; it fails at the next `gym today`, on the Mac,
# with a message about the phone being ahead.
cmd_snapshot_schema() {
  local swift_file="app/RathiFitness/Model/Snapshot.swift"
  local cli_file="cli/gym"
  local doc_file="docs/SNAPSHOT.md"
  local rc=0

  for f in "$swift_file" "$cli_file" "$doc_file"; do
    [ -f "$f" ] || { echo "::error::$f is missing — the snapshot contract has three ends and this is one of them."; return 1; }
  done

  local app_schema cli_schema
  app_schema=$(grep -oE 'currentSchema = [0-9]+' "$swift_file" | grep -oE '[0-9]+' | head -1)
  cli_schema=$(grep -oE '^SCHEMA_SUPPORTED = [0-9]+' "$cli_file" | grep -oE '[0-9]+' | head -1)

  if [ -z "$app_schema" ] || [ -z "$cli_schema" ]; then
    echo "::error::could not read the schema number from $swift_file or $cli_file."
    echo "  Expected 'currentSchema = N' and 'SCHEMA_SUPPORTED = N'."
    return 1
  fi

  if [ "$app_schema" != "$cli_schema" ]; then
    echo "::error::the app writes snapshot schema $app_schema; cli/gym reads $cli_schema."
    echo "  The CLI refuses a version it does not know, so RIA goes blind to the gym"
    echo "  log until both move. Update SCHEMA_SUPPORTED in $cli_file."
    rc=1
  fi

  # Every version needs a row saying what changed, because "schema 4" tells a
  # reader nothing about which field stopped meaning what it used to.
  if ! grep -qE "^\| $app_schema \|" "$doc_file"; then
    echo "::error::$doc_file has no history row for schema $app_schema."
    echo "  Add one to the table. A bump with no row is a changed meaning nobody wrote down."
    rc=1
  fi

  [ "$rc" -eq 0 ] && echo "✓ snapshot schema $app_schema agrees across app, CLI and docs."
  return $rc
}
EXTRA+=(snapshot-schema)
