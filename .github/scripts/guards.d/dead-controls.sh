# A control that draws and does nothing.
#
# "Add a day" in the plan editor was dead in every release through v0.1.1. Not
# a limit, not a failed save — a `Button` whose label was an `ActionRow`, which
# is itself a `Button`, with `.allowsHitTesting(false)` on the inner one to stop
# the two fighting over the tap. That does not hand the tap outward. It removes
# the only hit-testable content the outer control had, so BOTH go dead.
#
# It was introduced by a visual refactor (f16e454, "Settings and the plan editor
# are drawn by hand") that swapped a passive `Label` for an `ActionRow`. The
# action in that diff is unchanged and correct, which is why review did not
# catch it, and the row still renders perfectly, which is why screenshots did
# not either. The failure mode is invisible to everything except a finger.
#
# Three greps, each catching a different half of that:
#
#   1. `.allowsHitTesting(false)` in a view — the mechanism.
#   2. an interactive component used as another control's label — the cause.
#   3. an empty action closure — the action that goes nowhere.
#
# STRUCTURAL, like the other guards here: the presence of a construct, not a
# judgement about whether a screen is any good.
cmd_dead_controls() {
  local views="app/RathiFitness/Views"
  local rc=0

  [ -d "$views" ] || { echo "✓ no views to check."; return 0; }

  # The components that are themselves a Button/NavigationLink. `SettingRow`,
  # `SettingFigure`, `StatusLine` and `ActionRowLabel` are deliberately NOT in
  # here — they are appearance only, which is exactly what makes them safe to
  # use as somebody else's label.
  local interactive='ActionRow|ToggleRow|ChoiceRow|StepperRow|TogglePill|DisclosureRow'

  # 1. The mechanism. Zero legitimate uses in this app today; every future one
  #    is somebody resolving a nested-interactive conflict the wrong way.
  local hit
  hit=$(grep -rn 'allowsHitTesting(false)' "$views" 2>/dev/null \
        | grep -vE ':[0-9]+: *(//|\*|///)' || true)
  if [ -n "$hit" ]; then
    echo "::error::.allowsHitTesting(false) in a view:"
    echo "$hit" | sed 's/^/    /'
    echo "  This does not pass the tap to the parent — it removes the parent's only"
    echo "  hit-testable content, and both controls go dead. That shipped once. If you"
    echo "  need a row's appearance inside something already interactive, use the"
    echo "  appearance-only type (ActionRowLabel / SettingRow) instead of nesting."
    rc=1
  fi

  # 2. The cause. `} label: {` followed within a few lines by a component that
  #    brings its own Button. Four lines is enough for the opening brace, a
  #    comment and a modifier without reaching the next control.
  local nested
  nested=$(awk -v pat="$interactive" '
    FNR == 1 { depth = 0 }
    depth > 0 {
      depth--
      if ($0 ~ "(^|[^A-Za-z])(" pat ")\\(") {
        printf "%s:%d: %s\n", FILENAME, FNR, $0
        depth = 0
      }
      next
    }
    /label: *\{/ { depth = 4 }
  ' $(find "$views" -name '*.swift') 2>/dev/null | grep -vE ':[0-9]+: *(//|\*|///)' || true)
  if [ -n "$nested" ]; then
    echo "::error::an interactive row is being used as another control's label:"
    echo "$nested" | sed 's/^/    /'
    echo "  These types are Buttons. Nesting one inside a Button or NavigationLink"
    echo "  makes two controls compete for the tap, and every way of settling that"
    echo "  fight has ended with neither of them firing. Give the row its own action,"
    echo "  or use the appearance-only type as the label."
    rc=1
  fi

  # 3. The action that goes nowhere. `ActionRow(...) {}` compiled fine and was
  #    half of why the dead button looked deliberate.
  local empty
  empty=$(grep -rnE "($interactive)\(.*\) *\{ *\}" "$views" 2>/dev/null \
          | grep -vE ':[0-9]+: *(//|\*|///)' || true)
  if [ -n "$empty" ]; then
    echo "::error::a control with an empty action:"
    echo "$empty" | sed 's/^/    /'
    echo "  A row that draws and does nothing reads to the user as a refusal, not a"
    echo "  bug. If it genuinely has nothing to do, it should not be tappable."
    rc=1
  fi

  # 4. A control you can see and cannot press. Under `.buttonStyle(.plain)` a
  #    button's hit area is the OPAQUE part of its label, so a background painted
  #    `Color.clear` — an outline-style button, an unselected chip — is tappable
  #    only on its glyphs and its one-point stroke unless a `contentShape` says
  #    otherwise. `PrimaryButton`, `SecondaryButton`, the three set chips and the
  #    cardio note chip all shipped that way: "Skip to set N" drew a 54-point bar
  #    and answered to almost none of it.
  #
  #    File-scoped rather than per-view, because a `contentShape` two lines below
  #    the fill is the fix and a grep cannot pair them reliably. Narrow enough to
  #    be honest: `Color.clear` is rare here and always deliberate.
  local invisible
  for f in $(grep -rlE '\.fill\([^)]*Color\.clear|Color\.clear[^)]*\)$' "$views" 2>/dev/null || true); do
    grep -qE '\.fill\(|\.stroke\(' "$f" || continue
    grep -qE 'Color\.clear' "$f" || continue
    # `listRowBackground(Color.clear)` is not a hit area; it is a List being told
    # to stop drawing its own row fill.
    grep -E 'Color\.clear' "$f" | grep -qvE 'listRowBackground|//' || continue
    grep -q 'contentShape(' "$f" || invisible="$invisible$f\n"
  done
  if [ -n "$invisible" ]; then
    echo "::error::a control is painted Color.clear with no contentShape:"
    printf "%b" "$invisible" | sed 's/^/    /'
    echo "  Under .buttonStyle(.plain) the hit area is the OPAQUE part of the label,"
    echo "  so a clear fill is a button you can see and cannot press. Add"
    echo "  .contentShape(RoundedRectangle(cornerRadius: ...)) matching what it draws."
    rc=1
  fi

  [ "$rc" -eq 0 ] && echo "✓ no control draws without acting."
  return $rc
}
EXTRA+=(dead-controls)
