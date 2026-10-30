"""Closeups of the converted redline_shop with the approved ramen vendor/customer loaded at the manifest's actor_sockets.

ak-blender tools/city_pipeline/city_realism_actor_shots.py [-- --res 1000]
Re-imports the exported GLBs (what Godot loads). Output: assets/previews/city_realism/redline_shop_actors_<view>.png"""
import argparse
import json
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
REAL = os.path.join(ROOT, "godot", "assets", "city", "realism")
PREV = os.path.join(ROOT, "assets", "previews", "city_realism")

p = argparse.ArgumentParser()
p.add_argument("--res", type=int, default=1000)
A = args(p)
os.makedirs(PREV, exist_ok=True)

man = json.load(open(os.path.join(REAL, "city_families_manifest.json"), encoding="utf-8"))
shop = next(a for a in man["assets"] if a["id"] == "redline_shop")
SK = shop["actor_sockets"]


def b(p):
    """glTF (x, y up, z) -> Blender (x, -z, y), the importer's own conversion."""
    return V((p[0], -p[2], p[1]))


# name, camera (Blender shop space), target, lens, night
VIEWS = [
    ("handoff", (1.4, 2.6, 1.55), (1.35, 0.0, 1.25), 38, False),
    ("handoff_34", (-1.0, 2.3, 1.7), (1.35, 0.0, 1.2), 38, False),
    ("feet_counter", (2.6, 2.1, 0.55), (1.35, 0.0, 0.8), 40, False),
    ("kitchen_side", (1.2, -2.5, 1.5), (1.35, 0.2, 1.3), 35, False),
    ("street_34", (-4.5, 6.0, 1.7), (1.0, 0.5, 1.6), 32, False),
    ("night", (1.6, 3.4, 1.6), (1.35, 0.0, 1.3), 38, True),
]


def place_actor(key):
    s = SK[key]
    for o in R.import_glb(os.path.join(ROOT, s["glb"])):
        if o.parent is None:
            o.rotation_mode = "XYZ"
            o.location = b(s["position"])
            o.rotation_euler = (0, 0, math.radians(s["yaw_degrees"]))


for name, cam, tgt, lens, night in VIEWS:
    R.reset()
    R.setup((A.res, int(A.res * 0.75)), night=night)
    R.import_glb(os.path.join(REAL, "redline_shop.glb"))
    place_actor("vendor")
    place_actor("customer")
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 4.0, -0.003))
    R.studio_lights(night=night)
    if night:
        la = SK["light"]
        R.add_light("POINT", b(la["position"]), 150 * la["energy"], la["color"])
        R.add_light("POINT", (0.0, 2.7, 4.5), 220, (1.0, 0.3, 0.15))
        R.add_light("SUN", (0, 10, 10), 0.15, (0.5, 0.6, 1.0), target=(0, 2, 0))
    else:
        R.add_light("AREA", (0, 14, 6), 2500, (1, 0.97, 0.92), size=8, target=(0, 2, 1.5))
        R.add_light("POINT", (1.35, -1.8, 2.2), 120, (1.0, 0.9, 0.7))          # kitchen fill for the vendor side
    R.camera(cam, tgt, lens)
    R.render(os.path.join(PREV, f"redline_shop_actors_{name}.png"))
report(done="actor_shots", views=[v[0] for v in VIEWS])
