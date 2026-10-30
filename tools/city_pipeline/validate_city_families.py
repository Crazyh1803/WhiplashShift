"""Validate the city realism library (stdlib only): decodes every real GLB (positions, normals, tangents, UV0, COLOR_0, indices, materials,
texture references, node transforms) and checks them against godot/assets/city/realism/city_families_manifest.json (version 2), the frozen
caps in .ai/plans/city-realism-conversion.md, the shared PBR library on disk, LOD1 footprint equality, socket data and untouched legacy assets.

Usage: python validate_city_families.py [realism_dir]      Exit 1 on any failure.   `analyze(path)` is also used by build_city_families.py.
"""
import hashlib
import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import validate_industrial_market as VIM  # noqa: E402  (GLB container / accessor decoding only)

ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_DIR = os.path.join(ROOT, "godot", "assets", "city", "realism")
BUILDINGS = ("habitation_workshop", "market_habitat", "service_tenement", "freight_depot", "redline_shop", "row_workshop", "utility_substation", "transit_depot")
STREETS = ("sidewalk_panel", "curb_segment", "drain_cover", "street_lamp", "bollard", "bench_planter", "refuse_station", "alley_conduit")
EMISSIVE_WHITELIST = ("sign_atlas", "lamp_glass")
LIBRARY = ("steel_structure", "cladding_corrugated", "cladding_patch", "concrete", "brick", "render_plaster", "roof_membrane", "paving", "equipment_steel",
           "glass_window", "fabric_awning", "plastic_rubber", "sign_atlas", "lamp_glass")
CAPS = {"lod0_tris": 22000, "lod0_tris_redline": 25000, "lod1_tris": 2000, "lod1_surfaces": 3, "frontage": (12.0, 18.0, 24.0), "depth": 22.0, "height": 18.0,
        "materials": 14, "textures": 43, "tex_px": 512, "atlas_px": 1024, "street_tris": 3500, "global_unique_tris": 450000}
TOL = 0.02
errors = []


def err(m):
    errors.append(m)


def png_dims(path):
    with open(path, "rb") as f:
        return VIM.png_info(f.read(32))


