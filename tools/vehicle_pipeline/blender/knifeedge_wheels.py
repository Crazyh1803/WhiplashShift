"""Knobby spiked truck wheels (End B) and wire speedster wheels (End A). Axis is local Y.

Names: Wheel_Truck_* / Wheel_Coupe_* with one `_Tire_` object per wheel; every origin is the hub.
"""
import math

import bmesh
from mathutils import Matrix, Vector

import knifeedge_prims as P
import knifeedge_trace as T

STYLE = {
    "truck": {"R": T.WHEEL_R["truck"], "W": T.WHEEL_W["truck"], "flange": 0.205, "segments": 44,
              "tread_depth": 0.034, "lug_every": 2, "spikes": 22, "spokes": 8, "web": 0.55},
    "coupe": {"R": T.WHEEL_R["coupe"], "W": T.WHEEL_W["coupe"], "flange": 0.188, "segments": 48,
              "tread_depth": 0.006, "lug_every": 1, "spikes": 0, "spokes": 0, "web": 0.0},
}


def _tire_profile(st):
    R, hw, fl = st["R"], st["W"] / 2, st["flange"]
    sw = R - fl
    shoulder = hw * 0.74
    return [
        (fl - 0.006, -hw * 0.80), (fl + 0.010, -hw * 0.98), (fl + 0.55 * sw, -hw * 1.0),
        (R - 0.040, -hw * 0.90), (R - 0.016, -shoulder * 1.06),
    ], shoulder


def build_tire(builder, style, side, location):
    st = STYLE[style]
    R, hw = st["R"], st["W"] / 2
    head, shoulder = _tire_profile(st)
    cols = 5
    tread_h = [shoulder * (-1 + 2 * k / (cols - 1)) for k in range(cols)]
    N = st["segments"]
    bm = bmesh.new()
    rings = []
    for s in range(N):
        ang = math.tau * s / N
        ca, sa = math.cos(ang), math.sin(ang)
        phase = s % st["lug_every"]
        groove = st["lug_every"] > 1 and phase == st["lug_every"] - 1
        ring = []

        def add(r, h):
            ring.append(bm.verts.new((r * ca, h * side, r * sa)))
        for r, h in head:
            add(r, h)
        for k, h in enumerate(tread_h):
            if st["lug_every"] > 1:
                depth = st["tread_depth"] if groove else 0.0
                if k in (0, cols - 1) and groove:
                    depth *= 0.7
            else:
                depth = st["tread_depth"] * (1.0 if k in (1, 3) else 0.0)
            add(R - depth - (0.004 if k in (0, cols - 1) else 0.0), h)
        for r, h in reversed(head):
            add(r, -h)
        rings.append(ring)
    m = len(rings[0])
    for s in range(N):
        a, b = rings[s], rings[(s + 1) % N]
        for i in range(m - 1):
            bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
    inner = [(st["flange"] - 0.010, -hw * 0.78), (st["flange"] - 0.010, hw * 0.78)]
    ring_i = []
    for s in range(N):
        ang = math.tau * s / N
        ca, sa = math.cos(ang), math.sin(ang)
        ring_i.append([bm.verts.new((r * ca, h * side, r * sa)) for r, h in inner])
    for s in range(N):
        a, b = ring_i[s], ring_i[(s + 1) % N]
        bm.faces.new((a[0], a[1], b[1], b[0]))
    for s in range(N):
        a, b = rings[s], rings[(s + 1) % N]
        li, lj = ring_i[s], ring_i[(s + 1) % N]
        bm.faces.new((a[0], b[0], lj[0], li[0]))
        bm.faces.new((a[m - 1], li[1], lj[1], b[m - 1]))
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    # spikes: iron-free rubber studs on the shoulders (part of the tyre object)
    for k in range(st["spikes"]):
        ang = math.tau * (k + 0.25 * (k % 2)) / st["spikes"]
        col = shoulder * (0.62 if k % 2 else -0.62)
        cone = bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=0.016, radius2=0.004,
                                     depth=0.044)
        ca, sa = math.cos(ang), math.sin(ang)
        for v in cone["verts"]:
            lx, ly, lz = v.co
            rad = R - 0.022 + lz
            v.co = Vector((rad * ca - lx * sa, (col + ly) * side, rad * sa + lx * ca))
    # outboard sidewall studs (conical, pointing along the axle) as drawn on the front elevation
    for k in range(14 if style == "truck" else 0):
        ang = math.tau * (k + 0.5) / 14
        cone = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.016, radius2=0.004, depth=0.046)
        ca, sa = math.cos(ang), math.sin(ang)
        for v in cone["verts"]:
            lx, ly, lz = v.co
            rr = (st["flange"] + 0.052) + lx
            v.co = Vector((rr * ca - ly * sa, side * (hw * 0.93 + 0.012 + lz), rr * sa + ly * ca))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return P.finish(builder, f"Wheel_{style.title()}_Tire_{side:+d}", bm, "rubber",
                    location=location, smooth_angle=48)


