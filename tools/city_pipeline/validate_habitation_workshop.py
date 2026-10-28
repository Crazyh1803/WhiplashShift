"""Validate the habitation_workshop candidate GLB against its manifest (stdlib only). Exit 1 on any failure.

Usage: python validate_habitation_workshop.py [candidate_dir]
"""
import json
import math
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SEM = {"steel", "ceramic", "cavity", "machinery", "sinew", "glow_cyan", "glow_amber", "trim"}
TRI_CAP = 30000
TOL = 2e-3
BAD_EXT = ("KHR_lights", "KHR_physics", "OMI_", "KHR_xmp", "MSFT_")
errors = []


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


def read_accessor(js, binary, ai, comps, what):
    """Decode a dense float32 accessor with `comps` components per element (rows of tuples)."""
    a = js["accessors"][ai]
    ctype = a.get("componentType")
    # float32 always; COLOR_0 may also be normalised ubyte/ushort (5121/5123)
    codes = {5126: ("f", 4, 1.0), 5121: ("B", 1, 255.0), 5123: ("H", 2, 65535.0)}
    if ctype not in codes or (ctype != 5126 and not (what == "COLOR_0" and a.get("normalized"))) \
            or a.get("type") != {3: "VEC3", 4: "VEC4"}[comps] or "sparse" in a or "bufferView" not in a:
        raise ValueError(f"{what} accessor must be dense VEC{comps} (float32 or normalised int for COLOR_0)")
    code, csize, div = codes[ctype]
    cnt = a.get("count")
    if type(cnt) is not int or cnt <= 0:
        raise ValueError(f"bad {what} count")
    bv = js["bufferViews"][a["bufferView"]]
    size = csize * comps
    stride = bv.get("byteStride", size)
    start, bvo, bvl = a.get("byteOffset", 0), bv.get("byteOffset", 0), bv["byteLength"]
    if any(type(v) is not int or v < 0 for v in (stride, start, bvo, bvl)) or stride < size or stride % csize \
            or start % csize or bvo % csize:
        raise ValueError(f"bad {what} stride/offsets")
    if start + stride * (cnt - 1) + size > bvl or bvo + bvl > len(binary):
        raise ValueError(f"{what} data outside bufferView/BIN chunk")
    fmt = "<%d%s" % (comps, code)
    rows = [tuple(c / div for c in struct.unpack_from(fmt, binary, bvo + start + i * stride)) for i in range(cnt)]
    if not all(math.isfinite(c) for r in rows for c in r):
        raise ValueError(f"non-finite {what}")
    return rows, a


def read_positions(js, binary, ai):
    verts, a = read_accessor(js, binary, ai, 3, "POSITION")
    for bound in (a.get("min"), a.get("max")):
        if not isinstance(bound, list) or len(bound) != 3 or not all(type(v) in (int, float) for v in bound):
            raise ValueError("POSITION min/max must be numeric VEC3")
    for k in range(3):
        vmin, vmax = min(v[k] for v in verts), max(v[k] for v in verts)
        if abs(vmin - a["min"][k]) > 1e-4 or abs(vmax - a["max"][k]) > 1e-4:
            raise ValueError(f"POSITION min/max axis {k} declared {a['min'][k]}..{a['max'][k]} vs vertices {vmin}..{vmax}")
    return verts


def prim_tris(js, p):
    mode = p.get("mode", 4)
    acc = js["accessors"]
    n = acc[p["indices"]]["count"] if "indices" in p else acc[p["attributes"]["POSITION"]]["count"]
    return n // 3 if mode == 4 else max(0, n - 2) if mode in (5, 6) else 0


