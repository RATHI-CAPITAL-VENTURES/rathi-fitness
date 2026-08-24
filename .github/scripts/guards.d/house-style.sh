# The two rules from DESIGN.md that a person cannot see themselves breaking.
#
# Settings and the plan editor were built out of a stock `Form` and were the
# only two screens that did not look like this app — and the diagnosis was a
# grep, not an opinion: they used zero of the app's typographic primitives
# while Today used twelve. Both are now drawn by hand. This stops the drift
# coming back, in the only way that works: by failing the build.
#
# Deliberately narrow. Both checks are STRUCTURAL — the presence of a
# construct, not a judgement about how a screen looks. A guard that argues
# about quality gets label-spammed until it means nothing.
cmd_house_style() {
  local views="app/RathiFitness/Views"
  local design="app/RathiFitness/Design/RFDesign.swift"
  local rc=0

  [ -d "$views" ] || { echo "✓ no views to check."; return 0; }

  # 1. No stock Form. `List` is still allowed and used in exactly two places,
  #    because onMove and onDelete are real features — reimplementing
  #    drag-to-reorder to win a typeface is a bad trade. `Form` buys nothing
  #    but somebody else's fonts.
  local forms
  forms=$(grep -rln 'Form {' "$views" 2>/dev/null || true)
  if [ -n "$forms" ]; then
    echo "::error::a stock Form is back in Views:"
    echo "$forms" | sed 's/^/    /'
    echo "  Form brings its own fonts, row radius and inset separators — it is why"
    echo "  Settings and the plan editor were the only screens that looked wrong."
    echo "  Build it from Views/SettingsKit.swift instead."
    rc=1
  fi

  # 2. Colour is declared in one place. A hex in a view is how a design system
  #    stops being one — DESIGN.md says it plainly and nothing was checking.
  local literals
  # `grep -rn` prefixes each hit with `path:line:`, so anchoring the
  # comment filter at `^` matched the PATH and never the code. Filter after
  # the line number instead — a colour named in a comment explaining why it
  # moved to RFDesign is not a colour in a view.
  literals=$(grep -rn 'Color(red:\|Color(hue:\|#colorLiteral' "$views" 2>/dev/null \
             | grep -vE ':[0-9]+: *//' || true)
  if [ -n "$literals" ]; then
    echo "::error::a colour is defined outside $design:"
    echo "$literals" | sed 's/^/    /'
    echo "  Every colour comes from RFDesign. A literal here is a value that cannot"
    echo "  follow the cooldown ramp and will not move when the system does."
    rc=1
  fi

  [ "$rc" -eq 0 ] && echo "✓ views use the house primitives."
  return $rc
}
EXTRA+=(house-style)
