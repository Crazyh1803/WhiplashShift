"""Validate the City kit manifest and GLBs (stdlib only). Exit 1 on any failure."""
import json
import math
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KIT = os.environ.get("CITY_KIT_DIR") or os.path.join(ROOT, "godot", "assets", "city", "kit")
IDS = {
    "landmark": ["relay_tower", "exchange_hall", "pump_citadel"],
    "building": ["shutter_workshop", "utility_midrise", "ribbed_stack"],
    "prop": ["pipe_rack", "exhaust_stack", "service_cabinet", "transformer", "cargo_crate", "barrier_segment",
             "beacon_post", "conduit_pillar"],
}
MAX_TRIS = {"landmark": 18000, "building": 8000, "prop": 2000}
SEM = {"steel", "ceramic", "cavity", "machinery", "sinew", "glow_cyan", "glow_amber", "trim"}
GLOWS = {"glow_cyan", "glow_amber"}
WORLDS = {"city", "underworks", "foundry", "coldworks"}
KEYS = {"id", "class", "glb", "tris", "aabb", "footprint", "front_setback_m", "surfaces", "reuse_worlds", "budget_note"}
BAD_EXT = ("KHR_lights", "KHR_physics", "OMI_", "KHR_xmp", "MSFT_")
TOL = 2e-3
errors, warns = [], []


def err(m):
    errors.append(m)


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, ver, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or ver != 2 or length != len(data):
        raise ValueError("bad GLB header")
    off, js, binary = 12, None, b""
    while off < len(data):
        clen, ctype = struct.unpack_from("<I4s", data, off)
        if ctype == b"JSON":
            js = json.loads(data[off + 8:off + 8 + clen].decode("utf-8"))
        elif ctype == b"BIN\x00":
            binary = data[off + 8:off + 8 + clen]
        off += 8 + clen
    if js is None:
        raise ValueError("no JSON chunk")
    return js, binary


def node_matrix(n):
    if "matrix" in n:
        m = n["matrix"]
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    tx, ty, tz = n.get("translation", [0, 0, 0])
    qx, qy, qz, qw = n.get("rotation", [0, 0, 0, 1])
    sx, sy, sz = n.get("scale", [1, 1, 1])
    r = [[1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw)],
         [2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw)],
         [2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy)]]
    s = (sx, sy, sz)
    return [[r[i][j] * s[j] for j in range(3)] + [(tx, ty, tz)[i]] for i in range(3)] + [[0, 0, 0, 1]]


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def read_positions(js, binary, ai, aid):
    """Decode the real float32 VEC3 vertices of accessor ai and check them against the declared min/max."""
    a = js["accessors"][ai]
    if a.get("componentType") != 5126 or a.get("type") != "VEC3" or "sparse" in a or "bufferView" not in a:
        raise ValueError(f"POSITION accessor must be dense float32 VEC3")
    cnt = a.get("count")
    if not isinstance(cnt, int) or cnt <= 0:
        raise ValueError("bad POSITION count")
    bv = js["bufferViews"][a["bufferView"]]
    if bv.get("buffer", 0) != 0:
        raise ValueError("POSITION bufferView not in the GLB BIN buffer")
    stride = bv.get("byteStride", 12)
    start, bvo, bvl = a.get("byteOffset", 0), bv.get("byteOffset", 0), bv["byteLength"]
    if stride < 12 or stride % 4 or start % 4 or bvo % 4:
        raise ValueError("bad POSITION stride/alignment")
    if start + stride * (cnt - 1) + 12 > bvl or bvo + bvl > len(binary):
        raise ValueError("POSITION data outside bufferView/BIN chunk")
    base = bvo + start
    verts = [struct.unpack_from("<3f", binary, base + i * stride) for i in range(cnt)]
    if not all(math.isfinite(c) for v in verts for c in v):
        raise ValueError("non-finite vertex position")
    for k in range(3):
        vmin, vmax = min(v[k] for v in verts), max(v[k] for v in verts)
        if abs(vmin - a["min"][k]) > 1e-4 or abs(vmax - a["max"][k]) > 1e-4:
            raise ValueError(f"POSITION min/max axis {k} declared {a['min'][k]}..{a['max'][k]} but vertices {vmin}..{vmax}")
    return verts


