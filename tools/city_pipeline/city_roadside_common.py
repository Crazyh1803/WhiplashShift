"""Shared plumbing for the roadside detail builders (Blender, never the GUI).

Reuses industrial_market_common (C.Mesh / C.commit / box_uv / ray_ao), city_realism_parts (P.Ctx and the facade helpers) and city_realism_bind
(textured export + geometry-only runtime GLB). The shared PBR library already exists on disk, so no texture is generated here and nothing in
godot/assets/city/realism/ is written. build_city_families is deliberately not imported (it runs main on import).

    mats()                       the 14 canonical library materials as Blender materials (bound to the shared PNGs)
    finish(ctx, name, ...)       box UVs + refined cells + AO/wear in COLOR_0 -> textured export + runtime stub GLB + metrics dict
"""
import hashlib
import json
import math
import os
import struct
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
for _home in (os.environ.get("AK_HOME"), os.path.expanduser("~/agent-kit")):
    if _home and os.path.isdir(os.path.join(_home, "blender")):
        sys.path.insert(0, os.path.join(_home, "blender"))

import industrial_market_common as C  # noqa: E402
import city_realism_bind as BIND  # noqa: E402
import city_realism_textures as T  # noqa: E402
import city_realism_parts as P  # noqa: E402
import validate_city_families as VAL  # noqa: E402

V = Vector
ROOT = os.path.dirname(os.path.dirname(HERE))
REAL = os.path.join(ROOT, "godot", "assets", "city", "realism")
OUT = os.path.join(ROOT, "godot", "assets", "city", "roadside")
GEN = os.path.join(ROOT, "assets", "generated", "city_roadside")
TEXTURED = os.path.join(GEN, "textured_exports")
for _d in (OUT, GEN, TEXTURED, os.path.join(GEN, "blends")):
    os.makedirs(_d, exist_ok=True)

_MATS = {}


def library():
    return json.load(open(os.path.join(REAL, "city_families_manifest.json"), encoding="utf-8"))["materials"]


def mats():
    """name -> Blender material for every canonical library entry (same node setup the family build used)."""
    if _MATS:
        return _MATS
    lib = library()
    for name in T.LIBRARY:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        b = nt.nodes["Principled BSDF"]
        base, rough, metal = T.FACTORS[name]
        b.inputs["Base Color"].default_value = (*base, 1)
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal

        def img(slot, nc, name=name):
            path = os.path.join(REAL, lib[name][slot])
            im = bpy.data.images.load(path, check_existing=True)
            im.colorspace_settings.name = "Non-Color" if nc else "sRGB"
            im.name = os.path.splitext(os.path.basename(path))[0]
            n = nt.nodes.new("ShaderNodeTexImage")
            n.image = im
            n.interpolation = "Linear"
            return n
        if "albedo" in lib[name]:
            nt.links.new(img("albedo", False).outputs["Color"], b.inputs["Base Color"])
        if "orm" in lib[name]:
            sep = nt.nodes.new("ShaderNodeSeparateColor")
            nt.links.new(img("orm", True).outputs["Color"], sep.inputs["Color"])
            nt.links.new(sep.outputs["Green"], b.inputs["Roughness"])
            nt.links.new(sep.outputs["Blue"], b.inputs["Metallic"])
        if "normal" in lib[name]:
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(img("normal", True).outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
        if name == "sign_atlas":
            nt.links.new(img("emissive", False).outputs["Color"], b.inputs["Emission Color"])
            b.inputs["Emission Strength"].default_value = T.EMISSIVE[name]
        if name == "lamp_glass":
            b.inputs["Emission Color"].default_value = (1.0, 0.82, 0.5, 1)
            b.inputs["Emission Strength"].default_value = T.EMISSIVE[name]
        _MATS[name] = m
    return _MATS


def seed_of(name):
    return sum(ord(ch) * (i + 11) for i, ch in enumerate(name))


def refine(mesh, max_edge):
    bm = mesh.bm
    for _ in range(6):
        edges = []
        for e in bm.edges:
            if e.calc_length() <= max_edge or not e.link_faces:
                continue
            if any(len(f.verts) > 4 or mesh.mats[f.material_index] in ("sign_atlas", "lamp_glass") or max(abs(f.normal.x), abs(f.normal.y), abs(f.normal.z)) < 0.998 for f in e.link_faces):
                continue
            edges.append(e)
        if not edges:
            break
        bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True)


