# A write that touches your training data may not fail quietly.
#
# Every save in this app was `try? context.save()` — twenty-one of them. Nobody
# decided that; it was copied from the first one. The cost only became obvious
# when "Add a day" did nothing and the natural next step was to stream the
# phone's logs while it was pressed: there was nothing to stream. No log line,
# no error, no banner. The button turned out to be dead rather than the save
# failing, but the investigation had no instrument either way.
#
# `context.saveOrReport("adding a day")` is the replacement — see
# Model/Saving.swift. This guard exists because the old form is one autocomplete
# away and reads as perfectly normal Swift, which is exactly the kind of
# regression a person cannot catch by reviewing a diff.
#
# STRUCTURAL, like the other two in here: the presence of a construct, not a
# judgement. And deliberately narrow — `try?` on the haptic engine, the audio
# session or a `Task.sleep` is correct and is not matched.
cmd_silent_saves() {
  local app="app/RathiFitness"
  local rc=0

  [ -d "$app" ] || { echo "✓ no app sources to check."; return 0; }

  # `grep -rn` prefixes `path:line:`, so the comment filter is anchored after
  # the line number — Saving.swift's own docs name the banned form on purpose,
  # and a guard that cannot survive being explained is not much of a guard.
  local silent
  silent=$(grep -rn 'try? *context\.save()\|try? *modelContext\.save()' "$app" 2>/dev/null \
           | grep -vE ':[0-9]+: *(//|\*)' || true)
  if [ -n "$silent" ]; then
    echo "::error::a save is swallowing its own failure:"
    echo "$silent" | sed 's/^/    /'
    echo "  \`try?\` on a save decides for the user that they do not need to know"
    echo "  the set they just logged is gone. Use:"
    echo "      context.saveOrReport(\"logging a set\")"
    echo "  where the string completes \"save failed while ___\". See"
    echo "  $app/Model/Saving.swift."
    rc=1
  fi

  # The same hole one level up: the seed/wipe/export helpers throw, and they
  # touch the same data. `reportingFailure(\"...\") { try ... }` wraps them.
  local silentOps
  silentOps=$(grep -rn 'try? *Seed\.\|try? *Export\.write' "$app" 2>/dev/null \
              | grep -vE ':[0-9]+: *(//|\*)' || true)
  if [ -n "$silentOps" ]; then
    echo "::error::a data operation is swallowing its own failure:"
    echo "$silentOps" | sed 's/^/    /'
    echo "  Wrap it: reportingFailure(\"exporting your data\") { try Export.write(...) }"
    rc=1
  fi

  [ "$rc" -eq 0 ] && echo "✓ no save fails quietly."
  return $rc
}
EXTRA+=(silent-saves)
