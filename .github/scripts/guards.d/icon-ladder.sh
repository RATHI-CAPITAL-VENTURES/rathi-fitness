# A single 1024 is not an app icon, and the failure looks like success.
#
# Xcode derives the 60pt and 76pt renditions from a lone 1024 and none of the
# small ones — so the 20pt a NOTIFICATION draws is simply absent from the
# bundle. The home screen looks perfect while the banner arrives with a grey
# crosshatch where the icon goes. RIA learned this the expensive way and has a
# test for it; this app now sends notifications when a rest ends, which makes
# that banner the feature rather than a corner case.
#
# Also checks she is there at all. Every app in the RIA family carries her face
# — that is a house rule, and the icon is generated, so the only way it goes
# missing is the generator failing to find her and printing a warning nobody
# reads.
cmd_icon_ladder() {
  local set_dir="app/RathiFitness/Assets.xcassets/AppIcon.appiconset"
  local rc=0
  [ -d "$set_dir" ] || { echo "::error::$set_dir is missing."; return 1; }

  # The sizes iOS actually asks for. Notifications draw 20pt, Settings 29pt and
  # Spotlight 40pt; those are the three a lone 1024 leaves empty.
  local required="20 29 40 58 60 76 80 87 120 152 167 180 1024"
  local missing=""
  for size in $required; do
    [ -f "$set_dir/icon-$size.png" ] || missing="$missing $size"
  done

  if [ -n "$missing" ]; then
    echo "::error::the icon ladder is missing:$missing"
    echo "  A lone 1024 renders a correct home screen and a BLANK notification icon."
    echo "  Run: python3 design/make_icon.py"
    rc=1
  fi

  if ! grep -q '"filename" *: *"icon-20.png"\|icon-20.png' "$set_dir/Contents.json" 2>/dev/null; then
    echo "::error::Contents.json does not reference the small renditions."
    echo "  The files existing is not enough — the catalogue has to name them."
    rc=1
  fi

  [ "$rc" -eq 0 ] && echo "✓ the full iOS icon ladder is present."
  return $rc
}
EXTRA+=(icon-ladder)
