"""Low-cost city ground kit: four flat 16.1 m wide pieces (road_apron, service_lane, loading_yard, utility_verge) for the street fabric between the
rail and the building frontages. Stdlib only, deterministic, idempotent:  python build_city_ground.py   (or  ak-blender tools/city_pipeline/build_city_ground.py)

Each piece is a handful of horizontal polygons layered a few millimetres apart (repaired concrete, dark bitumen/rubber patches, sealed cracks, paint marks,
wheel and pallet wear, restrained weeds). Detail comes from the shared realism material library (box-projected UV0 from the library's tiles per metre)
and from COLOR_0 (large-scale mottling, gutter grime, tints), not from geometry. Coordinates are glTF: metres, Y up, front faces -Z, XZ footprint centred,
foot at y=0 (only the recessed drain channels touch it).

Outputs
  godot/assets/city/ground/<id>.glb                                 geometry-only runtime GLB: named material stubs with extras.library_binding
  godot/assets/city/ground/city_ground_manifest.json                version 1
  assets/generated/city_ground/textured_exports/<id>.glb            full textured source, relative PNG URIs into the shared realism textures
  assets/generated/city_ground/build_records.json                   per-piece polygon counts and hashes
"""
import copy
import hashlib
import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import city_realism_bind as BIND  # noqa: E402
import validate_city_families as VAL  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
REAL = os.path.join(ROOT, "godot", "assets", "city", "realism")
OUT = os.path.join(ROOT, "godot", "assets", "city", "ground")
GEN = os.path.join(ROOT, "assets", "generated", "city_ground")
TEXTURED = os.path.join(GEN, "textured_exports")
PREVIEWS = os.path.join(ROOT, "assets", "previews", "city_ground")
LIB_MANIFEST = "godot/assets/city/realism/city_families_manifest.json"
LIB_TEXTURES = os.path.join(ROOT, "assets", "generated", "city_realism", "textures")
TEX_REL = "../../city_realism/textures/"       # from assets/generated/city_ground/textured_exports/

WIDTH = 16.1
HW = WIDTH / 2
MAX_Y = 0.03
SURFACE_CAP = 3
# id -> (depth, tri cap, district role, identity)
SPECS = {
    "road_apron": (3.8, 24, "roadside apron", "Repaired road shoulder between rail and sidewalk: a dark longitudinal drain channel, a black bitumen patch, a fresh bright slab, sealed cracks, broken yellow edge line and a tyre oil smear."),
    "service_lane": (10.0, 40, "back lane", "Worn service lane with a central drainage gutter, polished wheel tracks, paving and bitumen repairs, sealed cracks, faded edge dashes and weedy kerb edges."),
    "loading_yard": (14.0, 64, "loading yard", "Six settled concrete yard slabs on a dark sub-base with a drain channel, yellow bay dividers and stop bar, pedestrian lanes, pallet and forklift wear, oil, cracks and hazard hatching."),
    "utility_verge": (14.0, 64, "utility verge", "Gravel and soil utility verge with a drainage swale, steel cover plates in dark frames, a cable trench, stepping slabs, pale kerb strips, ruts and weed tufts."),
}
IDS = tuple(SPECS)
LIB_ORDER = ("steel_structure", "cladding_corrugated", "cladding_patch", "concrete", "brick", "render_plaster", "roof_membrane", "paving",
             "equipment_steel", "glass_window", "fabric_awning", "plastic_rubber", "sign_atlas", "lamp_glass")

# polygon layers (metres): base slabs, then each overlay at least 4 mm above the one it covers; max stays under MAX_Y
B0, L1, L2, L3, L4 = 0.010, 0.015, 0.020, 0.025, 0.030
SOIL, GREEN, DARK_SOIL, PALE = (0.78, 0.64, 0.5), (0.45, 0.72, 0.3), (0.34, 0.29, 0.24), (0.97, 0.93, 0.84)


def load_library():
    with open(os.path.join(ROOT, LIB_MANIFEST), encoding="utf-8") as f:
        return json.load(f)["materials"]


