"""Inhabited City neighbourhood kit: market_habitat + service_tenement + freight_depot (the last lives in city_neighborhood_depot.py).

Run (never the GUI):  ak-blender tools/city_pipeline/build_city_neighborhood.py -- [--no-render] [--size 1.0]
                      [--only market_habitat] [--only-shots a,b]

Reuses the approved habitation_workshop Kit / Wall / opening / stair / rail / pipe / colour / export helpers (imported,
never edited) and adds neighbourhood components. Design space is the workshop's: +Y facade (Godot -Z), +Z up, a root X
mirror in the Kit. Each building registers itself with @building(...); the shared main() builds every registered
building from a clean Blender scene, snapshotting/resetting the workshop module's per-asset globals (ASSET_ID, OFFSET).
freight_depot registers itself through the city_neighborhood_depot.py hook at the bottom.
"""
import argparse
import importlib.util
import json
import math
import os
import random
import sys
from math import pi

import bpy
from mathutils import Vector

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("build_habitation_workshop", os.path.join(_HERE, "build_habitation_workshop.py"))
W = importlib.util.module_from_spec(_spec)
sys.modules["build_habitation_workshop"] = W
_spec.loader.exec_module(W)

for _n in ("Kit", "Wall", "face_frame", "face_len", "armor_field", "stencil", "railing", "column", "xbrace", "deck",
           "stair", "pipe_run", "stand_off", "bezel", "interior", "fit_door", "fit_strip", "fit_louvre", "fit_slits",
           "fit_bars", "fit_shutter", "fit_porthole", "spine", "cornice", "truss", "crate", "drum", "rack", "gas_bottle",
           "hang_line", "cloth", "tank_horizontal", "canister", "valve", "gauge", "conduit_bank", "rib_cutaway",
           "CURTAIN_TONES", "DRUM_TONES", "hazard_floor", "report", "args", "SEM"):
    globals()[_n] = getattr(W, _n)

TRI_CAP = 35000
TONES = CURTAIN_TONES
OXIDE = [(0.85, 0.5, 0.36), (0.78, 0.6, 0.4), (0.7, 0.42, 0.34), (0.9, 0.72, 0.5)]
TEAL = [(0.55, 0.82, 0.86), (0.5, 0.74, 0.82), (0.62, 0.86, 0.8), (0.45, 0.62, 0.78)]
GREEN = (0.42, 0.7, 0.4)
BUILDINGS = {}
SHOTS = {}


def building(bid, **meta):
    def deco(fn):
        BUILDINGS[bid] = dict(meta, id=bid, build=fn)
        return fn
    return deco


# ---------------------------------------------------------------------------- shared neighbourhood components


def bays(rng, a, b, zs0, floors, fh, kinds, avoid=(), margin=0.9, gap=(1.3, 2.6), sill=0.95, wh=(1.25, 1.7),
         top_margin=0.0):
    """Row(s) of recessed openings along a face-local span; `avoid` is a list of (xa, xb) kept clear (doors)."""
    out = []
    for f in range(floors):
        zb = zs0 + f * fh + sill
        x = a + margin + rng.uniform(0.0, 0.6)
        while True:
            kind = rng.choices([c[0] for c in kinds], [c[1] for c in kinds])[0]
            w = {"strip": rng.uniform(2.4, 3.4), "porthole": 0.95, "slits": 1.7, "louvre": rng.uniform(1.0, 1.4),
                 "bars": rng.uniform(1.0, 1.4), "shutter": rng.uniform(1.15, 1.7)}[kind]
            h = 0.95 if kind == "porthole" else rng.uniform(*wh)
            if x + w > b - margin:
                break
            hit = [v for v in avoid if not (x + w + 0.5 <= v[0] or x >= v[1] + 0.5)]
            if hit:
                x = max(v[1] for v in hit) + 0.5
                continue
            kw = {}
            if kind == "shutter":
                kw = dict(frac=rng.choice((0.0, 0.0, 0.3, 0.5, 0.75)), tone=rng.choice(TONES), lit=rng.random() < 0.7)
            elif kind in ("strip", "bars", "louvre"):
                kw = dict(lit=rng.random() < 0.7)
            out.append((kind, round(x, 3), round(x + w, 3), round(zb, 3), round(zb + h, 3), kw))
            x += w + rng.uniform(*gap)
    return out


def shell(k, bx, z0, z1, rng, windows, t=None, armor=True, akw=None, extra_excl=None, corner=True, base_cornice=True,
          patches=0, patch_rgbs=TEAL):
    """Habitation block like workshop module(), but with per-side wall thickness t={'F':..,'B':..,'L':..,'R':..}.
    `patches` adds that many bolted repair panels per face in free wall space (tinted by patch_rgbs)."""
    x0, x1, y0, y1 = bx
    tt = dict(F=0.75, B=0.75, L=0.75, R=0.75)
    tt.update(t or {})
    k.box(x0 + tt["L"], x1 - tt["R"], y0 + tt["B"], y1 - tt["F"], z0, z1, "steel")
    for side in "FBLR":
        L = face_len(side, bx)
        a, b = {"F": (0.0, L), "B": (0.0, L), "L": (tt["B"], L - tt["F"]), "R": (tt["F"], L - tt["B"])}[side]
        wl = Wall(k, a, b, z0, z1, tt[side])
        for kind, xa, xb, za, zb, kw in windows.get(side, []):
            wl.hole(xa, xb, za, zb, kind if callable(kind) else W.FITS[kind], **kw)
        with face_frame(k, side, bx):
            with k.part(".windows"):
                wl.build(rng)
            if armor:
                ex = wl.excl(0.3) + list((extra_excl or {}).get(side, []))
                with k.part(".armor"):
                    armor_field(k, a, b, z0 + 0.25, z1 - 0.22, ex, rng, y=0.0, **(akw or {}))
            placed, tries = [], 0
            while len(placed) < patches and tries < 40 and b - a > 2.5:
                tries += 1
                pw, ph = rng.uniform(0.8, 1.8), rng.uniform(0.6, 1.2)
                px, pz = rng.uniform(a + 0.5, b - 0.5 - pw), rng.uniform(z0 + 0.5, z1 - 0.6 - ph)
                r = (px - 0.2, px + pw + 0.2, pz - 0.2, pz + ph + 0.2)
                if any(not (r[1] <= e[0] or r[0] >= e[1] or r[3] <= e[2] or r[2] >= e[3]) for e in ex + placed):
                    continue
                placed.append(r)
                with k.part(".patches"):
                    repair_panel(k, px, px + pw, pz, pz + ph, 0.0, rng, patch_rgbs, 0.4)
    if corner:
        for cx, cy, sx, sy in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
            spine(k, cx + 0.12 * sx, cy + 0.12 * sy, z0, z1, 0.27)
    if base_cornice:
        cornice(k, bx, z0, 0.2, 0.25)
    cornice(k, bx, z1 - 0.2, 0.2, 0.3)


def person(k, x, y, z, rng, rot=0.0, seated=False, tone=None):
    """Simple occupant silhouette (legs, torso, arms, head) so stalls and galleries read as inhabited."""
    tone = tone or rng.choice(TONES)
    with k.at(x, y, z, rz=rot):
        if seated:
            k.box(-0.18, 0.18, -0.22, 0.25, 0.42, 0.5, "machinery")
            k.box(-0.17, -0.04, -0.2, 0.3, 0.0, 0.42, "machinery", skip=("zn",))
            k.box(0.04, 0.17, -0.2, 0.3, 0.0, 0.42, "machinery", skip=("zn",))
            zt = 0.5
        else:
            k.box(-0.17, -0.03, -0.1, 0.1, 0.0, 0.85, "machinery", skip=("zn",))
            k.box(0.03, 0.17, -0.1, 0.1, 0.0, 0.85, "machinery", skip=("zn",))
            zt = 0.85
        with k.look(0.85, tone):
            k.box(-0.22, 0.22, -0.13, 0.13, zt, zt + 0.6, "trim")
            k.box(-0.33, -0.22, -0.07, 0.07, zt + 0.1, zt + 0.55, "trim")
            k.box(0.22, 0.33, -0.07, 0.07, zt + 0.1, zt + 0.55, "trim")
        with k.at(0, 0, zt + 0.62):
            k.lathe([(0, 0.0), (0.11, 0.04), (0.11, 0.2), (0, 0.26)], "ceramic", 6, True)


def lamp(k, x, y, z, mat="glow_amber", s=0.07):
    k.box(x - s, x + s, y - s, y + s, z - s, z + s, mat)


def awning(k, x0, x1, y, depth, z, drop, rng, tone=None, poles=True, ground=0.0):
    """Cloth awning: slope from the wall at z down by `drop` over `depth`, scalloped valance, frame and front poles."""
    tone = tone or rng.choice(TONES)
    with k.look(0.88, tone):
        with k.at(x0, y, z):
            k.prism([(0.0, 0.0), (depth, -drop), (depth, -drop - 0.05), (0.0, 0.05)], 0.0, x1 - x0, "trim", "yz")
        n = max(2, int((x1 - x0) / 0.45))
        for i in range(n):
            xa = x0 + (x1 - x0) * i / n
            k.box(xa + 0.02, xa + (x1 - x0) / n - 0.02, y + depth - 0.02, y + depth + 0.03,
                  z - drop - 0.2 - (0.06 if i % 2 else 0.0), z - drop, "trim", skip=("yn",))
    k.beam((x0, y, z - 0.05), (x0, y + depth, z - drop - 0.05), 0.04, 0.04, "steel")
    k.beam((x1, y, z - 0.05), (x1, y + depth, z - drop - 0.05), 0.04, 0.04, "steel")
    if poles:
        for px in (x0, x1):
            k.box(px - 0.025, px + 0.025, y + depth - 0.05, y + depth, ground, z - drop - 0.1, "steel", skip=("zn",))


