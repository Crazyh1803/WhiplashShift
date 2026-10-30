"""Build the city realism library: shared PBR textures -> 8 building families (+LOD1) and 8 street pieces -> wear in COLOR_0 -> GLB with
shared EXTERNAL texture URIs -> version 2 manifest.   ak-blender tools/city_pipeline/build_city_families.py [-- --only a,b --skip-tex --manifest-only --fast]

Outputs: godot/assets/city/realism/{<id>.glb,<id>_lod1.glb,textures/*.png,city_families_manifest.json}; sources assets/generated/city_realism/
(textures, blends, build records). Blender Z-up, front +Y -> glTF Y-up, front -Z."""
import hashlib
import json
import math
import os
import shutil
import struct
import sys
import time

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
for _home in (os.environ.get("AK_HOME"), os.path.expanduser("~/agent-kit")):
    if _home and os.path.isdir(os.path.join(_home, "blender")):
        sys.path.insert(0, os.path.join(_home, "blender"))
from ak_util import args, report  # noqa: E402

import industrial_market_common as C  # noqa: E402
import city_realism_textures as T  # noqa: E402
import city_realism_parts as P  # noqa: E402
import city_realism_families as F  # noqa: E402
import city_realism_streets as S  # noqa: E402
import validate_city_families as VAL  # noqa: E402

V = Vector
ROOT = os.path.dirname(os.path.dirname(HERE))
REAL = os.path.join(ROOT, "godot", "assets", "city", "realism")
TEXG = os.path.join(REAL, "textures")
GEN = os.path.join(ROOT, "assets", "generated", "city_realism")
TEXS = os.path.join(GEN, "textures")
PREV = os.path.join(ROOT, "assets", "previews", "city_realism")

p = __import__("argparse").ArgumentParser()
p.add_argument("--only", default="")
p.add_argument("--skip-tex", action="store_true")
p.add_argument("--manifest-only", action="store_true")
p.add_argument("--fast", action="store_true", help="fewer AO rays (iteration only)")
A = args(p)
ONLY = set(x for x in A.only.split(",") if x)
for d in (REAL, TEXG, GEN, TEXS, PREV, os.path.join(GEN, "blends")):
    os.makedirs(d, exist_ok=True)

IDENTITY = {
    "habitation_workshop": ("housing+workshop", "Three storeys of patched render and brick housing over a four-bay steel-framed workshop floor: half-raised shutter, barred display window, bolted cladding repairs, balconies with laundry, roof tanks."),
    "market_habitat": ("market+housing", "Open market arcade on a steel colonnade with mixed canvas stall awnings, produce crates and bulb strings under two brick housing floors with laundry poles and roof tanks."),
    "service_tenement": ("housing+services", "Narrow five-storey brick tenement with an external steel fire stair, shop shutter and stair door, corbelled cornice, chimney stacks and roof tank."),
    "freight_depot": ("freight", "Corrugated portal-frame depot on a raised concrete dock: four dock doors at different heights, bumpers, levellers, cantilever canopy, office annex, ridge ventilator."),
    "redline_shop": ("market/food", "Lower-cost conversion of the approved Redline Ramen counter shop: H-column frame on plinths, header beam, cladding with repairs, red awning, counter, cooking hood and duct, flat above."),
    "row_workshop": ("workshops", "Row of four brick/clad workshop units under a sawtooth roof, each with its own shutter or doors, signs, stock and flues."),
    "utility_substation": ("utility", "Brick control building with blast door and louvres beside a fenced transformer yard: radiator-finned transformer with ribbed bushings, insulator gantry, cable tray, floodlight."),
    "transit_depot": ("transit", "Two-bay vehicle hall with raised grilles and hazard-striped thresholds beside a cantilever passenger shelter with bench, kiosk, timetable, stop pole and clock."),
    "sidewalk_panel": ("paving", "Six settled paving slabs, steel expansion strip, bolted service plate, tactile studs and a bright replacement patch."),
    "curb_segment": ("paving", "Kerb with steel edge angle, joints, gutter lip and worn no-parking paint."),
    "drain_cover": ("drainage", "Cast frame with parallel grate bars and lifting eyes over a dark sump."),
    "street_lamp": ("lighting", "7.9 m column on base plate and bolts with hand-hole cover, sleeve joint, banner bracket, cranked arm and lensed luminaire."),
    "bollard": ("protection", "Concrete-filled steel crash bollard on a bolted base plate with reflective band."),
    "bench_planter": ("street furniture", "Concrete planter with shrubs and a steel-framed slatted bench."),
    "refuse_station": ("services", "Steel mesh cage with three wheeled bins, hinged lids, hose bib and drip tray."),
    "alley_conduit": ("utility", "Alley-crossing steel gantry carrying conduit, pipes, junction boxes and a sagging cable."),
}
SEED = {k: sum(ord(ch) * (i + 7) for i, ch in enumerate(k)) for k in IDENTITY}
GABLE = {"freight_depot": (22.0, 8.0, 9.8, 12.4), "transit_depot": (22.0, 8.4, 10.6, 12.3)}   # depth, eave, ridge, half-width of the roof sheet


