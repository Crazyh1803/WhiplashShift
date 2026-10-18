"""Build the Helix Wraith biomechanical racer blueprint model.

Run headlessly: ak-blender tools/vehicle_pipeline/blender/build_helix.py
Optional args after `--`: --no-renders, --no-export, --views=<a,b,...>.
Other vehicles' files are never touched. Deterministic: rebuilding gives identical geometry.
"""
import json
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import helix_body as B  # noqa: E402
import helix_core as C  # noqa: E402
import helix_export as X  # noqa: E402
import helix_organic as O  # noqa: E402
import helix_tracks as TR  # noqa: E402
import helix_trace as T  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
BLUEPRINT = ROOT / "tools/vehicle_pipeline/references/r-type.jpg"
MODEL_DIR = ROOT / "godot/assets/vehicles/models/helix"
BLEND = HERE / "helix_blueprint.blend"
STEM = "helix_blueprint"
VIEWS = next((a.split("=", 1)[1].split(",") for a in argv if a.startswith("--views=")), None)


def main():
    cols = C.reset_scene()
    mats = C.build_materials()
    builder = C.Builder(cols, mats)
    hull = B.build_hull(builder)
    bpy.context.view_layer.update()
    surf = B.Surface(hull)
    B.build_plates(builder)
    B.build_collar(builder)
    B.build_maw(builder)
    B.build_sponsons(builder)
    B.build_wings(builder)
    B.build_nacelles(builder)
    B.build_pods(builder)
    B.build_canopies(builder, surf)
    B.build_blister(builder)
    O.build_claws(builder)
    O.build_hoses(builder)
    O.build_fins(builder, surf)
    O.build_vents(builder, surf)
    O.build_lenses(builder)
    TR.build_tracks(builder)
    try:
        import helix_details as D
        D.build(builder, hull, surf)
    except ModuleNotFoundError:
        pass
    print("AK: source triangles", C.triangle_count(list(cols["HELIX_SOURCE"].objects)), flush=True)
    X.finalize_scene(cols, hull, BLUEPRINT)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    result = {"blend": str(BLEND.relative_to(ROOT))}
    if "--no-export" not in argv:
        result.update(X.export_all(cols, MODEL_DIR, STEM))
    if "--no-renders" not in argv:
        X.render_qa(cols, MODEL_DIR, STEM, BLUEPRINT, VIEWS)
    result["handoff"] = {
        "vehicle_id": "helix", "candidate_scene": f"res://assets/vehicles/models/helix/{STEM}.glb",
        "source_axes": "X long (hovering nose End A +X, biomech claw End B -X), Y width, Z up, ground z=0; "
                       "runtime yaw +90 deg, offset y -0.62",
        "overall_length_m": T.LENGTH, "blueprint_scale_m_per_px": T.SCALE,
        "wheels": "none authored: the sheet has tracks under End B and a wheel-less hovering nose; the four "
                  "physical wheels' visuals/axles are hidden by the game adapter",
        "track_contact": {
            "z": 0.0, "x_range": [TR.X1 - TR.R_OUT, TR.X2 + TR.R_OUT],
            "flat_x_range": [TR.X1, TR.X2], "y_centres": [T.TRACK_Y, -T.TRACK_Y], "width": T.TRACK_W,
            "sprocket_axle": [[TR.X1, TR.ZC], [TR.X2, TR.ZC]], "outer_radius": TR.R_OUT},
        "semantic_materials": ["Helix_Paint", "Helix_Secondary", "Helix_Stripe"],
    }
    if "--no-export" not in argv:
        (MODEL_DIR / f"{STEM}_build.json").write_text(json.dumps(result, indent=2) + "\n")
    print("AK: build " + json.dumps(result))


main()
