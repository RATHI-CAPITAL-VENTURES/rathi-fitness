#!/usr/bin/env python3
"""Render the app icon from the one idea in the product.

The icon is the cooldown ring, and its colours come from the same ramp the app
draws with (`RFDesign.coolHue`) rather than from a designer's eyedropper — so if
the mechanic is ever retuned, re-running this keeps the icon honest.

    python3 design/make_icon.py

Writes app/RathiFitness/Assets.xcassets/AppIcon.appiconset/icon-1024.png.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4                      # supersample, then downsample for clean edges
W = SIZE * SS

GROUND = (7, 9, 11)

# RFDesign.swift — keep these in step with it.
EMBER_HUE, HANDOFF_HUE, READY_HUE, WARM_HOLD = 18.0, 44.0, 167.0, 0.75


def cool_hue(p: float) -> float:
    """RFDesign.coolHue, in Python. Warm for three quarters, then hands over."""
    p = min(max(p, 0.0), 1.0)
    if p < WARM_HOLD:
        return EMBER_HUE + (HANDOFF_HUE - EMBER_HUE) * (p / WARM_HOLD)
    t = (p - WARM_HOLD) / (1 - WARM_HOLD)
    return HANDOFF_HUE + (READY_HUE - HANDOFF_HUE) * (t * t * (3 - 2 * t))


def cool_saturation(p: float) -> float:
    return 0.92 - 0.26 * min(max(p, 0.0), 1.0)


EMBER_RGB = (255, 138, 76)
READY_RGB = (95, 220, 196)
BLEND_FROM, BLEND_TO = 0.72, 0.88


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


def hsb(h: float, s: float, v: float) -> tuple[int, int, int]:
    h = (h % 360) / 60.0
    i = int(h)
    f = h - i
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    r, g, b = [(v, t, p), (q, v, p), (p, v, t),
               (p, q, v), (t, p, v), (v, p, q)][i % 6]
    return int(r * 255), int(g * 255), int(b * 255)


def main() -> None:
    img = Image.new("RGB", (W, W), GROUND)

    # The room: her light, in the hue the ring ends on. Drawn on its own layer
    # and blurred, because a hard-edged radial reads as a shape rather than as
    # light coming off the ring.
    glow = Image.new("RGB", (W, W), GROUND)
    gd = ImageDraw.Draw(glow)
    cx = cy = W / 2
    for i in range(40, 0, -1):
        radius = W * 0.50 * (i / 40)
        weight = (1 - i / 40) ** 2
        tint = READY_RGB
        colour = tuple(int(GROUND[c] + (tint[c] - GROUND[c]) * weight * 0.34)
                       for c in range(3))
        gd.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=colour)
    img = Image.blend(img, glow.filter(ImageFilter.GaussianBlur(W * 0.05)), 0.85)

    draw = ImageDraw.Draw(img)

    # The ring. Segment by segment so the colour can travel along it — the whole
    # point being that the arc IS the cooldown, ember at the top where you rack
    # the bar, teal by the time it comes round.
    radius = W * 0.315
    width = int(W * 0.082)
    start, sweep = -90.0, 300.0
    steps = 900
    for i in range(steps):
        p = i / (steps - 1)
        a0 = start + sweep * (i / steps)
        a1 = start + sweep * ((i + 1.6) / steps)   # overlap, so no seams
        colour = ring_colour(p)
        draw.arc([cx - radius, cy - radius, cx + radius, cy + radius],
                 a0, a1, fill=colour, width=width)

    # Round the two ends, the way a stroked SwiftUI arc is capped.
    #
    # PIL strokes an arc INWARD from the bounding box, so the stroke's centreline
    # sits at `radius - width/2`, not at `radius`. Placing the caps at `radius`
    # puts them half a stroke outside the ring, which reads as two blobs stuck
    # to a circle rather than as rounded ends.
    centreline = radius - width / 2
    for angle, p in ((start, 0.0), (start + sweep, 1.0)):
        rad = math.radians(angle)
        ex, ey = cx + centreline * math.cos(rad), cy + centreline * math.sin(rad)
        r = width / 2
        draw.ellipse([ex - r, ey - r, ex + r, ey + r], fill=ring_colour(p))

    out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "app", "RathiFitness", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "icon-1024.png")
    img.resize((SIZE, SIZE), Image.LANCZOS).save(path)
    print("wrote", path)


if __name__ == "__main__":
    main()
