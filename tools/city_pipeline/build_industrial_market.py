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
    d =os.path.join(TEXD, asset)
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
    grip = dict(f=(0, 1, 0), n=(-1, 0, 0), curls=[(0.50, 0.85, 0.7), (0.55, 0.9, 0.72), (0.58, 0.9, 0.72), (0.6, 0.9, 0.7)],
                thumb=[(-0.2, 0.6, 0.7), (-0.7, 0.5, 0.2), (-0.8, 0.3, -0.4)])
    flat = dict(f=(0.12, 1, 0), n=(0, 0, -1), curls=PP_FLAT, thumb=[(0.7, 0.7, 0), (0.5, 0.9, 0), (0.3, 1, 0)])
    relaxed = dict(f=(0.0, 0.25, -1), n=(1, 0, 0), curls=PP_RELAXED, thumb=[(0.2, 0.5, -0.8), (0.1, 0.6, -0.8), (0, 0.7, -0.7)])
    # gaze: each person looks at the other's face (person-local metres); the eyeballs turn at most ~22 deg from the head direction
    vendor = dict(
        id="ramen_vendor", body="male", H=1.72, seed=11, hem=0.50, neck_cut=0.826, cuff=0.068, sleeve_t=0.32, top_ease=0.010, top_drop=0.9, trousers_ease=0.017,
        fold_amp=1.0, boot_top=None, boot_ease=0.007, hair_thick=0.011, hairline=0.07, ponytail=False,
        mat=dict(skin="skin", top="shirt", trousers="trousers", leather="leather", hair="hair", cloth2="apron"), dress=dress_vendor,
        pose=dict(lean_angle=0.05, pelvis_shift=(-0.012, -0.02, 0.0), pelvis_yaw=0.03, head_tilt=(-0.07, 0.07), ankle_lift=0.02,
                  feet={"L": (-0.115, -0.16, math.radians(9)), "R": (0.135, -0.13, math.radians(-14))}, weight="L",
                  arms={"R": dict(wrist=(vr.x, vr.y, bowl_z), pole=(0.7, -0.4, -0.6), hand=grip),
                        "L": dict(wrist=(vl.x - 0.0, vl.y, COUNTER_TOP - FLOOR + 0.0165), pole=(-0.7, -0.4, -0.6), hand=flat)}),
        gaze=(0.26, 1.2, 1.64),
    )
    customer = dict(
        id="ramen_customer", body="female", H=1.80, seed=23, hem=0.53, neck_cut=0.826, cuff=0.105, sleeve_t=0.93, top_ease=0.021, top_drop=0.5, trousers_ease=0.016,
        fold_amp=1.0, boot_top=0.145, boot_ease=0.008, shaft_ease=0.016, hair_thick=0.012, hairline=0.066, ponytail=True,
        mat=dict(skin="skin", top="jacket", trousers="trousers", leather="leather", hair="hair"), dress=dress_customer,
        pose=dict(lean_angle=0.045, pelvis_shift=(0.012, 0.0, 0.0), pelvis_yaw=-0.03, head_tilt=(-0.04, -0.06), ankle_lift=0.02,
                  feet={"L": (-0.12, 0.0, math.radians(12)), "R": (0.115, -0.09, math.radians(-8))}, weight="R",
                  arms={"R": dict(wrist=(cr.x, cr.y, bowl_z), pole=(0.7, -0.5, -0.5), hand=grip),
                        "L": dict(wrist=(-0.235, 0.035, 0.80), pole=(-0.4, -0.8, -0.2), hand=relaxed)}),
        gaze=(-0.12, 1.2, 1.62),
    )
    return vendor, customer


PP_FLAT = [(0.04, 0.10, 0.08), (0.03, 0.09, 0.08), (0.03, 0.10, 0.08), (0.05, 0.12, 0.1)]
PP_RELAXED = [(0.30, 0.50, 0.38), (0.36, 0.56, 0.42), (0.44, 0.62, 0.46), (0.52, 0.66, 0.5)]