def analyze(path):
    """Decode a GLB. Returns dict: tris, aabb, surfaces [{material, tris, uv_span, color_min/max, has_tangent, tex}], flags, node info."""
    js, binary = VIM.read_glb(path)
    name = os.path.basename(path)
    out = {"js": js, "problems": []}
    pr = out["problems"]
    for k in ("cameras", "animations", "skins"):
        if js.get(k):
            pr.append(f"{name}: contains {k}")
    for ext in list(js.get("extensionsUsed", [])) + list(js.get("extensionsRequired", [])):
        if ext.startswith(VIM.BAD_EXT) or "physics" in ext.lower():
            pr.append(f"{name}: forbidden extension {ext}")
    nodes = js.get("nodes", [])
    scene_nodes = js["scenes"][js.get("scene", 0)]["nodes"]
    ident = [[1 if i == j else 0 for j in range(4)] for i in range(4)]
    stack = [(n, ident) for n in scene_nodes]
    mesh_instances = []
    while stack:
        ni, parent = stack.pop()
        n = nodes[ni]
        for k in ("camera", "skin"):
            if k in n:
                pr.append(f"{name}: node uses {k}")
        if "extensions" in n and any("light" in e for e in n["extensions"]):
            pr.append(f"{name}: node carries a light")
        mtx = VIM.mat_mul(parent, VIM.node_matrix(n))
        if "mesh" in n:
            mesh_instances.append((n["mesh"], mtx))
        stack += [(c, mtx) for c in n.get("children", [])]
    out["mesh_instances"] = len(mesh_instances)
    lo, hi = [math.inf] * 3, [-math.inf] * 3
    surfaces = []
    tris_total = 0
    ncols = 0
    for mi, mtx in mesh_instances:
        for prim in js["meshes"][mi]["primitives"]:
            at = prim["attributes"]
            extra = [k for k in at if k.startswith(("TEXCOORD_", "COLOR_", "JOINTS_", "WEIGHTS_")) and k not in ("TEXCOORD_0", "COLOR_0")]
            if extra:
                pr.append(f"{name}: unexpected attributes {extra}")
            if "POSITION" not in at or "TEXCOORD_0" not in at or "COLOR_0" not in at or "NORMAL" not in at:
                pr.append(f"{name}: primitive misses POSITION/NORMAL/TEXCOORD_0/COLOR_0")
                continue
            if prim.get("mode", 4) != 4 or "indices" not in prim:
                pr.append(f"{name}: primitive is not indexed triangles")
                continue
            pos = VIM.accessor(js, binary, at["POSITION"], "VEC3")
            nrm = VIM.accessor(js, binary, at["NORMAL"], "VEC3")
            uv = VIM.accessor(js, binary, at["TEXCOORD_0"], "VEC2")
            col = VIM.accessor(js, binary, at["COLOR_0"])
            idx = [r[0] for r in VIM.accessor(js, binary, prim["indices"], "SCALAR")]
            n_v = len(pos)
            if not (len(nrm) == len(uv) == len(col) == n_v):
                pr.append(f"{name}: attribute counts differ")
                continue
            if max(idx) >= n_v or len(idx) % 3:
                pr.append(f"{name}: bad indices")
                continue
            tan = VIM.accessor(js, binary, at["TANGENT"], "VEC4") if "TANGENT" in at else None
            world = [tuple(sum(mtx[r][c] * (p[c] if c < 3 else 1) for c in range(4)) for r in range(3)) for p in pos]
            for w in world:
                if not all(math.isfinite(v) and abs(v) < 500 for v in w):
                    pr.append(f"{name}: non-finite vertex")
                    break
                for a in range(3):
                    lo[a] = min(lo[a], w[a])
                    hi[a] = max(hi[a], w[a])
            badn = sum(1 for nv in nrm if abs(math.sqrt(sum(c * c for c in nv)) - 1) > 0.02)
            if badn:
                pr.append(f"{name}: {badn} non-unit normals")
            degen = 0
            for t in range(0, len(idx), 3):
                a, b, c_ = world[idx[t]], world[idx[t + 1]], world[idx[t + 2]]
                ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
                vx, vy, vz = c_[0] - a[0], c_[1] - a[1], c_[2] - a[2]
                cx, cy, cz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
                if cx * cx + cy * cy + cz * cz < 1e-14:
                    degen += 1
            ntri = len(idx) // 3
            mat = js["materials"][prim["material"]] if "material" in prim else {}
            used = sorted(set(idx))
            uvs = [uv[i] for i in used]
            cols = [col[i] for i in used]
            surfaces.append({"material": mat.get("name"), "tris": ntri, "degenerate": degen, "vertices": len(used),
                             "uv_min": [min(u[0] for u in uvs), min(u[1] for u in uvs)], "uv_max": [max(u[0] for u in uvs), max(u[1] for u in uvs)],
                             "color_min": [min(c[k] for c in cols) for k in range(3)], "color_max": [max(c[k] for c in cols) for k in range(3)],
                             "color_mean": [sum(c[k] for c in cols) / len(cols) for k in range(3)],
                             "has_tangent": tan is not None, "tangent_ok": bool(tan) and all(abs(math.sqrt(sum(c * c for c in t4[:3])) - 1) < 0.05 and abs(abs(t4[3]) - 1) < 1e-3 for t4 in tan[:200]),
                             "material_index": prim.get("material")})
            tris_total += ntri
            ncols += 1
    out["tris"] = tris_total
    out["aabb"] = {"min": [round(v, 4) for v in lo], "max": [round(v, 4) for v in hi]}
    out["surfaces"] = surfaces
    mats = []
    for m in js.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        tex = {}
        for slot, tinfo in (("albedo", pbr.get("baseColorTexture")), ("orm", pbr.get("metallicRoughnessTexture")), ("normal", m.get("normalTexture")), ("emissive", m.get("emissiveTexture"))):
            if tinfo is None:
                continue
            if tinfo.get("texCoord", 0) != 0:
                pr.append(f"{name}: {m.get('name')} {slot} reads texCoord {tinfo['texCoord']}")
            t = js["textures"][tinfo["index"]]
            im = js["images"][t["source"]]
            tex[slot] = {"uri": im.get("uri"), "embedded": "bufferView" in im}
        mats.append({"name": m.get("name"), "tex": tex, "emissive_factor": m.get("emissiveFactor", [0, 0, 0]),
                     "base_factor": pbr.get("baseColorFactor", [1, 1, 1, 1]), "unlit": "KHR_materials_unlit" in m.get("extensions", {})})
    out["materials"] = mats
    out["image_count"] = len(js.get("images", []))
    out["glb_bytes"] = os.path.getsize(path)
    return out