def barrel_radius(st):
    return st["flange"] - 0.016


def web_height(st):
    return st["W"] / 2 * st["web"] if st["web"] else 0.0


def build_rim(builder, style, side, location):
    st = STYLE[style]
    fl, hw = st["flange"], st["W"] / 2
    br = barrel_radius(st)
    oh = hw * 0.86
    profile = [
        (br, -oh), (fl + 0.002, -oh * 1.02), (fl + 0.008, -oh * 0.93), (fl - 0.010, -oh * 0.80),
        (br + 0.010, -oh * 0.50), (br + 0.010, oh * 0.50), (fl - 0.010, oh * 0.80),
        (fl + 0.008, oh * 0.93), (fl + 0.002, oh * 1.02), (br, oh),
        (br - 0.012, oh * 0.60), (br - 0.012, -oh * 0.60),
    ]
    bm = bmesh.new()
    N = 36
    rings = P.lathe(bm, [(r, h * side) for r, h in profile], N)
    m = len(profile)
    for s_ in range(N):
        a_, b_ = rings[s_], rings[(s_ + 1) % N]
        bm.faces.new((a_[m - 1], a_[0], b_[0], b_[m - 1]))
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return P.finish(builder, f"Wheel_{style.title()}_Rim_{side:+d}", bm, "iron" if style == "truck" else "brass",
                    location=location, smooth_angle=40)


