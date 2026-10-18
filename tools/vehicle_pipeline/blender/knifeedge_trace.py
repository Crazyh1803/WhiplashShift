"""Landmarks traced from hot-wheels.jpg (1024x572 sheet) for the Knifeedge XR build.

Frame: X long (supercar End A +X, sand-rail End B -X), Y width, Z up, ground Z=0.
One uniform scale comes from the two side-elevation wheel centres (px 360.5 and 663.5), which are the
3.38 m wheelbase (hubs x -1.72 / +1.66).  Side-elevation ground line y=204; top-view centre line y=402.5.
Side and top views are the proportion authority; the two end elevations are drawn at a different scale
and only place features (lamps, grille, bumper).  Tables come from gridded crops
(tools/vehicle_pipeline/qa/knifeedge_ref/*.png) read through ak-look plus thresholded pixel scans of the
sheet, then corrected against overlay renders.
"""
from bisect import bisect_right

GROUND_PX = 204.0
TOP_CENTER_PY = 402.5
WHEEL_PX = {"truck": (360.5, 164.0, 40.0), "coupe": (663.5, 169.0, 35.0)}  # x, y, tyre radius (px)
WHEEL_X = {"truck": -1.72, "coupe": 1.66}
WHEELBASE = WHEEL_X["coupe"] - WHEEL_X["truck"]
SCALE = WHEELBASE / (WHEEL_PX["coupe"][0] - WHEEL_PX["truck"][0])  # m per px
CENTER_PX = WHEEL_PX["truck"][0] - WHEEL_X["truck"] / SCALE
# Display (visual-only) tyre radii: sand-rail knobbies 40 px, supercar tyres 35 px.
WHEEL_R = {"truck": round(WHEEL_PX["truck"][2] * SCALE, 3), "coupe": round(WHEEL_PX["coupe"][2] * SCALE, 3)}
WHEEL_W = {"truck": 0.38, "coupe": 0.30}
# Visual half-tracks (hub y): top view tyres span +/-98 px outer; knobby width 34 px, supercar tyre ~27 px.
TRACK_Y = {"truck": 0.93, "coupe": 0.90}


def X(px):
    return (px - CENTER_PX) * SCALE


def Z(py):
    return (GROUND_PX - py) * SCALE


def Y(py):
    """Top-view image row -> world Y (upper image edge is +Y)."""
    return (TOP_CENTER_PY - py) * SCALE


def W(px):
    """Pixel length -> metres."""
    return px * SCALE


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


# Supercar shell, End A: top line (side py), underside (py), half width (top view, px from centre).
SHELL_PX0, SHELL_PX1 = 452.0, 756.0
SHELL_TOP = [(452, 113), (620, 113), (640, 114), (660, 116), (680, 119), (700, 127), (720, 136),
             (740, 147), (756, 158)]
SHELL_BOT = [(452, 187), (700, 187), (720, 187), (740, 184), (756, 172)]
SHELL_HALF = [(452, 86), (480, 92), (620, 92), (640, 96), (680, 96), (700, 92), (720, 82), (740, 64),
              (756, 18)]
# Rear floor pan (End B): half width (px) from the top view, underside py.
FLOOR_HALF = [(318, 46), (340, 47), (360, 52), (380, 57), (400, 63), (420, 71), (452, 84)]
FLOOR_BOT = [(318, 175), (440, 177), (452, 184)]
# Upper rear slope rail (cage side tube / deck panel): tail (305,110) to roof header (455,66).
ROOF_PY = 66.0
ROOF_HALF_PX = 48.5  # cage half width at the roof (top view roof panels reach +/-50 px)
BELT_PY = 113.0
SLOPE_A = (305.0, 110.0)
SLOPE_B = (455.0, 66.0)


def slope_py(px):
    t = (px - SLOPE_A[0]) / (SLOPE_B[0] - SLOPE_A[0])
    return SLOPE_A[1] + (SLOPE_B[1] - SLOPE_A[1]) * t


FLOOR_THICK = 0.13
FLOOR_TOP_Z = Z(176.5) + FLOOR_THICK  # flat part of the pan under the engine (px 380..440)


def shell_top_z(px):
    return Z(lerp_table(SHELL_TOP, px))


def shell_bot_z(px):
    return Z(lerp_table(SHELL_BOT, px))


def shell_half(px):
    return lerp_table(SHELL_HALF, px) * SCALE
