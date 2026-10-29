"""Clothed, smoothed human figures for the industrial market benchmark (bmesh; Blender Z-up, front +Y, feet at z=0).

Anatomy is built from swept elliptical tubes (limbs bend through Catmull-Rom paths, so elbows/knees are continuous),
a lofted torso, a displaced-sphere head with a modelled brow/nose/lip/chin/ear/eye set, articulated hands with
finger phalanges and a thumb, and shaped shoes. Clothing is the outer layer: sleeves, trousers, jacket/shirt with
authored fold ridges, ray-cast-draped apron/pockets/flaps, collars, cuffs, hood and headband. Two-bone IK puts the
wrists exactly at world grip points supplied by the caller (the counter and bowl).
"""
import math

from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import industrial_market_textures as TX

V = Vector


def g(x, s):
    return math.exp(-(x / s) ** 2)


def unit(v):
    v = V(v)
    return v.normalized() if v.length > 1e-9 else V((0, 0, 1))


def ik2(S, W, a, b, pole):
    S, W, pole = V(S), V(W), V(pole)
    d = W - S
    L = d.length
    L = min(L, a + b - 1e-3)
    dirv = d.normalized()
    x = (a * a - b * b + L * L) / (2 * L)
    h = math.sqrt(max(a * a - x * x, 1e-8))
    perp = pole - dirv * pole.dot(dirv)
    perp = perp.normalized() if perp.length > 1e-6 else V((0, 0, 1))
    return S + dirv * x + perp * h, (S + dirv * L)


# ---------------------------------------------------------------------------------------------- head
def head_point(th, ph, sk):
    """Head surface at azimuth th (0 = front, +Y) and elevation ph. Eye line is z=0; returns Vector."""
    d = V((math.sin(th) * math.cos(ph), math.cos(th) * math.cos(ph), math.sin(ph)))
    d = V([math.copysign(abs(c) ** 0.84, c) for c in d])        # superellipsoid: flatter face/sides, more skull-like volume
    wid, dep, up_, dn = 0.0775 * sk["w"], 0.098, 0.118, 0.118
    zc = 0.004
    z = zc + d.z * (up_ if d.z > 0 else dn)
    x, y = d.x * wid, d.y * dep
    zr = z / 0.118
    if zr < 0:                                                   # jaw taper and chin
        k = (-zr) ** 1.5
        x *= 1 - 0.30 * k * sk["jaw"]
        y *= 1 - 0.12 * k
        if y > 0:
            y += 0.004 * k
    if y > 0:                                                    # flatter face plane
        y *= 0.93 + 0.07 * (1 - min(1, abs(x) / 0.06))
        y -= 0.006 * (1 - g(z + 0.01, 0.07))
    ax = abs(x)
    if y > 0.02:
        s = sk
        y += 0.011 * g(ax, 0.05) * g(z - 0.032, 0.013) * s["brow"]                         # brow ridge
        y -= 0.0055 * g(ax - 0.033, 0.016) * g(z - 0.0, 0.013)                              # eye socket
        y += 0.009 * g(ax - 0.05, 0.024) * g(z + 0.034, 0.028)                              # cheek
        ny = (0.0085 * max(0.0, min(1.0, (z + 0.058) / 0.07)) + (0.028 * g(z + 0.043, 0.0095))) * s["nose"]   # bridge + tip
        y += ny * g(x, 0.0085 + 0.0045 * g(z + 0.04, 0.012))
        y += 0.0065 * g(ax - 0.0145, 0.0058) * g(z + 0.043, 0.007) * s["nose"]               # alae
        y += 0.0085 * g(x, 0.026) * g(z + 0.0735, 0.0058) * s["lip"]                         # upper lip
        y += 0.0095 * g(x, 0.025) * g(z + 0.0905, 0.0072) * s["lip"]                         # lower lip
        y -= 0.0045 * g(x, 0.03) * g(z + 0.0815, 0.0019)                                    # mouth line
        y += 0.0085 * g(x, 0.02) * g(z + 0.118, 0.012)                                      # chin
        y -= 0.003 * g(x, 0.02) * g(z + 0.058, 0.005)                                       # philtrum/under nose
    return V((x, y, z))


