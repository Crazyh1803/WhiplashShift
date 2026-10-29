"""Validate the neighbourhood candidate GLBs against neighborhood_manifest.json (stdlib only). Exit 1 on any failure.

Reuses the approved workshop validator's low-level decoders and per-GLB checks (bounds, grounding, COLOR_0, materials,
no cameras/lights/collision) at the 35k near-review cap, then adds manifest-level, path, ID-set and review-target checks.

Usage: python validate_city_neighborhood.py [neighborhood_candidate_dir]
"""
import importlib.util
import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
EXPECTED_IDS = ("market_habitat", "service_tenement", "freight_depot")
TRI_CAP = 35000
MIN_TRIS = 8000                                          # a "detailed" building, not a blockout
TARGETS = ("entry", "activity", "service")
MARGIN = 6.0                                             # review targets sit in the street/yard, just outside the AABB

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


def check_entry(cand, e):
    aid = e.get("id", "?")
    for key in ("id", "class", "glb", "tris", "aabb", "footprint", "front_setback_m", "surfaces", "reuse_worlds", "vertex_colors",
                "budget_note", "lod_strategy", "identity", "review_targets"):
        if key not in e:
            err(f"{aid}: manifest entry missing {key}")
            return
    g = e["glb"]
    if not isinstance(g, str) or g != os.path.basename(g) or "\\" in g or not g.endswith(".glb") or g != aid + ".glb":
        err(f"{aid}: glb must be the plain filename {aid}.glb relative to the manifest, got {g!r}")
        return
    path = os.path.join(cand, g)
    if not os.path.isfile(path):
        err(f"{aid}: {g} not found beside the manifest")
        return
    if not isinstance(e["lod_strategy"], str) or "not yet" not in e["lod_strategy"].lower() and "no mid" not in e["lod_strategy"].lower():
        err(f"{aid}: lod_strategy must honestly state that no LODs exist yet")
    saved_cap, saved_errors = V.TRI_CAP, V.errors
    V.TRI_CAP, V.errors = TRI_CAP, []
    try:
        tris, lo, hi, _ = V.check_glb(path, e)
        errors.extend(V.errors)
    except (OSError, ValueError, KeyError, struct.error) as ex:
        err(f"{aid}: unreadable GLB: {ex}")
        return
    finally:
        V.TRI_CAP, V.errors = saved_cap, saved_errors
    if tris < MIN_TRIS:
        err(f"{aid}: only {tris} triangles; expected a detailed building (>= {MIN_TRIS})")
    js, _b = V.read_glb(path)
    if has_extras(js):
        err(f"{aid}: GLB carries extras (runtime metadata not allowed)")
    if (hi[1] - lo[1]) < 6.0 or (hi[0] - lo[0]) < 6.0:
        err(f"{aid}: implausibly small building {[round(hi[i] - lo[i], 2) for i in range(3)]}")
    rt = e["review_targets"]
    if not isinstance(rt, dict) or any(t not in rt for t in TARGETS):
        err(f"{aid}: review_targets must contain {TARGETS}")
        return
    for t in TARGETS:
        p = rt[t]
        if not (isinstance(p, list) and len(p) == 3 and all(isinstance(v, (int, float)) and math.isfinite(v) for v in p)):
            err(f"{aid}: review target {t} must be a finite [x, y, z]")
            continue
        if p[1] < -0.01 or p[1] > hi[1] or not (lo[0] - MARGIN <= p[0] <= hi[0] + MARGIN and lo[2] - MARGIN <= p[2] <= hi[2] + MARGIN):
            err(f"{aid}: review target {t} {p} is outside the grounded model envelope")
    return tris


def main():
    cand = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "godot", "assets", "city", "candidates", "neighborhood")
    try:
        with open(os.path.join(cand, "neighborhood_manifest.json"), encoding="utf-8") as f:
            manifest = json.load(f)
    except (OSError, ValueError) as ex:
        print(f"FAIL: cannot read manifest: {ex}")
        return 1
    if manifest.get("version") != 1 or manifest.get("status") != "candidate-review":
        err("manifest must be version 1 with status candidate-review")
    ids = [a.get("id") for a in manifest.get("assets", [])]
    if sorted(ids) != sorted(EXPECTED_IDS) or len(set(ids)) != len(ids):
        err(f"manifest ids {ids} must be exactly {list(EXPECTED_IDS)}")
    sizes = {}
    for e in manifest.get("assets", []):
        t = check_entry(cand, e)
        if t:
            sizes[e["id"]] = t
            print(f"{e['id']}: {t} tris")
    glbs = sorted(n for n in os.listdir(cand) if n.endswith(".glb")) if os.path.isdir(cand) else []
    if glbs != sorted(i + ".glb" for i in EXPECTED_IDS):
        err(f"GLBs on disk {glbs} do not match the expected set")
    digests = set()
    for n in glbs:
        with open(os.path.join(cand, n), "rb") as f:
            digests.add(f.read())
    if len(digests) != len(glbs):
        err("two candidate GLBs are byte-identical")
    for m in errors:
        print("FAIL:", m)
    print("PASS" if not errors else f"{len(errors)} failure(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
