"""Landmarks traced from 80sFord.jpg for the Deadbolt hard-surface candidate.

Source frame: X long (coupe +X), Y width, Z up, ground at Z=0.  All *_PX tables
are pixels of the 1024x572 sheet (x right, y down).  The sheet is never
stretched: one uniform scale comes from the two wheel centres, which are the
physical wheelbase (3.38 m).  Silhouettes were measured by column edge scans of
the side elevation (x 274..770) and the top-down view (y centre line 409 px).
"""
from bisect import bisect_right

GROUND_PX = 241.0
WHEEL_PX = {"truck": (346.0, 205.0, 36.5), "coupe": (667.0, 205.0, 36.5)}
WHEEL_X = {"truck": -1.72, "coupe": 1.66}
WHEEL_R = {"truck": 0.43, "coupe": 0.40}
WHEEL_W = {"truck": 0.34, "coupe": 0.29}
TRACK_Y = 0.91
WHEELBASE = WHEEL_X["coupe"] - WHEEL_X["truck"]
SCALE = WHEELBASE / (WHEEL_PX["coupe"][0] - WHEEL_PX["truck"][0])  # m per px
CENTER_PX = WHEEL_PX["truck"][0] - WHEEL_X["truck"] / SCALE
# Drawn tyres are 0.385 m; the physical wheels are 0.43/0.40 m. Raise the whole
# drawing so the drawn axle line meets the physical axle height.
LIFT = WHEEL_R["truck"] - (GROUND_PX - WHEEL_PX["truck"][1]) * SCALE

NOSE_TRUCK_PX = 285.0
NOSE_COUPE_PX = 770.0


def X(px):
    return (px - CENTER_PX) * SCALE


def Z(py):
    return (GROUND_PX - py) * SCALE + LIFT


def PX(x):
    return x / SCALE + CENTER_PX


def PY(z):
    return GROUND_PX - (z - LIFT) / SCALE


def lerp_table(table, px):
    keys = [k for k, _ in table]
    if px <= keys[0]:
        return table[0][1]
    if px >= keys[-1]:
        return table[-1][1]
    i = bisect_right(keys, px) - 1
    (a, va), (b, vb) = table[i], table[i + 1]
    t = (px - a) / (b - a)
    return va + (vb - va) * t


# Top line of hood / cowl / windshield / roof / deck (py).
TOP = [
    (285, 137), (287, 133.5), (292, 131.5), (300, 128), (316, 126), (332, 125), (348, 123),
    (372, 122), (388, 121), (396, 118.5), (404, 113), (412, 105), (420, 97), (428, 89),
    (436, 82), (444, 76.5), (452, 74.5), (508, 74), (516, 74.5), (524, 76), (532, 79),
    (540, 83), (556, 91), (572, 103), (588, 113), (604, 125), (620, 131), (636, 135),
    (652, 135.5), (668, 138), (684, 139), (700, 142), (716, 145), (732, 150), (748, 155),
    (756, 164), (762, 174), (766, 183), (769, 190), (770, 193),
]
# Belt / fender shoulder line (py).
BELT = [
    (285, 141), (300, 133), (396, 131), (404, 130.5), (510, 130.5), (522, 141),
    (560, 145), (600, 150), (640, 151), (700, 152), (740, 160), (756, 168),
    (764, 182), (770, 195),
]
# Lowest body edge (py): truck valance, flat rocker, coupe chin.
SILL = [
    (285, 207), (296, 206), (308, 206), (392, 212), (404, 213), (508, 213),
    (520, 214), (628, 214), (700, 213), (724, 212.5), (740, 212), (756, 212),
    (766, 212), (770, 212),
]
# Body half-width (metres) from the top-down view; flared at the wheel arches.
HALF = [
    (285, 0.86), (292, 0.90), (300, 0.94), (318, 0.995), (346, 1.010), (374, 0.995),
    (392, 0.965), (420, 0.950), (508, 0.950), (540, 0.950), (600, 0.960), (628, 0.980),
    (667, 1.010), (704, 0.990), (730, 0.950), (750, 0.92), (762, 0.88), (770, 0.80),
]
# Hood / roof top half-width (metres): narrower greenhouse between the hoods.
TOP_HALF = [
    (285, 0.74), (300, 0.80), (392, 0.85), (404, 0.84), (428, 0.80), (448, 0.78),
    (508, 0.78), (524, 0.79), (556, 0.81), (604, 0.83), (636, 0.85), (700, 0.84),
    (740, 0.79), (762, 0.72), (770, 0.62),
]


def top_z(px):
    return Z(lerp_table(TOP, px))


def belt_z(px):
    return Z(lerp_table(BELT, px))


def sill_z(px):
    return Z(lerp_table(SILL, px))


def half_width(px):
    return lerp_table(HALF, px)


def top_half(px):
    return lerp_table(TOP_HALF, px)


# Pixel stations of the cage. Denser at both noses, the cowl, the cab/coupe
# transition and around the arches; closely spaced pairs act as support loops.
STATIONS = sorted(set([
    285, 286.6, 290, 296, 304, 314, 324, 334, 346, 358, 368, 378, 388, 394, 399.5, 404,
    409, 415, 421, 428, 436, 444, 452, 470, 490, 508, 515, 520, 524, 530, 540, 552, 566,
    580, 594, 606, 618, 628, 640, 654, 667, 680, 692, 704, 716, 728, 738, 746, 752, 757,
    761, 764.5, 767.5, 770,
]))

# Side-window openings in side-elevation pixels (counter-clockwise in x/z).
WINDOW_TRUCK_SIDE = [(414, 127), (448, 85), (452, 82), (503, 82), (505, 127)]
WINDOW_COUPE_SIDE = [(520, 141), (520, 87), (548, 96), (574, 112), (597, 131), (604, 140),
                     (604, 149)]
# Windshield footprints: (start px, end px) along the slope.
WINDSHIELD_TRUCK = (406.0, 438.0)
WINDSHIELD_COUPE = (549.0, 611.0)
