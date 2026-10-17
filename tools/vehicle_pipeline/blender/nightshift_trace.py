"""Landmarks traced from 80sFord.jpg for the Nightshift hard-surface candidate.

Source frame: X long (coupe +X), Y width, Z up, ground at Z=0.  All *_PX tables
are pixels of the 1024x572 sheet (x right, y down).  The sheet is never
stretched: one uniform scale comes from the two wheel centres, which are the
physical wheelbase (3.38 m).  Silhouettes were measured by column edge scans of
the side elevation (x 274..770) and the top-down view (y centre line 409 px).
"""
from bisect import bisect_right

GROUND_PX = 252.0
WHEEL_PX = {"truck": (349.0, 210.0, 41.7), "coupe": (677.0, 213.0, 38.8)}
WHEEL_X = {"truck": -1.72, "coupe": 1.66}
WHEEL_R = {"truck": 0.43, "coupe": 0.40}
WHEEL_W = {"truck": 0.34, "coupe": 0.29}
# Visible half-track; physical hardpoints (0.91) untouched, runtime derives the visible pivot
# from the authored tyre centre.  0.82 keeps outer tyre faces (0.99 / 0.965) under the flare.
TRACK_Y = 0.82
WHEELBASE = WHEEL_X["coupe"] - WHEEL_X["truck"]
SCALE = WHEELBASE / (WHEEL_PX["coupe"][0] - WHEEL_PX["truck"][0])  # m per px
CENTER_PX = WHEEL_PX["truck"][0] - WHEEL_X["truck"] / SCALE
LIFT = WHEEL_R["truck"] - (GROUND_PX - WHEEL_PX["truck"][1]) * SCALE

NOSE_TRUCK_PX = 285.0
NOSE_COUPE_PX = 784.0


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


# Top line of hood / cowl / windshield / roof / deck (py).  Truck cab roof 95, Camaro roof 121.
TOP = [
    (285, 156), (287, 153), (292, 151.5), (300, 150), (312, 147), (336, 145), (368, 142),
    (392, 140.5), (404, 140), (410, 138), (416, 130.9), (424, 121.5), (432, 112.1), (440, 102.6),
    (446, 95.5), (452, 95), (516, 95), (520, 95.5), (523, 103), (526, 112), (529, 118),
    (533, 120.5), (544, 121), (560, 123), (571, 125.5), (580, 130.6), (592, 137.4), (604, 144.2),
    (616, 151), (628, 157.8), (636, 161), (648, 160.5), (664, 162), (680, 164), (696, 165.5),
    (712, 168), (728, 171), (744, 174), (756, 179), (766, 187), (774, 196), (781, 203),
    (784, 207),
]
# Belt / fender shoulder line (py).
BELT = [
    (285, 160), (300, 153), (400, 142), (410, 140), (518, 140), (524, 150), (534, 160),
    (600, 161), (640, 163), (700, 168), (740, 176), (758, 184), (772, 198), (784, 207),
]
# Lowest body edge (py): truck valance, flat rocker, coupe chin.
SILL = [
    (285, 224), (296, 226), (308, 227), (392, 232), (404, 233), (508, 233), (520, 234),
    (628, 234), (700, 231), (724, 229), (740, 228), (770, 226), (784, 225),
]
# Body half-width (metres) from the top-down view; flared at the wheel arches.
HALF = [
    (285, 0.86), (292, 0.90), (304, 0.95), (324, 0.985), (349, 1.000), (374, 0.985),
    (392, 0.965), (420, 0.950), (516, 0.945), (530, 0.930), (545, 0.925), (600, 0.945),
    (632, 0.975), (677, 1.000), (704, 0.980), (730, 0.945), (750, 0.900), (766, 0.830),
    (778, 0.720), (784, 0.600),
]
# Hood / roof top half-width (metres): narrower greenhouse between the hoods.
TOP_HALF = [
    (285, 0.72), (300, 0.79), (392, 0.85), (404, 0.84), (430, 0.80), (448, 0.77),
    (518, 0.77), (530, 0.79), (545, 0.79), (572, 0.80), (604, 0.83), (636, 0.86),
    (700, 0.84), (740, 0.78), (764, 0.70), (784, 0.56),
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
    285, 286.6, 290, 296, 304, 314, 324, 334, 349, 360, 372, 384, 394, 402, 406, 410, 414, 420,
    426, 432, 438, 444, 450, 462, 480, 498, 510, 516, 519.5, 522, 524.5, 527, 530, 533, 535.5,
    540, 550, 562, 572, 582, 592, 602, 612, 622, 632, 642, 654, 666, 677, 690, 702, 714, 726,
    738, 748, 756, 762, 768, 773, 777, 780.5, 782.7, 784,
]))

# Side-window openings in side-elevation pixels (counter-clockwise in x/z).
WINDOW_TRUCK_SIDE = [(420, 138), (432, 119), (441, 108), (449, 105), (512, 105), (514, 138)]
WINDOW_COUPE_SIDE = [(534, 159), (534, 128), (562, 130), (590, 144), (614, 157), (618, 159)]
# Windshield footprints: (start px, end px) along the slope.
WINDSHIELD_TRUCK = (410.0, 444.0)
WINDSHIELD_COUPE = (571.0, 633.0)
