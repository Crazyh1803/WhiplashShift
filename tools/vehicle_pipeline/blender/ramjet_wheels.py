"""Truck steel wheels and coupe turbine wheels. Axis is local Y; origin at the hub."""
import math

import bmesh
from mathutils import Matrix, Vector

import ramjet_prims as P
import ramjet_trace as T

STYLE = {
    "truck": {"R": 0.43, "W": 0.34, "flange": 0.240, "segments": 60,
              "spokes": 6, "tread_depth": 0.024, "lug_every": 3},
    "coupe": {"R": 0.40, "W": 0.29, "flange": 0.262, "segments": 64,
              "spokes": 10, "tread_depth": 0.007, "lug_every": 1},
}


def _tire_profile(st):
    R, hw = st["R"], st["W"] / 2
    fl = st["flange"]
    sw = R - fl
    shoulder = hw * 0.76
    return [
        (fl - 0.008, -hw * 0.82), (fl + 0.014, -hw * 0.99), (fl + 0.50 * sw, -hw * 1.0),
        (R - 0.045, -hw * 0.90), (R - 0.018, -shoulder * 1.06),
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
            depth = st["tread_depth"] if (groove or k == cols // 2) else 0.0
            if st["lug_every"] == 1:
                depth = st["tread_depth"] if k in (1, 3) else 0.0
            if k in (0, cols - 1):
                depth = st["tread_depth"] * 0.6 if groove else 0.0
            add(R - depth - (0.006 if k in (0, cols - 1) else 0.0), h)
        for r, h in reversed(head):
            add(r, -h)
        rings.append(ring)
    m = len(rings[0])
    for s in range(N):
        a, b = rings[s], rings[(s + 1) % N]
        for i in range(m - 1):
            bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
    # inner liner so the tire is a closed ring, hidden behind the rim
    inner = [(st["flange"] - 0.012, -hw * 0.78), (st["flange"] - 0.012, hw * 0.78)]
    ring_i = []
    for s in range(N):
        ang = math.tau * s / N
        ca, sa = math.cos(ang), math.sin(ang)
        ring_i.append([bm.verts.new((r * ca, h * side, r * sa)) for r, h in inner])
    for s in range(N):
        a, b = ring_i[s], ring_i[(s + 1) % N]
        bm.faces.new((a[0], a[1], b[1], b[0]))
    for s in range(N):  # close the bead edges against the liner
        a, b = rings[s], rings[(s + 1) % N]
        li, lj = ring_i[s], ring_i[(s + 1) % N]
        bm.faces.new((a[0], b[0], lj[0], li[0]))
        bm.faces.new((a[m - 1], li[1], lj[1], b[m - 1]))
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return P.finish(builder, f"Wheel_{style.title()}_Tire_{side:+d}", bm, "rubber",
                    location=location, smooth_angle=48)


def web_height(st):
    """Axial (outboard-positive) height of the spoke/web mid-plane."""
    return st["W"] / 2 * (0.62 if st["spokes"] == 6 else 0.78)


def barrel_radius(st):
    return st["flange"] - 0.018


def build_rim(builder, style, side, location):
    st = STYLE[style]
    fl, hw = st["flange"], st["W"] / 2
    br = barrel_radius(st)
    oh = hw * 0.88
    profile = [
        (br, -oh), (fl + 0.002, -oh * 1.02), (fl + 0.008, -oh * 0.93), (fl - 0.010, -oh * 0.80),
        (br + 0.010, -oh * 0.50), (br + 0.010, oh * 0.50), (fl - 0.010, oh * 0.80),
        (fl + 0.008, oh * 0.93), (fl + 0.002, oh * 1.02), (br, oh),
        (br - 0.014, oh * 0.60), (br - 0.014, -oh * 0.60),
    ]
    bm = bmesh.new()
    N = 28
    rings = P.lathe(bm, [(r, h * side) for r, h in profile], N)
    m = len(profile)
    for s_ in range(N):
        a_, b_ = rings[s_], rings[(s_ + 1) % N]
        bm.faces.new((a_[m - 1], a_[0], b_[0], b_[m - 1]))
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    for f in bm.faces:  # inner barrel well is dark so the gaps between spokes read as depth
        c = f.calc_center_median()
        if math.hypot(c.x, c.z) < br - 0.004:
            f.material_index = 1
    mat = ["chrome" if style == "coupe" else "dark", "dark"]
    return P.finish(builder, f"Wheel_{style.title()}_Rim_{side:+d}", bm, mat, location=location,
                    smooth_angle=40)


def build_spoke(builder, style, side, index, location):
    st = STYLE[style]
    count = st["spokes"]
    hw = st["W"] / 2
    pitch = math.tau / count
    bm = bmesh.new()
    if style == "truck":
        # steel disc web segment between two ventilation openings, dished inboard
        r0, r1 = 0.070, barrel_radius(st) + 0.002
        a0, a1 = 0.20 * pitch, 0.80 * pitch
        steps = 4
        thick = 0.034
        outer = [(r1, a0 + (a1 - a0) * k / steps) for k in range(steps + 1)]
        inner = [(r0, a1 - (a1 - a0) * k / steps) for k in range(steps + 1)]
        poly = outer + inner
        base = side * web_height(st)
        top = []
        bot = []
        for r, a in poly:
            x, z = r * math.cos(a), r * math.sin(a)
            top.append(bm.verts.new((x, base + side * thick * 0.5, z)))
            bot.append(bm.verts.new((x, base - side * thick * 0.5, z)))
        n = len(poly)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((bot[i], bot[j], top[j], top[i]))
        bm.faces.new(list(reversed(bot)) if side > 0 else bot)
        bm.faces.new(top if side > 0 else list(reversed(top)))
        mat = "chrome"  # brushed steel web against the gunmetal rim and rotor
    else:
        # five-point star, each spoke drawn as a twin-line pair of tapered blades
        pair, sub = divmod(index, 2)
        pitch5 = math.tau / 5
        r0, r1 = 0.082, barrel_radius(st) + 0.002
        steps = 5
        poly = []
        lo, hi = [], []
        for k in range(steps + 1):
            t = k / steps
            r = r0 + (r1 - r0) * t
            c = (-1 if sub == 0 else 1) * (0.082 + 0.030 * t) * pitch5
            h = (0.050 + 0.016 * t) * pitch5
            lo.append((r, c - h))
            hi.append((r, c + h))
        poly = lo + list(reversed(hi))
        thick = 0.022
        base = side * web_height(st)
        top, bot = [], []
        for r, a in poly:
            x, z = r * math.cos(a), r * math.sin(a)
            tilt = (r - r0) / (r1 - r0)
            top.append(bm.verts.new((x, base + side * (thick * 0.5 + 0.012 * tilt), z)))
            bot.append(bm.verts.new((x, base - side * thick * 0.5 + side * 0.006 * tilt, z)))
        n = len(poly)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((bot[i], bot[j], top[j], top[i]))
        bm.faces.new(list(reversed(bot)) if side > 0 else bot)
        bm.faces.new(top if side > 0 else list(reversed(top)))
        mat = "chrome"
    # place the spoke at its pitch angle about the axle (Y)
    rot = Matrix.Rotation((index // 2 * math.tau / 5) if style == "coupe" else index * pitch, 4, "Y")
    for v in bm.verts:
        v.co = rot @ v.co
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return P.finish(builder, f"Wheel_{style.title()}_Spoke_{side:+d}_{index}", bm, mat,
                    location=location, smooth_angle=40)


def build_hub(builder, style, side, location):
    st = STYLE[style]
    hw = st["W"] / 2
    web = web_height(st)
    coupe = style == "coupe"
    bm = bmesh.new()

    def tag(faces, index):
        for f in faces:
            f.material_index = index

    def piece(index, fn):
        before = set(bm.faces)
        fn()
        tag([f for f in bm.faces if f not in before], index)

    plate_r = 0.098 if coupe else 0.078
    cap_r = 0.040 if coupe else 0.036
    # hub plate that every spoke / web segment bolts to (dark, continuous disc)
    piece(1, lambda: P.lathe(bm, [(0.0, side * (web + 0.012)), (plate_r, side * (web + 0.012)),
                                  (plate_r, side * (web - 0.012)), (0.0, side * (web - 0.012))], 28))
    # centre cap dome (chrome)
    piece(0, lambda: P.lathe(bm, [(0.0, side * (web + 0.034)), (cap_r * 0.6, side * (web + 0.031)),
                                  (cap_r, side * (web + 0.014)), (cap_r, side * (web + 0.012)),
                                  (0.0, side * (web + 0.012))], 20))

    def lugs():
        count = 5 if coupe else 6
        lug_r = 0.066 if coupe else 0.056
        for k in range(count):
            ang = math.tau * (k + 0.5) / count
            cx, cz = lug_r * math.cos(ang), lug_r * math.sin(ang)
            geom = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.0135,
                                         radius2=0.011, depth=0.022)
            for v in geom["verts"]:
                x, y, z = v.co
                v.co = Vector((cx + x, side * (web + 0.012 + z + 0.011), cz + y))
    piece(0, lugs)
    # brake rotor behind the web and a caliper clamping its rim
    rotor_r = barrel_radius(st) - 0.030
    h_rotor = web - 0.070
    # dark rotor so the chrome blades read against it instead of a solid grey disc
    piece(1, lambda: P.lathe(bm, [(0.050, side * (h_rotor - 0.010)), (rotor_r, side * (h_rotor - 0.010)),
                                  (rotor_r, side * (h_rotor + 0.010)), (0.050, side * (h_rotor + 0.010)),
                                  (0.050, side * (h_rotor - 0.010))], 28))

    def caliper():
        arc = [(rotor_r - 0.048, side * (h_rotor - 0.036)), (rotor_r + 0.008, side * (h_rotor - 0.036)),
               (rotor_r + 0.008, side * (h_rotor + 0.036)), (rotor_r - 0.048, side * (h_rotor + 0.036))]
        rings = P.lathe(bm, arc + arc[:1], 7, start=math.radians(35), turn=math.radians(42))
        bm.faces.new(rings[0][:-1])
        bm.faces.new(list(reversed(rings[-1][:-1])))
    piece(2, caliper)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    mats = ["chrome", "dark", "accent"]
    return P.finish(builder, f"Wheel_{style.title()}_Hub_{side:+d}", bm, mats, location=location,
                    smooth_angle=40)


def build_wheels(builder):
    objs = []
    for style in ("truck", "coupe"):
        st = STYLE[style]
        for side in (-1, 1):
            loc = (T.WHEEL_X[style], side * T.TRACK_Y, T.WHEEL_R[style])
            objs.append(build_tire(builder, style, side, loc))
            objs.append(build_rim(builder, style, side, loc))
            objs.append(build_hub(builder, style, side, loc))
            for k in range(st["spokes"]):
                objs.append(build_spoke(builder, style, side, k, loc))
    return objs
