"""Renders of the REAL exported city realism GLBs, re-imported into a clean scene (what Godot loads):
ak-blender tools/city_pipeline/city_realism_preview.py -- --set all|assets|lineups [--only id,id] [--res 900]

Runtime GLBs are geometry-only: every imported material stub (named exactly like its extras.library_binding) is explicitly rebound
to the shared PNGs of the manifest material library, so previews stay reproducible without the textured source exports.
Outputs assets/previews/city_realism/<id>_{front,street,night}.png and lineup_{buildings,streets}_{neutral,night}.png. Blender lighting is diagnostic only."""
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
p.add_argument("--set", default="all")
p.add_argument("--only", default="")
p.add_argument("--res", type=int, default=900)
A = args(p)
os.makedirs(PREV, exist_ok=True)
MAN = json.load(open(os.path.join(REAL, "city_families_manifest.json"), encoding="utf-8"))
ASSETS = {a["id"]: a for a in MAN["assets"]}
rebound = {"n": 0}


def to_bl(g):
    return V((g[0], -g[2], g[1]))


def rebind(objs):
    """Make sure every imported library material carries its texture nodes; rebuild from the manifest library if the importer dropped them."""
    for o in objs:
        if o.type != "MESH":
            continue
        for slot in o.material_slots:
            m = slot.material
            lib = MAN["materials"].get(m.name.split(".")[0])
            if lib is None:
                raise SystemExit(f"material {m.name} not in library")
            nt = m.node_tree
            if any(n.type == "TEX_IMAGE" and n.image for n in nt.nodes) or ("albedo" not in lib and "orm" not in lib):
                continue                                     # already bound, or texture-free by design (lamp_glass)
            rebound["n"] += 1
            rebound.setdefault("names", set()).add(m.name)
            b = nt.nodes["Principled BSDF"]
            for slot_name, nc, sock in (("albedo", False, "Base Color"),):
                if slot_name in lib:
                    n = nt.nodes.new("ShaderNodeTexImage")
                    n.image = bpy.data.images.load(os.path.join(REAL, lib[slot_name]), check_existing=True)
                    nt.links.new(n.outputs["Color"], b.inputs[sock])
            if "orm" in lib:
                n = nt.nodes.new("ShaderNodeTexImage")
                n.image = bpy.data.images.load(os.path.join(REAL, lib["orm"]), check_existing=True)
                n.image.colorspace_settings.name = "Non-Color"
                sep = nt.nodes.new("ShaderNodeSeparateColor")
                nt.links.new(n.outputs["Color"], sep.inputs["Color"])
                nt.links.new(sep.outputs["Green"], b.inputs["Roughness"])
                nt.links.new(sep.outputs["Blue"], b.inputs["Metallic"])
            if "normal" in lib:
                n = nt.nodes.new("ShaderNodeTexImage")
                n.image = bpy.data.images.load(os.path.join(REAL, lib["normal"]), check_existing=True)
                n.image.colorspace_settings.name = "Non-Color"
                nm = nt.nodes.new("ShaderNodeNormalMap")
                nt.links.new(n.outputs["Color"], nm.inputs["Color"])
                nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
            if "emissive" in lib:
                n = nt.nodes.new("ShaderNodeTexImage")
                n.image = bpy.data.images.load(os.path.join(REAL, lib["emissive"]), check_existing=True)
                nt.links.new(n.outputs["Color"], b.inputs["Emission Color"])


def place(aid, x=0.0, lod1=False):
    objs = R.import_glb(os.path.join(REAL, aid + ("_lod1" if lod1 else "") + ".glb"))
    rebind(objs)
    for o in objs:
        if o.parent is None:
            o.location.x += x
    return objs


def ground(w=60, depth=60, y0=-30):
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, y0 + depth / 2 - depth / 2 + 0.0, -0.01))
    g = bpy.context.object
    g.scale = (w, depth, 1)
    mt = bpy.data.materials.new("ground")
    mt.use_nodes = True
    b = mt.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.09, 0.09, 0.095, 1)
    b.inputs["Roughness"].default_value = 0.9
    g.data.materials.append(mt)
    return g