# ------------------------------------------------------------------------------------------------ polygon helpers
def rect(x0, x1, z0, z1):
    return [(x0, z0), (x0, z1), (x1, z1), (x1, z0)]


def rot(cx, cz, length, width, ang):
    """Rectangle of length x width centred on (cx, cz) turned by ang radians about Y (keeps the winding)."""
    c, s = math.cos(ang), math.sin(ang)
    return [(cx + px * c - pz * s, cz + px * s + pz * c) for px, pz in ((-length / 2, -width / 2), (-length / 2, width / 2), (length / 2, width / 2), (length / 2, -width / 2))]


def noise(x, z, k):
    return 0.5 + 0.28 * math.sin(x * 0.83 * k + z * 0.41 + 1.7) * math.cos(z * 1.17 * k - x * 0.29) + 0.22 * math.sin(x * 2.9 + k * 3.1) * math.sin(z * 2.3 - k)


def quad(mat, pts, y, tint=(1.0, 1.0, 1.0), light=0.9, amp=0.2, grime=()):
    """One horizontal polygon. COLOR_0 per corner = tint * (light + mottling) * gutter grime; paint and fresh slabs pass amp=0.06 and grime=()."""
    return {"mat": mat, "pts": pts, "y": y, "tint": tint, "light": light, "amp": amp, "grime": grime}


def corner_colour(q, x, z, k):
    b = q["light"] + q["amp"] * (noise(x, z, k) - 0.5) * 2
    for zc, width, strength in q["grime"]:
        b *= 1.0 - strength * math.exp(-abs(z - zc) / width)
    return tuple(max(0.04, min(1.0, c * b)) for c in q["tint"])


# ------------------------------------------------------------------------------------------------ piece layouts
def road_apron():
    g = ((-1.9, 0.5, 0.3),)                       # road-side grime (rail side is -Z)
    return [
        quad("concrete", rect(-HW, HW, -1.9, -1.45), B0, light=0.74, grime=g),
        quad("plastic_rubber", rect(-HW, HW, -1.45, -1.27), 0.0, light=0.85, amp=0.1),                      # longitudinal drain channel
        quad("concrete", rect(-HW, HW, -1.27, 1.9), B0, light=0.88, amp=0.2),
        quad("plastic_rubber", rot(-3.2, 0.35, 4.6, 1.9, 0.04), L1, light=0.9, amp=0.1),                      # black bitumen repair
        quad("concrete", rect(3.4, 7.6, -0.9, 1.5), L1, light=1.0, amp=0.07),                                 # fresh replacement slab
        quad("plastic_rubber", rot(0.8, -0.5, 5.0, 0.08, 0.05), L2, light=0.9, amp=0.1),                      # sealed crack
        quad("plastic_rubber", rect(0.0, 0.09, -1.27, 1.9), L2, light=0.9, amp=0.1),                          # expansion joint
        quad("cladding_patch", rect(-7.6, -4.6, -1.78, -1.64), L1, light=0.8, amp=0.18),                      # broken yellow edge line
        quad("cladding_patch", rect(-3.4, -0.4, -1.78, -1.64), L1, light=0.68, amp=0.18),
        quad("cladding_patch", rect(0.8, 3.8, -1.78, -1.64), L1, light=0.9, amp=0.12),
        quad("concrete", rect(-6.5, -2.0, -0.8, -0.25), L2, light=0.5, amp=0.12),                             # tyre oil smear
        quad("concrete", rot(5.6, 1.6, 2.4, 0.4, 0.03), L1, tint=GREEN, light=0.85, amp=0.15),               # weed fringe at the sidewalk edge
    ]