def person_textures(asset):
    v = asset == "ramen_vendor"
    t = {}
    if v:
        t["shirt"] = make_tex(asset, "shirt", lambda n, r: TX.r_cloth(n, r, (0.17, 0.21, 0.27), weave=110, wear=0.35, streak=0.2, stain=0.4), nstr=1.6)
        t["apron"] = make_tex(asset, "apron", lambda n, r: TX.r_cloth(n, r, (0.5, 0.45, 0.34), weave=70, twill=False, wear=0.2, stain=0.8, streak=0.3), nstr=2.0)
        t["trousers"] = make_tex(asset, "trousers", lambda n, r: TX.r_cloth(n, r, (0.12, 0.115, 0.095), weave=120, wear=0.45, stain=0.3), nstr=1.6)
        t["hair"] = make_tex(asset, "hair", lambda n, r: TX.r_hair(n, r, (0.13, 0.1, 0.08)), n=256, nstr=1.2)       # 256 px: keeps the 128 MiB budget with 1k skin atlases
        t["leather"] = make_tex(asset, "leather", lambda n, r: TX.r_leather(n, r, (0.09, 0.065, 0.045)), nstr=0.8)
    else:
        t["jacket"] = make_tex(asset, "jacket", lambda n, r: TX.r_cloth(n, r, (0.14, 0.2, 0.21), weave=90, twill=False, wear=0.3, streak=0.25, stain=0.2), nstr=1.6)
        t["trousers"] = make_tex(asset, "trousers", lambda n, r: TX.r_cloth(n, r, (0.09, 0.095, 0.105), weave=130, wear=0.4, stain=0.25, streak=0.15), nstr=1.6)
        t["hair"] = make_tex(asset, "hair", lambda n, r: TX.r_hair(n, r, (0.2, 0.08, 0.045)), n=256, nstr=1.2)
        t["leather"] = make_tex(asset, "leather", lambda n, r: TX.r_leather(n, r, (0.1, 0.07, 0.05), scuff=0.55), nstr=0.8)
    return t


