"""Deterministic Whiplash Shift City kit: 14 hard-surface assets -> .blend, GLBs, manifest, QA, studio renders.

Run (never the GUI):  ak-blender tools/city_pipeline/build_city_kit.py -- [--no-render] [--only id,id] [--size 1280]
"""
import argparse
import json
import math
import os
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

SEM = ("steel", "ceramic", "cavity", "machinery", "sinew", "glow_cyan", "glow_amber", "trim")
PBR = {
    "steel": ((0.05, 0.055, 0.068), 0.55, 0.7, None),
    "ceramic": ((0.60, 0.56, 0.45), 0.45, 0.1, None),
    "cavity": ((0.008, 0.009, 0.013), 0.9, 0.1, None),
    "machinery": ((0.16, 0.17, 0.2), 0.38, 0.85, None),
    "sinew": ((0.33, 0.02, 0.024), 0.25, 0.0, None),
    "glow_cyan": ((0.0, 0.25, 0.3), 0.3, 0.0, (0.0, 0.87, 1.0)),
    "glow_amber": ((0.3, 0.12, 0.0), 0.3, 0.0, (1.0, 0.42, 0.02)),
    "trim": ((0.25, 0.22, 0.16), 0.5, 0.5, None),
}


class Kit:
    """Transform-stack mesh builder; every primitive is emitted into one bmesh with a semantic slot."""

    def __init__(s, remap=None):
        s.bm = bmesh.new()
        s.slots = []
        s.remap = remap or {}
        s.stack = [Matrix.Identity(4)]

    def mi(s, name):
        name = s.remap.get(name, name)
        assert name in SEM, name
        if name not in s.slots:
            s.slots.append(name)
        return s.slots.index(name)

    @contextmanager
    def at(s, x=0.0, y=0.0, z=0.0, rx=0.0, ry=0.0, rz=0.0, mirror=False):
        m = s.stack[-1] @ Matrix.Translation((x, y, z)) @ Euler((rx, ry, rz), "XYZ").to_matrix().to_4x4()
        if mirror:
            m = m @ Matrix.Diagonal((-1, 1, 1, 1))
        s.stack.append(m)
        try:
            yield
        finally:
            s.stack.pop()

    @contextmanager
    def along(s, p0, p1):
        d = Vector(p1) - Vector(p0)
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        s.stack.append(s.stack[-1] @ Matrix.Translation(p0) @ rot)
        try:
            yield d.length
        finally:
            s.stack.pop()

    def _mk(s, verts, faces, mat, smooth=None, bev=0.0):
        M = s.stack[-1]
        mi = s.mi(mat)
        vs = [s.bm.verts.new(M @ Vector(v)) for v in verts]
        out = []
        for i, f in enumerate(faces):
            fc = s.bm.faces.new([vs[j] for j in f])
            fc.material_index = mi
            fc.smooth = bool(smooth[i]) if smooth else False
            out.append(fc)
        if bev > 0:
            es = list({e for fc in out for e in fc.edges})
            bmesh.ops.bevel(s.bm, geom=es, offset=bev, segments=1, affect="EDGES", clamp_overlap=True)

    def box(s, x0, x1, y0, y1, z0, z1, mat, bev=0.0):
        if x1 - x0 < 1e-5 or y1 - y0 < 1e-5 or z1 - z0 < 1e-5:
            return
        v = [(x, y, z) for z in (z0, z1) for y in (y0, y1) for x in (x0, x1)]
        f = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
        s._mk(v, f, mat, bev=min(bev, 0.4 * min(x1 - x0, y1 - y0, z1 - z0)))

    def taper(s, cx, cy, z0, z1, hx0, hy0, hx1, hy1, mat, ox=0.0, oy=0.0, bev=0.0):
        v = [(cx + a * hx0, cy + b * hy0, z0) for b in (-1, 1) for a in (-1, 1)]
        v += [(cx + ox + a * hx1, cy + oy + b * hy1, z1) for b in (-1, 1) for a in (-1, 1)]
        f = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
        s._mk(v, f, mat, bev=bev)

    def prism(s, pts, lo, hi, mat, plane="xy"):
        n = len(pts)

        def mp(p, t):
            return {"xy": (p[0], p[1], t), "yz": (t, p[0], p[1]), "xz": (p[0], t, p[1])}[plane]

        v = [mp(p, lo) for p in pts] + [mp(p, hi) for p in pts]
        f = [tuple(range(n)), tuple(range(n, 2 * n))]
        f += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
        s._mk(v, f, mat)

    def lathe(s, prof, mat, seg=12, closed=False, smooth=True):
        rings, faces, verts = [], [], []
        for r, h in prof:
            if r < 1e-6:
                rings.append([len(verts)])
                verts.append((0.0, 0.0, h))
            else:
                rings.append([len(verts) + i for i in range(seg)])
                verts += [(r * cos(2 * pi * i / seg), r * sin(2 * pi * i / seg), h) for i in range(seg)]
        pairs = list(zip(rings[:-1], rings[1:])) + ([(rings[-1], rings[0])] if closed else [])
        for a, b in pairs:
            for i in range(seg):
                j = (i + 1) % seg
                if len(a) == 1:
                    faces.append((a[0], b[j], b[i]))
                elif len(b) == 1:
                    faces.append((a[i], a[j], b[0]))
                else:
                    faces.append((a[i], a[j], b[j], b[i]))
        sm = [True] * len(faces)
        if not closed:
            for ring in (rings[0], rings[-1]):
                if len(ring) > 1:
                    faces.append(tuple(ring))
                    sm.append(False)
        s._mk(verts, faces, mat, smooth=sm if smooth else None)

    def cyl(s, x, y, z, r, h, mat, axis="z", seg=12, r2=None, smooth=True):
        rot = {"z": {}, "x": {"ry": pi / 2}, "y": {"rx": -pi / 2}}[axis]
        with s.at(x, y, z, **rot):
            s.lathe([(r, 0.0), (r if r2 is None else r2, h)], mat, seg, smooth=smooth)

    def sphere(s, x, y, z, r, mat, seg=8):
        with s.at(x, y, z):
            s.lathe([(0, -r), (r * 0.7, -r * 0.7), (r, 0), (r * 0.7, r * 0.7), (0, r)], mat, seg)

    def beam(s, p0, p1, w, h, mat, bev=0.0):
        with s.along(p0, p1) as L:
            s.box(-w / 2, w / 2, -h / 2, h / 2, 0, L, mat, bev)

    def pipe(s, p0, p1, r, mat, seg=8, r2=None):
        with s.along(p0, p1) as L:
            s.lathe([(r, 0.0), (r if r2 is None else r2, L)], mat, seg)


def bays(k, xa, xb, z0, z1, cols, rows, depth, back, pier=0.5, sill=0.5, frame="ceramic", wall="steel",
         glow=None, louvre=0, pbev=0.0):
    W, H = xb - xa, z1 - z0
    ow = (W - (cols + 1) * pier) / cols
    oh = (H - (rows + 1) * sill) / rows
    assert ow > 0.05 and oh > 0.05, (W, H, cols, rows, ow, oh)
    k.box(xa, xb, back, -depth, z0, z1, "cavity")
    for i in range(cols + 1):
        px = xa + i * (ow + pier)
        k.box(px, px + pier, back, 0, z0, z1, frame, pbev)
    for i in range(cols):
        ox = xa + pier + i * (ow + pier)
        for j in range(rows + 1):
            zb = z0 + j * (oh + sill)
            k.box(ox, ox + ow, back, -0.06, zb, zb + sill, wall)
        for j in range(rows):
            zb = z0 + sill + j * (oh + sill)
            for m in range(louvre):
                zz = zb + (m + 1) * oh / (louvre + 1)
                k.box(ox + 0.06, ox + ow - 0.06, -depth + 0.04, -depth + 0.3, zz - 0.04, zz + 0.04, "machinery")
            if glow and (i + j * 2) % glow[1] == glow[2]:
                zm = zb + oh * 0.5
                k.box(ox + ow * 0.2, ox + ow * 0.8, -depth, -depth + 0.05, zm - 0.07, zm + 0.07, glow[0])


def block(k, cx, cy, hx, hy, z0, z1, cols=(3, 3), rows=3, depth=0.5, pier=0.45, sill=0.5, faces="FBLR",
          glow=None, louvre=0, pbev=0.0, core="steel", frame="ceramic"):
    dF, dB, dL, dR = depth if isinstance(depth, tuple) else (depth,) * 4
    k.box(cx - hx + dL + 0.1, cx + hx - dR - 0.1, cy - hy + dB + 0.1, cy + hy - dF - 0.1, z0, z1, core)
    kw = dict(rows=rows, pier=pier, sill=sill, frame=frame, glow=glow, louvre=louvre, pbev=pbev)
    if "F" in faces:
        with k.at(cx, cy + hy, 0):
            bays(k, -hx, hx, z0, z1, cols[0], depth=dF, back=-dF - 0.1, **kw)
    if "B" in faces:
        with k.at(cx, cy - hy, 0, rz=pi):
            bays(k, -hx, hx, z0, z1, cols[0], depth=dB, back=-dB - 0.1, **kw)
    if "L" in faces:
        with k.at(cx - hx, cy, 0, rz=pi / 2):
            bays(k, -(hy - dB), hy - dF, z0, z1, cols[1], depth=dL, back=-dL - 0.1, **kw)
    if "R" in faces:
        with k.at(cx + hx, cy, 0, rz=-pi / 2):
            bays(k, -(hy - dF), hy - dB, z0, z1, cols[1], depth=dR, back=-dR - 0.1, **kw)


def joints(k, x0, x1, z0, z1, n, y=0.0):
    for i in range(1, n):
        x = x0 + (x1 - x0) * i / n
        k.box(x - 0.03, x + 0.03, y, y + 0.04, z0, z1, "cavity")


def slots(k, x0, x1, z0, z1, n, y=0.0):
    for i in range(n):
        z = z0 + (z1 - z0) * (i + 0.5) / n
        k.box(x0, x1, y, y + 0.05, z - 0.04, z + 0.04, "cavity")


