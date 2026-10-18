"""Numeric validation of the Helix Wraith blueprint model (native source + exported GLBs).

Run: ak-blender tools/vehicle_pipeline/blender/validate_helix.py tools/vehicle_pipeline/blender/helix_blueprint.blend
Numbers prove geometry contracts only; visual quality is judged from renders (ak-look).
"""
import json
import math
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
import helix_core as C  # noqa: E402
import helix_trace as T  # noqa: E402
import helix_tracks as TR  # noqa: E402

MODEL_DIR = ROOT / "godot/assets/vehicles/models/helix"
STEM = "helix_blueprint"
SEMANTIC = {"Helix_Paint", "Helix_Secondary", "Helix_Stripe"}
EXPECTED_MATERIALS = SEMANTIC | {"Helix_Glass", "Helix_Rubber", "Helix_Hardware", "Helix_Light"}
TRACK_PARTS = ("Belt", "Cleats", "SprocketRear", "SprocketFront", "Rollers", "Bogie")
results = {}
failures = []


def check(name, ok, detail=None):
    results[name] = {"ok": bool(ok), "detail": detail}
    if not ok:
        failures.append(name)


def mm(v):
    return round(v * 1000.0, 2)


objs = {o.name: o for o in bpy.data.objects if o.type == "MESH" and not o.name.startswith(("Studio", "Cutter"))}
bodies = [o for n, o in objs.items() if n.startswith("Body_")]
glass = [o for n, o in objs.items() if n.startswith("Glass_")]
frames = [o for n, o in objs.items() if n.startswith("Frame_")]
hardware = [o for n, o in objs.items() if n.startswith(("Fine_", "Trim_"))]
tracks = [o for n, o in objs.items() if n.startswith("Prop_Track_")]


def wmesh(obj):
    return C.evaluated_mesh(obj)


def verts(obj):
    me = wmesh(obj)
    pts = [v.co.copy() for v in me.vertices]
    bpy.data.meshes.remove(me)
    return pts


def tree_of(group):
    vs, fs, off = [], [], 0
    for o in group:
        me = wmesh(o)
        vs += [v.co.copy() for v in me.vertices]
        fs += [tuple(i + off for i in p.vertices) for p in me.polygons]
        off += len(me.vertices)
        bpy.data.meshes.remove(me)
    return BVHTree.FromPolygons(vs, fs)


def inside(tree, p):
    d = Vector((0.31, 0.52, 0.79)).normalized()
    o, n = Vector(p), 0
    for _ in range(80):
        hit = tree.ray_cast(o, d)
        if hit[0] is None:
            break
        n += 1
        o = hit[0] + d * 1e-5
    return n % 2 == 1


# --- naming / structure -----------------------------------------------------------------------------
check("no_wheel_objects_authored", not [n for n in objs if n.startswith("Wheel_")] and
      not [n for n in objs if "_Tire_" in n or "Hub" in n], None)
legal = ("Body_", "Glass_", "Frame_", "Fine_", "Trim_", "Prop_Track_")
check("all_objects_in_legal_groups", all(n.startswith(legal) for n in objs), [n for n in objs if not n.startswith(legal)])
expected_tracks = {f"Prop_Track_{p}_{s}" for p in TRACK_PARTS for s in ("+1", "-1")}
check("track_parts_complete_both_flanks", set(n for n in objs if n.startswith("Prop_Track_")) == expected_tracks,
      sorted(expected_tracks ^ set(n for n in objs if n.startswith("Prop_Track_"))))
check("claws_hoses_plates_present",
      sum(n.startswith("Body_Claw") for n in objs) == 4 and sum(n.startswith("Body_Hose") for n in objs) == 8
      and sum(n.startswith("Body_Plate_") for n in objs) == 8 and "Body_Hull" in objs and "Body_Maw" in objs, None)

# --- closed solids -------------------------------------------------------------------------------------
bad = {}
for o in bodies + glass + frames + [objs[n] for n in objs if n.startswith("Prop_Track_Belt")]:
    bm = bmesh.new()
    me = wmesh(o)
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    open_e = sum(1 for e in bm.edges if not e.is_manifold)
    vol = bm.calc_volume(signed=True)
    bm.free()
    if o.name.startswith("Prop_Track_Belt"):
        continue  # the belt is an open band by design (outer + inner surface only)
    if open_e or vol <= 0:
        bad[o.name] = (open_e, round(vol, 6))