def build_head(m, sk, origin, tilt, skin_mat, seg=36, rings=27):
    """Returns (surface_fn(x, z)->y in head-local, face list). origin = eye-line centre in person space."""
    base = []
    for i in range(rings + 1):
        ph = -math.pi / 2 + math.pi * i / rings
        if i == 0:
            ph += 1e-3
        if i == rings:
            ph -= 1e-3
        base.append([head_point(2 * math.pi * j / seg - math.pi * 0 , ph, sk) for j in range(seg)])
    # azimuth 0 = front; surface() column order is increasing azimuth
    rows = [[origin + tilt @ p for p in r] for r in base]
    local = [[p for p in r] for r in base]

    def uvf(ri, cj, nr, nc):
        p = local[ri][cj % nc]
        nx = p.x
        # front-facing region: planar paint; otherwise skin tile
        th = 2 * math.pi * (cj % nc) / nc
        front = math.cos(th) > 0.22 and abs(p.x) < TX.FACE_HALF_W * 0.97 and p.y > 0.0
        if front:
            return TX.face_uv(p.x, p.z)
        return (0.5 * (cj / nc), 0.505 + 0.49 * (ri / (nr - 1)) * 1.0) if False else (0.5 * (cj / nc), 0.5 + 0.49 * ri / (nr - 1))
    fs, vs = m.surface(rows, True, skin_mat, smooth=True, uv_fn=uvf)
    # re-map UVs per face corner so the planar face region never mixes with the tile mapping within one face
    for f in fs:
        fr = []
        for lp in f.loops:
            p = tilt.inverted() @ (lp.vert.co - origin)
            th = math.atan2(p.x, p.y)
            fr.append(math.cos(th) > 0.22 and abs(p.x) < TX.FACE_HALF_W * 0.97 and p.y > 0.0)
        if all(fr):
            for lp in f.loops:
                p = tilt.inverted() @ (lp.vert.co - origin)
                lp[m.uv].uv = TX.face_uv(p.x, p.z)
        elif any(fr):
            for lp in f.loops:
                p = tilt.inverted() @ (lp.vert.co - origin)
                th = math.atan2(p.x, p.y) % (2 * math.pi)
                lp[m.uv].uv = (0.5 * th / (2 * math.pi), 0.5 + 0.49 * (p.z + 0.12) / 0.24)
    m.fan_cap(vs[0], origin + tilt @ V((0, 0, -0.118 + 0.004)), skin_mat, flip=True, smooth=True)
    m.fan_cap(vs[-1], origin + tilt @ V((0, 0, 0.118 + 0.004)), skin_mat, smooth=True)
    verts = [(tilt @ p) + origin for r in base for p in r]
    polys = []
    for i in range(rings):
        for j in range(seg):
            j2 = (j + 1) % seg
            polys.append((i * seg + j, i * seg + j2, (i + 1) * seg + j2, (i + 1) * seg + j))
    tree = BVHTree.FromPolygons([tuple(v) for v in verts], polys)

    def surf_y(x, z):
        hit = tree.ray_cast(origin + tilt @ V((x, 0.4, z)), tilt @ V((0, -1, 0)), 1.0)
        return (tilt.inverted() @ (hit[0] - origin)).y if hit[0] is not None else 0.08
    return surf_y, tree


def build_eyes_ears(m, sk, origin, tilt, surf_y, skin):
    R = 0.0118
    for s in (-1, 1):
        ex = s * 0.0325 * sk["w"]
        ey = surf_y(ex, 0.0) - 0.0078
        c = origin + tilt @ V((ex, ey, 0.0))
        fs = m.sphere(c, R, skin, seg=12, rings=8, smooth=True, rot=tilt)
        ue0, ve0, ue1, ve1 = TX.ATLAS["eye"]
        for f in fs:
            m.explicit.add(f)
            for lp in f.loops:
                p = tilt.inverted() @ (lp.vert.co - c)
                lp[m.uv].uv = (ue0 + (ue1 - ue0) * (0.5 + p.x / (2 * R * 1.0)), ve0 + (ve1 - ve0) * (0.5 + p.z / (2 * R * 1.0)))
        # lids: upper heavier, lower thin; arcs just proud of the eyeball
        def arc(a0, a1, rad_t, sx, sz, n=9):
            pts = []
            for k in range(n):
                a = a0 + (a1 - a0) * k / (n - 1)
                px, pz = sx * math.cos(a), sz * math.sin(a)
                yy = surf_y(ex + px, pz) - 0.002
                pts.append(origin + tilt @ V((ex + px, min(yy, ey + R * 0.8 + 0.0035), pz)))
            fs2, _, _ = m.tube(pts, [rad_t] * n, skin, seg=6, samples=n, up=tilt @ V((0, 1, 0)), uv=("atlas",), round_ends=(True, True))
        arc(math.radians(172), math.radians(8), 0.0030, 0.0148, 0.0098)          # upper lid
        arc(math.radians(188), math.radians(352), 0.0021, 0.0140, 0.0085)        # lower lid
        # ear: flattened ellipsoid + helix ring
        ear_c = origin + tilt @ V((s * 0.0795 * sk["w"], -0.012, -0.012))
        m.sphere(ear_c, 0.021, skin, scale=(0.32, 0.55, 1.0), seg=10, rings=8, smooth=True, rot=tilt @ Matrix.Rotation(s * 0.25, 4, "Z"))
        helix = [origin + tilt @ V((s * (0.0805 * sk["w"] + 0.002), -0.012 + 0.012 * math.cos(a), -0.012 + 0.028 * math.sin(a))) for a in
                 [math.radians(x) for x in (-60, -10, 40, 90, 140, 200, 250)]]
        m.tube(helix, [0.0040] * len(helix), skin, seg=5, samples=9, up=tilt @ V((1, 0, 0)), uv=("atlas",))