def hazard(k, x0, x1, y0, y1, z, h, n):
    w = (x1 - x0) / n
    for i in range(0, n, 2):
        a = x0 + i * w
        k.prism([(a, z), (a + w, z), (a + w + h * 0.5, z + h), (a + h * 0.5, z + h)], y0, y1, "trim", "xz")


def ladder(k, x, y, z0, z1, w=0.5, step=0.6, axis="y"):
    rot = 0.0 if axis == "y" else pi / 2
    with k.at(x, y, 0, rz=rot):
        for sx in (-w / 2, w / 2):
            k.box(sx - 0.03, sx + 0.03, 0, 0.06, z0, z1, "machinery")
        z = z0 + 0.3
        while z < z1:
            k.box(-w / 2, w / 2, 0.0, 0.05, z, z + 0.04, "machinery")
            z += step


def rail_line(k, p0, p1, h=1.0, spacing=1.5):
    L = (Vector(p1) - Vector(p0)).length
    n = max(1, int(math.ceil(L / spacing)))
    for i in range(n + 1):
        p = Vector(p0).lerp(Vector(p1), i / n)
        k.box(p.x - 0.03, p.x + 0.03, p.y - 0.03, p.y + 0.03, p.z, p.z + h, "machinery")
    for hh in (h, h * 0.5):
        k.beam((p0[0], p0[1], p0[2] + hh), (p1[0], p1[1], p1[2] + hh), 0.05, 0.05, "machinery")


def flange(k, x, y, z, r, axis="z"):
    k.cyl(x, y, z - 0.06, r * 1.35, 0.12, "trim", axis=axis, seg=10)


def vent(k, x, y, z, r, h, cap=True):
    k.cyl(x, y, z, r, h, "machinery", seg=10)
    k.cyl(x, y, z + h, r * 1.5, 0.12, "trim", seg=10)
    if cap:
        k.cyl(x, y, z + h + 0.12, r * 1.15, 0.1, "steel", seg=10, r2=r * 0.4)


def catenary(k, p0, p1, sag, n, r, mat):
    pts = []
    for i in range(n + 1):
        t = i / n
        p = Vector(p0).lerp(Vector(p1), t)
        p.z -= sag * 4 * t * (1 - t)
        pts.append(p)
    for a, b in zip(pts[:-1], pts[1:]):
        k.pipe(a, b, r, mat, seg=6)


def around(n, r, fn, phase=0.0):
    for i in range(n):
        a = phase + 2 * pi * i / n
        fn(i, a, r * cos(a), r * sin(a))


# ---------------------------------------------------------------------------- landmarks

def relay_tower(k):
    A = dict(cx=-4.5, cy=-1.0, zs=[7, 19, 31, 42, 53, 63, 70], hs=[3.4, 3.1, 2.8, 2.4, 2.0, 1.6])
    B = dict(cx=5.0, cy=0.8, zs=[7, 19, 30, 40, 48], hs=[3.0, 2.7, 2.3, 1.9])

    def half(sp, z):
        for i, h in enumerate(sp["hs"]):
            if sp["zs"][i] <= z <= sp["zs"][i + 1]:
                return h
        return sp["hs"][-1]

    k.box(-10.8, 10.8, -8.8, 8.8, 0, 0.8, "steel", bev=0.12)
    block(k, 0, 0, 10.0, 8.0, 0.8, 7.0, cols=(5, 5), rows=1, depth=(1.4, 0.8, 0.8, 0.8), pier=0.8, sill=0.7,
          faces="BLR", glow=("glow_amber", 4, 1), louvre=2, pbev=0.06)
    with k.at(0, 8.0, 0):
        for sx, x0, x1 in ((-1, -10.0, -3.4), (1, 3.4, 10.0)):
            bays(k, x0, x1, 0.8, 7.0, 3, 1, 1.4, -1.5, pier=0.75, sill=0.7, glow=("glow_amber", 3, 1), louvre=2, pbev=0.06)
        k.box(-3.4, 3.4, -1.5, 0, 6.0, 7.0, "ceramic", 0.08)
        k.box(-3.4, -2.5, -1.5, 0, 0.8, 6.0, "ceramic", 0.06)
        k.box(2.5, 3.4, -1.5, 0, 0.8, 6.0, "ceramic", 0.06)
        k.box(-2.5, 2.5, -2.2, -1.4, 0.8, 6.0, "cavity")
        k.box(-1.6, 1.6, -2.2, -2.1, 5.2, 5.4, "glow_cyan")
        for i in range(4):
            k.box(-3.0, 3.0, 0.2 + i * 0.35, 1.9 - i * 0.35 + 0.0, 0.8, 0.8 + 0.12 * (4 - i), "trim")
        for sx in (-3.9, 3.9):
            k.cyl(sx, 1.8, 0.8, 0.22, 1.0, "trim", seg=8)
            k.cyl(sx, 1.8, 1.8, 0.14, 0.14, "glow_amber", seg=8)
        hazard(k, -3.4, 3.4, 0, 0.1, 6.0, 0.25, 14)
    k.box(-10.4, 10.4, -8.4, 8.4, 7.0, 7.6, "ceramic", bev=0.12)

    def spine(sp, windows_glow):
        for i, h in enumerate(sp["hs"]):
            z0, z1 = sp["zs"][i] + (0.6 if i == 0 else 0.0), sp["zs"][i + 1]
            rows = max(1, round((z1 - z0 - 0.9) / 4.0))
            block(k, sp["cx"], sp["cy"], h, h, z0, z1 - 0.9, cols=(2 if h > 1.7 else 1,) * 2, rows=rows,
                  depth=0.45, pier=0.45, sill=0.5, glow=windows_glow, pbev=0.0)
            k.box(sp["cx"] - h - 0.3, sp["cx"] + h + 0.3, sp["cy"] - h - 0.3, sp["cy"] + h + 0.3, z1 - 0.9, z1, "ceramic", bev=0.1)
    k.box(-8.2, 8.2, -4.6, 4.6, 7.6, 8.1, "trim", bev=0.08)
    spine(A, ("glow_amber", 5, 2))
    spine(B, ("glow_cyan", 6, 1))
    for sx in (-1, 1):
        k.taper(A["cx"] + sx * 3.2, A["cy"] + 3.5, 7.6, 45, 0.55, 0.55, 0.3, 0.3, "ceramic", bev=0.05)
    k.taper(B["cx"] + 2.8, B["cy"] + 3.2, 7.6, 38, 0.5, 0.5, 0.28, 0.28, "ceramic", bev=0.05)

    for zc in (22.5, 35.0, 45.0):
        xa = A["cx"] + half(A, zc)
        xb = B["cx"] - half(B, zc)
        if xb - xa < 0.5:
            continue
        ym = (A["cy"] + B["cy"]) / 2
        k.box(xa, xb, ym - 0.9, ym + 0.9, zc - 1.1, zc + 1.1, "steel", bev=0.06)
        k.box(xa + 0.3, xb - 0.3, ym + 0.9, ym + 0.96, zc - 0.4, zc + 0.4, "cavity")
        k.box(xa + 0.5, xb - 0.5, ym + 0.96, ym + 1.0, zc - 0.05, zc + 0.05, "glow_cyan")
        k.beam((xa, ym, zc - 1.1), ((xa + xb) / 2, ym, zc - 3.2), 0.28, 0.28, "ceramic")
        k.beam((xb, ym, zc - 1.1), ((xa + xb) / 2, ym, zc - 3.2), 0.28, 0.28, "ceramic")
        k.box(xa, xb, ym - 0.9, ym + 0.9, zc + 1.1, zc + 1.3, "trim")

    for p0, p1 in (((A["cx"] + 1.6, A["cy"] + 0.2, 47.0), (B["cx"] - 1.4, B["cy"] + 0.2, 44.0)),
                   ((A["cx"] + 1.0, A["cy"] - 0.4, 60.0), (B["cx"] - 0.6, B["cy"] - 0.4, 47.5))):
        catenary(k, p0, p1, 2.2, 6, 0.12, "sinew")

    dish_pos = Vector((-8.4, 3.2, 58.0))
    aim = Vector((-0.45, 0.75, 0.5)).normalized()
    k.beam((A["cx"] - 1.6, A["cy"] + 0.8, 56.5), tuple(dish_pos - aim * 0.4), 0.45, 0.45, "machinery")
    k.beam((A["cx"] - 1.6, A["cy"] + 1.6, 52.5), tuple(dish_pos - aim * 0.6), 0.3, 0.3, "ceramic")
    with k.along(dish_pos, dish_pos + aim):
        k.lathe([(0, -0.35), (1.8, 0.0), (3.6, 0.65 - 0.35), (3.6, 0.65), (1.8, 0.65 - 0.2 + 0.0), (0, 0.0)], "ceramic", 20)
        k.pipe((0, 0, 0), (0, 0, 2.2), 0.08, "machinery")
        k.sphere(0, 0, 2.3, 0.16, "glow_cyan", 6)
    dp2 = Vector((8.6, -2.2, 43.5))
    ax2 = Vector((0.75, -0.35, 0.4)).normalized()
    k.beam((B["cx"] + 1.6, B["cy"] - 1.4, 42.0), tuple(dp2 - ax2 * 0.3), 0.35, 0.35, "machinery")
    with k.along(dp2, dp2 + ax2):
        k.lathe([(0, -0.25), (1.0, 0.0), (2.0, 0.35 - 0.25), (2.0, 0.35), (1.0, 0.1), (0, 0.0)], "ceramic", 14)
        k.pipe((0, 0, 0), (0, 0, 1.2), 0.06, "machinery")

    ax, ay = A["cx"], A["cy"]
    k.cyl(ax, ay, 70.0, 2.3, 1.4, "machinery", seg=16)
    k.lathe([(2.0, 71.4), (2.0, 71.7)], "trim", 16, smooth=False)
    around(14, 2.3, lambda i, a, x, y: k.box(ax + x - 0.2, ax + x + 0.2, ay + y - 0.2, ay + y + 0.2, 70.2, 71.2, "trim", 0.03))
    k.cyl(ax, ay, 71.4, 1.3, 0.8, "steel", seg=12)
    for a in (0.0, pi / 2):
        with k.at(ax, ay, 72.0, rz=a):
            k.box(-3.6, 3.6, -0.18, 0.18, 0, 0.3, "ceramic", 0.03)
            for sx in (-3.6, 3.6):
                k.box(sx - 0.12, sx + 0.12, -0.12, 0.12, 0.3, 0.6, "glow_cyan")
    legs = [(sx * 0.9, sy * 0.9) for sx in (-1, 1) for sy in (-1, 1)]
    for lx, ly in legs:
        k.beam((ax + lx, ay + ly, 72.3), (ax + lx * 0.25, ay + ly * 0.25, 80.5), 0.14, 0.14, "machinery")
    for zz, sc in ((74.0, 0.75), (76.6, 0.55), (78.8, 0.38)):
        for (x0, y0), (x1, y1) in zip(legs, legs[1:] + legs[:1]):
            k.beam((ax + x0 * sc, ay + y0 * sc, zz), (ax + x1 * sc, ay + y1 * sc, zz), 0.08, 0.08, "machinery")
    k.box(ax - 1.6, ax + 1.6, ay - 0.1, ay + 0.1, 76.0, 76.12, "trim")
    k.sphere(ax, ay, 81.0, 0.35, "glow_amber", 8)

    with k.at(A["cx"], A["cy"] - half(A, 20) - 0.45, 0, rz=pi):
        k.pipe((-1.0, 0.0, 8.0), (-1.0, 0.0, 49.0), 0.2, "machinery")
        k.pipe((-0.4, 0.0, 8.0), (-0.4, 0.0, 49.0), 0.12, "sinew")
        for zz in range(10, 49, 6):
            k.box(-1.3, -0.1, -0.05, 0.3, zz, zz + 0.12, "trim")
    ladder(k, B["cx"] + 1.0, B["cy"] - 3.0, 7.6, 40.0, 0.5, 0.8)
    return 8.0


