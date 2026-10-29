"""QA lineup for city_detail.py: every person role, the six shop signs + two plaques, and one pier, with measured tris.

Run (never the GUI):  ak-blender tools/city_pipeline/city_detail_lineup.py -- [--outdir assets/previews/city_neighborhood/detail]
Reads only the AK: lines. Renders go to --outdir (people_front/people_three_quarter/faces/signs/pier + night signs).
"""
import argparse
import importlib.util
import os
import random
import sys

import bpy

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
_spec = importlib.util.spec_from_file_location("build_habitation_workshop", os.path.join(_HERE, "build_habitation_workshop.py"))
W = importlib.util.module_from_spec(_spec)
sys.modules["build_habitation_workshop"] = W
_spec.loader.exec_module(W)
import city_detail as CD  # noqa: E402

p = argparse.ArgumentParser()
p.add_argument("--outdir", default="assets/previews/city_neighborhood/detail")
a = W.args(p)
os.makedirs(a.outdir, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
W.ASSET_ID = "lineup"
coll = bpy.data.collections.new("lineup")
bpy.context.scene.collection.children.link(coll)
mats = W.make_materials()
k = W.Kit()
ROLES = [("stand", False), ("shopper", False), ("walker", False), ("worker", False), ("vendor", False), ("diner", True),
         ("stand", False), ("shopper", False), ("walker", False), ("worker", False)]
tri = {}
for i, (role, seated) in enumerate(ROLES):
    t0 = k.tris()
    CD.person(k, -5.0 + i * 1.1, -14.0, 0.0, random.Random(i * 7 + 3), 0.0, seated, role=role, stool=seated)
    tri[f"{i}:{role}"] = k.tris() - t0
W.report(person_tris=tri, mean=round(sum(tri.values()) / len(tri)))
y0 = 6.0
with k.part(".signs"):
    rng = random.Random("signs")
    for i, (name, icon, ca, cb, tint, gl) in enumerate(CD.SHOPS):
        x0 = -9.0 + (i % 3) * 3.7
        z0 = 3.0 + (i // 3) * 1.2
        with k.part(".sign" + str(i)):
            k.box(x0 - 0.1, x0 + 3.4, y0 - 0.4, y0, z0 - 0.2, z0 + 1.0, "ceramic")
            CD.shop_sign(k, x0, x0 + 3.3, z0, z0 + 0.8, name, icon, ca, cb, tint, gl, rng, y0=y0, y1=y0 + 0.42)
    for i, (name, icon, ca, cb, tint) in enumerate(CD.PLAQUES):
        CD.shop_sign(k, 4.5 + i * 2.7, 6.9 + i * 2.7, 3.0, 3.6, name, icon, ca, cb, tint, False, rng, y0=y0, y1=0.3 + y0)
CD.pier(k, 9.0, 0.0, 0.0, 4.45)
CD.blade_sign(k, 6.0, 1.0, 4.0, 3.1, "cup", "glow_cyan", "glow_amber", (0.2, 0.2, 0.3), 0.6, 4.45)
ob = W.finalize(k, mats, coll)
W.report(total_tris=W.measure(ob)[2][1], parts=k.parts)
W.wire_vertex_colors(mats)
W.pick_engine(bpy.context.scene)
st = W.Studio()
from mathutils import Vector  # noqa: E402


def shot(name, az, cam, tgt, lens=38, res=(1600, 1000)):
    st.aim(az)
    st.snap(os.path.join(a.outdir, name + ".png"), W.dp(*cam), W.dp(*tgt), lens, res=res)
    W.report(render=name)


shot("people_front", 0, (0.5, -4.5, 1.4), (0.5, -14, 0.9), 40)
shot("people_three_quarter", -30, (-9, -8.5, 1.9), (0, -14, 0.9), 40)
shot("people_faces", 0, (-2.0, -11.5, 1.65), (-2.0, -14, 1.55), 55)
shot("vendor_full", 0, (0.6, -11.0, 1.2), (-0.6, -14, 0.9), 40, (1000, 1400))
shot("sign_roots", 0, (-7, 12, 3.3), (-6, y0, 3.4), 40)
shot("signs_all", 0, (-3, 17, 3.5), (-3, y0, 3.5), 36)
shot("pier_assembly", -20, (14, 6.5, 2.4), (9, 0, 2.3), 38, (1000, 1400))
bg = bpy.context.scene.world.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.004, 0.005, 0.009, 1)
for lo, _ in st.lights:
    lo.data.energy *= 0.04
shot("signs_night", 0, (-3, 17, 3.5), (-3, y0, 3.5), 36)
