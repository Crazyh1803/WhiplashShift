"""Inhabited workshop-plus-habitation block: the City quality benchmark (one combined mesh with COLOR_0 wear).

Run (never the GUI):  ak-blender tools/city_pipeline/build_habitation_workshop.py -- [--no-render] [--size 1.0]

Design space: +Y is the facade (Godot -Z), +Z up, origin at the foot centre. The whole build sits under a root X
mirror so that design +X reads as the viewer's right when looking at the facade from outside.
Face-local frames (`face_frame`): F/B/L/R = facade/rear/left/right, local +Y is outward, local X runs left to
right as seen by someone standing outside, local Z is world Z.
"""
import argparse
import json
import math
import os
import random
import sys
from contextlib import contextmanager
from math import cos, pi, sin

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

for _home in (os.environ.get("AK_HOME"), os.path.expanduser("~/agent-kit")):
    if _home and os.path.isdir(os.path.join(_home, "blender")):
        sys.path.insert(0, os.path.join(_home, "blender"))
from ak_util import args, eval_counts, report  # noqa: E402

ASSET_ID = "habitation_workshop"
SEM = ("steel", "ceramic", "cavity", "machinery", "sinew", "glow_cyan", "glow_amber", "trim")
# COLOR_0 multiplies base colour: albedo is the lit value, vertex colour darkens / tints it (never above 1).
PBR = {
    "steel": ((0.115, 0.122, 0.148), 0.62, 0.7, None),
    "ceramic": ((0.64, 0.59, 0.47), 0.5, 0.1, None),
    "cavity": ((0.012, 0.013, 0.019), 0.92, 0.1, None),
    "machinery": ((0.27, 0.285, 0.33), 0.4, 0.85, None),
    "sinew": ((0.55, 0.045, 0.05), 0.25, 0.0, None),
    "glow_cyan": ((0.0, 0.25, 0.3), 0.3, 0.0, (0.0, 0.87, 1.0)),
    "glow_amber": ((0.3, 0.12, 0.0), 0.3, 0.0, (1.0, 0.42, 0.02)),
    "trim": ((0.52, 0.40, 0.19), 0.5, 0.5, None),
}
TRI_CAP = 30000
TRI_TARGET = (18000, 30000)
GLOWS = ("glow_cyan", "glow_amber")

# ---------------------------------------------------------------------------- vertex-colour wear model


def _h(ix, iy, iz):
    n = (ix * 374761393 + iy * 668265263 + iz * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def vnoise(x, y, z):
    ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = x - ix, y - iy, z - iz
    fx, fy, fz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)

    def lerp(a, b, t):
        return a + (b - a) * t

    c = [[[_h(ix + i, iy + j, iz + l) for l in (0, 1)] for j in (0, 1)] for i in (0, 1)]
    return lerp(lerp(lerp(c[0][0][0], c[0][0][1], fz), lerp(c[0][1][0], c[0][1][1], fz), fy),
                lerp(lerp(c[1][0][0], c[1][0][1], fz), lerp(c[1][1][0], c[1][1][1], fz), fy), fx)


def wear_tint(p, mat):
    """Grime near the street, dirty streaks, broad patchiness. Pure function of position: idempotent."""
    if mat in GLOWS or mat == "cavity":
        return (1.0, 1.0, 1.0)
    n1 = vnoise(p.x * 0.45 + 11, p.y * 0.45, p.z * 0.45)
    n2 = vnoise(p.x * 2.3, p.y * 2.3 + 5, p.z * 2.3)
    v = 0.88 + 0.16 * (n1 - 0.5) + 0.08 * (n2 - 0.5)
    v *= 1 - 0.42 * max(0.0, 1 - p.z / 3.0) * (0.55 + 0.45 * n2)
    v *= 1 - 0.3 * max(0.0, vnoise(p.x * 1.9 + p.y * 1.9, 3.7, p.z * 0.14) - 0.52)
    v = max(0.16, min(1.0, v))
    if mat == "ceramic":
        return (v, v * (0.965 + 0.035 * n2), v * (0.9 + 0.06 * n1))
    if mat == "sinew":
        return (v, v * (0.8 + 0.2 * n2), v * (0.8 + 0.2 * n1))
    return (v, v, v)


# ---------------------------------------------------------------------------- mesh builder


