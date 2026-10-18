"""Render the shipped Knifeedge GLBs (gameplay, LOD1, LOD2) from one 3/4 view for visual LOD review.

Run: ak-blender tools/vehicle_pipeline/blender/render_knifeedge_lods.py
"""
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import knifeedge_core as C  # noqa: E402
import knifeedge_qa as Q  # noqa: E402

MODEL_DIR = ROOT / "godot/assets/vehicles/models/knifeedge"
OUT = ROOT / "tools/vehicle_pipeline/qa/knifeedge_blueprint"
STEM = "knifeedge_blueprint"

for tag, rel in (("gameplay", f"{STEM}.glb"), ("lod1", f"lod/{STEM}_LOD1.glb"),
                 ("lod2", f"lod/{STEM}_LOD2.glb")):
    cols = C.reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(MODEL_DIR / rel))
    Q.build_studio(cols)
    for view in ("three_quarter_coupe", "three_quarter_truck"):
        Q.configure(view, 1024, 576)
        Q.render(OUT / f"{STEM}_lod_{tag}_{view}.png")
print("AK: lod renders done")
