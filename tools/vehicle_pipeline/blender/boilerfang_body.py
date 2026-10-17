"""Main body masses: hull, boiler barrel, fenders, plows, tanks and cylinders.

Every mass is a closed, mirrored-by-construction solid (loft, sweep or lathe). They overlap like
the cast and riveted parts of a real engine; the combined silhouette is checked against the
traced side/top tables by validate_boilerfang.py.
"""
import math

from mathutils import Matrix, Vector

import boilerfang_forms as F
import boilerfang_prims as P
import boilerfang_trace as T

HULL_MATS = ["paint", "paint2", "accent", "iron"]
HULL_PX = [296, 304, 320, 340, 360, 380, 400, 420, 431.5, 433, 440, 446, 452, 460, 470, 490, 510,
           530, 550, 565, 580, 595, 610, 625, 640, 655, 670, 685, 695, 702, 710, 718, 726, 740,
           760, 780, 800, 820, 840, 852, 862]
CROWN = [(296, 0.03), (431, 0.03), (433, 0.0), (460, 0.0), (470, 0.05), (560, 0.05), (600, 0.03),
         (640, 0.02), (695, 0.02), (702, 0.0), (725, 0.0), (735, 0.03), (862, 0.03)]
ARCH_STEPS = {"truck": 22, "coupe": 18}
BARREL_Z = (0.60, 1.06)
DECK_Z = 0.62
CAB_PX = 432.2


def hull_top(px):
    """Flat-part top of the hull; the crown lifts the centreline to the traced silhouette."""
    return DECK_Z if px < CAB_PX else T.top_z(px) - T.lerp_table(CROWN, px)


def hull_ring(px):
    w = T.half_w(px)
    zb, zt = T.sill_z(px), hull_top(px)
    crown = T.lerp_table(CROWN, px)
    split = zb + 0.16 if px < 432 else 0.50
    half, roles = F.section_half(w, zb, zt, 0.05, 0.09 if CAB_PX < px < 640 else 0.06, crown,
                                 split=split)
    return F.full_ring(half, roles)


def build_hull(builder):
    stations, roles = [], None
    for px in HULL_PX:
        ring, roles = hull_ring(px)
        stations.append((T.X(px), ring))
    return F.loft(builder, "Body_Hull", stations, HULL_MATS, row_mats=roles)


def barrel_ring(px, grow=0.0):
    w = T.half_w(px) + grow
    half, roles = F.section_half(w, BARREL_Z[0] - grow, BARREL_Z[1] + grow, 0.19, 0.19, 0.0,
                                 steps=5, crown_steps=2)
    return F.full_ring(half, roles)


def build_barrel(builder):
    """Copper boiler barrel on the truck deck with riveted brass bands."""
    stations = []
    for px in (296, 310, 340, 370, 400, 431.9):
        ring, roles = barrel_ring(px)
        stations.append((T.X(px), ring))
    n = len(stations[0][1])
    barrel = F.loft(builder, "Body_BoilerBarrel", stations, ["copper"], row_mats=[0] * n)
    bands = []
    for k, px in enumerate((318, 352, 388, 418)):
        a, b = T.X(px - 3), T.X(px + 3)
        ra, _ = barrel_ring(px - 3, 0.007)
        rb_, _ = barrel_ring(px + 3, 0.007)
        bands.append(F.loft(builder, f"Trim_BoilerBand_{k}", [(a, ra), (b, rb_)], ["brass"],
                            row_mats=[0] * len(ra), smooth_angle=60))
    return barrel, bands


def arch_path(hub, radius, a0, a1, steps):
    pts = []
    for k in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * k / steps)
        pts.append((hub[0] + radius * math.cos(a), hub[1] + radius * math.sin(a)))
    return pts


