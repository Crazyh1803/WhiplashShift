"""Numeric validation of the Deadbolt hard-surface candidate (native source + exports).

Run: ak-blender tools/vehicle_pipeline/blender/validate_deadbolt_hardsurface.py \
         tools/vehicle_pipeline/blender/deadbolt_hardsurface.blend
Numbers prove geometry contracts only; visual quality is judged from renders (ak-look).
"""
import hashlib
import json
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import deadbolt_hardsurface_core as C  # noqa: E402
import deadbolt_hardsurface_trace as T  # noqa: E402

MODEL_DIR = ROOT / "godot/assets/vehicles/models/deadbolt"
STEM = "deadbolt_hardsurface"
SEMANTIC = {"Deadbolt_Paint", "Deadbolt_Secondary", "Deadbolt_Stripe"}
EXPECTED_MATERIALS = SEMANTIC | {
    "Deadbolt_Glass", "Deadbolt_Rubber", "Deadbolt_BrushedMetal", "Deadbolt_Gunmetal",
    "Deadbolt_Grille", "Deadbolt_Headlight", "Deadbolt_Marker", "Deadbolt_Amber",
}
results = {}
failures = []


def check(name, ok, detail=None):
    results[name] = {"ok": bool(ok), "detail": detail}
    if not ok:
        failures.append(name)


def bvh_of(obj):
    mesh = C.evaluated_mesh(obj)
    tree = C.bvh_of(mesh)
    return tree, mesh


meshes = {o.name: o for o in bpy.data.objects if o.type == "MESH" and not o.name.startswith("Cutter")}
shell = meshes["Body_DeadboltShell"]
shell_tree, shell_mesh = bvh_of(shell)

# --- closed, positive-volume shell -----------------------------------------------------------
bm = bmesh.new()
bm.from_mesh(shell_mesh)
open_edges = sum(1 for e in bm.edges if not e.is_manifold)
volume = bm.calc_volume(signed=True)
check("shell_closed_manifold", open_edges == 0, {"open_edges": open_edges})
check("shell_positive_volume", volume > 8.0, {"volume_m3": round(volume, 4)})
bm.free()

