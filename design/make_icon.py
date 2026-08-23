#!/usr/bin/env python3
"""Render the app icon: the cooldown ring, with RIA in the middle of it.

    python3 design/make_icon.py

Writes the whole iOS ladder into
`app/RathiFitness/Assets.xcassets/AppIcon.appiconset/`.

**The ring is this app's idea; RIA is the family's.** The arc's colours come
from the same ramp the app draws with (`RFDesign.coolHue`) rather than from a
designer's eyedropper, so retuning the mechanic and re-running keeps the icon
honest. Her face comes from `ria_icon`, the shared kit in the RIA repo, for the
same reason one level up: every app in the family carries her, and a second
drawing of her made in this repo's toolchain would disagree with the real one
the day either was touched. See `~/RIA/app/icons/ria_icon.py`.

The first cut of this set the letters "RIA" in Fraunces. That is a label about
her, not a picture of her — and the mark is the character. Corrected the same
afternoon.

**The whole ladder, not just the 1024.** A lone 1024 gets a correct home screen
and a BLANK notification banner: Xcode derives the 60pt and 76pt renditions and
none of the small ones, so the 20pt a notification draws is simply absent from
the bundle. This app pings you when a rest ends, so that banner is not a corner
case — it is the feature.
"""
import math
import os
import sys

from PIL import Image

# The shared kit. This project lives inside the RIA checkout, so the path is
# stable; `RIA_ROOT` covers a checkout that is somewhere else.
RIA_ROOT = os.environ.get("RIA_ROOT") or os.path.expanduser("~/RIA")
sys.path.insert(0, os.path.join(RIA_ROOT, "app", "icons"))
try:
    from ria_icon import IconCanvas, IOS_LADDER, READY_RGB   # noqa: E402
except ImportError as exc:                                   # pragma: no cover
    # The kit is a file in the RIA repo, so it is only on disk when that repo is
    # checked out on a branch that has it. Say so, rather than letting a bare
    # ImportError read as a broken script — the committed PNGs are still fine;
    # it is only REGENERATING them that needs the kit.
    raise SystemExit(
        f"the shared icon kit is not at {RIA_ROOT}/app/icons/ria_icon.py ({exc}).\n"
        "It lives in the RIA repo: check out a branch that has it (it landed in\n"
        "v2.38.1), or point RIA_ROOT at a checkout that does. The icons already\n"
        "in the asset catalogue are unaffected — only re-rendering needs this.")

SIZE = 1024

# RFDesign.swift — keep these in step with it.
EMBER_HUE, HANDOFF_HUE, READY_HUE, WARM_HOLD = 18.0, 44.0, 167.0, 0.75

EMBER_RGB = (255, 138, 76)
BLEND_FROM, BLEND_TO = 0.72, 0.88

# The ring, as fractions of the tile.
RING_RADIUS = 0.315
RING_WIDTH = 0.082
RING_START, RING_SWEEP = -90.0, 300.0


def cool_hue(p: float) -> float:
    """RFDesign.coolHue, in Python. Warm for three quarters, then hands over."""
    p = min(max(p, 0.0), 1.0)
    if p < WARM_HOLD:
        return EMBER_HUE + (HANDOFF_HUE - EMBER_HUE) * (p / WARM_HOLD)
    t = (p - WARM_HOLD) / (1 - WARM_HOLD)
    return HANDOFF_HUE + (READY_HUE - HANDOFF_HUE) * (t * t * (3 - 2 * t))


def ring_colour(p: float) -> tuple[int, int, int]:
    """Ember for most of the arc, then a short blend to teal.

    NOT the same as sampling `cool_hue` across the whole arc, and the difference
    is the point. In the app you only ever see ONE value of the ramp at a time,
    so travelling through the hue wheel is a transient nobody registers. An icon
    shows every value at once, and the yellow-green stretch between orange and
    teal becomes a third colour the product does not have — a mood ring.

    So the icon keeps the ramp's *timing* (warm for roughly three quarters, then
    a decisive handover) and blends in RGB, which goes straight from one to the
    other without visiting the hue wheel on the way.
    """
    if p <= BLEND_FROM:
        return EMBER_RGB
    if p >= BLEND_TO:
        return READY_RGB
    t = (p - BLEND_FROM) / (BLEND_TO - BLEND_FROM)
    t = t * t * (3 - 2 * t)
    return tuple(int(EMBER_RGB[c] + (READY_RGB[c] - EMBER_RGB[c]) * t) for c in range(3))


def draw_ring(icon: IconCanvas) -> float:
    """The arc. Returns the clear diameter left inside it, for her.

    Segment by segment so the colour can travel along it — the whole point being
    that the arc IS the cooldown, ember at the top where you rack the bar, teal
    by the time it comes round.
    """
    cx = cy = icon.centre
    radius = icon.W * RING_RADIUS
    width = int(icon.W * RING_WIDTH)
    steps = 900
    for i in range(steps):
        p = i / (steps - 1)
        a0 = RING_START + RING_SWEEP * (i / steps)
        a1 = RING_START + RING_SWEEP * ((i + 1.6) / steps)   # overlap, so no seams
        icon.draw.arc([cx - radius, cy - radius, cx + radius, cy + radius],
                      a0, a1, fill=ring_colour(p), width=width)

    # Round the two ends, the way a stroked SwiftUI arc is capped.
    #
    # PIL strokes an arc INWARD from the bounding box, so the stroke's centreline
    # sits at `radius - width/2`, not at `radius`. Placing the caps at `radius`
    # puts them half a stroke outside the ring, which reads as two blobs stuck
    # to a circle rather than as rounded ends.
    centreline = radius - width / 2
    for angle, p in ((RING_START, 0.0), (RING_START + RING_SWEEP, 1.0)):
        rad = math.radians(angle)
        ex, ey = cx + centreline * math.cos(rad), cy + centreline * math.sin(rad)
        r = width / 2
        icon.draw.ellipse([ex - r, ey - r, ex + r, ey + r], fill=ring_colour(p))

    return (radius - width) * 2


def main() -> None:
    icon = IconCanvas(size=SIZE)
    # Her light, in the hue the ring ends on.
    icon.room(READY_RGB, energy=0.34)
    clear = draw_ring(icon)
    # Her, in the hole the arc left. Sized against that hole rather than the
    # tile, so retuning the ring's weight cannot quietly crop her ears.
    icon.face(clear_diameter=clear, fill=0.72)

    out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "app", "RathiFitness", "Assets.xcassets", "AppIcon.appiconset")
    written = icon.save_ladder(out_dir, IOS_LADDER)
    print(f"wrote {len(written)} sizes to {out_dir}")


if __name__ == "__main__":
    main()