def ladder(k, x, y, z0, z1, width=0.45, axis="x", cage=False, mat="machinery"):
    """Rung ladder in the xz plane (axis 'x') or yz plane (axis 'y'); optional safety-cage hoops."""
    ax = (lambda o: (x + o, y)) if axis == "x" else (lambda o: (x, y + o))
    for s in (-width / 2, width / 2):
        px, py = ax(s)
        k.box(px - 0.025, px + 0.025, py - 0.025, py + 0.025, z0, z1, mat, skip=("zn",))
    n = int((z1 - z0) / 0.3)
    for i in range(n):
        zz = z0 + 0.25 + i * 0.3
        a, b = ax(-width / 2), ax(width / 2)
        k.box(min(a[0], b[0]) - 0.02, max(a[0], b[0]) + 0.02, min(a[1], b[1]) - 0.02, max(a[1], b[1]) + 0.02, zz - 0.015, zz + 0.015, "steel", skip=("xn", "xp") if axis == "x" else ("yn", "yp"))
    if cage:
        for zz in [z0 + 2.2 + i * 0.9 for i in range(int((z1 - z0 - 2.2) / 0.9))]:
            with k.at(x, y, zz):
                k.lathe([(0.42, 0.0), (0.42, 0.04)], "steel", 6, False)


def laundry(k, p0, p1, rng, n=None, drop=(0.45, 0.9)):
    """Sagging line with garments hung along it (cloth is thin boxes in the line's vertical plane)."""
    pts = hang_line(k, p0, p1, 0.22, 8, 0.012, "steel")
    d = Vector(p1) - Vector(p0)
    along_x = abs(d.x) >= abs(d.y)
    for i in range(n or max(2, int(d.length / 0.8))):
        q = pts[1 + rng.randrange(len(pts) - 2)] if len(pts) > 2 else pts[0]
        w, h = rng.uniform(0.25, 0.5), rng.uniform(*drop)
        with k.look(0.9, rng.choice(TONES + OXIDE)):
            if along_x:
                k.box(q.x - w / 2, q.x + w / 2, q.y - 0.012, q.y + 0.012, q.z - h, q.z - 0.02, "trim")
            else:
                k.box(q.x - 0.012, q.x + 0.012, q.y - w / 2, q.y + w / 2, q.z - h, q.z - 0.02, "trim")


def cistern(k, x, y, z, r, h, rng, tone=None, legs=True):
    """Vertical water cistern on a steel stand: banded tank, domed head, ladder, level gauge, outlet valve."""
    tone = tone or rng.choice(DRUM_TONES)
    with k.look(0.85, tone):
        with k.at(x, y, z):
            k.lathe([(r * 0.9, 0.0), (r, 0.12), (r, h - 0.2), (r * 0.82, h), (r * 0.35, h + 0.18), (0, h + 0.2)], "machinery", 10, True)
    for zz in (z + h * 0.3, z + h * 0.62):
        with k.at(x, y, zz):
            k.lathe([(r * 1.04, 0.0), (r * 1.04, 0.1)], "steel", 10, False)
    if legs:
        for a in range(4):
            th = pi / 4 + a * pi / 2
            k.box(x + r * 0.85 * math.cos(th) - 0.06, x + r * 0.85 * math.cos(th) + 0.06, y + r * 0.85 * math.sin(th) - 0.06,
                  y + r * 0.85 * math.sin(th) + 0.06, max(0.0, z - 0.6), z + 0.1, "steel", skip=("zn",))
    ladder(k, x + r + 0.12, y, z + 0.2, z + h + 0.1, 0.4, "x")
    k.box(x - 0.03, x + 0.03, y + r - 0.04, y + r + 0.05, z + h * 0.2, z + h * 0.8, "cavity")
    k.box(x - 0.015, x + 0.015, y + r + 0.05, y + r + 0.07, z + h * 0.22 + h * 0.4 * rng.random(), z + h * 0.8, "glow_cyan", skip=("yn",))
    valve(k, x - r * 0.4, y - r - 0.1, z + 0.3, 0.1)


def tendon(k, pts, r=0.05):
    for a, b in zip(pts[:-1], pts[1:]):
        k.pipe(a, b, r, "sinew", 5)
    for p in (pts[0], pts[-1]):
        k.joint(p[0], p[1], p[2], r * 1.6, "sinew")


def repair_panel(k, x0, x1, z0, z1, y, rng, rgbs=TEAL, t=0.08):
    """Bolted faded patch (face-local frame): steel/ceramic sheet in a repair tint with four trim bolts."""
    with k.look(0.95, rng.choice(rgbs)):
        k.box(x0, x1, y, y + t, z0, z1, "ceramic" if rng.random() < 0.5 else "machinery", skip=("yn",))
    for bx, bz in ((x0 + 0.1, z0 + 0.1), (x1 - 0.1, z1 - 0.1)):
        k.box(bx - 0.04, bx + 0.04, y + t, y + t + 0.04, bz - 0.04, bz + 0.04, "trim", skip=("yn",))


def planter(k, x0, x1, y0, y1, z, rng):
    k.box(x0, x1, y0, y1, z, z + 0.4, "machinery")
    with k.look(0.8, GREEN):
        for _ in range(int((x1 - x0) / 0.15)):
            px, py = rng.uniform(x0 + 0.05, x1 - 0.05), rng.uniform(y0 + 0.05, y1 - 0.05)
            k.box(px - 0.05, px + 0.05, py - 0.05, py + 0.05, z + 0.4, z + 0.4 + rng.uniform(0.15, 0.5), "ceramic", skip=("zn",))


def gallery(k, x0, x1, y0, y1, z, rng, gaps=(), edges="FLR", brace=True, thick=0.3, laundry_z=None):
    """Access gallery deck with posts/rails on its free edges (F = y1, L = x0, R = x1), under-braces to the wall at y0."""
    deck(k, x0, x1, y0, y1, z, "machinery", thick, True, rng)
    ry = y1 - 0.08
    if "F" in edges:
        xs = [x0] + [v for g in sorted(gaps) for v in g] + [x1]
        for a, b in zip(xs[0::2], xs[1::2]):
            if b - a > 0.3:
                railing(k, (a, ry, z), (b, ry, z), 1.05, 1.5)
    if "L" in edges:
        railing(k, (x0 + 0.08, y0, z), (x0 + 0.08, ry, z), 1.05, 1.5)
    if "R" in edges:
        railing(k, (x1 - 0.08, y0, z), (x1 - 0.08, ry, z), 1.05, 1.5)
    if brace:
        n = max(2, int((x1 - x0) / 3.2))
        for i in range(n + 1):
            bx = x0 + 0.2 + (x1 - x0 - 0.4) * i / n
            k.beam((bx, y0, z - 1.0), (bx, y1 - 0.4, z - thick - 0.05), 0.09, 0.1, "steel")


def sign_plate(k, x0, x1, z0, z1, text, rng, y=0.0, lit=True):
    """Stencilled number plate on the outer face (face-local frame) with a tiny lamp."""
    with k.look(0.9, rng.choice(TEAL + OXIDE)):
        k.box(x0, x1, y, y + 0.14, z0, z1, "machinery", skip=("yn",))
    stencil(k, text, x0 + 0.18, z0 + (z1 - z0 - 0.35) / 2, 0.07, "trim", y + 0.14, rng)
    if lit:
        lamp(k, x1 - 0.12, y + 0.2, z1 + 0.1, rng.choice(("glow_amber", "glow_amber", "glow_cyan")), 0.04)


def goods(k, x0, x1, y, depth, zb, rng, hmax=0.4, tones=None):
    """A shelf/counter run of produce bins, jars and crates between x0..x1."""
    x = x0
    tones = tones or (TONES + OXIDE)
    while x < x1 - 0.2:
        w = rng.uniform(0.15, 0.4)
        h = rng.uniform(0.1, hmax)
        with k.look(rng.uniform(0.8, 1.0), rng.choice(tones)):
            if rng.random() < 0.4:
                k.cyl(x + w / 2, y + depth / 2, zb, min(w, depth) / 2 * 0.9, h, rng.choice(("machinery", "ceramic")), seg=6)
            else:
                k.box(x, x + w, y + 0.03, y + depth - 0.03, zb, zb + h, rng.choice(("machinery", "trim", "ceramic")))
        x += w + rng.uniform(0.02, 0.12)


