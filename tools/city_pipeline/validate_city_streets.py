"""Validate the street kit GLBs against street_kit_manifest.json (stdlib only). Exit 1 on any failure.

Reuses the approved workshop validator's decoders and per-GLB checks (bounds, grounding, COLOR_0, materials, no
cameras/lights/collision) at each model's own triangle cap, then adds: exact ID set, plain filename paths, no extras,
NORMAL decoding, plan dimensions, ordered semantic surfaces, minimum detail, provenance files and distinct GLBs.

Usage: python validate_city_streets.py [street_dir]
"""
import importlib.util
import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
# id -> (tri cap, plan size x/y/z in glTF metres, tolerance, minimum tris for "detailed, not a blockout")
SPECS = {
    "sidewalk_panel": (450, (6.0, 0.18, 4.0), 0.02, 200),
    "curb_segment": (180, (6.0, 0.22, 0.22), 0.02, 70),
    "drain_cover": (300, (1.2, 0.06, 0.7), 0.02, 140),
    "street_lamp": (1600, (0.6, 8.0, 3.7), 0.5, 500),
    "bollard": (300, (0.34, 1.1, 0.34), 0.1, 100),
    "bench_planter": (1800, (3.8, 1.5, 1.2), 0.05, 600),
    "refuse_station": (1800, (3.0, 2.2, 1.5), 0.05, 600),
    "alley_conduit": (1800, (8.0, 4.5, 1.0), 0.05, 600),
}
EXPECTED_IDS = tuple(SPECS)
MIN_VIEWS = 2

_spec = importlib.util.spec_from_file_location("validate_habitation_workshop", os.path.join(HERE, "validate_habitation_workshop.py"))
V = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(V)
errors = []


def err(m):
    errors.append(m)


def has_extras(js):
    def walk(o):
        if isinstance(o, dict):
            return "extras" in o or any(walk(v) for v in o.values())
        if isinstance(o, list):
            return any(walk(v) for v in o)
        return False
    return walk(js)


def check_normals(aid, js, binary):
    prims = [p for m in js["meshes"] for p in m["primitives"]]
    for p in prims:
        if "NORMAL" not in p["attributes"]:
            err(f"{aid}: primitive missing NORMAL")
            continue
        rows, _ = V.read_accessor(js, binary, p["attributes"]["NORMAL"], 3, "NORMAL")
        pos = js["accessors"][p["attributes"]["POSITION"]]["count"]
        if len(rows) != pos:
            err(f"{aid}: NORMAL count {len(rows)} != POSITION count {pos}")
        bad = sum(1 for r in rows if abs(math.sqrt(sum(c * c for c in r)) - 1.0) > 0.02)
        if bad:
            err(f"{aid}: {bad} NORMALs are not unit length")


def ordered_surfaces(js):
    """Material names in order of the first primitive that uses them."""
    out = []
    for p in (q for m in js["meshes"] for q in m["primitives"]):
        name = js["materials"][p["material"]].get("name", "") if "material" in p else ""
        if name and name not in out:
            out.append(name)
    return out