def world_bounds(js, binary, aid):
    scene = js["scenes"][js.get("scene", 0)]
    nodes = js["nodes"]
    lo, hi = [math.inf] * 3, [-math.inf] * 3
    count = [0, 0]

    def walk(i, parent):
        n = nodes[i]
        m = mat_mul(parent, node_matrix(n))
        if "camera" in n:
            err(f"{aid}: camera node")
        if "mesh" in n:
            count[0] += 1
            for p in js["meshes"][n["mesh"]]["primitives"]:
                for cx, cy, cz in read_positions(js, binary, p["attributes"]["POSITION"], aid):
                    for k in range(3):
                        v = m[k][0] * cx + m[k][1] * cy + m[k][2] * cz + m[k][3]
                        lo[k], hi[k] = min(lo[k], v), max(hi[k], v)
        for c in n.get("children", []):
            walk(c, m)

    ident = [[1 if i == j else 0 for j in range(4)] for i in range(4)]
    for r in scene["nodes"]:
        walk(r, ident)
    return lo, hi, count[0]


def prim_tris(js, p):
    mode = p.get("mode", 4)
    n = js["accessors"][p["indices"]]["count"] if "indices" in p else js["accessors"][p["attributes"]["POSITION"]]["count"]
    return n // 3 if mode == 4 else max(0, n - 2) if mode in (5, 6) else 0


def check_glb(e):
    aid = e["id"]
    path = os.path.join(KIT, e["glb"])
    if not os.path.isfile(path):
        return err(f"{aid}: missing {e['glb']}")
    try:
        js, binary = read_glb(path)
    except Exception as ex:
        return err(f"{aid}: {ex}")
    for k in ("cameras", "animations", "skins", "images", "textures"):
        if js.get(k):
            err(f"{aid}: GLB has {k}")
    for x in list(js.get("extensionsUsed", [])) + list(js.get("extensionsRequired", [])):
        if x.startswith(BAD_EXT):
            err(f"{aid}: forbidden extension {x}")
    for n in js["nodes"]:
        if "extensions" in n:
            err(f"{aid}: node extensions {list(n['extensions'])}")
    meshes = js.get("meshes", [])
    if len(meshes) != 1:
        return err(f"{aid}: expected 1 mesh, got {len(meshes)}")
    prims = meshes[0]["primitives"]
    tris = sum(prim_tris(js, p) for p in prims)
    if any(p.get("mode", 4) != 4 for p in prims):
        err(f"{aid}: non-triangle primitive mode")
    if tris != e["tris"]:
        err(f"{aid}: manifest tris {e['tris']} != GLB {tris}")
    mats = [js["materials"][p["material"]] for p in prims if "material" in p]
    names = [m.get("name") for m in mats]
    if names != e["surfaces"]:
        err(f"{aid}: GLB materials {names} != manifest surfaces {e['surfaces']}")
    for m in mats:
        em = m.get("emissiveFactor", [0, 0, 0])
        if m.get("name") not in GLOWS and any(v > 1e-6 for v in em):
            err(f"{aid}: emission on non-glow surface {m.get('name')}")
        if m.get("name") in GLOWS:
            ok = len(em) == 3 and all(isinstance(v, (int, float)) and math.isfinite(v) and v >= 0 for v in em) and max(em) > 1e-3
            if not ok:
                err(f"{aid}: glow surface {m.get('name')} needs positive finite emissiveFactor, got {em}")
            st = m.get("extensions", {}).get("KHR_materials_emissive_strength", {}).get("emissiveStrength")
            if not isinstance(st, (int, float)) or abs(st - 2.0) > 1e-6:
                err(f"{aid}: glow surface {m.get('name')} needs KHR_materials_emissive_strength 2.0, got {st}")
        for t in ("emissiveTexture", "normalTexture", "occlusionTexture"):
            if t in m:
                err(f"{aid}: texture reference {t}")
        if "baseColorTexture" in m.get("pbrMetallicRoughness", {}):
            err(f"{aid}: baseColorTexture")
    try:
        lo, hi, nm = world_bounds(js, binary, aid)
    except (ValueError, KeyError, IndexError, struct.error) as ex:
        return err(f"{aid}: {ex}")
    if nm != 1:
        err(f"{aid}: {nm} mesh nodes")
    for k in range(3):
        if abs(lo[k] - e["aabb"]["min"][k]) > TOL or abs(hi[k] - e["aabb"]["max"][k]) > TOL:
            err(f"{aid}: aabb axis {k} manifest {e['aabb']['min'][k]}..{e['aabb']['max'][k]} vs GLB {lo[k]:.4f}..{hi[k]:.4f}")