def exchange_hall(k):
    k.box(-28.8, 28.8, -14.0, 14.0, 0, 0.8, "steel", bev=0.15)
    block(k, 0, 0, 20.0, 13.0, 0.8, 17.0, cols=(7, 5), rows=2, depth=(3.6, 0.9, 0.9, 0.9), pier=0.9, sill=0.7,
          faces="BLR", glow=("glow_amber", 5, 2), pbev=0.0)
    with k.at(0, 13.0, 0):
        bw, bp = 5.6, 1.2
        bays(k, -17.6, 17.6, 0.8, 9.4, 5, 1, 3.6, -3.7, pier=bp, sill=0.5, pbev=0.08)
        for i in range(5):
            ox = -17.6 + bp + i * (bw + bp)
            k.box(ox, ox + bw, -3.55, -3.3, 8.2, 8.3, "glow_amber")
            top = 8.9
            n = (3, 0, 5, 2, 4)[i]
            for m in range(n):
                k.box(ox + 0.1, ox + bw - 0.1, -1.1, -0.95, top - (m + 1) * 0.27, top - m * 0.27 - 0.03, "machinery")
            k.cyl(ox, -1.0, 8.6, 0.25, bw, "trim", axis="x")
            for ry in (-3.0, -2.3, -1.6):
                k.cyl(ox + 0.3, ry, 0.8, 0.2, bw - 0.6, "machinery", axis="x", seg=8)
            k.box(ox + 0.4, ox + bw - 0.4, -3.55, -1.6, 0.8, 1.1, "trim")
        k.box(-20.0, 20.0, -3.7, 1.0, 9.4, 11.4, "ceramic", bev=0.15)
        bays(k, -19.0, 19.0, 9.7, 11.1, 14, 1, 0.4, -0.6, pier=0.55, sill=0.3, glow=("glow_amber", 3, 1), frame="trim")
        k.box(-20.0, 20.0, -3.7, -1.0, 11.4, 17.0, "steel")
        for i in range(8):
            x = -17.5 + i * 5.0
            k.taper(x, 0.2, 11.4, 17.0, 0.7, 0.7, 0.45, 0.4, "ceramic", bev=0.05)
        for i in range(7):
            x = -15.0 + i * 5.0
            k.box(x - 1.3, x + 1.3, -1.0, -0.94, 12.4, 15.8, "cavity")
            k.box(x - 1.3, x + 1.3, -0.94, -0.9, 14.0, 14.1, "glow_cyan" if i % 3 == 0 else "glow_amber")
        k.box(-20.4, 20.4, -3.0, 1.2, 16.6, 17.2, "ceramic", bev=0.1)
        hazard(k, -17.0, 17.0, 0.0, 0.1, 8.9 - 0.0, 0.0001, 2)
    k.box(-20.4, 20.4, -13.4, 13.4, 16.8, 17.2, "ceramic", bev=0.1)

    ys = [-12.0 + 3.0 * i for i in range(9)]
    nodes = [(20.0, 17.2), (13.5, 19.4), (7.0, 21.2), (0.0, 22.2)]
    for y in ys:
        k.box(-20.0, 20.0, y - 0.15, y + 0.15, 17.2, 17.5, "machinery")
        for mir in (False, True):
            with k.at(0, y, 0, mirror=mir):
                for (xa, za), (xb, zb) in zip(nodes[:-1], nodes[1:]):
                    k.beam((xa, 0, za + 0.3), (xb, 0, zb + 0.3), 0.3, 0.3, "ceramic")
                    k.beam((xa, 0, 17.5), (xb, 0, zb), 0.12, 0.2, "machinery")
                for xn, zn in nodes[1:]:
                    k.box(xn - 0.07, xn + 0.07, -0.1, 0.1, 17.5, zn + 0.1, "machinery")
    for mir in (False, True):
        with k.at(0, 0, 0, mirror=mir):
            for si, ((xa, za), (xb, zb)) in enumerate(zip(nodes[:-1], nodes[1:])):
                for yi in range(len(ys) - 1):
                    m = "cavity" if (yi + si) % 3 == 1 else "steel"
                    k.prism([(xa, za + 0.45), (xb, zb + 0.45), (xb, zb + 0.6), (xa, za + 0.6)], ys[yi] + 0.2, ys[yi + 1] - 0.2, m, "xz")
    k.box(-0.5, 0.5, -12.4, 12.4, 22.6, 22.95, "trim")
    for y in (-10.0, -3.0, 4.0, 11.0):
        k.box(-0.3, 0.3, y - 0.3, y + 0.3, 22.95, 23.15, "glow_amber")

    for i, (y, r, h) in enumerate(((-8.0, 3.0, 15.5), (-1.0, 3.0, 12.5), (6.0, 3.0, 10.0))):
        x = -24.6
        k.cyl(x, y, 0.8, r, h, "machinery", seg=20)
        with k.at(x, y, 0.8 + h):
            k.lathe([(r, 0.0), (r * 0.75, 0.9), (r * 0.3, 1.4), (0, 1.5)], "steel", 20)
        for zz in (3.0, h * 0.55, h - 0.8):
            k.cyl(x, y, 0.8 + zz, r + 0.15, 0.3, "trim", seg=20)
        k.box(x + r - 0.1, x + r + 0.12, y - 0.25, y + 0.25, 2.0, h - 1.0, "cavity")
        k.box(x + r + 0.12, x + r + 0.16, y - 0.06, y + 0.06, 2.4, 2.4 + h * 0.4, "glow_cyan")
        ladder(k, x, y + r + 0.05, 0.8, h + 0.8, 0.5, 0.7)
        k.pipe((x + r, y, 0.8 + h * 0.4), (-20.0, y, 0.8 + h * 0.4 - 0.0), 0.28, "machinery")
        for fx in (-22.0, -21.0):
            flange(k, fx, y, 0.8 + h * 0.4, 0.28, "x")
    for y in (-3.5, 3.5):
        k.pipe((-27.4, y, 0.8), (-27.4, y, 12.5), 0.2, "sinew" if y > 0 else "machinery")
    k.beam((-27.5, -11.0, 17.5), (-20.0, -11.0, 17.5), 0.5, 0.5, "ceramic")
    k.beam((-27.5, 10.0, 17.5), (-20.0, 10.0, 17.5), 0.5, 0.5, "ceramic")
    k.beam((-27.5, -11.0, 17.5), (-27.5, 10.0, 17.5), 0.5, 0.5, "ceramic")
    k.box(-27.8, -27.2, -11.2, 10.2, 17.3, 17.4, "trim")

    for y in (-8.5, -2.5, 3.5):
        k.box(21.0, 25.5, y - 1.9, y + 1.9, 0.8, 4.2, "machinery", bev=0.1)
        for f in range(8):
            k.box(25.5, 26.3, y - 1.8 + f * 0.5, y - 1.6 + f * 0.5, 1.0, 4.0, "steel")
        for b in range(3):
            k.cyl(22.0 + b * 1.3, y, 4.2, 0.3, 1.2, "ceramic", seg=8)
            k.cyl(22.0 + b * 1.3, y, 5.4, 0.12, 0.2, "trim", seg=6)
        k.box(21.0, 21.4, y - 0.5, y + 0.5, 2.5, 2.9, "glow_amber" if y > 0 else "glow_cyan")
    for y in (8.5, 12.0):
        k.cyl(24.0, y, 0.8, 1.5, 21.0, "steel", seg=16, r2=1.0)
        k.cyl(24.0, y, 21.8, 1.2, 0.5, "trim", seg=16)
        k.cyl(24.0, y, 22.1, 1.25, 0.12, "glow_amber", seg=16)
        for zz in (6.0, 11.0, 16.0):
            k.cyl(24.0, y, zz, 1.45 - zz * 0.02, 0.3, "ceramic", seg=16)
    for y in (-11.5, 11.5):
        k.box(20.0, 27.5, y - 0.2, y + 0.2, 0.8, 7.0, "machinery")
    for z in (6.0, 7.2):
        k.pipe((20.0, 6.2, z), (27.0, 6.2, z), 0.28, "machinery")
    return 13.0