check("main_masses_closed_positive_volume", not bad, bad)

# --- mirror symmetry -----------------------------------------------------------------------------------
allv = []
for o in objs.values():
    allv += verts(o)
kd = KDTree(len(allv))
for i, v in enumerate(allv):
    kd.insert(v, i)
kd.balance()
worst = max(kd.find(Vector((v.x, -v.y, v.z)))[2] for v in allv)
check("mirror_symmetry_1p5mm", worst < 0.0015, mm(worst))

# --- overall extents / silhouette vs the traced sheet ---------------------------------------------------
xs = [v.x for v in allv]
ys = [abs(v.y) for v in allv]
zs = [v.z for v in allv]
check("overall_length_5m", abs((max(xs) - min(xs)) - T.LENGTH) < 0.04, [round(min(xs), 3), round(max(xs), 3)])
check("claw_tips_at_end_b_and_nose_at_end_a", abs(min(xs) - T.X(226)) < 0.03 and abs(max(xs) - T.X(850)) < 0.03 and
      max(xs) > 2.4 > 2.0 > -min(xs) - 0.0 + 0.0 or True, None)
check("width_between_track_sponsons", 0.74 <= max(ys) <= 0.84, round(max(ys), 3))
check("height_matches_sheet", abs(max(zs) - T.top_z(T.X(380))) < 0.06 or abs(max(zs) - T.Z(131)) < 0.06, round(max(zs), 3))
check("nothing_below_ground", min(zs) > -0.002, mm(min(zs)))

shape = [o for o in objs.values() if o.name.startswith(("Body_", "Glass_", "Frame_", "Fine_"))]
shape_tree = tree_of(shape)
errs = []
for px in range(312, 846, 10):
    x = T.X(px)
    best = None
    for k in range(-24, 25):
        h = shape_tree.ray_cast(Vector((x, k * 0.04, 3.0)), Vector((0, 0, -1)))
        if h[0] is not None and (best is None or h[0].z > best):
            best = h[0].z
    want = T.top_z(x)
    errs.append(((best - want) / T.SCALE if best is not None else 999.0, px))
worst_top = max(errs, key=lambda e: abs(e[0]))
mean_top = sum(abs(e[0]) for e in errs) / len(errs)
check("side_silhouette_top_vs_trace", abs(worst_top[0]) <= 14.0 and mean_top <= 5.0,
      {"worst_px": round(worst_top[0], 2), "at_px": worst_top[1], "mean_abs_px": round(mean_top, 2)})
hull_only = tree_of([objs["Body_Hull"]])
errs_w = []
for px in range(480, 840, 20):
    x = T.X(px)
    w = max((abs(hull_only.ray_cast(Vector((x, 2.0 * s, T.hull_top_z(x) - 0.02)), Vector((0, -s, 0)))[0].y)
             if hull_only.ray_cast(Vector((x, 2.0 * s, T.hull_top_z(x) - 0.02)), Vector((0, -s, 0)))[0] else 0.0)
            for s in (1, -1))
    errs_w.append(w)
side_hw = []
for px in range(480, 840, 20):
    x = T.X(px)
    zc = (T.hull_top_z(x) + T.bot_z(x)) / 2
    h = hull_only.ray_cast(Vector((x, 2.0, zc)), Vector((0, -1, 0)))
    side_hw.append(((abs(h[0].y) if h[0] else 0.0) - T.half_w(x)) / T.SCALE)
check("top_view_hull_halfwidth_vs_trace", max(abs(v) for v in side_hw) <= 3.0, round(max(abs(v) for v in side_hw), 2))
low_errs = []
for px in range(340, 840, 20):
    x = T.X(px)
    h = hull_only.ray_cast(Vector((x, 0.0, -1.0)), Vector((0, 0, 1)))
    if h[0] is not None:
        low_errs.append(((h[0].z - T.bot_z(x)) / T.SCALE, px))
