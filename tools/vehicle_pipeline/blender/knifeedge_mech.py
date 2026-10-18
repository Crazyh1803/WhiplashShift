"""Rear-engine drivetrain and suspension (End B, decorative, no physics) plus the cockpit seats.

Engine/transaxle/muffler are `Prop_*` body nodes (not wheels). Shocks, arms, driveshafts and the stub axles
are `Fine_*` hardware; the stub axle is the only part allowed to touch a wheel.
"""
import math

import bmesh
from mathutils import Matrix, Vector

import knifeedge_forms as F
import knifeedge_prims as P
import knifeedge_trace as T

HUB_X = T.WHEEL_X["truck"]
HUB_Y = T.TRACK_Y["truck"]
HUB_Z = T.WHEEL_R["truck"]
UPRIGHT_Y = 0.655


def cyl(builder, name, a, b, r, mat, sides=10, smooth=50):
    return P.sweep(builder, name, [a, b], mat, radius=r, sides=sides)


def spring(builder, name, a, b, radius, wire, turns, mat="steel"):
    a, b = Vector(a), Vector(b)
    axis = (b - a)
    n = axis.normalized()
    u = n.cross(Vector((0, 1, 0)) if abs(n.y) < 0.9 else Vector((1, 0, 0))).normalized()
    v = n.cross(u)
    pts = []
    steps = int(turns * 12)
    for k in range(steps + 1):
        t = k / steps
        ang = math.tau * turns * t
        pts.append(a + axis * t + (u * math.cos(ang) + v * math.sin(ang)) * radius)
    return P.sweep(builder, name, pts, mat, radius=wire, sides=5)


def barrel(builder, name, centre, side, length, mat="steel"):
    """Finned cylinder barrel along Y (outboard = side)."""
    r0, r1 = 0.050, 0.068
    prof = [(0.0, 0.0), (r0, 0.0)]
    n = 6
    for k in range(n):
        y = length * (k + 0.5) / n
        prof += [(r0, y - length / (3 * n)), (r1, y - length / (4 * n)), (r1, y + length / (4 * n)), (r0, y + length / (3 * n))]
    prof += [(r0, length), (0.0, length)]
    prof = [(r, y * side) for r, y in prof]
    return F.revolve(builder, name, prof, [mat], axis=1, center=centre, segments=18)


def engine(builder):
    cx = T.X(437.0)
    base = T.FLOOR_TOP_Z - 0.008  # floor pan top (flat under the engine), sunk 8 mm
    top = base + 0.30
    P.rbox(builder, "Prop_Engine_Block", (0.56, 0.44, 0.30), "iron", bevel=0.012, segments=2, location=(cx, 0, base + 0.15))
    for s in (-1, 1):
        P.rbox(builder, f"Prop_Engine_Head_{s:+d}", (0.50, 0.17, 0.20), "steel", bevel=0.01, segments=2,
               location=(cx, s * 0.30, base + 0.12))
        for k in range(2):
            barrel(builder, f"Prop_Engine_Barrel_{s:+d}_{k}", (cx + (k - 0.5) * 0.24, s * 0.37, base + 0.12), s, 0.14)
        for k in range(6):
            P.rbox(builder, f"Fine_HeadFin_{s:+d}_{k}", (0.50, 0.022, 0.005), "steel", bevel=0.0015,
                   location=(cx, s * (0.226 + 0.006 + k * 0.022), base + 0.215))
        for k in range(6):
            P.sweep(builder, f"Fine_ValveBolt_{s:+d}_{k}", [(cx + (k - 2.5) * 0.085, s * 0.30, base + 0.222),
                                                              (cx + (k - 2.5) * 0.085, s * 0.30, base + 0.236)], "iron",
                    radius=0.011, sides=6)
    P.rbox(builder, "Prop_Transaxle", (0.25, 0.54, 0.30), "iron", bevel=0.012, segments=2,
           location=(T.X(390.0), 0, base + 0.14))
    P.sweep(builder, "Prop_Transaxle_Bell", [(T.X(404.0), 0, base + 0.15), (T.X(417.0), 0, base + 0.15)], "iron",
            radius=0.13, sides=24)
    z_m = top + 0.075 + 0.012
    cyl(builder, "Prop_Exhaust_Muffler", (T.X(447.0), 0, z_m), (T.X(403.0), 0, z_m), 0.075, "steel", sides=24)
    for k, px in enumerate((405.0, 445.0)):
        P.sweep(builder, f"Fine_MufflerBand_{k}", [(T.X(px), 0, z_m), (T.X(px) + 0.02, 0, z_m)], "iron", radius=0.081, sides=24)
    for s in (-1, 1):
        cyl(builder, f"Prop_Exhaust_Header_{s:+d}", (T.X(450.0), s * 0.30, base + 0.24), (T.X(446.0), s * 0.04, z_m - 0.02), 0.020, "steel")
        for k in (0, 1):
            P.rbox(builder, f"Fine_MufflerMount_{s:+d}_{k}", (0.04, 0.03, z_m - 0.075 - top + 0.01), "iron", bevel=0.004,
                   location=(T.X(412.0 + 28.0 * k), s * 0.04, top - 0.005 + (z_m - 0.075 - top + 0.01) / 2))
    route = [(T.X(403.0), 0, z_m), (T.X(392.0), 0, z_m + 0.03), (T.X(370.0), 0, z_m + 0.03), (T.X(345.0), 0, T.Z(149.0)),
             (T.X(296.0), 0, T.Z(149.0))]
    P.sweep(builder, "Prop_Exhaust_Tailpipe", P.rounded_path(route, 0.10, steps=5), "steel", radius=0.034, sides=16)