# ================================================================================================ textures / materials
def ensure_textures():
    if not A.skip_tex and not A.manifest_only:
        T.generate(TEXS)
    for f in os.listdir(TEXS):
        if f.endswith(".png"):
            shutil.copyfile(os.path.join(TEXS, f), os.path.join(TEXG, f))
    lib = {}
    for name in T.LIBRARY:
        e = {"uv_per_m": T.UV_PER_M.get(name, 1.0), "factors": {"base_color": list(T.FACTORS[name][0]), "roughness": T.FACTORS[name][1], "metallic": T.FACTORS[name][2]}}
        for slot in ("albedo", "orm", "normal", "emissive"):
            fn = f"{name}_{slot}.png"
            if os.path.isfile(os.path.join(TEXG, fn)):
                e[slot] = f"textures/{fn}"
        e["emission"] = {"allowed": name in T.EMISSIVE, "strength": T.EMISSIVE.get(name, 0.0), "source": "emissive texture (glyphs/icons only)" if name == "sign_atlas" else ("emissive factor" if name == "lamp_glass" else None)}
        lib[name] = e
    return lib


def lib_material(name, lib):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    base, rough, metal = T.FACTORS[name]
    b.inputs["Base Color"].default_value = (*base, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal

    def img(slot, nc):
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
    return m


# ================================================================================================ geometry finishing
def refine(mesh, max_edge):
    bm = mesh.bm
    for _ in range(6):
        edges = []
        for e in bm.edges:
            if e.calc_length() <= max_edge or not e.link_faces:
                continue
            if any(len(f.verts) > 4 or mesh.mats[f.material_index] in ("sign_atlas", "lamp_glass") or max(abs(f.normal.x), abs(f.normal.y), abs(f.normal.z)) < 0.998 for f in e.link_faces):
                continue                                   # n-gons, emissive faces and sloped/curved faces stay whole (partial subdivision leaves T-junction slivers)
            edges.append(e)
        if not edges:
            break
        bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True)


def tri_count(bm):
    return sum(len(f.verts) - 2 for f in bm.faces)


