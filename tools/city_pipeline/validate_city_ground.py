"""Validator for the city ground kit (godot/assets/city/ground/). Decodes the exported GLBs and compares them with the manifest, the plan limits,
the retained textured sources and a fresh in-memory rebuild.   python validate_city_ground.py [--no-rebuild]   (or via ak-blender)
validate(root, rebuild) -> list of problem strings; empty means valid."""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import city_realism_bind as BIND  # noqa: E402
import validate_city_families as VAL  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
IDS = ("road_apron", "service_lane", "loading_yard", "utility_verge")
WIDTH = 16.1
DEPTH = {"road_apron": 3.8, "service_lane": 10.0, "loading_yard": 14.0, "utility_verge": 14.0}
TRI_CAP = {"road_apron": 24, "service_lane": 40, "loading_yard": 64, "utility_verge": 64}
MAX_SURFACES = 3
Y_MAX = 0.03
TOL = 0.002
LIB_MANIFEST = "godot/assets/city/realism/city_families_manifest.json"
ASSET_FIELDS = ("id", "glb", "tris", "aabb", "surfaces", "role", "footprint")


def _near(a, b, tol=TOL):
    return len(a) == len(b) and all(abs(x - y) <= tol for x, y in zip(a, b))


def check_glb(aid, path, lib, pr):
    """Geometry/materials of one runtime GLB against the plan limits. Returns the analysis dict."""
    an = VAL.analyze(path)
    pr += an["problems"]
    bb, d = an["aabb"], DEPTH[aid]
    if an["mesh_instances"] != 1:
        pr.append(f"{aid}: {an['mesh_instances']} mesh instances (want 1)")
    if an["tris"] > TRI_CAP[aid]:
        pr.append(f"{aid}: {an['tris']} tris exceeds cap {TRI_CAP[aid]}")
    if len(an["surfaces"]) > MAX_SURFACES:
        pr.append(f"{aid}: {len(an['surfaces'])} surfaces exceeds {MAX_SURFACES}")
    if not _near([bb["max"][0] - bb["min"][0], bb["max"][2] - bb["min"][2]], [WIDTH, d]):
        pr.append(f"{aid}: footprint {bb['max'][0] - bb['min'][0]:.4f} x {bb['max'][2] - bb['min'][2]:.4f} misses {WIDTH} x {d}")
    if abs(bb["min"][0] + bb["max"][0]) > TOL or abs(bb["min"][2] + bb["max"][2]) > TOL:
        pr.append(f"{aid}: footprint is not centred on XZ")
    if abs(bb["min"][1]) > 1e-4:
        pr.append(f"{aid}: foot at y={bb['min'][1]} (want 0)")
    if bb["max"][1] > Y_MAX + 1e-6:
        pr.append(f"{aid}: top at y={bb['max'][1]} above {Y_MAX}")
    if an["image_refs"] or an["image_count"]:
        pr.append(f"{aid}: runtime GLB carries images/textures {an['image_refs']}")
    for m in an["materials"]:
        if m["name"] not in lib:
            pr.append(f"{aid}: material {m['name']} is not a realism library material")
        if an["bindings"].get(m["name"]) != m["name"]:
            pr.append(f"{aid}: {m['name']} library_binding is {an['bindings'].get(m['name'])!r}")
    names = [s["material"] for s in an["surfaces"]]
    if len(set(names)) != len(names):
        pr.append(f"{aid}: duplicate surfaces {names}")
    if an["tangent_bad"]:
        pr.append(f"{aid}: {an['tangent_bad']} vertices with non-canonical TANGENT")
    allc = []
    for s in an["surfaces"]:
        if s["degenerate"]:
            pr.append(f"{aid}/{s['material']}: {s['degenerate']} degenerate triangles")
        if not s["has_tangent"] or not s["tangent_ok"]:
            pr.append(f"{aid}/{s['material']}: TANGENT missing or not unit length")
        if min(s["uv_max"][i] - s["uv_min"][i] for i in range(2)) < 0.1:
            pr.append(f"{aid}/{s['material']}: UV0 span too small {s['uv_min']}..{s['uv_max']}")
        allc += [s["color_min"], s["color_max"]]
    if max(c[k] for c in allc for k in range(3)) - min(c[k] for c in allc for k in range(3)) < 0.3:
        pr.append(f"{aid}: COLOR_0 shows no meaningful wear/paint variation")
    js, binary = BIND.read_glb(path)
    for mesh in js["meshes"]:
        for prim in mesh["primitives"]:
            pos = VAL.VIM.accessor(js, binary, prim["attributes"]["POSITION"], "VEC3")
            nrm = VAL.VIM.accessor(js, binary, prim["attributes"]["NORMAL"], "VEC3")
            idx = [r[0] for r in VAL.VIM.accessor(js, binary, prim["indices"], "SCALAR")]
            if any(n[1] < 0.99 for n in nrm):
                pr.append(f"{aid}: a vertex normal is not facing up")
            for t in range(0, len(idx), 3):
                a, b, c = (pos[i] for i in idx[t:t + 3])
                if (b[2] - a[2]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[2] - a[2]) <= 0:
                    pr.append(f"{aid}: a triangle faces down")
                    break
    return an


