"""Landmarks traced from dodge.jpg for the Ramjet hard-surface blueprint build.

Source frame: X long (coupe +X), Y width, Z up, ground at Z=0.  All *_PX tables
are pixels of the 1024x572 sheet (x right, y down).  The sheet is never
stretched: one uniform scale comes from the two wheel centres, which are the
physical wheelbase (3.38 m).  Silhouettes were measured by column edge scans of
the side elevation (x 277..745, ground y 237) and the top-down view; the front
elevations (Ram B at x 48..216, Conquest A at x 790..956) set widths and heights.
"""
from bisect import bisect_right

GROUND_PX = 237.0
WHEEL_PX = {"truck": (363.0, 203.0, 34.0), "coupe": (660.0, 203.0, 33.0)}
WHEEL_X = {"truck": -1.72, "coupe": 1.66}
WHEEL_R = {"truck": 0.43, "coupe": 0.40}
WHEEL_W = {"truck": 0.33, "coupe": 0.35}
# Visible half-track: both front elevations put the tyre centres 75.5 px off the centre line
# (Ram x 48..76 / 199..227 about 137.5; Conquest x 801..833 / 952..984 about 892.5) = 0.86 m.
# Physical hardpoints (0.91) are untouched; the runtime derives the visible pivot.
TRACK_Y = 0.86
WHEELBASE = WHEEL_X["coupe"] - WHEEL_X["truck"]
SCALE = WHEELBASE / (WHEEL_PX["coupe"][0] - WHEEL_PX["truck"][0])  # m per px
CENTER_PX = WHEEL_PX["truck"][0] - WHEEL_X["truck"] / SCALE
LIFT = WHEEL_R["truck"] - (GROUND_PX - WHEEL_PX["truck"][1]) * SCALE

NOSE_TRUCK_PX = 294.0
NOSE_COUPE_PX = 758.0
# Cab-back wall (roof step): the Ram roof ends and the Conquest roof starts lower.
STEP_PX = (535.0, 547.0)


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


# Top line of hood / cowl / windshield / roof / deck (py).  Ram cab roof 69, Conquest roof 100.
TOP = [
    (294, 134), (297, 129), (301, 126), (306, 124), (318, 123),
    (340, 122), (360, 121.5), (380, 121), (400, 121), (412, 121), (418, 119), (424, 111),
    (430, 102), (438, 94), (444, 85), (450, 80), (456, 74), (462, 70), (468, 69), (522, 68.5),
    (530, 69), (535, 70), (538, 73), (541, 80), (544, 88), (547, 93), (554, 96), (562, 98),
    (568, 102), (574, 108), (584, 116), (594, 124), (604, 134), (612, 136.5), (630, 135.5),
    (650, 136.5), (668, 138), (684, 140), (698, 142), (710, 145), (720, 151), (730, 155),
    (738, 161), (743, 166), (747, 171), (751, 174), (755, 178), (757.4, 181), (758, 183),
]
# Belt / fender shoulder line (py).
BELT = [
    (294, 150), (300, 134), (306, 128), (320, 125), (412, 125), (418, 123), (535, 123),
    (547, 138), (600, 141), (640, 141), (684, 144), (710, 150), (730, 160), (743, 169),
    (751, 178), (758, 188),
]
# Lowest body edge (py): truck valance, flat rocker, coupe skirt rising into the bumper cover.
SILL = [
    (294, 197), (300, 199), (330, 200), (404, 200), (470, 201), (486, 207), (510, 210),
    (540, 210), (600, 211), (690, 214), (703, 212), (710, 205), (730, 202), (758, 199),
]
# Body half-width (metres) from the top-down and front views; flared at the wheel arches.
HALF = [
    (294, 1.000), (299, 1.015), (304, 1.030), (330, 1.050), (363, 1.060), (396, 1.040),
    (420, 1.010), (520, 1.000), (535, 0.995), (560, 0.990), (610, 1.000), (640, 1.030),
    (660, 1.060), (690, 1.040), (715, 1.000), (730, 0.985), (743, 0.960), (751, 0.930),
    (758, 0.860),
]
# Hood / roof top half-width (metres): fender-top plus a narrower greenhouse; the Ram roof is
# 0.655 m half-wide and widens ~0.5 px/px down the A-pillar (front elevation rows 70..102).
TOP_HALF = [
    (294, 0.96), (300, 0.97), (392, 0.97), (412, 0.96), (424, 0.91), (436, 0.81), (450, 0.74),
    (468, 0.66), (522, 0.655), (535, 0.66), (547, 0.64), (560, 0.66), (574, 0.74),
    (590, 0.86), (604, 0.93), (640, 0.95), (700, 0.94), (730, 0.90), (758, 0.80),
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


# Pixel stations of the cage. Denser at both noses, the cowl, the roof step and the arches.
STATIONS = sorted(set([
    294, 295.5, 298, 301, 304, 314, 324, 336, 350, 363, 376, 390, 402, 412, 418, 424, 430, 437,
    444, 451, 458, 466, 478, 492, 506, 520, 528, 532, 535, 537.5, 540, 543, 547, 551, 558, 566,
    574, 584, 594, 604, 614, 626, 638, 650, 660, 672, 684, 696, 708, 718, 726, 733, 738, 743, 748,
    753, 756.3, 758,
]))

# Side-window openings in side-elevation pixels (counter-clockwise in x/z).
WINDOW_TRUCK_SIDE = [(452, 121), (466, 90), (472, 84), (524, 84), (528, 121)]
WINDOW_COUPE_SIDE = [(549, 138), (549, 102), (556, 100), (566, 103), (598, 133), (596, 138)]
# Windshield footprints: (start px, end px) along the slope.
WINDSHIELD_TRUCK = (421.0, 462.0)
WINDSHIELD_COUPE = (568.0, 606.0)