def tri_count(bm):
    return sum(len(f.verts) - 2 for f in bm.faces)


def wear_fn(ctx, top, grime=1.0, soot=None):
    """COLOR_0 tint: ground splash, rain streaks under joints, use-point grime, sun-faded top; `soot` = (x, y, z, r, s) burn marks."""
    drips, dirty, polish = ctx.drips, ctx.dirty, ctx.polish
    exp = math.exp

    def f(pt, n, mat):
        if mat in ("sign_atlas", "lamp_glass"):
            return (1.0, 1.0, 1.0)
        z = pt.z
        v = 0.97 * (1 - 0.34 * grime * exp(-z / 0.5))
        v *= 0.94 + 0.06 * math.sin(pt.x * 0.63 + z * 0.29) * math.cos(pt.y * 0.47 + pt.x * 0.17)
        for (x, y, zt, w, s) in drips:
            if zt - 2.4 < z < zt + 0.02 and abs(pt.y - y) < 1.0:
                v *= 1 - s * grime * exp(-((pt.x - x) / w) ** 2) * (1 - (zt - z) / 2.4)
        for (x, y, zc, r, s) in dirty:
            d2 = (pt.x - x) ** 2 + (pt.y - y) ** 2 + (z - zc) ** 2
            if d2 < r * r:
                v *= 1 - s * grime * (1 - math.sqrt(d2) / r)
        for (x, y, zc, r) in polish:
            d2 = (pt.x - x) ** 2 + (pt.y - y) ** 2 + (z - zc) ** 2
            if d2 < r * r:
                v = min(1.0, v * 1.22)
        if z > top - 0.9:
            v *= 0.94
        rust = 0.93 if (z < 1.3 and mat in ("steel_structure", "cladding_corrugated", "equipment_steel")) else 1.0
        out = (v, v * 0.985, v * rust * 0.965)
        for (x, y, zc, r, rgb, tmat) in ctx.tints:
            if mat == tmat and (pt.x - x) ** 2 + (pt.y - y) ** 2 + (z - zc) ** 2 < r * r:
                out = (out[0] * rgb[0], out[1] * rgb[1], out[2] * rgb[2])
        for (x, y, zc, r, s) in (soot or ()):
            d2 = (pt.x - x) ** 2 + (pt.y - y) ** 2 + (z - zc) ** 2
            if d2 < r * r:
                k = 1 - s * (1 - math.sqrt(d2) / r)
                out = (out[0] * k, out[1] * k, out[2] * k)
        return out
    return f


def externalize(path):
    """Exported GLB -> shared image URIs, TANGENT added -> retained textured source + geometry-only runtime stub (same flow as the family build)."""
    data = open(path, "rb").read()
    off = 12
    js = binary = None
    while off < len(data):
        clen, ctype = struct.unpack_from("<I4s", data, off)
        body = data[off + 8:off + 8 + clen]
        if ctype == b"JSON":
            js = json.loads(body.decode("utf-8"))
        elif ctype == b"BIN\x00":
            binary = body
        off += 8 + clen
    extra_tangents = VAL.compute_tangents(js, binary)
    image_views = {im["bufferView"] for im in js.get("images", []) if "bufferView" in im}
    for im in js.get("images", []):
        stem = os.path.splitext(im.get("name", ""))[0]
        if "bufferView" in im:
            del im["bufferView"]
        im["uri"] = f"textures/{stem}.png"
        im["mimeType"] = "image/png"
    new_bin = bytearray()
    remap = {}
    views = []
    for i, bv in enumerate(js["bufferViews"]):
        if i in image_views:
            continue
        o = bv.get("byteOffset", 0)
        chunk = binary[o:o + bv["byteLength"]]
        while len(new_bin) % 4:
            new_bin.append(0)
        nb = dict(bv)
        nb["byteOffset"] = len(new_bin)
        new_bin += chunk
        remap[i] = len(views)
        views.append(nb)
    js["bufferViews"] = views
    for a in js["accessors"]:
        if "bufferView" in a:
            a["bufferView"] = remap[a["bufferView"]]
    for (pi_mesh, pi_prim), tans in extra_tangents.items():
        while len(new_bin) % 4:
            new_bin.append(0)
        blob = b"".join(struct.pack("<4f", *t) for t in tans)
        js["bufferViews"].append({"buffer": 0, "byteOffset": len(new_bin), "byteLength": len(blob), "target": 34962})
        new_bin += blob
        js["accessors"].append({"bufferView": len(js["bufferViews"]) - 1, "componentType": 5126, "count": len(tans), "type": "VEC4"})
        js["meshes"][pi_mesh]["primitives"][pi_prim]["attributes"]["TANGENT"] = len(js["accessors"]) - 1
    while len(new_bin) % 4:
        new_bin.append(0)
    js["buffers"] = [{"byteLength": len(new_bin)}]
    BIND.write_pair(js, bytes(new_bin), os.path.join(TEXTURED, os.path.basename(path)), path)


