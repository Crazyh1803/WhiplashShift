"""Prepare the retained base-human source: ak-blender tools/city_pipeline/industrial_market_base_source.py

Downloads the official Blender Human Base Meshes bundle v1.4.1 (CC0, see sources/PROVENANCE.json) into a scratch dir under %TEMP%,
checks/records its sha256, and writes ONLY the used data (realistic male + female body at multires level 0, with their eye
spheres and UVs) to assets/generated/industrial_market/sources/human_base_meshes_v141_used.blend. Idempotent."""
import hashlib
import json
import os
import sys
import tempfile
import urllib.request
import zipfile

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
for _home in (os.environ.get("AK_HOME"), os.path.expanduser("~/agent-kit")):
    if _home and os.path.isdir(os.path.join(_home, "blender")):
        sys.path.insert(0, os.path.join(_home, "blender"))
from ak_util import report  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
SRCDIR = os.path.join(ROOT, "assets", "generated", "industrial_market", "sources")
URL = "https://download.blender.org/demo/asset-bundles/human-base-meshes/human-base-meshes-bundle-v1.4.1.zip"
SHA = "811f43accbb31a88266d932f8f5563b2d13586fca0ba2693aad1f5fe582b3515"
PICK = {"male": ("Body Male - Realistic", "GEO-body_male_realistic"), "female": ("Body Female - Realistic", "GEO-body_female_realistic")}


def main():
    os.makedirs(SRCDIR, exist_ok=True)
    work = os.path.join(tempfile.gettempdir(), "hbm_src_v141")
    os.makedirs(work, exist_ok=True)
    zp = os.path.join(work, "bundle.zip")
    if os.path.exists(zp):
        with open(zp, "rb") as cached:
            valid_cache = hashlib.sha256(cached.read()).hexdigest() == SHA
        if not valid_cache:
            os.remove(zp)
    if not os.path.exists(zp):
        with urllib.request.urlopen(URL, timeout=60) as response:
            payload = response.read(64 * 1024 * 1024 + 1)
        if hashlib.sha256(payload).hexdigest() != SHA:
            raise RuntimeError("Downloaded human-base bundle checksum differs")
        with open(zp + ".part", "wb") as archive:
            archive.write(payload)
        os.replace(zp + ".part", zp)
    h = SHA
    ex = os.path.join(work, "x")
    if not os.path.isdir(ex):
        with zipfile.ZipFile(zp) as z:
            z.extractall(ex)
    blend = os.path.join(ex, "human-base-meshes-bundle-v1.4.1", "human_base_meshes_bundle.blend")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(blend) as (d, t):
        t.collections = [v[0] for v in PICK.values()]
    stats = {}
    out = bpy.data.collections.new("HBM_v141_used")
    bpy.context.scene.collection.children.link(out)
    for key, (cname, oname) in PICK.items():
        coll = next(c for c in t.collections if c.name == cname)
        bpy.context.scene.collection.children.link(coll)
        bpy.context.view_layer.update()
        src = coll.all_objects[oname]
        for mod in src.modifiers:
            if mod.type == "MULTIRES":
                mod.levels = mod.sculpt_levels = mod.render_levels = 0
        dg = bpy.context.evaluated_depsgraph_get()
        # level-0 data lives in the mesh itself (no evaluation needed); copy verts/polys/UV into a fresh displacement-free mesh
        me0 = src.data
        me = bpy.data.meshes.new(f"base_{key}")
        me.from_pydata([v.co[:] for v in me0.vertices], [], [tuple(p.vertices) for p in me0.polygons])
        uv = me.uv_layers.new(name="UVMap")
        for i, lp in enumerate(me0.loops):
            uv.data[i].uv = me0.uv_layers["UVMap"].data[i].uv
        for p in me.polygons:
            p.use_smooth = True
        ob = bpy.data.objects.new(f"base_{key}", me)
        ob.location = (0, 0, 0)
        out.objects.link(ob)
        ob["source_object"] = oname
        ob["source_location"] = list(src.location)
        stats[key] = {"verts": len(me.vertices), "polys": len(me.polygons)}
        for eye in src.children:
            em = bpy.data.meshes.new(f"eye_{key}_{eye.name[-1]}")
            e0 = eye.data
            em.from_pydata([v.co[:] for v in e0.vertices], [], [tuple(p.vertices) for p in e0.polygons])
            eo = bpy.data.objects.new(f"eye_{key}_{eye.name[-1]}", em)
            mw = eye.matrix_world.copy()                       # true world matrix (collection is linked + updated above)
            mw.translation = mw.translation - src.matrix_world.translation
            eo.location, eo.rotation_euler, eo.scale = mw.to_translation(), mw.to_euler(), mw.to_scale()
            out.objects.link(eo)
    for c in list(bpy.data.collections):
        if c is not out:
            bpy.data.collections.remove(c)
    for o in list(bpy.data.objects):
        if o.name not in out.objects:
            bpy.data.objects.remove(o)
    bpy.data.orphans_purge(do_recursive=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRCDIR, "human_base_meshes_v141_used.blend"), compress=True)
    prov = {"name": "Human Base Meshes", "version": "1.4.1", "publisher": "Blender Studio / Blender Foundation (community contributors)",
            "license": "CC0 1.0 (as listed on https://www.blender.org/download/demo-files/; not re-verified in-session)",
            "download_url": URL, "download_method": "ak-blender script urllib download, sha256-verified (this script)", "bundle_sha256": SHA,
            "bundle_bytes": os.path.getsize(zp), "used": {"male": "GEO-body_male_realistic (+2 eye spheres), Multires level 0", "female": "GEO-body_female_realistic (+2 eye spheres), Multires level 0"},
            "not_retained": "rest of the bundle (skeletons, primitives, stylized, heads, hands, feet); multires levels 1-3 displacement not retained",
            "retained_file": "human_base_meshes_v141_used.blend", "retained_sha256": hashlib.sha256(open(os.path.join(SRCDIR, "human_base_meshes_v141_used.blend"), "rb").read()).hexdigest(),
            "stats": stats}
    with open(os.path.join(SRCDIR, "PROVENANCE.json"), "w", encoding="utf-8") as fh:
        json.dump(prov, fh, indent=1)
    with open(os.path.join(SRCDIR, "LICENSE_CREDITS.txt"), "w", encoding="utf-8") as fh:
        fh.write("Human Base Meshes v1.4.1 - Blender Studio / Blender Foundation and contributors.\nListed as CC0 (public domain dedication) at "
                 "https://www.blender.org/download/demo-files/ . Only the realistic male/female body level-0 meshes, UVs and eye spheres are retained here.\n"
                 "Derived person assets in this folder's parent use these meshes with clothing, hair and textures added by tools/city_pipeline.\n")
    report(**stats, sha=h)


main()
