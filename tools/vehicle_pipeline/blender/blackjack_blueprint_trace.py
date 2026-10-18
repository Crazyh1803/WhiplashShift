"""Hand-traced landmarks from SpyHunter.jpg; never stretch a view's aspect ratio.

X = vehicle length, Y = up, Z = width. All dimensions below are image pixels.
The physical chassis is unchanged; only the rendered skin and modules use these
coordinates. The cage is authored at its settled pose, then inverse-raked for
the canonical export coordinate system.
"""
from mathutils import Matrix, Vector

SCALE = 1.364606 / (694 - 360)
GROUND_PIXEL = 235.0
GROUND_Y = -.395
X_OFFSET = -.02485
POSE = Matrix.Translation((0, .064, 0)) @ Matrix.Rotation(-.0905, 4, 'Z')
INVERSE_POSE = POSE.inverted()

# Longitudinal station, lower sill, belt/fender, roof/hood, top half-width,
# greenhouse half-width. Support stations explicitly preserve folded armor.
STATIONS = [
    (281, 202, 139, 129, 63, 57), (284, 202, 138, 128, 67, 59),
    (298, 183, 128, 124, 76, 63), (326, 162, 125, 114, 78, 64),
    (335, 157, 124, 102, 79, 65), (343, 157, 124, 84, 79, 65),
    (349, 157, 124, 72, 79, 67), (354, 157, 124, 69, 79, 69),
    (360, 157, 124, 69, 79, 69), (397, 157, 124, 69, 79, 70),
    (459, 157, 124, 70, 79, 70), (469, 157, 124, 70, 78, 69),
    (474, 164, 128, 76, 77, 67), (482, 173, 138, 78, 76, 65),
    (490, 173, 141, 80, 75, 63), (509, 174, 143, 93, 66, 54),
    (531, 177, 144, 110, 55, 44), (545, 186, 147, 123, 52, 42),
    (548, 191, 148, 133, 57, 44), (551, 200, 148, 131, 62, 49),
    (560, 212, 148, 126, 70, 56), (568, 216, 148, 127, 74, 59),
    (596, 216, 151, 128, 77, 62), (615, 216, 153, 132, 78, 62),
    (631, 216, 157, 140, 79, 63), (648, 216, 162, 153, 81, 66),
    (655, 217, 164, 161, 82, 68), (669, 218, 165, 163, 83, 69),
    (687, 219, 165, 163, 83, 69), (703, 219, 166, 164, 84, 69),
    (720, 219, 170, 169, 83, 68), (742, 219, 176, 175, 81, 68),
    (764, 219, 181, 180, 78, 66), (778, 216, 184, 183, 74, 64),
    (785, 207, 185, 185, 74, 64), (788, 198, 187, 187, 73, 63),
]
WHEELS = [(360, 201, 34, .360), (440, 201, 34, .360), (694, 203, 32, .343)]

# Central body junction (truck cabin to coupe), redesigned after the traced
# stations produced a roof notch, a staircase sill and a pinched waist. Stations
# strictly inside JUNCTION_PX are authored curves, not drawing traces; every
# station outside (and both bounding rows) keeps the original hand trace.
LEGACY_STATIONS = STATIONS
JUNCTION_PX = (469, 596)


def _ease(t):
    return t*t*(3-2*t)


def _junction_row(px):
    a = next(r for r in LEGACY_STATIONS if r[0] == JUNCTION_PX[0])
    b = next(r for r in LEGACY_STATIONS if r[0] == JUNCTION_PX[1])
    t = (px-JUNCTION_PX[0])/(JUNCTION_PX[1]-JUNCTION_PX[0])
    s = _ease(t)
    # Sill, belt, roof and greenhouse ease with zero slope into both ends. The
    # shoulder half-width stays level (no hourglass), so the flank is continuous.
    return (px, a[1]+(b[1]-a[1])*s, a[2]+(b[2]-a[2])*s, a[3]+(b[3]-a[3])*s,
            a[4]+(b[4]-a[4])*t, a[5]+(b[5]-a[5])*s)


STATIONS = ([r for r in LEGACY_STATIONS if r[0] <= JUNCTION_PX[0]]
            + [_junction_row(px) for px in range(474, 596, 9)]
            + [r for r in LEGACY_STATIONS if r[0] >= JUNCTION_PX[1]])


def in_junction(px):
    return JUNCTION_PX[0] < px < JUNCTION_PX[1]


def point(px, py, z=0):
    return Vector(((px - 527) * SCALE + X_OFFSET,
                   (GROUND_PIXEL - py) * SCALE + GROUND_Y, z))


def top_width(px):
    for a, b in zip(STATIONS, STATIONS[1:]):
        if a[0] <= px <= b[0]:
            t = (px-a[0])/(b[0]-a[0])
            return (a[4] + t*(b[4]-a[4])) * SCALE
    return STATIONS[0 if px < STATIONS[0][0] else -1][4] * SCALE


def profile(px):
    for a, b in zip(STATIONS, STATIONS[1:]):
        if a[0] <= px <= b[0]:
            t = (px-a[0])/(b[0]-a[0])
            return [aa + t*(bb-aa) for aa, bb in zip(a, b)]
    return STATIONS[0 if px < STATIONS[0][0] else -1]


def wheel_radius(end):
    return WHEELS[-1 if end == 'A' else 0][2] * SCALE
