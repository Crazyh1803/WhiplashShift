"""One neutral and one night lineup of the REAL exported ground GLBs, re-imported into a clean scene (what Godot loads):
ak-blender tools/city_pipeline/city_ground_preview.py -- [--res 2000]

The runtime GLBs are geometry-only, so each imported material stub is rebound by name to the shared realism PNGs (as city_realism_preview.py does).
Outputs assets/previews/city_ground/lineup_ground_{neutral,night}.png. Blender lighting is diagnostic only."""
import argparse
import json
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
for _home in (os.environ.get("AK_HOME"), os.path.expanduser("~/agent-kit")):
    if _home and os.path.isdir(os.path.join(_home, "blender")):
        sys.path.insert(0, os.path.join(_home, "blender"))
from ak_util import args, report  # noqa: E402

import industrial_market_render as R  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
REAL = os.path.join(ROOT, "godot", "assets", "city", "realism")
GROUND = os.path.join(ROOT, "godot", "assets", "city", "ground")
PREV = os.path.join(ROOT, "assets", "previews", "city_ground")
p = argparse.ArgumentParser()
p.add_argument("--res", type=int, default=2000)
A = args(p)
MAN = json.load(open(os.path.join(GROUND, "city_ground_manifest.json"), encoding="utf-8"))
LIB = json.load(open(os.path.join(ROOT, MAN["shared_library"]["manifest"]), encoding="utf-8"))["materials"]


def tex_node(nt, rel, srgb):
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = bpy.data.images.load(os.path.join(REAL, rel), check_existing=True)
    n.image.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
    return n


def rebind(objs):
    """Bind each stub material to its library PNGs; COLOR_0 (the importer's vertex-colour node) multiplies the albedo."""
    for o in objs:
        if o.type != "MESH":
            continue
        for slot in o.material_slots:
            m = slot.material
            lib = LIB[m.name.split(".")[0]]
            nt = m.node_tree
            b = nt.nodes["Principled BSDF"]
            alb = tex_node(nt, lib["albedo"], True)
            vc = next((v for v in nt.nodes if v.type == "VERTEX_COLOR"), None)
            if vc is None:
                nt.links.new(alb.outputs["Color"], b.inputs["Base Color"])
            else:
                mul = nt.nodes.new("ShaderNodeMix")
                mul.data_type, mul.blend_type = "RGBA", "MULTIPLY"
                mul.inputs["Factor"].default_value = 1.0
                nt.links.new(alb.outputs["Color"], mul.inputs["A"])
                nt.links.new(vc.outputs["Color"], mul.inputs["B"])
                nt.links.new(mul.outputs["Result"], b.inputs["Base Color"])
            sep = nt.nodes.new("ShaderNodeSeparateColor")
            nt.links.new(tex_node(nt, lib["orm"], False).outputs["Color"], sep.inputs["Color"])
            nt.links.new(sep.outputs["Green"], b.inputs["Roughness"])
            nt.links.new(sep.outputs["Blue"], b.inputs["Metallic"])
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(tex_node(nt, lib["normal"], False).outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])


def surround():
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, -0.012))
    g = bpy.context.object
    g.scale = (120, 60, 1)
    mt = bpy.data.materials.new("surround")
    mt.use_nodes = True
    b = mt.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.05, 0.05, 0.055, 1)
    b.inputs["Roughness"].default_value = 0.95
    g.data.materials.append(mt)


def lineup(night):
    R.reset()
    sc = R.setup((A.res, int(A.res * 0.45)), night=night)
    surround()
    gap = 1.8
    total = sum(a["width_m"] for a in MAN["assets"]) + gap * (len(MAN["assets"]) - 1)
    x = -total / 2
    for a in MAN["assets"]:
        objs = R.import_glb(os.path.join(GROUND, a["glb"]))
        rebind(objs)
        for o in objs:
            if o.parent is None:
                o.location.x += x + a["width_m"] / 2
        x += a["width_m"] + gap
    if night:
        R.add_light("SUN", (-10, 10, 14), 0.25, (0.55, 0.65, 1.0), target=(0, 0, 0))
        for lx in (-26, -9, 9, 26):
            R.add_light("POINT", (lx, 3.0, 5.0), 9000, (1.0, 0.72, 0.4), size=0.4, target=(lx, 0, 0))
        sc.view_settings.exposure = 0.8
    else:
        R.add_light("SUN", (12, 18, 22), 3.2, (1.0, 0.96, 0.9), target=(0, 0, 0))
        R.add_light("AREA", (-10, 20, 8), 900, (0.8, 0.88, 1.0), size=8, target=(0, 0, 0))
    R.camera((0, 40, 34), (0, -1.0, 0), 24)
    path = os.path.join(PREV, f"lineup_ground_{'night' if night else 'neutral'}.png")
    R.render(path)
    report(lineup="ground", night=night, out=os.path.relpath(path, ROOT).replace("\\", "/"))


os.makedirs(PREV, exist_ok=True)
for n in (False, True):
    lineup(n)