def service_lane():
    g = ((-5.0, 0.6, 0.25), (0.0, 0.5, 0.2), (5.0, 0.6, 0.25))
    q = [
        quad("concrete", rect(-HW, HW, -5.0, -0.14), B0, light=0.85, amp=0.18, grime=g),
        quad("plastic_rubber", rect(-HW, HW, -0.14, 0.14), 0.0, light=0.85, amp=0.1),                         # central drainage gutter
        quad("concrete", rect(-HW, HW, 0.14, 5.0), B0, light=0.88, amp=0.18, grime=g),
    ]
    for i, (z0, z1, lt) in enumerate(((-3.7, -3.1, 0.58), (-2.1, -1.5, 0.52), (1.5, 2.1, 0.55), (3.1, 3.7, 0.6))):     # polished wheel tracks
        q.append(quad("concrete", rect(-HW, HW, z0, z1), L1, light=lt, amp=0.14 + 0.02 * i))
    q += [
        quad("paving", rect(-5.2, -2.4, 0.8, 2.9), L2, light=0.95, amp=0.14),                                 # paving repairs
        quad("paving", rect(3.1, 5.9, -4.4, -2.6), L2, light=0.9, amp=0.14),
        quad("plastic_rubber", rot(-1.0, -2.6, 3.2, 0.07, 0.35), L3, light=0.9, amp=0.1),                     # sealed cracks
        quad("plastic_rubber", rot(1.8, 3.9, 2.6, 0.07, -0.4), L3, light=0.9, amp=0.1),
        quad("plastic_rubber", rot(6.6, 0.9, 1.8, 0.06, 0.8), L3, light=0.9, amp=0.1),
        quad("plastic_rubber", rect(3.0, 3.09, -5.0, 5.0), L3, light=0.9, amp=0.1),                           # expansion joint
    ]
    for x0, x1, z0, z1, lt in ((-7.2, -4.8, -4.65, -4.5, 0.82), (-0.8, 1.6, -4.65, -4.5, 0.72), (-4.0, -1.6, 4.5, 4.65, 0.78), (2.4, 4.8, 4.5, 4.65, 0.88)):
        q.append(quad("concrete", rect(x0, x1, z0, z1), L3, tint=(1.0, 0.97, 0.88), light=lt, amp=0.08))          # faded edge dashes
    q += [
        quad("concrete", rot(-6.4, 4.7, 3.0, 0.35, 0.02), L2, tint=GREEN, light=0.85, amp=0.15),              # weedy kerb edges
        quad("concrete", rot(5.9, -4.7, 2.4, 0.35, -0.03), L2, tint=GREEN, light=0.8, amp=0.15),
        quad("concrete", rect(-1.2, 1.0, -3.7, -3.1), L2, light=0.4, amp=0.1),                                # oil on the track
    ]
    return q