def pump_citadel(k):
    shell_r, base = 10.5, 0.9
    k.cyl(0, -2.0, 0, 15.5, 0.9, "steel", seg=32, r2=15.0)
    with k.at(0, -2.0, base):
        k.lathe([(12.5, 0.0), (11.8, 2.0), (shell_r, 4.0), (shell_r, 21.0), (shell_r - 0.6, 22.0), (shell_r - 1.4, 23.0),
                 (9.0, 24.0), (7.8, 26.5), (5.8, 28.5), (3.2, 30.0), (3.2, 30.6), (0, 30.8)], "ceramic", 28)
        for zz in (7.5, 13.0, 18.5):
            k.cyl(0, 0, zz, shell_r + 0.35, 0.55, "trim", seg=28)
        for ring_z in (9.5, 15.5):
            around(24, shell_r, lambda i, a, x, y, rz_=ring_z: _slit(k, x, y, a, rz_))
        for i in range(14):
            a = 2 * pi * (i + 0.5) / 14
            with k.at(shell_r * cos(a), shell_r * sin(a), 3.4, rz=a):
                k.taper(0.2, 0, 0, 17.5, 0.35, 0.3, 0.2, 0.18, "ceramic", bev=0.03)
        around(8, shell_r, lambda i, a, x, y: _buttress(k, x, y, a))
        prof = [(9.0, 24.0), (7.8, 26.5), (5.8, 28.5), (3.2, 30.0)]
        for ri in range(12):
            ra = 2 * pi * ri / 12
            pts = [((r + 0.2) * cos(ra), (r + 0.2) * sin(ra), z) for r, z in prof]
            for p0, p1 in zip(pts[:-1], pts[1:]):
                k.beam(p0, p1, 0.4, 0.4, "ceramic")
        k.cyl(0, 0, 30.8, 0.9, 1.0, "machinery", seg=10)
        k.cyl(0, 0, 31.8, 1.0, 0.18, "trim", seg=10)
        k.sphere(0, 0, 32.3, 0.28, "glow_cyan", 8)
        around(8, 5.8, lambda i, a, x, y: vent(k, x, y, 26.6 - 0.0 + (0.0 if True else 0), 0.35, 1.2))
        k.lathe([(shell_r + 0.2, 14.9), (shell_r + 2.2, 14.9), (shell_r + 2.2, 15.1), (shell_r + 0.2, 15.1)], "trim", 28, closed=True)
        for i in range(20):
            a = 2 * pi * i / 20
            k.box(shell_r * 0 + (shell_r + 2.1) * cos(a) - 0.03, (shell_r + 2.1) * cos(a) + 0.03,
                  (shell_r + 2.1) * sin(a) - 0.03, (shell_r + 2.1) * sin(a) + 0.03, 15.1, 16.1, "machinery")
        for i in range(20):
            a0, a1 = 2 * pi * i / 20, 2 * pi * (i + 1) / 20
            p0 = ((shell_r + 2.1) * cos(a0), (shell_r + 2.1) * sin(a0), 16.1)
            p1 = ((shell_r + 2.1) * cos(a1), (shell_r + 2.1) * sin(a1), 16.1)
            k.beam(p0, p1, 0.05, 0.05, "machinery")

    tanks = [(-13.0, 8.0, 3.8, 14.0), (-7.2, 14.0, 3.4, 11.0), (7.2, 14.0, 3.4, 16.0), (13.0, 8.0, 3.8, 12.0),
             (-13.5, -10.0, 3.2, 9.5), (13.5, -10.0, 3.2, 10.5)]
    for tx, ty, tr, th in tanks:
        k.cyl(tx, ty, 0, tr + 0.4, 0.9, "steel", seg=18)
        k.cyl(tx, ty, 0.9, tr, th, "machinery", seg=18)
        with k.at(tx, ty, 0.9 + th):
            k.lathe([(tr, 0.0), (tr * 0.82, 0.8), (tr * 0.45, 1.3), (0, 1.5)], "ceramic", 18)
            k.cyl(0, 0, 1.4, 0.25, 0.8, "trim", seg=8)
        for zz in (2.2, th * 0.5, th - 0.7):
            k.cyl(tx, ty, 0.9 + zz, tr + 0.14, 0.3, "ceramic", seg=18)
        a = math.atan2(ty + 2.0, tx)
        sx, sy = tx + (tr + 0.02) * cos(a), ty + (tr + 0.02) * sin(a)
        with k.at(sx, sy, 0, rz=a - pi / 2):
            k.box(-0.22, 0.22, -0.02, 0.1, 1.6, th - 0.6, "cavity")
            k.box(-0.06, 0.06, 0.1, 0.14, 1.9, 1.9 + th * 0.5, "glow_cyan")
    sx, sz = 0.0, 3.2
    k.box(-5.0, 5.0, 10.0, 11.2, sz - 0.7, sz + 0.7, "machinery", bev=0.1)
    for xx in (-4.2, -2.1, 0.0, 2.1, 4.2):
        k.cyl(xx, 10.6, sz + 0.7, 0.3, 1.1, "trim", seg=8)
        flange(k, xx, 10.6, sz + 1.2, 0.3)
    for ty, tz in ((8.0, 4.2), (14.0, 6.0)):
        pass
    for (tx, ty, tr, th), z in zip(tanks[:4], (4.0, 5.4, 5.4, 4.0)):
        tgt = (tx * 0.62, ty - 4.0, z)
        k.pipe((tx, ty, z), (tgt[0], ty, z), 0.34, "machinery")
        k.pipe((tgt[0], ty, z), (tgt[0], 10.6 if abs(tgt[0]) < 5.2 else 10.6, z), 0.34, "machinery")
        for t in (0.35, 0.7):
            flange(k, tx + (tgt[0] - tx) * t, ty, z, 0.34, "x")
        k.sphere(tgt[0], ty, z, 0.45, "trim", 8)
    for xx in (-3.0, 3.0):
        k.pipe((xx, 10.6, 4.0), (xx, 3.0, 11.0), 0.4, "machinery")
        k.pipe((xx * 0.6, 10.6, 3.6), (xx * 0.6, 2.0, 7.0), 0.2, "sinew")
        with k.at(xx, 9.0, 5.4):
            k.cyl(0, 0, 0, 0.35, 0.6, "machinery", axis="y", seg=8)
            k.cyl(0, 0.55, 0, 0.62, 0.1, "sinew", axis="y", seg=10)
            for sp in range(4):
                k.beam((0, 0.6, 0), (0.55 * cos(sp * pi / 2), 0.6, 0.55 * sin(sp * pi / 2)), 0.06, 0.06, "sinew")

    with k.at(0, 14.0, 0):
        k.box(-4.0, 4.0, -3.4, 0.4, 0, 0.9, "steel", 0.08)
        block(k, 0, -1.5, 3.8, 1.9, 0.9, 7.6, faces="LR", cols=(2, 1), rows=1, depth=0.4, pier=0.5, sill=0.9)
        k.box(-3.8, 3.8, -3.4, 0.4, 7.6, 8.1, "ceramic", 0.1)
        k.box(-3.3, 3.3, -3.4, -1.6, 0.9, 7.6, "steel")
        with k.at(0, 0.4, 0):
            k.box(-2.0, 2.0, -1.8, 0, 0.9, 5.4, "cavity")
            k.box(-1.5, 1.5, -1.8, -1.75, 5.3, 5.45, "glow_cyan")
            k.box(-3.3, -2.0, -1.8, 0, 0.9, 7.6, "ceramic", 0.05)
            k.box(2.0, 3.3, -1.8, 0, 0.9, 7.6, "ceramic", 0.05)
            k.box(-2.0, 2.0, -1.8, 0, 5.4, 7.6, "ceramic", 0.05)
            hazard(k, -3.3, 3.3, 0.0, 0.06, 0.9, 0.3, 12)
            k.sphere(-3.9, 0.3, 4.0, 0.14, "glow_amber", 6)
            k.sphere(3.9, 0.3, 4.0, 0.14, "glow_amber", 6)
    return 14.0 + 0.4


def _slit(k, x, y, a, z):
    with k.at(x, y, z, rz=a - pi / 2):
        k.box(-0.28, 0.28, -0.04, 0.12, 0, 1.4, "cavity")
        k.box(-0.05, 0.05, 0.1, 0.14, 0.5, 0.9, "glow_amber")


def _buttress(k, x, y, a):
    with k.at(x, y, 0.9 - 0.9, rz=a - pi / 2):
        k.taper(0, 3.0, 0.9, 13.5, 1.1, 2.6, 0.5, 0.6, "ceramic", bev=0.08, oy=-1.6)
        k.beam((0, 0.2, 18.0), (0, 3.0 - 0.0, 13.5), 0.45, 0.45, "ceramic")
        k.box(-0.18, 0.18, -0.4, 0.6, 17.2, 18.4, "trim")


# ---------------------------------------------------------------------------- buildings