def fit_stall(k, w, h, t, rng, lit=True, tone=None, seated=True, **_):
    """Deep street stall: dark recess, counter with produce, back shelves, dispenser, lamp, occupant, cloth canopy."""
    tone = tone or rng.choice(TONES)
    k.box(0, w, -t - 0.02, -t + 0.03, 0, h, "cavity")
    k.box(0, w, -t, 0.12, 0.0, 0.07, "steel")
    bezel(k, w, h, top=0.36, side=0.16, sill=0.0, out=0.2, sides=True)
    with k.look(0.85, tone):
        k.box(0.15, w - 0.15, -0.12, 0.34, 0.0, 0.95, "machinery")
    k.box(0.1, w - 0.1, -0.17, 0.4, 0.95, 1.02, "steel")
    k.box(0.1, w - 0.1, 0.34, 0.4, 0.2, 0.95, "cavity", skip=("yn",))
    goods(k, 0.25, w - 0.25, -0.1, 0.4, 1.02, rng, 0.38)
    for i, zz in enumerate((1.25, 1.85, 2.4)):
        if zz + 0.3 > h:
            continue
        k.box(0.1, w - 0.1, -t + 0.04, -t + 0.55, zz, zz + 0.04, "machinery")
        for sx in (0.12, w - 0.16):
            k.box(sx, sx + 0.04, -t + 0.04, -t + 0.06, zz - 0.3, zz, "steel", skip=("yn",))
        goods(k, 0.2, w * (0.55 if i == 0 else 0.9), -t + 0.06, 0.45, zz + 0.04, rng, 0.3)
    dx = w - 0.55
    with k.look(0.8, rng.choice(TEAL)):
        k.cyl(dx, -t + 0.75, 0.07, 0.22, 0.95, "machinery", seg=6)
    k.cyl(dx, -t + 0.75, 1.02, 0.1, 0.12, "steel", seg=6)
    k.box(dx - 0.03, dx + 0.03, -t + 0.45, -t + 0.6, 0.55, 0.62, "steel")
    k.box(dx - 0.02, dx + 0.02, -t + 0.46, -t + 0.52, 0.45, 0.5, "glow_cyan")
    lx = w * rng.uniform(0.25, 0.7)
    k.box(lx - 0.008, lx + 0.008, -0.6, -0.58, h - 0.6, h, "steel", skip=("yn", "yp"))
    if lit:
        k.box(lx - 0.07, lx + 0.07, -0.66, -0.52, h - 0.7, h - 0.58, "glow_amber", skip=("zp",))
    with k.look(0.88, rng.choice(TONES)):
        k.box(0.05, w - 0.05, -0.2, -0.14, h - rng.choice((0.35, 0.55, 0.8)), h - 0.03, "machinery")
    if rng.random() < 0.75:
        person(k, w * rng.uniform(0.3, 0.55), -0.95, 0.0, rng, pi, seated)
    awning(k, -0.45, w + 0.45, 0.2, 1.7, h + 0.48, 0.55, rng, tone, True, 0.0)


def fit_entry(k, w, h, t, rng, **kw):
    k.box(0, w, -t, 0.1, 0.0, 0.07, "steel")
    fit_door(k, w, h, t, rng, **kw)


# ---------------------------------------------------------------------------- building: market_habitat

MG = (-16.0, 16.0, -7.0, 5.0)      # ground block (stall wall at y=5)
ZG = 4.4                           # ground block roof
ZD = 4.75                          # gallery / first-floor level
ARC_Y = 9.8                        # outer edge of arcade + gallery
L1 = (-14.0, 14.0, -6.0, 5.0)
Z1 = 8.35
L2R = (2.0, 14.0, -6.0, 5.0)
Z2R = 12.0
L2L = (-14.0, -5.0, -6.0, 3.0)
Z2L = 11.4
L3 = (5.0, 14.0, -5.0, 3.0)
Z3 = 15.2
BAY = (8.2, 13.6, 3.8, 7.6)
M_TARGETS = {}


def m_ground(k, rng):
    items = [("stall", 3.4), ("stall", 3.0), ("door", 2.2), ("stall", 3.6), ("stall", 3.2), ("stall", 3.0), ("door", 2.0),
             ("stall", 3.4)]
    L = face_len("F", MG)
    gap = (L - sum(w for _, w in items)) / (len(items) + 1)
    wf, excl, x, n = [], [], gap, 0
    M_TARGETS["stalls"], M_TARGETS["doors"] = [], []
    for kind, w in items:
        if kind == "stall":
            wf.append((fit_stall, x, x + w, 0.0, 2.9, dict(tone=TONES[n % len(TONES)], seated=n % 2 == 0)))
            M_TARGETS["stalls"].append(x + w / 2)
        else:
            wf.append((fit_entry, x, x + w, 0.0, 2.7, dict(awning=False, lamp="glow_cyan" if n % 2 else "glow_amber")))
            M_TARGETS["doors"].append(x + w / 2)
        excl.append((x - 0.2, x + w + 0.2, 3.25, 4.25))
        n += 1
        x += w + gap
    wb = [(fit_entry, 20.0, 23.4, 0.0, 3.0, dict(awning=True))] + [
        (kd, a, b, za, zb, kw) for kd, a, b, za, zb, kw in bays(rng, 0, L, 1.2, 1, 3.0, [("louvre", 3), ("slits", 2), ("bars", 2)],
                                                                avoid=[(19.0, 24.4)], margin=1.2)]
    wl = bays(rng, 0.75, 11.25, 1.3, 1, 3.0, [("louvre", 2), ("bars", 2), ("slits", 2), ("shutter", 1)], margin=1.0, wh=(1.2, 1.8))
    wr = bays(rng, 2.0, 11.25, 1.3, 1, 3.0, [("louvre", 2), ("bars", 2), ("slits", 2), ("shutter", 1)], margin=1.0, wh=(1.2, 1.8))
    shell(k, MG, 0.0, ZG, rng, {"F": wf, "B": wb, "L": wl, "R": wr}, t=dict(F=2.0), akw=dict(cov=0.85, repair=0.16, max_rib=2),
          extra_excl={"F": excl}, base_cornice=False)
    with face_frame(k, "F", MG):
        for i, (kind, w) in enumerate(items):
            xx = gap * (i + 1) + sum(v for _, v in items[:i])
            if kind == "stall":
                sign_plate(k, xx + 0.15, xx + w - 0.15, 3.4, 4.1, ("A-%02d" % (11 + 3 * i)), rng)
            else:
                sign_plate(k, xx + 0.2, xx + w - 0.2, 3.1, 3.75, "ROOT" if i == 2 else "HAB-" + str(2 + i % 3), rng)
    # shop-front legs at pilaster seams: grime kerb and a drain along the street edge
    k.box(-16.4, 16.4, 4.2, 5.0, 0.0, 0.18, "steel")


def m_arcade(k, rng):
    with k.part(".arcade"):
        k.box(-16.4, 16.4, 5.0, ARC_Y + 0.1, 0.0, 0.07, "steel")
        for i in range(8):
            x = -14.0 + i * 4.0
            k.box(x - 0.34, x + 0.34, 8.56, 9.24, 0.0, 0.4, "steel")
            spine(k, x, 8.9, 0.4, ZD - 0.35, 0.28)
            k.box(x - 0.45, x + 0.45, 8.45, 9.35, ZD - 0.65, ZD - 0.35, "ceramic")
            k.beam((x, 8.9, ZD - 0.65), (x, 7.5, ZD - 0.35), 0.18, 0.12, "steel")
            lamp(k, x + 0.0, 8.9, ZD - 0.75, "glow_amber" if i % 3 else "glow_cyan", 0.06)
        k.box(-16.5, 16.5, -7.0, 5.0, ZG, ZD, "ceramic")
        # street life: crates, barrels, carts, benches and shoppers between the columns
        for i in range(14):
            x = -15.0 + i * 2.2 + rng.uniform(-0.3, 0.3)
            y = rng.uniform(6.0, 8.0)
            c = rng.random()
            if c < 0.35:
                crate(k, x, y, 0.07, rng.uniform(0.5, 0.9), rng.uniform(0.4, 0.7), rng.uniform(0.35, 0.8), rng)
                if rng.random() < 0.5:
                    crate(k, x + 0.1, y + 0.05, 0.9, 0.45, 0.4, 0.4, rng)
            elif c < 0.55:
                drum(k, x, y, 0.07, rng, 0.3, 0.9)
            elif c < 0.7:
                k.box(x, x + 1.2, y, y + 0.4, 0.45, 0.5, "machinery")
                for sx in (x + 0.1, x + 1.0):
                    k.box(sx, sx + 0.06, y + 0.05, y + 0.35, 0.07, 0.45, "steel")
            else:
                person(k, x, y, 0.07, rng, rng.uniform(0, 6.28), False)
        k.box(2.0, 3.6, 6.6, 7.4, 0.07, 0.17, "machinery")                   # hand cart bed
        k.box(2.0, 3.6, 6.6, 6.65, 0.17, 1.0, "steel")
        for wx in (2.2, 3.4):
            with k.at(wx, 7.0, 0.22):
                k.lathe([(0.22, -0.04), (0.22, 0.04)], "steel", 8, True)


def m_galleries(k, rng):
    gap = (-12.2, -10.8)
    with k.part(".gallery"):
        gallery(k, -16.5, 16.5, 5.0, ARC_Y, ZD, rng, gaps=[gap], brace=False)
        s_top = stair(k, (-17.3, 10.6, 0.0), -pi / 2, 5.4, ZD, 1.1, 0.19)
        k.box(-12.4, -10.8, 9.7, 11.15, ZD - 0.12, ZD, "machinery")
        for lx in (-14.6, -6.8, 1.8, 8.8):
            laundry(k, (lx, 5.3, 7.9), (lx + rng.uniform(-0.3, 0.3), 9.7, 7.3), rng, 4)
        laundry(k, (-15.0, 9.6, 6.6), (-8.0, 9.6, 6.3), rng, 7)
        awning(k, -9.0, -4.5, 5.15, 4.5, 8.15, 1.0, rng, None, True, ZD)
        awning(k, 6.0, 11.0, 5.15, 4.5, 8.15, 1.0, rng, None, True, ZD)
        # gallery furniture: tables, stools, planters, water jugs, occupants
        for x in (-12.5, -3.0, 3.5, 12.0):
            k.box(x, x + 1.0, 7.4, 8.0, ZD + 0.7, ZD + 0.76, "machinery")
            for sx, sy in ((x + 0.05, 7.45), (x + 0.9, 7.45), (x + 0.05, 7.9), (x + 0.9, 7.9)):
                k.box(sx, sx + 0.05, sy, sy + 0.05, ZD, ZD + 0.7, "steel", skip=("zn",))
            goods(k, x + 0.1, x + 0.9, 7.5, 0.4, ZD + 0.76, rng, 0.2)
            person(k, x + 0.5, 8.6, ZD, rng, pi, True)
        for x in (-15.6, -1.5, 9.5, 15.5):
            planter(k, x, x + 1.2, 9.0, 9.5, ZD, rng)
        for x in (-8.8, 0.5, 7.5):
            drum(k, x, 6.0, ZD, rng, 0.28, 0.85)
        # lamps on the gallery rail posts
        for x in range(-15, 16, 3):
            lamp(k, x + 0.0, ARC_Y - 0.08, ZD + 1.2, "glow_amber" if x % 2 else "glow_cyan", 0.045)