def night_lights(aid, x=0.0, scale=1.0):
    a = ASSETS[aid]
    for la in a["light_anchors"]:
        pos = to_bl(la["position"]) + V((x, 0, 0))
        d = to_bl(la["direction"])
        kind = "SPOT" if la["shadow"] else "POINT"
        ld = bpy.data.lights.new(la["id"], kind)
        ld.energy = 900 * la["energy"] * (la["range_m"] / 8.0) ** 2 * scale
        ld.color = tuple(la["color"])
        ld.shadow_soft_size = 0.15
        if kind == "SPOT":
            ld.spot_size = math.radians(100)
            ld.spot_blend = 0.6
        ob = bpy.data.objects.new(la["id"], ld)
        bpy.context.scene.collection.objects.link(ob)
        ob.location = pos
        if kind == "SPOT":
            ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def moon():
    R.add_light("SUN", (-10, 10, 14), 0.25, (0.55, 0.65, 1.0), target=(0, 0, 0))


def shot(path, cam, tgt, lens, night, objs_fn, res=None, aspect=0.75):
    R.reset()
    sc = R.setup((res or A.res, int((res or A.res) * aspect)), night=night)
    ground()
    objs_fn()
    if night:
        moon()
        sc.view_settings.exposure = 0.8
    else:
        R.add_light("SUN", (12, 18, 22), 3.2, (1.0, 0.96, 0.9), target=(0, -4, 3))
        R.add_light("AREA", (-10, 20, 8), 900, (0.8, 0.88, 1.0), size=8, target=(0, 0, 3))
    R.camera(cam, tgt, lens)
    R.render(path)


def asset_shots(aid):
    a = ASSETS[aid]
    if a["role"] == "building":
        W, H = a["frontage_m"], a["height_m"]
        shots = [("front", (W * 0.55, 13 + W * 0.45, 2.0 + H * 0.18), (-W * 0.02, 0, H * 0.4), 30, False),
                 ("street", (-W * 0.18, 9.5, 1.65), (0, 0, min(H * 0.28, 3.2)), 26, False),
                 ("night", (W * 0.4, 9.0 + W * 0.2, 1.7), (0, 0, min(H * 0.33, 3.5)), 28, True)]
    else:
        ext = max(a["aabb"]["max"][0] - a["aabb"]["min"][0], a["aabb"]["max"][1], 1.0)
        c = V((0, 0, a["aabb"]["max"][1] * 0.45))
        shots = [("front", (ext * 0.8, ext * 1.5 + 1.5, c.z + ext * 0.5), tuple(c), 38, False),
                 ("night", (ext * 0.9, ext * 1.4 + 1.5, c.z + ext * 0.2), tuple(c), 38, True)]
    for tag, cam, tgt, lens, night in shots:
        def fn():
            place(aid)
            if night:
                night_lights(aid)
        shot(os.path.join(PREV, f"{aid}_{tag}.png"), cam, tgt, lens, night, fn)
        report(shot=f"{aid}_{tag}")


def lineup(kind, night, part=0):
    ids = [i for i, a in ASSETS.items() if a["role"] == kind]
    if kind == "building":
        ids = ids[part * 4:(part + 1) * 4]
    xs, cur = {}, 0.0
    widths = {i: (ASSETS[i]["frontage_m"] if kind == "building" else max(ASSETS[i]["aabb"]["max"][0] - ASSETS[i]["aabb"]["min"][0], 0.8)) for i in ids}
    gap = 3.0 if kind == "building" else 1.4
    total = sum(widths.values()) + gap * (len(ids) - 1)
    cur = -total / 2
    for i in ids:
        xs[i] = cur + widths[i] / 2
        cur += widths[i] + gap

    def fn():
        for i in ids:
            place(i, xs[i])
            if night:
                night_lights(i, xs[i], 0.8)
    if kind == "building":
        name = "lineup_buildings" if part == 0 else "lineup_buildings_b"
        shot(os.path.join(PREV, f"{name}_{'night' if night else 'neutral'}.png"), (total * 0.08, total * 0.98 + 14, 3.0), (0, 0, 5.2), 32, night, fn, res=2000, aspect=0.42)
    else:
        shot(os.path.join(PREV, f"lineup_streets_{'night' if night else 'neutral'}.png"), (0, 56, 4.0), (0, 0, 3.4), 40, night, fn, res=2400, aspect=0.34)
    report(lineup=kind, night=night, part=part)


if A.set in ("all", "assets"):
    for aid in ASSETS:
        if not A.only or aid in A.only.split(","):
            asset_shots(aid)
if A.set in ("all", "lineups"):
    for n in (False, True):
        lineup("building", n, 0)
        lineup("building", n, 1)
        lineup("street", n)
report(rebound_materials=rebound["n"], names=sorted(rebound.get("names", [])))