def build_hair(m, sk, origin, tilt, hair, surf_y, ponytail=False, rng=None, thick=0.007, back_len=0.0):
    seg, rings = 32, 12

    def hairline(th):
        a = abs((th + math.pi) % (2 * math.pi) - math.pi)
        if a <= math.radians(36):
            return 0.066
        if a <= math.radians(105):
            return 0.066 + (a - math.radians(36)) / math.radians(69) * (-0.03 - 0.066)
        return -0.03 + (a - math.radians(105)) / math.radians(75) * (-0.075 + 0.03 - back_len)
    rows = []
    for i in range(rings + 1):
        ph = math.radians(-8) + (math.pi / 2 - 1e-3 - math.radians(-8)) * i / rings
        row = []
        for j in range(seg):
            th = 2 * math.pi * j / seg
            base = head_point(th, ph, sk)
            hl = hairline(th)
            n = V((base.x / 0.0775, base.y / 0.098, (base.z - 0.004) / 0.118)).normalized()
            # the part of the sphere below the hairline slides up onto the hairline (open edge)
            zc = max(base.z, hl) if i < rings else base.z
            t = (i / rings)
            clump = 0.0035 * math.sin(th * 13 + ph * 7) + 0.0025 * math.sin(th * 29 - ph * 11)
            p = base + n * (thick * (0.6 + 0.8 * t) + clump * 0.8) + V((0, 0, 0))
            if base.z < hl:
                p = V((p.x * 1.0, p.y * 1.0, p.z))
                p.z = hl + (base.z - hl) * 0.0
                k = 0.0
                p = V((p.x, p.y, hl)) + n * 0.0
                # pull to head surface at hairline height (keep xy on the same azimuth)
                bh = head_point(th, math.asin(max(-1, min(1, (hl - 0.004) / 0.118))), sk)
                p = bh + V((bh.x, bh.y, 0)).normalized() * (thick * 0.4)
                p.z = hl
            row.append(origin + tilt @ (p * V((1.045, 1.04, 1.045)) + V((0, -0.002, 0.002))))
        rows.append(row)
    ncol = seg

    def uvf(ri, cj, nr, nc):
        return (cj / nc * 3.0, ri / (nr - 1) * 1.5)
    m.surface(rows, True, hair, smooth=True, uv_fn=uvf, flip=False)
    # crown fan cap
    m.fan_cap(m.bm.verts[-seg:], origin + tilt @ V((0, -0.002, 0.118 * 1.045 + 0.01)), hair, smooth=True)
    if ponytail:
        pts = [origin + tilt @ V(p) for p in ((0, -0.092, 0.035), (0, -0.125, 0.02), (0.004, -0.15, -0.05), (-0.004, -0.158, -0.16), (0.006, -0.15, -0.26))]
        m.tube(pts, [0.026, 0.028, 0.026, 0.02, 0.006], hair, seg=10, samples=14, ratio=1.0, uv=("cloth", 3.0))
        m.tube([origin + tilt @ V(p) for p in ((0, -0.096, 0.028), (0, -0.108, 0.026))], [0.02, 0.02], "leather", seg=10, samples=3,
               uv=("cloth", 3.0))  # hair tie


