"""Vehicle-matched industrial market benchmark: redline_shop + ramen_vendor + ramen_customer (GLB, glTF Y-up, front -Z).

Run (never the GUI):  ak-blender tools/city_pipeline/build_industrial_market.py -- [--only vendor,customer,shop] [--no-render] [--fast]

Pipeline: numpy PBR textures (industrial_market_textures) -> bmesh construction (industrial_market_people / _shop) -> real UVs ->
ray-cast AO in COLOR_0 -> source .blend + GLB export -> measured manifest -> re-import studio renders.
World layout (Blender, Z-up, front +Y; Godot = (x, z, -y)): shop footprint x -4..4, y -2..2 (+ sidewalk to y 4.7), floor top z 0.15.
"""
import argparse
import importlib
import json
import math
import os
import sys
import time

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
for _home in (os.environ.get("AK_HOME"), os.path.expanduser("~/agent-kit")):
    if _home and os.path.isdir(os.path.join(_home, "blender")):
        sys.path.insert(0, os.path.join(_home, "blender"))
from ak_util import args, report  # noqa: E402

import numpy as np  # noqa: E402

import industrial_market_common as C  # noqa: E402
import industrial_market_dress as D  # noqa: E402
import industrial_market_people as PP  # noqa: E402
import industrial_market_textures as TX  # noqa: E402

V = Vector
ROOT = os.path.dirname(os.path.dirname(HERE))
CAND = os.path.join(ROOT, "godot", "assets", "city", "candidates", "industrial_market")
GEN = os.path.join(ROOT, "assets", "generated", "industrial_market")
PREV = os.path.join(ROOT, "assets", "previews", "industrial_market")
TEXD = os.path.join(GEN, "textures")            # source PNGs (provenance); the GLBs embed their own copies
FLOOR = 0.15                                    # shop floor / sidewalk top above road level
COUNTER_TOP = FLOOR + 1.05
BOWL = V((0.55, 1.78))                           # bowl centre on the counter (shop space, x, y)
VENDOR_POS = V((0.40, 1.33))
CUSTOMER_POS = V((0.66, 2.30))
MIPS = 4.0 / 3.0

p = __import__("argparse").ArgumentParser()
p.add_argument("--only", default="vendor,customer,shop")
p.add_argument("--no-render", action="store_true")
p.add_argument("--manifest-only", action="store_true", help="rewrite the manifest from the exported GLBs and *_build.json records")
p.add_argument("--fast", action="store_true", help="64-ray-free quick AO + smaller textures for iteration")
A = args(p)
ONLY = set(A.only.split(","))
for d in (CAND, GEN, PREV, TEXD):
    os.makedirs(d, exist_ok=True)

TEX_LOG = {}


