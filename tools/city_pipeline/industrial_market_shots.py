"""Render inspection shots of exported GLBs: ak-blender industrial_market_shots.py -- --set people|shop|all [--night]

Re-imports the real GLBs (people placed per the manifest layout) so what is rendered is what Godot loads."""
import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
for _home in (os.environ.get("AK_HOME"), os.path.expanduser("~/agent-kit")):
    if _home and os.path.isdir(os.path.join(_home, "blender")):
        sys.path.insert(0, os.path.join(_home, "blender"))
from ak_util import args, report  # noqa: E402

import industrial_market_render as R  # noqa: E402

V = Vector
ROOT = os.path.dirname(os.path.dirname(HERE))
CAND = os.path.join(ROOT, "godot", "assets", "city", "candidates", "industrial_market")
PREV = os.path.join(ROOT, "assets", "previews", "industrial_market")

p = argparse.ArgumentParser()
p.add_argument("--set", default="people")
p.add_argument("--outdir", default=PREV)
p.add_argument("--only", default="")
p.add_argument("--res", type=int, default=900)
p.add_argument("--clay", action="store_true", help="people shots with one neutral clay material (anatomy check on the exported mesh)")
A = args(p)
os.makedirs(A.outdir, exist_ok=True)

# Shop-space (Blender) positions of the people; the customer is yawed 180 about vertical.
VEND = V((0.40, 1.33, 0.15))
CUST = V((0.66, 2.30, 0.15))

SHOTS = {
    "people": [
        ("vendor_front", "ramen_vendor", (0, 4.6, 1.0), (0, 0, 0.9), 45),
        ("vendor_side", "ramen_vendor", (4.6, 0.4, 1.0), (0, 0.4, 0.9), 45),
        ("vendor_face", "ramen_vendor", (0.25, 1.1, 1.66), (0, 0.0, 1.62), 85),
        ("vendor_34", "ramen_vendor", (2.0, 2.2, 1.3), (0, 0, 0.95), 50),
        ("customer_front", "ramen_customer", (0, 4.6, 1.0), (0, 0, 0.9), 45),
        ("customer_face", "ramen_customer", (-0.25, 1.1, 1.74), (0, 0.0, 1.70), 85),
        ("customer_back", "ramen_customer", (-1.6, -2.6, 1.3), (0, 0, 0.95), 50),
        ("hands_vendor", "ramen_vendor", (0.65, 1.15, 1.35), (0.12, 0.45, 1.0), 70),
        ("hands_customer", "ramen_customer", (0.7, 1.0, 1.45), (0.2, 0.45, 1.1), 70),
        ("vendor_34_head", "ramen_vendor", (1.0, 1.0, 1.72), (0, 0.0, 1.62), 80),
        ("customer_34_head", "ramen_customer", (-1.0, 1.0, 1.78), (0, 0.0, 1.70), 80),
        ("boots_customer", "ramen_customer", (0.9, 1.3, 0.45), (0, 0, 0.12), 60),
        ("shoes_vendor", "ramen_vendor", (0.9, 1.3, 0.4), (0, -0.05, 0.08), 60),
    ],
}


def clay(objs):
    """Replace every material with one neutral grey clay so the real exported mesh anatomy can be judged without textures."""
    mat = bpy.data.materials.new("clay")
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.62, 0.58, 0.55, 1)
    b.inputs["Roughness"].default_value = 0.75
    for o in objs:
        if o.type == "MESH":
            o.data.materials.clear()
            o.data.materials.append(mat)


def run_people():
    for name, asset, cam, tgt, lens in SHOTS["people"]:
        if A.only and name not in A.only.split(","):
            continue
        R.reset()
        sc = R.setup((A.res, int(A.res * 0.78)))
        objs = R.import_glb(os.path.join(CAND, asset + ".glb"))
        if A.clay:
            clay(objs)
        # floor card
        bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, -0.002))
        R.studio_lights()
        # the shop/people frame is Blender-front +Y; cameras given in person space
        R.camera(cam, tgt, lens)
        R.render(os.path.join(A.outdir, f"{name}{'_clay' if A.clay else ''}.png"))


SHOP = [  # name, camera (shop space, Blender), target, lens, night
    ("approach_driver", (-3.0, 11.5, 1.25), (0.3, 2.0, 1.7), 40, False),
    ("sidewalk_34", (-5.5, 7.5, 1.6), (0.6, 1.8, 1.6), 32, False),
    ("sidewalk_34_b", (6.0, 7.0, 1.7), (-0.2, 2.0, 1.7), 32, False),
    ("counter", (1.6, 4.6, 1.55), (0.5, 1.7, 1.2), 38, False),
    ("support_contact", (-1.6, 3.6, 0.9), (-2.5, 1.94, 0.6), 45, False),
    ("sign_menu", (1.2, 5.5, 3.4), (1.4, 2.2, 3.2), 38, False),
    ("materials_menu", (3.4, 3.1, 1.6), (3.45, 2.0, 1.6), 50, False),
    ("interior_service", (-0.5, -1.2, 1.5), (-1.1, 1.0, 1.1), 40, False),
    ("handoff", (-0.9, 2.05, 1.62), (0.55, 1.95, 1.25), 36, False),
    ("handoff_top", (0.55, 2.0, 2.6), (0.55, 1.95, 1.15), 40, False),
    ("night_approach", (-3.0, 11.5, 1.25), (0.3, 2.0, 1.7), 40, True),
    ("night_counter", (1.6, 4.6, 1.55), (0.5, 1.7, 1.2), 38, True),
]
ANCHORS = [  # position (shop space), colour, energy W, radius
    ((0.0, 2.7, 4.5), (1.0, 0.2, 0.1), 220, 0.5), ((0.6, 1.2, 3.55), (1.0, 0.65, 0.3), 120, 0.3), ((-1.3, 0.7, 2.05), (1.0, 0.85, 0.6), 100, 0.3),
    ((3.33, 2.4, 2.15), (1.0, 0.65, 0.3), 60, 0.2), ((-2.6, 2.3, 2.4), (1.0, 0.6, 0.25), 60, 0.2),
]


def place_people():
    for asset, pos, yaw in (("ramen_vendor", VEND, 0.0), ("ramen_customer", CUST, math.pi)):
        for o in R.import_glb(os.path.join(CAND, asset + ".glb")):
            if o.parent is None:
                o.rotation_mode = "XYZ"
                o.location = pos
                o.rotation_euler = (0, 0, yaw)


def run_shop():
    for name, cam, tgt, lens, night in SHOP:
        if A.only and name not in A.only.split(","):
            continue
        R.reset()
        sc = R.setup((A.res, int(A.res * 0.72)), night=night)
        R.import_glb(os.path.join(CAND, "redline_shop.glb"))
        place_people()
        bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 4.0, -0.003))
        R.studio_lights(night=night)
        if night:
            for pos, col, en, rad in ANCHORS:
                R.add_light("POINT", pos, en, col)
            R.add_light("SUN", (0, 10, 10), 0.15, (0.5, 0.6, 1.0), target=(0, 2, 0))
            R.add_light("AREA", (0, 9, 3), 30, (0.4, 0.55, 1.0), size=4, target=(0, 2, 1.5))
        else:
            R.add_light("AREA", (0, 14, 6), 2500, (1, 0.97, 0.92), size=8, target=(0, 2, 1.5))
        R.camera(cam, tgt, lens)
        R.render(os.path.join(A.outdir, f"shop_{name}.png"))


if A.set in ("people", "all"):
    run_people()
if A.set in ("shop", "all"):
    run_shop()
report(done=A.set)
