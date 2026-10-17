"""Rivets, steam pipes, valves, gauges, axle stubs and leaf springs (the hardware layer)."""
import math

import bmesh
from mathutils import Vector

import boilerfang_body as B
import boilerfang_forms as F
import boilerfang_machinery as M
import boilerfang_prims as P
import boilerfang_trace as T

SIDES = (-1, 1)


def tag(side):
    return f"{side:+d}"


def side_rivets(surf, side, rows, spacing, r):
    """rows = [(px0, px1, z)] -> rivet spots seated on the hull flank by ray casts."""
    spots = []
    for px0, px1, z in rows:
        x0, x1 = T.X(px0), T.X(px1)
        n = max(1, int((x1 - x0) / spacing))
        for i in range(n + 1):
            x = x0 + (x1 - x0) * i / n
            hit = surf.side(x, z, side)
            if hit:
                spots.append((hit[0], hit[1]))
    return spots


def build_rivets(builder, surf):
    out = []
    for side in SIDES:
        s = tag(side)
        spots = side_rivets(surf, side, [(442, 700, 0.612), (442, 700, 0.47)], 0.075, 0.007)
        out.append(F.rivet_set(builder, f"Fine_Rivets_Flank_{s}", spots, 0.0065, "brass"))
        # door perimeter (inset inside the outline)
        door = []
        for z in (0.635, 1.205):
            door += side_rivets(surf, side, [(467, 512, z)], 0.07, 0.006)
        for px in (467, 512):
            x = T.X(px)
            for k in range(7):
                hit = surf.side(x, 0.68 + k * 0.085, side)
                if hit:
                    door.append((hit[0], hit[1]))
        out.append(F.rivet_set(builder, f"Fine_Rivets_Door_{s}", door, 0.0055, "brass"))
        # speedster hood and cockpit rows
        spots = side_rivets(surf, side, [(730, 850, 0.50), (730, 850, 0.36)], 0.07, 0.006)
        out.append(F.rivet_set(builder, f"Fine_Rivets_Hood_{s}", spots, 0.006, "brass"))
    # boiler band rivets around each ring (upper two thirds)
    band = []
    for px in (318, 352, 388, 418):
        ring, _ = B.barrel_ring(px, 0.007)
        zc = (B.BARREL_Z[0] + B.BARREL_Z[1]) / 2
        for i, (y, z) in enumerate(ring):
            if z < zc - 0.05 or i % 2:
                continue
            n = Vector((0.0, y, z - zc))
            if n.length < 1e-6:
                continue
            band.append(((T.X(px), y, z), n))
    out.append(F.rivet_set(builder, "Fine_Rivets_BoilerBands", band, 0.009, "brass"))
    # fender edge rows
    fend = []
    for side in SIDES:
        hub = (T.WHEEL_X["truck"], T.WHEEL_R["truck"])
        r = hub[1] + 0.045 + 0.0075 + 0.008
        for yy in (0.32, 0.64):
            for k in range(2, 33, 2):
                a = math.radians(215 + (-35 - 215) * k / 34)
                fend.append(((hub[0] + r * math.cos(a), side * yy, hub[1] + r * math.sin(a)),
                             (math.cos(a), 0.0, math.sin(a))))
        hub = (T.WHEEL_X["coupe"], T.WHEEL_R["coupe"])
        r = hub[1] + 0.045 + 0.0075 + 0.008
        for yy in (0.38, 0.62):
            for k in range(0, 27, 2):
                a = math.radians(152 + (-28 - 152) * k / 26)
                fend.append(((hub[0] + r * math.cos(a), side * yy, hub[1] + r * math.sin(a)),
                             (math.cos(a), 0.0, math.sin(a))))
    out.append(F.rivet_set(builder, "Fine_Rivets_Fenders", fend, 0.007, "brass"))
    # plow top plate rim
    plow = []
    x0, x1 = T.X(228), T.X(278)
    for side in SIDES:
        for k in range(1, 6):
            x = T.X(250) + (x1 - T.X(250)) * k / 6
            z = 0.12 + (0.54 - 0.12) * (x - x0) / (x1 - x0)
            plow.append(((x, side * 0.575, z + 0.002), (0.0, 0.0, 1.0)))
    out.append(F.rivet_set(builder, "Fine_Rivets_Plow", plow, 0.009, "brass"))
    return out


def wheel_valve(builder, name, pos, mat="brass"):
    x, y, z = pos
    out = [F.revolve(builder, name + "_Stem", [(0.0, -0.03), (0.012, -0.03), (0.016, 0.0), (0.012, 0.05),
                                               (0.0, 0.055)], [mat], axis=2, center=(x, y, z), segments=10)]
    ring = bmesh.new()
    F.torus(ring, 0.034, 0.005, (x, y, z + 0.058), axis=2, seg=16, rseg=5)
    for k in range(4):
        a = k * math.pi / 2
        v0 = ring.verts.new((x, y, z + 0.058))
        v1 = ring.verts.new((x + 0.034 * math.cos(a), y + 0.034 * math.sin(a), z + 0.058))
        v2 = ring.verts.new((x + 0.034 * math.cos(a), y + 0.034 * math.sin(a), z + 0.052))
        v3 = ring.verts.new((x, y, z + 0.052))
        ring.faces.new((v0, v1, v2, v3))
    bmesh.ops.recalc_face_normals(ring, faces=list(ring.faces))
    out.append(P.finish(builder, name + "_Wheel", ring, mat, smooth_angle=60))
    return out


