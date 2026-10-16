"""Build the Deadbolt hard-surface candidate (reversible 80s Ford truck / Mustang).

Run headlessly: ak-blender tools/vehicle_pipeline/blender/build_deadbolt_hardsurface.py
Optional args after `--`: --no-renders, --no-export.  Existing deadbolt_blueprint*
draft files are never touched. Deterministic: rebuilding gives identical geometry.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import deadbolt_hardsurface_cabin as CAB  # noqa: E402
import deadbolt_hardsurface_core as C  # noqa: E402
import deadbolt_hardsurface_cuts as K  # noqa: E402
import deadbolt_hardsurface_details as D  # noqa: E402
import deadbolt_hardsurface_qa as Q  # noqa: E402
import deadbolt_hardsurface_shell as SH  # noqa: E402
import deadbolt_hardsurface_trace as T  # noqa: E402
import deadbolt_hardsurface_wheels as W  # noqa: E402
import deadbolt_hardsurface_export as X  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
BLUEPRINT = ROOT / "tools/vehicle_pipeline/references/80sFord.jpg"
MODEL_DIR = ROOT / "godot/assets/vehicles/models/deadbolt"
BLEND = HERE / "deadbolt_hardsurface.blend"
STEM = "deadbolt_hardsurface"


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
    open_edges, volume = C.repair_manifold(shell)
    assert open_edges == 0, f"shell has {open_edges} open edges after repair"
    dissolved_open = C.dissolve_flat(shell, 1.5)
    assert dissolved_open == 0, 'flat dissolve opened the shell'
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
    W.build_wheels(builder)
    X.finalize_scene(cols, shell, BLUEPRINT)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    result = {"shell_volume_m3": round(volume, 4), "blend": str(BLEND.relative_to(ROOT))}
    if "--no-export" not in argv:
        result.update(X.export_all(cols, MODEL_DIR, STEM))
    if "--no-renders" not in argv:
        X.render_qa(cols, MODEL_DIR, STEM, BLUEPRINT)
    print("AK: build " + json.dumps(result))


main()
