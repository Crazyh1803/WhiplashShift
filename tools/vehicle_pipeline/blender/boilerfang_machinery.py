"""Boiler fittings, stack, lamps, plow frame, speedster nose hardware and the central mid-drive.

The central flywheel / belt drive is body-mounted decorative machinery (Prop_MidDrive_* /
Gear_MidDrive_*), mirrored as a pair; it never uses the Wheel_ prefix and has no physics role.
"""
import math

import bmesh
from mathutils import Matrix, Vector

import boilerfang_body as B
import boilerfang_forms as F
import boilerfang_prims as P
import boilerfang_trace as T

SIDES = (-1, 1)


def tag(side):
    return f"{side:+d}"


def rod(builder, name, p0, p1, r, mat, sides=8):
    return P.sweep(builder, name, [p0, p1], mat, radius=r, sides=sides)


def pipe(builder, name, pts, r, mat, bend=0.05, sides=8):
    return P.sweep(builder, name, P.rounded_path(pts, bend, 6), mat, radius=r, sides=sides)


def gauge_pair(builder, name, pos, r=0.05):
    """A double-faced gauge: dial on both flanks of a brass drum."""
    s = r / 0.05
    x, y, z = pos
    profile = [(0.0, 0.0155 * s), (0.034 * s, 0.0155 * s), (0.034 * s, 0.014 * s),
               (0.044 * s, 0.013 * s), (0.050 * s, 0.008 * s), (0.050 * s, -0.008 * s),
               (0.044 * s, -0.013 * s), (0.034 * s, -0.014 * s), (0.034 * s, -0.0155 * s),
               (0.0, -0.0155 * s)]
    obj = F.revolve(builder, name, profile, ["brass", "dial"], axis=1, center=pos, segments=20,
                    face_mats=[1, 0, 0, 0, 0, 0, 0, 0, 1])
    return obj


def build_smokebox(builder):
    out = []
    xf = T.X(296)
    zc = (B.BARREL_Z[0] + B.BARREL_Z[1]) / 2
    out.append(F.revolve(builder, "Fine_SmokeboxDoor", [
        (0.0, -0.002), (0.17, -0.002), (0.19, -0.010), (0.198, -0.020), (0.176, -0.024),
        (0.07, -0.024), (0.052, -0.040), (0.0, -0.046)], ["iron"], axis=0, center=(xf, 0, zc), segments=32))
    ring = bmesh.new()
    F.torus(ring, 0.188, 0.012, (xf - 0.016, 0, zc), axis=0, seg=32, rseg=6)
    bmesh.ops.recalc_face_normals(ring, faces=list(ring.faces))
    out.append(P.finish(builder, "Fine_SmokeboxRing", ring, "brass", smooth_angle=60))
    # cross handle on the door
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        out.append(rod(builder, f"Fine_SmokeboxHandle_{k}",
                       (xf - 0.040, 0.0, zc), (xf - 0.040, 0.075 * math.cos(a), zc + 0.075 * math.sin(a)),
                       0.008, "brass", 6))
    # hinge straps
    for k, dz in enumerate((-0.10, 0.10)):
        out.append(P.rbox(builder, f"Fine_SmokeboxHinge_{k}", (0.016, 0.20, 0.030), "iron", bevel=0.004,
                          location=(xf - 0.016, 0.0, zc + dz)))
    return out