def m_upper(k, rng):
    L = face_len("F", L1)
    doors = [3.0, 8.5, 15.5, 22.0]
    wf = [(fit_door, d, d + 1.4, 0.0, 2.3, dict(awning=False, lamp="glow_cyan" if i % 2 else "glow_amber")) for i, d in enumerate(doors)]
    wf = [(kd, a + 0, b, ZD + za, ZD + zb, kw) for kd, a, b, za, zb, kw in wf]
    wf += bays(rng, 0, L, ZD, 1, 3.6, [("shutter", 4), ("strip", 1), ("bars", 1)], avoid=[(d - 0.2, d + 1.6) for d in doors], margin=0.9)
    wb = bays(rng, 0, L, ZD, 1, 3.6, [("shutter", 3), ("louvre", 2), ("slits", 1)], margin=1.0)
    wl = bays(rng, 0.75, 10.25, ZD, 1, 3.6, [("shutter", 3), ("bars", 1), ("porthole", 1)], margin=0.9)
    wr = bays(rng, 0.75, 10.25, ZD, 1, 3.6, [("shutter", 3), ("bars", 1), ("slits", 1)], margin=0.9)
    shell(k, L1, ZD, Z1, rng, {"F": wf, "B": wb, "L": wl, "R": wr}, akw=dict(cov=0.82, repair=0.15),
          extra_excl={"F": [(d - 0.5, d + 1.9, ZD, ZD + 2.5) for d in doors]})
    for bx, z0, z1, kinds in ((L2R, Z1, Z2R, [("shutter", 4), ("strip", 1)]), (L2L, Z1, Z2L, [("shutter", 3), ("bars", 1), ("porthole", 1)]),
                              (L3, Z2R, Z3, [("shutter", 2), ("louvre", 2), ("slits", 1)])):
        wd = {s: bays(rng, 0.75 if s in "LR" else 0.0, face_len(s, bx) - (0.75 if s in "LR" else 0.0), z0, 1, 3.0, kinds, margin=1.0) for s in "FBLR"}
        shell(k, bx, z0, z1, rng, wd, akw=dict(cov=0.8, repair=0.18, max_rib=2))
    # corner bay: boxed oriel with a wide window strip, carried on corbels from the first floor
    bw = {"F": [(fit_strip, 0.9, 4.5, Z1 + 0.9, Z1 + 2.7, dict(cells=3))],
          "L": [("shutter", 0.9, 2.2, Z1 + 0.9, Z1 + 2.4, dict(frac=0.5, lit=True))], "R": [("shutter", 0.9, 2.2, Z1 + 0.9, Z1 + 2.4, dict(frac=0.3))]}
    shell(k, BAY, Z1 + 0.0, Z2R, rng, bw, t=dict(F=0.6, L=0.6, R=0.6), akw=dict(cov=0.8, repair=0.2))
    for x in (8.6, 10.9, 13.2):
        k.beam((x, 5.0, 6.0), (x, BAY[3] - 0.1, Z1 - 0.1), 0.2, 0.16, "steel")
    k.box(BAY[0], BAY[1], 5.0, BAY[3], Z1 - 0.25, Z1, "machinery")


def m_terrace(k, rng):
    z = Z1
    with k.part(".terrace"):
        railing(k, (-4.9, 4.9, z), (0.6, 4.9, z), 1.05, 1.5)
        railing(k, (-4.9, -5.8, z), (-4.9, 4.9, z), 1.05, 1.5)
        railing(k, (-4.9, -5.8, z), (1.9, -5.8, z), 1.05, 1.5)
        top = stair(k, (-3.5, 6.4, ZD), -pi / 2, 5.6, z - ZD, 1.1, 0.19)
        k.box(top.x - 0.2, top.x + 1.5, 5.0, 7.3, z - 0.12, z, "machinery")
        railing(k, (top.x - 0.2, 7.3, z), (top.x + 1.5, 7.3, z), 1.05, 1.5)
        railing(k, (top.x + 1.5, 5.0, z), (top.x + 1.5, 7.3, z), 1.05, 1.5)
        for i, x in enumerate((-4.0, -1.8)):
            k.box(x, x + 1.3, 0.5, 1.5, z + 0.7, z + 0.76, "machinery")
            for sx, sy in ((x + 0.05, 0.55), (x + 1.2, 0.55), (x + 0.05, 1.4), (x + 1.2, 1.4)):
                k.box(sx, sx + 0.05, sy, sy + 0.05, z, z + 0.7, "steel", skip=("zn",))
            goods(k, x + 0.1, x + 1.2, 0.7, 0.6, z + 0.76, rng, 0.2)
            person(k, x + 0.65, -0.1, z, rng, 0.0, True)
        planter(k, -4.6, -2.0, -5.4, -4.8, z, rng)
        planter(k, 0.2, 1.6, -5.4, -4.8, z, rng)
        planter(k, -4.7, -4.3, -3.0, 0.0, z, rng)
        # Horizontal terrace canopy meets the four pole tops; festoon lamps hang below.
        for px, py in ((-4.5, -1.5), (1.5, -1.5), (-4.5, 3.8), (1.5, 3.8)):
            k.box(px - 0.04, px + 0.04, py - 0.04, py + 0.04, z, z + 3.0, "steel", skip=("zn",))
        with k.look(0.85, rng.choice(TEAL)):
            k.box(-4.5, 1.5, -1.5, 3.8, z + 2.95, z + 3.0, "trim")
        hang_line(k, (-4.5, 3.8, z + 2.9), (1.5, 3.8, z + 2.9), 0.3, 6, 0.012)
        for x in (-3.5, -2.0, -0.5):
            lamp(k, x, 3.8, z + 2.55, "glow_amber", 0.05)
        for i, (cx, cy) in enumerate(((-3.8, -4.3), (-1.8, -4.3))):
            cistern(k, cx, cy, z + 0.0, 0.85, 2.1, rng)
        pipe_run(k, [(-3.0, -3.5, z + 2.2), (-3.0, -3.5, z + 3.4), (-3.0, -0.5, z + 3.4), (-3.0, -0.5, z + 2.9)], 0.1, "machinery")
        # trellis laundry across the terrace
        laundry(k, (-4.9, -2.2, z + 2.3), (1.9, -2.2, z + 2.2), rng, 8)


def m_rear(k, rng):
    with k.part(".rear"):
        # ground cisterns + manifold along the rear wall
        for i, x in enumerate((-12.0, -8.4, -4.8)):
            cistern(k, x, -9.3, 0.0, 1.15, 3.2, rng)
        pipe_run(k, [(-12.0, -8.0, 3.5), (-4.8, -8.0, 3.5)], 0.14, "machinery", 2.2)
        for x in (-12.0, -8.4, -4.8):
            pipe_run(k, [(x, -8.2, 3.5), (x, -8.0, 3.5), (x, -7.7, 3.5)], 0.12, "machinery")
            valve(k, x + 0.25, -8.0, 3.7, 0.12)
            stand_off(k, Vector((x, -8.0, 3.5)), "y", -7.0, 0.12)
        conduit_bank(k, -2.0, -7.45, ZD, 15.0, 4, 0.15, rng)
        conduit_bank(k, 1.0, -7.45, 0.3, ZG, 3, 0.16, rng)
        for z in (2.5, 7.0, 11.0):
            for x in (-2.0, 1.0):
                k.box(x - 0.7, x + 0.7, -7.6, -7.3, z, z + 0.08, "steel")
        # rear service platform + stair, deliveries, bins
        deck(k, 3.0, 15.0, -10.8, -6.0, ZD, "machinery", 0.3, True, rng)
        railing(k, (3.0, -10.7, ZD), (15.0, -10.7, ZD), 1.05, 1.5)
        railing(k, (15.0, -10.7, ZD), (15.0, -6.0, ZD), 1.05, 1.5)
        railing(k, (3.0, -10.7, ZD), (3.0, -9.0, ZD), 1.05, 1.5)
        stair(k, (-2.0, -10.2, 0.0), -pi / 2, 5.0, ZD, 1.1, 0.19)
        for x in (4.0, 8.0, 12.0, 14.8):
            column(k, x, -10.5, 0.0, ZD - 0.3, 0.22)
        xbrace(k, (4.0, -10.5, 0.2), (8.0, -10.5, ZD - 0.4), (8.0, -10.5, 0.2), (4.0, -10.5, ZD - 0.4))
        xbrace(k, (8.0, -10.5, 0.2), (12.0, -10.5, ZD - 0.4), (12.0, -10.5, 0.2), (8.0, -10.5, ZD - 0.4))
        # rear L1 service door + hoist beam + lamps
        k.beam((9.0, -6.0, 8.0), (9.0, -9.2, 8.0), 0.22, 0.22, "machinery")
        k.box(8.9, 9.1, -9.3, -9.1, 6.6, 8.0, "steel", skip=("zp",))
        k.box(8.6, 9.4, -9.4, -9.0, 6.2, 6.6, "trim")
        for x in (5.0, 9.0, 13.0):
            lamp(k, x, -6.1, ZD + 3.0, "glow_amber", 0.06)
        for i, x in enumerate((-13.0, -11.0, -9.0)):
            crate(k, x, -6.6, ZG, 0.9, 0.7, 0.8, rng)
        for x in (5.0, 6.5, 10.5, 12.0):
            drum(k, x, -8.0, ZD, rng, 0.3, 0.9)
        # breach with tendons on the rear wall
    with face_frame(k, "B", L1):
        tendon(k, [(2.0, 0.1, ZD + 0.5), (2.4, 0.18, ZD + 1.2), (2.2, 0.1, ZD + 2.2)], 0.045)
        tendon(k, [(19.0, 0.1, ZD + 1.0), (19.4, 0.2, ZD + 2.0), (19.1, 0.1, ZD + 2.9)], 0.04)