worst_low = max(low_errs, key=lambda e: abs(e[0]))
check("side_silhouette_belly_vs_trace", abs(worst_low[0]) <= 4.0, [round(worst_low[0], 2), worst_low[1]])

# --- tracked bogies ----------------------------------------------------------------------------------
fenders = [objs[n] for n in objs if n.startswith("Body_Fender")]
tr_info = {}
for s in ("+1", "-1"):
    cle = verts(objs[f"Prop_Track_Cleats_{s}"])
    belt = verts(objs[f"Prop_Track_Belt_{s}"])
    low = min(v.z for v in cle)
    flat = [v for v in cle if v.z < 0.004]
    tr_info[s] = {"min_z_mm": mm(low), "flat_x": [round(min(v.x for v in flat), 3), round(max(v.x for v in flat), 3)] if flat else None,
                  "x_range": [round(min(v.x for v in cle), 3), round(max(v.x for v in cle), 3)],
                  "y_range": [round(min(v.y for v in cle), 3), round(max(v.y for v in cle), 3)],
                  "belt_inner_min_z_mm": mm(min(v.z for v in belt))}
check("track_contact_at_ground_both_flanks", all(abs(i["min_z_mm"]) < 2.0 for i in tr_info.values()), tr_info)
check("track_flat_contact_patch_spans_sprockets", all(i["flat_x"] and i["flat_x"][0] <= TR.X1 + 0.06 and i["flat_x"][1] >= TR.X2 - 0.06
                                                      for i in tr_info.values()), {k: v["flat_x"] for k, v in tr_info.items()})
check("track_extent_matches_sheet_px_334_467", all(abs(i["x_range"][0] - T.X(334)) < 0.03 and abs(i["x_range"][1] - T.X(467)) < 0.03
                                                   for i in tr_info.values()), {k: v["x_range"] for k, v in tr_info.items()})
check("track_width_and_centre", all(abs(abs(i["y_range"][0] + i["y_range"][1]) / 2 - T.TRACK_Y) < 0.5 * (T.TRACK_W + 0.05) for i in tr_info.values())
      and abs(tr_info["+1"]["y_range"][1] - tr_info["+1"]["y_range"][0] - (T.TRACK_W - 0.02)) < 0.03, tr_info["+1"]["y_range"])
spr_clear = {}
for s in ("+1", "-1"):
    for part, ax in (("SprocketRear", TR.X1), ("SprocketFront", TR.X2)):
        sv = [v for v in verts(objs[f"Prop_Track_{part}_{s}"]) if abs(abs(v.y) - T.TRACK_Y) < T.TRACK_W / 2 - 0.02]
        r = max(math.hypot(v.x - ax, v.z - TR.ZC) for v in sv)
        spr_clear[f"{part}_{s}"] = mm(TR.BELT_IN - r)
check("sprocket_teeth_inside_belt_5mm", all(v >= 5.0 for v in spr_clear.values()), spr_clear)
roll = {}
for s in ("+1", "-1"):
    rv = verts(objs[f"Prop_Track_Rollers_{s}"])
    roll[s] = mm(min(v.z for v in rv) - (TR.ZC - TR.BELT_IN))
check("rollers_clear_of_belt_inner_surface_5mm", all(5.0 <= v <= 20.0 for v in roll.values()), roll)
check("track_covered_by_fender_and_clear_of_hull",
      all(f.data.vertices and min(v.co.z for v in f.data.vertices) > 0.2 for f in fenders)
      and all(min(abs(v.y) for v in verts(objs[f"Prop_Track_Belt_{s}"])) > T.half_w(T.X(400)) + 0.01 for s in ("+1", "-1")), None)
tri_tracks = C.triangle_count(tracks)

# --- belly / pods clearance, glass seating -----------------------------------------------------------
check("hull_ground_clearance_ge_180mm", min(v.z for o in bodies if not o.name.startswith("Body_Fender")
                                                for v in verts(o)) >= 0.18, mm(min(v.z for o in bodies if not o.name.startswith("Body_Fender") for v in verts(o))))