def wear_fn(ctx, top):
    drips, dirty, polish = ctx.drips, ctx.dirty, ctx.polish
    exp = math.exp

    def f(pt, n, mat):
        if mat in ("sign_atlas", "lamp_glass"):
            return (1.0, 1.0, 1.0)
        z = pt.z
        v = 0.97 * (1 - 0.34 * exp(-z / 0.5))                                        # ground splash / foot-traffic band
        v *= 0.94 + 0.06 * math.sin(pt.x * 0.63 + z * 0.29) * math.cos(pt.y * 0.47 + pt.x * 0.17)
        for (x, y, zt, w, s) in drips:                                               # rain streaks below joints, sills, outlets
            if zt - 2.4 < z < zt + 0.02 and abs(pt.y - y) < 1.0:
                v *= 1 - s * exp(-((pt.x - x) / w) ** 2) * (1 - (zt - z) / 2.4)
        for (x, y, zc, r, s) in dirty:                                               # oil / exhaust / splash around use points
            d2 = (pt.x - x) ** 2 + (pt.y - y) ** 2 + (z - zc) ** 2
            if d2 < r * r:
                v *= 1 - s * (1 - math.sqrt(d2) / r)
        for (x, y, zc, r) in polish:                                                 # hand-worn: door pulls stay clean and bright
            d2 = (pt.x - x) ** 2 + (pt.y - y) ** 2 + (z - zc) ** 2
            if d2 < r * r:
                v = min(1.0, v * 1.22)
        if z > top - 0.9:
            v *= 0.94                                                                 # sun-faded roofline
        rust = 0.93 if (z < 1.3 and mat in ("steel_structure", "cladding_corrugated", "equipment_steel")) else 1.0
        out = (v, v * 0.985, v * rust * 0.965)
        for (x, y, zc, r, rgb) in ctx.tints:                                           # foliage colour (no green library material)
            if (pt.x - x) ** 2 + (pt.y - y) ** 2 + (z - zc) ** 2 < r * r and mat == "render_plaster":
                out = (v * rgb[0], v * rgb[1], v * rgb[2])
        return out
    return f


def build_mesh(aid, builder, W, D, fast):
    ctx = P.Ctx(aid, SEED[aid], W, D)
    builder(ctx)
    m = ctx.m
    C.box_uv(m, T.UV_PER_M)
    return ctx


def finish_lod0(ctx, aid, tri_cap, rays):
    m = ctx.m
    tried = []
    for edge in (1.7, 2.4, 3.4, 5.0, 8.0, 99.0):
        bm0 = m.bm
        m.bm = bm0.copy()
        m.uv = m.bm.loops.layers.uv.get("UVMap")
        refine(m, edge)
        t = tri_count(m.bm)
        tried.append((edge, t))
        if t <= tri_cap or edge == 99.0:
            bm0.free()
            break
        m.bm.free()
        m.bm = bm0
        m.uv = bm0.loops.layers.uv.get("UVMap")
    m.finish_normals()
    bm = m.bm
    top = max(v.co.z for v in bm.verts)
    C.ray_ao(m, exclude_mats=("sign_atlas", "lamp_glass"), rays=4 if A.fast else rays, dist=0.9, floor=0.5, extra=wear_fn(ctx, top))
    return tried


def commit_export(m, name, mats, glb_path):
    ob = C.commit(m, name, [mats[n] for n in m.mats])
    ob.name = name
    export(ob, glb_path)
    if not name.endswith("_lod1"):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(GEN, "blends", name + ".blend"), copy=True, compress=True)
    me = ob.data
    bpy.data.objects.remove(ob)
    bpy.data.meshes.remove(me)


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


def externalize(path):
    """Rewrite the GLB so every image is a shared external URI (textures/<name>.png) and the embedded bytes are dropped."""
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
    for (pi_mesh, pi_prim), tans in extra_tangents.items():                       # append TANGENT (VEC4 float) accessors for normal-mapped primitives
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
    jb = json.dumps(js, separators=(",", ":")).encode("utf-8")
    jb += b" " * ((4 - len(jb) % 4) % 4)
    out = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(jb) + 8 + len(new_bin))
    out += struct.pack("<I4s", len(jb), b"JSON") + jb + struct.pack("<I4s", len(new_bin), b"BIN\x00") + bytes(new_bin)
    open(path, "wb").write(out)


# ================================================================================================ LOD1
def build_lod1(aid, W, D):
    spec = F.LOD1[aid]
    ctx = P.Ctx(aid + "_lod1", SEED[aid], W, D)
    m = ctx.m
    roles = dict(zip(("wall", "roof", "trim"), spec["mats"]))
    for (x0, x1, y0, y1, z0, z1, role) in spec["boxes"]:
        if aid in GABLE and role == "roof":
            continue
        P.bx(ctx, x0, x1, y0, y1, z0, z1, roles[role])
    if aid in GABLE:
        dd, eh, rh, hw = GABLE[aid]
        m.extrude_profile([(0.4, eh), (-dd / 2, rh), (-dd - 0.4, eh), (-dd - 0.4, eh - 0.3), (-dd / 2, rh - 0.3), (0.4, eh - 0.3)], -hw, hw, roles["roof"], plane="YZ")
    C.box_uv(m, T.UV_PER_M)
    return ctx