def check_geometry(label, an, manifest_dir, lib):
    """Per-GLB checks independent of the manifest entry."""
    for p in an["problems"]:
        err(p)
    if an["mesh_instances"] != 1:
        err(f"{label}: expected exactly 1 mesh instance, found {an['mesh_instances']}")
    for s in an["surfaces"]:
        nm = s["material"]
        if nm not in lib:
            err(f"{label}: surface material {nm!r} is not in the shared library")
            continue
        if s["degenerate"] > max(2, s["tris"] * 0.01):
            err(f"{label}/{nm}: {s['degenerate']} degenerate triangles")
        span = (s["uv_max"][0] - s["uv_min"][0], s["uv_max"][1] - s["uv_min"][1])
        if max(span) < 0.05:
            err(f"{label}/{nm}: TEXCOORD_0 is constant/collapsed (span {span})")
        spread = max(s["color_max"][k] - s["color_min"][k] for k in range(3))
        if nm not in EMISSIVE_WHITELIST and s["tris"] > 40 and spread < 0.02:
            pass
        if lib[nm].get("normal") and not s["has_tangent"]:
            err(f"{label}/{nm}: no TANGENT attribute (normal-mapped surface)")
        elif s["has_tangent"] and not s["tangent_ok"]:
            err(f"{label}/{nm}: invalid tangents")
    # COLOR_0: asset-level wear must be real (not default white / one constant)
    cs = [s for s in an["surfaces"] if s["material"] not in EMISSIVE_WHITELIST]
    spread = max((max(s["color_max"][k] - s["color_min"][k] for k in range(3)) for s in cs), default=0)
    mean = sum(s["color_mean"][0] * s["tris"] for s in cs) / max(1, sum(s["tris"] for s in cs))
    if spread < 0.15:
        err(f"{label}: COLOR_0 wear range {spread:.3f} < 0.15 (default white / constant)")
    if mean > 0.97:
        err(f"{label}: COLOR_0 mean {mean:.3f} - looks like default white")
    for m in an["materials"]:
        if m["name"] not in lib:
            err(f"{label}: GLB material {m['name']!r} not in library")
            continue
        li = lib[m["name"]]
        for slot, t in m["tex"].items():
            if t["embedded"]:
                err(f"{label}/{m['name']}: {slot} is an embedded image (must be shared external)")
                continue
            want = li.get(slot)
            if want is None or t["uri"] != want:
                err(f"{label}/{m['name']}: {slot} uri {t['uri']!r} != library {want!r}")
        for slot in ("albedo", "orm", "normal"):
            if m["name"] != "lamp_glass" and not (m["name"] == "sign_atlas" and slot == "normal") and slot not in m["tex"]:
                err(f"{label}/{m['name']}: missing {slot} texture binding")
        if m["name"] == "sign_atlas" and "emissive" not in m["tex"]:
            err(f"{label}/sign_atlas: missing emissive texture binding (emission must be glyph-only)")
        emits = any(v > 1e-4 for v in m["emissive_factor"])
        if emits and m["name"] not in EMISSIVE_WHITELIST:
            err(f"{label}/{m['name']}: emissive on a non-whitelisted material")
        if m["name"] in EMISSIVE_WHITELIST and not emits:
            err(f"{label}/{m['name']}: whitelisted emissive material does not emit")
    if an["image_count"] and any(t["embedded"] for m in an["materials"] for t in m["tex"].values()):
        err(f"{label}: embedded images present")


