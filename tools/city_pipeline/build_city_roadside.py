"""Roadside detail library: two landmark overlays, two detailed skyscrapers (+LOD1), board overlays per frontage family, four camps and two burning barrels.
    ak-blender tools/city_pipeline/build_city_roadside.py -- [--only id,id] [--fast]

Outputs: godot/assets/city/roadside/<id>.glb (geometry-only, library-bound) + roadside_manifest.json; sources in assets/generated/city_roadside/.
Nothing in godot/assets/city/{kit,realism}/ or any original source is written; the manifest records their hashes so tests can prove it."""
import json
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import city_roadside_common as R  # noqa: E402  (puts the agent-kit blender helpers on sys.path)
from ak_util import args  # noqa: E402

p = __import__("argparse").ArgumentParser()
p.add_argument("--only", default="")
p.add_argument("--fast", action="store_true")
A = args(p)
ONLY = set(x for x in A.only.split(",") if x)
RAYS = 4 if A.fast else 8

PROTECTED = ["godot/assets/city/kit/exchange_hall.glb", "godot/assets/city/kit/pump_citadel.glb", "godot/assets/city/kit/relay_tower.glb",
             "godot/assets/city/kit/city_kit_manifest.json", "godot/assets/city/realism/city_families_manifest.json",
             "godot/assets/city/realism/redline_shop.glb", "godot/assets/city/realism/habitation_workshop.glb", "godot/assets/city/realism/market_habitat.glb",
             "godot/assets/city/realism/service_tenement.glb", "godot/assets/city/realism/freight_depot.glb", "godot/assets/city/realism/row_workshop.glb",
             "godot/assets/city/realism/utility_substation.glb", "godot/assets/city/realism/transit_depot.glb",
             "godot/assets/city/candidates/industrial_market/ramen_vendor.glb", "godot/assets/city/candidates/industrial_market/ramen_customer.glb"]


def wanted(name):
    return not ONLY or name in ONLY


def reset():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)


def main():
    import city_roadside_dressing as D
    jobs = []
    for v in ("a", "b"):
        jobs.append(("barrel_fire_" + v, lambda v=v: D.barrel_fire(v), dict(tri_cap=2500, edges=(0.25, 0.5, 99.0), rays=RAYS, ao_dist=0.25), "barrel"))
    for v in ("a", "b", "c", "d"):
        jobs.append(("camp_" + v, lambda v=v: D.camp(v), dict(tri_cap=9000, edges=(0.6, 1.0, 99.0), rays=RAYS, ao_dist=0.5), "camp"))
    try:
        import city_roadside_towers as TW
        for v in ("a", "b"):
            jobs.append(("tower_" + v, lambda v=v: TW.tower(v, 0), dict(tri_cap=60000, rays=RAYS, ao_dist=0.9), "tower"))
            jobs.append(("tower_%s_lod1" % v, lambda v=v: TW.tower(v, 1), dict(tri_cap=9000, edges=(3.0, 6.0, 99.0), rays=RAYS, ao_dist=1.5), "tower_lod1"))
    except ImportError:
        pass
    try:
        import city_roadside_landmarks as LM
        for v in ("exchange_hall", "pump_citadel"):
            jobs.append((v + "_detail", lambda v=v: LM.landmark(v), dict(tri_cap=60000, rays=RAYS, ao_dist=0.9, edges=(1.2, 2.0, 3.4, 99.0)), "landmark"))
    except ImportError:
        pass
    try:
        import city_roadside_boards as BD
        for fam in BD.FAMILIES:
            jobs.append(("boards_" + fam, lambda fam=fam: BD.boards(fam), dict(tri_cap=16000, edges=(0.8, 1.5, 99.0), rays=RAYS, ao_dist=0.3), "boards"))
    except ImportError:
        pass
    path = os.path.join(R.OUT, "roadside_manifest.json")
    old = json.load(open(path, encoding="utf-8")) if os.path.isfile(path) else {"assets": {}}
    assets = old.get("assets", {})
    for name, build, kw, role in jobs:
        if not wanted(name):
            continue
        reset()
        ctx, extra = build()
        rec = R.finish(ctx, name, **kw)
        rec["role"] = role
        rec.update(extra)
        rec["entrances"] = [{"kind": e["kind"], "position": [round(e["p"][0], 3), round(e["p"][2], 3), round(-e["p"][1], 3)], "width": e["width"], "height": e["height"]} for e in ctx.entrances]
        assets[name] = rec
    manifest = {
        "version": 1, "status": "candidate-review",
        "coordinate_system": {"units": "metres", "up": "+Y", "front": "-Z", "blender_source": "Z-up, front +Y"},
        "binding": "geometry-only GLBs; every material is a stub named after the city realism library entry (extras.library_binding) and replaced from godot/assets/city/realism/city_families_manifest.json",
        "protected_sources": {rel: R.sha256(os.path.join(R.ROOT, rel)) for rel in PROTECTED if os.path.isfile(os.path.join(R.ROOT, rel))},
        "assets": assets,
    }
    problems = sorted(p_ for a in assets.values() for p_ in a["problems"])
    manifest["problems"] = problems
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1)
    print("AK: manifest assets=%d tris=%d problems=%d" % (len(assets), sum(a["tris"] for a in assets.values()), len(problems)))
    for p_ in problems:
        print("AK: PROBLEM", p_)


main()