def check_glb(path, entry):
    js, binary = read_glb(path)
    aid = entry["id"]
    for key in ("cameras", "animations", "skins"):
        if js.get(key):
            err(f"{aid}: contains {key}")
    for ext in list(js.get("extensionsUsed", [])) + list(js.get("extensionsRequired", [])):
        if ext.startswith(BAD_EXT):
            err(f"{aid}: forbidden extension {ext} (lights/collision/physics)")
    nodes = js["nodes"]
    scene = js["scenes"][js.get("scene", 0)]
    lo, hi = [math.inf] * 3, [-math.inf] * 3
    mesh_nodes, tris, colour_rows, mats_used = [], 0, [], set()

    def walk(i, parent):
        nonlocal tris
        n = nodes[i]
        name = n.get("name", "")
        if "camera" in n or "light" in n.get("extensions", {}).get("KHR_lights_punctual", {}) or "light" in n:
            err(f"{aid}: camera/light node {name}")
        if "collision" in name.lower() or name.lower().endswith(("-col", "-colonly")):
            err(f"{aid}: collision node {name}")
        m = mat_mul(parent, node_matrix(n))
        if "mesh" in n:
            mesh_nodes.append(i)
            for p in js["meshes"][n["mesh"]]["primitives"]:
                tris += prim_tris(js, p)
                if "material" in p:
                    mats_used.add(js["materials"][p["material"]].get("name", ""))
                for cx, cy, cz in read_positions(js, binary, p["attributes"]["POSITION"]):
                    for k in range(3):
                        v = m[k][0] * cx + m[k][1] * cy + m[k][2] * cz + m[k][3]
                        lo[k], hi[k] = min(lo[k], v), max(hi[k], v)
                if "COLOR_0" not in p["attributes"]:
                    err(f"{aid}: primitive missing COLOR_0")
                else:
                    ca = js["accessors"][p["attributes"]["COLOR_0"]]
                    comps = 4 if ca.get("type") == "VEC4" else 3
                    rows, _ = read_accessor(js, binary, p["attributes"]["COLOR_0"], comps, "COLOR_0")
                    colour_rows.extend(rows)
        for c in n.get("children", []):
            walk(c, m)

    ident = [[1 if i == j else 0 for j in range(4)] for i in range(4)]
    for r in scene["nodes"]:
        walk(r, ident)

    if len(mesh_nodes) != 1 or len(js["meshes"]) != 1:
        err(f"{aid}: expected exactly one mesh node, found {len(mesh_nodes)} nodes / {len(js['meshes'])} meshes")
    if tris > TRI_CAP:
        err(f"{aid}: {tris} triangles exceeds cap {TRI_CAP}")
    if tris != entry["tris"]:
        err(f"{aid}: manifest tris {entry['tris']} but GLB has {tris}")
    surfaces = {m.get("name", "") for m in js.get("materials", [])}
    if len(surfaces) > 8 or not surfaces <= SEM:
        err(f"{aid}: materials {sorted(surfaces)} must be <=8 and within {sorted(SEM)}")
    if set(entry["surfaces"]) != surfaces or not mats_used <= surfaces:
        err(f"{aid}: manifest surfaces {entry['surfaces']} disagree with GLB materials {sorted(surfaces)}")

    # bounds vs manifest
    for k in range(3):
        if abs(lo[k] - entry["aabb"]["min"][k]) > TOL or abs(hi[k] - entry["aabb"]["max"][k]) > TOL:
            err(f"{aid}: axis {k} GLB {lo[k]:.4f}..{hi[k]:.4f} != manifest "
                f"{entry['aabb']['min'][k]}..{entry['aabb']['max'][k]}")
    fp = entry["footprint"]
    if abs(fp["min"][0] - lo[0]) > TOL or abs(fp["max"][0] - hi[0]) > TOL or abs(fp["min"][1] - lo[2]) > TOL \
            or abs(fp["max"][1] - hi[2]) > TOL:
        err(f"{aid}: footprint does not match GLB bounds")
    # grounded + centred origin
    if abs(lo[1]) > TOL:
        err(f"{aid}: not grounded, lowest point y={lo[1]:.4f}")
    if abs((lo[0] + hi[0]) / 2) > 0.05 or abs((lo[2] + hi[2]) / 2) > 0.05:
        err(f"{aid}: footprint centre ({(lo[0] + hi[0]) / 2:.3f}, {(lo[2] + hi[2]) / 2:.3f}) is not at the origin")
    sb = entry.get("front_setback_m")
    if not isinstance(sb, (int, float)) or sb <= 0 or sb > (hi[2] - lo[2]) / 2:
        err(f"{aid}: front_setback_m {sb!r} not a meaningful positive value")

    # vertex colour presence and variation
    if colour_rows:
        lum = [sum(r[:3]) / 3 for r in colour_rows]
        if min(min(r[:3]) for r in colour_rows) < 0 or max(max(r[:3]) for r in colour_rows) > 1.0001:
            err(f"{aid}: COLOR_0 outside 0..1")
        distinct = len({tuple(round(c, 2) for c in r[:3]) for r in colour_rows})
        if max(lum) - min(lum) < 0.2 or distinct < 50:
            err(f"{aid}: COLOR_0 has too little variation (range {max(lum) - min(lum):.3f}, {distinct} distinct)")
    return tris, lo, hi, len(colour_rows)


def main():
    cand = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "godot", "assets", "city", "candidates")
    mpath = os.path.join(cand, "habitation_workshop_manifest.json")
    try:
        with open(mpath, encoding="utf-8") as f:
            manifest = json.load(f)
    except (OSError, ValueError) as e:
        print(f"FAIL: cannot read manifest: {e}")
        return 1
    if manifest.get("status") != "candidate-review":
        err("manifest status must be candidate-review")
    assets = [a for a in manifest.get("assets", []) if a.get("id") == "habitation_workshop"]
    if len(assets) != 1:
        err("manifest must contain exactly one habitation_workshop asset")
    else:
        try:
            tris, lo, hi, nc = check_glb(os.path.join(cand, assets[0]["glb"]), assets[0])
            print(f"habitation_workshop: {tris} tris, {nc} colour corners, "
                  f"bounds {[round(v, 3) for v in lo]}..{[round(v, 3) for v in hi]}")
        except (OSError, ValueError, KeyError, struct.error) as e:
            err(f"habitation_workshop: unreadable GLB: {e}")
    for e in errors:
        print("FAIL:", e)
    print("PASS" if not errors else f"{len(errors)} failure(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