def build_fenders(builder):
    """Mudguards over the wheels: truck arches over the knobby tyres, speedster pontoons."""
    out = []
    for side in (-1, 1):
        sgn = "+" if side > 0 else "-"
        hub = (T.WHEEL_X["truck"], T.WHEEL_R["truck"])
        r = hub[1] + 0.045 + 0.0075
        path = arch_path(hub, r, 215, -35, ARCH_STEPS["truck"])
        o = F.sweep_band(builder, f"Body_FenderTruck_{sgn}", path, 0.30 if side > 0 else -0.66,
                         0.66 if side > 0 else -0.30, 0.022, "paint")
        out.append(o)
        for k, yy in enumerate((0.30, 0.66)):
            out.append(P.sweep(builder, f"Trim_FenderBeadTruck_{sgn}_{k}", [(x, side * yy, z) for x, z in path],
                               "brass", radius=0.0085, sides=6))
        # speedster pontoon: running board, rise over the arch, nose drop
        hub = (T.WHEEL_X["coupe"], T.WHEEL_R["coupe"])
        r = hub[1] + 0.045 + 0.0075
        arc = arch_path(hub, r, 152, -28, ARCH_STEPS["coupe"])
        rear = [(T.X(696), 0.115), (1.12, 0.115), (1.30, 0.22)]
        path = rear + arc
        o = F.sweep_band(builder, f"Body_FenderSpeedster_{sgn}", path, 0.36 if side > 0 else -0.64,
                         0.64 if side > 0 else -0.36, 0.022, "paint")
        out.append(o)
        for k, yy in enumerate((0.36, 0.64)):
            out.append(P.sweep(builder, f"Trim_FenderBeadSpeedster_{sgn}_{k}", [(x, side * yy, z) for x, z in path],
                               "brass", radius=0.0085, sides=6))
    return out


def wedge(builder, name, plan, z_bottom, z_top_fn, mat, bevel=0.006):
    """Closed prism over a plan polygon (x, y) with a sloping top z_top_fn(x, y)."""
    import bmesh
    bm = bmesh.new()
    low = [bm.verts.new((x, y, z_bottom)) for x, y in plan]
    high = [bm.verts.new((x, y, z_top_fn(x, y))) for x, y in plan]
    n = len(plan)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((low[i], low[j], high[j], high[i]))
    bm.faces.new(list(reversed(low)))
    bm.faces.new(high)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    P.bevel_edges(bm, bevel, 1)
    return P.finish(builder, name, bm, mat)


def build_plows(builder):
    """Truck cowcatcher plow (End B) and the speedster's pointed prow (End A)."""
    out = []
    x0, x1 = T.X(228), T.X(278)
    z0, z1 = 0.12, 0.54
    plan = [(x0, 0.0), (T.X(250), 0.60), (x1, 0.60), (x1 + 0.07, 0.42), (x1 + 0.07, -0.42),
            (x1, -0.60), (T.X(250), -0.60)]
    plan = [(x0, 0.0), (T.X(250), 0.60), (x1, 0.60), (x1 + 0.07, 0.42), (x1 + 0.07, -0.42),
            (x1, -0.60), (T.X(250), -0.60)]

    def top(x, y):
        return z0 + (z1 - z0) * min(1.0, max(0.0, (x - x0) / (x1 - x0)))
    out.append(wedge(builder, "Body_PlowTruck", plan, z0 - 0.025, top, "iron"))
    # speedster prow: a long pointed wedge that falls to the ground line
    stations = []
    for px, w, zt in ((866, 0.18, 0.60), (874, 0.16, 0.52), (884, 0.14, 0.44), (896, 0.10, 0.30),
                      (908, 0.06, 0.18), (918, 0.025, 0.13), (925, 0.004, 0.10)):
        half, roles = F.section_half(w, 0.085, zt, 0.015, 0.03, 0.01, steps=2, crown_steps=2)
        stations.append((T.X(px), F.full_ring(half, roles)[0]))
    out.append(F.loft(builder, "Body_ProwSpeedster", stations, ["paint2"],
                      row_mats=[0] * len(stations[0][1])))
    return out


def side_y(px):
    """Hull half-width at an arbitrary px (linear between hull stations, as the loft is)."""
    return T.lerp_table([(p, T.half_w(p)) for p in HULL_PX], px)


def roof_z(px):
    """Hull top height (flat part, before crown) at an arbitrary px."""
    return T.lerp_table([(p, hull_top(p)) for p in HULL_PX], px)


def top_surface_z(px, y):
    """Exact hull top height at (px, |y|), interpolated on the lofted rings (flat or crowned)."""
    i = max(1, min(len(HULL_PX) - 1, next((k for k, p in enumerate(HULL_PX) if p >= px), len(HULL_PX) - 1)))
    p0, p1 = HULL_PX[i - 1], HULL_PX[i]
    t = (px - p0) / (p1 - p0)
    zs = []
    for p in (p0, p1):
        ring, _ = hull_ring(p)
        half = [(yy, zz) for yy, zz in ring if yy >= -1e-9 and zz > ring[0][1] + 0.1]
        half.sort()
        a = abs(y)
        z = half[-1][1]
        for (ya, za), (yb, zb) in zip(half, half[1:]):
            if ya <= a <= yb and yb > ya:
                z = za + (zb - za) * (a - ya) / (yb - ya)
                break
        zs.append(z)
    return zs[0] + (zs[1] - zs[0]) * t