def shutter_workshop(k):
    k.box(-9.0, 9.0, -7.0, 7.6, 0, 0.6, "steel", bev=0.08)
    block(k, 0, 0, 8.6, 6.6, 0.6, 9.5, cols=(4, 3), rows=3, depth=(1.2, 0.6, 0.6, 0.6), pier=0.55, sill=0.45,
          faces="BLR", glow=("glow_amber", 7, 3), louvre=1)
    with k.at(0, 6.6, 0):
        bays(k, -8.6, 1.6, 0.6, 6.6, 2, 1, 1.2, -1.3, pier=0.9, sill=0.5, pbev=0.05)
        ow = (10.2 - 3 * 0.9) / 2
        for i, closed in enumerate((0.62, 0.3)):
            ox = -8.6 + 0.9 + i * (ow + 0.9)
            ztop = 0.6 + 0.5 + 5.0
            for m in range(int(5.0 * closed / 0.26)):
                k.box(ox + 0.08, ox + ow - 0.08, -0.55, -0.4, ztop - (m + 1) * 0.26 + 0.03, ztop - m * 0.26, "machinery")
            k.cyl(ox, -0.6, ztop - 0.25, 0.22, ow, "trim", axis="x", seg=8)
            k.box(ox + 0.2, ox + 0.5, -0.6, -0.4, 0.6, 1.0, "trim")
        k.box(1.6, 3.4, -1.3, 0, 0.6, 6.6, "steel")
        k.box(5.4, 8.6, -1.3, 0, 0.6, 6.6, "steel")
        k.box(3.4, 5.4, -1.3, 0, 3.7, 6.6, "steel")
        k.box(3.4, 5.4, -1.3, -0.9, 0.6, 3.7, "cavity")
        k.box(3.7, 5.1, -0.85, -0.7, 0.6, 3.5, "steel", 0.03)
        k.box(3.9, 4.3, -0.7, -0.65, 2.4, 3.0, "cavity")
        k.box(3.4, 5.4, 0.0, 0.07, 3.55, 3.65, "glow_cyan")
        k.box(2.9, 5.9, -0.2, 1.4, 3.85, 4.05, "ceramic", 0.04)
        k.sphere(5.7, 1.2, 3.65, 0.13, "glow_amber", 6)
        k.box(7.7, 8.6, -1.3, 0.35, 0.6, 6.6, "ceramic", 0.06)
        joints(k, 5.4, 7.7, 0.8, 6.4, 4)
        joints(k, 1.6, 3.4, 0.8, 6.4, 2)
        slots(k, 5.7, 7.5, 1.0, 3.4, 4)
        for bx in (2.6, 6.4):
            k.cyl(bx, 1.5, 0.6, 0.16, 0.9, "trim", seg=8)
            k.cyl(bx, 1.5, 1.5, 0.16, 0.05, "glow_amber", seg=8)
        hazard(k, 1.6, 8.6, 0.0, 0.06, 0.6, 0.28, 18)
    k.box(-9.0, 9.0, -7.0, 6.9, 9.5, 10.0, "ceramic", bev=0.1)
    for x0 in (-6.4, -1.0, 4.4):
        k.prism([(-5.6, 10.0), (-2.2, 10.0), (-2.2, 12.3), (-5.6, 10.8)], x0, x0 + 4.2, "steel", "yz")
        k.box(x0 + 0.2, x0 + 4.0, -2.25, -2.2, 10.2, 12.0, "cavity")
        k.box(x0 + 0.4, x0 + 3.8, -2.22, -2.2, 11.1, 11.15, "glow_cyan" if x0 > 0 else "glow_amber")
    for x, y in ((-6.0, 3.0), (6.5, 2.6)):
        vent(k, x, y, 10.0, 0.45, 1.6)
    k.pipe((-7.0, 3.0, 10.4), (6.0, 3.0, 10.4), 0.22, "machinery")
    k.box(-1.0, 1.4, 3.6, 6.0, 10.0, 11.0, "machinery", 0.05)
    ladder(k, 6.8, -7.0, 0.6, 10.2, 0.5, 0.6)
    with k.at(0, -6.6, 0, rz=pi):
        k.box(-3.0, 3.0, -0.2, 1.6, 4.0, 4.2, "ceramic", 0.05)
        for sx in (-2.8, 2.8):
            k.beam((sx, 1.6, 4.0), (sx, 0.0, 2.6), 0.15, 0.15, "machinery")
        k.box(-1.0, 1.0, -0.4, 0.0, 0.6, 3.4, "cavity")
        k.pipe((4.4, 0.4, 0.6), (4.4, 0.4, 9.6), 0.2, "machinery")
        k.pipe((5.0, 0.35, 0.6), (5.0, 0.35, 9.4), 0.1, "sinew")
        for zz in (2.0, 5.0, 8.0):
            flange(k, 4.4, 0.4, zz, 0.2)
    return 6.6


def utility_midrise(k):
    k.box(-7.4, 7.4, -7.4, 7.4, 0, 0.8, "steel", bev=0.1)
    block(k, 0, 0, 7.0, 7.0, 0.8, 7.2, cols=(4, 4), rows=1, depth=(1.0, 0.6, 0.6, 0.6), pier=0.7, sill=0.6, louvre=4, pbev=0.05)
    k.box(-7.3, 7.3, -7.3, 7.3, 7.2, 7.7, "ceramic", bev=0.1)
    hazard(k, -6.0, 6.0, 7.05, 7.15, 0.8, 0.3, 16)
    cy = -0.8
    block(k, 0, cy, 5.4, 5.6, 7.7, 23.2, cols=(4, 3), rows=6, depth=0.8, pier=0.5, sill=0.55, glow=("glow_amber", 7, 3))
    for sx in (-1, 1):
        for sy in (-1, 1):
            k.taper(sx * 5.55, cy + sy * 5.75, 7.7, 23.2, 0.6, 0.6, 0.4, 0.4, "ceramic", bev=0.05)
    for zz in (12.0, 17.5):
        k.box(-5.5, 5.5, cy + 5.6, cy + 5.8, zz, zz + 0.25, "trim")
    block(k, 0, cy, 5.4, 5.6, 23.2, 25.6, cols=(5, 4), rows=1, depth=0.45, pier=0.4, sill=0.45, louvre=5)
    k.box(-5.9, 5.9, -6.7, 5.1, 25.6, 26.1, "ceramic", bev=0.1)
    for x in (-3.0, 0.0, 3.0):
        k.cyl(x, -2.0, 26.1, 0.95, 1.8, "machinery", seg=12)
        k.cyl(x, -2.0, 27.9, 1.05, 0.15, "trim", seg=12)
        k.cyl(x, -2.0, 27.7, 0.3, 0.1, "cavity", seg=8)
    k.cyl(-3.0, 2.8, 26.1, 1.3, 2.2, "steel", seg=14)
    for a in range(4):
        k.box(-3.0 + 1.1 * cos(a * pi / 2) - 0.05, -3.0 + 1.1 * cos(a * pi / 2) + 0.05, 2.8 + 1.1 * sin(a * pi / 2) - 0.05,
              2.8 + 1.1 * sin(a * pi / 2) + 0.05, 26.1, 26.1, "trim")
    rail_line(k, (-5.7, 4.9, 26.1), (5.7, 4.9, 26.1))
    rail_line(k, (-5.7, -6.5, 26.1), (5.7, -6.5, 26.1))
    k.pipe((4.5, -5.0, 26.1), (4.5, -5.0, 31.0), 0.08, "machinery")
    k.sphere(4.5, -5.0, 31.3, 0.2, "glow_cyan", 6)
    for zz in (28.5, 30.0):
        k.beam((3.5, -5.0, zz), (5.5, -5.0, zz), 0.06, 0.06, "machinery")
    k.box(-6.9, -5.4, -3.6, 0.4, 11.0, 14.5, "machinery", bev=0.06)
    k.box(-6.92, -6.2, -3.2, 0.0, 12.0, 13.4, "cavity")
    k.box(-6.95, -6.9, -3.0, -0.2, 12.7, 12.8, "glow_cyan")
    for yy in (-3.3, 0.1):
        k.beam((-6.7, yy, 11.0), (-5.4, yy, 8.4), 0.18, 0.18, "ceramic")
    with k.at(0, -5.6 - 0.8 + 0.0, 0, rz=pi):
        k.pipe((-3.4, 0.5, 0.8), (-3.4, 0.5, 24.0), 0.22, "machinery")
        k.pipe((-2.8, 0.45, 0.8), (-2.8, 0.45, 23.0), 0.1, "sinew")
        for zz in range(3, 24, 4):
            flange(k, -3.4, 0.5, zz, 0.22)
            k.box(-3.6, -2.6, 0.0, 0.4, zz + 0.2, zz + 0.32, "trim")
        ladder(k, 3.0, 0.1, 0.8, 24.0, 0.55, 0.75)
        for zz in (7.7, 15.0):
            k.box(0.3, 2.2, 0.0, 1.1, zz, zz + 0.15, "ceramic")
    return 4.8


def ribbed_stack(k):
    k.taper(0, 0, 0, 2.4, 6.4, 6.4, 5.0, 5.0, "steel", bev=0.12)
    block(k, 0, 0, 4.0, 4.0, 2.4, 29.0, cols=(6, 6), rows=3, depth=0.7, pier=0.4, sill=0.6, glow=("glow_amber", 8, 3), pbev=0.0)
    k.box(-4.4, 4.4, -4.4, 4.4, 29.0, 29.7, "ceramic", bev=0.1)
    k.box(-3.6, 3.6, -3.6, 3.6, 29.7, 30.0, "steel")
    for sx in (-1, 1):
        for sy in (-1, 1):
            k.taper(sx * 4.6, sy * 4.6, 0.0, 31.0, 1.6, 1.6, 0.85, 0.85, "ceramic", bev=0.12)
            for zz in (9.0, 17.0, 25.0):
                k.box(sx * 4.6 - 1.2, sx * 4.6 + 1.2, sy * 4.6 - 1.2, sy * 4.6 + 1.2, zz, zz + 0.4, "trim", 0.05)
            k.beam((sx * 4.6, sy * 4.6, 31.0), (sx * 1.1, sy * 1.1, 37.5), 0.7, 0.7, "ceramic", 0.04)
    for a in range(4):
        with k.at(0, 0, 0, rz=a * pi / 2):
            k.taper(0, 4.1, 2.4, 29.0, 0.9, 0.55, 0.5, 0.3, "ceramic", bev=0.05)
            k.beam((0, 4.3, 29.5), (0, 0.9, 36.0), 0.45, 0.45, "ceramic", 0.03)
            for zz in (12.0, 21.0):
                k.box(-0.8, 0.8, 4.35, 4.7, zz, zz + 0.25, "trim")
    k.lathe([(2.6, 33.2), (2.1, 33.2), (2.1, 33.45), (2.6, 33.45)], "trim", 12, closed=True)
    k.cyl(0, 0, 29.9, 0.3, 5.6, "glow_amber", seg=8)
    k.sphere(0, 0, 37.7, 0.45, "glow_cyan", 8)
    catenary(k, (-5.9, 4.0, 18.0), (-5.9, 5.0, 4.0), 0.0, 1, 0.12, "sinew")
    catenary(k, (5.9, -5.0, 27.0), (5.9, -4.0, 5.0), 0.0, 1, 0.14, "sinew")
    for i in range(4):
        k.pipe((5.2 - i * 0.5, 4.6, 29.8 - i * 0.2), (5.0 - i * 0.5, 4.6, 12.0), 0.07, "sinew", seg=6)
    with k.at(0, -4.7, 0, rz=pi):
        k.pipe((-2.5, 0.0, 2.4), (-2.5, 0.0, 28.0), 0.3, "machinery")
        k.pipe((-1.7, 0.0, 2.4), (-1.7, 0.0, 28.0), 0.2, "machinery")
        for zz in range(4, 28, 5):
            flange(k, -2.5, 0.0, zz, 0.3)
            flange(k, -1.7, 0.0, zz + 0.7, 0.2)
        ladder(k, 2.0, -0.3, 2.4, 29.0, 0.55, 0.8)
    return 4.7