def bake_skin_textures(asset, fig, m):
    """Skin atlas baked from the real mesh (rest pose): albedo 1024, ORM 512, subtle normal 512."""
    import industrial_market_skin as SK
    v = asset == "ramen_vendor"
    res = 512 if A.fast else 1024
    tone = (0.53, 0.39, 0.31) if v else (0.70, 0.54, 0.45)
    m.bm.verts.index_update()
    m.bm.normal_update()
    faces = [f for f, _ in fig.skin_faces]
    nmax = max(vt.index for fc in faces for vt in fc.verts) + 1
    Pm = np.zeros((nmax, 3))
    Nm = np.zeros((nmax, 3))
    for fc in faces:
        for vt in fc.verts:
            Pm[vt.index] = vt.co[:]
            Nm[vt.index] = vt.normal[:]
    flist = [tuple(vt.index for vt in fc.verts) for fc in faces]
    loopuv = [[tuple(lp[m.uv].uv) for lp in fc.loops] for fc in faces]
    pos, nrm, mask = SK.raster(flist, loopuv, Pm, Nm, res)
    rng = np.random.default_rng(31 if v else 47)
    nails = []                           # fingertips (rest pose) for nails; the dorsal side opposes the rest palm normal
    for sd, k in ((1, "R"), (-1, "L")):
        mir = np.ones(3) if sd == 1 else np.array([-1, 1, 1.0])
        f0, n0 = fig.rig.hf_rest[k]
        for chain in list(fig.rig.fingers_rest) + [fig.rig.thumb_rest]:
            j = [p * mir for p in chain]
            nails.append((j[3], unit_np(j[3] - j[2]), -n0))
    lm = dict(eye_mid=fig.eye_mid, s=fig.s)
    iris = (0.20, 0.11, 0.05) if v else (0.10, 0.20, 0.22)
    alb, rough, h = SK.bake(res, pos, nrm, mask, lm, rng, tone, stubble=0.8 if v else 0.0, freckle=0.0 if v else 0.8,
                            brow=(0.07, 0.05, 0.04) if v else (0.16, 0.07, 0.04), lip=(0.5, 0.25, 0.22) if v else (0.62, 0.32, 0.3), nail_joints=nails,
                            seed=5 if v else 9)
    u0, v0, u1, v1 = SK.EYE_RECT                       # eye tile (atlas square) painted over the baked image
    r0, r1, c0, c1 = int(res - v1 * res), int(res - v0 * res), int(u0 * res), int(u1 * res)
    ea, er = SK.paint_eye(c1 - c0, iris, rng)
    alb[r0:r1, c0:c1] = ea
    rough[r0:r1, c0:c1] = er
    mask[r0:r1, c0:c1] = True
    h[r0:r1, c0:c1] = 0.5
    alb, rough, h = SK.dilate(alb, mask), SK.dilate(rough, mask), SK.dilate(h, mask)
    nm = SK.normal_map(h, mask, amp=0.045)
    arrs = {"albedo": alb, "orm": TX.resize(np.stack([np.full_like(rough, 0.95), rough, np.zeros_like(rough)], -1), res // 2), "normal": TX.resize(nm, res // 2)}
    d = os.path.join(TEXD, asset)
    os.makedirs(d, exist_ok=True)
    paths, sizes = {}, {}
    for k_, arr in arrs.items():
        p_ = os.path.join(d, f"skin_{k_}.png")
        with open(p_, "wb") as fh:
            fh.write(TX.png_bytes(arr))
        paths[k_] = p_
        sizes[k_] = arr.shape[0]
    TEX_LOG[(asset, "skin")] = {"sizes": sizes, "files": {k_: os.path.relpath(v_, ROOT).replace("\\", "/") for k_, v_ in paths.items()}, "seed": 31 if v else 47,
                                "recipe": "industrial_market_skin.bake (3D-function bake on the Human Base Meshes smart-project atlas)", "params": {"tone": str(tone)}}
    return paths


def unit_np(v):
    return v / max(np.linalg.norm(v), 1e-9)


def make_person(P):
    asset = P["id"]
    tex = person_textures(asset)
    names = ["skin"] + list(tex.keys())
    m = C.Mesh(names)
    fig = PP.build_person(m, P)
    tex["skin"] = bake_skin_textures(asset, fig, m)
    mats = {n: C.make_material(n, tex=tex[n], normal_strength=(0.7 if n == "skin" else 1.0)) for n in names}
    pose = dict(P["pose"])                              # bake the pose into the vertices; eyes turn towards the other person's face
    fig.solve_pelvis(pose, pose["weight"])
    info = fig.pose(pose, gaze=P["gaze"])
    C.box_uv(m, {n: 2.6 for n in names})                # UVs for everything not authored (cloth strips, soles, accessories)
    import bmesh
    bmesh.ops.recalc_face_normals(m.bm, faces=[f for f in m.bm.faces if f not in fig.mine])
    eyes = np.mean([v.co[:] for fe, _ in fig.eye_faces for fc in fe for v in fc.verts], 0)
    out = {"face_world": eyes, "eye_surf": eyes + np.array([0.0, 0.012, 0.0]),
           "arms": {k: (info[f"shoulder{k}"], info[f"elbow{k}"], info[f"wrist{k}"]) for k in ("L", "R")}}
    return m, mats, tex, out


def dress_vendor(fig, m, P):
    import mathutils
    H, s = P["H"], fig.s
    sk = D.Skin(m)
    D.apron(m, sk, H, "apron", 0.0, "apron", ties=True)
    c, rx, ry = PP.neck_ring(fig, P["neck_cut"] * H + 0.004)
    D.collar(m, V((c.x, c.y, 0)), rx + 0.016, ry + 0.012, P["neck_cut"] * H + 0.006, 0.018, 0.007, "shirt", a0=-160, a1=160, lean=0.0)
    em = fig.eye_mid
    zb = em[2] + 0.052 * s                                       # band sits on the forehead just below the hairline
    ring = fig.P[(np.abs(fig.P[:, 2] - zb) < 0.006 * s) & fig.is_head]
    cx, cy = 0.5 * (ring[:, 0].min() + ring[:, 0].max()), 0.5 * (ring[:, 1].min() + ring[:, 1].max())
    hx, hy = 0.5 * (ring[:, 0].max() - ring[:, 0].min()), 0.5 * (ring[:, 1].max() - ring[:, 1].min())
    D.headband(m, V((cx, cy, zb)), mathutils.Matrix.Identity(4), "shirt", rx=hx + 0.014, ry=hy + 0.012, z=0.0)


def dress_customer(fig, m, P):
    H = P["H"]
    sk = D.Skin(m)
    c, rx, ry = PP.neck_ring(fig, P["neck_cut"] * H + 0.004)
    zc = P["neck_cut"] * H
    # hood roll, stand collar, zip, hand pockets, chest pocket, cargo pockets
    m.tube([V((c.x - rx - 0.03, c.y + 0.02, zc + 0.002)), V((c.x - rx - 0.04, c.y - 0.04, zc + 0.002)), V((c.x - 0.6 * rx, c.y - ry - 0.07, zc + 0.012)),
            V((c.x, c.y - ry - 0.085, zc + 0.016)), V((c.x + 0.6 * rx, c.y - ry - 0.07, zc + 0.012)), V((c.x + rx + 0.04, c.y - 0.04, zc + 0.002)),
            V((c.x + rx + 0.03, c.y + 0.02, zc + 0.002))],
           [0.024, 0.029, 0.033, 0.034, 0.033, 0.029, 0.024], "jacket", seg=12, samples=26, ratio=0.9, up=V((0, 0, 1)), uv=("cloth", 1.6))
    D.collar(m, V((c.x, c.y, 0)), rx + 0.022, ry + 0.02, zc + 0.012, 0.026, 0.009, "jacket", a0=-150, a1=150)
    zt, zb = zc - 0.004, 0.50 * H

    def zip_fn(i, j, nu=2, nv=26):
        z = zt - (zt - zb) * j / nv
        x = c.x + (i / nu * 2 - 1) * 0.011
        y = sk.y(x, z)
        return V((x, (y if y is not None else 0.1) + 0.0035, z))
    PP.thick_sheet(m, zip_fn, 2, 26, 0.003, "leather")
    m.box(V((c.x, (sk.y(c.x, 0.70 * H) or 0.1) + 0.012, 0.70 * H)), (0.012, 0.01, 0.03), "leather", bevel=0.002)
    for sd in (-1, 1):
        def pk(i, j, sd=sd, nu=6, nv=3):
            x = sd * 0.135 + (i / nu - 0.5) * 0.15
            z = 0.565 * H - 0.045 * j / nv - 0.015 * (i / nu)
            y = sk.y(x, z)
            return V((x, (y if y is not None else 0.1) + 0.004 + 0.004 * j / nv, z))
        PP.thick_sheet(m, pk, 6, 3, 0.004, "jacket", flip=(sd < 0))

        def cargo(i, j, sd=sd, nu=6, nv=6):
            x = sd * 0.125 + (i / nu - 0.5) * 0.15
            z = 0.42 * H - 0.17 * j / nv
            y = sk.y(x, z)
            return V((x, (y if y is not None else 0.1) + 0.008 + 0.003 * j / nv, z))
        PP.thick_sheet(m, cargo, 6, 6, 0.004, "trousers", flip=(sd < 0))

    def chest(i, j, nu=4, nv=3):
        x = 0.095 + (i / nu - 0.5) * 0.1
        z = 0.74 * H - 0.07 * j / nv
        y = sk.y(x, z)
        return V((x, (y if y is not None else 0.1) + 0.006, z))
    PP.thick_sheet(m, chest, 4, 3, 0.004, "jacket", flip=False)


def finish_person(key):
    t0 = time.time()
    P = person_specs()[0 if key == "vendor" else 1]
    m, mats, tex, info = make_person(P)
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
            return
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
        "human_base": {"source": "Blender Human Base Meshes v1.4.1 (CC0), realistic male/female body at multires level 0, retained as the static source blend",
                       "provenance": "assets/generated/industrial_market/sources/PROVENANCE.json", "bodies": {"ramen_vendor": "male", "ramen_customer": "female"},
                       "method": "capsule-bone skinning (industrial_market_rig.py) with FK/2-bone IK pose baked into the exported vertices; garments, boots and hair fitted to the "
                                 "rest-pose anatomy and skinned with the same weights; skin atlas baked from the real mesh UVs; eyes = base eyeball spheres with an atlas eye tile",
                       "person_tris_note": "raised from 8-18k: real face/hand topology (~21k tris base body incl. head and hands) cannot fit 18k once garments are added; covered body faces are removed"},
        "budgets": {"shop_tris": "35k-70k", "person_tris": "<=40k each (adult base-human topology)", "combined_tris": 120000, "combined_surfaces": 20, "texture_mib": 128},
        "costs": {"tris": {a["id"]: a["tris"] for a in assets}, "combined_tris": sum(a["tris"] for a in assets), "surfaces": {a["id"]: len(a["surfaces"]) for a in assets},
                  "combined_surfaces": sum(len(a["surfaces"]) for a in assets), "texture_mib_mips": round(tex_one, 3), "texture_mib_working": round(tex_dup, 3),
                  "texture_assumptions": "uncompressed RGBA8 + full mip chain per distinct embedded image, x2 for the duplicated imported copy; VRAM-compressed imports will be smaller",
                  "shadow_light_cost": "not measured here: Godot candidate scene owns it"},
        "previews": sorted(os.listdir(PREV)) if os.path.isdir(PREV) else [],
        "limitations": ["static baked pose, no rig or LODs", "faces/hands are the unmodified Human Base Meshes anatomy (generic adult; expression is neutral, mouth closed, no teeth/tongue, no eyelash cards); "
                        "brows, lips, stubble, nails and freckles are painted into the baked skin atlas", "eyes are the base eyeball spheres turned towards the other person (max ~22 deg from head direction); eyelids are the base mesh and do not follow",
                        "hair is a thin clumped shell (+ one ponytail tube), not strand/cards", "skin has no subsurface in glTF; the Godot post-import override should enable it", "cloth folds are procedural displacement on the garment shells, not simulated",
                        "no true glass/transparent sign lens (dark acrylic face)",
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
