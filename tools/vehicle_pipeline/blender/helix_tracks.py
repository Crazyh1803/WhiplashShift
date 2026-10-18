"""Body-mounted tracked bogies (Prop_Track_*): belts with cleats, sprockets, rollers, bogie frame.

The sheet shows tracks under the heavy End B. These are decorative body nodes; the vehicle's four
physical wheels are hidden by the game adapter, nothing here is named Wheel_*.
"""
import math

import bmesh
from mathutils import Matrix, Vector

import helix_core as C
import helix_prims as P
import helix_trace as T
from helix_body import SIDES, SN

R_OUT = T.TRACK_R_PX * T.SCALE           # cleat tip radius = 0.168 (loop bottom touches z=0)
BELT_OUT, BELT_IN = R_OUT - 0.012, R_OUT - 0.045
ZC = R_OUT                                # sprocket axle height
X1, X2 = T.X(T.TRACK_PX_X[0]), T.X(T.TRACK_PX_X[1])
ROLLER_Z = ZC - BELT_IN + 0.030 + 0.010  # roller axle: 10 mm clear of the belt's inner surface
CLEATS = 62
ARC = 16


def stadium_points(r, n_arc=ARC):
    """Closed stadium loop in (x, z) with outward unit normals, starting at the bottom-rear."""
    pts = [((X1, ZC - r), (0, -1)), ((X2, ZC - r), (0, -1))]
    for k in range(1, n_arc):
        a = -math.pi / 2 + math.pi * k / n_arc
        pts.append(((X2 + r * math.cos(a), ZC + r * math.sin(a)), (math.cos(a), math.sin(a))))
    pts += [((X2, ZC + r), (0, 1)), ((X1, ZC + r), (0, 1))]
    for k in range(1, n_arc):
        a = math.pi / 2 + math.pi * k / n_arc
        pts.append(((X1 + r * math.cos(a), ZC + r * math.sin(a)), (math.cos(a), math.sin(a))))
    return pts


def at_arclength(r, s):
    """Point/outward normal at arclength s on the stadium of radius r."""
    L = X2 - X1
    per = 2 * L + 2 * math.pi * r
    s %= per
    if s < L:
        return (X1 + s, ZC - r), (0, -1)
    s -= L
    if s < math.pi * r:
        a = -math.pi / 2 + s / r
        return (X2 + r * math.cos(a), ZC + r * math.sin(a)), (math.cos(a), math.sin(a))
    s -= math.pi * r
    if s < L:
        return (X2 - s, ZC + r), (0, 1)
    s -= L
    a = math.pi / 2 + s / r
    return (X1 + r * math.cos(a), ZC + r * math.sin(a)), (math.cos(a), math.sin(a))