# ---------------------------------------------------------------------------- props

def pipe_rack(k):
    for x in (-2.7, 0.0, 2.7):
        for y in (-0.7, 0.7):
            k.box(x - 0.1, x + 0.1, y - 0.1, y + 0.1, 0.15, 4.4, "ceramic", 0.02)
            k.box(x - 0.2, x + 0.2, y - 0.2, y + 0.2, 0, 0.15, "steel")
        for z in (2.3, 4.4):
            k.box(x - 0.12, x + 0.12, -0.8, 0.8, z, z + 0.16, "ceramic", 0.02)
        k.beam((x, -0.7, 0.4), (x, 0.7, 2.3), 0.07, 0.07, "machinery")
        k.beam((x, 0.7, 0.4), (x, -0.7, 2.3), 0.07, 0.07, "machinery")
    for i, (y, z, r) in enumerate(((-0.45, 2.55, 0.2), (0.0, 2.6, 0.26), (0.45, 2.55, 0.2), (-0.35, 4.7, 0.14), (0.3, 4.74, 0.18))):
        r = 0.06 if i == 4 else r
        mat = "sinew" if i == 4 else "machinery"
        k.pipe((-3.05, y, z), (3.05, y, z), r, mat, seg=10)
        for fx in (-2.7, 0.0, 2.7):
            k.cyl(fx - 0.06 + 0.0, y, z, r * 1.35, 0.12, "trim", axis="x", seg=10)
    k.pipe((2.2, 0.0, 2.8), (2.2, 0.0, 4.2), 0.12, "machinery")
    k.cyl(1.2, 0.0, 2.9, 0.05, 0.2, "machinery", seg=6)
    k.cyl(1.2, 0.0, 3.1, 0.3, 0.06, "sinew", seg=10)
    k.box(-2.9, 2.9, -0.15, 0.15, 4.95, 5.1, "cavity")
    k.box(-0.5, 0.5, -0.17, -0.12, 4.97, 5.02, "glow_cyan")
    k.box(2.3, 2.6, -0.82, -0.78, 2.35, 2.5, "glow_amber")
    return None


def exhaust_stack(k):
    k.box(-1.5, 1.5, -1.5, 1.5, 0, 0.5, "steel", bev=0.08)
    hazard(k, -1.4, 1.4, 1.45, 1.52, 0.5, 0.2, 10)
    k.cyl(0, 0, 0.5, 1.15, 0.5, "ceramic", seg=12)
    k.cyl(0, 0, 1.0, 1.0, 7.4, "machinery", seg=12, r2=0.72)
    for zz in (2.2, 4.6, 6.8):
        k.cyl(0, 0, zz, 1.0 - (zz - 1.0) * 0.038 + 0.1, 0.22, "trim", seg=12)
    k.cyl(0, 0, 8.4, 0.72, 0.35, "ceramic", seg=12, r2=1.0)
    k.cyl(0, 0, 8.75, 1.0, 0.12, "trim", seg=12)
    k.cyl(0, 0, 8.76, 0.85, 0.08, "glow_amber", seg=12)
    k.box(1.0, 2.6, -0.45, 0.45, 1.2, 2.2, "machinery", 0.04)
    k.box(2.6, 2.7, -0.4, 0.4, 1.3, 2.1, "cavity")
    ladder(k, 0, -1.04, 0.5, 8.2, 0.5, 0.55)
    for a in (0, pi / 2, pi, 3 * pi / 2):
        x, y = 1.55 * cos(a), 1.55 * sin(a)
        k.beam((x, y, 0.5), (0.72 * cos(a), 0.72 * sin(a), 6.5), 0.1, 0.1, "ceramic")
    k.pipe((-0.9, 0.5, 1.2), (-0.9, 0.5, 6.0), 0.07, "sinew", seg=6)
    return None


def service_cabinet(k):
    k.box(-0.6, 0.6, -0.4, 0.4, 0, 0.15, "steel", 0.02)
    k.box(-0.55, 0.55, -0.36, 0.36, 0.15, 1.95, "machinery", 0.04)
    k.box(-0.62, 0.62, -0.42, 0.42, 1.95, 2.1, "ceramic", 0.04)
    with k.at(0, 0.36, 0):
        k.box(-0.5, -0.02, 0, 0.04, 0.25, 1.85, "steel", 0.015)
        k.box(0.02, 0.5, 0, 0.04, 0.25, 1.85, "steel", 0.015)
        k.box(-0.04, 0.04, 0.0, 0.05, 0.25, 1.85, "cavity")
        slots(k, -0.4, -0.1, 0.35, 0.8, 5, 0.04)
        k.box(0.1, 0.4, 0.04, 0.07, 1.35, 1.7, "cavity")
        for i, m in enumerate(("glow_cyan", "glow_amber", "glow_cyan")):
            k.box(0.14 + i * 0.09, 0.2 + i * 0.09, 0.07, 0.09, 1.5, 1.56, m)
        k.box(0.3, 0.38, 0.04, 0.1, 1.0, 1.2, "trim", 0.01)
        hazard(k, -0.5, 0.5, 0.04, 0.06, 0.16, 0.08, 10)
    k.pipe((0.4, -0.3, 2.1), (0.4, -0.3, 2.45), 0.05, "machinery", seg=6)
    k.pipe((0.4, -0.3, 2.45), (0.9, -0.3, 2.45), 0.05, "sinew", seg=6)
    k.cyl(-0.3, -0.34, 2.1, 0.08, 0.15, "trim", seg=8)
    return None


def transformer(k):
    k.box(-1.6, 1.6, -1.2, 1.2, 0, 0.3, "steel", 0.04)
    k.box(-1.2, 1.2, -0.8, 0.8, 0.3, 2.3, "machinery", 0.08)
    k.box(-1.3, 1.3, -0.9, 0.9, 2.3, 2.5, "ceramic", 0.05)
    for sx in (-1, 1):
        for i in range(7):
            y0 = -0.66 + i * 0.22
            if sx > 0:
                k.box(1.2, 1.7, y0, y0 + 0.07, 0.45, 2.15, "steel")
            else:
                k.box(-1.7, -1.2, y0, y0 + 0.07, 0.45, 2.15, "steel")
        k.box((1.5 if sx > 0 else -1.7), (1.7 if sx > 0 else -1.5), -0.75, 0.75, 2.15, 2.25, "trim")
        k.box((1.5 if sx > 0 else -1.7), (1.7 if sx > 0 else -1.5), -0.75, 0.75, 0.35, 0.45, "trim")
    for x in (-0.7, 0.0, 0.7):
        for j in range(4):
            k.cyl(x, 0.0, 2.5 + j * 0.2, 0.17 - j * 0.01, 0.12, "ceramic", seg=10)
            k.cyl(x, 0.0, 2.5 + j * 0.2 + 0.12, 0.1, 0.08, "ceramic", seg=8)
        k.cyl(x, 0.0, 3.3, 0.06, 0.15, "trim", seg=6)
    k.cyl(-1.0, 0.45, 2.55, 0.35, 2.0, "steel", axis="x", seg=14)
    for xx in (-0.9, 0.9):
        k.box(xx - 0.05, xx + 0.05, 0.2, 0.7, 2.5, 2.6, "trim")
    k.box(-0.35, 0.35, -0.84, -0.8, 1.2, 1.8, "cavity")
    k.box(-0.2, 0.2, -0.86, -0.84, 1.45, 1.55, "glow_amber")
    k.box(0.5, 0.58, -0.84, -0.8, 0.8, 0.9, "glow_cyan")
    hazard(k, -1.1, 1.1, -0.85, -0.8, 0.32, 0.18, 8)
    return None


def cargo_crate(k):
    k.box(-2.0, 2.0, -1.1, 1.1, 0, 0.18, "steel", 0.02)
    k.box(-1.95, 1.95, -1.05, 1.05, 0.18, 2.5, "ceramic", 0.04)
    for sy in (-1, 1):
        for i in range(14):
            x = -1.7 + i * 0.26
            k.box(x, x + 0.13, sy * 1.05 if sy > 0 else -1.12, 1.12 if sy > 0 else -1.05, 0.3, 2.4, "ceramic" if i % 2 else "steel")
    for sx in (-1, 1):
        for sy in (-1, 1):
            for z in (0.0, 2.38):
                k.box((1.82 if sx > 0 else -2.04), (2.04 if sx > 0 else -1.82), (0.98 if sy > 0 else -1.14), (1.14 if sy > 0 else -0.98), z, z + 0.2, "trim", 0.02)
    k.box(-2.02, 2.02, -1.12, 1.12, 2.44, 2.56, "ceramic", 0.03)
    with k.at(2.0, 0, 0, rz=-pi / 2):
        for d in (-0.48, 0.48):
            k.box(d - 0.46, d + 0.46, 0, 0.05, 0.3, 2.4, "steel", 0.02)
            for rx in (-0.25, 0.25):
                k.cyl(d + rx, 0.08, 0.35, 0.025, 2.0, "trim", seg=6)
            k.box(d - 0.06, d + 0.06, 0.05, 0.1, 1.1, 1.4, "trim", 0.01)
        k.box(-0.05, 0.05, 0.0, 0.06, 0.3, 2.4, "cavity")
        k.box(-0.3, 0.3, 0.05, 0.07, 2.2, 2.3, "glow_amber")
    with k.at(0, 1.12, 0):
        k.box(-0.5, 0.5, 0.0, 0.03, 0.9, 1.5, "cavity")
        k.box(-0.3, 0.3, 0.03, 0.05, 1.1, 1.18, "glow_cyan")
    return None