def loading_yard():
    edges = ((-7.0, 0.5, 0.25), (7.0, 0.5, 0.25))
    xs = ((-HW, -2.72), (-2.66, 2.66), (2.72, HW))
    zs = ((-7.0, -0.17), (0.17, 7.0))
    q = [
        quad("plastic_rubber", rect(-HW, HW, -7.0, -0.12), 0.006, light=0.8, amp=0.1),                        # sub-base shows through the joints
        quad("plastic_rubber", rect(-HW, HW, 0.12, 7.0), 0.006, light=0.8, amp=0.1),
        quad("plastic_rubber", rect(-HW, HW, -0.12, 0.12), 0.0, light=0.85, amp=0.1),                         # drain channel
    ]
    tops = (0.013, 0.016, 0.014, 0.015, 0.012, 0.016)
    lights = (0.78, 0.9, 0.82, 0.86, 0.72, 0.92)
    for r, (z0, z1) in enumerate(zs):
        for c, (x0, x1) in enumerate(xs):
            i = r * 3 + c
            q.append(quad("concrete", rect(x0, x1, z0, z1), tops[i], light=lights[i], amp=0.2, grime=edges))
    for x in (-4.0, 0.0, 4.0):                                                                               # bay dividers, stop bar, walkway lines
        q.append(quad("cladding_patch", rect(x - 0.07, x + 0.07, -6.6, -3.2), L2 + 0.001, light=0.82, amp=0.16))
    q += [
        quad("cladding_patch", rect(-6.0, 6.0, -3.2, -3.06), L2 + 0.001, light=0.7, amp=0.18),
        quad("cladding_patch", rect(-7.6, 7.6, 3.7, 3.84), L2 + 0.001, light=0.76, amp=0.16),
        quad("cladding_patch", rect(-7.6, 7.6, 5.4, 5.54), L2 + 0.001, light=0.66, amp=0.16),
    ]
    for cx, cz in ((-6.0, 5.6), (-4.7, 5.6), (5.5, 5.2), (6.8, 5.2)):                                         # pallet footprints
        q.append(quad("concrete", rect(cx - 0.6, cx + 0.6, cz - 0.4, cz + 0.4), L2, tint=(0.8, 0.66, 0.52), light=0.6, amp=0.12))
    q += [
        quad("concrete", rot(-2.0, 1.8, 5.0, 0.5, 0.25), L2, light=0.5, amp=0.12),                            # forklift turning scuffs
        quad("concrete", rot(3.4, -1.3, 4.0, 0.5, -0.3), L2, light=0.48, amp=0.12),
        quad("plastic_rubber", rot(-1.0, 3.0, 4.0, 0.06, 0.6), L3, light=0.9, amp=0.1),                       # sealed cracks
        quad("plastic_rubber", rot(4.6, -5.6, 2.8, 0.06, -0.5), L3, light=0.9, amp=0.1),
        quad("cladding_patch", rect(-8.0, -7.4, -6.6, -3.2), L2 + 0.001, light=0.74, amp=0.2),                # hazard hatching at the bay ends
        quad("cladding_patch", rect(7.4, 8.0, -6.6, -3.2), L2 + 0.001, light=0.78, amp=0.2),
        quad("concrete", rect(3.4, 5.6, 0.6, 2.2), L3, light=1.0, amp=0.06),                                  # fresh patch
        quad("concrete", rect(-0.8, 0.8, -2.35, -1.25), L2, light=0.42, amp=0.1),                             # oil
        quad("concrete", rect(-6.3, -4.7, 1.9, 2.9), L2, light=0.5, amp=0.1),
        quad("concrete", rect(-2.78, -2.58, -7.0, -5.4), L2, tint=GREEN, light=0.85, amp=0.15),               # weeds along the slab joints
        quad("concrete", rect(2.6, 2.8, 1.0, 3.0), L2, tint=GREEN, light=0.82, amp=0.15),
    ]
    return q


def utility_verge():
    q = [
        quad("concrete", rect(-HW, HW, -7.0, -2.2), B0 + 0.002, tint=SOIL, light=0.88, amp=0.2),               # gravel and soil
        quad("concrete", rect(-HW, HW, -2.2, -1.6), 0.0, tint=DARK_SOIL, light=0.8, amp=0.12),                 # drainage swale
        quad("concrete", rect(-HW, HW, -1.6, 7.0), B0 + 0.002, tint=SOIL, light=0.9, amp=0.2, grime=((-1.6, 0.4, 0.3),)),
    ]
    for i in range(6):                                                                                       # stepping slabs
        x0 = -7.4 + i * 2.6
        q.append(quad("paving", rect(x0, x0 + 2.2, 2.0, 3.3), L1 + 0.003, light=0.82 + 0.03 * (i % 3), amp=0.14))
    for cx in (-5.0, -1.3, 2.6, 6.0):                                                                        # dark frames, then steel cover plates
        q.append(quad("concrete", rect(cx - 0.75, cx + 0.75, -5.0, -4.0), L1 + 0.003, light=0.4, amp=0.1))
    for cx in (-5.0, -1.3, 2.6, 6.0):
        q.append(quad("equipment_steel", rect(cx - 0.6, cx + 0.6, -4.9, -4.1), L3 - 0.002, light=0.78 + 0.04 * (cx > 0), amp=0.12))
    q += [
        quad("concrete", rect(-HW, HW, -6.2, -5.95), L1 + 0.003, light=0.42, amp=0.1),                         # cable trench
        quad("concrete", rect(-3.4, 1.2, 3.9, 5.5), L1 + 0.003, tint=PALE, light=0.95, amp=0.08),             # fresh gravel patch
    ]
    for cx, cz, ln, ang in ((-6.5, 0.3, 1.4, 0.2), (-0.5, -0.8, 1.2, -0.3), (4.2, 0.9, 1.6, 0.15), (7.0, -1.0, 1.0, 0.4)):
        q.append(quad("concrete", rot(cx, cz, ln, 0.5, ang), L1 + 0.003, tint=GREEN, light=0.85, amp=0.15))    # weed tufts
    q += [
        quad("concrete", rect(-HW, -3.0, 5.6, 6.1), L1 + 0.003, tint=(0.7, 0.56, 0.42), light=0.6, amp=0.12),  # worn ruts
        quad("concrete", rect(1.0, HW, 5.6, 6.1), L1 + 0.003, tint=(0.7, 0.56, 0.42), light=0.62, amp=0.12),
        quad("concrete", rect(-HW, HW, 6.55, 6.95), L1 + 0.003, tint=PALE, light=0.88, amp=0.1),               # pale kerb strips
        quad("concrete", rect(-HW, HW, -6.95, -6.55), L1 + 0.003, tint=PALE, light=0.82, amp=0.1),
        quad("equipment_steel", rect(-0.9, 0.9, -2.25, -1.55), L2, light=0.7, amp=0.12),                       # culvert grates over the swale
        quad("equipment_steel", rect(5.0, 6.8, -2.25, -1.55), L2, light=0.7, amp=0.12),
    ]
    return q