# --- mirror symmetry (surface distance of mirrored vertices) ---------------------------------
errors = sorted(shell_tree.find_nearest(Vector((v.co.x, -v.co.y, v.co.z)))[3] for v in shell_mesh.vertices)
p99 = errors[int(len(errors) * 0.99)]
# The cage and cutters are mirrored by construction; exact-Boolean tessellation where thin
# grooves cross each other may move a handful of vertices by millimetres between the halves.
outliers = sum(1 for e in errors if e > 0.002)
check("shell_mirror_symmetry_mm", errors[-1] < 0.02 and outliers <= 12 and p99 < 0.001,
      {"max_surface_error_mm": round(errors[-1] * 1000, 3), "p99_mm": round(p99 * 1000, 3),
       "vertices_over_2mm": outliers, "vertex_count": len(errors),
       "median_mm": round(errors[len(errors) // 2] * 1000, 4)})

# --- blueprint silhouette: roof/hood line, sill, half-width ----------------------------------
top_err, sill_err, width_err = [], [], []
for px in range(300, 755, 12):
    x = T.X(px)
    hit = shell_tree.ray_cast(Vector((x, 0.0, 4.0)), Vector((0, 0, -1)))[0]
    if hit:
        top_err.append(abs(hit.z - T.top_z(px)) / T.SCALE)
    if all(abs(px - T.WHEEL_PX[k][0]) > 48 for k in T.WHEEL_PX):
        hit = shell_tree.ray_cast(Vector((x, 0.0, -1.0)), Vector((0, 0, 1)))[0]
        if hit:
            sill_err.append(abs(hit.z - T.sill_z(px)) / T.SCALE)
    best = 0.0
    for k in range(1, 20):
        z = T.sill_z(px) + (T.belt_z(px) - T.sill_z(px)) * k / 20
        h = shell_tree.ray_cast(Vector((x, 2.0, z)), Vector((0, -1, 0)))[0]
        if h:
            best = max(best, h.y)
    if best:
        width_err.append(abs(best - T.half_width(px)) / T.SCALE)
check("silhouette_top_px", max(top_err) < 4.0, {"max": round(max(top_err), 2), "mean": round(sum(top_err) / len(top_err), 2)})
check("silhouette_sill_px", max(sill_err) < 6.0, {"max": round(max(sill_err), 2)})
check("silhouette_halfwidth_px", max(width_err) < 5.0, {"max": round(max(width_err), 2)})

# --- wheels: names, counts, centres, radii, orientation, arch clearance ----------------------
wheel_report = {}
for style, count, radius, width in (("Truck", 9, 0.43, 0.34), ("Coupe", 13, 0.40, 0.29)):
    for side in (-1, 1):
        parts = [o for n, o in meshes.items() if n.startswith(f"Wheel_{style}_") and
                 (n.endswith(f"_{side:+d}") or f"_{side:+d}_" in n)]
        tire = meshes[f"Wheel_{style}_Tire_{side:+d}"]
        centre = Vector((T.WHEEL_X[style.lower()], side * T.TRACK_Y, radius))
        dims = tire.dimensions
        origin_err = max((o.matrix_world.translation - centre).length for o in parts)
        key = f"{style}_{side:+d}"
        wheel_report[key] = {"parts": len(parts), "origin_err_mm": round(origin_err * 1000, 3),
                             "dims": [round(d, 4) for d in dims]}
        check(f"wheel_parts_{key}", len(parts) == count, {"parts": len(parts), "expected": count})
        check(f"wheel_origin_{key}", origin_err < 0.001, {"mm": round(origin_err * 1000, 3)})
        check(f"wheel_radius_{key}", abs(dims.x - 2 * radius) < 0.004 and abs(dims.z - 2 * radius) < 0.004,
              {"dims": [round(d, 4) for d in dims]})
        check(f"wheel_axis_Y_{key}", dims.y < dims.x and abs(dims.y - width) < 0.01,
              {"width": round(dims.y, 4)})
        tire_mesh = C.evaluated_mesh(tire)
        clear = min(shell_tree.find_nearest(v.co)[3] for v in tire_mesh.vertices)
        wheel_report[key]["arch_clearance_mm"] = round(clear * 1000, 1)
        check(f"arch_clearance_{key}", clear >= 0.030, {"mm": round(clear * 1000, 1)})
        bpy.data.meshes.remove(tire_mesh)
results["wheels"] = wheel_report

# --- glass: seated 0.5-6 mm off the shell, no crossing ---------------------------------------
glass_report = {}
for name, obj in sorted(meshes.items()):
    if not name.startswith("Glass_"):
        continue
    gm = C.evaluated_mesh(obj)
    dist = [shell_tree.find_nearest(v.co)[3] for v in gm.vertices]
    gtree = C.bvh_of(gm)
    crossings = len(gtree.overlap(shell_tree))
    glass_report[name] = {"min_mm": round(min(dist) * 1000, 2), "max_mm": round(max(dist) * 1000, 2),
                          "shell_crossings": crossings}
    check(f"glass_seated_{name}", 0.0005 <= min(dist) and max(dist) <= 0.006 and crossings == 0,
          glass_report[name])
    bpy.data.meshes.remove(gm)
results["glass"] = glass_report

# --- UV / material coverage ------------------------------------------------------------------
missing_uv = [n for n, o in meshes.items() if not o.data.uv_layers]
bad_slots = [n for n, o in meshes.items()
             if any(m is None for m in o.data.materials) or not o.data.materials]
bad_idx = [n for n, o in meshes.items()
           if any(p.material_index >= len(o.data.materials) for p in o.data.polygons)]
used = {m.name for o in meshes.values() for m in o.data.materials}
check("uv_complete", not missing_uv, {"missing": missing_uv[:5]})
check("material_slots_valid", not bad_slots and not bad_idx, {"bad": (bad_slots + bad_idx)[:5]})
check("materials_exact", used == EXPECTED_MATERIALS, {"extra": sorted(used - EXPECTED_MATERIALS),
                                                      "missing": sorted(EXPECTED_MATERIALS - used)})
check("semantic_paint_channels", SEMANTIC <= used)
check("packed_reference", bool(bpy.data.objects.get("Reference_80sFord_Blueprint")) and
      bool(bpy.data.objects["Reference_80sFord_Blueprint"].data.packed_file))

# --- bounds and ground ------------------------------------------------------------------------
lo = Vector((1e9,) * 3)
hi = Vector((-1e9,) * 3)
for o in meshes.values():
    mesh = C.evaluated_mesh(o)
    for v in mesh.vertices:
        lo = Vector((min(lo.x, v.co.x), min(lo.y, v.co.y), min(lo.z, v.co.z)))
        hi = Vector((max(hi.x, v.co.x), max(hi.y, v.co.y), max(hi.z, v.co.z)))
    bpy.data.meshes.remove(mesh)
size = hi - lo
results["bounds"] = {"min": [round(c, 4) for c in lo], "max": [round(c, 4) for c in hi],
                     "size": [round(c, 4) for c in size]}
check("bounds_length", 5.0 < size.x < 5.6, {"x": round(size.x, 3)})
check("bounds_width", 2.0 < size.y < 2.4, {"y": round(size.y, 3)})
check("bounds_height", 1.6 < size.z < 1.95, {"z": round(size.z, 3)})
check("ground_contact", abs(lo.z) < 0.003, {"min_z": round(lo.z, 4)})

# --- exported GLBs: re-import and count --------------------------------------------------------
glbs = {"gameplay": MODEL_DIR / f"{STEM}.glb", "lod1": MODEL_DIR / f"lod/{STEM}_LOD1.glb",
        "lod2": MODEL_DIR / f"lod/{STEM}_LOD2.glb"}
tris = {}
for key, path in glbs.items():
    check(f"export_exists_{key}", path.is_file() and path.stat().st_size > 1024, {"path": str(path.relative_to(ROOT))})
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    tris[key] = C.triangle_count(new)
    if key == "gameplay":
        names = [o.name for o in new]
        wheel_nodes = [n for n in names if n.startswith("Wheel_")]
        per = {}
        for n in wheel_nodes:
            tag = n.split("_")[1] + ("+" if "_+1" in n else "-")
            per[tag] = per.get(tag, 0) + 1
        check("export_wheel_counts", per == {"Coupe+": 13, "Coupe-": 13, "Truck+": 9, "Truck-": 9}, per)
        mats = {m.name.split(".")[0] for o in new for m in o.data.materials if m}
        check("export_materials", SEMANTIC <= mats and not any(m.startswith("Material") for m in mats),
              sorted(mats))
        check("export_has_uvs", all(o.data.uv_layers for o in new))
        results["export_objects"] = len(new)
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
results["triangles"] = tris
check("budget_visible_vehicle_20k_40k", 20000 <= tris["gameplay"] <= 40000, tris["gameplay"])
check("lod_monotonic", tris["gameplay"] > tris["lod1"] > tris["lod2"] > 5000, tris)
results["object_signatures"] = {
    n: [len(o.data.vertices), len(o.data.polygons),
        round(sum(v.co.x + 2 * v.co.y + 3 * v.co.z for v in o.data.vertices), 4)]
    for n, o in sorted(meshes.items())}
results["geometry_sha256"] = hashlib.sha256(json.dumps(
    sorted((n, len(o.data.vertices), len(o.data.polygons), round(sum(v.co.x + 2 * v.co.y + 3 * v.co.z for v in o.data.vertices), 4))
           for n, o in meshes.items())).encode()).hexdigest()

status = "FAIL" if failures else "PASS"
report = {"status": status, "failures": failures, "results": results}
out = MODEL_DIR / f"{STEM}_qa.json"
out.write_text(json.dumps(report, indent=2, default=str) + "\n")
print("AK: " + json.dumps({"status": status, "failures": failures, "triangles": tris,
                           "geometry_sha256": results["geometry_sha256"][:16]}))
if failures:
    sys.exit(1)