TOWER_APEX, TOWER_FOOT = T.TOWER_APEX, T.TOWER_FOOT  # shock tower A-frame (see knifeedge_cage.rear)


def tower_leg_point(tag, z):
    """Point on a tower leg centre-line at height z (the legs are the cage tubes the arms bolt to)."""
    ax, ay, ayy = TOWER_APEX
    fx, fy, fyy = TOWER_FOOT[tag]
    t = (T.Z(ay) - z) / (T.Z(ay) - T.Z(fy))
    return Vector((T.X(ax + (fx - ax) * t), ayy + (fyy - ayy) * t, z))


def suspension(builder):
    for s in (-1, 1):
        hub = Vector((HUB_X, s * UPRIGHT_Y, HUB_Z))
        P.rbox(builder, f"Prop_Upright_{s:+d}", (0.08, 0.07, 0.34), "iron", bevel=0.008, location=tuple(hub))
        cyl(builder, f"Fine_Axle_{s:+d}", (HUB_X, s * 0.60, HUB_Z), (HUB_X, s * (HUB_Y + 0.075), HUB_Z), 0.030, "steel",
            sides=12)
        outer_low = Vector((HUB_X, s * UPRIGHT_Y, HUB_Z - 0.12))
        outer_up = Vector((HUB_X, s * UPRIGHT_Y, HUB_Z + 0.12))
        arms = {}
        for dx, tag in ((0.30, "F"), (-0.30, "R")):
            px_in = T.PX(HUB_X + dx)
            floor_edge = T.W(T.lerp_table(T.FLOOR_HALF, px_in)) - 0.03
            low_in = Vector((HUB_X + dx, s * floor_edge, T.FLOOR_TOP_Z - 0.03))
            cyl(builder, f"Fine_ArmLow_{s:+d}{tag}", tuple(low_in), tuple(outer_low), 0.017, "steel", 10)
            leg = tower_leg_point(tag, T.Z(125.0))
            top_in = Vector((leg.x, s * leg.y, leg.z))
            arms[tag] = (top_in, outer_up)
            cyl(builder, f"Fine_ArmUp_{s:+d}{tag}", tuple(top_in), tuple(outer_up), 0.017, "steel", 10)
        shock_top = Vector((T.X(TOWER_APEX[0]), s * 0.47, T.Z(TOWER_APEX[1]) - 0.02))  # on the cross tube, outboard of the legs
        shock_low = arms["R"][0].lerp(arms["R"][1], 0.45)
        cyl(builder, f"Fine_ShockBody_{s:+d}", tuple(shock_top.lerp(shock_low, 0.42)), tuple(shock_low), 0.020, "iron", 12)
        cyl(builder, f"Fine_ShockRod_{s:+d}", tuple(shock_top), tuple(shock_top.lerp(shock_low, 0.45)), 0.010, "steel", 10)
        spring(builder, f"Fine_ShockSpring_{s:+d}", shock_top.lerp(shock_low, 0.08), shock_top.lerp(shock_low, 0.92), 0.034, 0.0055, 7)
        # driveshaft from the transaxle output to the upright
        cyl(builder, f"Fine_Driveshaft_{s:+d}", (T.X(390.0), s * 0.27, T.FLOOR_TOP_Z + 0.10), (HUB_X, s * 0.62, HUB_Z), 0.019, "steel", 10)