def barrier_segment(k):
    prof = [(-0.42, 0), (0.42, 0), (0.42, 0.18), (0.22, 0.65), (0.2, 1.1), (-0.2, 1.1), (-0.22, 0.65), (-0.42, 0.18)]
    k.prism(prof, -1.85, 1.85, "ceramic", "yz")
    k.prism([(-0.44, 0.0), (0.44, 0.0), (0.44, 0.14), (-0.44, 0.14)], -1.9, 1.9, "steel", "yz")
    k.prism([(-0.24, 1.1), (0.24, 1.1), (0.24, 1.2), (-0.24, 1.2)], -1.85, 1.85, "trim", "yz")
    for sx in (-1, 1):
        for zz in (0.25, 0.8):
            k.cyl(sx * 1.98, 0.0, zz, 0.12, 0.28, "machinery", seg=8)
        k.box(sx * 1.85 - (0.0 if sx > 0 else 0.15), sx * 1.85 + (0.15 if sx > 0 else 0.0), -0.2, 0.2, 0.15, 0.95, "steel", 0.02)
    for sy in (-1, 1):
        for i in range(4):
            x = -1.3 + i * 0.75
            ya, yb = (0.27, 0.31) if sy > 0 else (-0.31, -0.27)
            k.prism([(x, 0.3), (x + 0.28, 0.3), (x + 0.48, 0.75), (x + 0.2, 0.75)], ya, yb, "trim", "xz")
        k.box(-0.35, 0.35, 0.22 * sy if sy > 0 else -0.25, 0.25 if sy > 0 else -0.22, 0.9, 1.0, "cavity")
        k.box(-0.2, 0.2, 0.25 * sy if sy > 0 else -0.27, 0.27 if sy > 0 else -0.25, 0.93, 0.97, "glow_amber" if sy > 0 else "glow_cyan")
    return None


def beacon_post(k):
    k.cyl(0, 0, 0, 0.42, 0.25, "steel", seg=10, r2=0.34)
    k.cyl(0, 0, 0.25, 0.3, 0.3, "ceramic", seg=10)
    k.cyl(0, 0, 0.55, 0.11, 2.9, "machinery", seg=10)
    for zz in (1.2, 2.2, 3.0):
        k.cyl(0, 0, zz, 0.16, 0.12, "trim", seg=10)
    k.cyl(0, 0, 3.45, 0.26, 0.14, "ceramic", seg=10)
    k.sphere(0, 0, 3.8, 0.2, "glow_cyan", 10)
    for a in range(4):
        x, y = 0.24 * cos(a * pi / 2), 0.24 * sin(a * pi / 2)
        k.beam((x, y, 3.59), (x * 0.8, y * 0.8, 4.05), 0.05, 0.05, "trim")
    k.cyl(0, 0, 4.0, 0.2, 0.06, "ceramic", seg=10, r2=0.1)
    k.sphere(0, 0, 4.17, 0.07, "glow_amber", 6)
    k.beam((0.0, 0.0, 2.4), (0.6, 0.0, 2.9), 0.05, 0.05, "machinery")
    k.box(0.55, 0.75, -0.08, 0.08, 2.9, 3.1, "steel", 0.015)
    k.sphere(0.65, 0.09, 3.0, 0.03, "glow_amber", 4)
    k.pipe((-0.14, 0.0, 0.55), (-0.14, 0.0, 3.2), 0.025, "sinew", seg=5)
    return None


def conduit_pillar(k):
    k.taper(0, 0, 0, 0.7, 0.9, 0.9, 0.62, 0.62, "steel", bev=0.04)
    k.box(-0.55, 0.55, -0.55, 0.55, 0.7, 5.9, "ceramic", 0.1)
    for sx in (-1, 1):
        k.box(sx * 0.56 - 0.04, sx * 0.56 + 0.04, -0.3, 0.3, 1.0, 5.6, "cavity")
    with k.at(0, 0.55, 0):
        k.box(-0.3, 0.3, 0, 0.04, 1.4, 4.8, "cavity")
        k.box(-0.04, 0.04, 0.04, 0.07, 1.8, 4.4, "glow_cyan")
        for zz in (1.1, 2.8, 4.5):
            k.box(-0.5, 0.5, 0, 0.1, zz, zz + 0.12, "trim")
    for i, (x, y) in enumerate(((-0.28, 0.72), (0.28, 0.72), (-0.28, 0.96), (0.28, 0.96))):
        k.pipe((x, y, 0.7), (x, y, 6.2), 0.1 if i < 2 else 0.07, "sinew" if i == 3 else "machinery", seg=8)
        for zz in (1.4, 3.0, 4.6):
            k.box(x - 0.13, x + 0.13, y - 0.13, y + 0.13, zz, zz + 0.1, "trim")
    k.box(-0.75, 0.75, -0.75, 0.75, 5.9, 6.2, "ceramic", 0.06)
    k.box(-0.5, 0.5, -0.5, 0.5, 6.2, 6.55, "machinery", 0.04)
    k.sphere(0, 0, 6.65, 0.1, "glow_amber", 6)
    k.pipe((0.5, 0.0, 6.4), (1.0, 0.0, 5.0), 0.04, "sinew", seg=5)
    return None


ASSETS = [
    ("relay_tower", "landmark", relay_tower, "Split-spine relay tower; two tiered recessed shafts, off-axis dish, mechanical crown."),
    ("exchange_hall", "landmark", exchange_hall, "Broad exchange hall; five deep shuttered bays, articulated truss roof, silo and transformer wings."),
    ("pump_citadel", "landmark", pump_citadel, "Cylindrical pumping citadel; ribbed shell, buttresses, tank cluster and exposed manifolds."),
    ("shutter_workshop", "building", shutter_workshop, "Modular workshop with roll shutters, sawtooth roof; alt back/side."),
    ("utility_midrise", "building", utility_midrise, "Podium plus recessed tower with rooftop plant and riser/ladder back."),
    ("ribbed_stack", "building", ribbed_stack, "Slot-window block with buttress ribs and clawed crown."),
    ("pipe_rack", "prop", pipe_rack, "Portal pipe rack with flanged runs and valve."),
    ("exhaust_stack", "prop", exhaust_stack, "Guyed exhaust stack with ladder and breeching."),
    ("service_cabinet", "prop", service_cabinet, "Door cabinet with vent slots and status lights."),
    ("transformer", "prop", transformer, "Finned transformer with bushings and conservator."),
    ("cargo_crate", "prop", cargo_crate, "Corrugated container with castings and locking doors."),
    ("barrier_segment", "prop", barrier_segment, "Interlocking road barrier with hazard chevrons."),
    ("beacon_post", "prop", beacon_post, "Cyan beacon post with amber cap."),
    ("conduit_pillar", "prop", conduit_pillar, "Ceramic pillar with conduit bundle and junction cap."),
]
IDS = [a[0] for a in ASSETS]
_LM = {"trim": "machinery"}
_BU = {"trim": "machinery", "glow_cyan": "glow_amber", "sinew": "machinery"}
REMAP = {
    "relay_tower": _LM, "exchange_hall": _LM, "pump_citadel": _LM,
    "shutter_workshop": _BU, "utility_midrise": _BU,
    "ribbed_stack": {"trim": "machinery", "glow_cyan": "glow_amber"},
    "pipe_rack": {"steel": "machinery", "trim": "ceramic", "cavity": "machinery", "glow_cyan": "glow_amber"},
    "exhaust_stack": {"machinery": "steel", "trim": "ceramic", "sinew": "steel", "cavity": "steel"},
    "service_cabinet": {"sinew": "steel", "machinery": "steel", "trim": "ceramic", "cavity": "steel", "glow_amber": "glow_cyan"},
    "transformer": {"steel": "machinery", "trim": "ceramic", "glow_cyan": "glow_amber"},
    "cargo_crate": {"cavity": "steel", "trim": "steel", "machinery": "steel", "glow_cyan": "glow_amber"},
    "barrier_segment": {"machinery": "steel", "trim": "steel", "cavity": "steel", "glow_cyan": "glow_amber"},
    "beacon_post": {"machinery": "steel", "trim": "steel", "sinew": "steel", "glow_amber": "glow_cyan"},
    "conduit_pillar": {"machinery": "steel", "trim": "steel", "sinew": "steel", "glow_amber": "glow_cyan"},
}
WORLDS = {"landmark": ["city"], "building": ["city", "underworks", "foundry"],
          "prop": ["city", "underworks", "foundry", "coldworks"]}
BUDGET = {"landmark": 18000, "building": 8000, "prop": 2000}


def make_materials():
    mats = {}
    for name in SEM:
        base, rough, metal, emit = PBR[name]
        m = bpy.data.materials.new(name)
        try:
            m.use_nodes = True
        except Exception:
            pass
        nt = m.node_tree
        bsdf = nt.nodes.get("Principled BSDF") or nt.nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.inputs["Base Color"].default_value = (*base, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        if emit:
            bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
            bsdf.inputs["Emission Strength"].default_value = 2.0
        m.diffuse_color = (*base, 1.0)
        mats[name] = m
    return mats


def finalize(k, aid, mats, coll):
    bm = k.bm
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    off = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs)))
    bmesh.ops.translate(bm, verts=bm.verts, vec=-off)
    me = bpy.data.meshes.new(aid)
    bm.to_mesh(me)
    bm.free()
    for sem in k.slots:
        me.materials.append(mats[sem])
    ob = bpy.data.objects.new(aid, me)
    coll.objects.link(ob)
    return ob, off


def measure(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    pts = [(v.co.x, v.co.z, -v.co.y) for v in me.vertices]
    ev.to_mesh_clear()
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
                export_vertex_color="NONE", export_attributes=False, export_extras=False)
    have = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    bpy.ops.export_scene.gltf(**{k: v for k, v in want.items() if k in have})