class Kit:
    """Transform-stack builder emitting every primitive into one bmesh with a semantic slot and loop colours."""

    def __init__(s):
        s.bm = bmesh.new()
        lay = s.bm.loops.layers
        s.col = lay.float_color.new("Col") if hasattr(lay, "float_color") else lay.color.new("Col")
        s.stack = [Matrix.Diagonal((-1, 1, 1, 1))]
        s.shades = [1.0]
        s.rgbs = [(1.0, 1.0, 1.0)]
        s.parts = {}
        s.counts = {}

    def tris(s):
        return sum(len(f.verts) - 2 for f in s.bm.faces)

    @contextmanager
    def part(s, name):
        t0 = s.tris()
        try:
            yield
        finally:
            s.parts[name] = s.parts.get(name, 0) + s.tris() - t0

    @contextmanager
    def at(s, x=0.0, y=0.0, z=0.0, rx=0.0, ry=0.0, rz=0.0):
        m = s.stack[-1] @ Matrix.Translation((x, y, z)) @ Euler((rx, ry, rz), "XYZ").to_matrix().to_4x4()
        s.stack.append(m)
        try:
            yield
        finally:
            s.stack.pop()

    @contextmanager
    def along(s, p0, p1, up=(0, 0, 1)):
        p0, d = Vector(p0), Vector(p1) - Vector(p0)
        zax = d.normalized()
        hint = Vector(up)
        if abs(zax.dot(hint)) > 0.98:
            hint = Vector((0, 1, 0)) if abs(zax.y) < 0.9 else Vector((1, 0, 0))
        xax = hint.cross(zax).normalized()
        yax = zax.cross(xax)
        rot = Matrix((xax, yax, zax)).transposed().to_4x4()
        s.stack.append(s.stack[-1] @ Matrix.Translation(p0) @ rot)
        try:
            yield d.length
        finally:
            s.stack.pop()

    @contextmanager
    def look(s, shade=1.0, rgb=None):
        s.shades.append(s.shades[-1] * shade)
        r = s.rgbs[-1]
        s.rgbs.append(r if rgb is None else (r[0] * rgb[0], r[1] * rgb[1], r[2] * rgb[2]))
        try:
            yield
        finally:
            s.shades.pop()
            s.rgbs.pop()

    def _mk(s, verts, faces, mat, fix="centroid", fshade=None):
        M = s.stack[-1]
        mi = SEM.index(mat)
        vs = [s.bm.verts.new(M @ Vector(v)) for v in verts]
        if fix == "trust" and M.determinant() < 0:
            faces = [tuple(reversed(f)) for f in faces]
        if fix == "centroid":
            cen = sum((v.co for v in vs), Vector()) / len(vs)
            nf = []
            for f in faces:
                pts = [vs[j].co for j in f]
                n = Vector()
                for i in range(len(pts)):
                    a, b = pts[i], pts[(i + 1) % len(pts)]
                    n += Vector(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
                c = sum(pts, Vector()) / len(pts)
                nf.append(tuple(reversed(f)) if n.dot(c - cen) < 0 else f)
            faces = nf
        out = []
        for i, f in enumerate(faces):
            try:
                fc = s.bm.faces.new([vs[j] for j in f])
            except ValueError:
                continue
            fc.material_index = mi
            fc.smooth = False
            sh = s.shades[-1] * (fshade[i] if fshade else 1.0)
            r = s.rgbs[-1]
            for lp in fc.loops:
                t = wear_tint(lp.vert.co, mat)
                lp[s.col] = (min(1.0, t[0] * sh * r[0]), min(1.0, t[1] * sh * r[1]), min(1.0, t[2] * sh * r[2]), 1.0)
            out.append(fc)
        if fix == "recalc":
            bmesh.ops.recalc_face_normals(s.bm, faces=out)

    # -- primitives -----------------------------------------------------------------------------------------
    def box(s, x0, x1, y0, y1, z0, z1, mat, skip=()):
        if x1 - x0 < 1e-5 or y1 - y0 < 1e-5 or z1 - z0 < 1e-5:
            return
        v = [(x, y, z) for z in (z0, z1) for y in (y0, y1) for x in (x0, x1)]
        names = ("zn", "zp", "yn", "yp", "xn", "xp")
        f = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
        keep = [i for i, n in enumerate(names) if n not in skip]
        s._mk(v, [f[i] for i in keep], mat, fix="trust")

    def prism(s, pts, lo, hi, mat, plane="xy"):
        n = len(pts)

        def mp(p, t):
            return {"xy": (p[0], p[1], t), "yz": (t, p[0], p[1]), "xz": (p[0], t, p[1])}[plane]

        v = [mp(p, lo) for p in pts] + [mp(p, hi) for p in pts]
        f = [tuple(range(n)), tuple(range(n, 2 * n))]
        f += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
        s._mk(v, f, mat, fix="recalc")

    def plate(s, pts, y0, yb, mat, lip=1.0, face=0.84, yt=None):
        """Convex xz polygon: hidden back at y0, front cap sloping from thickness yb (bottom) to yt (top).
        Shingle-like: the heavy lower lip catches light, the face is darker."""
        n = len(pts)
        yt = yb if yt is None else yt
        zs = [p[1] for p in pts]
        zlo, zhi = min(zs), max(zs)

        def fy(z):
            return yb + (yt - yb) * ((z - zlo) / (zhi - zlo) if zhi > zlo else 0.0)

        v = [(p[0], y0, p[1]) for p in pts] + [(p[0], fy(p[1]), p[1]) for p in pts]
        f = [tuple(range(n, 2 * n))] + [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
        s._mk(v, f, mat, fix="centroid", fshade=[face] + [lip] * n)

    def frustum(s, cx, cy, z0, z1, hx0, hy0, hx1, hy1, mat):
        v = [(cx + a * hx0, cy + b * hy0, z0) for b in (-1, 1) for a in (-1, 1)]
        v += [(cx + a * hx1, cy + b * hy1, z1) for b in (-1, 1) for a in (-1, 1)]
        f = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
        s._mk(v, f, mat, fix="centroid")

    def lathe(s, prof, mat, seg=10, caps=True):
        rings, faces, verts = [], [], []
        for r, h in prof:
            if r < 1e-6:
                rings.append([len(verts)])
                verts.append((0.0, 0.0, h))
            else:
                rings.append([len(verts) + i for i in range(seg)])
                verts += [(r * cos(2 * pi * i / seg), r * sin(2 * pi * i / seg), h) for i in range(seg)]
        for a, b in zip(rings[:-1], rings[1:]):
            for i in range(seg):
                j = (i + 1) % seg
                if len(a) == 1:
                    faces.append((a[0], b[j], b[i]))
                elif len(b) == 1:
                    faces.append((a[i], a[j], b[0]))
                else:
                    faces.append((a[i], a[j], b[j], b[i]))
        # Side-face winding is derived from the profile: a segment's normal is (dh * radial, -dr * axial), so
        # ascending walls face out, descending walls (inner wall of a hollow ring) face in, flats follow dr.
        # An open profile that only descends (or a capped one that ends lower than it starts) is reversed so
        # its solid still faces out; hollow-ring profiles that rise somewhere are left as authored.
        dhs = [b[1] - a[1] for a, b in zip(prof[:-1], prof[1:])]
        flip = prof[-1][1] < prof[0][1] and (caps or all(d <= 0 for d in dhs))
        if flip:
            faces = [tuple(reversed(f)) for f in faces]
        if caps:
            for ring, down in ((rings[0], not flip), (rings[-1], flip)):
                if len(ring) > 1:
                    faces.append(tuple(reversed(ring)) if down else tuple(ring))
        s._mk(verts, faces, mat, fix="trust")

    def cyl(s, x, y, z, r, h, mat, axis="z", seg=10, r2=None, caps=True):
        rot = {"z": {}, "x": {"ry": pi / 2}, "y": {"rx": -pi / 2}}[axis]
        with s.at(x, y, z, **rot):
            s.lathe([(r, 0.0), (r if r2 is None else r2, h)], mat, seg, caps)

    def joint(s, x, y, z, r, mat, seg=6):
        with s.at(x, y, z):
            s.lathe([(0, -r), (r, 0), (0, r)], mat, seg)

    def beam(s, p0, p1, w, h, mat, up=(0, 0, 1), skip=()):
        with s.along(p0, p1, up) as L:
            s.box(-w / 2, w / 2, -h / 2, h / 2, 0, L, mat, skip=skip)

    def pipe(s, p0, p1, r, mat, seg=8, caps=False):
        with s.along(p0, p1) as L:
            s.lathe([(r, 0.0), (r, L)], mat, seg, caps)


# ---------------------------------------------------------------------------- reusable components: face frames


FRAMES = {
    # side -> (origin_x, origin_y, rz); local x runs left-to-right for a viewer standing outside
    "F": lambda b: (b[0], b[3], 0.0),
    "B": lambda b: (b[1], b[2], pi),
    "L": lambda b: (b[0], b[2], pi / 2),
    "R": lambda b: (b[1], b[3], -pi / 2),
}
# NOTE: in design space (pre-mirror) F local x = +x, B local x = -x, L local x = +y, R local x = -y.


@contextmanager
def face_frame(k, side, box):
    ox, oy, rz = FRAMES[side](box)
    with k.at(ox, oy, 0.0, rz=rz):
        yield


def face_len(side, box):
    return (box[1] - box[0]) if side in "FB" else (box[3] - box[2])


class Wall:
    """Local-frame wall: spans x[x0,x1] z[z0,z1], outer face at y=0, thickness t toward -y; holes get fitted."""

    def __init__(s, k, x0, x1, z0, z1, t, mat="steel"):
        s.k, s.x0, s.x1, s.z0, s.z1, s.t, s.mat = k, x0, x1, z0, z1, t, mat
        s.holes = []

    def hole(s, x0, x1, z0, z1, fit=None, **kw):
        assert s.x0 - 1e-6 <= x0 < x1 <= s.x1 + 1e-6 and s.z0 - 1e-6 <= z0 < z1 <= s.z1 + 1e-6, (x0, x1, z0, z1)
        for h in s.holes:
            assert x1 <= h[0] or x0 >= h[1] or z1 <= h[2] or z0 >= h[3], ("overlapping holes", (x0, z0), h[:4])
        s.holes.append((x0, x1, z0, z1, fit, kw))

    def build(s, rng):
        k = s.k
        xs = sorted({s.x0, s.x1} | {h[0] for h in s.holes} | {h[1] for h in s.holes})
        cols = []
        for a, b in zip(xs[:-1], xs[1:]):
            if b - a < 1e-4:
                continue
            blocked = sorted((h[2], h[3]) for h in s.holes if h[0] <= a + 1e-6 and h[1] >= b - 1e-6)
            segs, z = [], s.z0
            for z0, z1 in blocked:
                if z0 > z + 1e-6:
                    segs.append((z, z0))
                z = max(z, z1)
            if s.z1 > z + 1e-6:
                segs.append((z, s.z1))
            if cols and cols[-1][2] == segs and abs(cols[-1][1] - a) < 1e-6:
                cols[-1][1] = b
            else:
                cols.append([a, b, segs])
        def covered(col, z0, z1):
            return col is not None and any(sz0 <= z0 + 1e-6 and sz1 >= z1 - 1e-6 for sz0, sz1 in col[2])

        for i, (a, b, segs) in enumerate(cols):
            prev = cols[i - 1] if i and abs(cols[i - 1][1] - a) < 1e-6 else None
            nxt = cols[i + 1] if i + 1 < len(cols) and abs(cols[i + 1][0] - b) < 1e-6 else None
            for z0, z1 in segs:
                skip = ["yn"]
                if covered(prev, z0, z1):
                    skip.append("xn")
                if covered(nxt, z0, z1):
                    skip.append("xp")
                if abs(z0 - s.z0) < 1e-6:
                    skip.append("zn")
                if abs(z1 - s.z1) < 1e-6:
                    skip.append("zp")
                k.box(a, b, -s.t, 0, z0, z1, s.mat, skip=tuple(skip))
        for x0, x1, z0, z1, fit, kw in s.holes:
            if fit:
                with k.at(x0, 0, z0), k.part(".fit_" + fit.__name__[4:]):
                    fit(k, x1 - x0, z1 - z0, s.t, random.Random(rng.random()), **kw)

    def excl(s, pad=0.0):
        return [(h[0] - pad - h[5].get("pad", 0.0), h[1] + pad + h[5].get("pad", 0.0),
                 h[2] - pad - h[5].get("pad", 0.0), h[3] + pad + h[5].get("pad", 0.0)) for h in s.holes]


# ---------------------------------------------------------------------------- reusable components: armour


def _overlaps(a, b, pad=0.05):
    return not (a[1] <= b[0] - pad or a[0] >= b[1] + pad or a[3] <= b[2] - pad or a[2] >= b[3] + pad)


def chip_poly(rng, a, b, z0, z1, chip=0.45):
    """Rectangle with up to two clipped (chipped) corners, CCW in (x,z)."""
    corners = [(a, z0), (b, z0), (b, z1), (a, z1)]
    out = []
    pick = set(rng.sample(range(4), rng.choice((0, 0, 0, 1, 1, 2))))
    for i, (x, z) in enumerate(corners):
        if i in pick:
            cx, cz = rng.uniform(0.12, chip), rng.uniform(0.12, chip)
            sx, sz = (1 if x == a else -1), (1 if z == z0 else -1)
            pa, pb = (x + sx * cx, z), (x, z + sz * cz)
            out += [pb, pa] if i in (0, 2) else [pa, pb]
        else:
            out.append((x, z))
    # corner order is CCW; clipped pairs were emitted so that the polygon stays convex and ordered
    return out


def rib_cutaway(k, x0, x1, z0, z1, y):
    """Exposed pressure-hull ribs behind a stripped armour plate: dark pocket, C-ribs, stringers."""
    w, h = x1 - x0, z1 - z0
    k.box(x0, x1, y - 0.18, y - 0.04, z0, z1, "cavity")
    n = max(2, int(w / 0.75))
    for i in range(n):
        xx = x0 + w * (i + 0.5) / n
        k.box(xx - 0.07, xx + 0.07, y - 0.1, y + 0.12, z0, z1, "machinery")
        k.box(xx - 0.2, xx + 0.2, y + 0.04, y + 0.12, z0, z0 + 0.08, "machinery")
        k.box(xx - 0.2, xx + 0.2, y + 0.04, y + 0.12, z1 - 0.08, z1, "machinery")
    for zz in (z0 + h * 0.35, z0 + h * 0.72):
        k.box(x0, x1, y - 0.04, y + 0.07, zz - 0.05, zz + 0.05, "steel")


def armor_field(k, x0, x1, z0, z1, excl, rng, y=0.0, cov=0.8, miss=0.08, repair=0.1, rows=(1.0, 1.7),
                cw=(1.8, 3.6), t=0.2, max_rib=2, min_h=0.32):
    """Shingled courses of chipped ceramic plates over dark hull.

    Courses snap to the top/bottom edges of exclusion rectangles (openings), so plates wrap around windows
    instead of being rejected by them; stripped patches show ribs, repair plates are tinted bolted steel."""
    zs = {z0, z1}
    for e in excl:
        for z in (e[2], e[3]):
            if z0 + 0.05 < z < z1 - 0.05:
                zs.add(round(z, 3))
    zs = sorted(zs)
    bands = []
    for a, b in zip(zs[:-1], zs[1:]):
        if b - a < min_h:
            continue
        n = max(1, math.ceil((b - a) / rows[1]))
        bands += [(a + (b - a) * i / n, a + (b - a) * (i + 1) / n) for i in range(n)]
    ribs = plates = 0
    for row, (za, zb) in enumerate(bands):
        blocked = sorted((e[0], e[1]) for e in excl if e[2] < zb - 1e-4 and e[3] > za + 1e-4)
        free, x = [], x0
        for bx0, bx1 in blocked:
            if bx0 > x:
                free.append((x, bx0))
            x = max(x, bx1)
        if x1 > x:
            free.append((x, x1))
        h = zb - za
        for fa, fb in free:
            if fb - fa < 0.45:
                continue
            x = fa - (rng.uniform(0.0, cw[0] * 0.6) if row % 2 else 0.0)
            while x < fb - 0.2:
                w = rng.uniform(*cw)
                a, b = max(x, fa), min(x + w, fb)
                x += w
                if fb - b < 0.8:
                    b, x = fb, fb
                if b - a < 0.4:
                    continue
                u = rng.random()
                if u > cov:
                    continue
                top = zb + (0.1 if row else 0.0)
                if u < miss and ribs < max_rib and h > 0.7:
                    rib_cutaway(k, a + 0.1, b - 0.1, za + 0.05, zb - 0.05, y)
                    ribs += 1
                elif u < miss + repair and b - a > 0.9 and h > 0.7:
                    aa, bb, zz0, zz1 = a + rng.uniform(0.05, 0.25), b - rng.uniform(0.05, 0.25), za + 0.1, zb - rng.uniform(0.0, 0.3)
                    tone = rng.choice([(1.0, 0.8, 0.52), (0.62, 0.7, 0.8), (0.5, 0.5, 0.5), (0.95, 0.52, 0.42)])
                    with k.look(0.95, tone):
                        k.box(aa, bb, y, y + t + 0.07, zz0, zz1, "machinery" if rng.random() < 0.55 else "ceramic",
                              skip=("yn",))
                    for bx in (aa + 0.12, bb - 0.12):
                        k.box(bx - 0.05, bx + 0.05, y + t + 0.07, y + t + 0.11, (zz0 + zz1) / 2 - 0.05, (zz0 + zz1) / 2 + 0.05,
                              "trim", skip=("yn", "zn"))
                    plates += 1
                else:
                    with k.look(rng.uniform(0.86, 1.02)):
                        k.plate(chip_poly(rng, a, b, za, top), y, y + t + rng.uniform(0.0, 0.12), "ceramic", yt=y + 0.05)
                    plates += 1
    return plates


# ---------------------------------------------------------------------------- reusable components: details


FONT = {
    "0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111",
    "4": "101101111001001", "5": "111100111001111", "6": "111100111101111", "7": "111001010010010",
    "8": "111101111101111", "9": "111101111001111", "A": "010101111101101", "B": "110101110101110",
    "C": "011100100100011", "D": "110101101101110", "E": "111100110100111", "H": "101101111101101",
    "I": "111010010010111", "K": "101101110101101", "L": "100100100100111", "O": "111101101101111",
    "R": "110101110101101", "S": "011100010001110", "T": "111010010010010", "U": "101101101101111",
    "-": "000000111000000", "/": "001001010100100", ".": "000000000000010",
}


def stencil(k, text, x, z, px=0.07, mat="trim", y=0.0, rng=None, tone=(1.0, 0.92, 0.6), wear=0.12):
    """Raised stencil lettering from a 3x5 bitmap font; each row's runs merge into one thin box."""
    cx = x
    with k.look(1.0, tone):
        for ch in text:
            g = FONT.get(ch)
            if g:
                for r in range(5):
                    row, c = g[r * 3:r * 3 + 3], 0
                    while c < 3:
                        if row[c] == "1":
                            e = c
                            while e < 3 and row[e] == "1":
                                e += 1
                            if not (rng and rng.random() < wear):
                                k.box(cx + c * px, cx + e * px, y, y + 0.02, z + (4 - r) * px, z + (5 - r) * px, mat, skip=("yn", "zn"))
                            c = e
                        else:
                            c += 1
            cx += 4 * px
    return cx - x


def railing(k, p0, p1, h=1.05, every=1.5, mat="machinery", toe=True):
    p0, p1 = Vector(p0), Vector(p1)
    n = max(1, round((p1 - p0).length / every))
    for i in range(n + 1):
        p = p0 + (p1 - p0) * i / n
        k.box(p.x - 0.03, p.x + 0.03, p.y - 0.03, p.y + 0.03, p.z, p.z + h, mat, skip=("zn",))
    up = Vector((0, 0, h))
    k.beam(p0 + up, p1 + up, 0.07, 0.06, mat)
    k.beam(p0 + up * 0.5, p1 + up * 0.5, 0.04, 0.04, mat)
    if toe:
        k.beam(p0 + Vector((0, 0, 0.04)), p1 + Vector((0, 0, 0.04)), 0.02, 0.14, "steel", skip=("zn",))


def column(k, x, y, z0, z1, s=0.2, mat="steel"):
    k.box(x - s / 2, x + s / 2, y - s / 2, y + s / 2, z0, z1, mat)


def xbrace(k, lo0, hi0, lo1, hi1, w=0.07, mat="machinery"):
    """Two crossing diagonals: lo0->hi0 and lo1->hi1."""
    k.beam(lo0, hi0, w, w, mat)
    k.beam(lo1, hi1, w, w, mat)


def deck(k, x0, x1, y0, y1, z, mat="machinery", thick=0.12, joists=True, rng=None):
    k.box(x0, x1, y0, y1, z - thick, z, mat)
    if joists:
        n = max(1, int(max(x1 - x0, y1 - y0) / 2.4))
        horiz = (x1 - x0) >= (y1 - y0)
        for i in range(n + 1):
            if horiz:
                xx = x0 + (x1 - x0) * i / n
                k.box(xx - 0.05, xx + 0.05, y0, y1, z - thick - 0.22, z - thick, "steel")
            else:
                yy = y0 + (y1 - y0) * i / n
                k.box(x0, x1, yy - 0.05, yy + 0.05, z - thick - 0.22, z - thick, "steel")
    k.box(x0, x1, y0, y1, z - thick - 0.2, z - thick - 0.17, "steel")


def stair(k, p0, heading, run_len, rise_total, width=1.1, rise=0.19, mat="machinery", rails=True, close_ends=True):
    """Straight flight starting at foot point p0 and climbing along local +Y rotated by heading (design space).
    Treads, twin stringers, rails with posts. Returns the top point."""
    n = max(2, round(rise_total / rise))
    rs, run = rise_total / n, run_len / n
    p0 = Vector(p0)
    with k.at(p0.x, p0.y, p0.z, rz=heading):
        for i in range(n):
            zt = (i + 1) * rs
            k.box(-width / 2, width / 2, i * run, (i + 1) * run + 0.03, zt - 0.05, zt, mat, skip=("zn", "yn"))
        for sx in (-width / 2 - 0.03, width / 2 + 0.03):
            k.beam((sx, 0.0, 0.0), (sx, run_len, rise_total), 0.06, 0.28, "steel", up=(0, 0, 1))
        if rails:
            for sx in (-width / 2 - 0.06, width / 2 + 0.06):
                a, b = Vector((sx, 0.0, 0.0)), Vector((sx, run_len, rise_total))
                m = max(2, n // 6)
                for i in range(m + 1):
                    p = a + (b - a) * i / m
                    k.box(p.x - 0.03, p.x + 0.03, p.y - 0.03, p.y + 0.03, p.z, p.z + 0.98, mat, skip=("zn",))
                k.beam(a + Vector((0, 0, 0.98)), b + Vector((0, 0, 0.98)), 0.07, 0.06, mat)
                k.beam(a + Vector((0, 0, 0.5)), b + Vector((0, 0, 0.5)), 0.04, 0.04, mat)
    m = Matrix.Rotation(heading, 4, "Z")
    return p0 + (m @ Vector((0, run_len, rise_total)))


def pipe_run(k, pts, r, mat="machinery", flange_every=3.0, joint_mat=None, seg=8):
    """Continuous pipework: segments joined by elbow joints, flanged every few metres."""
    pts = [Vector(p) for p in pts]
    acc = 0.0
    for a, b in zip(pts[:-1], pts[1:]):
        k.pipe(a, b, r, mat, seg)
        d = b - a
        L = d.length
        acc += L
        n = int(L // flange_every)
        for i in range(1, n + 1):
            q = a + d * (i * flange_every / L)
            with k.along(q - d.normalized() * 0.04, q + d.normalized() * 0.04):
                k.lathe([(r * 1.35, 0), (r * 1.35, 0.08)], joint_mat or "steel", 6, True)
    for p in pts[1:-1]:
        k.joint(p.x, p.y, p.z, r * 1.3, joint_mat or mat)
    return pts[-1]


def stand_off(k, p, wall_axis, wall_pos, r=0.1, w=0.08, mat="steel"):
    """Bracket from a pipe centre p to a wall plane (axis 'y' or 'x')."""
    if wall_axis == "y":
        a, b = sorted((p.y, wall_pos))
        k.box(p.x - w / 2, p.x + w / 2, a, b, p.z - r, p.z + r, mat)
    else:
        a, b = sorted((p.x, wall_pos))
        k.box(a, b, p.y - w / 2, p.y + w / 2, p.z - r, p.z + r, mat)


# ---------------------------------------------------------------------------- reusable components: openings
# Fit functions draw inside a hole of a Wall: frame origin at the hole's lower-left on the outer face (y=0),
# interior toward -y, w/h are the opening size and t the wall depth.

CURTAIN_TONES = [(0.9, 0.45, 0.35), (0.45, 0.62, 0.7), (0.85, 0.7, 0.4), (0.55, 0.5, 0.55), (0.4, 0.45, 0.42)]


def bezel(k, w, h, top=0.34, side=0.12, sill=0.12, out=0.1, sides=False, shade=0.92, hood=0.42):
    """Heavy dark jambs and sill under a sloped ceramic hood: the window reads as a shadowed pocket."""
    k.prism([(0.0, h + 0.02), (hood, h + 0.02), (hood, h + 0.1), (0.0, h + top)], -side - 0.12, w + side + 0.12, "ceramic", "yz")
    if sill:
        k.box(-side * 0.6, w + side * 0.6, 0, out + 0.1, -sill, 0, "machinery")
    if sides:
        k.box(-side, 0, 0, out, 0, h, "machinery")
        k.box(w, w + side, 0, out, 0, h, "machinery")


def interior(k, w, h, t, rng, lit=True, kind=None):
    """Recessed dark room with a few lived-in fittings; at most a tiny amber lamp."""
    k.box(0, w, -t - 0.02, -t + 0.03, 0, h, "cavity")
    kind = kind or rng.choice(("lamp", "shelf", "bunk", "curtain", "lamp", "bare"))
    y0 = -t + 0.03
    if kind in ("lamp", "shelf") and w > 0.5:
        lx = w * rng.uniform(0.25, 0.75)
        k.box(lx - 0.008, lx + 0.008, y0, y0 + 0.016, h * 0.66, h, "steel")
        k.box(lx - 0.09, lx + 0.09, y0 - 0.04, y0 + 0.12, h * 0.6, h * 0.66, "machinery")
        if lit:
            k.box(lx - 0.05, lx + 0.05, y0 + 0.02, y0 + 0.1, h * 0.585, h * 0.6, "glow_amber", skip=("zp",))
    if kind == "shelf" and w > 0.7:
        zb = h * rng.uniform(0.3, 0.45)
        k.box(w * 0.1, w * 0.9, y0, y0 + 0.3, zb - 0.03, zb, "machinery")
        x = w * 0.14
        while x < w * 0.8:
            iw, ih = rng.uniform(0.1, 0.28), rng.uniform(0.1, 0.32)
            with k.look(0.9, rng.choice(CURTAIN_TONES)):
                k.box(x, x + iw, y0 + 0.02, y0 + 0.02 + rng.uniform(0.1, 0.22), zb, zb + ih, rng.choice(("ceramic", "machinery", "trim")))
            x += iw + rng.uniform(0.04, 0.12)
    if kind == "bunk" and w > 0.8:
        k.box(w * 0.05, w * 0.7, y0, y0 + 0.4, 0, h * 0.22, "machinery")
        with k.look(0.9, rng.choice(CURTAIN_TONES)):
            k.box(w * 0.08, w * 0.62, y0 + 0.02, y0 + 0.42, h * 0.22, h * 0.27, "trim")
    if kind == "curtain":
        cw = w * rng.uniform(0.4, 0.8)
        with k.look(0.85, rng.choice(CURTAIN_TONES)):
            k.box(0, cw, -0.2, -0.14, h * rng.uniform(0.2, 0.5), h, "trim")
        k.box(-0.03, w + 0.03, -0.24, -0.1, h - 0.05, h, "steel")


def fit_shutter(k, w, h, t, rng, frac=0.5, lit=True, tone=None, kind=None, hood=True, frame=True):
    interior(k, w, h, t, rng, lit, kind)
    drop = h * frac
    if frame:
        bezel(k, w, h)
    tone = tone or rng.choice(CURTAIN_TONES)
    if drop > 0.08:
        with k.look(0.88, tone):
            k.box(0.04, w - 0.04, -0.16, -0.06, h - drop, h - 0.03, "machinery")
            for i in range(int(drop / 0.3)):
                zz = h - 0.15 - i * 0.3
                k.box(0.04, w - 0.04, -0.06, -0.02, zz - 0.025, zz + 0.025, "machinery", skip=("yn", "xn", "xp"))
        k.box(0.02, w - 0.02, -0.2, 0.0, h - drop - 0.07, h - drop, "steel", skip=("xn", "xp"))


def fit_louvre(k, w, h, t, rng, lit=True, **_):
    interior(k, w, h, t, rng, lit, "lamp")
    bezel(k, w, h, top=0.28, sill=0.0)
    n = max(3, int(h / 0.3))
    for i in range(n):
        zz = 0.04 + i * (h - 0.1) / n
        with k.at(0, -0.04, zz, rx=-0.55):
            k.box(0.04, w - 0.04, -0.012, 0.012, 0, 0.22, "machinery", skip=("xn", "xp", "zn"))


def fit_bars(k, w, h, t, rng, lit=True, **_):
    interior(k, w, h, t, rng, lit)
    bezel(k, w, h)
    n = max(3, int(w / 0.22))
    for i in range(n + 1):
        xx = w * i / n
        k.box(xx - 0.016, xx + 0.016, -0.06, -0.02, 0, h, "steel", skip=("zn", "zp", "xn", "xp"))
    k.box(0, w, -0.08, 0.0, h * 0.5, h * 0.5 + 0.04, "machinery", skip=("xn", "xp"))


def fit_slits(k, w, h, t, rng, lit=True, **_):
    interior(k, w, h, t, rng, lit, "lamp")
    n = max(2, int(w / 0.5))
    with k.look(0.92):
        for i in range(n + 1):
            xx = w * i / n
            k.box(xx - 0.07, xx + 0.07, -t + 0.1, 0.1, 0, h, "ceramic", skip=("zn", "zp"))
    bezel(k, w, h, sill=0.0)


def fit_porthole(k, w, h, t, rng, lit=True, **_):
    r = min(w, h) / 2
    k.box(0, w, -t - 0.02, -t + 0.03, 0, h, "cavity")
    with k.at(w / 2, 0.04, h / 2, rx=-pi / 2):
        k.lathe([(r * 1.25, -0.3), (r * 1.25, 0.0), (r * 0.98, 0.0), (r * 0.98, -0.4)], "ceramic", 8, False)
    if lit:
        k.box(w * 0.3, w * 0.42, -t + 0.04, -t + 0.08, h * 0.3, h * 0.38, "glow_amber", skip=("yn", "zn"))


def fit_door(k, w, h, t, rng, lit=True, leaf="machinery", awning=True, lamp="glow_amber", **_):
    k.box(0, w, -t - 0.02, -t + 0.03, 0, h, "cavity")
    tone = rng.choice(CURTAIN_TONES)
    with k.look(0.8, tone):
        k.box(0.04, w - 0.04, -t + 0.12, -t + 0.26, 0, h - 0.05, leaf)
    k.box(w * 0.15, w * 0.85, -t + 0.26, -t + 0.3, h * 0.6, h * 0.82, "cavity")
    bezel(k, w, h, top=0.34, sill=0.0, out=0.16, sides=True)
    k.box(-0.3, w + 0.3, 0, 0.5, 0, 0.16, "machinery", skip=("zn", "yn"))
    if awning:
        with k.at(-0.25, 0.0, h + 0.5, rx=0.3):
            k.box(0, w + 0.5, 0, 1.0, 0, 0.05, "machinery", skip=("yn",))
        k.beam((-0.2, 0.0, h + 0.35), (-0.2, 0.85, h + 0.65), 0.05, 0.05, "steel")
    if lit:
        k.box(w / 2 - 0.07, w / 2 + 0.07, 0.16, 0.26, h + 0.38, h + 0.48, lamp, skip=("yn", "zn"))


def fit_strip(k, w, h, t, rng, lit=True, cells=None, **_):
    interior(k, w, h, t, rng, lit, "lamp")
    n = cells or max(2, round(w / 1.1))
    cw = w / n
    bezel(k, w, h, top=0.34, side=0.16, sill=0.14)
    for i in range(n + 1):
        xx = cw * i
        k.box(xx - 0.04, xx + 0.04, -0.12, 0.08, 0, h, "machinery", skip=("zn", "zp"))
    drops = 0
    for i in range(n):
        f = rng.choice((0.0, 0.0, 0.0, 0.3, 0.6)) if drops < 2 else 0.0
        if f:
            drops += 1
            with k.look(0.88, rng.choice(CURTAIN_TONES)):
                k.box(cw * i + 0.05, cw * (i + 1) - 0.05, -0.1, -0.04, h * (1 - f), h - 0.02, "machinery", skip=("yn",))


FITS = {"shutter": fit_shutter, "louvre": fit_louvre, "bars": fit_bars, "slits": fit_slits,
        "porthole": fit_porthole, "door": fit_door, "strip": fit_strip}


def spine(k, cx, cy, z0, z1, r=0.27, seg=1.6, mat="ceramic"):
    """Segmented vertebra column: tapered chitin segments with dark joints (silhouette stays opaque at distance)."""
    n = max(2, round((z1 - z0) / seg))
    hh = (z1 - z0) / n
    with k.look(0.93):
        for i in range(n):
            za = z0 + i * hh + 0.03
            k.frustum(cx, cy, za, za + hh - 0.1, r * 0.74, r * 0.74, r, r, mat)
        k.box(cx - r * 0.5, cx + r * 0.5, cy - r * 0.5, cy + r * 0.5, z0, z1, "steel")


def cornice(k, bx, z, h=0.22, out=0.3, mat="ceramic"):
    x0, x1, y0, y1 = bx
    with k.look(0.9):
        k.box(x0 - out, x1 + out, y1 - 0.1, y1 + out, z, z + h, mat)
        k.box(x0 - out, x1 + out, y0 - out, y0 + 0.1, z, z + h, mat)
        k.box(x0 - out, x0 + 0.1, y0, y1, z, z + h, mat)
        k.box(x1 - 0.1, x1 + out, y0, y1, z, z + h, mat)


def module(k, bx, z0, z1, rng, windows, t=0.75, armor=True, corner=True, akw=None, extra_excl=None):
    """Habitation module: pressure shell with deep recessed openings, layered armour, corner pilasters, cornices."""
    x0, x1, y0, y1 = bx
    k.box(x0 + t, x1 - t, y0 + t, y1 - t, z0, z1, "steel")
    for side in "FBLR":
        L = face_len(side, bx)
        a, b = (0.0, L) if side in "FB" else (t, L - t)
        wl = Wall(k, a, b, z0, z1, t)
        for kind, xa, xb, za, zb, kw in windows.get(side, []):
            wl.hole(xa, xb, za, zb, FITS[kind], **kw)
        with face_frame(k, side, bx):
            with k.part(".windows"):
                wl.build(rng)
            if armor:
                ex = wl.excl(0.3) + list((extra_excl or {}).get(side, []))
                with k.part(".armor"):
                    armor_field(k, a, b, z0 + 0.25, z1 - 0.22, ex, rng, y=0.0, **(akw or {}))
    if corner:
        for cx, cy, sx, sy in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
            spine(k, cx + 0.12 * sx, cy + 0.12 * sy, z0, z1, 0.27)
    if z0 <= PZ + 0.01:
        cornice(k, bx, z0, 0.2, 0.25)
    cornice(k, bx, z1 - 0.2, 0.2, 0.3)


# ---------------------------------------------------------------------------- reusable props (workshop / services)

DRUM_TONES = CURTAIN_TONES + [(0.5, 0.5, 0.52), (0.35, 0.38, 0.45)]


def truss(k, x0, x1, y0, y1, z0, z1, n, chord=0.22, mat="machinery"):
    ym = (y0 + y1) / 2
    k.box(x0, x1, y0, y1, z0, z0 + chord, mat)
    k.box(x0, x1, y0, y1, z1 - chord, z1, mat)
    dx = (x1 - x0) / n
    for i in range(n + 1):
        xx = x0 + i * dx
        k.box(xx - 0.07, xx + 0.07, ym - 0.09, ym + 0.09, z0 + chord, z1 - chord, "steel")
    for i in range(n):
        a, b = z0 + chord, z1 - chord
        if i % 2:
            a, b = b, a
        k.beam((x0 + i * dx, ym, a), (x0 + (i + 1) * dx, ym, b), 0.18, 0.08, mat)


def hazard_floor(k, x0, x1, y0, y1, z, n=10, vertical=False):
    """Alternating slanted hazard bars laid flat on the floor (xy plane)."""
    w = ((y1 - y0) if vertical else (x1 - x0)) / n
    for i in range(0, n, 2):
        if vertical:
            a = y0 + i * w
            pts = [(x0, a), (x1, a + w * 0.9), (x1, a + w * 1.6), (x0, a + w * 0.7)]
            pts = [(px, min(py, y1)) for px, py in pts]
        else:
            a = x0 + i * w
            pts = [(a, y0), (a + w, y0), (a + w * 1.5, y1), (a + w * 0.5, y1)]
            pts = [(min(px, x1), py) for px, py in pts]
        with k.look(0.95, (1.0, 0.85, 0.5)):
            k.prism(pts, z, z + 0.03, "trim", "xy")


def drum(k, x, y, z, rng, r=0.3, h=0.9):
    with k.look(0.8, rng.choice(DRUM_TONES)):
        k.cyl(x, y, z, r, h, "machinery", seg=6)
    k.cyl(x, y, z + h * 0.55, r * 1.05, 0.05, "steel", seg=6, caps=False)


def crate(k, x, y, z, w, d, h, rng, mat="machinery"):
    with k.look(0.85, rng.choice(CURTAIN_TONES)):
        k.box(x, x + w, y, y + d, z, z + h, mat)


def gas_bottle(k, x, y, z=0.0, tone=(0.5, 0.6, 0.7)):
    with k.look(0.85, tone):
        with k.at(x, y, z):
            k.lathe([(0.1, 0), (0.1, 1.15), (0.06, 1.3), (0, 1.34)], "machinery", 6, True)
    k.box(x - 0.025, x + 0.025, y - 0.025, y + 0.025, z + 1.3, z + 1.42, "steel", skip=("zn",))


def rack(k, x, y, w, d, h, rng, shelves=4, items=True):
    for sx in (x, x + w - 0.05):
        for sy in (y, y + d - 0.05):
            k.box(sx, sx + 0.05, sy, sy + 0.05, 0, h, "steel", skip=("zn",))
    for i in range(shelves):
        zz = 0.25 + i * (h - 0.35) / max(1, shelves - 1)
        k.box(x, x + w, y, y + d, zz, zz + 0.04, "machinery")
        if items:
            cx = x + 0.08
            while cx < x + w - 0.3:
                cw = rng.uniform(0.3, 0.7)
                ch = rng.uniform(0.15, 0.4)
                if rng.random() < 0.45 and cx + cw < x + w - 0.04:
                    crate(k, cx, y + 0.06, zz + 0.04, cw, d - 0.12, min(ch, (h - 0.35) / max(1, shelves - 1) - 0.1), rng)
                cx += cw + rng.uniform(0.02, 0.2)


def workbench(k, x0, x1, y, rng, depth=0.8, wall_y=None):
    k.box(x0, x1, y, y + depth, 0.88, 0.95, "machinery")
    for sx in (x0 + 0.05, x1 - 0.1):
        k.box(sx, sx + 0.06, y + 0.05, y + depth - 0.1, 0, 0.88, "steel", skip=("zn",))
    k.box(x0 + 0.05, x1 - 0.05, y + 0.05, y + depth - 0.05, 0.25, 0.3, "steel")
    k.box(x0 + 0.2, x0 + 0.4, y + 0.1, y + 0.28, 0.95, 1.12, "machinery")
    k.box(x0 + 0.26, x0 + 0.34, y + 0.28, y + 0.45, 1.0, 1.06, "steel")
    k.box(x1 - 0.8, x1 - 0.45, y + 0.1, y + 0.5, 0.95, 1.08, "steel")
    if wall_y is not None:
        k.box(x0 + 0.05, x1 - 0.05, wall_y, wall_y + 0.04, 1.2, 2.2, "cavity")
        x = x0 + 0.15
        while x < x1 - 0.3:
            h = rng.uniform(0.25, 0.7)
            k.box(x, x + rng.uniform(0.03, 0.08), wall_y + 0.04, wall_y + 0.09, 2.1 - h, 2.1, "steel", skip=("yn",))
            x += rng.uniform(0.22, 0.4)


def gantry(k, xa, xb, y0, y1, z, yb, rng, hook_z=2.6):
    """Overhead travelling crane: two runway beams, bridge, trolley, chain, hook. Returns the hook x."""
    for xx in (xa, xb):
        k.box(xx - 0.18, xx + 0.18, y0, y1, z, z + 0.42, "machinery")
        k.box(xx - 0.3, xx + 0.3, y0, y1, z + 0.38, z + 0.46, "steel")
    k.box(xa, xb, yb - 0.25, yb + 0.25, z - 0.38, z, "machinery")
    k.box(xa, xb, yb - 0.04, yb + 0.04, z - 0.5, z - 0.38, "steel")
    for xx in (xa, xb):
        k.box(xx - 0.3, xx + 0.3, yb - 0.4, yb + 0.4, z - 0.12, z + 0.0, "steel")
    hx = (xa + xb) / 2 + rng.uniform(-1.2, 1.2)
    k.box(hx - 0.35, hx + 0.35, yb - 0.3, yb + 0.3, z - 0.78, z - 0.38, "steel")
    k.box(hx - 0.1, hx + 0.1, yb - 0.1, yb + 0.1, z - 0.9, z - 0.78, "trim")
    k.box(hx - 0.02, hx + 0.02, yb - 0.02, yb + 0.02, hook_z, z - 0.9, "steel")
    k.box(hx - 0.07, hx + 0.07, yb - 0.07, yb + 0.07, hook_z - 0.2, hook_z, "trim")
    return hx


def ribbed_pod(k, cx, y0, y1, cz, R, rng, split):
    """Engine pod on display: plated nose half and a ribs-only cutaway tail with core, stringers and tendon."""
    L = y1 - y0
    with k.at(cx, y0, cz, rx=-pi / 2):
        # nose shell (local z along +y world)
        with k.look(0.85):
            k.lathe([(0.45 * R, 0.0), (R * 0.96, 0.18 * L), (R, split * L * 0.5), (R, split * L)], "ceramic", 10, True)
        for f in (0.1, 0.3, 0.55, 0.8):
            zz = split * L * f
            k.lathe([(R * 1.05, zz), (R * 1.05, zz + 0.07)], "steel", 10, False)
        n = 4
        for i in range(n):
            zz = split * L + (L * (1 - split)) * (i + 0.5) / n
            k.lathe([(R, zz - 0.045), (R, zz + 0.045), (R * 0.9, zz + 0.045), (R * 0.9, zz - 0.045)], "machinery", 8, False)
        for a in range(8):
            th = 2 * pi * a / 8
            if cos(th) < 0.6:  # keep the cutaway side (towards +x of the pod) open to view the core
                continue
            pass
        for a in range(6):
            th = pi * 0.15 + pi * 1.7 * a / 5
            k.beam((R * 0.95 * cos(th), R * 0.95 * sin(th), split * L), (R * 0.95 * cos(th), R * 0.95 * sin(th), L), 0.06, 0.06, "steel")
        k.cyl(0, 0, split * L, R * 0.42, L * (1 - split) - 0.15, "machinery", seg=8)
        for rr in (R * 0.43,):
            for zz in (split * L + 0.25, split * L + 0.65, split * L + 1.05):
                k.lathe([(rr, zz), (rr * 1.15, zz), (rr * 1.15, zz + 0.12), (rr, zz + 0.12)], "steel", 8, False)
        for a in (0.5, 1.9, 3.3):
            k.pipe((R * 0.35 * cos(a), R * 0.35 * sin(a), split * L + 0.1), (R * 0.2 * cos(a + 1), R * 0.2 * sin(a + 1), L + 0.25), 0.05, "sinew", 5)


def cradle(k, x, y, r, rng):
    k.box(x - r - 0.3, x + r + 0.3, y - 0.2, y + 0.2, 0, 0.2, "machinery")
    for sx in (-1, 1):
        k.beam((x + sx * (r + 0.1), y, 0.2), (x + sx * (r * 0.55), y, 0.2 + r * 0.8), 0.25, 0.14, "steel")
        k.box(x + sx * r * 0.55 - 0.12, x + sx * r * 0.55 + 0.12, y - 0.2, y + 0.2, 0.2 + r * 0.8 - 0.05, 0.2 + r * 0.8 + 0.06, "trim")


def conduit_bank(k, x, y, z0, z1, n, r, rng, axis="z", mat="machinery"):
    for i in range(n):
        dx = (i - (n - 1) / 2) * r * 2.4
        tone = rng.choice(DRUM_TONES)
        with k.look(0.82, tone):
            if axis == "z":
                k.pipe((x + dx, y, z0), (x + dx, y, z1), r, mat, 6)
            else:
                k.pipe((x, y + dx, z0), (x, y + dx, z1), r, mat, 6)


# ---------------------------------------------------------------------------- the building

PZ = 7.4  # podium roof / terrace level
BAY_A = (-13.5, -3.5, 5.8)
BAY_B = (-0.5, 7.5, 4.8)
AIR = (10.4, 12.4, 2.6)
PBOX = (-15.0, 15.0, -10.0, 10.0)


def part_podium(k, rng):
    """Dark pressure-hull podium with two deep repair bays and the human airlock."""
    with k.part("podium_hull"):
        # rear core with the breach notch cut into the left-rear flank (x -15..-13.6, y -9.3..-4.0, z 0.8..7.0)
        k.box(-13.6, 15, -10, 2, 0, PZ, "steel")
        k.box(-15, -13.6, -10, -9.3, 0, PZ, "steel")
        k.box(-15, -13.6, -4.0, 2, 0, PZ, "steel")
        k.box(-15, -13.6, -9.3, -4.0, 0, 0.8, "steel")
        k.box(-15, -13.6, -9.3, -4.0, 7.0, PZ, "steel")
        for a, b in ((-15, BAY_A[0]), (BAY_A[1], BAY_B[0]), (BAY_B[1], AIR[0]), (AIR[1], 15)):
            k.box(a, b, 2, 10, 0, PZ, "steel")
        k.box(AIR[0], AIR[1], 2, 7.0, 0, PZ, "steel")
        k.box(AIR[0], AIR[1], 7.0, 10, AIR[2], PZ, "steel")
        k.box(BAY_A[0], BAY_A[1], 2, 9.3, BAY_A[2], PZ, "steel")
        k.box(BAY_B[0], BAY_B[1], 2, 9.3, BAY_B[2], PZ, "steel")
        with k.look(0.7):
            k.box(BAY_A[0], BAY_A[1], 2, 10.5, 0, 0.1, "machinery")
            k.box(BAY_B[0], BAY_B[1], 2, 10.5, 0, 0.1, "machinery")
    with k.part("podium_front_armor"):
        ex = [(BAY_A[0] - 0.35, BAY_A[1] + 0.35, -1, PZ + 1), (BAY_B[0] - 0.35, BAY_B[1] + 0.35, -1, PZ + 1),
              (AIR[0] - 0.7, AIR[1] + 0.7, -1, 3.6)]
        with k.at(0, 10, 0):
            armor_field(k, -15, 15, 0.0, PZ - 0.2, ex, rng, y=0.0, cov=0.9, miss=0.08, repair=0.1, max_rib=2)
    with k.part("podium_lintels"):
        for (xa, xb, top), n in ((BAY_A, 6), (BAY_B, 5)):
            truss(k, xa - 0.2, xb + 0.2, 9.45, 10.15, top, PZ, n, 0.25, "machinery")
            with k.look(0.9):
                k.box(xa - 0.35, xb + 0.35, 9.4, 10.35, PZ - 0.02, PZ + 0.25, "ceramic")
                k.box(xa - 0.35, xa + 0.15, 9.4, 10.3, 0.0, top + 0.25, "ceramic")
                k.box(xb - 0.15, xb + 0.35, 9.4, 10.3, 0.0, top + 0.25, "ceramic")
        r2 = random.Random(5)
        with k.at(0, 10.36, 0):
            stencil(k, "A1", -9.4, 6.2, 0.1, rng=r2, y=0.0)
        with k.at(0, 10.27, 0):
            pass
    bay_a(k, rng)
    bay_b(k, rng)
    airlock(k, rng)


def bay_a(k, rng):
    xa, xb, top = BAY_A
    with k.part("bay_a"):
        for xx in (-11.6, -5.4):
            k.box(xx - 0.07, xx + 0.07, 2.2, 12.2, 0.1, 0.18, "steel")
        hazard_floor(k, xa, xb, 10.1, 10.6, 0.1, 14)
        # side ribs, conduit and wall fittings
        for sx, sgn in ((xa, 1), (xb, -1)):
            for yy in (3.2, 5.6, 8.0):
                k.box(sx if sgn > 0 else sx - 0.45, sx + 0.45 if sgn > 0 else sx, yy, yy + 0.4, 0.1, top, "steel")
            for zz, r in ((1.2, 0.1), (4.8, 0.14)):
                k.pipe((sx + sgn * 0.05, 2.2, zz), (sx + sgn * 0.05, 9.4, zz), r, "machinery", 6)
        k.box(xb - 0.12, xb, 3.2, 4.4, 1.4, 2.4, "machinery")
        k.box(xb - 0.16, xb - 0.12, 3.35, 3.7, 1.9, 2.1, "glow_cyan")
        k.box(xa, xa + 0.14, 5.2, 5.9, 1.2, 2.5, "machinery")
        # back wall: internal blast door, racks, benches, bottles
        k.box(-10.3, -7.2, 2.0, 2.18, 0.1, 3.5, "cavity")
        k.box(-10.5, -7.0, 2.1, 2.3, 3.4, 3.65, "trim", skip=("yn",))
        hazard_floor(k, -10.5, -7.0, 2.3, 2.9, 0.1, 6)
        rack(k, xa + 0.15, 2.1, 2.5, 0.65, 2.9, rng, 3)
        workbench(k, xb - 3.2, xb - 0.35, 2.1, rng, 0.8, wall_y=2.02)
        for i, xx in enumerate((-12.4, -12.1, -11.8)):
            gas_bottle(k, xx, 4.4 if i != 1 else 4.7, 0.1, rng.choice(CURTAIN_TONES))
        k.beam((-12.6, 4.2, 0.9), (-11.6, 4.2, 0.9), 0.02, 0.02, "steel")
        drum(k, -4.6, 3.6, 0.1, rng)
        crate(k, -13.1, 6.0, 0.1, 0.9, 0.7, 0.7, rng)
        # the pod on display: plated nose, cutaway tail, cradles
        ribbed_pod(k, -8.5, 3.4, 8.2, 1.85, 1.25, rng, 0.45)
        cradle(k, -8.5, 4.4, 1.25, rng)
        cradle(k, -8.5, 7.4, 1.25, rng)
        # inspection pit with grating
        k.box(-12.2, -11.0, 3.6, 8.4, 0.1, 0.13, "cavity")
        for yy in [3.7 + 0.45 * i for i in range(10)]:
            k.box(-12.2, -11.0, yy, yy + 0.04, 0.12, 0.17, "steel", skip=("zn",))
        # ceiling: beams, gantry, spreader and slings
        for yy in (3.3, 5.3, 7.3, 9.1):
            k.box(xa, xb, yy, yy + 0.3, top - 0.45, top, "machinery")
        hx = gantry(k, xa + 0.35, xb - 0.35, 2.4, 9.6, top - 0.45, 5.9, rng, hook_z=3.5)
        k.box(-9.7, -7.3, 5.5, 6.3, 3.3, 3.5, "steel")
        for sx in (-9.4, -7.6):
            k.beam((sx, 5.9, 3.3), (-8.5 + (sx + 8.5) * 0.7, 5.9, 2.95), 0.05, 0.05, "steel")
        k.beam((-8.5, 5.9, 3.5), (-8.5, 5.9, 4.9), 0.04, 0.04, "steel")
        for xx, yy in ((-12.0, 4.0), (-5.4, 6.5), (-7.0, 8.9)):
            k.box(xx - 0.01, xx + 0.01, yy - 0.01, yy + 0.01, 4.45, top - 0.45, "steel")
            k.box(xx - 0.12, xx + 0.12, yy - 0.12, yy + 0.12, 4.2, 4.45, "machinery")
            k.box(xx - 0.07, xx + 0.07, yy - 0.07, yy + 0.07, 4.12, 4.2, "glow_amber", skip=("zp",))
        # roll shutter: lowered 1.35 m, ragged bottom bar, guide rails and housing
        with k.look(0.8, (0.62, 0.7, 0.8)):
            k.box(xa + 0.2, xb - 0.2, 9.5, 9.64, top - 1.4, top - 0.1, "machinery")
        for i in range(6):
            zz = top - 0.3 - i * 0.22
            k.box(xa + 0.2, xb - 0.2, 9.64, 9.68, zz - 0.03, zz + 0.03, "machinery", skip=("yn",))
        k.box(xa + 0.15, xb - 0.15, 9.45, 9.72, top - 1.55, top - 1.4, "steel")
        x = xa + 0.4
        while x < xb - 0.6:
            tw = rng.uniform(0.2, 0.5)
            k.box(x, x + tw, 9.5, 9.7, top - 1.7, top - 1.55, "steel", skip=("zp",))
            x += tw + rng.uniform(0.15, 0.7)
        for sx in (xa, xb - 0.25):
            k.box(sx, sx + 0.25, 9.3, 10.1, 0.1, top, "machinery")
        k.box(xa, xb, 9.3, 10.2, top - 0.35, top, "machinery")
        for xx in (-12.6, -4.4):
            k.cyl(xx, 10.9, 0.1, 0.16, 0.9, "trim", seg=6)
            k.box(xx - 0.2, xx + 0.2, 10.7, 11.1, 0.0, 0.1, "steel")
        k.box(-8.8, -8.2, 10.05, 10.2, 5.45, 5.65, "glow_amber", skip=("yp", "zp"))


def bay_b(k, rng):
    xa, xb, top = BAY_B
    with k.part("bay_b"):
        for xx in (1.4, 5.6):
            k.box(xx - 0.07, xx + 0.07, 2.2, 12.2, 0.1, 0.18, "steel")
        hazard_floor(k, xa, xb, 10.1, 10.6, 0.1, 12)
        for sx, sgn in ((xa, 1), (xb, -1)):
            for yy in (3.0, 5.4, 7.8):
                k.box(sx if sgn > 0 else sx - 0.4, sx + 0.4 if sgn > 0 else sx, yy, yy + 0.35, 0.1, top, "steel")
            k.pipe((sx + sgn * 0.05, 2.2, 3.3), (sx + sgn * 0.05, 9.4, 3.3), 0.12, "machinery", 6)
            pipe_run(k, [(sx + sgn * 0.12, 2.3, 0.6), (sx + sgn * 0.12, 2.3, 2.2), (sx + sgn * 0.12, 4.4, 2.2)], 0.07, "trim")
        # back wall: tool wall, compressor, tyre stack, drums, rack
        rack(k, xa + 0.2, 2.1, 2.4, 0.6, 2.7, rng, 3)
        k.box(xa + 2.9, xa + 5.6, 2.02, 2.06, 1.1, 2.9, "cavity")
        xx = xa + 3.0
        while xx < xa + 5.5:
            hh = rng.uniform(0.3, 0.9)
            k.box(xx, xx + rng.uniform(0.04, 0.09), 2.06, 2.11, 2.7 - hh, 2.7, "steel", skip=("yn",))
            xx += rng.uniform(0.2, 0.42)
        with k.at(xb - 1.6, 2.9, 0.75, ry=pi / 2):
            k.lathe([(0, -0.8), (0.4, -0.7), (0.4, 0.7), (0, 0.8)], "machinery", 8, True)
        k.box(xb - 1.9, xb - 1.3, 2.4, 2.5, 0.1, 0.6, "steel")
        k.cyl(xb - 1.6, 2.9, 1.1, 0.07, 0.25, "steel", seg=5)
        k.box(xb - 1.65, xb - 1.55, 2.55, 2.6, 1.3, 1.4, "glow_cyan")
        with k.look(0.5):
            k.cyl(xa + 3.2, 3.2, 0.1, 0.5, 0.56, "machinery", seg=8)
            k.cyl(xa + 3.2, 3.2, 0.66, 0.5, 0.3, "machinery", seg=8)
        drum(k, xa + 4.2, 3.4, 0.1, rng)
        drum(k, xa + 4.6, 3.1, 0.1, rng)
        # crawler chassis on a two-post lift
        for sx in (xa + 1.2, xb - 1.2):
            k.box(sx - 0.2, sx + 0.2, 5.0, 5.4, 0.1, 3.2, "machinery")
            k.box(sx - 0.3, sx + 0.3, 4.9, 5.5, 0.1, 0.2, "steel")
        k.box(xa + 0.9, xb - 0.9, 5.15, 5.25, 1.55, 1.6, "steel")
        for sx in (xa + 1.5, xb - 1.5):
            k.box(sx - 0.14, sx + 0.14, 3.0, 8.2, 1.6, 1.9, "machinery")
            for yy in (3.5, 4.7, 5.9, 7.1, 7.9):
                with k.look(0.45):
                    k.cyl(sx - 0.2, yy, 1.4, 0.38, 0.4, "machinery", axis="x", seg=8)
            k.box(sx - 0.2, sx + 0.2, 3.0, 8.2, 1.04, 1.12, "steel")
        for yy in (3.2, 4.8, 6.4, 8.0):
            k.box(xa + 1.5, xb - 1.5, yy, yy + 0.16, 1.7, 1.9, "steel")
        k.box(xa + 2.4, xb - 2.4, 3.2, 4.7, 1.9, 2.9, "machinery")
        for sx in (xa + 2.4, xb - 2.4):
            k.pipe((sx, 3.4, 2.9), (sx, 3.4, 3.6), 0.08, "steel", 5)
        for sx, sy in ((xa + 2.2, 6.0), (xb - 2.2, 6.0), (xa + 2.2, 8.0), (xb - 2.2, 8.0)):
            column(k, sx, sy, 1.9, 3.6, 0.1, "machinery")
        k.box(xa + 2.1, xb - 2.1, 5.9, 8.1, 3.55, 3.62, "steel")
        # monorail hoist
        k.box(xa + 0.2, xb - 0.2, 6.7, 6.95, top - 0.5, top - 0.05, "machinery")
        hx = rng.uniform(2.0, 4.0)
        k.box(hx - 0.3, hx + 0.3, 6.65, 7.0, top - 1.0, top - 0.5, "steel")
        k.box(hx - 0.015, hx + 0.015, 6.81, 6.84, 3.0, top - 1.0, "steel")
        k.box(hx - 0.1, hx + 0.1, 6.74, 6.9, 2.85, 3.0, "trim")
        # ceiling ducts and lamps
        for yy in (3.2, 5.2, 8.9):
            k.box(xa, xb, yy, yy + 0.28, top - 0.4, top, "machinery")
        k.pipe((xa, 3.6, top - 0.6), (xb, 3.6, top - 0.6), 0.2, "steel", 8)
        for xx, yy in ((1.2, 8.0), (4.6, 8.4)):
            k.box(xx - 0.01, xx + 0.01, yy - 0.01, yy + 0.01, top - 0.9, top - 0.4, "steel")
            k.box(xx - 0.12, xx + 0.12, yy - 0.12, yy + 0.12, top - 1.0, top - 0.9, "machinery")
            k.box(xx - 0.06, xx + 0.06, yy - 0.06, yy + 0.06, top - 1.04, top - 1.0, "glow_amber", skip=("zp",))
        # roll drum (door fully raised), guides, hanging chain loop
        k.cyl(xa, 9.65, top - 0.38, 0.28, xb - xa, "machinery", axis="x", seg=8)
        for xx in (xa + 1.0, xa + 4.0, xb - 1.0):
            k.cyl(xx, 9.65, top - 0.38, 0.33, 0.1, "steel", axis="x", seg=8)
        for sx in (xa, xb - 0.2):
            k.box(sx, sx + 0.2, 9.3, 10.1, 0.1, top, "machinery")
        k.box(1.58, 1.62, 9.9, 9.94, top - 1.75, top - 0.55, "steel")
        k.box(1.4, 1.8, 9.88, 9.96, top - 1.95, top - 1.75, "trim")
        k.box(-0.8, 7.8, 10.0, 10.5, 0.0, 0.1, "steel")
        for xx in (0.3, 6.9):
            k.cyl(xx, 10.9, 0.1, 0.16, 0.9, "trim", seg=6)


def airlock(k, rng):
    """Human-scale pressure door set into the podium: ceramic collar, open outer hatch, inner dogged door."""
    x0, x1, zt = AIR
    w = x1 - x0
    with k.part("airlock"):
        with k.look(0.9):
            k.box(x0 - 0.5, x0, 9.9, 10.45, 0, zt + 0.7, "ceramic")
            k.box(x1, x1 + 0.5, 9.9, 10.45, 0, zt + 0.7, "ceramic")
            k.box(x0 - 0.5, x1 + 0.5, 9.9, 10.45, zt, zt + 0.7, "ceramic")
        k.box(x0, x1, 7.0, 10, 0, 0.1, "machinery")
        hazard_floor(k, x0 + 0.1, x1 - 0.1, 9.0, 10.3, 0.1, 6)
        for i in range(4):  # chamber ribs
            yy = 7.4 + i * 0.7
            k.box(x0, x0 + 0.1, yy, yy + 0.15, 0.1, zt, "machinery")
            k.box(x1 - 0.1, x1, yy, yy + 0.15, 0.1, zt, "machinery")
        # inner pressure door with dogwheel
        k.box(x0 + 0.1, x1 - 0.1, 6.95, 7.12, 0.1, zt - 0.15, "machinery")
        k.box(x0 + 0.2, x1 - 0.2, 7.12, 7.2, 0.4, zt - 0.4, "cavity")
        with k.at((x0 + x1) / 2, 7.2, 1.3, rx=-pi / 2):
            k.lathe([(0.26, 0.0), (0.26, 0.05), (0.22, 0.05), (0.22, 0.0)], "trim", 8, False)
            for a in (0, pi / 2):
                with k.at(0, 0, 0.0, rz=a):
                    k.box(-0.25, 0.25, -0.02, 0.02, 0, 0.05, "trim")
        k.box(x0 + 0.1, x1 - 0.1, 7.12, 7.16, zt - 0.35, zt - 0.25, "glow_cyan", skip=("yn",))
        # outer hatch swung open against the right jamb
        with k.at(x1 + 0.02, 10.05, 0.0, rz=-0.9):
            k.box(0.0, 0.1, 0.0, w - 0.05, 0.1, zt - 0.05, "machinery")
            k.box(0.1, 0.16, 0.12, w - 0.17, 0.3, zt - 0.3, "steel")
            k.box(0.1, 0.18, w - 0.35, w - 0.25, 1.0, 1.3, "trim")
        # lamp, label plate and stencil
        k.box(x0 + w / 2 - 0.06, x0 + w / 2 + 0.06, 10.45, 10.55, zt + 0.45, zt + 0.55, "glow_amber")
        k.box(x0 + 0.3, x0 + w - 0.3, 10.45, 10.5, zt + 0.12, zt + 0.42, "cavity")
        with k.at(0, 10.5, 0):
            stencil(k, "AIR3", x0 + 0.38, zt + 0.17, 0.045, rng=rng)
        k.box(x0 - 0.5, x1 + 0.5, 10.2, 10.6, 0, 0.18, "ceramic")
        for sx in (x0 - 0.7, x1 + 0.7):
            k.cyl(sx, 10.95, 0.0, 0.1, 1.0, "trim", seg=6)


def cloth(k, x0, x1, z0, z1, y, rng):
    with k.look(0.9, rng.choice(CURTAIN_TONES)):
        k.box(x0, x1, y, y + 0.025, z0, z1, "trim", skip=("yn",))


def hang_line(k, p0, p1, sag, n, r, mat="steel"):
    """Catenary-ish cable between two points."""
    p0, p1 = Vector(p0), Vector(p1)
    pts = []
    for i in range(n + 1):
        t = i / n
        p = p0 + (p1 - p0) * t
        p.z -= sag * 4 * t * (1 - t)
        pts.append(p)
    for a, b in zip(pts[:-1], pts[1:]):
        k.pipe(a, b, r, mat, 4)
    return pts


def part_terrace(k, rng):
    """Roof terrace over the bays: perimeter parapet, scuppers, market stall, laundry, tank, the S2 stair."""
    with k.part("terrace"):
        with k.look(0.9):
            for xa, xb in ((-15, -6.2), (8.2, 15)):
                k.box(xa, xb, 9.6, 10.1, PZ, PZ + 0.95, "ceramic")
                k.box(xa - 0.05, xb + 0.05, 9.5, 10.2, PZ + 0.95, PZ + 1.08, "machinery")
            k.box(-15, -14.6, -10, 9.6, PZ, PZ + 0.6, "ceramic")
            k.box(14.6, 15, -10, 9.6, PZ, PZ + 0.6, "ceramic")
            k.box(-15, 15, -10, -9.6, PZ, PZ + 0.6, "ceramic")
        railing(k, (-6.2, 9.85, PZ), (8.2, 9.85, PZ), 1.05, 1.6)
        for xx in (-5.4, 3.2, 9.6):
            k.pipe((xx, 10.1, PZ + 0.45), (xx, 10.55, PZ + 0.45), 0.09, "steel", 6, True)
        # downpipes from scuppers, tied to the piers
        pipe_run(k, [(-2.0, 10.45, PZ + 0.5), (-2.0, 10.45, 3.0), (-2.5, 10.45, 2.4), (-2.5, 10.45, 0.25)], 0.1, "machinery")
        pipe_run(k, [(9.0, 10.45, PZ + 0.4), (9.0, 10.45, 0.25)], 0.09, "machinery")
        for zz in (1.2, 3.6, 5.8):
            for xx in (-2.0, 9.0):
                k.box(xx - 0.12, xx + 0.12, 10.1, 10.45, zz - 0.04, zz + 0.04, "steel")
        # market stall
        k.box(-12.2, -8.6, 7.0, 8.0, PZ, PZ + 0.95, "machinery")
        k.box(-12.2, -8.6, 7.0, 8.0, PZ + 0.95, PZ + 1.02, "steel")
        for sx in (-12.2, -8.65):
            k.box(sx, sx + 0.05, 8.0, 8.05, PZ + 0.95, PZ + 2.6, "steel", skip=("zn",))
            k.box(sx, sx + 0.05, 6.35, 6.4, PZ + 0.95, PZ + 2.3, "steel", skip=("zn",))
        with k.at(-12.4, 6.3, PZ + 2.3, rx=-0.28):
            with k.look(0.9, (0.95, 0.5, 0.42)):
                k.box(0, 3.9, 0, 1.8, 0, 0.05, "trim")
            for i in range(8):
                k.box(i * 0.5 + 0.02, i * 0.5 + 0.2, 1.8, 1.86, -0.12, 0.0, "trim", skip=("yn",))
        for xx in (-11.4, -9.6):
            crate(k, xx, 7.15, PZ + 1.02, 0.5, 0.45, 0.28, rng)
        k.box(-11.0, -10.2, 7.3, 7.7, PZ + 1.02, PZ + 1.3, "machinery")
        k.box(-10.7, -10.5, 7.45, 7.55, PZ + 1.3, PZ + 1.34, "glow_cyan")
        for xx in (-11.6, -9.2):
            k.pipe((xx, 7.5, PZ + 2.28), (xx, 7.5, PZ + 1.85), 0.01, "steel", 4)
            k.box(xx - 0.07, xx + 0.07, 7.43, 7.57, PZ + 1.78, PZ + 1.85, "glow_amber")
        # laundry line, tank on legs, benches, drums, reels
        for xx in (4.8, 8.6):
            k.box(xx - 0.04, xx + 0.04, 8.9, 9.0, PZ, PZ + 2.4, "steel", skip=("zn",))
        hang_line(k, (4.8, 8.95, PZ + 2.3), (8.6, 8.95, PZ + 2.3), 0.12, 6, 0.012)
        for i, xx in enumerate((5.1, 5.9, 6.7, 7.5)):
            cloth(k, xx, xx + 0.5, PZ + 1.3 + 0.1 * (i % 2), PZ + 2.28, 8.93, rng)
        for lx, ly in ((12.8, 8.0), (14.0, 8.0)):
            k.cyl(lx, ly, PZ + 0.8, 0.5, 1.2, "machinery", seg=8)
            for sx, sy in ((-0.38, -0.38), (0.38, -0.38), (-0.38, 0.38), (0.38, 0.38)):
                k.box(lx + sx - 0.03, lx + sx + 0.03, ly + sy - 0.03, ly + sy + 0.03, PZ, PZ + 0.85, "steel", skip=("zn",))
        pipe_run(k, [(12.8, 8.0, PZ + 2.0), (12.8, 8.0, PZ + 2.5), (12.8, 9.9, PZ + 2.5), (12.8, 9.9, PZ + 0.5)], 0.07, "machinery")
        for xx in (-6.0, 1.0):
            k.box(xx, xx + 1.2, 6.6, 6.9, PZ + 0.4, PZ + 0.45, "machinery")
            for sx in (xx + 0.1, xx + 1.0):
                k.box(sx, sx + 0.05, 6.6, 6.9, PZ, PZ + 0.4, "steel", skip=("zn",))
        for i in range(2):
            drum(k, 13.6 + 0.35 * (i % 2), 4.1 + 0.6 * i, PZ, rng)
        with k.at(-4.2, 6.5, PZ):
            k.lathe([(0.45, 0.0), (0.45, 0.12), (0.12, 0.12), (0.12, 0.6), (0.45, 0.6), (0.45, 0.72)], "machinery", 8, True)
        # hanging service cables from the module face to the parapet
        hang_line(k, (-14.0, 6.0, PZ + 3.2), (-6.0, 6.0, PZ + 3.9), 0.35, 8, 0.018)
    with k.part("stair_front"):
        top = stair(k, (-2.0, 8.4, PZ), -pi / 2, 3.9, 2.75, 1.0, rise=0.21)
        deck(k, 1.9, 4.5, 5.8, 9.6, 10.15, "machinery", joists=True)
        for sx, sy in ((4.3, 9.4), (2.1, 9.4), (4.3, 6.1)):
            column(k, sx, sy, PZ, 10.0, 0.2, "steel")
        xbrace(k, (2.1, 9.45, PZ + 0.1), (4.3, 9.45, 9.6), (4.3, 9.45, PZ + 0.1), (2.1, 9.45, 9.6))
        railing(k, (1.9, 9.6, 10.15), (4.5, 9.6, 10.15), 1.05, 1.3)
        railing(k, (4.5, 9.6, 10.15), (4.5, 5.9, 10.15), 1.05, 1.3)
        top2 = stair(k, (4.1, 6.8, 10.15), pi / 2, 3.9, 2.75, 1.0, rise=0.21)
        column(k, 2.0, 6.7, PZ, 11.5, 0.16, "steel")
        k.beam((2.0, 6.7, 11.5), (1.5, 7.4, 11.0), 0.06, 0.06, "steel")


def part_left_stair(k, rng):
    """Zig-zag exterior stair up the left flank with landings, columns, cross-bracing and wall ties."""
    with k.part("stair_left"):
        stair(k, (-16.6, 9.0, 0.0), pi, 8.0, 3.7, 1.2, rise=0.185)
        deck(k, -19.0, -15.2, -3.4, 1.0, 3.7, "machinery")
        stair(k, (-18.2, -3.0, 3.7), 0.0, 8.0, 3.7, 1.2, rise=0.185)
        deck(k, -19.0, -15.0, 5.0, 8.8, PZ, "machinery")
        for sx, sy in ((-18.8, -3.2), (-15.4, -3.2), (-18.8, 0.8), (-15.4, 0.8)):
            column(k, sx, sy, 0.0, 3.6, 0.22, "steel")
        for sx, sy in ((-18.8, 5.2), (-15.4, 8.6), (-18.8, 8.6)):
            column(k, sx, sy, 0.0, PZ - 0.2, 0.22, "steel")
        xbrace(k, (-18.8, -3.4, 0.2), (-15.4, -3.4, 3.4), (-15.4, -3.4, 0.2), (-18.8, -3.4, 3.4))
        xbrace(k, (-18.8, 8.8, 0.2), (-18.8, 5.2, PZ - 0.4), (-18.8, 5.2, 0.2), (-18.8, 8.8, PZ - 0.4))
        xbrace(k, (-18.8, 0.9, 0.2), (-18.8, -3.3, 3.4), (-18.8, -3.3, 0.2), (-18.8, 0.9, 3.4))
        for yy in (-3.3, 0.9):
            k.box(-19.0, -15.0, yy - 0.06, yy + 0.06, 3.5, 3.66, "steel")
        # mid-flight posts under both flights
        for yy, h in ((4.2, 2.0), (6.6, 1.0)):
            for sx in (-16.0, -17.2):
                column(k, sx, yy, 0.0, h, 0.14, "steel")
        for yy, z0 in ((1.6, 5.4), (-0.4, 4.6)):
            for sx in (-17.6, -18.8):
                column(k, sx, yy, 0.0, z0, 0.14, "steel")
        for z in (3.6, 7.3):
            k.beam((-19.0, 2.2, z - 0.1), (-15.0, 2.2, z - 0.1), 0.1, 0.1, "steel")
        railing(k, (-19.0, -3.4, 3.7), (-19.0, 1.0, 3.7), 1.05, 1.5)
        railing(k, (-19.0, -3.4, 3.7), (-15.2, -3.4, 3.7), 1.05, 1.5)
        railing(k, (-19.0, 5.0, PZ), (-19.0, 8.8, PZ), 1.05, 1.5)
        railing(k, (-19.0, 8.8, PZ), (-15.0, 8.8, PZ), 1.05, 1.5)
        # ties into the podium wall
        for yy, z in ((-3.3, 3.5), (0.9, 3.5), (5.2, 7.2), (8.6, 7.2)):
            k.box(-19.0, -14.9, yy - 0.07, yy + 0.07, z - 0.12, z, "machinery")
        for yy in (-3.3, 0.9):
            k.box(-15.2, -14.95, yy - 0.2, yy + 0.2, 3.1, 4.3, "steel")
        k.box(-15.15, -15.0, -1.6, -1.4, 5.2, 5.5, "glow_amber")
    with k.part("podium_side_stencil"):
        with k.at(-15.0, 4.4, 0.0, rz=pi / 2):
            stencil(k, "07-C", 0.2, 5.4, 0.1, rng=rng, y=0.0)


def part_modules(k, rng):
    """Three stacked, stepped habitation modules (M1 over the podium, M2 set back, M3 cantilevered right)."""
    M1 = (-14.0, 7.5, -7.0, 5.8)
    M2 = (-10.0, 4.5, -5.0, 3.4)
    M3 = (-3.0, 9.5, -3.5, 4.2)
    z1, z2, z3, z4 = PZ, 12.9, 18.4, 22.6

    def f(x, d):  # design x on a facade -> local x on that face
        return x + d

    with k.part("module_m1"):
        W = {
            "F": [("shutter", f(-13, 14), f(-9.8, 14), 8.4, 9.9, dict(frac=0.5)),
                  ("door", f(-8.7, 14), f(-7.7, 14), PZ, 9.5, {}),
                  ("strip", f(-6.6, 14), f(-3.4, 14), 8.5, 9.8, dict(cells=3)),
                  ("shutter", f(4.6, 14), f(6.8, 14), 8.5, 9.8, dict(frac=0.8)),
                  ("porthole", f(-12.8, 14), f(-12.0, 14), 11.2, 12.0, {}),
                  ("porthole", f(-11.6, 14), f(-10.8, 14), 11.2, 12.0, {}),
                  ("louvre", f(-9.3, 14), f(-6.9, 14), 11.0, 12.3, {}),
                  ("shutter", f(-5.9, 14), f(-3.1, 14), 10.9, 12.3, dict(frac=0.3)),
                  ("door", f(2.9, 14), f(3.9, 14), 10.15, 12.2, {})],
            "L": [("strip", 1.4, 4.0, 8.5, 9.8, dict(cells=2)),
                  ("shutter", 6.6, 8.8, 8.5, 9.9, dict(frac=0.4)), ("slits", 4.6, 5.6, 11.0, 12.3, {})],
            "B": [("door", 1.2, 2.2, PZ, 9.5, {}), ("shutter", 3.6, 6.0, 8.4, 9.9, dict(frac=0.65)),
                  ("louvre", 7.6, 12.4, 8.3, 10.2, {}), ("strip", 13.6, 17.0, 8.5, 9.8, dict(cells=3)),
                  ("shutter", 4.4, 7.0, 11.0, 12.3, dict(frac=0.5))],
            "R": [("door", 1.6, 2.6, PZ, 9.5, {}), ("shutter", 4.0, 6.5, 8.5, 9.9, dict(frac=0.45)),
                  ("louvre", 3.0, 5.0, 11.0, 12.3, {})],
        }
        module(k, M1, z1, z2, rng, W, akw=dict(cov=0.86, miss=0.06, repair=0.1, max_rib=2, cw=(2.5, 4.6), rows=(1.2, 2.0)))
    with k.part("module_m2"):
        W = {
            "F": [("strip", f(-9, 10), f(-2.6, 10), 14.1, 16.2, dict(cells=6)),
                  ("shutter", f(-1.5, 10), f(1.2, 10), 14.0, 15.6, dict(frac=0.6)),
                  ("door", f(2.4, 10), f(3.4, 10), z2, 15.0, {}),
                  ("louvre", f(-8.5, 10), f(-6.5, 10), 16.6, 17.9, {}),
                  ("porthole", f(-5.6, 10), f(-4.8, 10), 16.9, 17.7, {})],
            "L": [("shutter", 1.6, 4.0, 14.0, 15.5, dict(frac=0.5)), ("slits", 5.2, 6.4, 14.0, 16.0, {})],
            "B": [("strip", 1.6, 5.0, 14.0, 15.5, dict(cells=3)), ("door", 6.2, 7.2, z2, 15.0, {}),
                  ("shutter", 2.0, 4.6, 16.6, 17.9, dict(frac=0.35))],
            "R": [("shutter", 1.4, 3.6, 14.0, 15.4, dict(frac=0.7)), ("porthole", 2.2, 3.0, 16.8, 17.6, {})],
        }
        module(k, M2, z2, z3, rng, W, t=0.7, akw=dict(cov=0.84, miss=0.08, repair=0.1, max_rib=2, cw=(2.5, 4.6), rows=(1.2, 2.0)))
    with k.part("module_m3"):
        W = {
            "F": [("strip", f(-2.0, 3), f(3.4, 3), 19.5, 21.4, dict(cells=5)),
                  ("shutter", f(4.4, 3), f(7.4, 3), 19.4, 21.2, dict(frac=0.35))],
            "L": [("shutter", 1.4, 3.4, 19.4, 21.0, dict(frac=0.55))],
            "B": [("strip", 2.0, 6.0, 19.4, 21.0, dict(cells=3)), ("louvre", 7.4, 10.0, 19.4, 21.6, {})],
            "R": [("door", 1.2, 2.2, z3, 20.5, {}), ("shutter", 3.6, 6.0, 19.4, 21.0, dict(frac=0.3))],
        }
        module(k, M3, z3, z4, rng, W, t=0.7, akw=dict(cov=0.82, miss=0.08, repair=0.1, max_rib=2, cw=(2.5, 4.6), rows=(1.2, 2.0)))
    with k.part("module_support"):
        # M3 cantilever: heavy diagonal struts, underside girders, corbels
        for yy in (3.2, -2.4):
            k.beam((6.6, yy, z2), (8.9, yy, z3 - 0.2), 0.34, 0.3, "steel")
            k.beam((7.1, yy, z2 + 0.9), (7.1 + 1.7, yy, z2 + 2.4), 0.2, 0.18, "machinery")
            k.box(6.4, 7.8, yy - 0.3, yy + 0.3, z2, z2 + 0.25, "machinery")
            k.box(8.5, 9.4, yy - 0.3, yy + 0.3, z3 - 0.5, z3, "ceramic")
        for xx in (5.2, 6.8, 8.4):
            k.box(xx - 0.12, xx + 0.12, -3.5, 4.2, z3 - 0.35, z3, "machinery")
        k.pipe((4.6, -3.0, z3 - 0.6), (9.4, -3.0, z3 - 0.6), 0.14, "machinery", 6)
        k.pipe((4.6, 3.6, z3 - 0.6), (9.4, 3.6, z3 - 0.6), 0.12, "machinery", 6)
        # M1-roof gallery G2: cantilevered lip with brackets and rails
        deck(k, -13.6, 5.0, 5.8, 7.0, z2, "machinery", joists=False)
        for xx in [-13.0 + 2.4 * i for i in range(8)]:
            k.beam((xx, 5.8, z2 - 1.5), (xx, 7.0, z2 - 0.15), 0.1, 0.1, "steel")
            k.box(xx - 0.05, xx + 0.05, 5.8, 5.85, z2 - 1.5, z2 - 1.3, "steel")
        railing(k, (-13.6, 7.0, z2), (-0.3, 7.0, z2), 1.05, 1.6)
        railing(k, (1.0, 7.0, z2), (5.0, 7.0, z2), 1.05, 1.6)
        railing(k, (-13.6, 5.8, z2), (-13.6, 7.0, z2), 1.05, 1.2)
        railing(k, (5.0, 5.8, z2), (5.0, 7.0, z2), 1.05, 1.2)


def valve(k, x, y, z, r=0.2, side=1.0):
    """Gate valve on a vertical pipe: fat body, stem and a hand-wheel."""
    k.cyl(x, y, z, r * 1.6, 0.42, "steel", seg=6)
    k.box(min(x + side * r, x + side * (r + 0.28)), max(x + side * r, x + side * (r + 0.28)), y - 0.03, y + 0.03, z + 0.18, z + 0.24, "steel", skip=("yn", "yp"))
    with k.at(x + side * (r + 0.3), y, z + 0.21, ry=pi / 2):
        k.lathe([(0.2, 0), (0.2, 0.04), (0.16, 0.04), (0.16, 0)], "trim", 6, False)


def gauge(k, x, y, z, lit=True):
    k.cyl(x, y, z, 0.1, 0.1, "steel", axis="y", seg=6)
    if lit:
        k.box(x - 0.025, x + 0.025, y + 0.1, y + 0.13, z - 0.03, z + 0.03, "glow_cyan", skip=("yn",))


def tank_horizontal(k, cx, y0, y1, r, z, rng):
    """Bullet tank on saddles, axis along y."""
    L = y1 - y0
    with k.at(cx, y0, z, rx=-pi / 2):
        k.lathe([(0, -0.0), (r * 0.7, 0.12), (r, 0.45), (r, L - 0.45), (r * 0.7, L - 0.12), (0, L)], "machinery", 8, False)
    for yy in (y0 + L * 0.2, y0 + L * 0.8):
        k.box(cx - r * 0.9, cx + r * 0.9, yy - 0.12, yy + 0.12, 0.0, z - r * 0.45, "steel")
    k.box(cx - 0.12, cx + 0.12, (y0 + y1) / 2 - 0.12, (y0 + y1) / 2 + 0.12, z + r, z + r + 0.25, "steel")


def canister(k, x, y, z0, H, r, seg=7):
    """Filter canister: flanged foot, banded barrel, collar and domed head."""
    with k.at(x, y, z0):
        k.lathe([(r * 1.2, 0.0), (r * 1.2, 0.3), (r, 0.3), (r, H - 0.9), (r * 1.12, H - 0.9), (r * 1.12, H - 0.7),
                 (r * 0.9, H - 0.7), (r * 0.9, H - 0.3), (r * 0.4, H), (0, H + 0.12)], "machinery", seg, True)
    for zz in (z0 + H * 0.33, z0 + H * 0.64):
        with k.at(x, y, zz):
            k.lathe([(r * 1.08, 0.0), (r * 1.08, 0.14)], "steel", seg, False)


def part_filter_tower(k, rng):
    """Life-support filtration tower on the right deck: canister bank, manifolds, ladder cage, catwalk, valves."""
    cx = 12.3
    with k.part("filter_tower"):
        k.box(9.8, 14.8, -3.8, 3.8, PZ, PZ + 0.5, "machinery")
        for y, H in ((-2.4, 10.2), (0.3, 13.6), (2.8, 11.8)):
            canister(k, cx, y, PZ + 0.5, H, 1.0)
        canister(k, 14.1, 0.3, PZ + 0.5, 16.0, 0.52, 6)
        with k.at(14.1, 0.3, PZ + 16.4):
            k.lathe([(0.7, 0.0), (0.7, 0.2), (0.35, 0.55)], "steel", 6, True)
        # manifolds linking the canisters and feeding the building
        pipe_run(k, [(10.9, -2.4, 9.2), (10.9, 2.8, 9.2)], 0.2, "machinery", 2.6)
        pipe_run(k, [(10.9, 0.3, 9.2), (10.9, 0.3, 8.3), (9.4, 0.3, 8.3), (7.35, 0.3, 8.3)], 0.17, "machinery", 2.0)
        pipe_run(k, [(13.7, -2.4, 13.4), (13.7, 2.8, 13.4)], 0.16, "machinery", 2.6)
        pipe_run(k, [(10.9, 2.8, 9.2), (10.9, 3.4, 9.2), (10.9, 3.4, 12.8), (8.9, 3.4, 12.8)], 0.14, "trim", 3.0)
        for zz in (11.6, 15.8):
            k.pipe((cx - 0.9, -2.4, zz), (cx - 0.9, 0.3, zz), 0.08, "steel", 5)
            k.pipe((cx - 0.9, 0.3, zz), (cx - 0.9, 2.8, zz), 0.08, "steel", 5)
        valve(k, 10.9, -1.0, 8.6, 0.2, -1.0)
        valve(k, 10.9, 1.5, 8.6, 0.2, -1.0)
        gauge(k, 10.5, 0.3, 11.0)
        gauge(k, 10.5, -2.4, 10.2)
        gauge(k, 10.5, 2.8, 14.0)
        # sealed wall penetration with collar
        with k.at(7.5, 0.3, 8.3, ry=pi / 2):
            k.lathe([(0.34, 0), (0.34, 0.14)], "steel", 6, False)
        # caged ladder up the front, catwalk ring at 12.9 and the M3 bridge platform at 18.4
        for sx in (11.5, 12.3):
            k.box(sx - 0.03, sx + 0.03, 4.1, 4.2, PZ + 0.5, 12.9, "steel", skip=("yn", "yp", "zn"))
        for i in range(14):
            zz = PZ + 0.9 + i * 0.37
            k.box(11.5, 12.3, 4.13, 4.17, zz, zz + 0.03, "steel", skip=("yn", "yp", "xn", "xp"))
        for zz in (9.4, 10.8, 12.2):
            with k.at(11.9, 4.15, zz, rx=-pi / 2):
                k.lathe([(0.55, 0), (0.55, 0.04)], "steel", 6, False)
        deck(k, 9.9, 14.4, -3.9, 4.0, 12.9, "machinery", joists=False)
        railing(k, (9.9, 4.0, 12.9), (14.4, 4.0, 12.9), 1.05, 1.5)
        railing(k, (14.4, -3.9, 12.9), (14.4, 4.0, 12.9), 1.05, 1.5)
        railing(k, (9.9, -3.9, 12.9), (14.4, -3.9, 12.9), 1.05, 1.5)
        for sy in (-3.9, 4.0):
            k.beam((9.9, sy, 12.0), (10.7, sy, 12.9), 0.08, 0.08, "steel")
        deck(k, 9.4, 13.6, 1.4, 4.1, 18.4, "machinery", joists=False)
        railing(k, (9.4, 1.4, 18.4), (13.6, 1.4, 18.4), 1.05, 1.5)
        railing(k, (13.6, 1.4, 18.4), (13.6, 4.1, 18.4), 1.05, 1.4)
        railing(k, (9.4, 4.1, 18.4), (13.6, 4.1, 18.4), 1.05, 1.5)
        for sy in (1.5, 4.0):
            k.beam((9.6, sy, 17.0), (10.4, sy, 18.3), 0.08, 0.08, "steel")
        for sx in (13.4,):
            k.beam((sx, 4.0, 17.2), (sx, 4.0, 18.3), 0.08, 0.08, "steel")
        k.box(10.1, 10.5, 4.1, 4.2, 18.4, 19.6, "steel", skip=("yn", "yp"))
        # tendon: no. Warning stencils and a lamp
        with k.at(0, 3.82, 0):
            stencil(k, "FLT", 10.2, PZ + 0.62, 0.06, rng=rng)
        k.box(11.8, 11.95, 3.82, 3.9, PZ + 1.2, PZ + 1.3, "glow_cyan")


def part_right_alley(k, rng):
    """Right flank service elevation: pressure tanks, riser manifold, catwalk, service door, armour."""
    with k.part("right_alley"):
        ex = [(1.4, 3.2, -1, 3.3), (13.0, 20.0, 6.0, 7.5)]
        with face_frame(k, "R", PBOX):
            armor_field(k, 0.0, 20.0, 0.3, PZ - 0.2, ex, rng, y=0.0, cov=0.7, miss=0.08, repair=0.12, cw=(2.4, 4.4))
        tank_horizontal(k, 16.5, 2.4, 6.2, 0.7, 0.85, rng)
        tank_horizontal(k, 16.5, -2.2, 1.6, 0.7, 0.85, rng)
        # riser manifold: three runs from the tanks up the wall, over the parapet and into the tower base
        for i, (yy, r) in enumerate(((3.6, 0.2), (-0.6, 0.17))):
            xx = 15.65 + 0.0 * i
            top = 8.35 + 0.15 * i
            pipe_run(k, [(16.5, yy, 1.5), (16.5, yy, 2.0), (xx, yy, 2.0), (xx, yy, top), (14.4, yy, top)], r,
                     "machinery", 2.6, "steel")
            for zz in (1.0, 3.0, 5.0, 6.6):
                if zz > 2.0:
                    k.box(14.95, xx - 0.05, yy - 0.05, yy + 0.05, zz - 0.04, zz + 0.04, "steel")
            valve(k, xx, yy, 3.4, r, 1.0)
            gauge(k, xx + 0.25, yy, 5.1)
        # tank-to-wall link and a drain
        k.pipe((16.5, 4.3, 1.5), (16.5, 4.3, 0.2), 0.07, "steel", 5)
        # catwalk with triangular brackets and a ladder to the ground
        deck(k, 15.0, 16.4, -9.0, -4.2, 3.6, "machinery", joists=False)
        for yy in (-8.6, -6.6, -4.6):
            k.beam((15.0, yy, 2.2), (16.35, yy, 3.5), 0.08, 0.1, "steel")
            k.box(14.95, 15.1, yy - 0.15, yy + 0.15, 2.1, 2.3, "steel")
        railing(k, (16.4, -9.0, 3.6), (16.4, -4.2, 3.6), 1.05, 1.6)
        railing(k, (15.0, -9.0, 3.6), (16.4, -9.0, 3.6), 1.05, 1.4)
        for sy in (-3.8, -4.4):
            k.box(15.55, 15.62, sy, sy + 0.04, 0.0, 3.6, "steel", skip=("zn",))
        for i in range(9):
            zz = 0.3 + i * 0.4
            k.box(15.55, 15.62, -4.4, -3.8, zz, zz + 0.03, "steel", skip=("zn", "xn", "xp"))
        # proud service door with canopy and hazard sill
        k.box(15.0, 15.18, 5.8, 7.0, 0.0, 2.3, "machinery")
        k.box(15.18, 15.24, 5.95, 6.85, 0.1, 2.15, "cavity")
        with k.look(0.9):
            k.box(15.0, 15.4, 5.6, 5.8, 0.0, 2.6, "ceramic")
            k.box(15.0, 15.4, 7.0, 7.2, 0.0, 2.6, "ceramic")
            k.box(15.0, 15.4, 5.6, 7.2, 2.3, 2.6, "ceramic")
        k.box(15.35, 15.45, 6.3, 6.5, 2.65, 2.8, "glow_amber")
        hazard_floor(k, 15.2, 16.0, 5.8, 7.0, 0.0, 6, True)
        with k.at(15.0, 0.0, 0.0, rz=-pi / 2):
            stencil(k, "SVC 7", 3.1, 1.2, 0.06, rng=rng, y=0.0)


def part_rear_service(k, rng):
    """Rear service elevation: loading hatch, fan/louvre wall, cable tray, meter cabinet, caged ladder, freight lift."""
    with k.part("rear_service"):
        with face_frame(k, "B", PBOX):
            ex = [(10.8, 14.8, -1, 3.4), (16.0, 24.2, 2.1, 6.4), (6.6, 9.4, 0.9, 3.2), (24.8, 27.0, -1, 3.6)]
            armor_field(k, 0.0, 30.0, 0.3, PZ - 0.2, ex, rng, y=0.0, cov=0.68, miss=0.08, repair=0.12, cw=(2.4, 4.4))
        # loading hatch (design x 0.5..4): frame, half-raised curtain, coil housing, dock bumpers
        with k.at(2.25, -10.0, 0.0, rz=pi):
            with k.look(0.9):
                k.box(-2.05, -1.85, 0.0, 0.4, 0.0, 3.2, "ceramic")
                k.box(1.85, 2.05, 0.0, 0.4, 0.0, 3.2, "ceramic")
                k.box(-2.05, 2.05, 0.0, 0.4, 3.0, 3.35, "ceramic")
            k.box(-1.85, 1.85, 0.05, 0.12, 0.0, 3.0, "cavity")
            with k.look(0.85, (0.62, 0.7, 0.8)):
                k.box(-1.8, 1.8, 0.1, 0.2, 1.5, 3.0, "machinery")
            for i in range(5):
                k.box(-1.8, 1.8, 0.2, 0.24, 1.7 + i * 0.26, 1.76 + i * 0.26, "machinery", skip=("yn", "xn", "xp"))
            k.box(-1.85, 1.85, 0.08, 0.28, 1.4, 1.5, "steel")
            k.cyl(0, 0.3, 3.15, 0.2, 3.5, "steel", axis="x", seg=6)  # coil housing seen above
            k.box(-1.9, 1.9, 0.0, 1.5, 0.0, 0.5, "machinery", skip=("zn", "yn"))
            for sx in (-1.6, 1.6):
                k.box(sx - 0.15, sx + 0.15, 1.5, 1.8, 0.2, 1.1, "steel")
            stencil(k, "LOAD 2", -0.8, 3.45, 0.07, rng=rng, y=0.0)
        # fan / louvre wall (design x -13.5..-6.5, z 2.4..6.2)
        with k.at(-10.0, -10.0, 0.0, rz=pi):
            k.box(-3.7, 3.7, 0.0, 0.22, 2.3, 6.3, "machinery")
            k.box(-3.5, 3.5, 0.22, 0.28, 2.5, 6.1, "cavity")
            for i in range(9):
                zz = 2.55 + i * 0.37
                with k.at(0, 0.24, zz, rx=-0.5):
                    k.box(-3.5, 3.5, 0.0, 0.03, 0.0, 0.34, "machinery", skip=("xn", "xp", "zn"))
            for fx in (-1.7, 1.7):
                with k.at(fx, 0.3, 4.3, rx=-pi / 2):
                    k.lathe([(1.25, 0), (1.25, 0.55), (1.05, 0.55), (1.05, 0)], "steel", 8, False)
                    k.lathe([(0.2, 0.12), (0.2, 0.4)], "machinery", 6, True)
                    for a in range(5):
                        with k.at(0, 0, 0.28, rz=a * 2 * pi / 5):
                            k.box(0.15, 1.0, -0.1, 0.1, -0.02, 0.02, "steel", skip=("xn",))
                k.box(fx - 1.3, fx + 1.3, 0.1, 0.58, 4.3 - 0.04, 4.3 + 0.04, "steel")
                k.box(fx - 0.04, fx + 0.04, 0.1, 0.58, 3.0, 5.6, "steel")
        # cable tray with drops, meter cabinet, dumpster, drums
        k.box(-15.0, 15.0, -10.45, -10.0, 6.35, 6.5, "machinery", skip=("yp",))
        for xx in (-15.0, -9.0, -3.0, 3.0, 9.0, 15.0):
            k.box(xx - 0.05, xx + 0.05, -10.45, -10.0, 6.0, 6.35, "steel", skip=("zp",))
        for i, tone in enumerate(((0.8, 0.45, 0.4), (0.5, 0.5, 0.55), (0.9, 0.7, 0.3))):
            with k.look(0.9, tone):
                k.pipe((-15 + 0.0, -10.3 - 0.05 * i, 6.55), (15, -10.3 - 0.05 * i, 6.55), 0.035, "sinew" if i == 0 else "machinery", 4)
        for xx in (8.6, 9.2):
            k.pipe((xx, -10.3, 6.5), (xx, -10.3, 3.2), 0.04, "machinery", 4)
        k.box(7.0, 10.0, -10.5, -10.0, 1.1, 3.0, "machinery")
        k.box(7.1, 9.9, -10.55, -10.5, 1.2, 2.9, "steel")
        for i in range(5):
            k.box(7.35 + i * 0.5, 7.5 + i * 0.5, -10.58, -10.55, 2.55, 2.62, "glow_cyan" if i % 2 else "glow_amber")
        crate(k, 12.0, -11.8, 0.0, 1.6, 1.0, 1.1, rng)
        k.box(11.9, 13.7, -11.9, -10.7, 1.1, 1.18, "steel")
        for i, xx in enumerate((-5.9, -5.4)):
            drum(k, xx, -10.9 - 0.2 * (i % 2), 0.0, rng)
        # caged ladder (design x 5.5) to the rear deck
        for sx in (5.2, 5.8):
            k.box(sx - 0.03, sx + 0.03, -10.45, -10.38, 0.0, PZ + 1.0, "steel", skip=("zn", "xn", "xp"))
        for i in range(13):
            zz = 0.3 + i * 0.57
            k.box(5.2, 5.8, -10.45, -10.4, zz, zz + 0.03, "steel", skip=("zn", "xn", "xp", "yn"))
        for zz in (2.6, 4.6, 6.6):
            with k.at(5.5, -10.75, zz, rx=-pi / 2):
                k.lathe([(0.5, 0), (0.5, 0.04)], "steel", 6, False)
        # freight lift: guide posts, car with gate, counterweight, machine room
        lx0, lx1, ly0, ly1 = -5.0, -1.8, -12.6, -10.6
        for sx in (lx0, lx1):
            for sy in (ly0, ly1):
                column(k, sx, sy, 0.0, 15.0, 0.22, "steel")
        for z in (7.4, 14.8):
            k.box(lx0, lx1, ly0 - 0.06, ly0 + 0.06, z - 0.08, z + 0.08, "machinery")
            k.box(lx0 - 0.06, lx0 + 0.06, ly0, ly1, z - 0.08, z + 0.08, "machinery")
            k.box(lx1 - 0.06, lx1 + 0.06, ly0, ly1, z - 0.08, z + 0.08, "machinery")
        k.beam((lx0, ly0 - 0.1, 7.5), (lx1, ly0 - 0.1, 11.0), 0.06, 0.06, "steel")
        k.beam((lx0, ly0 - 0.1, 11.0), (lx1, ly0 - 0.1, 7.5), 0.06, 0.06, "steel")
        k.box(lx0 + 0.15, lx1 - 0.15, ly0 + 0.2, ly1 - 0.1, 5.2, 5.35, "machinery")
        railing(k, (lx0 + 0.15, ly0 + 0.2, 5.35), (lx1 - 0.15, ly0 + 0.2, 5.35), 1.2, 1.5, toe=False)
        railing(k, (lx0 + 0.15, ly0 + 0.2, 5.35), (lx0 + 0.15, ly1 - 0.1, 5.35), 1.2, 1.5, toe=False)
        railing(k, (lx1 - 0.15, ly0 + 0.2, 5.35), (lx1 - 0.15, ly1 - 0.1, 5.35), 1.2, 1.5, toe=False)
        k.box(lx0 + 0.15, lx1 - 0.15, ly0 + 0.2, ly1 - 0.1, 6.6, 6.65, "steel")
        for sx in (lx0 + 0.4, lx1 - 0.4):
            k.box(sx - 0.015, sx + 0.015, ly0 + 0.5, ly0 + 0.53, 6.65, 14.9, "steel")
        k.box(lx1 + 0.1, lx1 + 0.55, ly0 + 0.2, ly0 + 0.7, 8.0, 12.0, "machinery")
        k.box(lx0 - 0.3, lx1 + 0.3, ly0 - 0.3, ly1 + 0.3, 15.0, 16.3, "machinery")
        with k.look(0.9):
            k.box(lx0 - 0.4, lx1 + 0.4, ly0 - 0.4, ly1 + 0.4, 16.3, 16.6, "ceramic")
        with k.at((lx0 + lx1) / 2, ly0 + 0.5, 16.0, rz=0.0, ry=pi / 2):
            k.lathe([(0.5, -0.1), (0.5, 0.1)], "steel", 8, True)
        k.box(lx1 - 0.2, lx1 - 0.1, ly1 + 0.28, ly1 + 0.36, 15.4, 15.6, "glow_amber")
        # duct riser up the M1/M2 rear with collars, feeding the vent bank
        k.box(-2.0, -1.0, -8.2, -7.4, PZ, 16.2, "machinery")
        for z in (8.4, 10.4, 12.4, 14.4):
            k.box(-2.12, -0.88, -8.32, -7.28, z, z + 0.14, "steel")
        k.box(-3.2, -2.0, -8.0, -7.5, 8.9, 9.8, "machinery")
        k.box(-1.0, 0.2, -8.0, -7.5, 13.4, 14.2, "machinery")


def part_damage(k, rng):
    """The one breached service duct: torn armour lips, exposed ribs, tendon intrusion confined to this patch."""
    with k.part("damage_breach"):
        # exposed C-ribs inside the notch cut into the hull (x -15..-13.6, y -9.3..-4.0, z 0.8..7.0)
        k.box(-13.9, -13.6, -9.3, -4.0, 0.8, 7.0, "cavity")
        for i in range(6):
            yy = -9.0 + i * 0.95
            k.box(-14.85, -13.9, yy - 0.07, yy + 0.07, 0.8, 7.0, "machinery")
            k.box(-14.85, -14.7, yy - 0.22, yy + 0.22, 0.8, 7.0, "machinery")
        for zz in (2.3, 4.2, 6.0):
            k.box(-14.85, -13.9, -9.3, -4.0, zz - 0.06, zz + 0.06, "steel")
        # torn armour lips (face L: local x = y + 10)
        with face_frame(k, "L", PBOX):
            r = random.Random(11)
            for a, b, za, zb in ((0.2, 1.7, 6.9, 7.3), (1.3, 3.2, 7.0, 7.3), (3.9, 6.2, 7.0, 7.3), (0.35, 0.85, 1.0, 6.9),
                                 (5.9, 6.5, 1.2, 6.8), (0.3, 2.4, 0.3, 0.85), (3.4, 6.4, 0.3, 0.85)):
                with k.look(0.82):
                    k.plate(chip_poly(r, a, b, za, zb, 0.3), 0.0, 0.34, "ceramic", yt=0.12)
            # a plate peeled off and hanging by one bolt
            with k.at(1.2, 0.0, 6.9, rx=0.0):
                k.plate([(0.0, 0.0), (1.5, 0.1), (1.35, -1.4), (0.1, -1.0)], 0.0, 0.5, "ceramic", yt=0.2)
        # burst duct stub with torn collar
        k.pipe((-13.7, -6.6, 3.4), (-15.9, -6.6, 3.4), 0.42, "machinery", 8)
        for a in range(5):
            th = a * 2 * pi / 5 + 0.3
            k.beam((-15.9, -6.6 + 0.4 * cos(th), 3.4 + 0.4 * sin(th)), (-16.5, -6.6 + 0.75 * cos(th), 3.4 + 0.75 * sin(th)), 0.14, 0.04, "steel")
        # tendons: a bundle that boils out of the duct and drapes down / across the ribs, branching
        tr = random.Random(23)
        mouth = Vector((-15.9, -6.6, 3.4))
        paths = []
        for i in range(7):
            th = i * 2 * pi / 7
            p = [mouth + Vector((0.0, 0.2 * cos(th), 0.2 * sin(th)))]
            drift = Vector((-tr.uniform(0.2, 0.7), tr.uniform(-1.6, 1.6), tr.uniform(-2.8, 0.5)))
            for j in range(1, 4):
                q = p[-1] + drift * (0.4 + 0.2 * j) / 1.3 + Vector((0, tr.uniform(-0.25, 0.25), tr.uniform(-0.3, 0.1) - 0.15 * j))
                q.x = max(q.x, -17.2)
                q.z = max(q.z, 0.15)
                p.append(q)
            paths.append(p)
        for i, p in enumerate(paths):
            r0 = 0.17 - 0.012 * i
            for j, (a, b) in enumerate(zip(p[:-1], p[1:])):
                k.pipe(a, b, max(0.04, r0 * (1 - j * 0.28)), "sinew", 5)
                k.joint(b.x, b.y, b.z, max(0.05, r0 * (1 - j * 0.28)) * 1.2, "sinew", 5)
        # fine tendrils creeping back across the ribs inside the notch
        for yy in (-8.4, -7.2, -5.4):
            hang_line(k, (-14.7, yy, 6.6), (-14.7, yy + 0.4, 2.5), 0.15, 4, 0.04, "sinew")
        for yy, z in ((-5.9, 4.4), (-7.9, 2.2)):
            k.pipe((-14.8, yy, z), (-14.8, yy - 0.6, z - 0.9), 0.05, "sinew", 4)
        # warning stencil and a work lamp rigged by repair crews
        k.box(-15.9, -15.6, -4.2, -4.0, 6.2, 6.5, "glow_amber")


def part_roof(k, rng):
    """Roof landscapes: M3 crown (dish, chimney, hatch), M2 plant, M1 tank deck, right-deck HVAC and skylights."""
    z4 = 22.6
    with k.part("roof_m3"):
        with k.look(0.9):
            k.box(-3.1, 9.6, -3.6, 4.3, z4, z4 + 0.6, "ceramic", skip=("zn",))
        k.box(-2.7, 9.2, -3.2, 3.9, z4 + 0.6, z4 + 0.7, "machinery")
        # dish on pedestal
        k.box(-1.5, -0.5, -1.2, -0.2, z4 + 0.7, z4 + 1.9, "machinery")
        with k.at(-1.0, -0.4, z4 + 2.6, rx=-0.9):
            k.lathe([(0.0, 0.0), (0.9, 0.15), (1.7, 0.6), (1.75, 0.65)], "ceramic", 8, True)
            k.pipe((0, 0, 0.0), (0, 0, 1.4), 0.05, "steel", 4)
            k.box(-0.08, 0.08, -0.08, 0.08, 1.4, 1.5, "glow_cyan")
        # chimney stack with bands and a sinew-free cap
        with k.at(6.8, -1.2, z4 + 0.7):
            k.lathe([(0.9, 0), (0.9, 0.5), (0.55, 0.5), (0.55, 5.2), (0.7, 5.2), (0.7, 5.5), (0.45, 5.5)], "steel", 8, True)
        for zz in (2.0, 3.6):
            with k.at(6.8, -1.2, z4 + 0.7 + zz):
                k.lathe([(0.62, 0), (0.62, 0.16)], "machinery", 8, False)
        pipe_run(k, [(6.8, -0.6, z4 + 1.8), (6.8, 0.8, z4 + 1.8), (5.6, 0.8, z4 + 1.8), (5.6, 0.8, z4 + 0.7)], 0.16, "machinery", 2.0)
        # vent hoods, access hatch with rail, and a mast with a tiny beacon
        for hx, hy in ((2.4, 2.4), (4.0, 2.6)):
            k.box(hx - 0.5, hx + 0.5, hy - 0.4, hy + 0.4, z4 + 0.7, z4 + 1.3, "machinery")
            with k.at(hx, hy, z4 + 1.3, rx=0.0):
                k.prism([(-0.6, 0.0), (0.6, 0.0), (0.6, 0.2), (0.0, 0.55), (-0.6, 0.2)], -0.5, 0.5, "steel", "xz")
        k.box(-2.4, -1.0, 1.6, 3.0, z4 + 0.7, z4 + 1.05, "steel")
        k.box(-2.3, -1.1, 1.7, 2.9, z4 + 1.05, z4 + 1.12, "machinery")
        railing(k, (-2.6, 1.4, z4 + 0.7), (-0.8, 1.4, z4 + 0.7), 1.0, 1.2, toe=False)
        railing(k, (-2.6, 3.2, z4 + 0.7), (-0.8, 3.2, z4 + 0.7), 1.0, 1.2, toe=False)
        for a, b, c in ((-2.9, -3.0, 1.0), (8.9, 3.6, 1.0)):
            k.beam((a, b, z4 + 0.7), (a, b, z4 + 6.5), 0.08, 0.08, "steel")
        k.box(8.87, 8.93, 3.57, 3.63, z4 + 6.5, z4 + 6.62, "glow_cyan")
        k.beam((-2.9, -3.0, z4 + 3.5), (8.9, 3.6, z4 + 3.5), 0.03, 0.03, "steel")
    with k.part("roof_m2"):
        # M2 roof (z 18.4), x -10..-3 free of M3
        z3 = 18.4
        with k.look(0.9):
            k.box(-10.2, -3.0, -5.2, 3.6, z3, z3 + 0.45, "ceramic", skip=("zn",))
        for i, (sx, sy, h) in enumerate(((-8.8, -3.4, 2.6), (-7.4, -3.8, 3.2), (-6.0, -3.4, 2.2))):
            canister(k, sx, sy, z3 + 0.45, h, 0.4, 6)
        pipe_run(k, [(-8.8, -3.4, z3 + 2.4), (-8.8, -2.2, z3 + 2.4), (-6.0, -2.2, z3 + 2.4), (-6.0, -3.4, z3 + 2.0)], 0.1, "machinery", 2.5)
        k.box(-9.3, -6.5, -0.2, 1.6, z3 + 0.45, z3 + 1.5, "machinery")
        for i in range(5):
            xx = -9.1 + i * 0.5
            k.box(xx, xx + 0.08, -0.25, -0.2, z3 + 0.6, z3 + 1.4, "steel", skip=("yp",))
        with k.at(-5.2, 0.6, z3 + 0.45):
            k.lathe([(0.7, 0), (0.7, 0.9), (0.5, 0.9), (0.5, 1.4), (0.0, 1.7)], "steel", 8, True)
        # antenna lattice
        for dx, dy in ((-0.2, -0.2), (0.2, -0.2), (-0.2, 0.2), (0.2, 0.2)):
            k.beam((-4.2 + dx, 2.2 + dy, z3 + 0.45), (-4.2 + dx * 0.4, 2.2 + dy * 0.4, z3 + 6.2), 0.05, 0.05, "steel")
        for zz in (z3 + 1.8, z3 + 3.5, z3 + 5.2):
            k.box(-4.5, -3.9, 1.9, 2.5, zz, zz + 0.05, "steel")
        k.box(-4.25, -4.15, 2.15, 2.25, z3 + 6.2, z3 + 6.35, "glow_amber")
        with k.at(-4.2, 2.2, z3 + 4.4, rx=-1.2):
            k.lathe([(0.0, 0.0), (0.45, 0.12), (0.85, 0.4)], "ceramic", 6, True)
    with k.part("roof_m1"):
        # M1 roof (z 12.9): water tank on legs, radiators, ducts, stair hatch (areas outside M2)
        z2 = 12.9
        with k.at(-12.0, -2.8, z2 + 1.6):
            k.lathe([(0.0, 1.9), (0.95, 1.7), (1.25, 1.4), (1.25, 0.1), (1.0, 0.0)], "machinery", 8, True)
        for sx, sy in ((-0.85, -0.85), (0.85, -0.85), (-0.85, 0.85), (0.85, 0.85)):
            k.box(-12.0 + sx - 0.05, -12.0 + sx + 0.05, -2.8 + sy - 0.05, -2.8 + sy + 0.05, z2, z2 + 1.7, "steel", skip=("zn",))
        xbrace(k, (-12.85, -3.65, z2 + 0.1), (-11.15, -3.65, z2 + 1.5), (-11.15, -3.65, z2 + 0.1), (-12.85, -3.65, z2 + 1.5))
        pipe_run(k, [(-12.0, -2.8, z2 + 1.65), (-12.0, -2.8, z2 + 0.4), (-12.0, -5.0, z2 + 0.4), (-11.0, -5.0, z2 + 0.4)], 0.09, "machinery", 2.4)
        k.box(-13.6, -10.8, 0.2, 2.6, z2, z2 + 0.9, "machinery")
        for i in range(8):
            xx = -13.4 + i * 0.35
            k.box(xx, xx + 0.07, 2.6, 2.66, z2 + 0.1, z2 + 0.8, "steel", skip=("yn", "zn"))
        k.box(-9.8, -4.0, -6.6, -5.4, z2, z2 + 0.8, "machinery")
        with k.at(-8.0, -6.0, z2 + 0.8):
            k.lathe([(0.8, 0), (0.8, 0.12), (0.7, 0.12), (0.0, 0.2)], "steel", 8, True)
        k.box(5.0, 7.2, -5.0, -2.0, z2, z2 + 0.9, "machinery")
        k.box(5.1, 7.1, -4.9, -2.1, z2 + 0.9, z2 + 1.0, "steel")
        railing(k, (7.4, -6.8, z2), (7.4, 3.2, z2), 1.0, 1.9, toe=False)
    with k.part("roof_right_deck"):
        # right deck (z 7.4, x 7.5..14.6): skylight bank, HVAC units, cooling stack
        for yy in (-8.4, -6.2, -4.0):
            k.box(8.5, 11.0, yy, yy + 1.5, PZ, PZ + 0.5, "machinery")
            with k.at(8.5, yy, PZ + 0.5):
                k.prism([(0.0, 0.0), (1.5, 0.0), (1.5, 0.2), (0.75, 0.75), (0.0, 0.2)], 0.0, 2.5, "cavity", "yz")
        for hx, hy in ((9.0, 6.5), (11.4, 6.6)):
            k.box(hx - 0.9, hx + 0.9, hy - 0.7, hy + 0.7, PZ, PZ + 1.1, "machinery")
            with k.at(hx, hy, PZ + 1.1):
                k.lathe([(0.7, 0), (0.7, 0.1), (0.62, 0.1), (0.62, 0.0)], "steel", 8, False)
            for a in range(3):
                with k.at(hx, hy, PZ + 1.14, rz=a * pi / 3):
                    k.box(-0.62, 0.62, -0.04, 0.04, 0, 0.03, "steel", skip=("xn", "xp", "zn"))
        k.box(13.0, 14.4, -8.6, -6.0, PZ, PZ + 1.0, "steel")
        for i in range(6):
            xx = 13.1 + i * 0.22
            k.box(xx, xx + 0.07, -8.6, -6.0, PZ + 1.0, PZ + 1.9, "machinery", skip=("zn",))
        pipe_run(k, [(8.8, 6.5, PZ + 1.1), (8.8, 6.5, PZ + 2.2), (10.2, 6.5, PZ + 2.2), (10.2, 4.4, PZ + 2.2), (11.0, 4.4, PZ + 2.2)], 0.11,
                 "machinery", 2.2)


# @@PARTS@@


PART_FUNCS = [part_podium, part_terrace, part_left_stair, part_modules, part_filter_tower, part_right_alley,
              part_rear_service, part_damage, part_roof]  # @@LIST@@


def build_building(k):
    for fn in PART_FUNCS:
        fn(k, random.Random(fn.__name__))


# ---------------------------------------------------------------------------- materials, export, QA


def make_materials():
    mats = {}
    for name in SEM:
        base, rough, metal, emit = PBR[name]
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*base, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        if emit:
            bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
            bsdf.inputs["Emission Strength"].default_value = 2.0
        m.diffuse_color = (*base, 1.0)
        mats[name] = m
    return mats


def wire_vertex_colors(mats):
    """Preview only (after export): multiply Base Color by the mesh's COLOR_0 so Blender shows what Godot will."""
    for name, m in mats.items():
        if name in GLOWS:
            continue
        nt = m.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        base = tuple(bsdf.inputs["Base Color"].default_value)
        ca = nt.nodes.new("ShaderNodeVertexColor")
        ca.layer_name = "Col"
        mix = nt.nodes.new("ShaderNodeMixRGB")
        mix.blend_type = "MULTIPLY"
        mix.inputs["Fac"].default_value = 1.0
        mix.inputs["Color1"].default_value = base
        nt.links.new(ca.outputs["Color"], mix.inputs["Color2"])
        nt.links.new(mix.outputs["Color"], bsdf.inputs["Base Color"])


OFFSET = [0.0, 0.0, 0.0]  # Blender-space translation baked into the mesh by finalize()


def finalize(k, mats, coll):
    bm = k.bm
    me = bpy.data.meshes.new(ASSET_ID)
    bm.to_mesh(me)
    bm.free()
    # Bake a foot-centred origin: xz footprint centre at 0, lowest point at y=0 (glTF space; Blender y = -glTF z).
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    OFFSET[:] = [-(min(xs) + max(xs)) / 2, -(min(ys) + max(ys)) / 2, -min(zs)]
    me.transform(Matrix.Translation(Vector(OFFSET)))
    # The exporter writes the active/render colour attribute as COLOR_0; make "Col" both so it isn't left as COLOR_1.
    me.color_attributes.active_color = me.color_attributes["Col"]
    me.color_attributes.render_color_index = me.color_attributes.find("Col")
    for sem in SEM:
        me.materials.append(mats[sem])
    ob = bpy.data.objects.new(ASSET_ID, me)
    coll.objects.link(ob)
    return ob


def measure(ob):
    """Bounds in glTF space (Godot): x, y(up), z(-forward) from the evaluated mesh."""
    dg = bpy.context.evaluated_depsgraph_get()
    me = ob.evaluated_get(dg).to_mesh()
    pts = [(v.co.x, v.co.z, -v.co.y) for v in me.vertices]
    ob.evaluated_get(dg).to_mesh_clear()
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    return lo, hi, eval_counts(ob)


def export_glb(ob, path):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    want = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                export_cameras=False, export_lights=False, export_animations=False, export_normals=True,
                export_tangents=False, export_texcoords=False, export_materials="EXPORT", export_image_format="NONE",
                export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_colors=True, export_attributes=False, export_extras=False)
    have = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    bpy.ops.export_scene.gltf(**{key: v for key, v in want.items() if key in have})


def colour_stats(ob):
    me = ob.data
    att = me.color_attributes.get("Col")
    vals = [tuple(d.color) for d in att.data]
    lum = [(c[0] + c[1] + c[2]) / 3 for c in vals]
    return dict(corners=len(vals), min=round(min(lum), 3), mean=round(sum(lum) / len(lum), 3), max=round(max(lum), 3),
                distinct=len({tuple(round(x, 2) for x in c[:3]) for c in vals}))


# ---------------------------------------------------------------------------- reference human (never exported)


def build_human(coll, mats):
    k = Kit()
    k.stack = [Matrix.Identity(4)]
    k.box(-0.19, -0.02, -0.1, 0.1, 0.0, 0.85, "machinery")
    k.box(0.02, 0.19, -0.1, 0.1, 0.0, 0.85, "machinery")
    k.box(-0.24, 0.24, -0.14, 0.14, 0.85, 1.45, "trim")
    k.box(-0.38, -0.25, -0.08, 0.08, 0.85, 1.42, "trim")
    k.box(0.25, 0.38, -0.08, 0.08, 0.85, 1.42, "trim")
    k.cyl(0, 0, 1.45, 0.09, 0.1, "machinery", seg=6)
    with k.at(0, 0, 1.55):
        k.lathe([(0, 0.0), (0.12, 0.05), (0.12, 0.2), (0, 0.27)], "ceramic", 8, True)
    me = bpy.data.meshes.new("human_ref")
    k.bm.to_mesh(me)
    k.bm.free()
    for sem in SEM:
        me.materials.append(mats[sem])
    ob = bpy.data.objects.new("human_ref_1p75m", me)
    coll.objects.link(ob)
    return ob


# ---------------------------------------------------------------------------- studio renders


def pick_engine(scene):
    names = bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items.keys()
    scene.render.engine = next((e for e in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE") if e in names), "CYCLES")
    if scene.render.engine == "CYCLES":
        scene.cycles.samples = 32
    scene.view_settings.view_transform = "Standard"


class Studio:
    def __init__(s, scale=200.0):
        scene = bpy.context.scene
        s.scene = scene
        world = scene.world or bpy.data.worlds.new("studio")
        scene.world = world
        world.use_nodes = True
        bg = world.node_tree.nodes.get("Background")
        bg.inputs[0].default_value = (0.11, 0.115, 0.13, 1)
        bg.inputs[1].default_value = 1.0
        s.lights = []
        for name, d, energy in (("key", (-0.35, -0.75, -0.55), 4.2), ("fill", (0.7, -0.45, -0.5), 1.6),
                                ("rim", (0.1, 0.8, -0.35), 1.8)):
            ld = bpy.data.lights.new(name, "SUN")
            ld.energy = energy
            ld.angle = 0.05
            lo = bpy.data.objects.new(name, ld)
            scene.collection.objects.link(lo)
            s.lights.append((lo, Vector(d)))
        fm = bpy.data.materials.new("floor")
        fm.use_nodes = True
        fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.06, 0.062, 0.07, 1)
        fm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
        me = bpy.data.meshes.new("floor")
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=scale)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(fm)
        s.floor = bpy.data.objects.new("floor", me)
        s.floor.location.z = -0.03
        scene.collection.objects.link(s.floor)

    def aim(s, az):
        """Rotate the rig so the key lights the side being photographed (az = degrees about Z, 0 = facade)."""
        rot = Matrix.Rotation(math.radians(az), 3, "Z")
        for lo, d in s.lights:
            lo.rotation_euler = (rot @ d).to_track_quat("-Z", "Y").to_euler()

    def snap(s, path, loc, target, lens=45.0, ortho=None, res=(1280, 1280)):
        cd = bpy.data.cameras.new("cam")
        if ortho:
            cd.type = "ORTHO"
            cd.ortho_scale = ortho
        else:
            cd.lens = lens
        cd.clip_start, cd.clip_end = 0.1, 2000
        cam = bpy.data.objects.new("cam", cd)
        s.scene.collection.objects.link(cam)
        cam.location = loc
        cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        s.scene.camera = cam
        s.scene.render.resolution_x, s.scene.render.resolution_y = res
        s.scene.render.resolution_percentage = 100
        s.scene.render.image_settings.file_format = "PNG"
        s.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam)
        bpy.data.cameras.remove(cd)


def dp(x, y, z):
    """Design-space point -> Blender world (the root X mirror)."""
    return Vector((-x, y, z)) + Vector(OFFSET)


# name, light azimuth (deg), camera (design xyz), target (design xyz), lens, show_human, resolution
SHOTS = [
    ("front_studio", 0, (0, 70, 14), (0, 0, 11), 38, False, (1600, 1200)),
    ("front_three_quarter", -25, (-48, 52, 17), (0, 0, 10), 38, False, (1600, 1200)),
    ("rear_studio", 180, (0, -72, 14), (0, 0, 11), 38, False, (1600, 1200)),
    ("rear_three_quarter", 160, (50, -45, 15), (0, 0, 10), 38, False, (1600, 1200)),
    ("street_human_view", 0, (-6, 27, 1.6), (0, 0, 7), 28, True, (1600, 1200)),
    ("street_right_alley", 90, (50, 8, 1.6), (13, 2, 5), 26, True, (1600, 1200)),
    ("roof_service", 180, (-28, -30, 38), (4, -1, 17), 34, False, (1600, 1200)),
    ("closeup_bay_a", 0, (-8.5, 21, 2.2), (-8.5, 5, 2.5), 34, True, (1400, 1050)),
    ("closeup_bay_b", 0, (3.5, 20, 2.0), (3.5, 5, 2.4), 34, True, (1400, 1050)),
    ("closeup_airlock", 0, (14, 17, 2.0), (11.4, 9, 1.8), 36, True, (1400, 1050)),
]


def render_all(ob, human, outdir, size_scale=1.0, only=()):
    scene = bpy.context.scene
    pick_engine(scene)
    scene.render.film_transparent = False
    st = Studio()
    for name, az, cam, tgt, lens, show, res in SHOTS:
        if only and name not in only:
            continue
        st.aim(az)
        human.hide_render = not show
        if show:
            hp = {"street_human_view": (-3.0, 18.0), "street_right_alley": (22.0, 6.0), "closeup_bay_a": (-8.5, 14.0),
                  "closeup_bay_b": (3.5, 14.0), "closeup_airlock": (11.6, 12.5)}[name]
            human.location = dp(hp[0], hp[1], 0.0)
        res = (int(res[0] * size_scale), int(res[1] * size_scale))
        st.snap(os.path.join(outdir, name + ".png"), dp(*cam), dp(*tgt), lens, res=res)
        report(render=name)
    human.hide_render = True
    return st


# ---------------------------------------------------------------------------- main


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--no-render", action="store_true")
    p.add_argument("--size", type=float, default=1.0, help="render resolution scale")
    p.add_argument("--only-shots", default="")
    a = args(p)
    if not 0.25 <= a.size <= 2.0:
        p.error("--size is a resolution SCALE from 0.25 to 2.0; use --size 1.0, not a pixel width")
    root = os.environ.get("AK_REPO", os.getcwd())
    cand_dir = os.path.join(root, "godot", "assets", "city", "candidates")
    gen_dir = os.path.join(root, "assets", "generated", "city_habitation")
    prev_dir = os.path.join(root, "assets", "previews", "city_habitation")
    for d in (cand_dir, gen_dir, prev_dir):
        os.makedirs(d, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    coll = bpy.data.collections.new("habitation_workshop")
    bpy.context.scene.collection.children.link(coll)
    ref_coll = bpy.data.collections.new("reference_nonruntime")
    bpy.context.scene.collection.children.link(ref_coll)
    mats = make_materials()
    k = Kit()
    build_building(k)
    ob = finalize(k, mats, coll)
    lo, hi, (nv, tris) = measure(ob)
    cs = colour_stats(ob)
    report(asset=ASSET_ID, tris=tris, verts=nv, lo=[round(x, 2) for x in lo], hi=[round(x, 2) for x in hi], colors=cs,
           parts=k.parts)

    # Primary facade plane (podium front, design y = PBOX[3]) vs the footprint's front extent (glTF -Z).
    setback = round(-(PBOX[3] + OFFSET[1]) - lo[2], 4)
    glb = os.path.join(cand_dir, ASSET_ID + ".glb")
    export_glb(ob, glb)
    surfaces = [m.name for m in ob.data.materials]
    manifest = {
        "version": 1, "status": "candidate-review", "assets": [{
            "id": ASSET_ID, "class": "building", "glb": ASSET_ID + ".glb", "tris": tris,
            "aabb": {"min": [round(x, 4) for x in lo], "max": [round(x, 4) for x in hi]},
            "footprint": {"min": [round(lo[0], 4), round(lo[2], 4)], "max": [round(hi[0], 4), round(hi[2], 4)]},
            "front_setback_m": setback,
            "origin": "foot-centred: footprint centre at xz 0, base at y 0; primary facade faces -Z", "surfaces": surfaces, "reuse_worlds": ["city", "underworks", "foundry"],
            "vertex_colors": {"attribute": "COLOR_0", "role": "multiplies albedo: grime, streaks, paint and repair tint"},
            "lod_strategy": "near: this mesh; mid: drop interiors, stencils, rails, window furniture (about 45 percent of "
                            "tris); far: podium + module + roof silhouettes only (about 5 percent). Not yet generated.",
            "budget_note": f"{tris} tris of {TRI_CAP} cap, {len(surfaces)} materials, COLOR_0 wear.",
        }]}
    with open(os.path.join(cand_dir, ASSET_ID + "_manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    qa = dict(tris=tris, verts=nv, lo=[round(x, 3) for x in lo], hi=[round(x, 3) for x in hi], colors=cs, parts=k.parts,
              cameras_lights=[o.name for o in bpy.context.scene.objects if o.type in ("CAMERA", "LIGHT")])
    with open(os.path.join(gen_dir, "qa.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(qa, f, indent=2)
    report(done="export", tris=tris)

    human = build_human(ref_coll, mats)
    human.hide_render = True
    wire_vertex_colors(mats)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(gen_dir, ASSET_ID + ".blend"))
    if not a.no_render:
        render_all(ob, human, prev_dir, a.size, [x for x in a.only_shots.split(",") if x])
        report(done="render")


main()