# --------------------------------------------------------------------------------------------- hands
def build_hand(m, W, f, n, side, curls, thumb, skin, scale=1.0, cuff_r=0.0):
    """Wrist W; fingers point along f, palm faces n; side +1 right/-1 left. curls: 4 tuples of 3 flexion angles (rad toward n).
    thumb: 3 world-space direction vectors for the thumb segments."""
    f, n = unit(f), unit(n)
    n = unit(n - f * n.dot(f))
    l = f.cross(n) * side                       # thumb side
    palm = 0.098 * scale
    # palm: flattened tube wrist -> knuckles
    ppts = [W - f * 0.012, W + f * palm * 0.5 + n * 0.002, W + f * palm + n * 0.003]
    m.tube(ppts, [0.0275 * scale, 0.037 * scale, 0.0415 * scale], skin, seg=12, samples=7, ratio=0.36, up=l, uv=("atlas",), round_ends=(True, True),
           cap_len=0.012)
    # finger roots across the knuckle line (thumb side first)
    spec = [(0.031, 0.95, 0.0105), (0.0105, 1.0, 0.0108), (-0.0105, 0.93, 0.0102), (-0.0305, 0.74, 0.0092)]
    splay = [0.10, 0.02, -0.05, -0.14]
    tips = []
    for k, (off, ln, rad) in enumerate(spec):
        root = W + f * palm + l * off * scale + n * 0.003
        lens = [0.044 * ln * scale, 0.026 * ln * scale, 0.0215 * ln * scale]
        pts, ang = [root], 0.0
        d_side = l * splay[k] * 0.5
        p = root
        for s_i in range(3):
            ang += curls[k][s_i]
            d = unit(f * math.cos(ang) + n * math.sin(ang) + d_side)
            p = p + d * lens[s_i]
            pts.append(p)
        rr = [rad * scale, rad * 0.93 * scale, rad * 0.84 * scale, rad * 0.74 * scale]
        m.tube(pts, rr, skin, seg=6, samples=5, ratio=0.9, up=n, uv=("atlas",), cap_len=rad * 0.7)
        tips.append((pts[-2], pts[-1], d))
    # thumb
    root = W + f * 0.038 * scale + l * 0.027 * scale + n * 0.0
    pts = [root]
    for d, ln in zip(thumb, (0.043, 0.037, 0.030)):
        pts.append(pts[-1] + unit(d) * ln * scale)
    m.tube(pts, [0.0135 * scale, 0.0118 * scale, 0.0105 * scale, 0.0093 * scale], skin, seg=6, samples=6, ratio=0.9, up=n, uv=("atlas",), cap_len=0.008)
    tips.append((pts[-2], pts[-1], unit(thumb[-1])))
    # fingernails on the back of each tip
    for a, b, d in tips:
        c = (a + b) * 0.5 - n * 0.0075 * scale
        if abs(d.dot(n)) > 0.99:
            continue
        bas = Matrix(((d.x, 0, 0), (d.y, 0, 0), (d.z, 0, 0)))
        ax = unit(d)
        side_v = ax.cross(n)
        side_v = unit(side_v) if side_v.length > 1e-6 else l
        nrm = unit(ax.cross(side_v))
        R3 = Matrix((side_v, ax, nrm)).transposed()
        fs = m.sphere(c, 0.0066 * scale, skin, scale=(0.85, 1.15, 0.28), seg=6, rings=3, smooth=True, rot=R3.to_4x4())
        ua, va, ub, vb = TX.ATLAS["nail"]
        for fc in fs:
            m.explicit.add(fc)
            for lp in fc.loops:
                lp[m.uv].uv = ((ua + ub) / 2, (va + vb) / 2)
    return l


FIST = [(0.55, 1.0, 0.9)] * 4
RELAXED = [(0.30, 0.50, 0.38), (0.36, 0.56, 0.42), (0.44, 0.62, 0.46), (0.52, 0.66, 0.5)]
CUP = [(0.26, 0.55, 0.45), (0.3, 0.6, 0.48), (0.34, 0.62, 0.5), (0.4, 0.62, 0.5)]
FLAT = [(0.04, 0.10, 0.08), (0.03, 0.09, 0.08), (0.03, 0.10, 0.08), (0.05, 0.12, 0.1)]


