"""Landmarks traced from r-type.jpg (1024x572 sheet) for the Helix Wraith build.

Frame: X long (sleek hovering nose End A +X, biomechanical claw End B -X), Y width, Z up, ground Z=0.
The sheet has NO wheels on the sleek half and a tracked bogie under the heavy half, so the only
dimensional anchor is the overall side-elevation length (claw tips px 226 to nose tip px 850 = 5.0 m).
Side elevation: ground (track contact) py 281. Top view centre line py 421.5.
Tables are taken from per-column ink extents of the sheet (side y 112..285, top y 322..524) and
gridded ak-look crops (qa/helix_ref/*.png).
"""
from bisect import bisect_right

X_TIP_B, X_TIP_A = 226.0, 850.0
LENGTH = 5.0
SCALE = LENGTH / (X_TIP_A - X_TIP_B)  # m per px
CENTER_PX = (X_TIP_A + X_TIP_B) / 2
GROUND_PX = 281.0
TOP_CENTER_PY = 421.5

# side-elevation upper silhouette of the fuselage / carapace spine: (px x, px y)
TOP = [(297, 196), (305, 170), (310, 153), (320, 145), (330, 140), (350, 135), (370, 131), (400, 131),
       (420, 134), (450, 135), (460, 139), (470, 141), (480, 146), (500, 144), (540, 142), (560, 144),
       (580, 147), (600, 154), (620, 162), (640, 169), (660, 166), (700, 166), (720, 169), (740, 174),
       (760, 182), (780, 192), (810, 205), (835, 216), (850, 224)]
# lower hull line (core fuselage / carapace belly)
BOT = [(297, 232), (330, 242), (360, 250), (470, 250), (490, 238), (520, 240), (550, 247), (565, 249),
       (590, 242), (630, 242), (690, 246), (740, 247), (780, 247), (810, 243), (830, 232), (850, 224)]
# half-width (px) of the central hull from the top view
HALF = [(297, 30), (310, 44), (330, 50), (400, 52), (470, 56), (500, 58), (540, 56), (560, 64), (600, 62),
        (630, 68), (660, 52), (690, 44), (740, 36), (790, 28), (820, 24), (835, 14), (850, 0.5)]

# tracked bogie (side view, per flank): sprocket centres, outer track radius, rollers, pivots
TRACK_PX_X = (352.0, 444.0)
TRACK_R_PX = 21.0
TRACK_Y = 0.625  # centre of each track (top view housings 325..362 / 482..518 around 421.5)
TRACK_W = 0.30
FENDER_PX = (322.0, 472.0)  # x extent of the armoured sponson
ROLLER_PX_X = (375.0, 391.0, 407.0)
PIVOT_PX_X = (362.0, 421.0)

# weapon pods (top view y 332..352 / 492..512; side view x 656..795, barrels to 814)
POD_PX_X = (656.0, 795.0)
POD_Y = 0.64
POD_Z_PX = 244.0
POD_R = 0.095
# claw pivots (side view)
CLAW_PIVOT_PX = ((305.0, 224.0, 12.0), (282.0, 236.0, 8.0))
# canopies (side view)
CANOPY_AFT_PX = (490.0, 615.0)
CANOPY_FWD_PX = (652.0, 772.0)


def X(px):
    return (px - CENTER_PX) * SCALE


def Z(py):
    return (GROUND_PX - py) * SCALE


def Y(py):
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
    (k0, v0), (k1, v1) = table[i], table[i + 1]
    return v0 + (v1 - v0) * (px - k0) / (k1 - k0)


def top_z(x):
    return Z(lerp_table(TOP, PX(x)))


def bot_z(x):
    return Z(lerp_table(BOT, PX(x)))


def half_w(x):
    return lerp_table(HALF, PX(x)) * SCALE


# Canopy domes ride on the hull: the sheet's upper silhouette is the glass, so the hull line is lower.
DOMES = ((490.0, 615.0, 18.0), (652.0, 772.0, 14.0))  # (px start, px end, rise px)


def dome_rise_px(px):
    import math
    for a, b, rise in DOMES:
        if a < px < b:
            return rise * math.sin(math.pi * (px - a) / (b - a)) ** 0.7
    return 0.0


def hull_top_z(x):
    px = PX(x)
    return Z(lerp_table(TOP, px) + dome_rise_px(px))