LAYOUTS = {"road_apron": road_apron, "service_lane": service_lane, "loading_yard": loading_yard, "utility_verge": utility_verge}


# ------------------------------------------------------------------------------------------------ geometry -> glTF
def geometry(aid, lib):
    """Primitive arrays per material (library order), polygons triangulated as quads, centred on the XZ footprint, +Y normals, world-projected UV0."""
    depth = SPECS[aid][0]
    k = IDS.index(aid) + 1.0
    prims = {}
    for q in LAYOUTS[aid]():
        pts = q["pts"]
        area2 = sum(pts[i][0] * pts[(i + 1) % 4][1] - pts[(i + 1) % 4][0] * pts[i][1] for i in range(4))
        if area2 > 0:                                           # the (x, z) winding that gives +Y normals is clockwise in x/z
            pts = pts[::-1]
        p = prims.setdefault(q["mat"], {"pos": [], "uv": [], "col": [], "idx": []})
        base = len(p["pos"])
        upm = lib[q["mat"]]["uv_per_m"]
        for x, z in pts:
            p["pos"].append((round(x, 4), round(q["y"], 4), round(z, 4)))
            p["uv"].append((round(x * upm, 5), round(z * upm, 5)))
            p["col"].append(corner_colour(q, x, z, k))
        p["idx"] += [base, base + 1, base + 2, base, base + 2, base + 3]
    ordered = [(m, prims[m]) for m in LIB_ORDER if m in prims]
    xs = [v[0] for _, p in ordered for v in p["pos"]]
    zs = [v[2] for _, p in ordered for v in p["pos"]]
    if abs(min(xs) + HW) > 1e-4 or abs(max(xs) - HW) > 1e-4 or abs(min(zs) + depth / 2) > 1e-4 or abs(max(zs) - depth / 2) > 1e-4:
        raise SystemExit(f"{aid}: footprint x {min(xs)}..{max(xs)} z {min(zs)}..{max(zs)} misses {WIDTH} x {depth}")
    return ordered


def pad4(b):
    return b + b"\0" * ((4 - len(b) % 4) % 4)


