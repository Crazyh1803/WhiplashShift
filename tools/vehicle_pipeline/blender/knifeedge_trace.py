"""Landmarks traced from hot-wheels.jpg (1024x572 sheet) for the Knifeedge build.

Frame: X long (speedster End A +X, truck End B -X), Y width, Z up, ground Z=0.
One uniform scale comes from the two side-elevation wheel centres (px 348 and 824) which are the
3.38 m wheelbase (hubs x -1.72 / +1.66).  Side elevation ground line y=285; top-down centre
line y=431.  Side and top views are proportion authority; the two front elevations are drawn at
inconsistent scales and are used only for feature placement (lamps, domes, track).  Tables were
measured from labelled grid crops (tools/vehicle_pipeline/qa/knifeedge_ref/*.png) and
corrected against overlay renders.
"""
from bisect import bisect_right

GROUND_PX = 285.0
TOP_CENTER_PY = 431.0
WHEEL_PX = {"truck": (348.0, 236.0, 49.0), "coupe": (824.0, 249.0, 36.0)}
WHEEL_X = {"truck": -1.72, "coupe": 1.66}
WHEELBASE = WHEEL_X["coupe"] - WHEEL_X["truck"]
SCALE = WHEELBASE / (WHEEL_PX["coupe"][0] - WHEEL_PX["truck"][0])  # m per px
CENTER_PX = WHEEL_PX["truck"][0] - WHEEL_X["truck"] / SCALE
# Display (visual-only) tyre radii from the sheet: 49 px and 36 px.
WHEEL_R = {"truck": round(WHEEL_PX["truck"][2] * SCALE, 3), "coupe": round(WHEEL_PX["coupe"][2] * SCALE, 3)}
WHEEL_W = {"truck": 0.24, "coupe": 0.13}
# Visual half-tracks (hub y): top view puts the spiked truck tyres at 0.57..0.80 m and the speedster
# wheels inside 0.63 m pontoon fenders.
TRACK_Y = {"truck": 0.66, "coupe": 0.50}

# Central flywheel / belt drive (side view): flywheel (639,244) r25, pulley (583,241) r10.
FLY_PX = (639.0, 244.0, 25.0)
PULLEY_PX = (583.0, 241.0, 10.0)
FLY_Y = 0.55  # half-distance of the body-mounted pair


def X(px):
    return (px - CENTER_PX) * SCALE


def Z(py):
    return (GROUND_PX - py) * SCALE


def Y(py):
    """Top-view image row -> world Y (upper image edge is +Y)."""
    return (TOP_CENTER_PY - py) * SCALE


def PX(x):
    return x / SCALE + CENTER_PX


def PY(z):
    return GROUND_PX - z / SCALE


def lerp_table(table, px):
    keys = [k for k, _ in table]
    if px <= keys[0]:
        return table[0][1]
    if px >= keys[-1]:
        return table[-1][1]
    i = bisect_right(keys, px) - 1
    (a, va), (b, vb) = table[i], table[i + 1]
    return va + (vb - va) * (px - a) / (b - a)


# Side-elevation top line of the main mass (py), excluding stack/gauge/push-bar protrusions.
TOP = [
    (296, 150), (308, 130), (320, 134), (396, 136), (432, 136), (436, 130), (446, 112),
    (452, 96), (460, 89), (475, 88), (525, 90), (550, 95), (575, 104), (600, 118),
    (625, 138), (650, 158), (675, 162), (700, 166), (712, 174), (725, 184), (750, 187),
    (800, 192), (850, 197), (870, 200), (878, 210),
]
# Hull underside (py).
SILL = [
    (296, 226), (330, 232), (400, 246), (450, 254), (500, 262), (550, 268), (700, 270),
    (790, 270), (850, 262), (878, 255),
]
# Body half-width in the top view (px, rows from the centre line).
HALF_PX = [
    (296, 41), (325, 43), (350, 47), (375, 50), (400, 53), (425, 66), (450, 72), (475, 75),
    (525, 75), (550, 73), (575, 69), (600, 65), (625, 60), (650, 57), (675, 56), (700, 55),
    (725, 50), (775, 47), (800, 38), (825, 33), (850, 29), (878, 25),
]


def top_z(px):
    return Z(lerp_table(TOP, px))


def sill_z(px):
    return Z(lerp_table(SILL, px))


def half_w(px):
    return lerp_table(HALF_PX, px) * SCALE
