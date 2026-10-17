"""Build the Boilerfang 88 steam-punk speedster / off-road truck blueprint model.

Run headlessly: ak-blender tools/vehicle_pipeline/blender/build_boilerfang.py
Optional args after `--`: --no-renders, --no-export, --views=<a,b,...> (render only those QA views).
Other vehicles' files are never touched. Deterministic: rebuilding gives identical geometry.
"""
import json
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import boilerfang_body as B  # noqa: E402
import boilerfang_core as C  # noqa: E402
import boilerfang_export as X  # noqa: E402
import boilerfang_trace as T  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
BLUEPRINT = ROOT / "tools/vehicle_pipeline/references/steam-punk.jpg"
MODEL_DIR = ROOT / "godot/assets/vehicles/models/boilerfang"
BLEND = HERE / "boilerfang_blueprint.blend"
STEM = "boilerfang_blueprint"
VIEWS = next((a.split("=", 1)[1].split(",") for a in argv if a.startswith("--views=")), None)


def modules():
    mods = {}
    for name in ("wheels", "machinery", "cab", "details"):
        try:
            mods[name] = __import__(f"boilerfang_{name}")
        except ModuleNotFoundError:
            mods[name] = None
    return mods


def main():
    cols = C.reset_scene()
    mats = C.build_materials()
    builder = C.Builder(cols, mats)
    mods = modules()
    hull = B.build_hull(builder)
    B.build_barrel(builder)
    B.build_fenders(builder)
    B.build_plows(builder)
    bpy.context.view_layer.update()
    for name in ("cab", "machinery", "details", "wheels"):
        mod = mods.get(name)
        if mod is not None:
            mod.build(builder, hull)
            print(f"AK: stage {name} objects={len(cols['BOILERFANG_SOURCE'].objects)}", flush=True)
    print("AK: source triangles", C.triangle_count(list(cols["BOILERFANG_SOURCE"].objects)), flush=True)
    X.finalize_scene(cols, hull, BLUEPRINT)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    result = {"blend": str(BLEND.relative_to(ROOT))}
    if "--no-export" not in argv:
        result.update(X.export_all(cols, MODEL_DIR, STEM))
    if "--no-renders" not in argv:
        X.render_qa(cols, MODEL_DIR, STEM, BLUEPRINT, VIEWS)
    result["handoff"] = {
        "vehicle_id": "boilerfang", "candidate_scene": f"res://assets/vehicles/models/boilerfang/{STEM}.glb",
        "source_axes": "X long (speedster End A +X, truck End B -X), Y width, Z up; runtime yaw +90 deg, offset y -0.62",
        "display_radii": {"A": T.WHEEL_R["coupe"], "B": T.WHEEL_R["truck"]},
        "display_half_track": {"A": T.TRACK_Y["coupe"], "B": T.TRACK_Y["truck"]},
        "wheel_centres": {"A": [T.WHEEL_X["coupe"], T.TRACK_Y["coupe"], T.WHEEL_R["coupe"]],
                          "B": [T.WHEEL_X["truck"], T.TRACK_Y["truck"], T.WHEEL_R["truck"]]},
        "semantic_materials": ["Boilerfang_Paint", "Boilerfang_Secondary", "Boilerfang_Stripe"],
        "blueprint_scale_m_per_px": T.SCALE, "wheelbase_m": T.WHEELBASE,
    }
    if "--no-export" not in argv:
        (MODEL_DIR / f"{STEM}_build.json").write_text(json.dumps(result, indent=2) + "\n")
    print("AK: build " + json.dumps(result))


main()
