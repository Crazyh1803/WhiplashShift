"""Strict numeric validation for the saved Deadbolt Blender source."""
import json
import hashlib
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]
MODEL_DIR = ROOT / "godot/assets/vehicles/models/deadbolt"
required = {
    "Body_DeadboltUnifiedShell",
    "Truck_Grille",
    "Truck_BrushGuard",
    "Coupe_Grille",
    "Coupe_Splitter",
    "Glass_Roof",
    "Wheel_Truck_Tire_-1",
    "Wheel_Truck_Tire_+1",
    "Wheel_Coupe_Tire_-1",
    "Wheel_Coupe_Tire_+1",
}
missing = sorted(required - set(bpy.data.objects.keys()))
assert not missing, f"Missing required objects: {missing}"

meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
assert len(meshes) == 95, f"Expected 95 meshes, got {len(meshes)}"
assert all(obj.data.uv_layers for obj in meshes), "Every exported mesh must have UVs"

depsgraph = bpy.context.evaluated_depsgraph_get()
triangles = 0
minimum = Vector((math.inf, math.inf, math.inf))
maximum = Vector((-math.inf, -math.inf, -math.inf))
for source in meshes:
    obj = source.evaluated_get(depsgraph)
    mesh = obj.to_mesh()
    mesh.calc_loop_triangles()
    triangles += len(mesh.loop_triangles)
    for corner in obj.bound_box:
        point = obj.matrix_world @ Vector(corner)
        minimum.x = min(minimum.x, point.x)
        minimum.y = min(minimum.y, point.y)
        minimum.z = min(minimum.z, point.z)
        maximum.x = max(maximum.x, point.x)
        maximum.y = max(maximum.y, point.y)
        maximum.z = max(maximum.z, point.z)
    obj.to_mesh_clear()

size = maximum - minimum
assert 18000 <= triangles <= 20000, f"Triangle budget drifted: {triangles}"
assert 5.2 <= size.x <= 5.5, f"Length out of range: {size.x}"
assert 2.1 <= size.y <= 2.3, f"Width out of range: {size.y}"
assert 1.55 <= size.z <= 1.7, f"Height out of range: {size.z}"
assert minimum.z >= -0.002, f"Geometry below ground: {minimum.z}"

for name, expected in {
    "Wheel_Truck_Tire_-1": (0.86, 0.34, 0.86),
    "Wheel_Truck_Tire_+1": (0.86, 0.34, 0.86),
    "Wheel_Coupe_Tire_-1": (0.80, 0.29, 0.80),
    "Wheel_Coupe_Tire_+1": (0.80, 0.29, 0.80),
}.items():
    actual = bpy.data.objects[name].dimensions
    assert all(abs(actual[i] - expected[i]) < 0.012 for i in range(3)), (
        f"{name} dimensions {tuple(actual)} do not match {expected}")

materials = {material.name for material in bpy.data.materials}
expected_materials = {
    "Deadbolt_Paint", "Deadbolt_Secondary", "Deadbolt_Stripe",
    "Deadbolt_Glass", "Deadbolt_Rubber", "Deadbolt_BrushedMetal",
    "Deadbolt_Gunmetal", "Deadbolt_Grille", "Deadbolt_Headlight",
    "Deadbolt_Marker",
}
assert materials == expected_materials, f"Material drift: {sorted(materials)}"

reference = bpy.data.objects.get("Reference_80sFord_Blueprint")
assert reference and reference.data and reference.data.packed_file, "Blueprint is not packed"
blend_path = Path(bpy.data.filepath)
outputs = (
    MODEL_DIR / "deadbolt_blueprint.glb",
    MODEL_DIR / "lod/deadbolt_blueprint_LOD1.glb",
    MODEL_DIR / "lod/deadbolt_blueprint_LOD2.glb",
    MODEL_DIR / "deadbolt_blueprint_preview.png",
)
for path in outputs:
    assert path.is_file() and path.stat().st_size > 1024, f"Missing output: {path}"
    assert path.stat().st_mtime_ns >= blend_path.stat().st_mtime_ns, (
        f"Stale output predates source: {path}")
assert outputs[0].stat().st_size > outputs[1].stat().st_size > outputs[2].stat().st_size, (
    "LOD files must decrease in size")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

report = {
    "status": "PASS",
    "mesh_objects": len(meshes),
    "evaluated_triangles": triangles,
    "bbox_min": [round(value, 4) for value in minimum],
    "bbox_max": [round(value, 4) for value in maximum],
    "size": [round(value, 4) for value in size],
    "materials": len(materials),
    "uv_complete": True,
    "blueprint_packed": True,
    "wheel_dimensions_verified": True,
    "source_sha256": sha256(blend_path),
    "output_sha256": {path.name: sha256(path) for path in outputs},
}
(MODEL_DIR / "deadbolt_blueprint_qa.json").write_text(json.dumps(report, indent=2) + "\n")
print("AK: " + json.dumps(report), flush=True)
