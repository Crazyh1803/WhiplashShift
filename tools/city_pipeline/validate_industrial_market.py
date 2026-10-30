"""Validate the industrial market benchmark (stdlib only): decodes the real exported GLB vertices / normals / UVs / materials / embedded
textures and checks them against benchmark_manifest.json, the budgets, grounding, hand/bowl contact and placement/review-target safety.

Usage: python validate_industrial_market.py [candidate_dir]      Exit 1 on any failure.
"""
import hashlib
import json
import math
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_DIR = os.path.join(ROOT, "godot", "assets", "city", "candidates", "industrial_market")
ASSETS = ("redline_shop", "ramen_vendor", "ramen_customer")
BAD_EXT = ("KHR_lights", "KHR_physics", "OMI_", "KHR_xmp")
TOL = 2e-3
# person_tris was 18000 for the primitive figures; real adult base-human topology (face + hands + fitted garments) needs ~25-30k each (see manifest costs)
CAPS = {"shop_tris": 70000, "person_tris": 40000, "combined_tris": 120000, "combined_surfaces": 20, "texture_mib": 128.0}
FLOOR_TOP = 0.15
MIN_WEAR_SPREAD = 0.05     # real assets: COLOR_0 channel range over all non-emissive vertices
MIN_UV_SPAN = 0.05         # textured materials: TEXCOORD_0 must span at least this much in u or v
COUNTER_TOP = 1.20
errors = []
CT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def err(m):
    errors.append(m)


def safe_rel(p):
    return isinstance(p, str) and p != "" and not os.path.isabs(p) and ":" not in p and ".." not in p.replace("\\", "/").split("/") and not p.startswith(("/", "\\"))


def finite3(v):
    return isinstance(v, (list, tuple)) and len(v) == 3 and all(type(c) in (int, float) and math.isfinite(c) and abs(c) < 1000 for c in v)


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


def accessor(js, binary, ai, expect_type=None):
    a = js["accessors"][ai]
    if "sparse" in a or "bufferView" not in a:
        raise ValueError("sparse/absent accessor")
    code, size = CT[a["componentType"]]
    nc = NCOMP[a["type"]]
    if expect_type and a["type"] != expect_type:
        raise ValueError(f"accessor type {a['type']} != {expect_type}")
    bv = js["bufferViews"][a["bufferView"]]
    stride = bv.get("byteStride", size * nc)
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    cnt = a["count"]
    if start + stride * (cnt - 1) + size * nc > len(binary):
        raise ValueError("accessor outside BIN chunk")
    fmt = "<" + code * nc
    rows = [struct.unpack_from(fmt, binary, start + i * stride) for i in range(cnt)]
    if a.get("normalized") and a["componentType"] != 5126:
        div = {5121: 255.0, 5123: 65535.0, 5120: 127.0, 5122: 32767.0}[a["componentType"]]
        rows = [tuple(c / div for c in r) for r in rows]
    return rows


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


def png_info(blob):
    if blob[:8] != b"\x89PNG\r\n\x1a\n" or blob[12:16] != b"IHDR":
        raise ValueError("not a PNG")
    w, h = struct.unpack(">II", blob[16:24])
    return w, h


def image_blob(js, binary, glb_dir, im):
    if "bufferView" in im:
        bv = js["bufferViews"][im["bufferView"]]
        o = bv.get("byteOffset", 0)
        return binary[o:o + bv["byteLength"]]
    uri = im.get("uri", "")
    if not safe_rel(uri):
        raise ValueError(f"unsafe image uri {uri!r}")
    with open(os.path.join(glb_dir, uri), "rb") as f:
        return f.read()