def make_tex(asset, name, fn, **kw):
    seed = abs(hash((asset, name))) % (2 ** 31) if False else sum(ord(c) * (i + 3) for i, c in enumerate(asset + name))
    rng = np.random.default_rng(seed)
    n = 256 if A.fast else kw.pop("n", 512)
    alb, rough, metal, height = fn(n, rng)
    nstr = kw.pop("nstr", 3.0)
    atlas = kw.pop("atlas", None)
    if atlas:
        alb, rough, height = TX.paint_skin_atlas(alb, rough, height, rng=rng, **atlas)
    d = os.path.join(TEXD, asset)
    paths, sizes = TX.write_set(d, name, alb, rough, metal, height, nstr=nstr, alb_n=n, orm_n=n // 2 if n > 256 else n, nrm_n=n)
    TEX_LOG[(asset, name)] = {"sizes": sizes, "files": {k: os.path.relpath(v, ROOT).replace("\\", "/") for k, v in paths.items()},
                              "seed": int(seed), "recipe": fn.__name__ if hasattr(fn, "__name__") else "lambda", "params": {k: str(v) for k, v in kw.items()}}
    return paths


# ================================================================================================ people
def person_specs():
    # World-space grip points are converted to each person's local frame (vendor yaw 0, customer yaw 180 about vertical).
    bowl_z = COUNTER_TOP - FLOOR + 0.046 + 0.0                       # local z of palm centre on the bowl wall
    pr = lambda w, pos, yaw: (V((w[0] - pos[0], w[1] - pos[1])) if yaw == 0 else V((-(w[0] - pos[0]), -(w[1] - pos[1]))))
    vr = pr((BOWL.x + 0.098, BOWL.y - 0.06), VENDOR_POS, 0)
    cr = pr((BOWL.x - 0.098, BOWL.y + 0.06), CUSTOMER_POS, 180)
    vl = pr((0.12, 1.62), VENDOR_POS, 0)
    uvs = {"top": 2.6, "trousers": 2.6}
    vendor = dict(
        id="ramen_vendor", H=1.72, hipw=1.04, thigh=1.04, hem=1.03, waist=(0.164, 0.120, 0.170, 0.124), chest_d=1.05, shoulder_w=0.192, arm=1.04,
        pelvis=(-0.012, -0.02), lean=0.06, weight="L", head_off=(0.0, 0.0, -0.005), head_tilt=(math.radians(-6), math.radians(4)),
        feet={"L": (-0.115, -0.16, math.radians(9)), "R": (0.135, -0.13, math.radians(-14))},
        skull=dict(w=1.05, jaw=1.0, brow=1.1, nose=1.05, lip=1.0),
        mat=dict(skin="skin", top="shirt", trousers="trousers", leather="leather", hair="hair", cloth2="apron"),
        torso_folds=[(0.60 * 1.72, 0.05, 0.006, 2 * math.pi / 0.09, math.pi / 2, 0.9, 0.0), (0.665 * 1.72, 0.05, 0.005, 2 * math.pi / 0.08, math.pi / 2 + 0.4, 0.7, 1.0),
                     (0.52 * 1.72, 0.04, 0.007, 2 * math.pi / 0.07, 0.0, 1.6, 0.5)],
        arms={"R": dict(wrist=(vr.x, vr.y, bowl_z), pole=(0.7, -0.4, -0.6), sleeve_t=0.5, cuff_roll=0.5),
              "L": dict(wrist=(vl.x - 0.0, vl.y, COUNTER_TOP - FLOOR + 0.0165), pole=(-0.7, -0.4, -0.6), sleeve_t=0.5, cuff_roll=0.5)},
        hands={"R": dict(f=(0, 1, 0), n=(-1, 0, 0), curls=[(0.2, 0.45, 0.35), (0.24, 0.5, 0.38), (0.27, 0.52, 0.4), (0.3, 0.55, 0.4)],
                         thumb=[(-0.2, 0.6, 0.7), (-0.7, 0.5, 0.2), (-0.8, 0.3, -0.4)]),
               "L": dict(f=(0.12, 1, 0), n=(0, 0, -1), curls=PP.FLAT, thumb=[(0.7, 0.7, 0), (0.5, 0.9, 0), (0.3, 1, 0)])},
        uvs=uvs, boot=0.0, hair_thick=0.006, hair_back=0.0,
    )
    customer = dict(
        id="ramen_customer", H=1.80, hipw=0.97, thigh=0.98, hem=1.0, waist=(0.141, 0.098, 0.15, 0.103), chest_d=1.0, shoulder_w=0.188, arm=0.98,
        pelvis=(0.012, 0.0), lean=0.055, weight="R", head_off=(0.0, 0.0, 0.0), head_tilt=(math.radians(-3), math.radians(-5)),
        feet={"L": (-0.12, 0.0, math.radians(12)), "R": (0.115, -0.09, math.radians(-8))},
        skull=dict(w=0.97, jaw=0.88, brow=0.85, nose=0.92, lip=1.12),
        mat=dict(skin="skin", top="jacket", trousers="trousers", leather="leather", hair="hair"),
        torso_folds=[(0.60 * 1.8, 0.05, 0.007, 2 * math.pi / 0.1, math.pi / 2, 1.0, 0.3), (0.52 * 1.8, 0.045, 0.008, 2 * math.pi / 0.08, math.pi / 2, 1.2, 0.0),
                     (0.70 * 1.8, 0.05, 0.005, 2 * math.pi / 0.09, math.pi, 0.8, 0.0)],
        arms={"R": dict(wrist=(cr.x, cr.y, bowl_z), pole=(0.7, -0.5, -0.5), sleeve_t=1.0, cuff_roll=0.93),
              "L": dict(wrist=(-0.235, 0.035, 0.80), pole=(-0.4, -0.8, -0.2), sleeve_t=1.0, cuff_roll=0.93)},
        hands={"R": dict(f=(0, 1, 0), n=(-1, 0, 0), curls=[(0.2, 0.45, 0.35), (0.24, 0.5, 0.38), (0.27, 0.52, 0.4), (0.3, 0.55, 0.4)],
                         thumb=[(-0.2, 0.6, 0.7), (-0.7, 0.5, 0.2), (-0.8, 0.3, -0.4)]),
               "L": dict(f=(0.0, 0.25, -1), n=(1, 0, 0), curls=PP.RELAXED, thumb=[(0.2, 0.5, -0.8), (0.1, 0.6, -0.8), (0, 0.7, -0.7)])},
        uvs=uvs, boot=0.19, ponytail=True, hair_thick=0.009, hair_back=0.0,
    )
    return vendor, customer


def person_textures(asset):
    v = asset == "ramen_vendor"
    skin_tone = (0.60, 0.41, 0.31) if v else (0.74, 0.55, 0.43)
    t = {}
    t["skin"] = make_tex(asset, "skin", lambda n, r: TX.r_skin(n, r, skin_tone, ruddy=1.0), n=512, nstr=1.2,
                         atlas=dict(tone=skin_tone, stubble=0.8 if v else 0.0, iris=(0.2, 0.11, 0.05) if v else (0.1, 0.2, 0.22),
                                    brow=(0.07, 0.05, 0.04) if v else (0.16, 0.07, 0.04), lip=(0.5, 0.25, 0.22) if v else (0.62, 0.32, 0.3), freckle=0.0 if v else 0.8))
    if v:
        t["shirt"] = make_tex(asset, "shirt", lambda n, r: TX.r_cloth(n, r, (0.17, 0.21, 0.27), weave=110, wear=0.35, streak=0.2, stain=0.4), nstr=3.0)
        t["apron"] = make_tex(asset, "apron", lambda n, r: TX.r_cloth(n, r, (0.5, 0.45, 0.34), weave=70, twill=False, wear=0.2, stain=0.8, streak=0.3), nstr=3.5)
        t["trousers"] = make_tex(asset, "trousers", lambda n, r: TX.r_cloth(n, r, (0.12, 0.115, 0.095), weave=120, wear=0.45, stain=0.3), nstr=3.0)
        t["hair"] = make_tex(asset, "hair", lambda n, r: TX.r_hair(n, r, (0.13, 0.1, 0.08)), nstr=2.0)
        t["leather"] = make_tex(asset, "leather", lambda n, r: TX.r_leather(n, r, (0.09, 0.065, 0.045)), nstr=2.5)
    else:
        t["jacket"] = make_tex(asset, "jacket", lambda n, r: TX.r_cloth(n, r, (0.14, 0.2, 0.21), weave=90, twill=False, wear=0.3, streak=0.25, stain=0.2), nstr=3.0)
        t["trousers"] = make_tex(asset, "trousers", lambda n, r: TX.r_cloth(n, r, (0.09, 0.095, 0.105), weave=130, wear=0.4, stain=0.25, streak=0.15), nstr=3.0)
        t["hair"] = make_tex(asset, "hair", lambda n, r: TX.r_hair(n, r, (0.2, 0.08, 0.045)), nstr=2.0)
        t["leather"] = make_tex(asset, "leather", lambda n, r: TX.r_leather(n, r, (0.1, 0.07, 0.05), scuff=0.55), nstr=2.5)
    return t


PRM = {  # roughness/metal factors are multiplied by the ORM texture in glTF; base factors stay 1
}


def make_person(P, with_dress):
    asset = P["id"]
    tex = person_textures(asset)
    names = list(tex.keys())
    mats = {n: C.make_material(n, tex=tex[n]) for n in names}
    m = C.Mesh(names)
    for n in names:
        pass
    info = PP.build_person(m, P)
    with_dress(m, P, info)
    # UVs for everything not authored (cloth strips, soles, accessories)
    C.box_uv(m, {n: 2.6 for n in names})
    m.finish_normals()
    return m, mats, tex, info


def dress_vendor(m, P, info):
    sk = D.Skin(m)
    H = P["H"]
    D.apron(m, sk, H, "apron", P["lean"], "apron", ties=True)
    D.collar(m, V((0, P["lean"] - 0.004, 0)), 0.060, 0.055, 0.845 * H, 0.018, 0.007, "shirt", a0=-160, a1=160, lean=0.0)
    # bandana
    head_c = V((P["head_off"][0], 0.012 + P["lean"] * 0.6 + P["head_off"][1], 0.935 * H + P["head_off"][2]))
    tilt = Matrix.Rotation(P["head_tilt"][0], 4, "X") @ Matrix.Rotation(P["head_tilt"][1], 4, "Z")
    D.headband(m, head_c, tilt, "shirt")


def dress_customer(m, P, info):
    sk = D.Skin(m)
    H = P["H"]
    lean = P["lean"]
    # hood roll, stand collar, zip, hand pockets, chest pocket, cargo pockets
    hood = [V((s * 0.095, 0.045 + lean, 0.838 * H)) for s in (-1, 1)]
    m.tube([V((-0.105, 0.05 + lean, 0.835 * H)), V((-0.12, -0.02 + lean, 0.835 * H)), V((-0.075, -0.085 + lean, 0.845 * H)), V((0, -0.098 + lean, 0.848 * H)),
            V((0.075, -0.085 + lean, 0.845 * H)), V((0.12, -0.02 + lean, 0.835 * H)), V((0.105, 0.05 + lean, 0.835 * H))],
           [0.026, 0.031, 0.035, 0.036, 0.035, 0.031, 0.026], "jacket", seg=12, samples=26, ratio=0.9, up=V((0, 0, 1)), uv=("cloth", 1.6))
    D.collar(m, V((0, lean - 0.004, 0)), 0.064, 0.060, 0.856 * H, 0.026, 0.009, "jacket", a0=-150, a1=150)
    # zip tape
    def zip_fn(i, j, nu=2, nv=26):
        z = 0.838 * H - (0.838 * H - 0.452 * H) * j / nv
        x = (i / nu * 2 - 1) * 0.011
        y = sk.y(x, z)
        return V((x, (y if y is not None else 0.1) + 0.0035, z))
    PP.thick_sheet(m, zip_fn, 2, 26, 0.003, "leather")
    m.box(V((0, (sk.y(0, 0.62 * H) or 0.1) + 0.012, 0.62 * H)), (0.012, 0.01, 0.03), "leather", bevel=0.002)
    for s in (-1, 1):
        def pk(i, j, s=s, nu=6, nv=3):
            u = (i / nu - 0.5) * 0.15
            z = 0.505 * H - 0.045 * j / nv - 0.015 * (i / nu)
            x = s * 0.125 + u
            y = sk.y(x, z)
            return V((x, (y if y is not None else 0.1) + 0.006 + 0.004 * j / nv, z))
        PP.thick_sheet(m, pk, 6, 3, 0.004, "jacket", flip=(s < 0))
        def cp(i, j, s=s, nu=5, nv=4):
            u = (i / nu - 0.5) * 0.115
            z = 0.51 * H - 0.12 * j / nv + 0.0 if False else 0.455 * H - 0.0
            return V((0, 0, 0))
        # cargo pocket on the thigh with flap
        def cargo(i, j, s=s, nu=6, nv=6):
            x = s * 0.115 + (i / nu - 0.5) * 0.15
            z = 0.40 * H - 0.17 * j / nv
            y = sk.y(x, z)
            return V((x, (y if y is not None else 0.1) + 0.010 + 0.003 * j / nv, z))
        PP.thick_sheet(m, cargo, 6, 6, 0.004, "trousers", flip=(s < 0))
        # hem drawcord end
    cz = 0.662 * H
    def chest(i, j, nu=4, nv=3):
        x = 0.085 + (i / nu - 0.5) * 0.1
        z = cz - 0.07 * j / nv
        y = sk.y(x, z)
        return V((x, (y if y is not None else 0.1) + 0.006, z))
    PP.thick_sheet(m, chest, 4, 3, 0.004, "jacket", flip=False)
    # hem band loop
    D.ring_loop(m, V((P["pelvis"][0] * 0.9, P["pelvis"][1] + 0.004, 0)), 0.2 * H / 1.75 * 1.0, 0.14 * H / 1.75, info["hem_z"] + 0.012, 0.012, "jacket", ratio=0.9, a0=0, a1=345, uvs=1.6)


BUILDERS = {"vendor": ("ramen_vendor", dress_vendor), "customer": ("ramen_customer", dress_customer)}


def finish_person(key):
    t0 = time.time()
    P = person_specs()[0 if key == "vendor" else 1]
    m, mats, tex, info = make_person(P, BUILDERS[key][1])
    asset = P["id"]
    C.ray_ao(m, rays=6 if A.fast else 12, dist=0.22, floor=0.55)
    ob = C.commit(m, asset, [mats[n] for n in m.mats])
    ob.name = asset
    return asset, m, ob, tex, info, time.time() - t0


def save_and_export(asset, m, ob, outdir=CAND):
    path = os.path.join(outdir, asset + ".glb")
    size = C.export_glb(ob, path)
    return path, size


# ================================================================================================ shop
MENU_ROWS = [("SHIO RAMEN", "6.5"), ("MISO RAMEN", "6.5"), ("SPICY RAMEN", "7.0"), ("GYOZA", "4.5"), ("TEA", "3.0"), ("WATER", "2.0")]   # drafted via ak-qwen
DRIPS = [(-2.5, 2.1, 3.9, 0.14, 0.38), (-1.7, 2.3, 4.15, 0.1, 0.35), (4.12, 1.72, 3.7, 0.12, 0.5), (3.3, 2.05, 2.4, 0.3, 0.3), (-0.4, 2.0, 3.0, 0.5, 0.2)]


def shop_wear(p, n, mat):
    """Wear that follows gravity, shelter and use (multiplies the AO already in COLOR_0)."""
    if mat in ("sign_emissive",):
        return (1, 1, 1)
    z = p.z
    v = 0.94 * (1 - 0.30 * math.exp(-(z - FLOOR) / 0.4))                  # splash / foot-traffic grime near the ground
    for (x0, y0, zt, w, s) in DRIPS:                                      # rain streaks below joints, gutters and the sign
        if zt - 1.8 < z < zt and abs(p.y - y0) < 0.5:
            v *= 1 - s * math.exp(-((p.x - x0) / w) ** 2) * (1 - (zt - z) / 1.8)
    if z > 3.7:
        v *= 0.93                                                          # sun-faded roofline
    if mat == "equipment_steel" and p.y > 1.9 and abs(z - COUNTER_TOP) < 0.045:
        v = 1.0                                                            # counter lip polished by customers
    elif mat == "equipment_steel" and abs(p.x + 3.6) < 0.1 and 0.7 < z < 1.4 and p.y > 2.0:
        v = 1.0                                                            # door pull
    r = 1.0
    if mat in ("cladding_main", "steel_structure") and z < 1.2:
        r = 0.92                                                           # rust-brown splash band
    return (v, v * (0.97 if r < 1 else 1.0), v * r * 0.96)


def shop_textures():
    t = {}
    t["steel_structure"] = make_tex("redline_shop", "steel_structure", lambda n, r: TX.r_painted_metal(n, r, (0.1, 0.11, 0.125), rust=0.12, panel=0, grime=0.6), nstr=3.0)
    t["cladding_main"] = make_tex("redline_shop", "cladding_main", lambda n, r: TX.r_painted_metal(n, r, (0.16, 0.22, 0.22), rust=0.4, panel=0, grime=0.8), nstr=3.0)
    t["cladding_patch"] = make_tex("redline_shop", "cladding_patch", lambda n, r: TX.r_painted_metal(n, r, (0.46, 0.29, 0.09), rust=0.08, panel=4, grime=0.25), nstr=3.0)
    t["concrete"] = make_tex("redline_shop", "concrete", lambda n, r: TX.r_concrete(n, r), nstr=4.0)
    t["equipment_steel"] = make_tex("redline_shop", "equipment_steel", lambda n, r: TX.r_steel(n, r), nstr=2.0)
    t["awning_fabric"] = make_tex("redline_shop", "awning_fabric", lambda n, r: TX.r_awning(n, r, c1=(0.42, 0.05, 0.045), c2=(0.62, 0.56, 0.45), fade=0.18), nstr=3.0)
    t["rubber"] = make_tex("redline_shop", "rubber", lambda n, r: TX.r_rubber(n, r), nstr=2.0)

    def cer_food(n, r):
        a1, r1, m1, h1 = TX.r_ceramic(n, r)
        a2, r2, m2, h2 = TX.r_food(n, r)
        return (np.concatenate([a1[::2], a2[::2]], 0), np.concatenate([r1[::2], r2[::2]], 0), np.concatenate([m1[::2], m2[::2]], 0), np.concatenate([h1[::2], h2[::2]], 0))
    cer_food.__name__ = "r_ceramic+r_food atlas"
    t["ceramic"] = make_tex("redline_shop", "ceramic", cer_food, nstr=2.0)
    return t


UV_SCALE = {"steel_structure": 1.0, "cladding_main": 0.8, "cladding_patch": 0.9, "concrete": 0.5, "equipment_steel": 1.2, "awning_fabric": 0.45, "rubber": 2.0}


def make_shop():
    import industrial_market_shop as S
    import industrial_market_shop_detail as SD
    t0 = time.time()
    tex = shop_textures()
    mats = {n: C.make_material(n, tex=tex[n]) for n in tex}
    mats["sign_emissive"] = C.make_material("sign_emissive", base=(0.12, 0.012, 0.01), rough=0.35, emit=(1.0, 0.13, 0.05), emit_strength=1.0)
    m = C.Mesh(S.SHOP_MATS)
    S.build_shop(m)
    S.build_interior(m)
    S.build_counter_props(m)
    bc = V((BOWL.x, BOWL.y, COUNTER_TOP))
    S.bowl(m, bc, 0.098, 0.085)
    band = {}
    SD.build_food(m, bc, band)
    SD.build_sign(m)
    SD.build_menu(m, MENU_ROWS)
    SD.build_door_and_services(m)
    C.box_uv(m, UV_SCALE)
    foodset = {f for fl in band.values() for f in fl}
    cer = m.mi("ceramic")
    for f in m.bm.faces:
        if f.material_index != cer or f in m.explicit:
            continue
        if f in foodset:
            continue
        for lp in f.loops:
            c = lp.vert.co
            lp[m.uv].uv = (0.5 + 0.45 * math.sin(c.x * 9 + c.y * 4), 0.76 + 0.2 * math.sin(c.z * 20 + c.y * 6 + 1))
    for b, fl in band.items():
        vc = 0.5 - (b + 0.5) / 8
        for f in fl:
            for lp in f.loops:
                c = lp.vert.co
                lp[m.uv].uv = (0.2 + 0.6 * ((c.x * 13) % 1.0), vc + 0.05 * (((c.y * 17) % 1.0) - 0.5))
    m.finish_normals()
    C.ray_ao(m, exclude_mats=("sign_emissive",), rays=6 if A.fast else 10, dist=0.7, floor=0.45, extra=shop_wear)
    ob = C.commit(m, "redline_shop", [mats[n] for n in m.mats])
    return "redline_shop", m, ob, tex, {}, time.time() - t0


# ================================================================================================ manifest data
def g_from_b(v):
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def mesh_aabb(m):
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for v in m.bm.verts:
        g = (v.co.x, v.co.z, -v.co.y)
        for k in range(3):
            lo[k], hi[k] = min(lo[k], g[k]), max(hi[k], g[k])
    return [round(x, 4) for x in lo], [round(x, 4) for x in hi]


def person_world(pos, yaw, lp):
    lp = V(lp)
    if yaw == 0:
        return g_from_b((pos.x + lp.x, pos.y + lp.y, FLOOR + lp.z))
    return g_from_b((pos.x - lp.x, pos.y - lp.y, FLOOR + lp.z))


def write_manifest():
    """Measured manifest from the exported GLBs + per-asset build records (needs all three)."""
    import validate_industrial_market as VAL
    recs = {}
    for a in VAL.ASSETS:
        pth = os.path.join(GEN, a + "_build.json")
        if not (os.path.isfile(pth) and os.path.isfile(os.path.join(CAND, a + ".glb"))):
            raise FileNotFoundError("Manifest requires build record and GLB for " + a)
        with open(pth, encoding="utf-8") as fh:
            recs[a] = json.load(fh)
    assets, tex_dup, tex_one = [], 0.0, 0.0
    identity = {"redline_shop": "Redline Ramen: worn corrugated steel stall on an H-column portal frame, canvas awning, one aging illuminated sign, patched cladding, service counter",
                "ramen_vendor": "Ramen vendor: stocky cook in rolled-sleeve work shirt, canvas apron and headband, handing a bowl across the counter",
                "ramen_customer": "Ramen customer: slim diner in a hooded work jacket and cargo trousers, taking the bowl at the counter"}
    for a in VAL.ASSETS:
        info = VAL.analyze(os.path.join(CAND, a + ".glb"))
        est, est2 = VAL.tex_estimate(info["images"])
        tex_one += est
        tex_dup += est2
        textures = []
        for mt in info["materials"]:
            for slot, d in mt["slots"].items():
                textures.append({"material": mt["name"], "slot": slot, "embedded": True, "width": d["width"], "height": d["height"], "glb_bytes": d["bytes"]})
        srcs = sorted(v for t in recs[a]["textures"].values() for v in t["files"].values())
        assets.append({"id": a, "glb": a + ".glb", "tris": info["tris"], "aabb": {"min": [round(c, 4) for c in info["lo"]], "max": [round(c, 4) for c in info["hi"]]},
                       "surfaces": [mt["name"] for mt in info["materials"]], "tris_by_surface": info["tris_by_mat"], "textures": textures,
                       "texture_mib_mips": round(est, 4), "texture_mib_with_import_copy": round(est2, 4), "identity": identity[a],
                       "source_blend": f"assets/generated/industrial_market/{a}.blend", "source_textures": srcs,
                       "vertex_color": "COLOR_0 = ray-cast ambient occlusion x gravity/shelter wear (no flat albedo fill)"})
    vp = V((VENDOR_POS.x, VENDOR_POS.y, 0))
    gp = lambda b: [round(b.x, 4), round(FLOOR + b.z, 4), round(-b.y, 4)]
    bowl_g = [BOWL.x, COUNTER_TOP, -BOWL.y]
    face_v = person_world(VENDOR_POS, 0, recs["ramen_vendor"]["eye_local"])
    face_c = person_world(CUSTOMER_POS, 180, recs["ramen_customer"]["eye_local"])
    wr_v = person_world(VENDOR_POS, 0, recs["ramen_vendor"]["arms"]["R"][2])
    wl_v = person_world(VENDOR_POS, 0, recs["ramen_vendor"]["arms"]["L"][2])
    wr_c = person_world(CUSTOMER_POS, 180, recs["ramen_customer"]["arms"]["R"][2])
    anchors = [("sign_glow", (0.0, 2.7, 4.56), (1.0, 0.2, 0.1), 220, 6.0), ("counter_lamp", (0.6, 1.2, 3.55), (1.0, 0.65, 0.3), 120, 4.5),
               ("hood_lamp", (-1.3, 0.7, 2.05), (1.0, 0.85, 0.6), 100, 3.5), ("menu_lamp", (3.33, 2.4, 2.15), (1.0, 0.65, 0.3), 60, 2.8),
               ("door_lamp", (-2.6, 2.3, 2.4), (1.0, 0.6, 0.25), 60, 3.0)]
    man = {
        "version": 1, "status": "candidate-review", "units": "metres, Y-up, front -Z, origin at foot centre / floor",
        "generator": "tools/city_pipeline/build_industrial_market.py", "assets": assets,
        "placements": [{"asset": "redline_shop", "position": [0, 0, 0], "yaw_degrees": 0},
                       {"asset": "ramen_vendor", "position": [VENDOR_POS.x, FLOOR, -VENDOR_POS.y], "yaw_degrees": 0},
                       {"asset": "ramen_customer", "position": [CUSTOMER_POS.x, FLOOR, -CUSTOMER_POS.y], "yaw_degrees": 180}],
        "vehicle_slot": {"center": [-3.0, 0.0, -7.5], "yaw_degrees": 90, "reserved_strip_z": [-5.0, -10.0], "curb_z": -4.7,
                         "note": "Lead places the approved BLACKJACK X-17 here; no vehicle ships in this candidate."},
        "floor_top_y": FLOOR, "counter_top_y": COUNTER_TOP,
        "interaction": {"bowl_center": bowl_g, "bowl_radius": 0.098, "vendor_right_wrist": wr_v, "vendor_left_wrist_on_counter": wl_v, "customer_right_wrist": wr_c,
                        "note": "Both right hands hold the bowl rim from opposite sides (vendor +X, customer -X). Validator checks mesh proximity."},
        "review_targets": {"counter": [0.55, COUNTER_TOP, -1.80], "vendor_face": face_v, "customer_face": face_c, "support": [-2.5, 1.2, -2.07], "sign": [0.0, 4.56, -2.4],
                           "materials": {"cladding_main": [-3.45, 2.7, -2.03], "cladding_patch": [3.5, 0.9, -2.05], "steel_structure": [-2.5, 2.2, -2.08], "concrete": [0.0, FLOOR, -3.6],
                                         "equipment_steel": [-1.2, COUNTER_TOP, -1.8], "awning_fabric": [0.0, 3.15, -2.7], "ceramic_food": bowl_g, "rubber_menu": [3.45, 1.55, -2.07],
                                         "sign_emissive": [0.0, 4.56, -2.42], "skin_vendor": face_v, "jacket_customer": person_world(CUSTOMER_POS, 180, [0, 0.1, 1.3]),
                                         "apron_vendor": person_world(VENDOR_POS, 0, [0, 0.14, 1.0])}},
        "lighting": {"note": "Proposed runtime local lights as DATA only (no lights in the GLBs). Diagnostic neutral setup = sun + sky; night = these anchors only.",
                     "anchors": [{"name": n, "position": [p[0], p[2], -p[1]], "color": list(c), "energy": e, "range": r, "shadow": n in ("sign_glow", "counter_lamp")}
                                 for n, p, c, e, r in anchors]},
        "budgets": {"shop_tris": "35k-70k", "person_tris": "8k-18k", "combined_tris": 120000, "combined_surfaces": 20, "texture_mib": 128},
        "costs": {"tris": {a["id"]: a["tris"] for a in assets}, "combined_tris": sum(a["tris"] for a in assets), "surfaces": {a["id"]: len(a["surfaces"]) for a in assets},
                  "combined_surfaces": sum(len(a["surfaces"]) for a in assets), "texture_mib_mips": round(tex_one, 3), "texture_mib_working": round(tex_dup, 3),
                  "texture_assumptions": "uncompressed RGBA8 + full mip chain per distinct embedded image, x2 for the duplicated imported copy; VRAM-compressed imports will be smaller",
                  "shadow_light_cost": "not measured here: Godot candidate scene owns it"},
        "previews": sorted(os.listdir(PREV)) if os.path.isdir(PREV) else [],
        "limitations": ["static pose, no rig or LODs", "faces use displaced-sphere heads with painted brows/lips; eyelids are tubes", "no true glass/transparent sign lens (dark acrylic face)",
                        "AO + wear baked into COLOR_0 per vertex (multiplied over textures)", "textures are procedural (numpy), not photographed or ComfyUI-generated"]}
    with open(os.path.join(CAND, "benchmark_manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(man, fh, indent=1)
    prov = {"generator": "tools/city_pipeline/industrial_market_textures.py (numpy, deterministic seeds)", "comfyui_used": False,
            "assets": {a: recs[a]["textures"] for a in recs}}
    with open(os.path.join(GEN, "texture_provenance.json"), "w", encoding="utf-8") as fh:
        json.dump(prov, fh, indent=1)


if __name__ == "__main__":
    if A.manifest_only:
        write_manifest()
        report(manifest="rewritten")
        sys.exit(0)
    results, extras = {}, {}
    made = []
    for key in ("vendor", "customer", "shop"):
        if key not in ONLY:
            continue
        if key == "shop":
            asset, m, ob, tex, info, dt = make_shop()
        else:
            asset, m, ob, tex, info, dt = finish_person(key)
        path, size = save_and_export(asset, m, ob)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(GEN, asset + ".blend"), copy=True)
        lo, hi = mesh_aabb(m)
        per_mat = {}
        for f in m.bm.faces:
            per_mat[m.mats[f.material_index]] = per_mat.get(m.mats[f.material_index], 0) + len(f.verts) - 2
        results[asset] = dict(tris=m.tris(), glb_bytes=size, seconds=round(dt, 1), aabb=[lo, hi], tris_by_material=per_mat)
        extras[asset] = info
        rec = dict(results[asset], textures={n: v for (a, n), v in TEX_LOG.items() if a == asset},
                   face_local=[round(c, 4) for c in info["face_world"]] if info else None,
                   eye_local=[round(c, 4) for c in info["eye_surf"]] if info else None,
                   arms={k: [[round(c, 4) for c in p] for p in v] for k, v in info["arms"].items()} if info else None)
        with open(os.path.join(GEN, asset + "_build.json"), "w", encoding="utf-8") as fh:
            json.dump(rec, fh, indent=1)
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o)
        for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.curves):
            for x in list(coll):
                coll.remove(x)
    write_manifest()
    report(**{k: {kk: vv for kk, vv in v.items() if kk != "tris_by_material"} for k, v in results.items()})
    print("AK-BY-MATERIAL", json.dumps({k: v["tris_by_material"] for k, v in results.items()}))