def build_spoke(builder, side, index, location):
    """Truck: a tapered cast-iron bar from the hub boss to the rim barrel."""
    st = STYLE["truck"]
    pitch = math.tau / st["spokes"]
    r0, r1 = 0.060, barrel_radius(st) + 0.004
    a_in, a_out = 0.20 * pitch, 0.13 * pitch
    poly = [(r0, -a_in), (r1, -a_out), (r1, a_out), (r0, a_in)]
    bm = bmesh.new()
    base = side * web_height(st)
    thick = 0.040
    top, bot = [], []
    for r, a in poly:
        x, z = r * math.cos(a), r * math.sin(a)
        top.append(bm.verts.new((x, base + side * thick * 0.5, z)))
        bot.append(bm.verts.new((x, base - side * thick * 0.5, z)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bm.faces.new(list(reversed(bot)) if side > 0 else bot)
    bm.faces.new(top if side > 0 else list(reversed(top)))
    rot = Matrix.Rotation(index * pitch, 4, "Y")
    for v in bm.verts:
        v.co = rot @ v.co
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    P.bevel_edges(bm, 0.004, 1)
    return P.finish(builder, f"Wheel_Truck_Spoke_{side:+d}_{index}", bm, "iron", location=location,
                    smooth_angle=40)


def build_wires(builder, side, location):
    """Eighteen crossed wire spokes per face as one object (tangentially laced)."""
    st = STYLE["coupe"]
    bm = bmesh.new()
    br = barrel_radius(st)
    count = 18
    for face in (-1, 1):
        for k in range(count):
            ang = math.tau * k / count
            lace = (1 if face > 0 else -1) * 0.55
            p0 = Vector((0.046 * math.cos(ang), side * face * 0.020, 0.046 * math.sin(ang)))
            a1 = ang + lace
            p1 = Vector(((br - 0.004) * math.cos(a1), side * face * 0.004, (br - 0.004) * math.sin(a1)))
            t = (p1 - p0).normalized()
            n1 = t.cross(Vector((0, 1, 0))).normalized()
            n2 = t.cross(n1).normalized()
            r = 0.0028
            ring0 = [bm.verts.new(p0 + (n1 * math.cos(q) + n2 * math.sin(q)) * r) for q in (0, math.pi / 2, math.pi, 1.5 * math.pi)]
            ring1 = [bm.verts.new(p1 + (n1 * math.cos(q) + n2 * math.sin(q)) * r) for q in (0, math.pi / 2, math.pi, 1.5 * math.pi)]
            for i in range(4):
                j = (i + 1) % 4
                bm.faces.new((ring0[i], ring0[j], ring1[j], ring1[i]))
            bm.faces.new(list(reversed(ring0)))
            bm.faces.new(ring1)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return P.finish(builder, f"Wheel_Coupe_Wires_{side:+d}", bm, "iron", location=location, smooth_angle=60)


def build_hub(builder, style, side, location):
    st = STYLE[style]
    hw = st["W"] / 2
    truck = style == "truck"
    web = web_height(st)
    bm = bmesh.new()

    def piece(index, fn):
        before = set(bm.faces)
        fn()
        for f in bm.faces:
            if f not in before:
                f.material_index = index

    if truck:
        # cast boss the spokes bolt to, domed brass cap, hex bolt ring
        piece(1, lambda: P.lathe(bm, [(0.0, side * (web - 0.022)), (0.082, side * (web - 0.022)),
                                      (0.082, side * (web + 0.022)), (0.0, side * (web + 0.022))], 24))
        piece(0, lambda: P.lathe(bm, [(0.0, side * (web + 0.060)), (0.030, side * (web + 0.054)),
                                      (0.058, side * (web + 0.034)), (0.062, side * (web + 0.022)),
                                      (0.0, side * (web + 0.022))], 24))

        def bolts():
            for k in range(8):
                ang = math.tau * (k + 0.5) / 8
                cx, cz = 0.071 * math.cos(ang), 0.071 * math.sin(ang)
                geom = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.011,
                                             radius2=0.009, depth=0.016)
                for v in geom["verts"]:
                    x, y, z = v.co
                    v.co = Vector((cx + x, side * (web + 0.022 + z + 0.008), cz + y))
        piece(0, bolts)
        # rim bolts: 12 hex heads around the barrel face
        def rim_bolts():
            for k in range(12):
                ang = math.tau * k / 12
                cx, cz = (barrel_radius(st) - 0.010) * math.cos(ang), (barrel_radius(st) - 0.010) * math.sin(ang)
                geom = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.010,
                                             radius2=0.008, depth=0.014)
                for v in geom["verts"]:
                    x, y, z = v.co
                    v.co = Vector((cx + x, side * (hw * 0.86 + 0.004 + z), cz + y))
        piece(0, rim_bolts)
    else:
        piece(0, lambda: P.lathe(bm, [(0.0, side * 0.040), (0.026, side * 0.038), (0.050, side * 0.022),
                                      (0.052, side * 0.012), (0.0, side * 0.012)], 24))
        piece(0, lambda: P.lathe(bm, [(0.0, -side * 0.034), (0.048, -side * 0.034), (0.052, -side * 0.012),
                                      (0.0, -side * 0.012)], 24))
        piece(0, lambda: P.lathe(bm, [(0.0, side * 0.012), (0.040, side * 0.012), (0.040, -side * 0.012),
                                      (0.0, -side * 0.012)], 24))
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return P.finish(builder, f"Wheel_{style.title()}_Hub_{side:+d}", bm, ["brass", "iron"], location=location,
                    smooth_angle=40)


def build(builder, hull=None):
    objs = []
    for style, end in (("truck", "truck"), ("coupe", "coupe")):
        st = STYLE[style]
        for side in (-1, 1):
            loc = (T.WHEEL_X[end], side * T.TRACK_Y[end], T.WHEEL_R[end])
            objs.append(build_tire(builder, style, side, loc))
            objs.append(build_rim(builder, style, side, loc))
            objs.append(build_hub(builder, style, side, loc))
            if style == "truck":
                for k in range(st["spokes"]):
                    objs.append(build_spoke(builder, side, k, loc))
            else:
                objs.append(build_wires(builder, side, loc))
    return objs