def front_hubs(builder):
    """End A hub carriers: upright, stub axle and two lower arms from the arch wall (y 0.60) to each supercar wheel."""
    hx, hy, hz = T.WHEEL_X["coupe"], T.TRACK_Y["coupe"], T.WHEEL_R["coupe"]
    for s in (-1, 1):
        P.rbox(builder, f"Prop_UprightA_{s:+d}", (0.08, 0.07, 0.30), "iron", bevel=0.008, location=(hx, s * 0.66, hz))
        cyl(builder, f"Fine_AxleA_{s:+d}", (hx, s * 0.595, hz), (hx, s * (hy + 0.075), hz), 0.030, "steel", sides=12)
        for dx, tag in ((0.28, "F"), (-0.28, "R")):
            cyl(builder, f"Fine_ArmA_{s:+d}{tag}", (hx + dx, s * 0.595, hz - 0.08), (hx, s * 0.66, hz - 0.10), 0.017, "steel", 10)


def seats(builder):
    """Two bucket seats on the cockpit floor (headrests at side-view x 505..515) and the one steering wheel."""
    floor = 0.52
    x = T.X(522.0)
    for s in (-1, 1):
        y = s * 0.26
        P.rbox(builder, f"Fine_SeatBase_{s:+d}", (0.52, 0.30, 0.13), "paint2", bevel=0.035, segments=3,
               location=(x + 0.12, y, floor + 0.065 - 0.005))
        back = Matrix.Translation((x - 0.10, y, floor + 0.42)) @ Matrix.Rotation(math.radians(-10), 4, "Y")
        P.rbox(builder, f"Fine_SeatBack_{s:+d}", (0.09, 0.28, 0.66), "paint2", bevel=0.035, segments=3, matrix=back)
        for sb in (-1, 1):
            bol = Matrix.Translation((x - 0.07, y + sb * 0.135, floor + 0.38)) @ Matrix.Rotation(math.radians(-10), 4, "Y")
            P.rbox(builder, f"Fine_SeatBolster_{s:+d}{sb:+d}", (0.16, 0.05, 0.52), "iron", bevel=0.02, segments=2, matrix=bol)
        P.rbox(builder, f"Fine_SeatHead_{s:+d}", (0.09, 0.19, 0.17), "iron", bevel=0.03, segments=3,
               location=(x - 0.17, y, floor + 0.80))
    # steering wheel on the -Y seat (end-B elevation shows it right of centre); the only asymmetric part
    sw = (T.X(556.0), -0.26, floor + 0.62)
    col = [(T.X(606.0) + 0.008, sw[1], 0.97), (sw[0] + 0.01, sw[1], sw[2])]  # column ends 8 mm inside the dash wall
    P.sweep(builder, "Fine_SteeringColumn", col, "iron", radius=0.016, sides=10)
    bm = bmesh.new()
    F.torus(bm, 0.095, 0.0135, (0, 0, 0), axis=0, seg=28, rseg=8)
    for ang in (90, 210, 330):  # three spokes from the column boss to the rim
        a = math.radians(ang)
        P.sweep_into(bm, [(0, 0, 0), (0, 0.090 * math.cos(a), 0.090 * math.sin(a))], radius=0.011, sides=8)
    for v in bm.verts:
        v.co = Matrix.Rotation(math.radians(-25), 3, "Y") @ v.co + Vector(sw)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    P.finish(builder, "Fine_SteeringWheel", bm, "iron", smooth_angle=50)