def check_actor_sockets(aid, a, bb):
    """redline_shop must carry vendor/customer sockets for the approved benchmark actors: standing on one floor, 1.05 m below the counter top,
    facing each other (yaw 0 / 180), inside the lot, with a registered light anchor aimed at the hand-off."""
    sk = a.get("actor_sockets")
    if aid != "redline_shop":
        return
    if not sk:
        err(f"{aid}: actor_sockets missing")
        return
    pos = {}
    for who, yaw in (("vendor", 0.0), ("customer", 180.0)):
        s = sk.get(who) or {}
        p = s.get("position")
        if not isinstance(p, list) or len(p) != 3 or not all(isinstance(v, (int, float)) and math.isfinite(v) for v in p):
            err(f"{aid}: {who} socket position invalid")
            continue
        pos[who] = p
        if not isinstance(s.get("yaw_degrees"), (int, float)) or abs(((s["yaw_degrees"] - yaw + 180.0) % 360.0) - 180.0) > 1e-6:
            err(f"{aid}: {who} socket yaw {s.get('yaw_degrees')!r} != {yaw}")
        if s.get("actor") != "ramen_" + who:
            err(f"{aid}: {who} socket actor {s.get('actor')!r}")
        if not (bb["min"][0] <= p[0] <= bb["max"][0] and bb["min"][2] <= p[2] <= bb["max"][2]):
            err(f"{aid}: {who} socket outside the shop bounds")
    if len(pos) == 2:
        v, c = pos["vendor"], pos["customer"]
        if abs(v[1] - c[1]) > 1e-6 or not 0.1 <= v[1] <= 0.2:
            err(f"{aid}: vendor/customer feet not on one floor ({v[1]}, {c[1]})")
        if abs(sk.get("counter_top_y", 0) - sk.get("floor_y", 0) - 1.05) > 0.011 or abs(sk.get("floor_y", -1) - v[1]) > 1e-6:
            err(f"{aid}: counter top {sk.get('counter_top_y')} is not 1.05 m above the actor floor {sk.get('floor_y')}")
        if not (v[2] > c[2] and 0.7 <= v[2] - c[2] <= 1.3):
            err(f"{aid}: vendor must stand 0.7..1.3 m behind the customer ({v}, {c})")
        b = sk.get("bowl", [0, 0, 0])
        if not (v[2] > b[2] > c[2]) or abs(b[1] - sk.get("counter_top_y", -9)) > 1e-6 or not min(v[0], c[0]) - 0.3 <= b[0] <= max(v[0], c[0]) + 0.3:
            err(f"{aid}: bowl {b} is not on the counter between the actors")
    la = sk.get("light") or {}
    if la.get("id") not in [x.get("id") for x in a["light_anchors"]] or la not in a["light_anchors"]:
        err(f"{aid}: actor light is not a registered light anchor")


def load_manifest(d):
    p = os.path.join(d, "city_families_manifest.json")
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def aabb_close(a, b, tol=TOL):
    return all(abs(a["min"][i] - b["min"][i]) <= tol and abs(a["max"][i] - b["max"][i]) <= tol for i in range(3))


