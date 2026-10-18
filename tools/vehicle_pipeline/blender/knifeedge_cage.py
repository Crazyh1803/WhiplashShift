"""Tubular roll cage, rear spaceframe, tower A-frames, bumper hoop and floor rails (accent colour).

Tubes are swept 8-sided solids grouped into a few Body_Cage* objects; everything is mirrored.
"""
import bmesh

import knifeedge_prims as P
import knifeedge_trace as T

R_MAIN = 0.024
R_SMALL = 0.016
Y_ROOF = T.W(T.ROOF_HALF_PX)
Y_BASE = 0.66


def pt(px, py, y):
    return (T.X(px), y, T.Z(py))


def pz(px, z, y):
    return (T.X(px), y, z)


def tube(bm, pts, r=R_MAIN, round_r=0.05, sides=12):
    path = P.rounded_path(pts, round_r, steps=5) if len(pts) > 2 else pts
    P.sweep_into(bm, path, radius=r, sides=sides)


def both(bm, pts_fn, **kw):
    for s in (-1, 1):
        tube(bm, pts_fn(s), **kw)


def group(builder, name, fn, mat="accent"):
    bm = bmesh.new()
    fn(bm)
    return P.finish(builder, name, bm, mat, smooth_angle=50)


def roof(bm):
    both(bm, lambda s: [pt(562, 66, s * Y_ROOF), pt(455, 66, s * Y_ROOF)], round_r=0.0)           # roof rails
    both(bm, lambda s: [pt(562, 66, s * Y_ROOF), pt(615, T.BASE_PY, s * Y_BASE)], round_r=0.0)  # A pillars
    both(bm, lambda s: [pt(455, 66, s * Y_ROOF), pt(466, T.BASE_PY, s * Y_BASE)], round_r=0.0)  # B pillars
    tube(bm, [pt(562, 66, -Y_ROOF), pt(562, 66, Y_ROOF)], round_r=0.0)                             # windshield header
    tube(bm, [pt(455, 66, -Y_ROOF), pt(455, 66, Y_ROOF)], round_r=0.0)                             # rear header
    tube(bm, [pt(615, T.BASE_PY, -Y_BASE), pt(615, T.BASE_PY, Y_BASE)], round_r=0.0)           # cowl bar
    tube(bm, [pt(455, 66, 0.0), pt(562, 66, 0.0)], r=R_SMALL, round_r=0.0)                         # roof spine rail


def foot_y(px):
    """Lateral position of a lower truss end: on the floor-pan edge line, 20 mm inside the pan."""
    return T.W(T.lerp_table(T.FLOOR_HALF, px)) - 0.02


def rear(bm):
    both(bm, lambda s: [pt(455, 66, s * Y_ROOF), pt(305, 110, s * Y_ROOF)], round_r=0.0)           # slope rails
    for px in (345, 400):
        both(bm, lambda s: [pt(px, T.slope_py(px) + 1.0, s * Y_ROOF), pt(px, 176, s * foot_y(px))], r=R_SMALL, round_r=0.0)
    both(bm, lambda s: [pt(362, 99, s * 0.40), pt(335, 175, s * 0.50)], round_r=0.0)               # shock tower legs
    both(bm, lambda s: [pt(362, 99, s * 0.40), pt(392, 176, s * 0.50)], round_r=0.0)
    tube(bm, [pt(362, 99, -0.47), pt(362, 99, 0.47)], round_r=0.0)                                 # tower cross tube
    tube(bm, [pt(305, 110, -Y_ROOF), pt(305, 110, Y_ROOF)], round_r=0.0)
    # triangulated side truss (end elevations / side view): diagonals between slope rail, floor rail and B pillar
    for a, b_ in (((455, 68), (400, 175)), ((400, 85), (345, 175)), ((345, 101), (318, 172))):
        both(bm, lambda s, a=a, b_=b_: [pt(a[0], a[1], s * Y_ROOF), pt(b_[0], b_[1], s * foot_y(b_[0]))], r=R_SMALL, round_r=0.0)


def bumper(bm):
    hx = 290.0
    half = T.W(51.0)
    z0, z1 = T.Z(159.0), T.Z(108.0)
    loop = [(-half, z0 + 0.05), (-half, z1 - 0.05), (-half + 0.07, z1), (half - 0.07, z1), (half, z1 - 0.05),
            (half, z0 + 0.05), (half - 0.07, z0), (-half + 0.07, z0)]
    P.sweep_into(bm, [(T.X(hx), y, z) for y, z in loop], radius=0.022, sides=12, cyclic=True)
    for s in (-1, 1):
        for z in (z0 + 0.03, z1 - 0.03):
            tube(bm, [(T.X(hx), s * half, z), (T.X(311.0), s * half * 0.93, z)], r=R_SMALL, round_r=0.0)
    # wide lower wing tubes (end elevation: wing tubes spread beyond the plate)
    tube(bm, [(T.X(hx), -half, T.Z(142.0)), (T.X(hx), half, T.Z(142.0))], r=R_SMALL, round_r=0.0)


def floor(bm):
    for s in (-1, 1):
        pts = [pt(px, T.lerp_table(T.FLOOR_BOT, px) - 3.0, s * (T.W(T.lerp_table(T.FLOOR_HALF, px)) - 0.02))
               for px in (318, 360, 400, 440, 452)]
        tube(bm, pts, r=0.026, round_r=0.0)
    tube(bm, [pt(345, 176, -0.56), pt(345, 176, 0.56)], r=R_SMALL, round_r=0.0)
    tube(bm, [pt(400, 177, -0.60), pt(400, 177, 0.60)], r=R_SMALL, round_r=0.0)


def build(builder):
    return [group(builder, "Body_CageRoof", roof), group(builder, "Body_CageRear", rear),
            group(builder, "Body_CageBumper", bumper), group(builder, "Body_CageFloor", floor, mat="iron")]