def export(ob, path):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True, export_texcoords=True, export_normals=True,
              export_tangents=True, export_materials="EXPORT", export_cameras=False, export_lights=False, export_animations=False,
              export_image_format="AUTO", export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_colors=True)
    props = bpy.ops.export_scene.gltf.get_rna_type().properties
    kw = {k: v for k, v in kw.items() if k in props}
    if "export_active_vertex_color_when_no_material" in props:
        kw["export_active_vertex_color_when_no_material"] = True
    bpy.ops.export_scene.gltf(**kw)
    externalize(path)


def sha256(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def finish(ctx, name, tri_cap=40000, edges=(1.7, 2.4, 3.4, 5.0, 8.0, 99.0), rays=8, ao_dist=0.8, grime=1.0, soot=None, save_blend=True):
    """Refine to the finest cell size that fits tri_cap, bake AO x wear, export textured + runtime GLBs; returns the metrics record."""
    m = ctx.m
    C.box_uv(m, T.UV_PER_M)
    tried = []
    for edge in edges:
        bm0 = m.bm
        m.bm = bm0.copy()
        m.uv = m.bm.loops.layers.uv.get("UVMap")
        refine(m, edge)
        t = tri_count(m.bm)
        tried.append((edge, t))
        if t <= tri_cap or edge == edges[-1]:
            bm0.free()
            break
        m.bm.free()
        m.bm = bm0
        m.uv = bm0.loops.layers.uv.get("UVMap")
    m.finish_normals()
    top = max(v.co.z for v in m.bm.verts)
    C.ray_ao(m, exclude_mats=("sign_atlas", "lamp_glass"), rays=rays, dist=ao_dist, floor=0.5, extra=wear_fn(ctx, top, grime, soot))
    mt = mats()
    ob = C.commit(m, name, [mt[n] for n in m.mats])
    ob.name = name
    path = os.path.join(OUT, name + ".glb")
    export(ob, path)
    if save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(GEN, "blends", name + ".blend"), copy=True, compress=True)
    me = ob.data
    bpy.data.objects.remove(ob)
    bpy.data.meshes.remove(me)
    an = VAL.analyze(path)
    rec = {"id": name, "glb": name + ".glb", "tris": an["tris"], "aabb": an["aabb"], "surfaces": [s["material"] for s in an["surfaces"]],
           "tris_by_surface": {s["material"]: s["tris"] for s in an["surfaces"]}, "glb_bytes": an["glb_bytes"], "problems": an["problems"],
           "textured_source": f"assets/generated/city_roadside/textured_exports/{name}.glb", "refine": tried[-1]}
    print("AK: %s tris=%d surfaces=%d aabb=%s..%s bytes=%d refine=%s problems=%d" % (name, rec["tris"], len(rec["surfaces"]), rec["aabb"]["min"], rec["aabb"]["max"], rec["glb_bytes"], rec["refine"], len(rec["problems"])))
    return rec


def new_ctx(name, w=10.0, d=10.0):
    c = P.Ctx(name, seed_of(name), w, d)
    # the family Ctx owns a Mesh over the canonical material list; keep that contract
    return c
