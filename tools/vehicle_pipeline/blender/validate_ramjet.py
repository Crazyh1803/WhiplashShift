"""Numeric validation of the Ramjet hard-surface candidate (native source + exports).

Run: ak-blender tools/vehicle_pipeline/blender/validate_ramjet.py \
         tools/vehicle_pipeline/blender/ramjet_blueprint.blend
Numbers prove geometry contracts only; visual quality is judged from renders (ak-look).
"""
import json
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import ramjet_core as C  # noqa: E402
import ramjet_trace as T  # noqa: E402

MODEL_DIR = ROOT / "godot/assets/vehicles/models/ramjet"
STEM = "ramjet_blueprint"
SEMANTIC = {"Ramjet_Paint", "Ramjet_Secondary", "Ramjet_Stripe"}
EXPECTED_MATERIALS = SEMANTIC | {
    "Ramjet_Glass", "Ramjet_Rubber", "Ramjet_BrushedMetal", "Ramjet_Gunmetal",
    "Ramjet_Grille", "Ramjet_Headlight", "Ramjet_Marker", "Ramjet_Amber",
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
shell = meshes["Body_RamjetShell"]
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
for px in range(300, 757, 12):
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
for style, count, radius, width in (("Truck", 11, 0.43, 0.33), ("Coupe", 13, 0.40, 0.35)):
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

# --- every L/R cutter pair left the same cut in the shell (a silently dropped Boolean operand) ---
pair_report = {}
for cname, cobj in sorted(bpy.data.objects.items()):
    if not cname.startswith("Cutter_") or not cname.endswith("_L"):
        continue
    other = bpy.data.objects.get(cname[:-2] + "_R")
    if other is None or cobj.data.vertices is None:
        continue
    pts = [cobj.matrix_world @ v.co for v in cobj.data.vertices]
    cx = sum(p.x for p in pts) / len(pts)
    cz = sum(p.z for p in pts) / len(pts)
    if "HoodSeam" in cname or "Hood" in cname:
        continue  # top-surface grooves are checked by the silhouette/symmetry gates
    hit_l = shell_tree.ray_cast(Vector((cx, 3.0, cz)), Vector((0, -1, 0)))[0]
    hit_r = shell_tree.ray_cast(Vector((cx, -3.0, cz)), Vector((0, 1, 0)))[0]
    if hit_l is None or hit_r is None:
        pair_report[cname] = "miss"
    else:
        pair_report[cname] = round((abs(hit_l.y) - abs(hit_r.y)) * 1000, 2)
bad_pairs = {k: v for k, v in pair_report.items() if v == "miss" or abs(v) > 1.0}
check("cutter_pairs_applied_equally", not bad_pairs, {"pairs": len(pair_report), "bad_mm": bad_pairs})

# --- wheel wells are closed: rays through each wheel disc never escape across the car -----------
well_tris = []
well_verts = []
for name, obj in meshes.items():
    if name == "Body_RamjetShell" or name.startswith("Wheel_") and "_+1" in name or name.startswith("Wheel_") and "+1_" in name:
        wm = C.evaluated_mesh(obj)
        base = len(well_verts)
        well_verts.extend(v.co.copy() for v in wm.vertices)
        well_tris.extend(tuple(base + i for i in p.vertices) for p in wm.polygons)
        bpy.data.meshes.remove(wm)
well_tree = BVHTree.FromPolygons(well_verts, well_tris)
escaped = 0
shots = 0
for style, radius in (("truck", 0.43), ("coupe", 0.40)):
    cx = T.WHEEL_X[style]
    for ix in range(-4, 5):
        for iz in range(-4, 5):
            dx, dz = ix * radius / 4.5, iz * radius / 4.5
            if dx * dx + dz * dz > (radius * 0.95) ** 2:
                continue
            for tx, tz in ((0, 0), (0.45, 0), (-0.45, 0), (0, 0.45), (0, -0.45)):
                shots += 1
                direction = Vector((tx, -1.0, tz)).normalized()
                origin = Vector((cx + dx, T.TRACK_Y, radius + dz)) - direction * 2.3  # aim at the disc
                hit = well_tree.ray_cast(origin, direction)
                if hit[0] is None or hit[0].y < 0.0:
                    escaped += 1
check("wheel_wells_closed", escaped == 0, {"rays": shots, "escaped": escaped})

# --- lamps and markers: every vertex seated on the cut shell and inside the authored envelope ----
LAMP_KEYS = ("_Headlamp_", "_Signal_", "_Fog_", "_PopupLens_", "Marker_", "Reflector_")
ENV_X = (T.X(T.NOSE_TRUCK_PX) - 0.30, T.X(T.NOSE_COUPE_PX) + 0.05)
ENV_Y = max(v for _, v in T.HALF) + 0.14 + 0.01
ENV_Z = max(T.top_z(px) for px in range(int(T.NOSE_TRUCK_PX), int(T.NOSE_COUPE_PX) + 1)) + 0.05
lamp_report = {}
for name, obj in sorted(meshes.items()):
    if not any(k in name for k in LAMP_KEYS):
        continue
    lm = C.evaluated_mesh(obj)
    far = max(shell_tree.find_nearest(v.co)[3] for v in lm.vertices)
    # lenses may rest 4 mm off a pocket floor and stand 16 mm proud; side markers must stay thin
    limit = 0.035 if "Marker_" not in name and "Reflector_" not in name else 0.022
    inside = all(ENV_X[0] <= v.co.x <= ENV_X[1] and abs(v.co.y) <= ENV_Y and -0.001 <= v.co.z <= ENV_Z
                 for v in lm.vertices)
    lamp_report[name] = round(far * 1000, 1)
    check(f"lamp_seated_{name}", far <= limit and inside,
          {"max_mm": round(far * 1000, 1), "limit_mm": limit * 1000, "inside_envelope": inside})
    bpy.data.meshes.remove(lm)
results["lamps_max_dist_mm"] = lamp_report

# --- every visible detail vertex lies inside the envelope derived from the authored stations ------
outside = {}
for name, obj in meshes.items():
    if name == "Body_RamjetShell":
        continue
    dm = C.evaluated_mesh(obj)
    bad = sum(1 for v in dm.vertices if not (ENV_X[0] <= v.co.x <= ENV_X[1] and abs(v.co.y) <= ENV_Y
                                             and -0.002 <= v.co.z <= ENV_Z))
    if bad:
        outside[name] = bad
    bpy.data.meshes.remove(dm)
check("details_inside_envelope", not outside, {"outside": dict(list(outside.items())[:6]),
                                              "x": [round(c, 3) for c in ENV_X], "y": round(ENV_Y, 3),
                                              "z": round(ENV_Z, 3)})

# --- whole-assembly mirror symmetry (wipers are deliberately offset per driver/passenger) ------
sym_verts, sym_polys = [], []
for name, obj in meshes.items():
    if name.startswith(("Wiper_", "Cutter")):
        continue
    sm = C.evaluated_mesh(obj)
    base = len(sym_verts)
    sym_verts.extend(v.co.copy() for v in sm.vertices)
    sym_polys.extend(tuple(base + i for i in p.vertices) for p in sm.polygons)
    bpy.data.meshes.remove(sm)
kd = KDTree(len(sym_verts))
for i, v in enumerate(sym_verts):
    kd.insert(v, i)
kd.balance()
sym_tree = BVHTree.FromPolygons(sym_verts, sym_polys)
# Mirrored vertices must land on the assembly surface (Boolean tessellation is not mirrored
# vertex-for-vertex) and on a vertex for the mirrored hardware/wheel parts.
surf_err = sorted(sym_tree.find_nearest(Vector((v.x, -v.y, v.z)))[3] for v in sym_verts)
sym_p999 = surf_err[int(len(surf_err) * 0.999)]
check("assembly_mirror_symmetry", surf_err[-1] < 0.0035 and sym_p999 < 0.003,
      {"max_surface_error_mm": round(surf_err[-1] * 1000, 3), "p99.9_mm": round(sym_p999 * 1000, 4),
       "vertices": len(sym_verts)})

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

# --- glass covers its window cut: no hole between glass and the cutter outline ----------------
glass_trees = {}
for name, obj in meshes.items():
    if name.startswith("Glass_"):
        gm = C.evaluated_mesh(obj)
        glass_trees[name] = C.bvh_of(gm)
        bpy.data.meshes.remove(gm)
cover_report = {}
for name, gtree in sorted(glass_trees.items()):
    cutter = bpy.data.objects.get(name.replace("Glass_", "Cutter_Glass_", 1))
    if cutter is None:
        continue  # the cab-back panel sits on the wall without a cutter
    cm = cutter.data
    half = len(cm.vertices) // 2
    floor_idx = set(range(half))
    bound = set()
    for e in cm.edges:
        a, b = e.vertices
        if a in floor_idx and b in floor_idx:
            n_floor = sum(1 for p in cm.polygons if all(v in floor_idx for v in p.vertices)
                          and a in p.vertices and b in p.vertices)
            if n_floor == 1:
                bound.update((a, b))
    kd_b = KDTree(len(bound))
    for n, i in enumerate(sorted(bound)):
        kd_b.insert(cm.vertices[i].co, n)
    kd_b.balance()
    top_mode = "Windshield" in name
    tested = covered = 0
    for i in range(half):
        co = cm.vertices[i].co
        if i in bound or (len(bound) and kd_b.find(co)[2] < 0.03):
            continue
        out = Vector((0, 0, 1)) if top_mode else Vector((0, 1 if name.endswith("_L") else -1, 0))
        origin = co + out * 0.05
        g_hit = gtree.ray_cast(origin, -out)
        s_hit = shell_tree.ray_cast(origin, -out)
        tested += 1
        if g_hit[0] is not None and (s_hit[0] is None or g_hit[3] <= s_hit[3] + 1e-6):
            covered += 1
    cover_report[name] = {"tested": tested, "covered": covered}
    check(f"glass_covers_cut_{name}", tested > 0 and covered == tested, cover_report[name])
results["glass_coverage"] = cover_report

# --- hardware must not pierce the glass (mirrors, wipers, rails, trims) -------------------------
pierce = {}
for name, obj in meshes.items():
    if not name.startswith(("Mirror_", "Wiper_", "Rail_", "Molding_Belt", "Cab_RearGlassTrim")):
        continue
    hm = C.evaluated_mesh(obj)
    htree = C.bvh_of(hm)
    for gname, gtree in glass_trees.items():
        n = len(htree.overlap(gtree))
        if n and not name.startswith("Mirror_Truck_Glass") and not name.startswith("Mirror_Coupe_Glass"):
            pierce[f"{name}|{gname}"] = n
    bpy.data.meshes.remove(hm)
check("hardware_clear_of_glass", not pierce, dict(list(pierce.items())[:8]))

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
check("packed_reference", bool(bpy.data.objects.get("Reference_Dodge_Blueprint")) and
      bool(bpy.data.objects["Reference_Dodge_Blueprint"].data.packed_file))

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
ADDON = {"truck_front_m": 0.25, "coupe_front_m": 0.04, "mirror_out_m": 0.14, "roof_lamp_m": 0.05}
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
glb_bounds, lod_wheels, lod_mats = {}, {}, {}
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
        check("export_wheel_counts", per == {"Coupe+": 13, "Coupe-": 13, "Truck+": 11, "Truck-": 11}, per)
        mats = {m.name.split(".")[0] for o in new for m in o.data.materials if m}
        check("export_materials", SEMANTIC <= mats and not any(m.startswith("Material") for m in mats),
              sorted(mats))
        check("export_has_uvs", all(o.data.uv_layers for o in new))
        results["export_objects"] = len(new)
    lo_g = Vector((1e9,) * 3)
    hi_g = Vector((-1e9,) * 3)
    for o in new:
        for vert in o.data.vertices:
            w = o.matrix_world @ vert.co
            lo_g = Vector((min(lo_g.x, w.x), min(lo_g.y, w.y), min(lo_g.z, w.z)))
            hi_g = Vector((max(hi_g.x, w.x), max(hi_g.y, w.y), max(hi_g.z, w.z)))
    glb_bounds[key] = (lo_g, hi_g)
    lod_wheels[key] = sum(1 for o in new if o.name.startswith("Wheel_"))
    lod_mats[key] = {m.name.split(".")[0] for o in new for m in o.data.materials if m}
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
results["triangles"] = tris
for lod in ("lod1", "lod2"):
    d_lo = (glb_bounds[lod][0] - glb_bounds["gameplay"][0]).length
    d_hi = (glb_bounds[lod][1] - glb_bounds["gameplay"][1]).length
    check(f"{lod}_keeps_envelope", d_lo < 0.03 and d_hi < 0.03,
          {"min_delta_mm": round(d_lo * 1000, 1), "max_delta_mm": round(d_hi * 1000, 1)})
    check(f"{lod}_keeps_wheels_and_paint", lod_wheels[lod] == lod_wheels["gameplay"] and SEMANTIC <= lod_mats[lod],
          {"wheel_nodes": lod_wheels[lod], "gameplay": lod_wheels["gameplay"]})
check("budget_visible_vehicle_25k_45k", 25000 <= tris["gameplay"] <= 45000, tris["gameplay"])
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