def m_sides_roof(k, rng):
    with k.part(".sides"):
        # left flank: wall-run services from the terrace roof, leaning cistern stack, lamp row
        pipe_run(k, [(-14.3, -2.0, Z2L), (-14.3, -2.0, ZG + 0.2)], 0.17, "machinery", 3.0)
        pipe_run(k, [(-14.3, 1.0, Z2L), (-14.3, 1.0, ZG + 0.2)], 0.12, "machinery", 3.0)
        conduit_bank(k, -16.55, -3.0, 0.2, ZG - 0.2, 3, 0.15, rng)
        for z in (5.5, 8.0):
            stand_off(k, Vector((-14.3, -2.0, z)), "x", -14.0, 0.17)
        for i in range(3):
            cistern(k, -17.0, 0.5 + 2.8 * i, 0.0, 0.7, 2.6, rng)
        # right flank: cable tray, ducts and a galley vent
        for y in (-4.0, -1.5, 1.0):
            k.box(14.0, 14.5, y - 0.35, y + 0.35, Z2R - 2.5, Z2R - 1.7, "machinery")
        pipe_run(k, [(14.4, -4.5, ZD + 0.5), (14.4, -4.5, Z2R + 1.0)], 0.2, "machinery", 2.5)
        pipe_run(k, [(14.4, 2.0, ZD + 0.5), (14.4, 2.0, Z3 - 1.0), (13.5, 2.0, Z3 - 1.0)], 0.14, "machinery", 2.5)
        k.box(16.0, 16.6, -3.5, 1.5, ZG - 0.6, ZG, "steel")
        for z in (ZD + 1.0, Z1 + 1.0):
            lamp(k, 14.2, 4.8, z, "glow_cyan", 0.05)
        ladder(k, 14.3, -5.0, ZD, Z2R + 0.1, 0.45, "x", cage=True)
    with k.part(".roof"):
        # tower crown z=Z3: tanks, dish, vents, beacon
        rr = random.Random("m_roof")
        k.box(4.7, 14.3, -5.3, 3.3, Z3, Z3 + 0.3, "ceramic")
        tank_horizontal(k, 8.0, -3.0, 2.0, 0.8, Z3 + 1.1, rr)
        tank_horizontal(k, 11.0, -3.5, 1.0, 0.7, Z3 + 1.0, rr)
        pipe_run(k, [(9.5, -2.0, Z3 + 1.0), (9.5, -2.0, Z3 + 2.6), (9.5, 2.5, Z3 + 2.6)], 0.1, "machinery")
        with k.at(6.4, 1.5, Z3 + 0.3):
            k.lathe([(0.7, 0), (0.7, 0.5), (0.45, 0.5), (0.45, 4.8), (0.6, 4.8), (0.6, 5.1), (0.35, 5.1)], "steel", 8, True)
        with k.at(12.5, 2.0, Z3 + 2.4, rx=-0.9):
            k.lathe([(0.0, 0.0), (0.7, 0.12), (1.3, 0.45), (1.35, 0.5)], "ceramic", 8, True)
            lamp(k, 0, 0, 1.2, "glow_cyan", 0.07)
        k.box(12.3, 12.7, 1.8, 2.2, Z3 + 0.3, Z3 + 2.0, "machinery")
        k.beam((5.4, -4.5, Z3 + 0.3), (5.4, -4.5, Z3 + 4.8), 0.08, 0.08, "steel")
        lamp(k, 5.4, -4.5, Z3 + 4.9, "glow_amber", 0.08)
        for hx in (7.0, 9.0):
            k.box(hx - 0.5, hx + 0.5, 2.2, 3.0, Z3 + 0.3, Z3 + 0.9, "machinery")
        # lower roofs: left L2 garden + vent hoods, L1 service roof (over x>=14 none), right tower plant
        planter(k, -13.0, -9.0, -5.0, -4.2, Z2L, rr)
        planter(k, -13.0, -9.0, 1.2, 2.0, Z2L, rr)
        k.box(-8.0, -6.0, -5.0, -3.0, Z2L, Z2L + 1.0, "machinery")
        k.box(-12.0, -10.4, -2.0, -0.6, Z2L, Z2L + 0.3, "steel")
        for x in (-9.0, -7.0):
            cistern(k, x, -1.0, Z2L, 0.6, 1.6, rr)
        laundry(k, (-13.5, -3.0, Z2L + 1.9), (-5.5, -3.0, Z2L + 1.9), rr, 8)
        for x in (-13.5, -5.5):
            k.box(x - 0.04, x + 0.04, -3.04, -2.96, Z2L, Z2L + 1.95, "steel", skip=("zn",))
        for hx in (3.0, 5.0):
            k.box(hx - 0.5, hx + 0.5, -4.0, -3.0, Z2R, Z2R + 0.8, "machinery")
        tendon(k, [(3.3, -1.0, Z2R), (3.6, -1.1, Z2R + 0.5), (3.4, -1.0, Z2R + 1.0)], 0.05)


M_PARTS = [m_ground, m_arcade, m_galleries, m_upper, m_terrace, m_rear, m_sides_roof]


@building("market_habitat", cls="building", parts=M_PARTS, facade=(MG, 5.0), tint=(1.0, 0.88, 0.76),
          identity="Broad low corner arcade: recessed street stalls with counters, shelves and dispensers under cloth canopies; "
                   "upper residential galleries with laundry, a communal terrace with cisterns, and a stepped corner tower.",
          brief="Dusty oxide and cloth accents over chipped bone armour; warm occupied windows.")
def market_targets(off):
    """Design-space (x, y, z) review points: a street-level entrance, a stall counter and the rear cistern bank."""
    return dict(entry=(M_TARGETS["doors"][0] - 16.0, 6.4, 1.3), activity=(M_TARGETS["stalls"][1] - 16.0, 6.4, 1.2),
                service=(-8.4, -11.2, 1.8))


SHOTS["market_habitat"] = [
    ("front_studio", 0, (0, 64, 10), (0, 0, 6.5), 38, None, (1600, 1200)),
    ("front_three_quarter", -25, (-44, 48, 13), (0, 0, 6.5), 38, None, (1600, 1200)),
    ("entry_street_human", 0, (-2, 21, 1.6), (-3, 5, 2.8), 28, (1.0, 14.0), (1600, 1200)),
    ("activity_stalls", 0, (-9, 16.5, 1.7), (-9, 5, 2.2), 30, (-6.5, 12.0), (1600, 1200)),
    ("gallery_terrace", -20, (22, 24, 10), (-2, 5, 6.5), 34, None, (1600, 1200)),
    ("rear_service", 180, (8, -40, 9), (3, -7, 5.5), 34, (-0.5, -13.0), (1600, 1200)),
    ("roof_service", 180, (-26, -26, 32), (2, 0, 11), 34, None, (1600, 1200)),
    ("side_flank", 90, (48, 4, 7), (14, 0, 6.5), 32, (24.0, 4.0), (1600, 1200)),
]


# ---------------------------------------------------------------------------- shared export / render pipeline

def gp(off, dx, dy, dz):
    """Design-space point -> glTF/Godot coordinates (root X mirror, foot-centred by the baked OFFSET)."""
    return (round(-dx + off[0], 3), round(dz + off[2], 3), round(-(dy + off[1]), 3))


def dpo(off, x, y, z):
    return Vector((-x, y, z)) + Vector(off)


def render_building(bid, ob, human, outdir, off, size_scale, only):
    scene = bpy.context.scene
    W.pick_engine(scene)
    scene.render.film_transparent = False
    st = W.Studio()
    for name, az, cam, tgt, lens, hp, res in SHOTS[bid]:
        if only and name not in only:
            continue
        st.aim(az)
        human.hide_render = hp is None
        if hp:
            human.location = dpo(off, hp[0], hp[1], hp[2] if len(hp) > 2 else 0.0)
        res = (int(res[0] * size_scale), int(res[1] * size_scale))
        st.snap(os.path.join(outdir, name + ".png"), dpo(off, *cam), dpo(off, *tgt), lens, res=res)
        report(render=bid + ":" + name)
    human.hide_render = True