# ---------------------------------------------------------------------------------------------- shoes
def build_shoe(m, foot, yaw, mat, L=0.285, wide=0.102, boot=0.0, rubber=None):
    """foot: ankle-centre ground position (x,y). Toe points along local +Y rotated by yaw. Sole bottom at z=0."""
    rot = Matrix.Rotation(yaw, 4, "Z")
    base = V((foot[0], foot[1], 0))
    prof = [(-0.075, 0.095, 0.074, 0.050), (-0.04, 0.085, 0.082, 0.056), (0.0, 0.088, 0.088, 0.062), (0.05, 0.06, 0.092, 0.066),
            (0.11, 0.05, 0.10, 0.078), (0.18, 0.045, 0.104, 0.08), (0.235, 0.040, 0.092, 0.07), (0.275, 0.028, 0.062, 0.054)]
    prof = [(y, h, w * wide / 0.10, z0) for (y, h, w, z0) in prof]

    def ring(y, h, w, zc, n=14):
        pts = []
        for j in range(n):
            a = 2 * math.pi * j / n
            c, s = math.cos(a), math.sin(a)
            pts.append(base + rot @ V(((w / 2) * math.copysign(abs(c) ** 0.8, c), y, 0.016 + h * (1 + math.copysign(abs(s) ** 0.9, s)) / 2)))
        return pts
    rows = [ring(y, h * 1.3, w * 0.96, zc) for (y, h, w, zc) in prof]
    rows = [[V((p.x, p.y, max(p.z, 0.0))) for p in r] for r in rows]
    m.surface(rows, True, mat, smooth=True, uv_fn=lambda ri, cj, nr, nc: (cj / nc * 2.0, ri / (nr - 1) * 2.0))
    m.fan_cap(m.bm.verts[-14:], sum((p for p in rows[-1]), V()) / 14, mat, smooth=True)
    m.fan_cap(m.bm.verts[-14 * len(rows):-14 * (len(rows) - 1)], sum((p for p in rows[0]), V()) / 14, mat, flip=True, smooth=True)
    # sole slab (rubber/dark leather)
    sole = [(base + rot @ V(((w / 2 + 0.003) * math.cos(2 * math.pi * j / 18), y + 0.0, 0.0)), ) for j in range(0)]
    m.box(base + rot @ V((0, 0.105, 0.0095)), (wide * 0.92, 0.345, 0.019), mat, rot=(0, 0, yaw), bevel=0.006, smooth=False)
    # heel block
    m.box(base + rot @ V((0, -0.058, 0.019)), (wide * 0.72, 0.065, 0.016), mat, rot=(0, 0, yaw), bevel=0.003)
    if boot > 0:
        pts = [base + rot @ V((0, -0.005, 0.07)), base + rot @ V((0, -0.008, 0.07 + boot))]
        m.tube(pts, [0.047, 0.052], mat, seg=14, samples=5, uv=("cloth", 3.0), round_ends=(False, False))
        # lace/top band
        m.tube([base + rot @ V((0, -0.008, 0.07 + boot - 0.008)), base + rot @ V((0, -0.008, 0.07 + boot))], [0.056, 0.058], mat, seg=14,
               samples=3, uv=("cloth", 3.0), round_ends=(False, False))
        # tongue/front lace panel
        m.box(base + rot @ V((0, 0.035, 0.085)), (0.045, 0.014, 0.075), mat, rot=(-0.55, 0, yaw), bevel=0.003, smooth=True)


# ----------------------------------------------------------------------------------------- thick sheets
def thick_sheet(m, grid_fn, nu, nv, thick, mat, flip=False, uv_scale=2.0):
    """grid_fn(i,j)->Vector on the outer surface (i in 0..nu, j in 0..nv). Builds front + back + edge strips (cloth with thickness)."""
    outer = [[grid_fn(i, j) for i in range(nu + 1)] for j in range(nv + 1)]
    # approximate normals by finite differences, offset inward
    inner = []
    for j in range(nv + 1):
        row = []
        for i in range(nu + 1):
            du = outer[j][min(i + 1, nu)] - outer[j][max(i - 1, 0)]
            dv = outer[min(j + 1, nv)][i] - outer[max(j - 1, 0)][i]
            nrm = du.cross(dv)
            nrm = nrm.normalized() if nrm.length > 1e-9 else V((0, 1, 0))
            if flip:
                nrm = -nrm
            row.append(outer[j][i] - nrm * thick)
        inner.append(row)
    uvf = lambda ri, cj, nr, nc: (cj / (nc - 1) * uv_scale, ri / (nr - 1) * uv_scale)
    m.surface(outer, False, mat, smooth=True, uv_fn=uvf, flip=flip)
    m.surface(inner, False, mat, smooth=True, uv_fn=uvf, flip=not flip)
    edges = [[outer[0][i] for i in range(nu + 1)], [outer[nv][i] for i in range(nu + 1)]]
    inedges = [[inner[0][i] for i in range(nu + 1)], [inner[nv][i] for i in range(nu + 1)]]
    for e, ie, fl in ((edges[0], inedges[0], False), (edges[1], inedges[1], True)):
        m.surface([e, ie], False, mat, smooth=False, flip=fl)
    le = [outer[j][0] for j in range(nv + 1)]
    lie = [inner[j][0] for j in range(nv + 1)]
    re_ = [outer[j][nu] for j in range(nv + 1)]
    rie = [inner[j][nu] for j in range(nv + 1)]
    m.surface([le, lie], False, mat, smooth=False, flip=True)
    m.surface([re_, rie], False, mat, smooth=False, flip=False)


