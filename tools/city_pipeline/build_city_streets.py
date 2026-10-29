"""Reusable street kit for the finished Block Circuit block: eight small static models.

Run (never the GUI):  ak-blender tools/city_pipeline/build_city_streets.py -- [--no-render] [--size 1.0]
                      [--only drain_cover,bollard] [--only-shots a,b]

Reuses the approved habitation_workshop Kit / colour / material / export / studio helpers (imported by path, never edited).
Design space is the workshop's: +Y front (Godot -Z), +Z up, a root X mirror in the Kit. Every model is one foot-centred
static mesh (xz footprint centre at the origin, lowest point at y=0) with real COLOR_0 grime / repair tints. The shared
main() builds each registered model from a clean Blender scene, exports the GLB, and only then wires the preview-only
vertex-colour multiply so the exported materials stay pristine.
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

Kit, SEM, report, args, stencil, pipe_run, stand_off = W.Kit, W.SEM, W.report, W.args, W.stencil, W.pipe_run, W.stand_off

# id -> (tri cap, expected glTF size x/y/z in metres, tolerance, minimum tris, class note)
SPECS = {
    "sidewalk_panel": dict(cap=450, size=(6.0, 0.18, 4.0), tol=0.02, min_tris=200),
    "curb_segment": dict(cap=180, size=(6.0, 0.22, 0.22), tol=0.02, min_tris=70),
    "drain_cover": dict(cap=300, size=(1.2, 0.06, 0.7), tol=0.02, min_tris=140),
    "street_lamp": dict(cap=1600, size=(0.6, 8.0, 3.7), tol=0.5, min_tris=500),
    "bollard": dict(cap=300, size=(0.34, 1.1, 0.34), tol=0.1, min_tris=100),
    "bench_planter": dict(cap=1800, size=(3.8, 1.5, 1.2), tol=0.05, min_tris=600),
    "refuse_station": dict(cap=1800, size=(3.0, 2.2, 1.5), tol=0.05, min_tris=600),
    "alley_conduit": dict(cap=1800, size=(8.0, 4.5, 1.0), tol=0.05, min_tris=600),
}
IDS = tuple(SPECS)
BUILDERS = {}
SHOTS = {}

CONCRETE = [(0.78, 0.76, 0.72), (0.66, 0.64, 0.62), (0.84, 0.78, 0.7), (0.6, 0.6, 0.6), (0.72, 0.68, 0.62), (0.8, 0.8, 0.78)]
TEAL = (0.55, 0.82, 0.86)
OXIDE = (0.85, 0.5, 0.36)
OCHRE = (0.9, 0.72, 0.5)
GREEN = (0.42, 0.7, 0.4)
SOIL = (0.5, 0.36, 0.26)


def street_grime(k):
    """Street-level wear on top of the workshop tint: fine mottling plus gutter dirt low down and edge dust.
    A pure function of position, so rebuilding is idempotent. Emitters and cavities are left alone."""
    skip = {SEM.index(m) for m in ("glow_cyan", "glow_amber", "cavity")}
    for f in k.bm.faces:
        if f.material_index in skip:
            continue
        for lp in f.loops:
            p = lp.vert.co
            n = W.vnoise(p.x * 9.0 + 3, p.y * 9.0, p.z * 9.0 + 9)
            m = W.vnoise(p.x * 1.7, p.y * 1.7 + 4, p.z * 1.7)
            g = 0.92 + 0.45 * (n - 0.5) + 0.2 * (m - 0.5) - 0.22 * math.exp(-p.z / 0.3)
            c = lp[k.col]
            lp[k.col] = (max(0.05, min(1.0, c[0] * g)), max(0.05, min(1.0, c[1] * g * (0.97 + 0.03 * n))),
                         max(0.05, min(1.0, c[2] * g * (0.92 + 0.08 * m))), 1.0)


def street(sid, **meta):
    def deco(fn):
        BUILDERS[sid] = dict(meta, id=sid, build=fn)
        return fn
    return deco


def slab(k, cx, cy, hx, hy, z0, z1, ch, mat="ceramic"):
    """Chamfered paving slab: footprint half-extents hx/hy at the base, narrowed by `ch` at the top."""
    k.frustum(cx, cy, z0, z1, hx, hy, hx - ch, hy - ch, mat)


def crack(k, x, y, z, length, ang, w=0.014):
    with k.at(x, y, z, rz=ang):
        k.box(-length / 2, length / 2, -w / 2, w / 2, 0.0, 0.004, "cavity", skip=("zn",))


# ---------------------------------------------------------------------------- sidewalk_panel 6 x 4 x 0.18


@street("sidewalk_panel", cls="paving",
        identity="Six inset gray-brown paving slabs on a dark sub-base with settled heights, hairline cracks, a bolted steel "
                 "expansion strip, a bright replacement slab with a bolted service plate and a row of tactile studs on the kerb edge.",
        brief="Weathered ceramic paving, dark metal strip, restrained oxide/teal repairs.")
def sidewalk_panel(k, rng):
    k.box(-3.0, 3.0, -2.0, 2.0, 0.0, 0.10, "steel")
    tops = [0.168, 0.172, 0.165, 0.174, 0.16, 0.17]
    for r in range(2):
        for c in range(3):
            i = r * 3 + c
            cx, cy = -2.0 + c * 2.0, -1.0 + r * 2.0
            tone = CONCRETE[i % len(CONCRETE)]
            if i == 4:
                tone = (0.98, 0.97, 0.94)               # fresh replacement slab
            with k.look(rng.uniform(0.8, 1.0), tone):
                slab(k, cx, cy, 0.97, 0.97, 0.09, tops[i], 0.02)
    with k.look(0.9, (0.6, 0.65, 0.7)):                  # expansion joint plate across the middle seam
        k.box(-2.9, 2.9, -0.045, 0.045, 0.1, 0.176, "steel")
    for bx in (-2.5, -0.8, 0.9, 2.5):
        k.box(bx - 0.03, bx + 0.03, -0.03, 0.03, 0.176, 0.18, "trim", skip=("zn",))
    with k.look(0.85, TEAL):                              # bolted service plate on the replacement slab
        k.box(-0.55, 0.55, 0.45, 1.15, 0.168, 0.176, "machinery", skip=("zn",))
    for bx in (-0.45, 0.45):
        for by in (0.55, 1.05):
            k.box(bx - 0.025, bx + 0.025, by - 0.025, by + 0.025, 0.176, 0.18, "trim", skip=("zn",))
    for i in range(13):                                    # tactile studs along the kerb (front) edge
        x = -2.4 + i * 0.4
        k.box(x - 0.045, x + 0.045, 1.8, 1.89, 0.172, 0.18, "trim", skip=("zn",))
    for (x, y, ln, ang) in ((-2.1, -1.1, 0.8, 0.5), (1.5, -1.3, 0.6, -0.7), (2.2, 0.7, 0.7, 1.3), (-1.2, 1.2, 0.5, 2.4), (0.4, -0.6, 0.45, 0.2)):
        crack(k, x, y, 0.166, ln, ang)


# ---------------------------------------------------------------------------- curb_segment 6 x 0.22 x 0.22


@street("curb_segment", cls="paving",
        identity="Chamfered kerb run of four 1.5 m stones with cut joints and slightly settled tops, faded ochre hazard dashes and chipped corners.",
        brief="Weathered ceramic with dark joints and faded paint.")
def curb_segment(k, rng):
    for i in range(4):                                    # four 1.5 m stones with cut joints and slightly settled tops
        sink = (0.0, 0.004, 0.0, 0.007)[i]
        prof = [(0.0, 0.0), (0.22, 0.0), (0.22, 0.17 - sink), (0.19, 0.22 - sink), (0.03, 0.22 - sink), (0.0, 0.19 - sink)]
        with k.look(rng.uniform(0.85, 1.0), CONCRETE[i % len(CONCRETE)]):
            k.prism(prof, -3.0 + i * 1.5 + (0.008 if i else 0.0), -3.0 + (i + 1) * 1.5 - (0.008 if i < 3 else 0.0), "ceramic", "yz")
    for i in range(5):                                    # worn road-side hazard dashes (the faded paint is a vertex tint)
        x0 = -2.7 + i * 1.15
        with k.look(rng.uniform(0.55, 0.9), OCHRE):
            k.box(x0, x0 + 0.55, 0.19, 0.2205, 0.085, 0.145, "trim", skip=("zn", "xn", "xp", "yn"))
    for (x, y) in ((-2.95, 0.19), (-0.4, 0.02), (2.9, 0.19)):
        k.box(x - 0.03, x + 0.03, y - 0.015, y + 0.015, 0.2, 0.2205, "cavity", skip=("zn", "yn", "yp"))


# ---------------------------------------------------------------------------- drain_cover 1.2 x 0.7 x 0.06


@street("drain_cover", cls="fitting",
        identity="Cast steel storm-drain grating: flanged frame, eleven slotted bars over a dark sump, four bolts and a hinge lug.",
        brief="Dark metal with rust-brown grime and bright worn bar tops.")
def drain_cover(k, rng):
    k.box(-0.6, 0.6, -0.35, 0.35, 0.0, 0.03, "cavity")
    for (x0, x1, y0, y1) in ((-0.6, 0.6, -0.35, -0.28), (-0.6, 0.6, 0.28, 0.35), (-0.6, -0.52, -0.28, 0.28), (0.52, 0.6, -0.28, 0.28)):
        k.box(x0, x1, y0, y1, 0.0, 0.06, "steel")
    for i in range(11):
        x = -0.455 + i * 0.091
        with k.look(rng.uniform(0.75, 1.0), (0.9, 0.8, 0.72)):
            k.box(x - 0.026, x + 0.026, -0.28, 0.28, 0.025, 0.06, "machinery", skip=("zn", "xn", "xp") if i not in (0, 10) else ("zn",))
    k.box(-0.6, 0.6, -0.34, -0.28, 0.06, 0.063, "steel", skip=("zn",))
    for bx in (-0.56, 0.56):
        for by in (-0.31, 0.31):
            k.box(bx - 0.025, bx + 0.025, by - 0.025, by + 0.025, 0.06, 0.066, "trim", skip=("zn",))


# ---------------------------------------------------------------------------- street_lamp ~8 m


@street("street_lamp", cls="furniture",
        identity="Eight-metre dark-metal lamp pole on an octagonal plinth with service hatch, riser conduit and collars; a curved "
                 "arm carries a hooded amber luminaire over the carriageway, balanced by a banner boom with a faded hanging banner.",
        brief="Dark steel and ceramic plinth, brass collars, one amber lens, a small cyan status light.")
def street_lamp(k, rng):
    k.lathe([(0.3, 0.0), (0.3, 0.45), (0.25, 0.55), (0.17, 0.62), (0.13, 0.7)], "ceramic", 8, True)
    with k.look(0.8, OXIDE):
        k.lathe([(0.145, 0.65), (0.145, 0.7)], "trim", 8, False)
    k.box(-0.11, 0.11, 0.255, 0.285, 0.12, 0.42, "cavity", skip=("zn",))          # service hatch (front)
    k.box(-0.09, 0.09, 0.285, 0.3, 0.14, 0.4, "machinery", skip=("zn",))
    k.box(0.055, 0.075, 0.3, 0.315, 0.25, 0.3, "trim")
    k.box(-0.015, 0.015, 0.285, 0.305, 0.36, 0.385, "glow_cyan", skip=("zn",))
    k.lathe([(0.13, 0.7), (0.095, 0.9), (0.085, 3.0), (0.07, 6.9), (0.07, 7.0)], "steel", 8, False)
    for z, r in ((0.95, 0.125), (3.0, 0.1), (5.2, 0.09)):                       # collars
        with k.look(0.85, OCHRE):
            k.lathe([(r, z), (r, z + 0.09)], "trim", 8, False)
    with k.look(0.8, (0.7, 0.7, 0.72)):                                          # riser conduit with stand-offs
        k.pipe((0.0, -0.15, 0.7), (0.0, -0.15, 6.7), 0.026, "machinery", 5)
    for z in (1.4, 2.8, 4.2, 5.6):
        k.box(-0.012, 0.012, -0.145, -0.06, z - 0.035, z + 0.035, "steel")
    k.box(-0.07, 0.07, -0.2, -0.1, 6.6, 6.84, "machinery")                       # junction box
    k.box(-0.03, 0.03, -0.205, -0.2, 6.68, 6.74, "glow_cyan", skip=("zn", "yp"))
    k.box(-0.06, 0.06, -0.11, -0.06, 0.65, 0.72, "steel")
    # front arm: rises into a gooseneck and reaches over the road
    pts = [(0.0, 0.0, 6.95)] + [(0.0, 1.0 * math.sin(a) * 1.0, 6.95 + 0.75 * (1 - math.cos(a))) for a in [i * pi / 2 / 6 for i in range(1, 7)]]
    pts = [Vector(p) for p in pts]
    for a, b in zip(pts[:-1], pts[1:]):
        k.pipe(a, b, 0.05, "steel", 6)
    for p in pts[1:-1]:
        k.joint(p.x, p.y, p.z, 0.062, "steel")
    k.pipe((0, 0.0, 6.55), (0, 0.8, 7.35), 0.025, "machinery", 5)                # brace strut
    # hooded luminaire
    yc, zc = 1.45, 7.68
    k.box(-0.2, 0.2, yc - 0.42, yc + 0.42, zc, zc + 0.12, "ceramic")
    k.box(-0.17, 0.17, yc - 0.38, yc + 0.38, zc + 0.12, zc + 0.15, "steel")
    for fy in (-0.28, -0.1, 0.08, 0.26):
        k.box(-0.15, 0.15, yc + fy - 0.02, yc + fy + 0.02, zc + 0.15, zc + 0.2, "machinery")
    k.box(-0.19, 0.19, yc - 0.4, yc + 0.4, zc - 0.03, zc, "steel")
    k.box(-0.15, 0.15, yc - 0.33, yc + 0.33, zc - 0.045, zc - 0.03, "glow_amber", skip=("zp",))
    k.box(-0.02, 0.02, yc - 0.44, yc - 0.4, zc + 0.04, zc + 0.08, "glow_cyan")
    for sy in (-0.4, 0.4):
        k.box(-0.21, 0.21, yc + sy - 0.01, yc + sy + 0.01, zc - 0.04, zc + 0.12, "trim")
    # rear banner boom with faded banner and end cap
    k.pipe((0.0, -0.05, 6.35), (0.0, -1.85, 6.35), 0.035, "steel", 6)
    k.pipe((0.0, 0.0, 5.7), (0.0, -1.0, 6.3), 0.024, "machinery", 5)
    k.joint(0.0, -1.85, 6.35, 0.05, "trim")
    with k.look(0.82, TEAL):
        k.box(-0.012, 0.012, -1.55, -0.85, 4.55, 6.3, "machinery", skip=("yn", "yp"))
    with k.look(0.8, OXIDE):
        k.box(-0.016, 0.016, -1.5, -0.9, 5.7, 5.82, "trim")
        k.box(-0.016, 0.016, -1.4, -1.0, 5.35, 5.45, "trim")
    for y in (-1.55, -0.85):
        k.box(-0.015, 0.015, y - 0.012, y + 0.012, 4.52, 6.33, "steel", skip=("yn", "yp"))
    k.box(-0.016, 0.016, -1.57, -0.83, 4.5, 4.55, "steel")


# ---------------------------------------------------------------------------- bollard ~1.1 m


@street("bollard", cls="furniture",
        identity="Fat eight-sided steel bollard with a base flange, dome cap, glowing amber reflector band, worn hazard collar and dents.",
        brief="Dark metal, oxide scuffs, one amber band, tiny cyan pip.")
def bollard(k, rng):
    k.lathe([(0.17, 0.0), (0.17, 0.05), (0.135, 0.07), (0.115, 0.1), (0.115, 0.95), (0.1, 1.03), (0.06, 1.09), (0.0, 1.1)], "steel", 8, True)
    with k.look(0.9, OCHRE):
        k.lathe([(0.121, 0.26), (0.121, 0.4)], "trim", 8, False)
    with k.look(0.7, OXIDE):
        k.lathe([(0.121, 0.4), (0.121, 0.44)], "trim", 8, False)
    k.lathe([(0.121, 0.74), (0.121, 0.86)], "glow_amber", 8, False)
    for z in (0.7, 0.9):
        k.lathe([(0.123, z - 0.015), (0.123, z + 0.015)], "machinery", 8, False)
    k.box(-0.04, 0.04, 0.11, 0.125, 0.5, 0.6, "cavity", skip=("zn",))                 # dent
    k.box(0.1, 0.112, -0.05, 0.06, 0.12, 0.2, "cavity", skip=("zn",))
    k.box(-0.015, 0.015, -0.015, 0.015, 1.1, 1.115, "glow_cyan", skip=("zn",))
    for a in range(4):                                                              # anchor bolts
        th = pi / 4 + a * pi / 2
        k.box(0.15 * math.cos(th) - 0.02, 0.15 * math.cos(th) + 0.02, 0.15 * math.sin(th) - 0.02, 0.15 * math.sin(th) + 0.02,
              0.05, 0.075, "trim", skip=("zn",))


# ---------------------------------------------------------------------------- bench_planter 3.8 x 1.2 x 1.5


def plant(k, x, y, z, h, rng, spread=0.13):
    with k.look(rng.uniform(0.7, 1.0), GREEN):
        with k.at(x, y, 0.0):
            k.lathe([(0.03, z), (0.012, z + h)], "ceramic", 5, False)
        for i in range(2):
            with k.at(x, y, z + h * (0.55 + 0.4 * i)):
                k.lathe([(0.0, 0.0), (spread * (1.0 - 0.25 * i), 0.03), (0.0, 0.07)], "ceramic", 6, False)


@street("bench_planter", cls="furniture",
        identity="Street bench with slatted seat and backrest on cast steel supports, armrests and an under-seat cyan strip, fused to a "
                 "raised planter box with a rim, bolt rows, soil, drip line, ground-cover and a small tree.",
        brief="Dark steel frames, warm worn slats with one teal replacement, greens, tiny amber and cyan lights.")
def bench_planter(k, rng):
    # planter (left)
    k.box(-1.88, -0.62, -0.58, 0.58, 0.0, 0.58, "steel")
    k.box(-1.9, -0.6, -0.6, 0.6, 0.58, 0.66, "ceramic")
    with k.look(0.85, SOIL):
        k.box(-1.84, -0.66, -0.54, 0.54, 0.62, 0.7, "trim", skip=("zn",))
    for bx in (-1.7, -1.25, -0.8):
        k.box(bx - 0.025, bx + 0.025, 0.58, 0.6, 0.15, 0.2, "trim", skip=("yn",))
        k.box(bx - 0.025, bx + 0.025, 0.58, 0.6, 0.4, 0.45, "trim", skip=("yn",))
    for y0, y1 in ((-0.6, -0.58), (0.58, 0.6)):
        k.box(-1.9, -0.6, y0, y1, 0.28, 0.32, "machinery")
    # tree + ground cover
    with k.at(-1.25, 0.0, 0.0):
        k.lathe([(0.06, 0.7), (0.04, 1.05), (0.025, 1.2)], "steel", 6, False)
    with k.look(0.85, GREEN):
        with k.at(-1.25, 0.0, 1.05):
            k.lathe([(0.0, 0.0), (0.38, 0.1), (0.3, 0.3), (0.0, 0.45)], "ceramic", 7, True)
    with k.look(0.78, GREEN):
        with k.at(-1.25, 0.0, 0.95):
            k.lathe([(0.0, 0.0), (0.5, 0.06), (0.0, 0.2)], "ceramic", 8, True)
    for (x, y) in ((-1.7, 0.35), (-1.6, -0.35), (-0.85, 0.35), (-0.8, -0.3), (-1.25, 0.42), (-1.25, -0.42), (-1.0, 0.0), (-1.55, 0.0)):
        plant(k, x, y, 0.7, rng.uniform(0.18, 0.4), rng)
    # drip line + emitter lamp
    pipe_run(k, [(-1.88, 0.585, 0.5), (-0.62, 0.585, 0.5)], 0.015, "machinery", 2.0)
    k.box(-0.64, -0.6, 0.54, 0.6, 0.7, 0.74, "glow_amber", skip=("zn",))
    # bench (right): seat, backrest, supports, armrests
    for sx in (-0.4, 0.2, 1.8):
        k.box(sx, sx + 0.1, -0.55, 0.05, 0.0, 0.1, "steel")
        k.box(sx + 0.02, sx + 0.08, -0.55, 0.0, 0.1, 0.42, "steel")
        k.box(sx + 0.02, sx + 0.08, -0.58, -0.5, 0.1, 0.92, "steel")
    k.box(-0.45, 1.9, -0.56, -0.5, 0.36, 0.4, "steel")
    k.box(-0.45, 1.9, -0.58, -0.56, 0.36, 0.4, "steel")
    for i in range(5):
        y = -0.5 + i * 0.12
        with k.look(0.9, TEAL if i == 3 else (0.95, 0.72, 0.5)):
            k.box(-0.45, 1.9, y, y + 0.1, 0.42, 0.47, "machinery")
    for i in range(3):
        z = 0.52 + i * 0.16
        with k.look(0.88, TEAL if i == 1 else (0.95, 0.72, 0.5)):
            k.box(-0.45, 1.9, -0.58, -0.54, z, z + 0.12, "machinery")
    for ax in (-0.4, 0.8, 1.88):
        k.box(ax - 0.03, ax + 0.03, -0.5, 0.04, 0.47, 0.5, "steel")
        k.box(ax - 0.03, ax + 0.03, 0.0, 0.04, 0.5, 0.64, "steel", skip=("zn",))
    k.box(-0.35, 1.8, -0.505, -0.495, 0.3, 0.33, "glow_cyan", skip=("zn",))
    k.box(-0.35, 1.8, 0.07, 0.1, 0.46, 0.5, "steel", skip=("zn",))          # front edge rail
    for sx in (0.35, 1.55):
        k.box(sx, sx + 0.1, 0.0, 0.07, 0.42, 0.5, "trim", skip=("zn",))
    k.box(-0.4, 1.9, -0.6, -0.52, 0.9, 0.94, "steel")
    k.box(0.2, 0.8, 0.07, 0.12, 0.44, 0.48, "trim", skip=("zn",))
    k.box(-0.02, 0.02, 0.07, 0.11, 0.0, 0.06, "steel")


# ---------------------------------------------------------------------------- refuse_station 3 x 1.5 x 2.2


@street("refuse_station", cls="furniture",
        identity="Open-fronted waste-sorting shelter: floor plate, four posts, louvred back wall with stencilled A/B/C chutes, canopy roof with drip "
                 "lip, three wheeled bins (oxide, teal, gray) with lids and handles, status lights and a hanging tag.",
        brief="Dark metal shelter, painted bins, amber and cyan indicators.")
def refuse_station(k, rng):
    k.box(-1.5, 1.5, -0.75, 0.75, 0.0, 0.06, "ceramic")
    for x in (-1.45, 1.45):
        for y in (-0.7, 0.7):
            k.box(x - 0.05, x + 0.05, y - 0.05, y + 0.05, 0.06, 2.1, "steel", skip=("zn",))
    k.box(-1.5, 1.5, -0.74, -0.66, 0.06, 2.1, "machinery")                          # back wall
    for bx in (-0.95, 0.0, 0.95):                                                   # chute hatches with stencils
        k.box(bx - 0.3, bx + 0.3, -0.66, -0.62, 1.15, 1.75, "cavity", skip=("zn",))
        k.box(bx - 0.34, bx + 0.34, -0.66, -0.64, 1.72, 1.78, "steel", skip=("zn",))
        k.box(bx - 0.24, bx + 0.24, -0.62, -0.6, 1.2, 1.5, "machinery", skip=("zn",))
        k.box(bx - 0.08, bx + 0.08, -0.6, -0.57, 1.28, 1.32, "trim", skip=("zn",))
    for bx, ch in zip((-0.95, 0.0, 0.95), "ABC"):
        stencil(k, ch, bx - 0.05, 1.54, 0.05, "trim", -0.6)
    for i in range(6):
        z = 0.16 + i * 0.1
        k.box(-1.4, -1.25, -0.66, -0.58, z, z + 0.04, "steel")                      # vent slats on left end
        k.box(1.25, 1.4, -0.66, -0.58, z, z + 0.04, "steel")
    k.box(-1.5, 1.5, -0.75, 0.75, 2.1, 2.2, "ceramic")                              # canopy
    k.box(-1.5, 1.5, 0.73, 0.75, 2.07, 2.1, "steel")
    for sx in (-1.49, 1.49):
        k.box(sx - 0.01, sx + 0.01, -0.72, 0.72, 2.0, 2.1, "steel", skip=("zn",))
    for x in (-1.0, 0.0, 1.0):
        k.box(x - 0.2, x + 0.2, 0.2, 0.3, 2.0, 2.1, "steel")
    k.box(-1.4, 1.4, 0.69, 0.73, 1.9, 2.07, "machinery", skip=("zn",))
    k.box(-1.2, -1.0, 0.73, 0.75, 1.95, 2.03, "glow_amber", skip=("zn",))
    k.box(1.05, 1.15, 0.73, 0.75, 1.95, 2.03, "glow_cyan", skip=("zn",))
    # three bins
    for bx, tone in ((-0.95, OXIDE), (0.0, TEAL), (0.95, (0.62, 0.64, 0.66))):
        with k.look(rng.uniform(0.8, 0.95), tone):
            k.frustum(bx, -0.05, 0.12, 1.0, 0.36, 0.3, 0.42, 0.34, "machinery")
        with k.look(0.8, (0.6, 0.62, 0.66)):
            k.box(bx - 0.4, bx + 0.4, -0.4, 0.3, 1.0, 1.08, "steel")
        k.box(bx - 0.15, bx + 0.15, 0.3, 0.37, 0.95, 1.0, "trim", skip=("zn",))
        k.box(bx - 0.36, bx + 0.36, 0.29, 0.31, 0.15, 0.2, "steel", skip=("zn",))
        for wx in (-0.3, 0.3):
            with k.at(bx + wx, -0.3, 0.1, ry=pi / 2):
                k.lathe([(0.1, -0.03), (0.1, 0.03)], "cavity", 6, True)
        k.box(bx - 0.05, bx + 0.05, 0.3, 0.33, 0.7, 0.73, "steel")
    # hanging tag chain
    k.pipe((0.55, 0.7, 1.9), (0.55, 0.7, 1.55), 0.008, "steel", 4)
    with k.look(0.9, OCHRE):
        k.box(0.47, 0.63, 0.69, 0.71, 1.4, 1.55, "trim")
    # dirt stains
    for (x, y, w) in ((-0.3, 0.25, 0.5), (0.6, -0.1, 0.4), (-1.2, 0.0, 0.3)):
        with k.look(0.45, (0.8, 0.75, 0.7)):
            k.box(x - w / 2, x + w / 2, y - 0.2, y + 0.2, 0.06, 0.064, "machinery", skip=("zn",))


# ---------------------------------------------------------------------------- alley_conduit 8 x 1 x 4.5


@street("alley_conduit", cls="overhead",
        identity="Overhead utility run for an eight-metre alley: three portal frames with braced posts carry two fat pipes, a smaller "
                 "flanged line and a cable tray with sagging cable drops, a junction box with amber and cyan lights and a faded hazard tag.",
        brief="Dark metal frames, ochre pipe tones, restrained oxide and teal repair colours.")
def alley_conduit(k, rng):
    zx = [-3.8, 0.0, 3.8]
    for x in zx:
        for y in (-0.36, 0.36):
            k.box(x - 0.1, x + 0.1, y - 0.07, y + 0.07, 0.0, 4.35, "steel")
            k.box(x - 0.17, x + 0.17, y - 0.12, y + 0.12, 0.0, 0.1, "machinery")
            for bx in (-1, 1):
                for by in (-1, 1):
                    k.box(x + bx * 0.13 - 0.015, x + bx * 0.13 + 0.015, y + by * 0.09 - 0.015, y + by * 0.09 + 0.015, 0.1, 0.13, "trim", skip=("zn",))
        k.box(x - 0.1, x + 0.1, -0.48, 0.48, 4.35, 4.47, "machinery")                  # portal beam
        k.box(x - 0.12, x + 0.12, -0.48, 0.48, 4.47, 4.5, "steel")
        k.beam((x, -0.36, 0.35), (x, -0.05, 3.3), 0.05, 0.05, "machinery")           # knee braces
        k.beam((x, 0.36, 0.35), (x, 0.05, 3.3), 0.05, 0.05, "machinery")
        k.beam((x, -0.36, 3.9), (x, -0.2, 4.35), 0.05, 0.05, "steel")
    # long runs hung from the portal beams
    runs = [(-0.28, 3.95, 0.17, (0.9, 0.62, 0.45)), (0.12, 3.95, 0.13, (0.55, 0.7, 0.78)), (0.36, 3.8, 0.08, (0.85, 0.82, 0.7))]
    for y, z, r, tone in runs:
        with k.look(0.85, tone):
            k.pipe((-4.0, y, z), (4.0, y, z), r, "machinery", 8, True)
        for fx in (-2.0, 1.9):
            with k.along((fx - 0.04, y, z), (fx + 0.04, y, z)):
                k.lathe([(r * 1.35, 0), (r * 1.35, 0.08)], "steel", 8, True)
    for x in (-3.8, 0.0, 3.8):                                                       # strap hangers
        for y, z, r, _ in runs:
            k.box(x - 0.04, x + 0.04, y - r * 0.3, y + r * 0.3, z + r * 0.8, 4.35, "steel")
            k.box(x - 0.05, x + 0.05, y - r * 1.05, y + r * 1.05, z + r * 0.5, z + r * 0.8, "steel", skip=("zn",))
    # cable tray
    k.box(-4.0, 4.0, -0.5, -0.2, 3.45, 3.48, "machinery")
    k.box(-4.0, 4.0, -0.5, -0.47, 3.48, 3.6, "machinery")
    k.box(-4.0, 4.0, -0.23, -0.2, 3.48, 3.6, "machinery")
    for i in range(1, 16):
        k.box(-4.0 + i * 0.5 - 0.015, -4.0 + i * 0.5 + 0.015, -0.5, -0.2, 3.43, 3.45, "steel")
    for cy, tone in ((-0.4, OXIDE), (-0.3, (0.55, 0.5, 0.55))):
        with k.look(0.8, tone):
            k.pipe((-4.0, cy, 3.52), (4.0, cy, 3.52), 0.025, "machinery", 5)
    # cable drops (sag between frames); one muted oxide power line, the rest dark
    pts = [Vector((-3.8 + 7.6 * i / 8, -0.35, 3.5 - 0.35 * math.sin(pi * i / 8))) for i in range(9)]
    with k.look(0.7, OXIDE):
        for a, b in zip(pts[:-1], pts[1:]):
            k.pipe(a, b, 0.018, "machinery", 4)
    with k.look(0.5, (0.6, 0.62, 0.66)):
        k.pipe((1.9, -0.35, 3.45), (1.9, -0.35, 2.4), 0.02, "machinery", 4)
        k.pipe((1.9, -0.35, 2.4), (2.2, -0.2, 1.4), 0.02, "machinery", 4)
    # junction box with lights
    k.box(-0.9, -0.2, 0.34, 0.46, 3.0, 3.7, "machinery")
    k.box(-0.85, -0.25, 0.46, 0.48, 3.05, 3.65, "steel", skip=("zn",))
    k.box(-0.6, -0.5, 0.48, 0.5, 3.5, 3.58, "glow_amber", skip=("zn",))
    k.box(-0.55, -0.45, 0.48, 0.5, 3.2, 3.26, "glow_cyan", skip=("zn",))
    k.box(-0.8, -0.3, 0.48, 0.49, 3.35, 3.4, "cavity", skip=("zn",))
    k.pipe((-0.55, 0.4, 3.7), (-0.55, 0.36, 3.75), 0.04, "machinery", 5)
    with k.look(0.6, (0.6, 0.62, 0.66)):
        k.pipe((-0.55, 0.4, 3.0), (-0.55, 0.4, 2.4), 0.03, "machinery", 4)
    # wall-ward hazard tag + ground-level drip stain
    with k.look(0.9, OCHRE):
        k.box(2.5, 2.9, -0.34, -0.3, 3.0, 3.3, "trim")
    for (x, y) in ((-2.0, 0.0), (1.0, -0.2), (2.6, 0.2)):
        with k.look(0.5, (0.8, 0.75, 0.7)):
            k.box(x - 0.25, x + 0.25, y - 0.15, y + 0.15, 0.0, 0.004, "machinery", skip=("zn",))


# ---------------------------------------------------------------------------- shots, export, manifest

# name, light azimuth, camera (design xyz), target (design xyz), lens, human (x, y) or None, resolution
SHOTS["sidewalk_panel"] = [("three_quarter", -25, (-7, 8, 5.5), (0, 0, 0), 38, None, (1400, 1000)),
                           ("top_detail", 0, (0, 0.5, 9), (0, 0, 0), 38, None, (1400, 1000)),
                           ("human_scale", 0, (0, 11, 1.6), (0, 1, 0.1), 32, (1.2, 1.5), (1400, 1000))]
SHOTS["curb_segment"] = [("three_quarter", -25, (-4.0, 3.5, 2.0), (0, 0, 0.1), 38, None, (1400, 1000)),
                         ("road_side", 0, (0, 4, 0.8), (0, 0, 0.12), 40, None, (1400, 1000)),
                         ("human_scale", 0, (0, 8, 1.6), (0, 0.5, 0.1), 32, (1.5, 0.8), (1400, 1000))]
SHOTS["drain_cover"] = [("three_quarter", -25, (-1.1, 1.5, 1.2), (0, 0, 0.03), 40, None, (1400, 1000)),
                        ("top_detail", 0, (0, 0.1, 2.4), (0, 0, 0.03), 38, None, (1400, 1000)),
                        ("human_scale", 0, (0, 4, 1.6), (0, 0.5, 0.0), 32, (0.9, 0.6), (1400, 1000))]
SHOTS["street_lamp"] = [("three_quarter", -25, (-8, 12, 5.0), (0, 0, 4.0), 36, None, (1000, 1400)),
                        ("side_arm", 90, (14, 0, 5.0), (0, 0, 4.0), 36, None, (1000, 1400)),
                        ("head_detail", 0, (-1.8, 5.5, 8.2), (0, 1.2, 7.4), 40, None, (1400, 1000)),
                        ("base_human", -25, (-2.4, 3.6, 1.6), (0, 0, 1.1), 36, (0.8, 1.0), (1400, 1000))]
SHOTS["bollard"] = [("three_quarter", -25, (-1.2, 1.8, 1.0), (0, 0, 0.55), 40, None, (1000, 1000)),
                    ("side", 90, (2.0, 0, 0.7), (0, 0, 0.55), 40, None, (1000, 1000)),
                    ("human_scale", -25, (-1.5, 3.2, 1.4), (0, 0, 0.7), 34, (0.5, 0.5), (1400, 1000))]
SHOTS["bench_planter"] = [("three_quarter", -25, (-5, 6.5, 3.2), (0, 0, 0.6), 36, None, (1400, 1000)),
                          ("front", 0, (0, 8, 1.8), (0, 0, 0.7), 38, None, (1400, 1000)),
                          ("rear_three_quarter", 160, (5, -6.5, 3.2), (0, 0, 0.6), 36, None, (1400, 1000)),
                          ("human_scale", -25, (-5, 6.5, 1.7), (0, 0, 0.8), 34, (3.3, 0.9), (1400, 1000))]
SHOTS["refuse_station"] = [("three_quarter", -25, (-5, 6, 3.4), (0, 0, 1.0), 36, None, (1400, 1000)),
                           ("front", 0, (0, 7, 1.8), (0, 0, 1.1), 38, None, (1400, 1000)),
                           ("rear_three_quarter", 160, (4, -6, 3.2), (0, 0, 1.0), 36, None, (1400, 1000)),
                           ("human_scale", -25, (-5, 6, 1.7), (0, 0, 1.1), 34, (2.0, 1.4), (1400, 1000))]
SHOTS["alley_conduit"] = [("three_quarter", -25, (-9, 9, 3.6), (0, 0, 2.2), 38, None, (1600, 1000)),
                          ("side_end", 90, (16, 0, 2.5), (0, 0, 2.2), 40, None, (1000, 1000)),
                          ("underside", 0, (0, 5.5, 1.2), (0, 0, 3.6), 36, None, (1600, 1000)),
                          ("human_scale", 0, (-3, 9, 1.6), (0, 0, 2.3), 34, (-1.0, 2.0), (1600, 1000))]


def dpo(off, x, y, z):
    """Design-space point -> Blender world (root X mirror plus the baked foot-centring offset)."""
    return Vector((-x, y, z)) + Vector(off)


def render_asset(sid, human, outdir, off, size_scale, only):
    scene = bpy.context.scene
    W.pick_engine(scene)
    scene.render.film_transparent = False
    st = W.Studio(scale=60.0)
    for name, az, cam, tgt, lens, hp, res in SHOTS[sid]:
        if only and name not in only:
            continue
        st.aim(az)
        human.hide_render = hp is None
        if hp:
            human.location = dpo(off, hp[0], hp[1], 0.0)
        res = (int(res[0] * size_scale), int(res[1] * size_scale))
        st.snap(os.path.join(outdir, name + ".png"), dpo(off, *cam), dpo(off, *tgt), lens, res=res)
        report(render=sid + ":" + name)
    human.hide_render = True


def used_surfaces(ob):
    """Semantic surfaces that actually carry faces, in canonical SEM order (what the exporter writes)."""
    used = {p.material_index for p in ob.data.polygons}
    return [ob.data.materials[i].name for i in sorted(used)]


def build_one(sid, spec, glb_dir, gen_dir, prev_dir, render, size, only_shots):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    saved = (W.ASSET_ID, list(W.OFFSET))
    W.ASSET_ID = sid
    try:
        coll = bpy.data.collections.new(sid)
        bpy.context.scene.collection.children.link(coll)
        ref = bpy.data.collections.new("reference_nonruntime")
        bpy.context.scene.collection.children.link(ref)
        mats = W.make_materials()
        k = Kit()
        with k.part(sid):
            spec["build"](k, random.Random("street:" + sid))
        street_grime(k)
        ob = W.finalize(k, mats, coll)
        off = list(W.OFFSET)
        lo, hi, (nv, tris) = W.measure(ob)
        cs = W.colour_stats(ob)
        sp = SPECS[sid]
        report(asset=sid, tris=tris, verts=nv, lo=[round(x, 3) for x in lo], hi=[round(x, 3) for x in hi], colors=cs)
        if tris > sp["cap"]:
            raise SystemExit(f"{sid}: {tris} triangles exceeds its {sp['cap']} cap")
        size_m = [hi[i] - lo[i] for i in range(3)]
        for got, want in zip(size_m, sp["size"]):
            if abs(got - want) > sp["tol"]:
                raise SystemExit(f"{sid}: size {[round(v, 3) for v in size_m]} misses plan {sp['size']} (tol {sp['tol']})")
        glb = os.path.join(glb_dir, sid + ".glb")
        W.export_glb(ob, glb)                                   # export BEFORE wire_vertex_colors (preview-only nodes)
        surfaces = used_surfaces(ob)
        half = (hi[2] - lo[2]) / 2
        setback = math.floor(min(-lo[2], half) * 1e4) / 1e4
        entry = {
            "id": sid, "class": spec["cls"], "glb": sid + ".glb", "tris": tris, "tri_cap": sp["cap"],
            "size": {"x": round(size_m[0], 4), "y": round(size_m[1], 4), "z": round(size_m[2], 4)},
            "aabb": {"min": [round(x, 4) for x in lo], "max": [round(x, 4) for x in hi]},
            "footprint": {"min": [round(lo[0], 4), round(lo[2], 4)], "max": [round(hi[0], 4), round(hi[2], 4)]},
            "front_setback_m": setback,
            "origin": "foot-centred: footprint centre at xz 0, base at y 0; front faces -Z",
            "surfaces": surfaces, "reuse_worlds": ["city", "underworks", "foundry"],
            "vertex_colors": {"attribute": "COLOR_0", "role": "multiplies albedo: grime, scuffs, paint and repair tint"},
            "identity": spec["identity"], "style_note": spec["brief"],
            "lod_strategy": "Single near mesh only. No mid/far LODs exist yet; street furniture is batched by the block builder.",
            "provenance": {
                "builder": "tools/city_pipeline/build_city_streets.py", "helpers": "tools/city_pipeline/build_habitation_workshop.py",
                "blender": bpy.app.version_string, "source_blend": f"assets/generated/city_streets/{sid}/{sid}.blend",
                "qa": f"assets/generated/city_streets/{sid}/qa.json",
                "previews": [f"assets/previews/city_streets/{sid}/{s[0]}.png" for s in SHOTS[sid]],
                "export": "bpy.ops.export_scene.gltf via workshop export_glb, before wire_vertex_colors",
            },
            "budget_note": f"{tris} tris of the {sp['cap']} cap, {len(surfaces)} semantic surfaces, COLOR_0 wear.",
        }
        qa = dict(tris=tris, verts=nv, lo=[round(x, 3) for x in lo], hi=[round(x, 3) for x in hi], colors=cs, surfaces=surfaces,
                  offset=[round(v, 4) for v in off], cameras_lights=[o.name for o in bpy.context.scene.objects if o.type in ("CAMERA", "LIGHT")])
        os.makedirs(os.path.join(gen_dir, sid), exist_ok=True)
        with open(os.path.join(gen_dir, sid, "qa.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(qa, f, indent=2)
            f.write("\n")
        human = W.build_human(ref, mats)
        human.hide_render = True
        W.wire_vertex_colors(mats)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(gen_dir, sid, sid + ".blend"))
        if render:
            od = os.path.join(prev_dir, sid)
            os.makedirs(od, exist_ok=True)
            render_asset(sid, human, od, off, size, only_shots)
        return entry
    finally:
        W.ASSET_ID, W.OFFSET[:] = saved[0], saved[1]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--no-render", action="store_true")
    p.add_argument("--size", type=float, default=1.0, help="render resolution SCALE (0.25-2.0), not pixels")
    p.add_argument("--only", default="", help="comma list of street ids to (re)build and render")
    p.add_argument("--only-shots", default="")
    a = args(p)
    if not 0.25 <= a.size <= 2.0:
        p.error("--size is a resolution SCALE from 0.25 to 2.0; use --size 1.0, not a pixel width")
    root = os.environ.get("AK_REPO", os.getcwd())
    glb_dir = os.path.join(root, "godot", "assets", "city", "streets")
    gen = os.path.join(root, "assets", "generated", "city_streets")
    prev = os.path.join(root, "assets", "previews", "city_streets")
    for d in (glb_dir, gen, prev):
        os.makedirs(d, exist_ok=True)
    only = [x for x in a.only.split(",") if x]
    unknown = [x for x in only if x not in BUILDERS]
    if unknown:
        p.error(f"unknown street ids {unknown}; registered: {sorted(BUILDERS)}")
    shots = [x for x in a.only_shots.split(",") if x]
    mpath = os.path.join(glb_dir, "street_kit_manifest.json")
    entries = {}
    if only and os.path.exists(mpath):
        with open(mpath, encoding="utf-8") as f:
            entries = {e["id"]: e for e in json.load(f)["assets"]}
    for sid in IDS:
        if only and sid not in only:
            continue
        entries[sid] = build_one(sid, BUILDERS[sid], glb_dir, gen, prev, not a.no_render, a.size, shots)
    manifest = {"version": 1, "assets": [entries[s] for s in IDS if s in entries]}
    with open(mpath, "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    report(done="streets", ids=[e["id"] for e in manifest["assets"]], total_tris=sum(e["tris"] for e in manifest["assets"]))


if __name__ == "__main__":
    main()
