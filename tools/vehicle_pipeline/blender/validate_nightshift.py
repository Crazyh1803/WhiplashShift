"""Numeric validation of the Nightshift hard-surface candidate (native source + exports).

Run: ak-blender tools/vehicle_pipeline/blender/validate_nightshift.py \
         tools/vehicle_pipeline/blender/nightshift_blueprint.blend
Numbers prove geometry contracts only; visual quality is judged from renders (ak-look).
"""
import json
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import nightshift_core as C  # noqa: E402
import nightshift_trace as T  # noqa: E402

MODEL_DIR = ROOT / "godot/assets/vehicles/models/nightshift"
STEM = "nightshift_blueprint"
SEMANTIC = {"Nightshift_Paint", "Nightshift_Secondary", "Nightshift_Stripe"}
EXPECTED_MATERIALS = SEMANTIC | {
    "Nightshift_Glass", "Nightshift_Rubber", "Nightshift_BrushedMetal", "Nightshift_Gunmetal",
    "Nightshift_Grille", "Nightshift_Headlight", "Nightshift_Marker", "Nightshift_Amber",
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
shell = meshes["Body_NightshiftShell"]
shell_tree, shell_mesh = bvh_of(shell)

# --- closed, positive-volume shell -----------------------------------------------------------
bm = bmesh.new()
bm.from_mesh(shell_mesh)
open_edges = sum(1 for e in bm.edges if not e.is_manifold)
volume = bm.calc_volume(signed=True)
check("shell_closed_manifold", open_edges == 0, {"open_edges": open_edges})
check("shell_positive_volume", volume > 6.0, {"volume_m3": round(volume, 4)})
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
    if any(abs(px - T.WHEEL_PX[k][0]) <= 52 for k in T.WHEEL_PX):
        continue  # rays pass through the open wheel arches
    for k in range(1, 20):
        z = T.sill_z(px) + (T.belt_z(px) - T.sill_z(px)) * k / 20
        h = shell_tree.ray_cast(Vector((x, 2.0, z)), Vector((0, -1, 0)))[0]
        if h:
            best = max(best, h.y)
    if best:
        width_err.append((abs(best - T.half_width(px)) / T.SCALE, px))
check("silhouette_top_px", max(top_err) < 4.0, {"max": round(max(top_err), 2), "mean": round(sum(top_err) / len(top_err), 2)})
check("silhouette_sill_px", max(sill_err) < 6.0, {"max": round(max(sill_err), 2)})
check("silhouette_halfwidth_px", max(width_err)[0] < 5.0, {"max": round(max(width_err)[0], 2), "at_px": max(width_err)[1]})

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
        outer = abs(centre.y) + width / 2
        fender = T.half_width(T.PX(centre.x))
        wheel_report[key]["tyre_outer_face_m"] = round(outer, 4)
        wheel_report[key]["fender_half_width_m"] = round(fender, 4)
        check(f"tyre_under_fender_{key}", outer <= fender + 0.002,
              {"tyre_outer": round(outer, 4), "fender": round(fender, 4)})
        tire_mesh = C.evaluated_mesh(tire)
        clear = min(shell_tree.find_nearest(v.co)[3] for v in tire_mesh.vertices)
        wheel_report[key]["arch_clearance_mm"] = round(clear * 1000, 1)
        check(f"arch_clearance_{key}", clear >= 0.030, {"mm": round(clear * 1000, 1)})
        bpy.data.meshes.remove(tire_mesh)
results["wheels"] = wheel_report

# --- lamps: lenses seated in their pockets (within 35 mm of the cut shell, none floating) -------
lamp_report = {}
for name, obj in sorted(meshes.items()):
    if "_Headlamp_" not in name:
        continue
    lm = C.evaluated_mesh(obj)
    far = max(shell_tree.find_nearest(v.co)[3] for v in lm.vertices)
    lamp_report[name] = round(far * 1000, 1)
    check(f"lamp_seated_{name}", far <= 0.035, {"max_mm": round(far * 1000, 1)})
    bpy.data.meshes.remove(lm)
results["lamps_max_dist_mm"] = lamp_report

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
check("packed_reference", bool(bpy.data.objects.get("Reference_80s_Blueprint")) and
      bool(bpy.data.objects["Reference_80s_Blueprint"].data.packed_file))

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
# Envelope derived from the authored trace: body length/width/height plus declared add-ons
# (truck bumper + push guards ahead of the nose, chin spoiler, mirrors, roof clearance lamps).
body_len = T.X(T.NOSE_COUPE_PX) - T.X(T.NOSE_TRUCK_PX)
body_half = max(v for _, v in T.HALF)
roof_top = max(T.top_z(px) for px in range(int(T.NOSE_TRUCK_PX), int(T.NOSE_COUPE_PX) + 1))
ADDON = {"truck_front_m": 0.25, "coupe_front_m": 0.12, "mirror_out_m": 0.14, "roof_lamp_m": 0.05}
len_lo = body_len - 0.05
len_hi = body_len + ADDON["truck_front_m"] + ADDON["coupe_front_m"]
wid_lo = 2 * body_half
wid_hi = 2 * (body_half + ADDON["mirror_out_m"])
hgt_lo, hgt_hi = roof_top - 0.03, roof_top + ADDON["roof_lamp_m"]
results["bounds_expected"] = {"length": [round(len_lo, 3), round(len_hi, 3)], "width": [round(wid_lo, 3), round(wid_hi, 3)],
                              "height": [round(hgt_lo, 3), round(hgt_hi, 3)]}
check("bounds_length", len_lo <= size.x <= len_hi, {"x": round(size.x, 3), "range": results["bounds_expected"]["length"]})
check("bounds_width", wid_lo <= size.y <= wid_hi, {"y": round(size.y, 3), "range": results["bounds_expected"]["width"]})
check("bounds_height", hgt_lo <= size.z <= hgt_hi, {"z": round(size.z, 3), "range": results["bounds_expected"]["height"]})
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
results["object_counts"] = {n: [len(o.data.vertices), len(o.data.polygons)] for n, o in sorted(meshes.items())}
results["visual_half_track_m"] = T.TRACK_Y

status = "FAIL" if failures else "PASS"
report = {"status": status, "failures": failures, "results": results}
out = MODEL_DIR / f"{STEM}_qa.json"
out.write_text(json.dumps(report, indent=2, default=str) + "\n")
print("AK: " + json.dumps({"status": status, "failures": failures, "triangles": tris,
                           "visual_half_track_m": T.TRACK_Y}))
if failures:
    sys.exit(1)
