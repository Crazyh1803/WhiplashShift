"""Knobby beadlock sand-rail wheels (End B, `Truck`) and 10-spoke alloy supercar wheels (End A, `Coupe`). Axis is local Y.

Names: Wheel_Truck_* / Wheel_Coupe_* with one `_Tire_` object per wheel; every origin is the hub.
"""
import math

import bmesh
from mathutils import Matrix, Vector

import knifeedge_prims as P
import knifeedge_trace as T

STYLE = {
    "truck": {"R": T.WHEEL_R["truck"], "W": T.WHEEL_W["truck"], "flange": 0.262, "segments": 64,
              "tread_depth": 0.052, "lug_every": 2, "sidewall_studs": 0, "spokes": 6, "web": 0.55,
              "spoke_r0": 0.070, "spoke_t": 0.046, "hub_r": 0.092},
    "coupe": {"R": T.WHEEL_R["coupe"], "W": T.WHEEL_W["coupe"], "flange": 0.322, "segments": 64,
              "tread_depth": 0.006, "lug_every": 1, "sidewall_studs": 0, "spokes": 10, "web": 0.45,
              "spoke_r0": 0.050, "spoke_t": 0.030, "hub_r": 0.062},
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
    return P.finish(builder, f"Wheel_{style.title()}_Rim_{side:+d}", bm, "steel",
                    location=location, smooth_angle=40)


def build_spoke(builder, style, side, index, location):
    """A tapered bar from the hub boss to the rim barrel (cast alloy / pressed steel)."""
    st = STYLE[style]
    pitch = math.tau / st["spokes"]
    r0, r1 = st["spoke_r0"], barrel_radius(st) + 0.004
    a_in, a_out = 0.22 * pitch, 0.13 * pitch
    poly = [(r0, -a_in), (r1, -a_out), (r1, a_out), (r0, a_in)]
    bm = bmesh.new()
    base = side * web_height(st)
    thick = st["spoke_t"]
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
    rot = Matrix.Rotation((index + 0.5) * pitch, 4, "Y")
    for v in bm.verts:
        v.co = rot @ v.co
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    P.bevel_edges(bm, 0.004, 1)
    return P.finish(builder, f"Wheel_{style.title()}_Spoke_{side:+d}_{index}", bm,
                    "iron" if style == "truck" else "steel", location=location, smooth_angle=40)


def _bolt_ring(bm, count, ring_r, y, side, radius, depth, phase=0.0):
    for k in range(count):
        ang = math.tau * (k + phase) / count
        cx, cz = ring_r * math.cos(ang), ring_r * math.sin(ang)
        geom = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=radius, radius2=radius * 0.85,
                                     depth=depth)
        for v in geom["verts"]:
            x, yy, z = v.co
            v.co = Vector((cx + x, side * (y + z), cz + yy))


def build_hub(builder, style, side, location):
    """Boss + cap + bolts. Truck: pressed-steel boss, 16 beadlock bolts on the rim face. Coupe: alloy hub, 5 nuts."""
    st = STYLE[style]
    hw = st["W"] / 2
    web = web_height(st)
    hr = st["hub_r"]
    bm = bmesh.new()

    def piece(index, fn):
        before = set(bm.faces)
        fn()
        for f in bm.faces:
            if f not in before:
                f.material_index = index

    # boss the spokes bolt to and a domed cap
    piece(1, lambda: P.lathe(bm, [(0.0, side * (web - 0.022)), (hr, side * (web - 0.022)),
                                  (hr, side * (web + 0.022)), (0.0, side * (web + 0.022))], 24))
    piece(0, lambda: P.lathe(bm, [(0.0, side * (web + 0.056)), (hr * 0.45, side * (web + 0.050)),
                                  (hr * 0.80, side * (web + 0.032)), (hr * 0.84, side * (web + 0.022)),
                                  (0.0, side * (web + 0.022))], 24))
    if style == "truck":
        piece(0, lambda: _bolt_ring(bm, 16, barrel_radius(st) - 0.010, hw * 0.86 + 0.004, side, 0.011, 0.016))
        piece(0, lambda: _bolt_ring(bm, 6, hr * 0.62, web + 0.030, side, 0.011, 0.016, 0.5))
    else:
        piece(0, lambda: _bolt_ring(bm, 5, hr * 0.62, web + 0.030, side, 0.009, 0.014, 0.5))
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return P.finish(builder, f"Wheel_{style.title()}_Hub_{side:+d}", bm, ["steel", "iron"], location=location,
                    smooth_angle=40)


def build_brake(builder, side, location):
    """Rotor with hat behind the spokes (End A only); origin at the hub."""
    bm = bmesh.new()
    P.lathe(bm, [(0.0, side * 0.040), (0.050, side * 0.040), (0.050, side * 0.011), (0.190, side * 0.011),
                 (0.190, -side * 0.011), (0.0, -side * 0.011)], 48)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return P.finish(builder, f"Wheel_Coupe_Brake_{side:+d}", bm, "steel", location=location, smooth_angle=40)


def build_caliper(builder, side, location):
    """Fixed caliper straddling the rotor at its rear edge; mesh is hub-relative with the origin at the hub."""
    ang = math.radians(165)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    rot = Matrix.Rotation(-ang + math.pi / 2, 4, "Y")
    for v in bm.verts:
        v.co = (Matrix.Translation((0.15 * math.cos(ang), 0, 0.15 * math.sin(ang))) @ rot
                @ Vector((v.co.x * 0.115, v.co.y * 0.070, v.co.z * 0.075)))
    P.bevel_edges(bm, 0.012, 2)
    return P.finish(builder, f"Wheel_Coupe_Caliper_{side:+d}", bm, "accent", location=location, smooth_angle=40)


def build(builder, hull=None):
    objs = []
    for style, end in (("truck", "truck"), ("coupe", "coupe")):
        st = STYLE[style]
        for side in (-1, 1):
            loc = (T.WHEEL_X[end], side * T.TRACK_Y[end], T.WHEEL_R[end])
            objs.append(build_tire(builder, style, side, loc))
            objs.append(build_rim(builder, style, side, loc))
            objs.append(build_hub(builder, style, side, loc))
            for k in range(st["spokes"]):
                objs.append(build_spoke(builder, style, side, k, loc))
            if style == "coupe":
                objs.append(build_brake(builder, side, loc))
                objs.append(build_caliper(builder, side, loc))
    return objs