def build_one(bid, spec, cand_dir, gen_dir, prev_dir, render, size, only_shots):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    saved = (W.ASSET_ID, list(W.OFFSET))
    W.ASSET_ID = bid
    try:
        coll = bpy.data.collections.new(bid)
        bpy.context.scene.collection.children.link(coll)
        ref = bpy.data.collections.new("reference_nonruntime")
        bpy.context.scene.collection.children.link(ref)
        mats = W.make_materials()
        k = Kit()
        for fn in spec["parts"]:
            with k.part(fn.__name__), k.look(1.0, spec["tint"]):
                fn(k, random.Random(bid + fn.__name__))
        ob = W.finalize(k, mats, coll)
        off = list(W.OFFSET)
        lo, hi, (nv, tris) = W.measure(ob)
        cs = W.colour_stats(ob)
        report(asset=bid, tris=tris, verts=nv, lo=[round(x, 2) for x in lo], hi=[round(x, 2) for x in hi], colors=cs, parts=k.parts)
        if tris > TRI_CAP:
            raise SystemExit(f"{bid}: {tris} triangles exceeds the {TRI_CAP} near-review cap")
        glb = os.path.join(cand_dir, bid + ".glb")
        W.export_glb(ob, glb)
        fx0, fx1, fy0, fy1 = spec["facade"][0]
        setback = round(-(spec["facade"][1] + off[1]) - lo[2], 4)
        tg = {n: list(gp(off, *p)) for n, p in spec["build"](off).items()}
        surfaces = [m.name for m in ob.data.materials]
        entry = {
            "id": bid, "class": spec["cls"], "glb": bid + ".glb", "tris": tris,
            "aabb": {"min": [round(x, 4) for x in lo], "max": [round(x, 4) for x in hi]},
            "footprint": {"min": [round(lo[0], 4), round(lo[2], 4)], "max": [round(hi[0], 4), round(hi[2], 4)]},
            "front_setback_m": setback,
            "origin": "foot-centred: footprint centre at xz 0, base at y 0; primary facade faces -Z",
            "surfaces": surfaces, "reuse_worlds": ["city", "underworks", "foundry"],
            "vertex_colors": {"attribute": "COLOR_0", "role": "multiplies albedo: grime, streaks, paint and repair tint"},
            "identity": spec["identity"], "style_note": spec["brief"], "review_targets": tg,
            "lod_strategy": "Near-review mesh only (this file). No mid/far LODs exist yet; a later pass could drop interiors, "
                            "stencils, rails and window furniture, then keep volumes + roof silhouette.",
            "budget_note": f"{tris} tris of the {TRI_CAP} near-review cap, {len(surfaces)} materials, COLOR_0 wear. "
                           "Review-scene budget only; production district budgets are unchanged.",
        }
        qa = dict(tris=tris, verts=nv, lo=[round(x, 3) for x in lo], hi=[round(x, 3) for x in hi], colors=cs, parts=k.parts,
                  cameras_lights=[o.name for o in bpy.context.scene.objects if o.type in ("CAMERA", "LIGHT")])
        os.makedirs(os.path.join(gen_dir, bid), exist_ok=True)
        with open(os.path.join(gen_dir, bid, "qa.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(qa, f, indent=2)
            f.write("\n")
        human = W.build_human(ref, mats)
        human.hide_render = True
        W.wire_vertex_colors(mats)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(gen_dir, bid, bid + ".blend"))
        if render:
            od = os.path.join(prev_dir, bid)
            os.makedirs(od, exist_ok=True)
            render_building(bid, ob, human, od, off, size, only_shots)
        return entry
    finally:
        W.ASSET_ID, W.OFFSET[:] = saved[0], saved[1]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--no-render", action="store_true")
    p.add_argument("--size", type=float, default=1.0, help="render resolution SCALE (0.25-2.0), not pixels")
    p.add_argument("--only", default="", help="comma list of building ids to (re)build and render")
    p.add_argument("--only-shots", default="")
    a = args(p)
    if not 0.25 <= a.size <= 2.0:
        p.error("--size is a resolution SCALE from 0.25 to 2.0; use --size 1.0, not a pixel width")
    root = os.environ.get("AK_REPO", os.getcwd())
    cand = os.path.join(root, "godot", "assets", "city", "candidates", "neighborhood")
    gen = os.path.join(root, "assets", "generated", "city_neighborhood")
    prev = os.path.join(root, "assets", "previews", "city_neighborhood")
    for d in (cand, gen, prev):
        os.makedirs(d, exist_ok=True)
    only = [x for x in a.only.split(",") if x]
    unknown = [x for x in only if x not in BUILDINGS]
    if unknown:
        p.error(f"unknown building ids {unknown}; registered: {sorted(BUILDINGS)}")
    shots = [x for x in a.only_shots.split(",") if x]
    entries = {}
    mpath = os.path.join(cand, "neighborhood_manifest.json")
    if only and os.path.exists(mpath):
        with open(mpath, encoding="utf-8") as f:
            entries = {e["id"]: e for e in json.load(f)["assets"]}
    for bid, spec in BUILDINGS.items():
        if only and bid not in only:
            continue
        entries[bid] = build_one(bid, spec, cand, gen, prev, not a.no_render, a.size, shots)
    manifest = {"version": 1, "status": "candidate-review", "assets": [entries[b] for b in BUILDINGS if b in entries]}
    with open(mpath, "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    report(done="neighborhood", ids=[e["id"] for e in manifest["assets"]])


# ---------------------------------------------------------------------------- building: service_tenement

TG = (-8.0, 8.0, -7.5, 7.0)         # ground block
ZT0 = 5.2                           # first tier floor (ground block roof)
TH = 5.4                            # tier height
NT = 4
ZTOP = ZT0 + NT * TH                # wing roofs
WL, WR = (-8.0, -2.4), (2.4, 8.0)   # wing x spans
YB, YF, YREC = -3.8, 7.0, 4.4       # wing rear / full front / recessed front
SPY = -1.0                          # life-support spine axis y
T_TARGETS = {}


def t_ground(k, rng):
    L = face_len("F", TG)
    wf = [(fit_strip, 1.2, 5.2, 1.0, 3.1, dict(cells=3)), (fit_entry, 6.8, 9.4, 0.0, 3.3, dict(awning=True, lamp="glow_cyan")),
          (fit_strip, 11.0, 14.8, 1.0, 3.1, dict(cells=3))]
    T_TARGETS["entry"], T_TARGETS["activity"] = TG[0] + 8.1, TG[0] + 3.2
    avoid = [(0.0, 0.0)]
    wb = [(fit_entry, 6.0, 8.6, 0.0, 3.3, dict(awning=True))] + bays(rng, 0, L, 1.2, 1, 3.4, [("slits", 3), ("bars", 2)],
                                                                      avoid=[(5.0, 9.6)], margin=1.2)
    side = [("shutter", 3.0, 4.4, 1.1, 2.7, dict(frac=0.4, lit=True))] + bays(rng, 7.0, 13.0, 1.2, 1, 3.4, [("slits", 3), ("bars", 1)], margin=0.8)
    shell(k, TG, 0.0, ZT0, rng, {"F": wf, "B": wb, "L": side, "R": list(side)}, t=dict(F=0.9, B=0.9, L=0.9, R=0.9),
          akw=dict(cov=0.65, repair=0.2, max_rib=2, cw=(2.4, 4.0)), extra_excl={"F": [(0.9, 5.6, 3.3, 4.9), (6.4, 9.8, 3.4, 4.9), (10.7, 15.1, 3.3, 4.9)]},
          patches=1, base_cornice=False)
    with face_frame(k, "F", TG):
        sign_plate(k, 1.4, 5.0, 3.6, 4.3, "H-07", rng, lit=True)
        sign_plate(k, 7.2, 9.0, 3.6, 4.3, "A-1", rng)
        sign_plate(k, 11.4, 14.4, 3.6, 4.3, "R-44", rng)
        awning(k, 1.0, 5.4, 0.1, 1.5, 3.3, 0.5, rng, rng.choice(TEAL), True, 0.0)
        awning(k, 10.8, 15.0, 0.1, 1.5, 3.3, 0.5, rng, rng.choice(OXIDE), True, 0.0)
        for x in (0.6, 5.6, 10.2, 15.4):
            lamp(k, x, 0.15, 3.2, "glow_amber", 0.05)
    with k.part(".street"):
        for x in (-7.0, -4.2, 4.4, 6.5):
            crate(k, x, 8.0, 0.0, rng.uniform(0.5, 0.9), 0.6, rng.uniform(0.4, 0.9), rng)
        drum(k, -2.2, 8.2, 0.0, rng, 0.3, 0.9)
        k.box(-7.4, -5.6, 8.0, 8.5, 0.45, 0.5, "machinery")                 # bench
        for sx in (-7.3, -5.7):
            k.box(sx, sx + 0.06, 8.05, 8.45, 0.0, 0.45, "steel", skip=("zn",))
        person(k, -6.5, 8.9, 0.0, rng, 0.3)
        person(k, 3.0, 8.6, 0.0, rng, 3.0)
        for x in (-4.8, 4.8):
            k.box(x - 0.05, x + 0.05, 8.7, 8.8, 0.0, 3.4, "steel", skip=("zn",))   # lamp post
            lamp(k, x, 8.75, 3.5, "glow_amber", 0.1)


def t_wings(k, rng):
    z = ZT0
    for i in range(NT):
        z0, z1 = ZT0 + i * TH, ZT0 + (i + 1) * TH
        for side, (x0, x1) in (("l", WL), ("r", WR)):
            rec = (i % 2 == 1) if side == "l" else (i % 2 == 0)
            yf = YREC if rec else YF
            bx = (x0, x1, YB, yf)
            Lf = x1 - x0
            door = (fit_door, 1.4, 2.8, 0.0 + z0, 2.4 + z0, dict(awning=False, lamp="glow_cyan" if (i + (side == "l")) % 2 else "glow_amber"))
            wf = [door] + bays(rng, 0, Lf, z0, 1, TH, [("shutter", 4), ("strip", 1)], avoid=[(1.2, 3.0)], margin=0.7, gap=(0.8, 1.6),
                               sill=1.1, wh=(1.4, 1.9))
            fl = yf - YB
            wo = bays(rng, 0.9, fl - 0.9, z0, 1, TH, [("shutter", 3), ("bars", 1), ("porthole", 1)], margin=0.8, sill=1.1, wh=(1.4, 1.9))
            wi = bays(rng, 0.9, fl - 0.9, z0, 1, TH, [("slits", 1), ("shutter", 2)], margin=0.8, sill=1.1, wh=(1.4, 1.9))
            wb = bays(rng, 0, Lf, z0, 1, TH, [("louvre", 2), ("slits", 2), ("bars", 1)], margin=0.7, sill=1.1)
            if side == "r" and i in (0, 2, 4):
                wo = [(fit_door, 1.4, 2.7, z0, z0 + 2.4, dict(awning=False, lamp="glow_amber"))] + [h for h in wo if h[1] > 3.3]
            win = {"F": wf, "B": wb}
            win.update({"L": wo, "R": wi} if side == "l" else {"L": wi, "R": wo})
            shell(k, bx, z0, z1, rng, win, akw=dict(cov=0.5, repair=0.16, max_rib=1, cw=(2.4, 4.2), rows=(1.3, 2.2)), patches=1,
                  base_cornice=(i == 0), corner=i in (0, NT - 1))
            if rec:
                gx0, gx1 = (x0 - 0.5, x1) if side == "l" else (x0, x1 + 0.5)
                with k.part(".gallery"):
                    gallery(k, gx0, gx1, yf - 0.2, YF + 0.5, z0, rng, edges="F" + ("L" if side == "l" else "R"), brace=True)
                    laundry(k, (x0 + 0.3, yf + 0.3, z0 + 3.5), (x1 - 0.3, YF + 0.2, z0 + 3.3), rng, 5)
                    planter(k, x0 + 0.4, x0 + 1.4, YF - 0.1, YF + 0.3, z0, rng)
                    drum(k, x1 - 0.7, yf + 0.7, z0, rng, 0.28, 0.85)
                    person(k, (x0 + x1) / 2 + 0.5, yf + 1.0, z0, rng, pi * 1.2, i % 2 == 0)
                    lamp(k, (x0 + x1) / 2, YF + 0.45, z0 + 1.2, "glow_amber" if i % 2 else "glow_cyan", 0.045)
        with k.part(".bridges"):
            gallery(k, WL[1] - 0.1, WR[0] + 0.1, 5.6, YF + 0.5, z0, rng, edges="F", brace=False, thick=0.25)
            for bx in (-1.6, 1.6):
                k.box(bx - 0.04, bx + 0.04, YF + 0.42, YF + 0.5, z0 + 0.0, z0 + 0.5, "cavity", skip=("zn",))
    # roofs of the top tier
    with k.part(".roofs"):
        for x0, x1 in (WL, WR):
            k.box(x0 - 0.1, x1 + 0.1, YB - 0.1, YF + 0.1, ZTOP, ZTOP + 0.25, "ceramic")


def t_spine(k, rng):
    z1 = ZTOP + 5.2
    with k.part(".spine"):
        spine(k, 0.0, SPY, 0.3, z1, 1.5, 1.9)
        for i in range(NT + 1):
            zz = ZT0 + i * TH - 0.2
            with k.at(0, SPY, zz):
                k.lathe([(1.9, 0.0), (1.9, 0.3), (1.6, 0.3), (1.6, 0.0)], "machinery", 12, False)
            k.box(-2.4, -1.5, SPY - 0.15, SPY + 0.15, zz + 0.05, zz + 0.22, "steel")
            k.box(1.5, 2.4, SPY - 0.15, SPY + 0.15, zz + 0.05, zz + 0.22, "steel")
        with k.at(0, SPY, z1):
            k.lathe([(1.7, 0.0), (1.7, 0.4), (2.2, 0.5), (2.2, 0.9), (1.2, 1.3), (0.3, 1.6)], "ceramic", 12, True)
        for a in range(4):
            th = a * pi / 2 + pi / 4
            lamp(k, 2.0 * math.cos(th), SPY + 2.0 * math.sin(th), z1 + 0.7, "glow_cyan" if a % 2 else "glow_amber", 0.09)
        k.pipe((0, SPY, z1 + 1.5), (0, SPY, z1 + 4.5), 0.06, "steel", 5)
        lamp(k, 0, SPY, z1 + 4.6, "glow_cyan", 0.1)
        # conduits hugging the inner wing faces (feeds from the spine to each tier)
        for sx in (-2.25, 2.25):
            conduit_bank(k, sx, -3.1, 0.3, ZTOP, 3, 0.13, rng, axis="y")
        for i in range(NT):
            zz = ZT0 + i * TH + 2.0
            tendon(k, [(-1.5, SPY - 1.0, zz), (-2.0, SPY - 0.2, zz + 0.4), (-2.3, SPY + 0.6, zz + 0.1)], 0.04) if i % 2 == 0 else \
                tendon(k, [(1.5, SPY - 1.0, zz), (2.0, SPY - 0.2, zz + 0.4), (2.3, SPY + 0.6, zz + 0.1)], 0.04)
    with k.part(".lift"):
        # lift core: cage in front of the spine with a car, cables, counterweight guides and a machine head house
        post = [(-1.8, 2.5), (1.8, 2.5), (-1.8, 5.1), (1.8, 5.1)]
        for px, py in post:
            column(k, px, py, ZT0, ZTOP + 3.4, 0.22, "machinery")
        for i in range(NT + 1):
            zz = ZT0 + i * TH
            k.box(-1.9, 1.9, 2.4, 2.6, zz, zz + 0.15, "steel")
            k.box(-1.9, 1.9, 5.0, 5.2, zz, zz + 0.15, "steel")
            for sx in (-1.9, 1.7):
                k.box(sx, sx + 0.2, 2.5, 5.1, zz, zz + 0.15, "steel")
            lamp(k, 1.6, 5.25, zz + 1.6, "glow_cyan" if i % 2 else "glow_amber", 0.05)
        k.box(-1.75, 1.75, 2.35, 2.5, ZT0, ZTOP + 3.0, "steel")          # shaft back wall
        with face_frame(k, "B", (-1.8, 1.8, 2.35, 5.1)):
            armor_field(k, 0.0, 3.6, ZT0 + 0.3, ZTOP + 2.8, [], rng, y=0.0, cov=0.7, repair=0.2, max_rib=1)
        for sx in (-1.0, 1.0):
            k.box(sx - 0.05, sx + 0.05, 2.6, 2.75, ZT0, ZTOP + 3.0, "machinery")      # guide rails
        zc = ZT0 + 2 * TH + 0.2
        k.box(-1.5, 1.5, 2.9, 4.9, zc, zc + 2.7, "machinery")
        k.box(-1.3, 1.3, 4.85, 5.0, zc + 0.1, zc + 2.5, "cavity")
        k.box(-0.9, 0.9, 4.9, 5.0, zc + 2.5, zc + 2.55, "glow_amber")
        for cx in (-0.6, 0.6):
            k.pipe((cx, 3.6, zc + 2.7), (cx, 3.6, ZTOP + 3.0), 0.03, "steel", 4)
        k.box(-1.0, 1.0, 3.0, 4.6, ZT0 + 0.3, ZT0 + 1.4, "steel")                     # counterweight
        shell(k, (-2.3, 2.3, 1.8, 5.8), ZTOP + 3.0, ZTOP + 6.2, rng, {"F": [("slits", 0.9, 3.0, ZTOP + 4.2, ZTOP + 5.2, {})]}, corner=True,
              akw=dict(cov=0.75), base_cornice=True)


def t_service(k, rng):
    with k.part(".rear"):
        # filtration bank under a supported maintenance deck
        deck(k, -7.0, 7.0, -11.6, -7.5, ZT0 + 0.8, "machinery", 0.3, True, rng)
        for cx in (-6.0, -3.6, -1.2, 1.2, 3.6, 6.0):
            canister(k, cx, -9.1, 0.0, 5.0, 0.62)
        for cx in (-6.0, -3.6, -1.2, 1.2, 3.6, 6.0):
            k.pipe((cx, -9.1, 5.1), (cx, -9.1, ZT0 + 0.5), 0.09, "machinery", 5)
        pipe_run(k, [(-6.0, -9.1, 4.2), (-6.0, -8.1, 4.2), (6.0, -8.1, 4.2)], 0.17, "machinery", 2.5)
        for cx in (-3.6, 3.6):
            valve(k, cx + 0.3, -8.1, 4.4, 0.13)
            gauge(k, cx, -8.0, 3.3)
        for cx in (-6.8, 6.8):
            column(k, cx, -11.3, 0.0, ZT0 + 0.5, 0.24)
            column(k, cx, -7.8, 0.0, ZT0 + 0.5, 0.24)
        xbrace(k, (-6.8, -11.3, 0.3), (-6.8, -7.8, ZT0 + 0.4), (-6.8, -7.8, 0.3), (-6.8, -11.3, ZT0 + 0.4))
        xbrace(k, (6.8, -11.3, 0.3), (6.8, -7.8, ZT0 + 0.4), (6.8, -7.8, 0.3), (6.8, -11.3, ZT0 + 0.4))
        railing(k, (-7.0, -11.5, ZT0 + 0.8), (7.0, -11.5, ZT0 + 0.8), 1.05, 1.5)
        railing(k, (-7.0, -11.5, ZT0 + 0.8), (-7.0, -7.7, ZT0 + 0.8), 1.05, 1.5)
        stair(k, (13.0, -10.0, 0.0), pi / 2, 6.0, ZT0 + 0.8, 1.1, 0.19)
        k.box(7.0, 8.2, -10.6, -9.4, ZT0 + 0.68, ZT0 + 0.8, "machinery")
        # rear risers up the full height with brackets, and a tank row on the first roof
        for rx in (-4.8, 4.8):
            conduit_bank(k, rx, -7.9, ZT0 + 0.8, ZTOP + 0.6, 3, 0.2, rng)
            for zz in range(int(ZT0 + 2), int(ZTOP), 4):
                k.box(rx - 0.9, rx + 0.9, -7.9, -7.5, zz, zz + 0.1, "steel")
        for zz in (ZT0 + 2.0, ZT0 + TH * 2 + 2.0, ZT0 + TH * 3 + 2.0):
            tendon(k, [(-2.0, -7.55, zz), (-1.5, -7.7, zz + 0.4), (-1.0, -7.55, zz + 0.9), (-0.4, -7.7, zz + 0.5)], 0.05)
        for x in (-2.5, 0.0, 2.5):
            lamp(k, x, -7.7, ZT0 + 1.8, "glow_amber", 0.06)
    # rear sections (rear block above the filtration deck)
    for j in range(NT // 2):
        z0, z1 = ZT0 + j * 2 * TH, ZT0 + (j + 1) * 2 * TH
        wb = bays(rng, 0, 16.0, z0, 2, TH, [("slits", 3), ("bars", 2), ("porthole", 2)], margin=1.0, gap=(2.4, 3.8), sill=1.2, wh=(1.2, 1.7))
        ws = bays(rng, 0.75, 3.0, z0, 2, TH, [("slits", 2), ("porthole", 1)], margin=0.5)
        shell(k, (-8.0, 8.0, -7.5, YB), z0, z1, rng, {"B": wb, "L": ws, "R": ws},
              akw=dict(cov=0.55, repair=0.2, max_rib=1, cw=(2.6, 4.4), rows=(1.4, 2.4)), patches=1, base_cornice=(j == 0), corner=(j == 0))


def t_maintenance(k, rng):
    """Supported maintenance access along the right wing: columns, three walkway decks, braces, cage ladders, stair."""
    with k.part(".maint"):
        xc = 11.2
        ys = (-3.4, 1.5, 6.4)
        for y in ys:
            column(k, xc, y, 0.0, ZTOP + 1.0, 0.26)
        for j, (ya, yb) in enumerate(zip(ys[:-1], ys[1:])):
            for z0 in (0.2, ZT0, ZT0 + 2 * TH, ZT0 + 4 * TH):
                z1 = z0 + (ZT0 if z0 < 1 else 2 * TH) - (0.2 if z0 < 1 else 0)
                if z1 > ZTOP + 1.0:
                    continue
                xbrace(k, (xc, ya, z0), (xc, yb, z1), (xc, yb, z0), (xc, ya, z1), 0.07)
        for z in (ZT0, ZT0 + 2 * TH, ZT0 + 4 * TH):
            deck(k, 8.0, 11.7, -4.0, 7.0, z, "machinery", 0.25, True, rng)
            railing(k, (11.65, -4.0, z), (11.65, 7.0, z), 1.05, 1.5)
            railing(k, (8.0, 7.0, z), (11.65, 7.0, z), 1.05, 1.5)
            railing(k, (8.0, -4.0, z), (11.65, -4.0, z), 1.05, 1.5)
            lamp(k, 11.6, 3.0, z + 1.2, "glow_cyan", 0.05)
            drum(k, 9.4, -3.0, z, rng, 0.28, 0.8)
        for z0 in (ZT0, ZT0 + 2 * TH):
            ladder(k, 10.4, -3.7, z0, z0 + 2 * TH + 0.1, 0.45, "x", cage=True)
        top = stair(k, (10.0, -10.2, 0.0), 0.0, 6.2, ZT0, 1.1, 0.19)
        pipe_run(k, [(8.4, 0.0, 0.3), (8.4, 0.0, ZTOP - 1.0), (8.4, 3.0, ZTOP - 1.0)], 0.16, "machinery", 2.4)
        for z in range(1, int(ZTOP), 5):
            stand_off(k, Vector((8.4, 0.0, z + 0.0)), "x", 8.0, 0.16)
        person(k, 9.6, 2.5, ZT0 + 2 * TH, rng, 1.6, False)


def t_left_roof(k, rng):
    with k.part(".left"):
        # left flank: heavy trunk mains, cable runs, canister cluster at the foot
        for i, y in enumerate((-2.5, 0.2, 2.9)):
            pipe_run(k, [(-8.5, y, 0.3), (-8.5, y, ZTOP + 1.0)], 0.2 - 0.02 * i, "machinery", 2.6)
            for z in range(2, int(ZTOP), 5):
                stand_off(k, Vector((-8.5, y, z)), "x", -8.0, 0.2)
        for z in (ZT0 + 2.0, ZT0 + TH + 2.0, ZT0 + 3 * TH + 2.0):
            tendon(k, [(-8.15, -1.0, z), (-8.35, 0.2, z + 0.5), (-8.2, 1.6, z + 0.1), (-8.3, 2.8, z + 0.8)], 0.05)
        for i, y in enumerate((-5.5, -3.5)):
            canister(k, -9.6, y, 0.0, 3.8, 0.55)
        cistern(k, -9.8, 3.8, 0.0, 0.8, 2.8, rng)
        deck(k, -10.4, -8.0, 1.0, 6.5, ZT0 - 0.0, "machinery", 0.25, True, rng)
        railing(k, (-10.4, 1.0, ZT0), (-10.4, 6.5, ZT0), 1.05, 1.5)
        for y in (1.2, 6.3):
            column(k, -10.2, y, 0.0, ZT0 - 0.3, 0.2)
    with k.part(".roof"):
        rr = random.Random("t_roof")
        for x0, x1 in (WL, WR):
            for hx in (x0 + 1.0, x1 - 1.0):
                k.box(hx - 0.6, hx + 0.6, -3.0, -2.0, ZTOP + 0.25, ZTOP + 1.0, "machinery")
        cistern(k, -5.2, 3.0, ZTOP + 0.25, 0.9, 2.2, rr)
        cistern(k, -3.5, 3.0, ZTOP + 0.25, 0.7, 1.8, rr)
        pipe_run(k, [(-4.3, 3.0, ZTOP + 2.3), (-4.3, 0.0, ZTOP + 2.3), (-4.3, 0.0, ZTOP + 1.0)], 0.1, "machinery")
        with k.at(5.5, 2.0, ZTOP + 0.25):
            k.lathe([(0.0, 0.0), (0.8, 0.12), (1.5, 0.5), (1.55, 0.55)], "ceramic", 8, True)
            k.cyl(0, 0, -0.0, 0.1, 1.2, "steel", seg=5)
        k.beam((7.2, 5.5, ZTOP + 0.25), (7.2, 5.5, ZTOP + 6.0), 0.1, 0.1, "steel")
        lamp(k, 7.2, 5.5, ZTOP + 6.1, "glow_amber", 0.1)
        for hx in (-6.5,):
            laundry(k, (-7.4, -1.0, ZTOP + 2.0), (-3.0, -1.0, ZTOP + 2.0), rr, 6)
        for p in ((-7.4, -1.0), (-3.0, -1.0)):
            k.box(p[0] - 0.04, p[0] + 0.04, p[1] - 0.04, p[1] + 0.04, ZTOP + 0.25, ZTOP + 2.05, "steel", skip=("zn",))
        ladder(k, 7.0, -3.5, ZTOP + 0.25, ZTOP + 1.5, 0.45, "x")


T_PARTS = [t_ground, t_wings, t_spine, t_service, t_maintenance, t_left_roof]


@building("service_tenement", cls="building", parts=T_PARTS, facade=(TG, 7.0), tint=(0.9, 0.97, 1.0),
          identity="Narrow tall block of stacked inhabited rooms and deep recessed galleries wrapped round a segmented life-support "
                   "spine and an open lift core; rear filtration bank under a supported deck and an exterior maintenance tower.",
          brief="Faded blue/teal repair panels over chipped bone armour on dark steel; sparse tendons; tiny cyan/amber lamps.")
def tenement_targets(off):
    """Design-space (x, y, z) review points: ground entrance, street shop counter and the rear filtration bank."""
    return dict(entry=(T_TARGETS["entry"], 8.4, 1.3), activity=(T_TARGETS["activity"], 8.4, 1.3), service=(0.0, -12.6, 1.8))


SHOTS["service_tenement"] = [
    ("front_studio", 0, (0, 70, 20), (0, 0, 16), 38, None, (1200, 1600)),
    ("front_three_quarter", -25, (-36, 46, 26), (0, 0, 15), 38, None, (1600, 1200)),
    ("entry_street_human", 0, (-2, 22, 1.6), (0, 6, 4.5), 30, (1.5, 13.0), (1600, 1200)),
    ("activity_gallery", 0, (-14, 18, 8.5), (-5, 6, 12), 32, None, (1600, 1200)),
    ("rear_service", 180, (6, -38, 10), (0, -8, 12), 34, (-1.0, -14.0), (1600, 1200)),
    ("roof_service", 180, (-24, -22, 50), (0, 0, 24), 36, None, (1600, 1200)),
    ("maintenance_side", 90, (50, 0, 10), (9, 0, 14), 36, (20.0, 3.0), (1600, 1200)),
    ("lift_core_closeup", 0, (3, 20, 14), (0, 5, 18), 34, None, (1400, 1050)),
]

sys.path.insert(0, _HERE)
try:  # freight_depot: register(module) uses @building / SHOTS / shared components from this module
    import city_neighborhood_depot
except ImportError:
    city_neighborhood_depot = None
if city_neighborhood_depot is not None:
    city_neighborhood_depot.register(sys.modules[__name__])

if __name__ == "__main__":
    main()