def analyze(path):
    """Decode the GLB: triangles, world AABB, ordered surfaces, per-surface texture slots, embedded image sizes, vertex data."""
    js, binary = read_glb(path)
    info = {"js": js}
    for key in ("cameras", "animations", "skins"):
        if js.get(key):
            err(f"{os.path.basename(path)}: contains {key}")
    for ext in list(js.get("extensionsUsed", [])) + list(js.get("extensionsRequired", [])):
        if ext.startswith(BAD_EXT):
            err(f"{os.path.basename(path)}: forbidden extension {ext}")
    nodes = js["nodes"]
    mesh_nodes = []
    verts, tris, uv_bad, nrm_bad, tri_uv_total, tri_uv_degen = [], 0, 0, 0, 0, 0
    nrm_lens = []
    uv_min, uv_max = [1e9, 1e9], [-1e9, -1e9]
    tris_by_mat = {}
    degen_by_mat = {}
    lo, hi = [math.inf] * 3, [-math.inf] * 3
    color_spread = 0.0
    uv_span = {}                                            # textured material -> [umin, vmin, umax, vmax] of TEXCOORD_0
    ident = [[1 if i == j else 0 for j in range(4)] for i in range(4)]

    def walk(i, parent):
        nonlocal tris, uv_bad, nrm_bad, tri_uv_total, tri_uv_degen, color_spread
        n = nodes[i]
        name = n.get("name", "")
        if "camera" in n or "light" in n.get("extensions", {}).get("KHR_lights_punctual", {}):
            err(f"{os.path.basename(path)}: camera/light node {name}")
        if "collision" in name.lower() or name.lower().endswith(("-col", "-colonly")):
            err(f"{os.path.basename(path)}: collision node {name}")
        m = mat_mul(parent, node_matrix(n))
        if "mesh" in n:
            mesh_nodes.append(i)
            for p in js["meshes"][n["mesh"]]["primitives"]:
                at = p["attributes"]
                pos = accessor(js, binary, at["POSITION"], "VEC3")
                if "COLOR_0" not in at:
                    raise ValueError("primitive missing baked AO/wear COLOR_0")
                colors = accessor(js, binary, at["COLOR_0"])
                if len(colors) != len(pos) or any(len(row) not in (3, 4) or any(not math.isfinite(c) or not 0 <= c <= 1 for c in row) for row in colors):
                    raise ValueError("invalid baked AO/wear COLOR_0")
                mat_json = js["materials"][p["material"]] if "material" in p else {}
                mat_name = mat_json.get("name", "")
                if mat_name != "sign_emissive" and colors:
                    color_spread = max(color_spread, max(max(r[k] for r in colors) - min(r[k] for r in colors) for k in range(3)))
                if any(k.startswith("COLOR_") and k != "COLOR_0" for k in at):
                    raise ValueError("extra COLOR_n attribute: baked wear must be the only colour attribute, COLOR_0")
                if any(k.startswith("TEXCOORD_") and k != "TEXCOORD_0" for k in at):
                    raise ValueError("extra TEXCOORD_n attribute: mapped data must be the only UV set, TEXCOORD_0")
                if not all(math.isfinite(c) for c in (c for r in pos for c in r)):
                    raise ValueError("non-finite POSITION")
                if "NORMAL" not in at or "TEXCOORD_0" not in at:
                    err(f"{os.path.basename(path)}: primitive missing NORMAL/TEXCOORD_0")
                    continue
                nrm = accessor(js, binary, at["NORMAL"], "VEC3")
                uvs = accessor(js, binary, at["TEXCOORD_0"], "VEC2")
                if len(nrm) != len(pos) or len(uvs) != len(pos):
                    raise ValueError("attribute counts differ")
                for r in nrm:
                    ln = math.sqrt(r[0] ** 2 + r[1] ** 2 + r[2] ** 2)
                    nrm_lens.append(ln)
                    if not math.isfinite(ln) or abs(ln - 1) > 0.05:
                        nrm_bad += 1
                if uvs and any(mat_json.get(k) or mat_json.get("pbrMetallicRoughness", {}).get(k)
                               for k in ("normalTexture", "baseColorTexture", "metallicRoughnessTexture", "emissiveTexture", "occlusionTexture")):
                    span = uv_span.setdefault(mat_name, [1e9, 1e9, -1e9, -1e9])
                    span[0], span[1] = min(span[0], min(u for u, _ in uvs)), min(span[1], min(v for _, v in uvs))
                    span[2], span[3] = max(span[2], max(u for u, _ in uvs)), max(span[3], max(v for _, v in uvs))
                for u, v in uvs:
                    if not (math.isfinite(u) and math.isfinite(v)) or abs(u) > 1000 or abs(v) > 1000:
                        uv_bad += 1
                    uv_min[0], uv_min[1] = min(uv_min[0], u), min(uv_min[1], v)
                    uv_max[0], uv_max[1] = max(uv_max[0], u), max(uv_max[1], v)
                idx = [r[0] for r in accessor(js, binary, p["indices"], "SCALAR")] if "indices" in p else list(range(len(pos)))
                nt = len(idx) // 3 if p.get("mode", 4) == 4 else 0
                tris += nt
                mname = js["materials"][p["material"]].get("name", "") if "material" in p else ""
                tris_by_mat[mname] = tris_by_mat.get(mname, 0) + nt
                for k in range(nt):
                    a, b, c = idx[3 * k:3 * k + 3]
                    (u0, v0), (u1, v1), (u2, v2) = uvs[a], uvs[b], uvs[c]
                    tri_uv_total += 1
                    if abs((u1 - u0) * (v2 - v0) - (u2 - u0) * (v1 - v0)) < 1e-12:
                        tri_uv_degen += 1
                        degen_by_mat[mname] = degen_by_mat.get(mname, 0) + 1
                for cx, cy, cz in pos:
                    w = tuple(m[k][0] * cx + m[k][1] * cy + m[k][2] * cz + m[k][3] for k in range(3))
                    verts.append(w)
                    for k in range(3):
                        lo[k], hi[k] = min(lo[k], w[k]), max(hi[k], w[k])
        for c in n.get("children", []):
            walk(c, m)
    for r in js["scenes"][js.get("scene", 0)]["nodes"]:
        walk(r, ident)
    info.update(tris=tris, lo=lo, hi=hi, verts=verts, mesh_nodes=len(mesh_nodes), meshes=len(js["meshes"]), uv_bad=uv_bad, nrm_bad=nrm_bad,
                uv_degenerate=tri_uv_degen / max(tri_uv_total, 1), degen_by_mat=degen_by_mat, uv_range=(uv_min, uv_max), tris_by_mat=tris_by_mat,
                nrm_mean=sum(nrm_lens) / max(len(nrm_lens), 1),
                color_spread=color_spread,
                uv_span={n: (s[2] - s[0], s[3] - s[1]) for n, s in uv_span.items()})
    # materials: ordered by first use in primitives; texture slots and embedded images
    glb_dir = os.path.dirname(path)
    mats = []
    images = []
    for mi, mt in enumerate(js.get("materials", [])):
        pbr = mt.get("pbrMetallicRoughness", {})
        slots = {}
        for slot, ref in (("baseColor", pbr.get("baseColorTexture")), ("metallicRoughness", pbr.get("metallicRoughnessTexture")), ("normal", mt.get("normalTexture")),
                          ("emissive", mt.get("emissiveTexture")), ("occlusion", mt.get("occlusionTexture"))):
            if ref is None:
                continue
            if ref.get("texCoord", 0) != 0:
                raise ValueError(f"material {mt.get('name')} {slot} reads texCoord {ref['texCoord']}; Godot imports only TEXCOORD_0 for mapped data")
            tex = js["textures"][ref["index"]]
            im = js["images"][tex["source"]]
            try:
                blob = image_blob(js, binary, glb_dir, im)
                w, h = png_info(blob)
            except (ValueError, OSError) as e:
                err(f"{os.path.basename(path)}: material {mt.get('name')} {slot} image unreadable: {e}")
                continue
            slots[slot] = {"image": tex["source"], "width": w, "height": h, "mime": im.get("mimeType", "image/png"), "bytes": len(blob)}
            if tex["source"] not in [i["index"] for i in images]:
                images.append({"index": tex["source"], "width": w, "height": h, "bytes": len(blob)})
        mats.append({"name": mt.get("name", ""), "slots": slots, "emissive": mt.get("emissiveFactor", [0, 0, 0]),
                     "base": pbr.get("baseColorFactor", [1, 1, 1, 1])})
    info["materials"] = mats
    info["images"] = images
    return info