# ---------------------------------------------------------------------------- studio renders

def pick_engine(scene):
    names = bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items.keys()
    scene.render.engine = next((e for e in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE") if e in names), "CYCLES")
    if scene.render.engine == "CYCLES":
        scene.cycles.samples = 32
    scene.view_settings.view_transform = "Standard"


def studio(scale):
    scene = bpy.context.scene
    world = bpy.data.worlds.new("studio") if not scene.world else scene.world
    scene.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.09, 0.095, 0.105, 1)
    bg.inputs[1].default_value = 0.9
    for name, rot, energy in (("key", (0.9, 0.2, 0.7), 4.0), ("fill", (1.1, -0.1, -0.9), 1.2), ("rim", (1.2, 0.0, 3.4), 2.5)):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy = energy
        lo = bpy.data.objects.new(name, ld)
        lo.rotation_euler = rot
        scene.collection.objects.link(lo)
    fm = bpy.data.materials.new("floor")
    fm.diffuse_color = (0.05, 0.052, 0.06, 1)
    try:
        fm.use_nodes = True
        fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.05, 0.052, 0.06, 1)
        fm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85
    except Exception:
        pass
    me = bpy.data.meshes.new("floor")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=scale)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(fm)
    fl = bpy.data.objects.new("floor", me)
    fl.location.z = -0.02
    scene.collection.objects.link(fl)
    return fl


def label(text, x, y, size):
    cu = bpy.data.curves.new("lbl_" + text, "FONT")
    cu.body = text
    cu.size = size
    cu.align_x = "CENTER"
    ob = bpy.data.objects.new("lbl_" + text, cu)
    ob.location = (x, y, 0.03)
    ob.rotation_euler = (-pi / 2 * 0 + pi / 2, 0, pi)
    ob.location.z = 0.0
    lm = bpy.data.materials.get("label") or bpy.data.materials.new("label")
    lm.diffuse_color = (0.9, 0.9, 0.85, 1)
    try:
        lm.use_nodes = True
        b = lm.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (0.9, 0.9, 0.85, 1)
        b.inputs["Emission Color"].default_value = (0.9, 0.9, 0.85, 1)
        b.inputs["Emission Strength"].default_value = 1.0
    except Exception:
        pass
    cu.materials.append(lm)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def snap(path, cam_loc, target, lens=None, ortho=None, res=(1280, 1280)):
    scene = bpy.context.scene
    cd = bpy.data.cameras.new("cam")
    if ortho:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho
    else:
        cd.lens = lens or 45
    cd.clip_start, cd.clip_end = 0.1, 2000
    cam = bpy.data.objects.new("cam", cd)
    scene.collection.objects.link(cam)
    cam.location = cam_loc
    cam.rotation_euler = (Vector(target) - Vector(cam_loc)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def render_all(objs, info, outdir, ids, size):
    scene = bpy.context.scene
    pick_engine(scene)
    scene.render.film_transparent = False
    big = max(info[i]["dims"][0] for i in IDS)
    fl = studio(300)
    for aid in ids:
        ob = objs[aid]
        for o in objs.values():
            o.hide_render = o is not ob
        w, h, d = info[aid]["dims"]
        rad = math.sqrt(w * w + h * h + d * d) / 2
        c = Vector((0, 0, h * 0.5))
        dist = rad / math.sin(math.atan(18 / 45)) * 0.98
        s = 720 if info[aid]["class"] == "prop" else size
        views = [("", 35.0, 18.0)] + ([("_back", 215.0, 18.0)] if info[aid]["class"] != "prop" else [])
        for suf, az, el in views:
            a, e = math.radians(az), math.radians(el)
            loc = c + Vector((sin(a) * cos(e), cos(a) * cos(e), sin(e))) * dist
            snap(os.path.join(outdir, f"{aid}{suf}.png"), loc, c, 45, res=(s, s))
            report(render=f"{aid}{suf}")
    for o in objs.values():
        o.hide_render = True

    def board(name, rows, caption, ortho_w, res, el=14.0):
        for o in objs.values():
            o.hide_render = True
        temp = []
        ymax = 0
        for row in rows:
            x = 0.0
            widths = [info[i]["dims"][0] for i in row["ids"]]
            total = sum(widths) + row["gap"] * (len(widths) - 1)
            x = -total / 2
            for aid, wd in zip(row["ids"], widths):
                dup = objs[aid].copy()
                dup.hide_render = False
                dup.location = (x + wd / 2, row["y"], 0)
                bpy.context.scene.collection.objects.link(dup)
                temp.append(dup)
                temp.append(label(aid, x + wd / 2, row["y"] + info[aid]["dims"][2] / 2 + row["tsize"] * 0.8, row["tsize"]))
                x += wd + row["gap"]
        maxh = max(info[i]["dims"][1] for r in rows for i in r["ids"])
        a = math.radians(caption.get("az", 8.0))
        e = math.radians(el)
        c = Vector((0, caption.get("cy", 0.0), maxh * 0.42))
        loc = c + Vector((sin(a) * cos(e), cos(a) * cos(e), sin(e))) * 400
        snap(os.path.join(outdir, name), loc, c, ortho=ortho_w, res=res)
        for t in temp:
            bpy.data.objects.remove(t)
        report(render=name)

    b_ids = ["shutter_workshop", "utility_midrise", "ribbed_stack"]
    l_ids = ["relay_tower", "exchange_hall", "pump_citadel"]
    p_ids = [i for i in IDS if info[i]["class"] == "prop"]
    if set(l_ids + b_ids) <= set(ids) or not ids:
        pass
    board("board_landmarks.png", [dict(ids=l_ids, y=0.0, gap=14.0, tsize=3.2)], dict(az=8.0), 170.0, (2400, 1500), 14.0)
    board("board_buildings.png", [dict(ids=b_ids, y=0.0, gap=12.0, tsize=1.6)], dict(az=8.0), 85.0, (2400, 1500), 14.0)
    board("board_props.png", [dict(ids=p_ids[:4], y=0.0, gap=5.0, tsize=0.5), dict(ids=p_ids[4:], y=16.0, gap=5.0, tsize=0.5)],
          dict(az=8.0, cy=8.0), 36.0, (2400, 1500), 22.0)


# ---------------------------------------------------------------------------- main

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--no-render", action="store_true")
    p.add_argument("--only", default="")
    p.add_argument("--size", type=int, default=1280)
    a = args(p)
    only = [x for x in a.only.split(",") if x] or IDS
    bad = [x for x in only if x not in IDS]
    if bad:
        report(error="unknown ids", ids=bad)
        sys.exit(1)

    root = os.environ.get("AK_REPO", os.getcwd())
    kit_dir = os.path.join(root, "godot", "assets", "city", "kit")
    prev_dir = os.path.join(root, "assets", "previews", "city_kit")
    blend = os.path.join(root, "assets", "generated", "city_kit", "city_kit.blend")
    for d in (kit_dir, prev_dir, os.path.dirname(blend)):
        os.makedirs(d, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    coll = bpy.data.collections.new("city_kit")
    bpy.context.scene.collection.children.link(coll)
    mats = make_materials()
    objs, info = {}, {}
    for aid, cls, fn, note in ASSETS:
        k = Kit(REMAP.get(aid))
        facade_y = fn(k)
        ob, off = finalize(k, aid, mats, coll)
        lo, hi, (nv, tris) = measure(ob)
        front = hi[2] * -1.0
        setback = 0.0 if facade_y is None else max(0.0, round((-lo[2]) - (facade_y - off.y), 3))
        info[aid] = dict(class_=cls, **{"class": cls}, tris=tris, verts=nv, lo=lo, hi=hi, surfaces=list(k.slots),
                         dims=[hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]], setback=setback, note=note)
        objs[aid] = ob
        info[aid].pop("class_")
        report(asset=aid, tris=tris, surfaces=len(k.slots), dims=[round(x, 2) for x in info[aid]["dims"]])
    bpy.ops.wm.save_as_mainfile(filepath=blend)

    mpath = os.path.join(kit_dir, "city_kit_manifest.json")
    old = {}
    if os.path.exists(mpath):
        with open(mpath, encoding="utf-8") as f:
            old = {e["id"]: e for e in json.load(f).get("assets", [])}
    for aid in only:
        export_glb(objs[aid], os.path.join(kit_dir, aid + ".glb"))
        i = info[aid]
        old[aid] = {
            "id": aid, "class": i["class"], "glb": aid + ".glb", "tris": i["tris"],
            "aabb": {"min": [round(x, 4) for x in i["lo"]], "max": [round(x, 4) for x in i["hi"]]},
            "footprint": {"min": [round(i["lo"][0], 4), round(i["lo"][2], 4)], "max": [round(i["hi"][0], 4), round(i["hi"][2], 4)]},
            "front_setback_m": i["setback"], "surfaces": i["surfaces"], "reuse_worlds": WORLDS[i["class"]],
            "budget_note": f"{i['tris']} tris of {BUDGET[i['class']]} max, {len(i['surfaces'])} surfaces. {i['note']}",
        }
    with open(mpath, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"version": 1, "assets": [old[x] for x in IDS if x in old]}, f, indent=2)
        f.write("\n")
    scene_cams = [o.name for o in bpy.context.scene.objects if o.type in ("CAMERA", "LIGHT")]
    qa = {aid: {"tris": info[aid]["tris"], "verts": info[aid]["verts"], "surfaces": info[aid]["surfaces"],
                "dims_m": [round(x, 3) for x in info[aid]["dims"]]} for aid in IDS}
    qa["_scene_cameras_lights"] = scene_cams
    with open(os.path.join(prev_dir, "qa.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(qa, f, indent=2)
    report(done="export", assets=len(only), total_tris=sum(info[x]["tris"] for x in IDS),
           total_surfaces=sum(len(info[x]["surfaces"]) for x in IDS))

    if not a.no_render:
        render_all(objs, info, prev_dir, only, a.size)
        report(done="render")


main()
