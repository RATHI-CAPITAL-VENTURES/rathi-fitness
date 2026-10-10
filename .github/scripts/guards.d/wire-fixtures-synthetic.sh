# The lens wire fixtures are PUBLIC, and must stay made up.
#
# This repo is public and the fixtures are fetched by another repo's CI, so a
# fixture recorded from a real workout would publish what the owner lifts and
# when. Three checks, each on the bytes:
#
#   1. Every "title" is an exercise from Catalogue.swift, or one of the fixed
#      synthetic phrases below — never a track you were really playing.
#   2. Every load (the number before " ×") comes from a fixed synthetic list.
#   3. No date and no timestamp: nothing like 2026-10-10, and no integer of ten
#      digits or more (seconds or milliseconds since 1970). Fixtures count
#      time from zero.
SYNTHETIC_LOADS="45 95 135 185 225"
SYNTHETIC_TITLES="Synthetic Track|Nothing playing|That's the workout"

cmd_wire_fixtures_synthetic() {
  local dir="wire/fixtures"
  local catalogue="app/RathiFitness/Model/Catalogue.swift"
  local rc=0

  [ -d "$dir" ] || { echo "✓ no wire fixtures to check."; return 0; }
  [ -f "$catalogue" ] || { echo "::error::$catalogue is missing — exercise names are checked against it."; return 1; }

  local names
  names=$(grep -oE '"[^"]+"' "$catalogue" | tr -d '"' | sort -u)

  local f title load bad=""
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    while IFS= read -r title; do
      [ -n "$title" ] || continue
      if printf '%s\n' "$title" | grep -qxE "$SYNTHETIC_TITLES"; then continue; fi
      if printf '%s\n' "$names" | grep -qxF -- "$title"; then continue; fi
      # "Treadmill is left" — a catalogue machine, said by the wrap-up card.
      if printf '%s\n' "$names" | grep -qxF -- "${title% is left}" && [ "$title" != "${title% is left}" ]; then continue; fi
      bad="$bad  $f: title \"$title\" is not a Catalogue name or a synthetic phrase\n"
    done < <(grep -oE '"title":"[^"]*"' "$f" | sed 's/^"title":"//; s/"$//')

    while IFS= read -r load; do
      [ -n "$load" ] || continue
      case " $SYNTHETIC_LOADS " in *" $load "*) ;; *)
        bad="$bad  $f: load $load is not in the synthetic list ($SYNTHETIC_LOADS)\n" ;;
      esac
    done < <(grep -oE '[0-9]+(\.[0-9]+)?( each| help)? ×' "$f" | grep -oE '^[0-9]+(\.[0-9]+)?')

    if grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$f"; then
      bad="$bad  $f: has a date\n"
    fi
    if grep -qE '(^|[^0-9.])[0-9]{10,}' "$f"; then
      bad="$bad  $f: has a number of ten digits or more — a timestamp\n"
    fi
  done

  if [ -n "$bad" ]; then
    echo "::error::a wire fixture is not synthetic:"
    printf "%b" "$bad"
    echo "  The fixtures are public. Use Catalogue names, the loads $SYNTHETIC_LOADS,"
    echo "  and times counted from zero (LensWireTests.t0)."
    rc=1
  fi
  [ "$rc" -eq 0 ] && echo "✓ wire fixtures are synthetic."
  return $rc
}
EXTRA+=(wire-fixtures-synthetic)