def tex_estimate(images):
    """RGBA8 + full mip chain, counted once per distinct image; x2 for the duplicated imported copy (source image + engine texture)."""
    one = sum(i["width"] * i["height"] * 4 * 4 / 3 for i in images)
    return one / 1048576.0, 2 * one / 1048576.0


def check_asset(aid, entry, cand):
    path = os.path.join(cand, entry.get("glb", ""))
    if not safe_rel(entry.get("glb")) or not os.path.isfile(path):
        err(f"{aid}: missing or unsafe glb path {entry.get('glb')!r}")
        return None
    try:
        info = analyze(path)
    except (ValueError, KeyError, OSError, struct.error) as e:
        err(f"{aid}: unreadable GLB: {e}")
        return None
    if info["mesh_nodes"] != 1 or info["meshes"] != 1:
        err(f"{aid}: expected one mesh node/mesh, found {info['mesh_nodes']}/{info['meshes']}")
    if info["tris"] != entry.get("tris"):
        err(f"{aid}: manifest tris {entry.get('tris')} != GLB {info['tris']}")
    lo, hi = info["lo"], info["hi"]
    for k in range(3):
        if abs(lo[k] - entry["aabb"]["min"][k]) > TOL or abs(hi[k] - entry["aabb"]["max"][k]) > TOL:
            err(f"{aid}: axis {k} GLB {lo[k]:.4f}..{hi[k]:.4f} != manifest {entry['aabb']['min'][k]}..{entry['aabb']['max'][k]}")
    if abs(lo[1]) > TOL:
        err(f"{aid}: not grounded, lowest y={lo[1]:.4f}")
    if info["uv_bad"] or info["nrm_bad"]:
        err(f"{aid}: {info['uv_bad']} bad UVs, {info['nrm_bad']} non-unit normals")
    if info["uv_degenerate"] > 0.08:
        err(f"{aid}: {info['uv_degenerate']:.1%} of triangles have degenerate UVs {info['degen_by_mat']}")
    if info["color_spread"] < MIN_WEAR_SPREAD:
        err(f"{aid}: COLOR_0 baked AO/wear is flat (spread {info['color_spread']:.3f} < {MIN_WEAR_SPREAD}) over the non-emissive surfaces")
    for mname, (du, dv) in info["uv_span"].items():
        if max(du, dv) < MIN_UV_SPAN:
            err(f"{aid}: material {mname} samples textures through a constant TEXCOORD_0 (span {du:.4f} x {dv:.4f})")
    names = [m["name"] for m in info["materials"]]
    if entry.get("surfaces") != names:
        err(f"{aid}: manifest surfaces {entry.get('surfaces')} != GLB materials {names}")
    textured = [m for m in info["materials"] if {"baseColor", "metallicRoughness", "normal"} <= set(m["slots"])]
    untextured = [m["name"] for m in info["materials"] if m not in textured]
    if aid != "redline_shop" and untextured:
        err(f"{aid}: people materials must carry albedo+ORM+normal textures; untextured: {untextured}")
    if aid == "redline_shop" and any(n not in ("sign_emissive",) for n in untextured):
        err(f"{aid}: untextured non-emissive materials {untextured}")
    for m in info["materials"]:
        if aid != "redline_shop" and any(c > 0 for c in m["emissive"]):
            err(f"{aid}: material {m['name']} has emissive {m['emissive']} (no self-glow fill on people)")
    if aid == "redline_shop" and not any(m["name"] == "sign_emissive" and max(m["emissive"]) > 0.3 for m in info["materials"]):
        err(f"{aid}: sign_emissive material missing or not emissive")
    shop_like = aid == "redline_shop"
    h = hi[1] - lo[1]
    if not shop_like and not (1.55 <= h <= 1.95):
        err(f"{aid}: implausible person height {h:.3f} m")
    if shop_like:
        w, d = hi[0] - lo[0], hi[2] - lo[2]
        if not (7.0 <= w <= 10.5 and 4.0 <= d <= 9.0 and 4.0 <= h <= 5.2):
            err(f"{aid}: shop size {w:.2f}x{d:.2f}x{h:.2f} outside the contract (~8 m wide, 4 m deep + sidewalk, 4-5 m tall)")
    est, est2 = tex_estimate(info["images"])
    if abs(est - entry.get("texture_mib_mips", -1)) > 0.05 * max(est, 1):
        err(f"{aid}: manifest texture_mib_mips {entry.get('texture_mib_mips')} != measured {est:.2f}")
    info["tex_mib"], info["tex_mib_dup"] = est, est2
    for im in info["images"]:
        if im["width"] > 2048 or im["height"] > 2048 or im["width"] < 128:
            err(f"{aid}: image {im} outside 128..2048")
    return info