def build_js(aid, ordered, lib, textured):
    """glTF dict and binary. textured=True: full library textures by relative URI (retained source); False is derived from it by strip_to_library."""
    binary = bytearray()
    views, accessors, prims_js = [], [], []

    def add(data, ctype, count, atype, target, bounds=False, normalized=False):
        while len(binary) % 4:
            binary.append(0)
        views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data), "target": target})
        binary.extend(data)
        a = {"bufferView": len(views) - 1, "componentType": ctype, "count": count, "type": atype}
        if normalized:
            a["normalized"] = True
        accessors.append(a)
        return len(accessors) - 1, a

    names = [m for m, _ in ordered]
    for mi, (mat, p) in enumerate(ordered):
        n = len(p["pos"])
        ai, acc = add(b"".join(struct.pack("<3f", *v) for v in p["pos"]), 5126, n, "VEC3", 34962)
        acc["min"] = [min(v[a] for v in p["pos"]) for a in range(3)]
        acc["max"] = [max(v[a] for v in p["pos"]) for a in range(3)]
        att = {"POSITION": ai}
        att["NORMAL"] = add(b"".join(struct.pack("<3f", 0.0, 1.0, 0.0) for _ in range(n)), 5126, n, "VEC3", 34962)[0]
        att["TEXCOORD_0"] = add(b"".join(struct.pack("<2f", *v) for v in p["uv"]), 5126, n, "VEC2", 34962)[0]
        att["COLOR_0"] = add(b"".join(struct.pack("<4H", *(int(round(c * 65535)) for c in v), 65535) for v in p["col"]), 5123, n, "VEC4", 34962, normalized=True)[0]
        idx = add(pad4(struct.pack(f"<{len(p['idx'])}H", *p["idx"])), 5123, len(p["idx"]), "SCALAR", 34963)
        accessors[idx[0]]["bufferView"] = idx[1]["bufferView"]
        views[idx[1]["bufferView"]]["byteLength"] = len(p["idx"]) * 2
        prims_js.append({"attributes": att, "indices": idx[0], "material": mi})
    materials, textures, images = [], [], []
    for mat in names:
        m = {"name": mat, "doubleSided": True, "pbrMetallicRoughness": {}}
        for slot, key in (("albedo", "baseColorTexture"), ("orm", "metallicRoughnessTexture"), ("normal", "normalTexture")):
            if slot not in lib[mat]:
                continue
            images.append({"name": f"{mat}_{slot}", "uri": f"textures/{mat}_{slot}.png", "mimeType": "image/png"})
            textures.append({"sampler": 0, "source": len(images) - 1})
            ref = {"index": len(textures) - 1}
            if slot == "normal":
                m["normalTexture"] = ref
            else:
                m["pbrMetallicRoughness"][key] = ref
        materials.append(m)
    js = {"asset": {"generator": "tools/city_pipeline/build_city_ground.py", "version": "2.0"}, "scene": 0, "scenes": [{"name": "Scene", "nodes": [0]}],
          "nodes": [{"mesh": 0, "name": aid}], "materials": materials, "meshes": [{"name": aid, "primitives": prims_js}],
          "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(binary)}]}
    if textures:
        js["textures"], js["images"] = textures, images
        js["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
    for (mi, pi), tans in VAL.compute_tangents(js, bytes(binary)).items():            # canonical TANGENT: bitangent follows increasing exported V
        a, v = add(b"".join(struct.pack("<4f", *t) for t in tans), 5126, len(tans), "VEC4", 34962)
        js["meshes"][mi]["primitives"][pi]["attributes"]["TANGENT"] = a
    js["buffers"] = [{"byteLength": len(pad4(bytes(binary)))}]
    return js, pad4(bytes(binary))


def build_asset(aid, lib=None):
    """-> (runtime GLB bytes, textured GLB bytes, record). Pure function of the layout code and the library manifest."""
    lib = lib or load_library()
    ordered = geometry(aid, lib)
    js, binary = build_js(aid, ordered, lib, True)
    textured = copy.deepcopy(js)
    for im in textured["images"]:
        im["uri"] = TEX_REL + os.path.basename(im["uri"])
    runtime = BIND.strip_to_library(copy.deepcopy(js))
    rt, tx = BIND.glb_bytes(runtime, binary), BIND.glb_bytes(textured, binary)
    rec = {"polygons": sum(len(p["idx"]) // 6 for _, p in ordered), "tris": sum(len(p["idx"]) // 3 for _, p in ordered), "surfaces": [m for m, _ in ordered],
           "runtime_sha256": hashlib.sha256(rt).hexdigest(), "textured_sha256": hashlib.sha256(tx).hexdigest()}
    return rt, tx, rec


def to_manifest(records, lib, analyses):
    assets = []
    for aid in IDS:
        depth, cap, role, ident = SPECS[aid]
        an = analyses[aid]
        bb = an["aabb"]
        assets.append({
            "id": aid, "role": "ground", "ground_role": role, "glb": aid + ".glb", "tris": an["tris"], "tri_cap": cap,
            "aabb": bb, "footprint": {"min": [-HW, -depth / 2], "max": [HW, depth / 2]}, "width_m": WIDTH, "depth_m": depth,
            "y_range_m": [bb["min"][1], bb["max"][1]], "surfaces": [s["material"] for s in an["surfaces"]], "surface_cap": SURFACE_CAP,
            "tris_by_surface": {s["material"]: s["tris"] for s in an["surfaces"]}, "polygons": records[aid]["polygons"], "identity": ident,
            "origin": "footprint centred on XZ, foot at y=0 (recessed drain channels only), front faces -Z; runs along X",
            "glb_bytes": an["glb_bytes"], "textured_source": f"assets/generated/city_ground/textured_exports/{aid}.glb",
            "vertex_color": "COLOR_0 multiplies albedo: large-scale mottling, gutter grime, paint and weed tints",
            "previews": ["assets/previews/city_ground/lineup_ground_neutral.png", "assets/previews/city_ground/lineup_ground_night.png"]})
    return {
        "version": 1, "status": "candidate-review",
        "coordinate_system": {"units": "metres", "up": "+Y", "front": "-Z", "origin": "XZ footprint centre, foot y=0", "width_m": WIDTH},
        "shared_library": {"manifest": LIB_MANIFEST, "base_dir": "godot/assets/city/realism/", "materials": sorted({m for a in assets for m in a["surfaces"]}),
                           "rule": "geometry-only GLBs: each material stub carries extras.library_binding equal to its exact name; load the shared library material by that name. No images, textures, samplers, lights or new material ids."},
        "limits": {"width_m": WIDTH, "depth_m": {a: SPECS[a][0] for a in IDS}, "tri_caps": {a: SPECS[a][1] for a in IDS}, "max_surfaces": SURFACE_CAP, "y_max_m": MAX_Y,
                   "uv": "TEXCOORD_0 world-projected (x, z) x library uv_per_m", "tangent": "canonical: bitangent follows increasing exported V"},
        "costs": {"tris": sum(a["tris"] for a in assets), "glb_bytes_total": sum(a["glb_bytes"] for a in assets)},
        "assets": assets}


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, indent=1)
        f.write("\n")


def main():
    lib = load_library()
    records, analyses = {}, {}
    for d in (OUT, TEXTURED):
        os.makedirs(d, exist_ok=True)
    for aid in IDS:
        rt, tx, rec = build_asset(aid, lib)
        with open(os.path.join(OUT, aid + ".glb"), "wb") as f:
            f.write(rt)
        with open(os.path.join(TEXTURED, aid + ".glb"), "wb") as f:
            f.write(tx)
        records[aid] = rec
        analyses[aid] = VAL.analyze(os.path.join(OUT, aid + ".glb"))
        if rec["tris"] > SPECS[aid][1] or len(rec["surfaces"]) > SURFACE_CAP:
            raise SystemExit(f"{aid}: {rec['tris']} tris / {len(rec['surfaces'])} surfaces exceed the caps")
    write_json(os.path.join(GEN, "build_records.json"), records)
    write_json(os.path.join(OUT, "city_ground_manifest.json"), to_manifest(records, lib, analyses))
    for aid in IDS:
        a = analyses[aid]
        print("AK: " + json.dumps({"ground": aid, "tris": a["tris"], "aabb": a["aabb"], "surfaces": [s["material"] for s in a["surfaces"]]}))


if __name__ == "__main__":
    main()