def build_pipes(builder, surf):
    """Steam feed and return pipes run low along the skirt (clear of the doors) to the cylinders."""
    out = []
    for side in SIDES:
        s = tag(side)
        hit = surf.side(T.X(424), 0.70, side)
        y0 = hit[0].y if hit else side * 0.47
        xp = -1.215
        path = [(T.X(424), y0 - side * 0.015, 0.70), (xp, side * 0.665, 0.70), (xp, side * 0.665, 0.150),
                (T.X(556) - 0.02, side * 0.665, 0.150), (T.X(556) - 0.02, side * 0.58, 0.262)]
        out.append(M.pipe(builder, f"Fine_SteamPipe_{s}", path, 0.021, "brass", 0.06, 10))
        path = [(T.X(424), y0 - side * 0.015, 0.62), (xp - 0.04, side * 0.69, 0.62), (xp - 0.04, side * 0.69, 0.115),
                (T.X(530), side * 0.69, 0.115), (T.X(530), side * 0.62, 0.22)]
        out.append(M.pipe(builder, f"Fine_ReturnPipe_{s}", path, 0.014, "copper", 0.05, 8))
        for k, (px, z) in enumerate(((470, 0.15), (505, 0.15), (545, 0.15))):
            out.append(P.rbox(builder, f"Fine_PipeBracket_{s}_{k}", (0.028, 0.050, 0.030), "iron", bevel=0.004,
                              location=(T.X(px), side * 0.665, z - 0.030)))
        out += wheel_valve(builder, f"Fine_SteamValve_{s}", (xp, side * 0.665, 0.46))
        out += wheel_valve(builder, f"Fine_DrainValve_{s}", (T.X(520), side * 0.665, 0.172))
    return out


def build_gauges(builder):
    out = []
    z = B.roof_z(459) + 0.02
    out.append(P.sweep(builder, "Fine_RoofGaugeStem", [(T.X(459), 0.0, z - 0.01), (T.X(459), 0.0, z + 0.13)],
                       "brass", radius=0.012, sides=8))
    out.append(M.gauge_pair(builder, "Fine_RoofGauge", (T.X(459), 0.0, z + 0.17), 0.05))
    # dash gauges on the speedster cowl
    for side in SIDES:
        zc = B.roof_z(748) + 0.020
        out.append(P.sweep(builder, f"Fine_CowlGaugeStem_{tag(side)}", [(T.X(748), side * 0.19, zc - 0.02),
                                                                       (T.X(748), side * 0.19, zc + 0.03)],
                           "brass", radius=0.010, sides=6))
        out.append(M.gauge_pair(builder, f"Fine_CowlGauge_{tag(side)}", (T.X(748), side * 0.19, zc + 0.065), 0.036))
    return out


def build_running_gear(builder):
    out = []
    for side in SIDES:
        s = tag(side)
        out.append(P.sweep(builder, f"Fine_AxleTruck_{s}", [(T.WHEEL_X["truck"], side * 0.30, T.WHEEL_R["truck"]),
                                                          (T.WHEEL_X["truck"], side * 0.57, T.WHEEL_R["truck"])],
                           "iron", radius=0.036, sides=12))
        out.append(P.sweep(builder, f"Fine_AxleSpeedster_{s}", [(T.WHEEL_X["coupe"], side * 0.20, T.WHEEL_R["coupe"]),
                                                              (T.WHEEL_X["coupe"], side * 0.44, T.WHEEL_R["coupe"])],
                           "iron", radius=0.026, sides=10))
        # leaf springs under the fenders, three leaves each
        for end, (hx, hz, yy, half) in (("T", (T.WHEEL_X["truck"], T.WHEEL_R["truck"], 0.46, 0.34)),
                                        ("S", (T.WHEEL_X["coupe"], T.WHEEL_R["coupe"], 0.34, 0.28))):
            for leaf in range(3):
                span = half * (1.0 - 0.22 * leaf)
                pts = []
                for k in range(9):
                    t = -1 + 2 * k / 8
                    pts.append((hx + span * t, side * yy, hz - 0.072 - 0.012 * leaf + 0.028 * (1 - t * t)))
                prof = [(-0.005, -0.028), (0.005, -0.028), (0.005, 0.028), (-0.005, 0.028)]
                out.append(P.sweep(builder, f"Fine_LeafSpring_{end}_{s}_{leaf}", pts, "iron", profile=prof,
                                   up=(0, 1, 0)))
    return out


def build(builder, hull):
    surf = F.Surface([hull])
    out = []
    out += build_rivets(builder, surf)
    out += build_pipes(builder, surf)
    out += build_gauges(builder)
    out += build_running_gear(builder)
    return out