def build_dome_and_stack(builder):
    out = []
    # steam dome with riser and double-faced gauge
    px = 358
    x = T.X(px)
    zt = 1.04
    out.append(F.revolve(builder, "Body_SteamDome", [
        (0.0, zt - 0.05), (0.098, zt - 0.05), (0.098, zt + 0.045), (0.092, zt + 0.075),
        (0.070, zt + 0.108), (0.040, zt + 0.124), (0.0, zt + 0.128)], ["brass"], axis=2,
        center=(x, 0, 0), segments=28))
    out.append(F.revolve(builder, "Fine_DomeRiser", [
        (0.0, zt + 0.12), (0.016, zt + 0.12), (0.016, zt + 0.19), (0.0, zt + 0.19)], ["brass"], axis=2,
        center=(x, 0, 0), segments=10))
    out.append(gauge_pair(builder, "Fine_DomeGauge", (x, 0.0, T.Z(103)), 0.052))
    # safety-valve bonnet on the dome
    out.append(F.revolve(builder, "Fine_SafetyValve", [
        (0.0, zt - 0.03), (0.022, zt - 0.03), (0.022, zt + 0.03), (0.014, zt + 0.05),
        (0.014, zt + 0.09), (0.026, zt + 0.105), (0.0, zt + 0.115)], ["brass"], axis=2,
        center=(x - 0.12, 0, 0), segments=12))
    # smokestack
    sx = T.X(402)
    out.append(F.revolve(builder, "Body_Smokestack", [
        (0.0, 0.98), (0.118, 0.98), (0.118, 1.090), (0.098, 1.112), (0.080, 1.170), (0.074, 1.250),
        (0.073, 1.380), (0.082, 1.450), (0.096, 1.482), (0.108, 1.500), (0.108, 1.512),
        (0.082, 1.512), (0.074, 1.496), (0.0, 1.470)], ["iron", "brass"], axis=2,
        center=(sx, 0, 0), segments=24, face_mats=[1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
    ring = bmesh.new()
    F.torus(ring, 0.082, 0.009, (sx, 0, 1.30), axis=2, seg=28, rseg=6)
    bmesh.ops.recalc_face_normals(ring, faces=list(ring.faces))
    out.append(P.finish(builder, "Fine_StackBand", ring, "brass", smooth_angle=60))
    # filler cap on the barrel nose
    out.append(F.revolve(builder, "Fine_FillerCap", [
        (0.0, 1.03), (0.040, 1.03), (0.040, 1.075), (0.030, 1.10), (0.0, 1.108)], ["brass"], axis=2,
        center=(T.X(308), 0, 0), segments=18))
    return out


def lamp_barrel(builder, name, center, r, depth, front=-1):
    """Brass headlamp can along X with an emissive lens at the front (front = -1 faces -X)."""
    x, y, z = center
    d = depth * front
    out = F.revolve(builder, name, [
        (0.0, 0.0), (r * 0.85, 0.0), (r, -d * 0.1), (r, -d * 0.9), (r * 0.96, -d), (r * 0.80, -d),
        (r * 0.80, -d * 0.97), (0.0, -d * 0.955)], ["brass"], axis=0, center=center, segments=18)
    lens = F.revolve(builder, name + "_Lens", [
        (0.0, -d * 0.96), (r * 0.78, -d * 0.972), (r * 0.78, -d * 0.985), (0.0, -d * 0.985)], ["lamp"],
        axis=0, center=center, segments=18)
    return [out, lens]


def build_truck_lamps(builder):
    out = []
    # twin brass headlamps on arms: top view x 295..315 (centre dy +/-55 px), side z 0.86
    for side in SIDES:
        y = side * 55 * T.SCALE
        x0 = T.X(315)
        out += lamp_barrel(builder, f"Fine_TruckLamp_{tag(side)}", (x0, y, 0.86), 0.092, 0.14, front=-1)
        out.append(rod(builder, f"Fine_TruckLampArm_{tag(side)}", (T.X(318), y * 0.45, 0.80),
                       (T.X(318), y, 0.80), 0.015, "iron", 6))
        out.append(rod(builder, f"Fine_TruckLampStem_{tag(side)}", (T.X(322), y, 0.80),
                       (T.X(322), y, 0.62), 0.014, "iron", 6))
    return out


def build_push_frame(builder):
    out = []
    xp = T.X(283)
    for side in SIDES:
        out.append(rod(builder, f"Fine_PushPost_{tag(side)}", (xp, side * 0.27, 0.40), (xp, side * 0.27, 0.92),
                       0.024, "iron", 8))
        out.append(rod(builder, f"Fine_PushBrace_{tag(side)}", (xp, side * 0.27, 0.86),
                       (T.X(296) + 0.01, side * 0.20, 0.74), 0.014, "iron", 6))
        out.append(F.revolve(builder, f"Fine_PushCap_{tag(side)}", [
            (0.0, 0.92), (0.034, 0.92), (0.034, 0.945), (0.020, 0.965), (0.0, 0.97)], ["brass"], axis=2,
            center=(xp, side * 0.27, 0), segments=14))
    out.append(rod(builder, "Fine_PushBar", (xp, -0.27, 0.90), (xp, 0.27, 0.90), 0.022, "iron", 8))
    # cowcatcher slats on the sloped plow face
    x0, x1 = T.X(228), T.X(278)
    z0, z1 = 0.12, 0.54
    for k in range(-3, 4):
        y = k * 0.17
        xa = x0 + (0.0 if k == 0 else (abs(y) / 0.60) * (T.X(250) - x0))
        xa = max(xa, x0 + 0.012) + 0.02
        za = z0 + (z1 - z0) * (xa - x0) / (x1 - x0)
        out.append(rod(builder, f"Fine_PlowSlat_{k + 3}", (xa, y, za + 0.016), (x1 + 0.02, y, z1 + 0.016), 0.014,
                       "brass" if k % 2 == 0 else "iron", 6))
    return out


def build_speedster_front(builder):
    out = []
    # shield-shaped radiator grille with vertical slats, standing across the nose
    x0 = T.X(864)
    poly = [(-0.20, 0.60), (-0.12, 0.66), (0.0, 0.70), (0.12, 0.66), (0.20, 0.60), (0.18, 0.40),
            (0.10, 0.22), (0.0, 0.14), (-0.10, 0.22), (-0.18, 0.40)]
    bm = bmesh.new()
    front = [bm.verts.new((x0 + 0.016, y, z)) for y, z in poly]
    back = [bm.verts.new((x0 - 0.016, y, z)) for y, z in poly]
    n = len(poly)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((back[i], back[j], front[j], front[i]))
    bm.faces.new(list(reversed(back)))
    bm.faces.new(front)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    P.bevel_edges(bm, 0.004, 1)
    out.append(P.finish(builder, "Fine_GrilleShield", bm, "brass"))
    out.append(F.revolve(builder, "Fine_GrilleBoss", [
        (0.0, 0.0), (0.040, 0.0), (0.040, 0.008), (0.028, 0.016), (0.0, 0.020)], ["copper"], axis=0,
        center=(x0 + 0.014, 0.0, 0.625), segments=20))
    # twin slotted headlamps on each pontoon nose
    for side in SIDES:
        out += lamp_barrel(builder, f"Fine_SpeedsterLamp_{tag(side)}", (T.X(848), side * 0.27, 0.44), 0.082,
                           0.11, front=1)
        out.append(rod(builder, f"Fine_SpeedsterLampStem_{tag(side)}", (T.X(850), side * 0.27, 0.44),
                       (T.X(850), side * 0.27, 0.34), 0.016, "iron", 6))
    return out


def build_speedster_hardware(builder):
    out = []
    # three side exhaust pipes per flank (px 720..776), swept slightly outward at the tail
    for side in SIDES:
        for k, z in enumerate((0.35, 0.41, 0.47)):
            y = side * (0.405 + 0.008 * k)
            path = [(T.X(720) - 0.05, side * (0.435 + 0.01 * k), z - 0.02), (T.X(728), y, z),
                    (T.X(776), y, z)]
            out.append(pipe(builder, f"Fine_SideExhaust_{tag(side)}_{k}", path, 0.027, "brass", 0.03, 10))
        out.append(P.rbox(builder, f"Fine_ExhaustClamp_{tag(side)}", (0.03, 0.044, 0.19), "iron", bevel=0.006,
                          location=(T.X(760), side * 0.42, 0.41)))
        out.append(P.rbox(builder, f"Fine_ExhaustClampB_{tag(side)}", (0.03, 0.044, 0.19), "iron", bevel=0.006,
                          location=(T.X(738), side * 0.42, 0.41)))
    # twin mushroom vents on the cockpit roof (front elevation A: two domes either side of centre)
    px = 668
    for side in SIDES:
        y = side * 0.16
        z0 = B.top_surface_z(px, 0.16)
        out.append(F.revolve(builder, f"Fine_RoofVent_{tag(side)}", [
            (0.0, z0 - 0.012), (0.028, z0 - 0.012), (0.028, z0 + 0.05), (0.075, z0 + 0.058),
            (0.082, z0 + 0.074), (0.062, z0 + 0.096), (0.0, z0 + 0.104)], ["brass"], axis=2,
            center=(T.X(px), y, 0), segments=20))
    return out


def build_cab_hardware(builder):
    out = []
    # twin roof lamps and a whistle on the cab roof
    z = B.top_surface_z(468, 0.30) + 0.012
    for side in SIDES:
        out += lamp_barrel(builder, f"Fine_RoofLamp_{tag(side)}", (T.X(468) + 0.035, side * 0.30, z + 0.06), 0.045, 0.07,
                           front=-1)
        out.append(rod(builder, f"Fine_RoofLampStem_{tag(side)}", (T.X(468), side * 0.30, z - 0.016),
                       (T.X(468), side * 0.30, z + 0.06), 0.014, "iron", 6))
    zw = B.top_surface_z(574, 0.0) + 0.05
    out.append(F.revolve(builder, "Fine_Whistle", [
        (0.0, zw - 0.06), (0.020, zw - 0.06), (0.020, zw + 0.02), (0.034, zw + 0.05), (0.034, zw + 0.16),
        (0.0, zw + 0.165)], ["brass"], axis=2, center=(T.X(574), 0.0, 0), segments=14))
    return out


def tank_and_cylinder(builder):
    """Water tanks (cream, brass banded) and steam cylinders on both flanks of the cab."""
    out = []
    zc, yc = 0.35, 0.56
    x0, x1 = T.X(425), T.X(520)
    for side in SIDES:
        c = (0.0, side * yc, zc)
        r = 0.115
        out.append(F.revolve(builder, f"Body_SideTank_{tag(side)}", [
            (0.0, x0), (0.06, x0 + 0.012), (0.10, x0 + 0.032), (r, x0 + 0.06), (r, x1 - 0.06),
            (0.10, x1 - 0.032), (0.06, x1 - 0.012), (0.0, x1)], ["paint2"], axis=0, center=c, segments=28))
        bands = bmesh.new()
        for px in (440, 472, 505):
            F.torus(bands, r + 0.004, 0.0075, (T.X(px), side * yc, zc), axis=0, seg=24, rseg=4)
        bmesh.ops.recalc_face_normals(bands, faces=list(bands.faces))
        out.append(P.finish(builder, f"Trim_TankBands_{tag(side)}", bands, "brass", smooth_angle=60))
        spots = []
        for px in (448, 480, 512):
            for k in range(11):
                a = math.radians(-30 + 240 * k / 10)
                spots.append(((T.X(px), side * yc + r * math.cos(a) * 1.0, zc + r * math.sin(a)),
                              (0.0, math.cos(a), math.sin(a))))
        out.append(F.rivet_set(builder, f"Fine_Rivets_Tank_{tag(side)}", spots, 0.0065, "brass"))
        # steam cylinder aft of the tank, with copper heads, steam chest and piston rod to the pulley
        xa, xb = T.X(527), T.X(572)
        rc = 0.088
        out.append(F.revolve(builder, f"Body_SteamCylinder_{tag(side)}", [
            (0.0, xa), (0.07, xa + 0.004), (rc, xa + 0.02), (rc, xb - 0.02), (0.07, xb - 0.004), (0.0, xb)],
            ["brass"], axis=0, center=(0, side * yc, zc), segments=24))
        out.append(P.rbox(builder, f"Fine_SteamChest_{tag(side)}", (0.15, 0.09, 0.07), "copper", bevel=0.012,
                          location=(0.5 * (xa + xb), side * yc, zc + rc + 0.025)))
        out.append(rod(builder, f"Fine_PistonRod_{tag(side)}", (xb, side * yc, zc), (T.X(583) - 0.03, side * yc, zc),
                       0.014, "iron", 8))
    return out


def build_mid_drive(builder):
    """Body-mounted flywheel + pulley + belt + guard on both flanks (decorative, not wheels)."""
    out = []
    fx, fz, fr = T.X(T.FLY_PX[0]), T.Z(T.FLY_PX[1]), T.FLY_PX[2] * T.SCALE
    px_, pz, pr = T.X(T.PULLEY_PX[0]), T.Z(T.PULLEY_PX[1]), T.PULLEY_PX[2] * T.SCALE
    for side in SIDES:
        y = side * T.FLY_Y
        loc = (fx, y, fz)
        bm = bmesh.new()

        def piece(index, fn):
            before = set(bm.faces)
            fn()
            for f in bm.faces:
                if f not in before:
                    f.material_index = index
        hw = 0.040
        # rim: flanged iron tyre with a belt groove
        rim = [(fr - 0.020, -hw), (fr, -hw * 0.9), (fr, -hw * 0.28), (fr - 0.012, -hw * 0.2),
               (fr - 0.012, hw * 0.2), (fr, hw * 0.28), (fr, hw * 0.9), (fr - 0.020, hw), (fr - 0.034, hw * 0.6),
               (fr - 0.034, -hw * 0.6)]
        bm2 = bm
        rings = P.lathe(bm2, rim, 40)
        m = len(rim)
        for s_ in range(40):
            a_, b_ = rings[s_], rings[(s_ + 1) % 40]
            bm2.faces.new((a_[m - 1], a_[0], b_[0], b_[m - 1]))
        # hub boss and brass cap
        piece(0, lambda: P.lathe(bm, [(0.0, -0.050 * side), (0.046, -0.050 * side), (0.052, -0.030 * side),
                                     (0.052, 0.040 * side), (0.0, 0.040 * side)], 22))
        piece(1, lambda: P.lathe(bm, [(0.0, 0.070 * side), (0.020, 0.066 * side), (0.034, 0.048 * side),
                                      (0.036, 0.040 * side), (0.0, 0.040 * side)], 20))
        # six spokes: tapered bars bolted into rim and boss
        for k in range(6):
            a = math.tau * k / 6
            r0, r1 = 0.045, fr - 0.030
            poly = [(r0, -0.016), (r1, -0.011), (r1, 0.011), (r0, 0.016)]
            top, bot = [], []
            for r, w_ in poly:
                x, z = r * math.cos(a) - w_ * math.sin(a), r * math.sin(a) + w_ * math.cos(a)
                top.append(bm.verts.new((x, 0.018, z)))
                bot.append(bm.verts.new((x, -0.018, z)))
            for i in range(4):
                j = (i + 1) % 4
                bm.faces.new((bot[i], bot[j], top[j], top[i]))
            bm.faces.new(list(reversed(bot)))
            bm.faces.new(top)
        # crank pin and counterweight on the outer face
        a = math.radians(40)
        pin = bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=0.014, radius2=0.012, depth=0.05)
        for v in pin["verts"]:
            x, yy, z = v.co
            v.co = Vector(((fr - 0.060) * math.cos(a) + x, side * (0.035 + z + 0.025), (fr - 0.060) * math.sin(a) + yy))
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        for f in bm.faces:
            if f.material_index == 0:
                pass
        out.append(P.finish(builder, f"Prop_MidDrive_Flywheel_{tag(side)}", bm, ["iron", "brass"], location=loc,
                            smooth_angle=45))
        # belt-driven pulley with flange and a toothed pinion on the same shaft
        pbm = bmesh.new()
        prof = [(r_, h_ * side) for r_, h_ in
                ((pr - 0.012, -0.040), (pr + 0.012, -0.034), (pr + 0.012, -0.012), (pr - 0.002, -0.006),
                 (pr - 0.002, 0.020), (pr + 0.014, 0.024), (pr + 0.014, 0.040), (pr - 0.012, 0.040))]
        rings = P.lathe(pbm, prof, 28)
        m = len(prof)
        for s_ in range(28):
            a_, b_ = rings[s_], rings[(s_ + 1) % 28]
            pbm.faces.new((a_[m - 1], a_[0], b_[0], b_[m - 1]))
        P.lathe(pbm, [(0.0, -0.060), (0.020, -0.060), (0.020, 0.060), (0.0, 0.060)], 14)
        P.lathe(pbm, [(0.020, -0.007), (pr - 0.004, -0.007), (pr - 0.004, 0.007), (0.020, 0.007), (0.020, -0.007)], 28)
        bmesh.ops.remove_doubles(pbm, verts=list(pbm.verts), dist=1e-5)
        bmesh.ops.recalc_face_normals(pbm, faces=list(pbm.faces))
        out.append(P.finish(builder, f"Gear_MidDrive_Pulley_{tag(side)}", pbm, "iron", location=(px_, y, pz),
                            smooth_angle=45))
        # pinion: 14-tooth gear on the inner side of the pulley shaft
        gbm = bmesh.new()
        teeth = 14
        gr = 0.050
        ring_top, ring_bot = [], []
        for k in range(teeth * 4):
            a = math.tau * k / (teeth * 4)
            ph = k % 4
            rr = gr + (0.012 if ph in (1, 2) else 0.0)
            ring_top.append(gbm.verts.new((rr * math.cos(a), 0.012, rr * math.sin(a))))
            ring_bot.append(gbm.verts.new((rr * math.cos(a), -0.012, rr * math.sin(a))))
        n = len(ring_top)
        for i in range(n):
            j = (i + 1) % n
            gbm.faces.new((ring_bot[i], ring_bot[j], ring_top[j], ring_top[i]))
        gbm.faces.new(list(reversed(ring_bot)))
        gbm.faces.new(ring_top)
        bmesh.ops.recalc_face_normals(gbm, faces=list(gbm.faces))
        out.append(P.finish(builder, f"Gear_MidDrive_Pinion_{tag(side)}", gbm, "brass",
                            location=(px_, side * (T.FLY_Y - 0.085), pz), smooth_angle=30))
        out += belt_and_guard(builder, side, (fx, fz, fr), (px_, pz, pr))
        # shaft from the cab side to the pulley
        out.append(rod(builder, f"Gear_MidDrive_Shaft_{tag(side)}", (px_, side * 0.43, pz), (px_, side * 0.62, pz),
                       0.016, "iron", 8))
    return out


def tangent_belt(c1, r1, c2, r2, steps=10):
    """Closed belt loop (x, z points) around two circles joined by outer tangents."""
    (x1, z1), (x2, z2) = c1, c2
    d = math.hypot(x2 - x1, z2 - z1)
    base = math.atan2(z2 - z1, x2 - x1)
    off = math.acos((r1 - r2) / d)  # outer tangent angle from the centre line
    pts = []
    # big circle: from -off..+off going around the far side (c1 is the big wheel)
    for k in range(steps * 2 + 1):
        a = base + off + (2 * math.pi - 2 * off) * k / (steps * 2)
        pts.append((x1 + r1 * math.cos(a), z1 + r1 * math.sin(a)))
    for k in range(steps + 1):
        a = base - off + 2 * off * k / steps
        pts.append((x2 + r2 * math.cos(a), z2 + r2 * math.sin(a)))
    return pts


def belt_and_guard(builder, side, fly, pul):
    out = []
    fx, fz, fr = fly
    px_, pz, pr = pul
    y = side * T.FLY_Y
    loop = tangent_belt((fx, fz), fr - 0.004, (px_, pz), pr + 0.002)
    # drop duplicate join points
    clean = [loop[0]]
    for p in loop[1:]:
        if math.hypot(p[0] - clean[-1][0], p[1] - clean[-1][1]) > 1e-4:
            clean.append(p)
    if math.hypot(clean[0][0] - clean[-1][0], clean[0][1] - clean[-1][1]) < 1e-4:
        clean.pop()
    path = [(x, y, z) for x, z in clean]
    hw, th = 0.024, 0.008
    prof = [(-th / 2, -hw), (th / 2, -hw), (th / 2, hw), (-th / 2, hw)]
    out.append(P.sweep(builder, f"Prop_MidDrive_Belt_{tag(side)}", path, "rubber", profile=prof, cyclic=True,
                       up=(0, 1, 0)))
    # guard: fender-like arch over the flywheel (flat run from the cab wall, then concentric arc)
    r_in = 0.248
    arc = B.arch_path((fx, fz), r_in + 0.008, 90, -12, 14)
    path2 = [(T.X(612), fz + r_in + 0.008)] + arc
    out.append(F.sweep_band(builder, f"Prop_MidDrive_Guard_{tag(side)}", path2, side * 0.47, side * 0.63, 0.012,
                            "paint2"))
    # brass rim beading along the guard edge
    out.append(F.sweep_band(builder, f"Trim_MidDriveGuardBead_{tag(side)}", [(x, z + 0.008) for x, z in path2],
                            side * 0.628, side * 0.634, 0.020, "brass"))
    return out


def build_markers(builder, surf):
    """Amber side markers: brass-bezelled domes seated on the flat flanks."""
    out = []
    for side in SIDES:
        for k, (px, z) in enumerate(((441, 0.80), (626, 0.70), (815, 0.44))):
            hit = surf.side(T.X(px), z, side)
            if not hit:
                continue
            loc = hit[0]
            prof = [(0.0, -0.003), (0.023, -0.003), (0.023, 0.006), (0.017, 0.009), (0.015, 0.011), (0.0, 0.015)]
            out.append(F.revolve(builder, f"Fine_Marker_{tag(side)}_{k}", [(r, h * side) for r, h in prof],
                                 ["brass"], axis=1, center=(loc.x, loc.y, loc.z), segments=14))
            lens = F.revolve(builder, f"Fine_Marker_{tag(side)}_{k}_Lens", [
                (0.0, 0.0095 * side), (0.013, 0.0085 * side), (0.013, 0.0105 * side), (0.0, 0.0155 * side)],
                ["amber"], axis=1, center=(loc.x, loc.y, loc.z), segments=14)
            out.append(lens)
    return out


def build(builder, hull):
    surf = F.Surface([hull])
    out = []
    out += build_smokebox(builder)
    out += build_dome_and_stack(builder)
    out += build_truck_lamps(builder)
    out += build_push_frame(builder)
    out += build_speedster_front(builder)
    out += build_speedster_hardware(builder)
    out += build_cab_hardware(builder)
    out += tank_and_cylinder(builder)
    out += build_mid_drive(builder)
    out += build_markers(builder, surf)
    return out