# ---------------------------------------------------------------------------------------------- person
def folds(spec, rad_dir_fn=None):
    """spec: list of (z0, zspread, amp, k, ang0, angspread, phase). Returns f(z, ang)->radial amount (m)."""
    def fn(z, ang):
        tot = 0.0
        for z0, zs, amp, k, a0, asp, ph in spec:
            da = math.atan2(math.sin(ang - a0), math.cos(ang - a0))
            tot += amp * g(z - z0, zs) * g(da, asp) * math.cos(k * (z - z0) + ph)
        return tot
    return fn


def build_person(m, P):
    """P: dict spec (see build_industrial_market). Returns info dict with joint/contact positions (person-local)."""
    H = P["H"]
    sc = H / 1.75
    skin, top, trou, leather, hair = P["mat"]["skin"], P["mat"]["top"], P["mat"]["trousers"], P["mat"]["leather"], P["mat"]["hair"]
    cloth2 = P["mat"].get("cloth2")
    out = {}
    feet = P["feet"]                                   # {'L': (x,y,yaw), 'R': ...}
    hipz = 0.505 * H + P.get("hip_drop", 0.0)
    pel = V(P["pelvis"])                                # (x, y) shift of hips
    lean = P["lean"]                                    # forward shift of shoulders (m)
    shz = 0.818 * H
    sk = P["skull"]

    # ---- legs (trousers) + shoes
    for side, key in ((-1, "L"), (1, "R")):
        fx, fy, fyaw = feet[key]
        hx = pel.x + side * 0.088 * sc * P["hipw"]
        hip = V((hx, pel.y + 0.005, hipz + (0.004 if key == P["weight"] else -0.006)))
        ank = V((fx, fy - 0.01 * math.cos(fyaw) , 0.12 * sc))
        # straight weight-bearing leg, relaxed leg slightly flexed forward at the knee
        flex = 0.0 if key == P["weight"] else 0.055
        knee = (hip + ank) * 0.5 + V((0, 0.035 + flex, 0.0))
        knee.z = (hip.z + ank.z) * 0.5 + 0.015
        mid_t = hip + (knee - hip) * 0.5 + V((0, 0.005, 0))
        mid_s = knee + (ank - knee) * 0.5 + V((0, -0.012, 0))
        cuff_z = ank.z + 0.045
        pts = [hip + V((0, 0, 0.06)), hip, mid_t, knee, mid_s, ank + V((0, 0, 0.05)), ank]
        rad = [0.088 * sc * P["thigh"], 0.088 * sc * P["thigh"], 0.080 * sc * P["thigh"], 0.062 * sc, 0.056 * sc, 0.058 * sc, 0.060 * sc]
        kz = knee.z
        lz0, lz1 = hip.z + 0.06, ank.z

        def disp(t, ang, base, R, kz=kz, key=key, flex=flex):
            z = base.z
            # ang 0 = forward (+Y); knee crease ridges on the front, hip pull-folds on thigh top, cuff stack above the shoe
            m_ = 1.0
            fr = max(0.0, math.cos(ang))
            m_ += 0.050 * fr * (g(z - (kz + 0.04), 0.017) + g(z - (kz - 0.045), 0.015)) * (1 + 3 * flex)
            m_ += 0.040 * max(0.0, math.cos(ang - 0.6)) * g(z - (kz + 0.11), 0.014)
            m_ -= 0.035 * fr * g(z - (kz - 0.01), 0.012) * (1 + 4 * flex)
            m_ += 0.050 * max(0.0, math.cos(ang - 0.4 * (1 if key == "R" else -1) + 0.9)) * g(z - (hipz - 0.07), 0.04) * math.sin(14 * z + 1.0)
            m_ += 0.035 * (g(z - (ank.z + 0.115), 0.012) + g(z - (ank.z + 0.065), 0.013)) * (0.4 + 0.6 * fr + 0.3)
            m_ += 0.006 * math.sin(ang * 3 + z * 31) * (0.5 + 0.5 * fr)
            return m_
        m.tube(pts, rad, trou, seg=12, samples=26, ratio=0.96, up=V((0, 1, 0)), disp=disp, uv=("cloth", P["uvs"]["trousers"]), round_ends=(True, False))
        build_shoe(m, (fx, fy), fyaw, leather, L=0.285 * sc, wide=0.102 * sc, boot=P.get("boot", 0.0))
    # ---- pelvis / hips (trousers) and torso (top)
    lx = lean
    ctr = lambda z: pel.x * max(0.0, 1 - (z - hipz) / 0.3)
    hipr = [dict(z=hipz - 0.10, cx=pel.x, cy=pel.y, rx=0.168 * sc * P["hipw"], ry=0.112 * sc, p=2.4),
            dict(z=hipz - 0.02, cx=pel.x, cy=pel.y + 0.003, rx=0.176 * sc * P["hipw"], ry=0.118 * sc, p=2.4),
            dict(z=hipz + 0.08, cx=pel.x, cy=pel.y + 0.005, rx=0.168 * sc * P["hipw"], ry=0.113 * sc, p=2.4)]
    m.loft(hipr, trou, seg=26, samples=9, uv=(2.0 * sc, 3.0, 0.0), close_bot=False, close_top=False)
    ws = P["waist"]
    tz = [hipz + 0.02, hipz + 0.09, 0.60 * H, 0.665 * H, 0.725 * H, 0.775 * H, shz - 0.012, shz + 0.018, 0.842 * H, 0.858 * H]
    def tor(t, z, cx, cy, rx, ry, p=2.35):
        return dict(z=z, cx=cx, cy=cy, rx=rx, ry=ry, p=p)
    sw = P["shoulder_w"] * sc
    rings = [tor(0, tz[0] - 0.035, pel.x, pel.y + 0.004, 0.2 * sc * P["hem"], 0.14 * sc * P["hem"], 2.2),
             tor(0, tz[0] + 0.02, pel.x * 0.9, pel.y + 0.004 + lx * 0.1, 0.186 * sc * P["hem"], 0.128 * sc * P["hem"], 2.3),
             tor(0, tz[2], pel.x * 0.6, 0.004 + lx * 0.25, ws[0] * sc, ws[1] * sc),
             tor(0, tz[3], pel.x * 0.3, 0.008 + lx * 0.5, ws[2] * sc, ws[3] * sc),
             tor(0, tz[4], 0, 0.012 + lx * 0.7, (sw * 0.88), 0.118 * sc * P["chest_d"], 2.4),
             tor(0, tz[5], 0, 0.012 + lx * 0.85, sw * 0.97, 0.112 * sc, 2.5),
             tor(0, tz[6], 0, 0.008 + lx, sw * 1.0, 0.098 * sc, 2.7),
             tor(0, tz[7], 0, 0.004 + lx, sw * 0.62, 0.082 * sc, 2.3),
             tor(0, tz[8], 0, 0.0 + lx, 0.075 * sc, 0.064 * sc, 2.1),
             tor(0, tz[9], 0, -0.004 + lx, 0.058 * sc, 0.056 * sc, 2.0)]
    tf = folds(P["torso_folds"])
    # armpit-to-centre pull wrinkles + belly hang
    def tdisp(t, ang, p):
        z = p.z
        rd = V((p.x - lx * (z / H), p.y - lx * (z / H) * 0.0, 0)).normalized() if abs(p.x) + abs(p.y) > 1e-6 else V((0, 1, 0))
        amt = tf(z, ang)
        amt += 0.006 * math.sin(ang * 5 + z * 23) * g(z - 0.64 * H, 0.1)
        return p + rd * amt
    m.loft(rings, top, seg=24, samples=16, disp=tdisp, uv=(3.0 * sc, 1.6, 0.0), close_bot=True, close_top=False)
    out["hem_z"] = tz[0] - 0.035
    # ---- neck + head
    neck_b = V((0, lx - 0.004, 0.855 * H))
    head_c = V((P["head_off"][0], 0.012 + lx * 0.6 + P["head_off"][1], 0.935 * H + P["head_off"][2]))
    tilt = Matrix.Rotation(P["head_tilt"][0], 4, "X") @ Matrix.Rotation(P["head_tilt"][1], 4, "Z")
    m.tube([neck_b - V((0, 0, 0.04)), neck_b + V((0, 0, 0.03)), head_c + V((0, -0.03, -0.1))], [0.058 * sc, 0.050 * sc, 0.047 * sc], skin, seg=18, samples=10,
           ratio=0.96, uv=("atlas",), round_ends=(True, True))
    surf_y, tree = build_head(m, sk, head_c, tilt, skin)
    build_eyes_ears(m, sk, head_c, tilt, surf_y, skin)
    build_hair(m, sk, head_c, tilt, hair, surf_y, ponytail=P.get("ponytail", False), thick=P.get("hair_thick", 0.007), back_len=P.get("hair_back", 0.0))
    out["face_world"] = head_c
    out["eye_surf"] = (head_c + tilt @ V((0, surf_y(0, 0.0), 0.0)))
    # ---- arms
    arm_info = {}
    for side, key in ((-1, "L"), (1, "R")):
        S = V((side * sw * 0.97, 0.003 + lx, shz - 0.018))
        a, b = 0.178 * H, 0.152 * H
        arm = P["arms"][key]
        W = V(arm["wrist"])
        elbow, W = ik2(S, W, a, b, arm["pole"])
        up_ = V(arm["pole"])
        pts = [S + V((side * -0.01, 0, 0.0)), S + (elbow - S) * 0.5, elbow, elbow + (W - elbow) * 0.55, W]
        sleeve_t = arm.get("sleeve_t", 1.0)
        rad = [0.056 * sc * P["arm"], 0.050 * sc * P["arm"], 0.043 * sc * P["arm"], 0.038 * sc, 0.0345 * sc]
        # fold ridges on the inner elbow and sleeve bunching near the cuff
        def adisp(t, ang, base, R, up_=up_, bend=(elbow - S).angle(W - elbow, 0.0)):
            m_ = 1.0
            inner = max(0.0, math.cos(ang - math.pi))
            m_ += 0.06 * inner * (g(t - 0.46, 0.05) + 0.6 * g(t - 0.58, 0.04)) * math.sin(10 * t) * min(1.0, bend * 2)
            m_ += 0.045 * (g(t - 0.52, 0.04)) * max(0, math.cos(ang - 0.2))
            m_ += 0.03 * (g(t - 0.9, 0.04) + g(t - 0.82, 0.03)) * (0.5 + 0.5 * math.sin(ang * 4))
            m_ += 0.005 * math.sin(ang * 3 + t * 40)
            return m_
        matfn = (lambda t, st=sleeve_t: top if t <= st else skin)
        cuff_t = arm.get("cuff_roll", None)
        fs, Pa, fr = m.tube(pts, rad, top, seg=12, samples=20, ratio=0.97, up=up_, disp=adisp, mat_fn=matfn, uv=("cloth", P["uvs"]["top"]),
                           round_ends=(True, True))
        # skin parts of the arm (forearm below the roll) use atlas UVs
        for f in fs:
            if f.material_index == m.mi(skin):
                for lp in f.loops:
                    lp[m.uv].uv = (0.5 * (lp.vert.co.x * 7 % 1.0) * 0.99, 0.505 + 0.49 * ((lp.vert.co.z * 3) % 1.0))
        # armscye seam + cuff / roll
        m.tube([S + V((0.0, 0.0, 0.0)) + V((0, 0.0, 0.0))] * 1 + [S + V((side * 0.0, 0.04, -0.01)), S + V((side * 0.01, 0.0, -0.05)), S + V((side * 0.0, -0.045, -0.015))],
               [0.0035] * 4, top, seg=5, samples=10, uv=("cloth", 3.0)) if False else None
        if cuff_t is not None:
            ci = int(cuff_t * (len(Pa) - 1))
            c0, c1 = Pa[max(ci - 2, 0)], Pa[min(ci + 1, len(Pa) - 1)]
            m.tube([c0, c1], [rad[3] * 1.19, rad[3] * 1.19], top, seg=18, samples=3, ratio=0.97, up=up_, uv=("cloth", P["uvs"]["top"]),
                   round_ends=(False, False))
        arm_info[key] = (S, elbow, W)
        # shoulder cap (deltoid) rounding where the sleeve meets the torso
        m.sphere(S + V((side * -0.012, 0.0, -0.004)), 0.047 * sc * P["arm"], top, scale=(0.9, 1.0, 1.0), seg=10, rings=7, smooth=True)
    out["arms"] = arm_info
    # ---- hands
    for key, side in (("L", -1), ("R", 1)):
        hd = P["hands"][key]
        W = arm_info[key][2]
        sleeve_end = P["arms"][key].get("sleeve_t", 1.0) >= 0.999
        build_hand(m, W, hd["f"], hd["n"], side, hd["curls"], hd["thumb"], skin, scale=sc * P.get("hand_scale", 1.0))
        if sleeve_end:
            f_ = unit(hd["f"])
            m.tube([W - f_ * 0.075, W + f_ * 0.004], [0.043 * sc, 0.037 * sc], top, seg=18, samples=4, uv=("cloth", P["uvs"]["top"]), round_ends=(False, False))
    return out
