"""Build the Nightshift blueprint (reversible 80s Chevy square-body truck / Camaro).

Run headlessly: ak-blender tools/vehicle_pipeline/blender/build_nightshift.py
Optional args after `--`: --no-renders, --no-export.  Deadbolt/Blackjack files are never
touched. Deterministic: rebuilding gives identical geometry.
"""
import json
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import nightshift_cabin as CAB  # noqa: E402
import nightshift_core as C  # noqa: E402
import nightshift_cuts as K  # noqa: E402
import nightshift_details as D  # noqa: E402
import nightshift_shell as SH  # noqa: E402
import nightshift_trace as T  # noqa: E402
import nightshift_wheels as W  # noqa: E402
import nightshift_export as X  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
BLUEPRINT = ROOT / "tools/vehicle_pipeline/references/80s.jpg"
MODEL_DIR = ROOT / "godot/assets/vehicles/models/nightshift"
BLEND = HERE / "nightshift_blueprint.blend"
STEM = "nightshift_blueprint"


def main():
    cols = C.reset_scene()
    mats = C.build_materials()
    builder = C.Builder(cols, mats)
    shell = SH.build_shell(builder)
    bpy.context.view_layer.update()
    surf0 = K.Surface(shell)
    K.arch_cutters(builder)
    specs = CAB.glaze(builder, surf0)
    D.detail_cutters(builder, surf0)
    K.add_boolean(shell, cols["CUTTERS"])
    C.apply_all_modifiers(shell)
    print('AK: stage boolean', len(shell.data.vertices), len(shell.data.polygons), flush=True)
    open_edges, volume = C.repair_manifold(shell)
    print('AK: stage repair', len(shell.data.vertices), len(shell.data.polygons), flush=True)
    assert open_edges == 0, f"shell has {open_edges} open edges after repair"
    dissolved_open = C.dissolve_flat(shell, 0.8)
    assert dissolved_open == 0, 'flat dissolve opened the shell'
    print('AK: stage dissolve', len(shell.data.vertices), len(shell.data.polygons), flush=True)
    C.harden(shell, 32.0, keep_flat=True)
    surf = K.Surface(shell)
    glass = CAB.seat_glass(builder, surf, specs)
    for g in glass:
        C.apply_all_modifiers(g)
        C.harden(g, 40.0)
    sd = D.Seat(builder, surf)
    D.build_truck_end(sd, surf)
    D.build_coupe_end(sd, surf)
    D.build_sides(sd, surf)
    D.build_mirrors(sd, surf)
    D.build_wipers_and_roof(sd, surf)
    D.build_extras(sd, surf)
    W.build_wheels(builder)
    X.finalize_scene(cols, shell, BLUEPRINT)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    result = {"shell_volume_m3": round(volume, 4), "blend": str(BLEND.relative_to(ROOT))}
    if "--no-export" not in argv:
        result.update(X.export_all(cols, MODEL_DIR, STEM))
    if "--no-renders" not in argv:
        X.render_qa(cols, MODEL_DIR, STEM, BLUEPRINT)
    result["handoff"] = {
        "vehicle_id": "nightshift", "candidate_scene": f"res://assets/vehicles/models/nightshift/{STEM}.glb",
        "source_axes": "X long (coupe +X), Y width, Z up; runtime yaw +90 deg unchanged",
        "visual_half_track_m": T.TRACK_Y,
        "wheel_centres": {"coupe": [T.WHEEL_X["coupe"], T.TRACK_Y, T.WHEEL_R["coupe"]],
                          "truck": [T.WHEEL_X["truck"], T.TRACK_Y, T.WHEEL_R["truck"]]},
        "semantic_materials": ["Nightshift_Paint", "Nightshift_Secondary", "Nightshift_Stripe"],
        "blueprint_scale_m_per_px": T.SCALE, "wheelbase_m": T.WHEELBASE,
    }
    if "--no-export" not in argv:
        (MODEL_DIR / f"{STEM}_build.json").write_text(json.dumps(result, indent=2) + "\n")
    print("AK: build " + json.dumps(result))


main()