def inside_box(p, lo, hi):
    return all(lo[k] < p[k] < hi[k] for k in range(3))


def place(p, pos, yaw_deg):
    """GLB (Y-up) point -> world: rotate about Y then translate."""
    a = math.radians(yaw_deg)
    c, s = math.cos(a), math.sin(a)
    return (p[0] * c + p[2] * s + pos[0], p[1] + pos[1], -p[0] * s + p[2] * c + pos[2])


def main():
    cand = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DIR
    try:
        with open(os.path.join(cand, "benchmark_manifest.json"), encoding="utf-8") as f:
            man = json.load(f)
    except (OSError, ValueError) as e:
        print(f"FAIL: cannot read benchmark_manifest.json: {e}")
        return 1
    if man.get("version") != 1 or man.get("status") != "candidate-review":
        err("manifest must have version 1 and status candidate-review")
    entries = {a.get("id"): a for a in man.get("assets", [])}
    if set(entries) != set(ASSETS):
        err(f"manifest assets {sorted(entries)} must be exactly {sorted(ASSETS)}")
    infos = {}
    for aid in ASSETS:
        if aid in entries:
            infos[aid] = check_asset(aid, entries[aid], cand)
            if not entries[aid].get("identity"):
                err(f"{aid}: missing identity")
            for t in entries[aid].get("source_textures", []):
                if not safe_rel(t) or not os.path.isfile(os.path.join(ROOT, t)):
                    err(f"{aid}: source texture {t!r} missing/unsafe")
    ok = all(infos.get(a) for a in ASSETS)
    # human base provenance: the retained source blend must exist, match its recorded checksum and the people must declare it
    hb = man.get("human_base", {})
    pv = hb.get("provenance")
    if not safe_rel(pv) or not os.path.isfile(os.path.join(ROOT, pv)):
        err("manifest human_base.provenance missing/unsafe")
    else:
        with open(os.path.join(ROOT, pv), encoding="utf-8") as fh:
            prov = json.load(fh)
        blend = os.path.join(os.path.dirname(os.path.join(ROOT, pv)), prov.get("retained_file", ""))
        if prov.get("license", "")[:5] != "CC0 1" or not prov.get("bundle_sha256") or not os.path.isfile(blend):
            err("human base provenance must record CC0 license, bundle checksum and the retained blend")
        elif hashlib.sha256(open(blend, "rb").read()).hexdigest() != prov.get("retained_sha256"):
            err("retained human base blend does not match its recorded sha256")
    for who in ("ramen_vendor", "ramen_customer"):
        if hb.get("bodies", {}).get(who) not in ("male", "female"):
            err(f"manifest human_base.bodies.{who} missing")
        sk = next((m for m in infos[who]["materials"] if m["name"] == "skin"), None) if infos.get(who) else None
        if infos.get(who) and (sk is None or sk["slots"].get("baseColor", {}).get("width", 0) < 1024):
            err(f"{who}: skin atlas must be at least 1024 px (faces need ~1500 px/m)")
    # budgets
    if ok:
        tt = {a: infos[a]["tris"] for a in ASSETS}
        if tt["redline_shop"] > CAPS["shop_tris"]:
            err(f"shop {tt['redline_shop']} tris > {CAPS['shop_tris']}")
        for a in ("ramen_vendor", "ramen_customer"):
            if tt[a] > CAPS["person_tris"]:
                err(f"{a} {tt[a]} tris > {CAPS['person_tris']}")
        if sum(tt.values()) > CAPS["combined_tris"]:
            err(f"combined {sum(tt.values())} tris > {CAPS['combined_tris']}")
        surf = sum(len(infos[a]["materials"]) for a in ASSETS)
        if surf > CAPS["combined_surfaces"]:
            err(f"combined surfaces {surf} > {CAPS['combined_surfaces']}")
        tex_total = sum(infos[a]["tex_mib_dup"] for a in ASSETS)
        if tex_total > CAPS["texture_mib"]:
            err(f"texture estimate {tex_total:.1f} MiB > {CAPS['texture_mib']}")
        est = man.get("costs", {})
        if abs(est.get("combined_tris", -1) - sum(tt.values())) > 0 or abs(est.get("texture_mib_working", -1) - tex_total) > 0.5:
            err("manifest costs disagree with decoded GLBs")
    # placements
    pls = {p.get("asset"): p for p in man.get("placements", [])}
    for aid in ASSETS:
        p = pls.get(aid)
        if not p or not finite3(p.get("position")) or type(p.get("yaw_degrees")) not in (int, float) or not math.isfinite(p["yaw_degrees"]):
            err(f"placement for {aid} missing or not finite")
    veh = man.get("vehicle_slot", {})
    if not finite3(veh.get("center")) or not (-10.5 <= veh["center"][2] <= -4.9) or abs(veh["center"][0]) > 8:
        err("vehicle_slot.center must be finite inside the reserved curb strip z -5..-10")
    rt = man.get("review_targets", {})
    for k in ("counter", "vendor_face", "customer_face", "support", "sign"):
        if not finite3(rt.get(k)):
            err(f"review_targets.{k} missing or not finite")
    mt = rt.get("materials")
    if not isinstance(mt, dict) or not mt or not all(finite3(v) for v in mt.values()):
        err("review_targets.materials must be a dict of finite points")
    anchors = man.get("lighting", {}).get("anchors", [])
    if not 1 <= len(anchors) <= 8:
        err("lighting.anchors must hold 1..8 entries")
    for a in anchors:
        if not finite3(a.get("position")) or not finite3(a.get("color")) or not all(0 <= c <= 1 for c in a.get("color", [])) \
                or not (a.get("energy", 0) > 0 and a.get("range", 0) > 0):
            err(f"bad lighting anchor {a}")
    # interaction + grounding in world space
    if ok and not errors:
        shop = pls["redline_shop"]
        for who in ("ramen_vendor", "ramen_customer"):
            pl = pls[who]
            pts = [place(v, pl["position"], pl["yaw_degrees"]) for v in infos[who]["verts"]]
            miny = min(p[1] for p in pts)
            if abs(miny - FLOOR_TOP) > 0.012:
                err(f"{who}: soles at y={miny:.3f}, floor top is {FLOOR_TOP}")
            # no body inside the counter carcass (x +-2.37, z -1.5..-2.0 in world, below the top plate)
            bad = sum(1 for p in pts if inside_box(p, (-2.36, FLOOR_TOP + 0.02, -2.0), (2.36, COUNTER_TOP - 0.045, -1.52)))
            if bad:
                err(f"{who}: {bad} vertices inside the counter carcass")
        bx, bz = man["interaction"]["bowl_center"][0], man["interaction"]["bowl_center"][2]
        by = man["interaction"]["bowl_center"][1]
        if abs(by - COUNTER_TOP) > 0.01:
            err("bowl is not on the counter top")
        ring = [(bx + 0.085 * math.cos(a * math.pi / 12), by + 0.045, bz + 0.085 * math.sin(a * math.pi / 12)) for a in range(24)]
        for who in ("ramen_vendor", "ramen_customer"):
            pl = pls[who]
            pts = [place(v, pl["position"], pl["yaw_degrees"]) for v in infos[who]["verts"]]
            near = min(math.dist(p, r) for r in ring for p in pts[::3])
            if near > 0.03:
                err(f"{who}: closest hand/body vertex is {near:.3f} m from the bowl wall (must be <= 0.03)")
        sx = infos["redline_shop"]
        for who in ("ramen_vendor", "ramen_customer"):
            pl = pls[who]["position"]
            if not (sx["lo"][0] < pl[0] < sx["hi"][0] and sx["lo"][2] < pl[2] < sx["hi"][2]):
                err(f"{who}: placement outside the shop/sidewalk footprint")
        cr = pls["ramen_customer"]["position"][2] - pls["ramen_vendor"]["position"][2]
        if cr > -0.5:
            err("customer must stand on the street side of the counter")
    for e in errors:
        print("FAIL:", e)
    if ok:
        for a in ASSETS:
            i = infos[a]
            print(f"{a}: {i['tris']} tris, {len(i['materials'])} surfaces, {len(i['images'])} images, "
                  f"bounds {[round(v, 3) for v in i['lo']]}..{[round(v, 3) for v in i['hi']]}, tex {i['tex_mib']:.1f} MiB (+dup {i['tex_mib_dup']:.1f})")
    print("PASS" if not errors else f"{len(errors)} failure(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