def check_entry(street, e):
    aid = e.get("id", "?")
    for key in ("id", "class", "glb", "tris", "tri_cap", "size", "aabb", "footprint", "front_setback_m", "surfaces", "reuse_worlds",
                "vertex_colors", "budget_note", "lod_strategy", "identity", "provenance"):
        if key not in e:
            err(f"{aid}: manifest entry missing {key}")
            return None
    if aid not in SPECS:
        err(f"{aid}: not a planned street asset")
        return None
    cap, size, tol, min_tris = SPECS[aid]
    g = e["glb"]
    if not isinstance(g, str) or g != os.path.basename(g) or "\\" in g or "/" in g or g != aid + ".glb":
        err(f"{aid}: glb must be the plain filename {aid}.glb relative to the manifest, got {g!r}")
        return None
    path = os.path.join(street, g)
    if not os.path.isfile(path):
        err(f"{aid}: {g} not found beside the manifest")
        return None
    if e["tri_cap"] != cap:
        err(f"{aid}: manifest tri_cap {e['tri_cap']} != planned cap {cap}")
    if "no mid" not in str(e["lod_strategy"]).lower() and "not yet" not in str(e["lod_strategy"]).lower():
        err(f"{aid}: lod_strategy must honestly state that no LODs exist yet")
    saved_cap, saved_errors = V.TRI_CAP, V.errors
    V.TRI_CAP, V.errors = cap, []
    try:
        tris, lo, hi, _ = V.check_glb(path, e)                   # decoders + bounds/grounding/COLOR_0/materials/no lights
        errors.extend(V.errors)
    except (OSError, ValueError, KeyError, struct.error) as ex:
        err(f"{aid}: unreadable GLB: {ex}")
        return None
    finally:
        V.TRI_CAP, V.errors = saved_cap, saved_errors
    js, binary = V.read_glb(path)
    if has_extras(js):
        err(f"{aid}: GLB carries extras (runtime metadata not allowed)")
    try:
        check_normals(aid, js, binary)
    except (ValueError, KeyError, struct.error) as ex:
        err(f"{aid}: unreadable NORMALs: {ex}")
    if tris < min_tris:
        err(f"{aid}: only {tris} triangles; expected a detailed model (>= {min_tris})")
    measured = [hi[i] - lo[i] for i in range(3)]
    for ax, got, want in zip("xyz", measured, size):
        if abs(got - want) > tol:
            err(f"{aid}: {ax} size {got:.3f} misses the plan {want} (tol {tol})")
    ms = e["size"]
    if any(abs(ms[ax] - got) > 2e-3 for ax, got in zip("xyz", measured)):
        err(f"{aid}: manifest size {ms} disagrees with GLB bounds {[round(v, 4) for v in measured]}")
    surfaces = ordered_surfaces(js)
    if e["surfaces"] != surfaces:
        err(f"{aid}: manifest surfaces {e['surfaces']} must equal the GLB's ordered surfaces {surfaces}")
    if lo[1] < -V.TOL or lo[1] > V.TOL:
        err(f"{aid}: not grounded")
    prov = e["provenance"]
    if not isinstance(prov, dict) or not all(k in prov for k in ("builder", "source_blend", "qa", "previews", "blender")):
        err(f"{aid}: provenance must list builder, blender, source_blend, qa and previews")
    else:
        for rel in [prov["source_blend"], prov["qa"], prov["builder"]]:
            if not os.path.isfile(os.path.join(ROOT, rel)):
                err(f"{aid}: provenance file {rel} is missing")
        views = [v for v in prov["previews"] if os.path.isfile(os.path.join(ROOT, v))]
        if len(views) < MIN_VIEWS:
            err(f"{aid}: needs >= {MIN_VIEWS} preview images, found {len(views)} of {len(prov['previews'])}")
    return tris


def main():
    street = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "godot", "assets", "city", "streets")
    try:
        with open(os.path.join(street, "street_kit_manifest.json"), encoding="utf-8") as f:
            manifest = json.load(f)
    except (OSError, ValueError) as ex:
        print(f"FAIL: cannot read manifest: {ex}")
        return 1
    if manifest.get("version") != 1:
        err("manifest must be version 1")
    ids = [a.get("id") for a in manifest.get("assets", [])]
    if ids != list(EXPECTED_IDS):
        err(f"manifest ids {ids} must be exactly {list(EXPECTED_IDS)} in that order")
    total = 0
    for e in manifest.get("assets", []):
        t = check_entry(street, e)
        if t:
            total += t
            print(f"{e['id']}: {t} tris")
    glbs = sorted(n for n in os.listdir(street) if n.endswith(".glb")) if os.path.isdir(street) else []
    if glbs != sorted(i + ".glb" for i in EXPECTED_IDS):
        err(f"GLBs on disk {glbs} do not match the expected set")
    blobs = set()
    for n in glbs:
        with open(os.path.join(street, n), "rb") as f:
            blobs.add(f.read())
    if len(blobs) != len(glbs):
        err("two street GLBs are byte-identical")
    for m in errors:
        print("FAIL:", m)
    print(f"street kit total {total} tris")
    print("PASS" if not errors else f"{len(errors)} failure(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