def check_textured(aid, root, runtime_path, pr):
    path = os.path.join(root, "assets", "generated", "city_ground", "textured_exports", aid + ".glb")
    if not os.path.isfile(path):
        pr.append(f"{aid}: textured source {path} is missing")
        return
    tjs, tbin = BIND.read_glb(path)
    rjs, rbin = BIND.read_glb(runtime_path)
    if tbin != rbin:
        pr.append(f"{aid}: textured source and runtime GLB binary geometry differ")
    for key in ("meshes", "accessors", "bufferViews", "nodes"):
        if tjs.get(key) != rjs.get(key):
            pr.append(f"{aid}: textured source differs from runtime in {key}")
    for im in tjs.get("images", []):
        uri = im.get("uri", "")
        if os.path.isabs(uri) or ":" in uri or "\\" in uri or not uri.startswith("../"):
            pr.append(f"{aid}: image uri {uri!r} is not a portable relative path")
        elif not os.path.isfile(os.path.normpath(os.path.join(os.path.dirname(path), uri))):
            pr.append(f"{aid}: image {uri} does not exist")
    for m in tjs["materials"]:
        for slot in ("baseColorTexture", "metallicRoughnessTexture"):
            if slot not in m.get("pbrMetallicRoughness", {}):
                pr.append(f"{aid}: textured {m['name']} misses {slot}")
        if "normalTexture" not in m:
            pr.append(f"{aid}: textured {m['name']} misses normalTexture")


def validate(root=ROOT, rebuild=True):
    pr = []
    gdir = os.path.join(root, "godot", "assets", "city", "ground")
    mpath = os.path.join(gdir, "city_ground_manifest.json")
    if not os.path.isfile(mpath):
        return [f"{mpath} is missing"]
    with open(mpath, encoding="utf-8") as f:
        man = json.load(f)
    with open(os.path.join(root, LIB_MANIFEST), encoding="utf-8") as f:
        lib = json.load(f)["materials"]
    if man.get("version") != 1:
        pr.append(f"manifest version {man.get('version')} (want 1)")
    sl = man.get("shared_library", {})
    if sl.get("manifest") != LIB_MANIFEST or not os.path.isfile(os.path.join(root, sl.get("manifest", "x"))):
        pr.append("shared_library.manifest does not point at the realism library manifest")
    ids = [a.get("id") for a in man.get("assets", [])]
    if ids != list(IDS):
        pr.append(f"manifest assets {ids} != {list(IDS)}")
    entries = {a["id"]: a for a in man.get("assets", [])}
    stray = [f for f in os.listdir(gdir) if f.lower().endswith((".png", ".jpg", ".ktx2", ".tres", ".tscn")) or f.endswith(".glb") and f[:-4] not in IDS]
    if stray:
        pr.append(f"unexpected files in ground dir: {stray}")
    for aid in IDS:
        e = entries.get(aid)
        path = os.path.join(gdir, aid + ".glb")
        if e is None or not os.path.isfile(path):
            pr.append(f"{aid}: manifest entry or GLB missing")
            continue
        for k in ASSET_FIELDS:
            if k not in e:
                pr.append(f"{aid}: manifest field {k} missing")
        an = check_glb(aid, path, lib, pr)
        if e.get("glb") != aid + ".glb":
            pr.append(f"{aid}: manifest glb {e.get('glb')}")
        if e.get("tris") != an["tris"]:
            pr.append(f"{aid}: manifest tris {e.get('tris')} != decoded {an['tris']}")
        if not (_near(e.get("aabb", {}).get("min", []), an["aabb"]["min"]) and _near(e.get("aabb", {}).get("max", []), an["aabb"]["max"])):
            pr.append(f"{aid}: manifest aabb {e.get('aabb')} != decoded {an['aabb']}")
        order = [s["material"] for s in an["surfaces"]]
        if e.get("surfaces") != order:
            pr.append(f"{aid}: manifest surfaces {e.get('surfaces')} != decoded {order}")
        fp = e.get("footprint", {})
        if not (_near(fp.get("min", []), [an["aabb"]["min"][0], an["aabb"]["min"][2]]) and _near(fp.get("max", []), [an["aabb"]["max"][0], an["aabb"]["max"][2]])):
            pr.append(f"{aid}: manifest footprint {fp} != decoded xz extent")
        if e.get("glb_bytes") != os.path.getsize(path):
            pr.append(f"{aid}: manifest glb_bytes is stale")
        check_textured(aid, root, path, pr)
        if rebuild:
            import build_city_ground as B
            rt, tx, _ = B.build_asset(aid)
            if rt != open(path, "rb").read():
                pr.append(f"{aid}: runtime GLB differs from a fresh rebuild")
            if tx != open(os.path.join(root, "assets", "generated", "city_ground", "textured_exports", aid + ".glb"), "rb").read():
                pr.append(f"{aid}: textured source differs from a fresh rebuild")
    return pr


def main():
    pr = validate(ROOT, "--no-rebuild" not in sys.argv)
    for p in pr:
        print("PROBLEM: " + p)
    print("AK: " + json.dumps({"validate_city_ground": "FAIL" if pr else "PASS", "problems": len(pr)}))
    if pr:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