def validate(d=DEFAULT_DIR):
    man = load_manifest(d)
    if man.get("version") != 2:
        err("manifest version must be 2")
    lib = man.get("materials", {})
    if set(lib) != set(LIBRARY):
        err(f"library materials {sorted(lib)} != expected {sorted(LIBRARY)}")
    if len(lib) > CAPS["materials"]:
        err(f"{len(lib)} library materials > {CAPS['materials']}")
    if set(man.get("emission_whitelist", [])) != set(EMISSIVE_WHITELIST):
        err("emission_whitelist must be exactly sign_atlas, lamp_glass")
    # ---- texture library on disk
    seen = {}
    tex_bytes_mib = 0.0
    for name, m in lib.items():
        for slot in ("albedo", "orm", "normal", "emissive"):
            rel = m.get(slot)
            if rel is None:
                if slot in ("albedo", "orm") and name != "lamp_glass" or (slot == "normal" and name not in ("sign_atlas", "lamp_glass")):
                    err(f"library {name}: missing {slot}")
                continue
            if not VIM.safe_rel(rel):
                err(f"library {name}: unsafe path {rel!r}")
                continue
            p = os.path.join(d, rel)
            if not os.path.isfile(p):
                err(f"library {name}: {rel} missing")
                continue
            w, h = png_dims(p)
            lim = CAPS["atlas_px"] if name == "sign_atlas" and slot in ("albedo", "emissive") else CAPS["tex_px"]
            if w > lim or h > lim:
                err(f"{rel}: {w}x{h} exceeds {lim}")
            if rel in seen:
                err(f"{rel} shared by two library entries")
            seen[rel] = (w, h)
            tex_bytes_mib += w * h * 4 * (4 / 3) / 1048576
        if (name in EMISSIVE_WHITELIST) != bool(m.get("emission", {}).get("allowed")):
            err(f"library {name}: emission flag mismatch")
    if len(seen) > CAPS["textures"]:
        err(f"{len(seen)} unique texture images > {CAPS['textures']}")
    # ---- assets
    ids = [a["id"] for a in man.get("assets", [])]
    if sorted(ids) != sorted(BUILDINGS + STREETS):
        err(f"asset ids {sorted(ids)} do not match the contract")
    costs = {"buildings": {}, "streets": {}}
    unique_tris = 0
    surfaces_used = set()
    for a in man.get("assets", []):
        aid = a["id"]
        for k in ("id", "role", "glb", "tris", "aabb", "footprint", "entrances", "front_setback_m", "light_anchors", "materials", "surfaces"):
            if k not in a:
                err(f"{aid}: manifest key {k} missing")
        building = a.get("role") == "building"
        if building != (aid in BUILDINGS):
            err(f"{aid}: role {a.get('role')!r} wrong")
        for rel in ([a.get("glb")] + ([a.get("lod1_glb")] if building else [])):
            if not VIM.safe_rel(rel or ""):
                err(f"{aid}: unsafe path {rel!r}")
        glb = os.path.join(d, a.get("glb", "x"))
        if not os.path.isfile(glb):
            err(f"{aid}: {a.get('glb')} missing")
            continue
        an = analyze(glb)
        check_geometry(aid, an, d, lib)
        unique_tris += an["tris"]
        if an["tris"] != a["tris"]:
            err(f"{aid}: tris {an['tris']} != manifest {a['tris']}")
        if not aabb_close(an["aabb"], a["aabb"]):
            err(f"{aid}: aabb {an['aabb']} != manifest {a['aabb']}")
        order = [s["material"] for s in an["surfaces"]]
        if order != a["surfaces"] or sorted(set(order)) != sorted(a["materials"]):
            err(f"{aid}: surfaces/materials differ from the GLB ({order})")
        surfaces_used.update(order)
        bb = an["aabb"]
        if abs(bb["min"][1]) > 0.011:
            err(f"{aid}: foot not at y=0 ({bb['min'][1]})")
        fp = a["footprint"]
        if building:
            cap = CAPS["lod0_tris_redline"] if aid == "redline_shop" else CAPS["lod0_tris"]
            if an["tris"] > cap:
                err(f"{aid}: {an['tris']} tris > {cap}")
            fw = fp["max"][0] - fp["min"][0]
            fd = fp["max"][1] - fp["min"][1]
            if min(abs(fw - f) for f in CAPS["frontage"]) > 1e-6:
                err(f"{aid}: frontage {fw} not 12/18/24")
            if fd > CAPS["depth"] + 1e-6 or bb["max"][1] > CAPS["height"] + 1e-6:
                err(f"{aid}: depth {fd} / height {bb['max'][1]} over caps")
            if abs(fp["min"][1]) > 1e-6 or abs((fp["min"][0] + fp["max"][0]) / 2) > 1e-6:
                err(f"{aid}: footprint not front-centre anchored: {fp}")
            # AABB must contain the footprint and the declared protrusions must equal the measured excess
            pro = a.get("protrusions", {})
            meas = {"front": max(0.0, -bb["min"][2]), "left": max(0.0, fp["min"][0] - bb["min"][0]), "right": max(0.0, bb["max"][0] - fp["max"][0]),
                    "back": max(0.0, bb["max"][2] - fp["max"][1])}
            for k, v in meas.items():
                if abs(pro.get(k, -1) - v) > 0.011:
                    err(f"{aid}: protrusion {k} {pro.get(k)} != measured {v:.3f}")
            if a["front_setback_m"] + 1e-6 < meas["front"]:
                err(f"{aid}: front_setback_m {a['front_setback_m']} < front protrusion {meas['front']:.3f}")
            if max(meas.values()) > 4.0:
                err(f"{aid}: protrusion {max(meas.values()):.2f} m is unbounded for a lot reservation")
            # LOD1
            l1 = os.path.join(d, a.get("lod1_glb", "x"))
            if not os.path.isfile(l1):
                err(f"{aid}: lod1 missing")
            else:
                a1 = analyze(l1)
                check_geometry(aid + ".lod1", a1, d, lib)
                if a1["tris"] != a.get("lod1_tris") or a1["tris"] > CAPS["lod1_tris"]:
                    err(f"{aid}: lod1 tris {a1['tris']} (manifest {a.get('lod1_tris')}, cap {CAPS['lod1_tris']})")
                if not aabb_close(a1["aabb"], a.get("lod1_aabb", {"min": [9] * 3, "max": [9] * 3})):
                    err(f"{aid}: lod1_aabb mismatch")
                o1 = [s["material"] for s in a1["surfaces"]]
                if o1 != a.get("lod1_surfaces") or len(o1) > CAPS["lod1_surfaces"]:
                    err(f"{aid}: lod1 surfaces {o1} vs manifest {a.get('lod1_surfaces')} (max {CAPS['lod1_surfaces']})")
                b1 = a1["aabb"]
                if abs(b1["min"][0] - fp["min"][0]) > 0.5 or abs(b1["max"][0] - fp["max"][0]) > 0.5 or abs(b1["max"][2] - fp["max"][1]) > 0.7:
                    err(f"{aid}: lod1 footprint differs from lod0 ({b1} vs {fp})")
                if abs(b1["max"][1] - bb["max"][1]) > 2.6:
                    err(f"{aid}: lod1 height {b1['max'][1]} vs lod0 {bb['max'][1]}")
                if a1["tris"] * 4 > an["tris"]:
                    err(f"{aid}: lod1 is not a meaningful reduction")
                for s in (a1["surfaces"]):
                    pass
                costs["buildings"][aid] = {"lod0_tris": an["tris"], "lod1_tris": a1["tris"], "surfaces": len(order), "lod1_surfaces": len(o1), "glb_bytes": an["glb_bytes"], "lod1_glb_bytes": a1["glb_bytes"]}
            # identity / sockets
            if len(a["entrances"]) < 1:
                err(f"{aid}: no entrances")
            for e in a["entrances"]:
                x, y, z = e["position"]
                if not (fp["min"][0] - 0.01 <= x <= fp["max"][0] + 0.01) or not (-3.7 <= z <= fp["max"][1]):
                    err(f"{aid}: entrance {e.get('id')} outside the lot")
                if e["width"] <= 0.5 or e["height"] <= 1.8:
                    err(f"{aid}: entrance {e.get('id')} too small")
            if len(a.get("signs", [])) < 1:
                err(f"{aid}: no readable sign recorded")
        else:
            if an["tris"] > CAPS["street_tris"]:
                err(f"{aid}: {an['tris']} tris > {CAPS['street_tris']}")
            costs["streets"][aid] = {"tris": an["tris"], "surfaces": len(order), "glb_bytes": an["glb_bytes"]}
        pad = 0.5
        for la in a["light_anchors"]:
            p = la["position"]
            if not all(math.isfinite(v) for v in p) or not (bb["min"][0] - pad <= p[0] <= bb["max"][0] + pad and -0.01 <= p[1] <= bb["max"][1] + pad and bb["min"][2] - pad <= p[2] <= bb["max"][2] + pad):
                err(f"{aid}: light anchor {la.get('id')} outside the asset bounds")
            if la["kind"] not in ("street", "shop_spot", "fixture", "sign", "window", "service"):
                err(f"{aid}: light anchor kind {la['kind']}")
            if math.sqrt(sum(v * v for v in la["direction"])) < 0.5 or la["range_m"] <= 0:
                err(f"{aid}: light anchor {la.get('id')} direction/range")
        check_actor_sockets(aid, a, bb)
        if building and sum(1 for la in a["light_anchors"] if la["kind"] in ("street", "fixture")) < 1:
            err(f"{aid}: needs at least one street/fixture light anchor")
        for rel in a.get("source_blend", []) if isinstance(a.get("source_blend"), list) else [a.get("source_blend")]:
            if rel and not os.path.isfile(os.path.join(ROOT, rel)):
                err(f"{aid}: source {rel} missing")
        for rel in a.get("previews", []):
            if not os.path.isfile(os.path.join(ROOT, rel)):
                err(f"{aid}: preview {rel} missing")
    if surfaces_used - set(LIBRARY):
        err(f"surfaces outside the library: {surfaces_used - set(LIBRARY)}")
    for rel in man.get("lineup_previews", []):
        if not os.path.isfile(os.path.join(ROOT, rel)):
            err(f"lineup preview {rel} missing")
    if len(man.get("lineup_previews", [])) < 2:
        err("need the neutral and night lineup previews")
    if unique_tris > CAPS["global_unique_tris"]:
        err(f"unique source geometry {unique_tris} > {CAPS['global_unique_tris']}")
    # ---- legacy assets untouched
    for rel, sha in man.get("untouched", {}).items():
        p = os.path.join(ROOT, rel)
        if not os.path.isfile(p) or hashlib.sha256(open(p, "rb").read()).hexdigest() != sha:
            err(f"legacy file changed or missing: {rel}")
    if not man.get("untouched"):
        err("manifest does not record the untouched legacy hashes")
    # ---- recorded costs match
    c = man.get("costs", {})
    if abs(c.get("texture_mib_mips", -1) - tex_bytes_mib) > 0.05:
        err(f"texture MiB {c.get('texture_mib_mips')} != measured {tex_bytes_mib:.3f}")
    if c.get("unique_textures") != len(seen):
        err(f"unique_textures {c.get('unique_textures')} != {len(seen)}")
    if c.get("unique_geometry_tris") != unique_tris:
        err(f"unique_geometry_tris {c.get('unique_geometry_tris')} != {unique_tris}")
    return costs, tex_bytes_mib


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]       # works under python and `ak-blender script -- dir`
    d = argv[0] if argv and not argv[0].startswith("-") else DEFAULT_DIR
    costs, tmib = validate(d)
    # "AK: " prefix keeps the lines visible when run through the ak-blender wrapper (plain python prints them as well)
    if errors:
        for e in errors:
            print("AK: " + json.dumps({"FAIL": e}))
        print("AK: " + json.dumps({"problems": len(errors)}))
        sys.exit(1)
    print("AK: " + json.dumps({"city_realism": "OK", "textures_mib": round(tmib, 2), "costs": costs}))