def _belt(builder, name, y, mat):
    half = T.TRACK_W / 2 - 0.006
    bm = bmesh.new()
    loops = []
    for r in (BELT_OUT, BELT_IN):
        pts = stadium_points(r)
        for yy in (y - half, y + half):
            loops.append([bm.verts.new((p[0], yy, p[1])) for p, _ in pts])
    n = len(loops[0])
    # loops: 0 outer-low, 1 outer-high, 2 inner-low, 3 inner-high
    for a, b in ((0, 1), (1, 3), (3, 2), (2, 0)):
        for k in range(n):
            bm.faces.new((loops[a][k], loops[a][(k + 1) % n], loops[b][(k + 1) % n], loops[b][k]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return P.finish(builder, name, bm, mat, smooth_angle=60)


def _cleats(builder, name, y):
    bm = bmesh.new()
    r = R_OUT - 0.006  # cleat centre radius; spacing uses this loop's own perimeter
    per = 2 * (X2 - X1) + 2 * math.pi * r
    for i in range(CLEATS):
        (px, pz), (nx, nz) = at_arclength(r, per * i / CLEATS)
        n = Vector((nx, 0, nz))
        t = Vector((nz, 0, -nx))
        rot = Matrix(((t.x, 0, n.x), (0, 1, 0), (t.z, 0, n.z)))
        P.bm_box(bm, (px, y, pz), (0.040, T.TRACK_W - 0.02, 0.012), rot)
        if i % 2 == 0:  # centre guide horn standing on the inside of the belt
            P.bm_box(bm, (px - nx * 0.034, y, pz - nz * 0.034), (0.026, 0.040, 0.024), rot)
    return P.bm_object(builder, name, bm, "hardware")


def _sprocket(builder, name, x, y):
    bm = bmesh.new()
    P.bm_cyl(bm, (x, y, ZC), (0, 1, 0), 0.095, 0.24, sides=24)
    P.bm_cyl(bm, (x, y, ZC), (0, 1, 0), 0.062, T.TRACK_W + 0.04, sides=16)
    for k in range(14):
        a = math.tau * k / 14
        rot = Matrix.Rotation(-a, 3, "Y")
        P.bm_box(bm, (x + 0.100 * math.cos(a), y, ZC + 0.100 * math.sin(a)), (0.030, 0.20, 0.034), rot)
    for k in range(8):  # hub bolts on the outer and inner faces
        a = math.tau * k / 8
        for sgn in (-1, 1):
            P.bm_cyl(bm, (x + 0.042 * math.cos(a), y + sgn * (T.TRACK_W / 2 + 0.024), ZC + 0.042 * math.sin(a)),
                     (0, 1, 0), 0.008, 0.014, sides=6)
    return P.bm_object(builder, name, bm, "hardware")


def build_tracks(builder):
    for s in SIDES:
        y = s * T.TRACK_Y
        tag = SN[s]
        _belt(builder, f"Prop_Track_Belt_{tag}", y, "rubber")
        _cleats(builder, f"Prop_Track_Cleats_{tag}", y)
        _sprocket(builder, f"Prop_Track_SprocketRear_{tag}", X1, y)
        _sprocket(builder, f"Prop_Track_SprocketFront_{tag}", X2, y)
        bm = bmesh.new()
        for px in T.ROLLER_PX_X:
            P.bm_cyl(bm, (T.X(px), y, ROLLER_Z), (0, 1, 0), 0.030, 0.22, sides=16)
            P.bm_cyl(bm, (T.X(px), y, ROLLER_Z), (0, 1, 0), 0.018, 0.30, sides=8)
        P.bm_object(builder, f"Prop_Track_Rollers_{tag}", bm, "hardware")
        # bogie frame: pivots, swing arms and the inner frame bar tying the roller axles
        bm = bmesh.new()
        zr = ROLLER_Z
        yi = y - s * (T.TRACK_W / 2 + 0.02)
        for px in T.ROLLER_PX_X:
            P.bm_box(bm, (T.X(px), yi, zr), (0.032, 0.020, 0.032))
        P.bm_box(bm, (T.X(T.ROLLER_PX_X[1]), yi, zr + 0.002), (T.X(T.ROLLER_PX_X[2]) - T.X(T.ROLLER_PX_X[0]) + 0.04, 0.020, 0.026))
        for px in T.PIVOT_PX_X:
            pz = T.Z(240)
            P.bm_cyl(bm, (T.X(px), y - s * 0.02, pz), (0, 1, 0), 0.040, 0.26, sides=14)
            P.bm_cyl(bm, (T.X(px), yi, pz), (0, 1, 0), 0.050, 0.018, sides=14)
        for px_p, px_r in ((T.PIVOT_PX_X[0], T.ROLLER_PX_X[0]), (T.PIVOT_PX_X[1], T.ROLLER_PX_X[2])):
            a = Vector((T.X(px_p), yi, T.Z(240)))
            b = Vector((T.X(px_r), yi, zr))
            d = b - a
            rot = P.frame(d)
            P.bm_box(bm, (a + b) / 2, (0.030, 0.018, d.length), rot.to_3x3())
        P.bm_object(builder, f"Prop_Track_Bogie_{tag}", bm, "hardware")