def main():
    mp = os.path.join(KIT, "city_kit_manifest.json")
    if not os.path.isfile(mp):
        print("FAIL: manifest missing; run ak-blender tools/city_pipeline/build_city_kit.py")
        return 1
    man = json.load(open(mp, encoding="utf-8"))
    if set(man) != {"version", "assets"} or man["version"] != 1:
        err("manifest top-level must be {version:1, assets:[...]}")
    assets = man.get("assets", [])
    want = [i for v in IDS.values() for i in v]
    got = [a.get("id") for a in assets]
    if sorted(got) != sorted(want) or len(got) != len(set(got)):
        err(f"asset ids mismatch: {sorted(set(want) ^ set(got))}")
    total_surf = 0
    for e in assets:
        aid = e.get("id", "?")
        if set(e) != KEYS:
            err(f"{aid}: keys differ: {sorted(set(e) ^ KEYS)}")
            continue
        cls = e["class"]
        if aid not in IDS.get(cls, []):
            err(f"{aid}: wrong class {cls}")
            continue
        if e["glb"] != os.path.basename(e["glb"]) or not e["glb"].endswith(".glb"):
            err(f"{aid}: glb must be a filename")
        if e["tris"] > MAX_TRIS[cls]:
            err(f"{aid}: {e['tris']} tris over {MAX_TRIS[cls]}")
        surf = e["surfaces"]
        total_surf += len(surf)
        if not 1 <= len(surf) <= 8 or len(set(surf)) != len(surf) or not set(surf) <= SEM:
            err(f"{aid}: bad surfaces {surf}")
        if not e["reuse_worlds"] or not set(e["reuse_worlds"]) <= WORLDS:
            err(f"{aid}: bad reuse_worlds")
        if not e["budget_note"]:
            err(f"{aid}: empty budget_note")
        lo, hi = e["aabb"]["min"], e["aabb"]["max"]
        vals = lo + hi + e["footprint"]["min"] + e["footprint"]["max"] + [e["front_setback_m"]]
        if not all(isinstance(v, (int, float)) and math.isfinite(v) for v in vals):
            err(f"{aid}: non-finite numbers")
            continue
        if any(h <= l for l, h in zip(lo, hi)):
            err(f"{aid}: degenerate aabb")
        if abs(lo[1]) > 0.01:
            err(f"{aid}: minY {lo[1]} not ~0")
        fp = e["footprint"]
        if abs(fp["min"][0] - lo[0]) > TOL or abs(fp["max"][0] - hi[0]) > TOL or abs(fp["min"][1] - lo[2]) > TOL or abs(fp["max"][1] - hi[2]) > TOL:
            err(f"{aid}: footprint differs from aabb xz")
        if not 0 <= e["front_setback_m"] <= hi[2] - lo[2]:
            err(f"{aid}: front_setback_m out of range")
        floor = {"landmark": 8000, "building": 2000, "prop": 200}[cls]
        if e["tris"] < floor:
            warns.append(f"{aid}: {e['tris']} tris under target {floor}")
        check_glb(e)
    if total_surf > 64:
        err(f"total surfaces {total_surf} > 64")
    for w in warns:
        print("warn:", w)
    for m in errors:
        print("FAIL:", m)
    if errors:
        return 1
    print(f"city kit OK: {len(assets)} assets, {sum(a['tris'] for a in assets)} tris, {total_surf} surfaces")
    return 0


sys.exit(main())