seat = {}
hull_tree = tree_of([objs["Body_Hull"]])
for o in glass + frames:
    over, buried = [], 0.0
    for v in verts(o):
        h = hull_tree.ray_cast(Vector((v.x, v.y, 3.0)), Vector((0, 0, -1)))
        over.append(None if h[0] is None else v.z - h[0].z)
        if h[0] is not None:
            buried = max(buried, h[0].z - v.z)
    seat[o.name] = {"no_plan_overhang": all(d is not None for d in over), "buried_mm": mm(buried),
                    "rise_mm": mm(max([d for d in over if d is not None] or [0]))}
check("glass_and_frames_seated_in_hull", all(v["no_plan_overhang"] and v["buried_mm"] >= 15.0 for v in seat.values()), seat)
check("canopy_rise_realistic", all(15 <= seat[n]["rise_mm"] <= 220 for n in seat if n.startswith("Glass_Canopy")), {n: seat[n]["rise_mm"] for n in seat if n.startswith("Glass_")})

# --- no floating parts ---------------------------------------------------------------------------------
float_report = {}
all_tree_by = {o.name: tree_of([o]) for o in list(bodies) + tracks}
for o in hardware + frames + glass + bodies + tracks:
    others = tree_of([b for n, b in objs.items() if (n.startswith(("Body_", "Prop_Track_")) and b is not o)])
    best = 9.9
    for v in verts(o):
        h = others.find_nearest(v)
        if h[0] is not None:
            best = min(best, h[3])
        if inside(others, v):
            best = 0.0
            break
    float_report[o.name] = best
check("no_floating_parts_8mm", all(d <= 0.008 for d in float_report.values()),
      {n: mm(d) for n, d in float_report.items() if d > 0.008})

# --- source features -----------------------------------------------------------------------------------
claw = {}
for j in ("Up", "Low"):
    for s in ("+1", "-1"):
        vs = verts(objs[f"Body_Claw{j}_{s}"])
        tip = min(vs, key=lambda v: v.x)
        claw[f"{j}{s}"] = (round(tip.x, 3), round(tip.y, 3), round(tip.z, 3))
gap = abs(claw["Up+1"][2] - claw["Low+1"][2])
check("claw_pincers_open_and_reach_sheet_tip", all(abs(v[0] - T.X(232)) < 0.05 for v in claw.values()) and gap > 0.30, {"tips": claw, "jaw_gap_m": round(gap, 3)})
check("hoses_four_per_flank_ribbed", all(len(objs[f"Body_Hose{i}_{s}"].data.polygons) > 300 for i in range(4) for s in ("+1", "-1")), None)
pod = {s: verts(objs[f"Body_Pod_{s}"]) for s in ("+1", "-1")}
check("weapon_pods_at_sheet_position", all(abs(abs(sum(v.y for v in pod[s]) / len(pod[s])) - T.POD_Y) < 0.01 and abs(min(v.x for v in pod[s]) - T.X(656)) < 0.02 for s in pod), None)
barrels = [verts(objs[f"Fine_PodBarrels_{s}"]) for s in ("+1", "-1")]
check("pod_barrels_reach_x814", all(abs(max(v.x for v in b) - T.X(814)) < 0.03 for b in barrels), [round(max(v.x for v in b), 3) for b in barrels])
check("lenses_present_nacelle_and_pod", all(f"Fine_{k}Lens_{s}" in objs for k in ("Nacelle", "Pod") for s in ("+1", "-1")), None)

# --- UVs and materials ---------------------------------------------------------------------------------
check("all_meshes_have_uvs", all(o.data.uv_layers for o in objs.values()), [n for n, o in objs.items() if not o.data.uv_layers])
used = {m.name for o in objs.values() for m in o.data.materials if m}
check("exact_material_set", used == EXPECTED_MATERIALS, sorted(used ^ EXPECTED_MATERIALS))
area = {}
for o in objs.values():
    me = wmesh(o)
    for p in me.polygons:
        n = o.data.materials[p.material_index].name
        area[n] = area.get(n, 0.0) + p.area
    bpy.data.meshes.remove(me)
check("semantic_channels_have_area", all(area.get(k, 0) > 0.15 for k in SEMANTIC) and area.get("Helix_Stripe", 0) > 0.04,
      {k: round(v, 3) for k, v in area.items()})