def finish_lod1(ctx):
    m = ctx.m
    refine(m, 4.5)
    m.finish_normals()
    top = max(v.co.z for v in m.bm.verts)
    C.ray_ao(m, exclude_mats=("sign_atlas", "lamp_glass"), rays=4, dist=1.5, floor=0.55, extra=wear_fn(ctx, top))


# ================================================================================================ manifest
def to_gltf(p):
    return [round(p[0], 4), round(p[2], 4), round(-p[1], 4)]


def sha(rel):
    return hashlib.sha256(open(os.path.join(ROOT, rel), "rb").read()).hexdigest()


def write_manifest(lib, recs):
    assets = []
    tris_total = 0
    for aid, rec in recs.items():
        building = aid in VAL.BUILDINGS
        an = VAL.analyze(os.path.join(REAL, aid + ".glb"))
        ctx_info = rec["ctx"]
        bb = an["aabb"]
        W, D = rec["W"], rec["D"]
        if building:
            fp = {"min": [-W / 2, 0.0], "max": [W / 2, D]}
        else:
            fp = {"min": [round(bb["min"][0], 4), round(bb["min"][2], 4)], "max": [round(bb["max"][0], 4), round(bb["max"][2], 4)]}
        order = [s["material"] for s in an["surfaces"]]
        e = {"id": aid, "role": "building" if building else "street", "district_role": IDENTITY[aid][0], "glb": aid + ".glb", "tris": an["tris"],
             "aabb": bb, "footprint": fp, "front_setback_m": 0.0, "materials": sorted(set(order)), "surfaces": order,
             "tris_by_surface": {s["material"]: s["tris"] for s in an["surfaces"]}, "identity": IDENTITY[aid][1],
             "origin": "front-centre foot: facade plane z=0, x centred, y=0 at ground; front faces -Z (back of the lot is +Z)" if building else "foot-centred: footprint centre at xz 0, base at y 0; front faces -Z",
             "glb_bytes": an["glb_bytes"]}
        if building:
            a1 = VAL.analyze(os.path.join(REAL, aid + "_lod1.glb"))
            pro = {"front": round(max(0.0, -bb["min"][2]), 3), "left": round(max(0.0, fp["min"][0] - bb["min"][0]), 3),
                   "right": round(max(0.0, bb["max"][0] - fp["max"][0]), 3), "back": round(max(0.0, bb["max"][2] - fp["max"][1]), 3)}
            e.update({"lod1_glb": aid + "_lod1.glb", "lod1_tris": a1["tris"], "lod1_aabb": a1["aabb"], "lod1_surfaces": [s["material"] for s in a1["surfaces"]],
                      "lod1_tris_by_surface": {s["material"]: s["tris"] for s in a1["surfaces"]}, "lod1_glb_bytes": a1["glb_bytes"], "protrusions": pro,
                      "frontage_m": W, "depth_m": D, "height_m": bb["max"][1]})
            e["front_setback_m"] = round(math.ceil((pro["front"] + 0.3) * 20) / 20, 2)
        else:
            e["front_setback_m"] = round(max(0.0, -bb["min"][2]), 4)
        e["entrances"] = [{"id": f"{aid}_entrance_{i}", "kind": en["kind"], "position": to_gltf(en["p"]), "width": round(en["width"], 3), "height": round(en["height"], 3)}
                          for i, en in enumerate(ctx_info["entrances"])]
        e["light_anchors"] = [{"id": f"{aid}_light_{i}", "kind": la["kind"], "position": to_gltf(la["p"]), "direction": [round(v, 3) for v in to_gltf(la["d"])],
                               "color": list(la["color"]), "range_m": la["range_m"], "energy": la["energy"], "shadow": la["shadow"]} for i, la in enumerate(ctx_info["anchors"])]
        e["signs"] = ctx_info["signs"]
        if ctx_info.get("sockets"):
            sk = ctx_info["sockets"]
            e["actor_sockets"] = {
                "meaning": "position = glTF coordinates of the point on the floor between the actor's feet (the actor GLB origin), in the shop's own frame; "
                           "yaw_degrees = rotation about +Y applied to the actor, same convention as benchmark_manifest placements (vendor 0 faces the street, customer 180 faces the counter)",
                "floor_y": round(sk["vendor"]["p"][2], 4), "counter_top_y": round(sk["bowl"][2], 4), "bowl": to_gltf(sk["bowl"]),
                "vendor": {"actor": sk["vendor"]["actor"], "glb": "godot/assets/city/candidates/industrial_market/" + sk["vendor"]["actor"] + ".glb",
                           "position": to_gltf(sk["vendor"]["p"]), "yaw_degrees": sk["vendor"]["yaw_degrees"]},
                "customer": {"actor": sk["customer"]["actor"], "glb": "godot/assets/city/candidates/industrial_market/" + sk["customer"]["actor"] + ".glb",
                             "position": to_gltf(sk["customer"]["p"]), "yaw_degrees": sk["customer"]["yaw_degrees"]},
                "light": e["light_anchors"][ctx_info["actor_light"]]}
        e["source_blend"] = f"assets/generated/city_realism/blends/{aid}.blend"
        e["previews"] = [f"assets/previews/city_realism/{f}" for f in sorted(os.listdir(PREV)) if f.startswith(aid + "_") and f.endswith(".png")] if os.path.isdir(PREV) else []
        e["wear"] = {"COLOR_0": "ray-cast AO x ground splash x rain streaks below joints/sills/outlets x oil/exhaust at use points x polished hand contacts x sun-faded roofline; emissive materials stay white",
                     "drip_sources": len(ctx_info["drips"]), "use_points": len(ctx_info["dirty"]), "polished_contacts": len(ctx_info["polish"])}
        e["build"] = {"refine_attempts": rec.get("tried"), "ao_rays": 4 if A.fast else 10}
        tris_total += an["tris"]
        assets.append(e)
    tex_mib = 0.0
    for m in lib.values():
        for slot in ("albedo", "orm", "normal", "emissive"):
            if slot in m:
                w, h = VAL.png_dims(os.path.join(REAL, m[slot]))
                tex_mib += w * h * 4 * (4 / 3) / 1048576
    n_tex = sum(1 for m in lib.values() for s in ("albedo", "orm", "normal", "emissive") if s in m)
    man = {
        "version": 2, "status": "candidate-review",
        "coordinate_system": {"units": "metres", "up": "+Y", "front": "-Z", "building_origin": "front-centre foot", "street_origin": "foot-centred", "blender_source": "Z-up, front +Y"},
        "texture_binding": {"mode": "shared external texture URIs", "base_dir": "godot/assets/city/realism/", "rule": "every GLB image is textures/<material>_<slot>.png; no embedded images; one Godot import per file, deduplicated by path",
                            "channels": {"albedo": "sRGB RGB", "orm": "R occlusion, G roughness, B metallic (glTF metallicRoughness uses G/B)", "normal": "OpenGL +Y tangent space, TANGENT exported",
                                         "emissive": "sRGB, sign_atlas only (glyphs and icons)"},
                            "vertex_color": "COLOR_0 multiplies albedo (AO x wear); TEXCOORD_0 is the only UV set", "uv_density": "tiles per metre in each material's uv_per_m (world-projected box UVs)"},
        "emission_whitelist": list(T.EMISSIVE),
        "sign_atlas": {"tile_px": [512, 128], "grid": [2, 8], "signs": [{"index": i, "text": s[0], "icon": s[1]} for i, s in enumerate(T.SIGNS)], "text_source": "ak-qwen draft, filtered to mundane words"},
        "materials": lib, "assets": assets,
        "costs": {"unique_geometry_tris": tris_total, "buildings_lod0_tris": sum(a["tris"] for a in assets if a["role"] == "building"),
                  "buildings_lod1_tris": sum(a["lod1_tris"] for a in assets if a["role"] == "building"), "streets_tris": sum(a["tris"] for a in assets if a["role"] == "street"),
                  "library_materials": len(lib), "unique_textures": n_tex, "texture_mib_mips": round(tex_mib, 4),
                  "texture_assumptions": "RGBA8 + full mip chain per distinct PNG, no VRAM compression, shared by path (one copy regardless of how many GLBs use it)",
                  "glb_bytes_total": sum(a["glb_bytes"] + a.get("lod1_glb_bytes", 0) for a in assets)},
        "untouched": {rel: sha(rel) for rel in ("godot/assets/city/candidates/industrial_market/redline_shop.glb", "godot/assets/city/candidates/industrial_market/ramen_vendor.glb",
                                                  "godot/assets/city/candidates/industrial_market/ramen_customer.glb", "godot/assets/city/candidates/industrial_market/benchmark_manifest.json",
                                                  "godot/assets/city/streets/street_kit_manifest.json", "godot/assets/city/kit/city_kit_manifest.json")},
        "lineup_previews": [f"assets/previews/city_realism/{f}" for f in ("lineup_buildings_neutral.png", "lineup_buildings_night.png", "lineup_buildings_b_neutral.png", "lineup_buildings_b_night.png", "lineup_streets_neutral.png", "lineup_streets_night.png") if os.path.isfile(os.path.join(PREV, f))],
        "limitations": ["procedural numpy textures, not photographic", "box-projected world UVs (no unwrapped islands), so repeats show on very large faces", "no interiors behind windows or bays beyond a dark hull",
                        "LOD1 is a massing proxy of walls, roof and trim only", "COLOR_0 wear is per vertex on faces refined to 1.7-8 m cells, finer grime comes from textures",
                        "signs use a 16-tile 1024 atlas; text is mundane filler"],
    }
    with open(os.path.join(REAL, "city_families_manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(man, fh, indent=1)
    return man


def load_records():
    p = os.path.join(GEN, "build_records.json")
    return json.load(open(p)) if os.path.isfile(p) else {}


def main():
    lib = ensure_textures()
    mats = {n: lib_material(n, lib) for n in T.LIBRARY}
    records = load_records()
    jobs = [(i, *F.BUILDERS[i], True) for i in VAL.BUILDINGS] + [(i, *S.STREETS[i], False) for i in VAL.STREETS]
    t_all = time.time()
    for aid, builder, W, D, building in jobs:
        if ONLY and aid not in ONLY:
            continue
        if A.manifest_only:
            continue
        t0 = time.time()
        ctx = build_mesh(aid, builder, W, D, A.fast)
        cap = 25000 if aid == "redline_shop" else 22000
        tried = finish_lod0(ctx, aid, cap - 300 if building else 3400, 10)
        tris = tri_count(ctx.m.bm)
        info = {"W": W, "D": D, "tried": tried, "tris_est": tris, "ctx": {"entrances": ctx.entrances, "anchors": ctx.anchors, "signs": ctx.signs, "sockets": ctx.sockets, "actor_light": ctx.actor_light, "drips": [list(d) for d in ctx.drips],
                                                                         "dirty": [list(d) for d in ctx.dirty], "polish": [list(d) for d in ctx.polish]}}
        glb = os.path.join(REAL, aid + ".glb")
        # keep the evaluated bmesh for the .blend copy, export first
        commit_export(ctx.m, aid, mats, glb)
        ctx.m.bm.free()
        t1 = time.time() - t0
        if building:
            c1 = build_lod1(aid, W, D)
            finish_lod1(c1)
            commit_export(c1.m, aid + "_lod1", mats, os.path.join(REAL, aid + "_lod1.glb"))
            c1.m.bm.free()
        records[aid] = info
        report(asset=aid, tris=tris, tried=tried, seconds=round(t1, 1), anchors=len(ctx.anchors), entrances=len(ctx.entrances))
    with open(os.path.join(GEN, "build_records.json"), "w", encoding="utf-8") as fh:
        json.dump(records, fh)
    ordered = {i: records[i] for i in list(VAL.BUILDINGS) + list(VAL.STREETS) if i in records}
    man = write_manifest(lib, ordered)
    report(manifest=True, assets=len(man["assets"]), costs=man["costs"], seconds=round(time.time() - t_all, 1))


main()