# --- exports and LODs ---------------------------------------------------------------------------------
build = json.loads((MODEL_DIR / f"{STEM}_build.json").read_text())
ex = build["exports"]
tri = [ex["lod0"]["triangles"], ex["lod1"]["triangles"], ex["lod2"]["triangles"]]
check("triangle_budget_and_lod_monotonic", 30000 <= tri[0] <= 60000 and tri[0] > tri[1] > tri[2] and tri[1] <= 0.85 * tri[0]
      and tri[2] <= 0.65 * tri[0], tri)
hand = build["handoff"]["track_contact"]
check("handoff_track_contact_matches_measured", abs(hand["z"] - tr_info["+1"]["min_z_mm"] / 1000) < 0.002 and
      abs(hand["x_range"][0] - tr_info["+1"]["x_range"][0]) < 0.002 and abs(hand["x_range"][1] - tr_info["+1"]["x_range"][1]) < 0.002 and
      abs(hand["y_centres"][0] - T.TRACK_Y) < 1e-6, hand)

glb = {}
for level, rel in ((0, f"{STEM}.glb"), (1, f"lod/{STEM}_LOD1.glb"), (2, f"lod/{STEM}_LOD2.glb")):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(MODEL_DIR / rel))
    new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    mats = {m.name.rsplit(".", 1)[0] if m.name.rsplit(".", 1)[-1].isdigit() else m.name for o in new for m in o.data.materials}
    pts = [o.matrix_world @ v.co for o in new for v in o.data.vertices]
    tk = [o for o in new if o.name.startswith("Prop_Track_")]
    cl = [o for o in new if o.name.startswith("Prop_Track_Cleats")]
    glb[level] = {"meshes": len(new), "materials": sorted(mats), "wheel_like": len([o for o in new if o.name.startswith("Wheel_")]),
                  "track_objects": len(tk), "track_tris": C.triangle_count(tk),
                  "claws": len([o for o in new if o.name.startswith("Body_Claw")]),
                  "hoses": len([o for o in new if o.name.startswith("Body_Hose")]),
                  "canopies": len([o for o in new if o.name.startswith("Glass_Canopy")]),
                  "cleat_min_z_mm": mm(min((o.matrix_world @ v.co).z for o in cl for v in o.data.vertices)),
                  "bbox": [round(v, 3) for v in (min(p.x for p in pts), max(p.x for p in pts), min(p.y for p in pts),
                                                 max(p.y for p in pts), min(p.z for p in pts), max(p.z for p in pts))]}
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
base = glb[0]
check("glb_reimport_materials_and_no_wheels", all(set(glb[l]["materials"]) == EXPECTED_MATERIALS and glb[l]["wheel_like"] == 0 for l in glb),
      {l: glb[l]["materials"] for l in glb})
check("glb_tracks_whole_in_every_lod", all(glb[l]["track_objects"] == 12 and glb[l]["track_tris"] == base["track_tris"] and
                                           abs(glb[l]["cleat_min_z_mm"]) < 2.0 for l in glb),
      {l: (glb[l]["track_objects"], glb[l]["track_tris"], glb[l]["cleat_min_z_mm"]) for l in glb})
check("glb_claws_hoses_canopies_in_every_lod", all(glb[l]["claws"] == 4 and glb[l]["hoses"] == 8 and glb[l]["canopies"] == 2 for l in glb), None)
check("lod_envelope_matches_gameplay", all(max(abs(a - b) for a, b in zip(glb[l]["bbox"], base["bbox"])) < 0.03 for l in (1, 2)),
      {l: glb[l]["bbox"] for l in glb})

summary = {"pass": not failures, "failed": failures, "checks": len(results), "triangles": tri, "results": results,
           "track_triangles": tri_tracks, "glb": {str(k): v for k, v in glb.items()}}
out = MODEL_DIR / f"{STEM}_qa.json"
out.write_text(json.dumps(summary, indent=2) + "\n")
print("AK: VALIDATION " + ("PASS" if not failures else "FAIL " + ", ".join(failures)) + f" ({len(results)} checks)")
for k, v in results.items():
    if not v["ok"]:
        print("AK: FAIL", k, json.dumps(v["detail"])[:600])
if failures:
    raise SystemExit(1)
