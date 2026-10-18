"""Numeric validation of the Knifeedge blueprint model (native source + exported GLBs).

Run: ak-blender tools/vehicle_pipeline/blender/validate_knifeedge.py \
         tools/vehicle_pipeline/blender/knifeedge_blueprint.blend
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
import knifeedge_cage as K  # noqa: E402
import knifeedge_core as C  # noqa: E402
import knifeedge_trace as T  # noqa: E402

MODEL_DIR = ROOT / "godot/assets/vehicles/models/knifeedge"
STEM = "knifeedge_blueprint"
SEMANTIC = {"Knifeedge_Paint", "Knifeedge_Secondary", "Knifeedge_Stripe"}
EXPECTED_MATERIALS = SEMANTIC | {
    "Knifeedge_Glass", "Knifeedge_Rubber", "Knifeedge_Steel", "Knifeedge_Iron", "Knifeedge_Lamp",
}
# Intentional authored asymmetry: the one steering wheel and its column (end-B elevation shows it on one seat only).
# Fine_ShockSpring: a helix is chiral (left/right springs are mirrored only in position); Fine_Badge sits on the
# tessellated hood crease (4 mm tessellation difference).
ASYMMETRIC_ALLOWED = ("Fine_SteeringWheel", "Fine_SteeringColumn", "Fine_ShockSpring", "Fine_Badge")
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
wheels = [o for n, o in objs.items() if n.startswith(("Wheel_Truck_", "Wheel_Coupe_"))]
glass = [o for n, o in objs.items() if n.startswith("Glass_")]
hardware = [o for n, o in objs.items() if n.startswith(("Fine_", "Trim_"))]
props = [o for n, o in objs.items() if n.startswith("Prop_")]
cage = [o for o in bodies if o.name.startswith("Body_Cage")]


def world_mesh(obj):
    return C.evaluated_mesh(obj)


def union_tree(group):
    verts, faces, off = [], [], 0
    for o in group:
        me = world_mesh(o)
        verts += [v.co.copy() for v in me.vertices]
        faces += [tuple(i + off for i in p.vertices) for p in me.polygons]
        off += len(me.vertices)
        bpy.data.meshes.remove(me)
    return BVHTree.FromPolygons(verts, faces)


def all_vertices(group):
    pts = []
    for o in group:
        me = world_mesh(o)
        pts += [v.co.copy() for v in me.vertices]
        bpy.data.meshes.remove(me)
    return pts


def ray(tree, origin, direction):
    return tree.ray_cast(Vector(origin), Vector(direction))


covered = {o.name for o in bodies + wheels + glass + hardware + props}
check("every_mesh_in_a_validated_group", set(objs) == covered, sorted(set(objs) - covered))

# --- closed, positive-volume masses ---------------------------------------------------------------------
bad, vol_bad = {}, {}
for o in bodies + wheels:
    me = world_mesh(o)
    bm = bmesh.new()
    bm.from_mesh(me)
    open_edges = sum(1 for e in bm.edges if not e.is_manifold)
    vol = bm.calc_volume(signed=True)
    bm.free()
    bpy.data.meshes.remove(me)
    if open_edges:
        bad[o.name] = open_edges
    if vol <= 0:
        vol_bad[o.name] = round(vol, 6)
check("main_masses_closed_manifold", not bad, bad)
check("main_masses_positive_volume", not vol_bad, vol_bad)
bad = {}
for o in glass + hardware + props:
    me = world_mesh(o)
    bm = bmesh.new()
    bm.from_mesh(me)
    n = sum(1 for e in bm.edges if not e.is_manifold)
    bm.free()
    bpy.data.meshes.remove(me)
    if n:
        bad[o.name] = n
check("glass_hardware_props_closed", not bad, bad)

# --- mirror symmetry of the whole assembly ----------------------------------------------------------------
pts = all_vertices([o for n, o in objs.items() if not n.startswith(ASYMMETRIC_ALLOWED)])
kd = KDTree(len(pts))
for i, p in enumerate(pts):
    kd.insert(p, i)
kd.balance()
errs = sorted((kd.find(Vector((p.x, -p.y, p.z)))[0] - Vector((p.x, -p.y, p.z))).length for p in pts)
check("assembly_mirror_symmetry", errs[-1] < 0.002, {"max_mm": mm(errs[-1]), "p99_mm": mm(errs[int(len(errs) * 0.99)]),
                                                   "vertices": len(pts), "intentional_asymmetric": list(ASYMMETRIC_ALLOWED)})

# --- silhouette and extents vs the traced sheet -------------------------------------------------------------
shell_tree = union_tree([objs["Body_Shell"]])
top_dev, bot_dev, half_dev = [], [], []
for px in range(612, 755, 6):
    x = T.X(px)
    h = ray(shell_tree, (x, 0.02, 3.0), (0, 0, -1))
    if h[0] is not None:
        top_dev.append(abs(h[0].z - T.shell_top_z(px)) / T.SCALE)
for px in range(460, 740, 8):
    x = T.X(px)
    h = ray(shell_tree, (x, 0.02, -1.0), (0, 0, 1))
    if h[0] is not None:
        bot_dev.append(abs(h[0].z - T.shell_bot_z(px)) / T.SCALE)
for px in list(range(470, 604, 8)) + list(range(716, 750, 8)):
    x = T.X(px)
    ys = [hh[0].y for z in (0.28, 0.34, 0.40) if (hh := ray(shell_tree, (x, 2.0, z), (0, -1, 0)))[0] is not None]
    if ys:
        half_dev.append(abs(max(ys) - T.shell_half(px)) / T.SCALE)
check("shell_top_vs_trace_px", top_dev and max(top_dev) < 4.0, {"max_px": round(max(top_dev), 2), "n": len(top_dev)})
check("shell_sill_vs_trace_px", bot_dev and max(bot_dev) < 4.0, {"max_px": round(max(bot_dev), 2), "n": len(bot_dev)})
check("shell_halfwidth_vs_trace_px", half_dev and max(half_dev) < 4.0, {"max_px": round(max(half_dev), 2), "n": len(half_dev)})
nowheel = [o for o in objs.values() if not o.name.startswith("Wheel_")]
allpts = all_vertices(nowheel)
xs = [p.x for p in allpts]
check("overall_length_vs_trace", abs(min(xs) - T.X(288)) < 0.06 and abs(max(xs) - T.X(756)) < 0.04,
      {"min_x": round(min(xs), 4), "max_x": round(max(xs), 4), "trace_min": round(T.X(288), 4), "trace_max": round(T.X(756), 4)})
zmax = max(p.z for p in allpts)
check("overall_height_vs_trace", abs(zmax - T.Z(46)) < 0.05, {"max_z": round(zmax, 4), "trace_light_bar_top": round(T.Z(46), 4)})
cage_pts = all_vertices(cage)
roof_z = max(p.z for p in cage_pts)
check("cage_roof_height_vs_trace", abs(roof_z - (T.Z(66) + K.R_MAIN)) < 0.01, {"roof_z": round(roof_z, 4), "trace": round(T.Z(66), 4)})
rear_slope = [p for p in cage_pts if p.x < T.X(330) and p.z > 0.8]
check("cage_rear_slope_vs_trace_px", all(abs(p.z - T.Z(T.slope_py(T.PX(p.x)))) / T.SCALE < 6.0 for p in rear_slope if abs(p.y) > 0.5 and T.PX(p.x) < 450 and p.z > T.Z(T.slope_py(T.PX(p.x))) - 0.0),
      {"samples": len(rear_slope)})
tail = [p for p in allpts if p.x < T.X(300)]
check("tail_hoop_spans_trace_height", tail and abs(max(p.z for p in tail) - T.Z(108)) < 0.05 and abs(min(p.z for p in tail) - T.Z(159)) < 0.06,
      {"zmax": round(max(p.z for p in tail), 3), "zmin": round(min(p.z for p in tail), 3)})

roof_pts = all_vertices([objs["Body_CageRoof"]])
pillar_gap = {}
for name, px in (("A", 615), ("B", 466)):
    for s in (-1, 1):
        low = [p for p in roof_pts if abs(p.x - T.X(px)) < 0.04 and s * p.y > 0.55 and p.z < 1.2]
        foot = min(low, key=lambda p: p.z)
        top = ray(shell_tree, (foot.x, foot.y, 3.0), (0, 0, -1))[0]
        pillar_gap[f"{name}{s:+d}"] = mm(foot.z - top.z) if top is not None else None
check("cage_pillars_planted_in_shell", all(g is not None and g <= 0.0 for g in pillar_gap.values()), pillar_gap)

# --- wheels: names, hubs, radii, ground, clearance -----------------------------------------------------------------
tires = [o for o in wheels if "_Tire_" in o.name]


def wheel_key(name):
    parts = name.split("_")
    side = next(p for p in parts if p in ("+1", "-1"))
    return parts[1] + side


groups = {}
for w in wheels:
    groups.setdefault(wheel_key(w.name), []).append(w.name)
check("one_tire_per_wheel", len(groups) == 4 and all(sum(1 for n in v_ if "_Tire_" in n) == 1 for v_ in groups.values()),
      {k: sum(1 for n in v_ if "_Tire_" in n) for k, v_ in groups.items()})
wheel_info = {}
arch_state = {}
arch_tree = shell_tree
chassis_tree = union_tree([o for o in objs.values() if not o.name.startswith("Wheel_") and not o.name.startswith("Fine_Axle")
                           and not o.name.startswith("Glass_")])
for t in tires:
    end = "truck" if "Truck" in t.name else "coupe"
    side = 1 if t.name.endswith("+1") else -1
    hub = Vector((T.WHEEL_X[end], side * T.TRACK_Y[end], T.WHEEL_R[end]))
    me = world_mesh(t)
    radii = [math.hypot(v.co.x - hub.x, v.co.z - hub.z) for v in me.vertices]
    zmin = min(v.co.z for v in me.vertices)
    ymin, ymax = min(v.co.y for v in me.vertices), max(v.co.y for v in me.vertices)
    arch = None
    if end == "coupe":
        # tyre must be outside the solid shell: no surface intersections and every vertex has an even ray parity
        overlaps = len(C.bvh_of(me).overlap(arch_tree))
        inside = 0
        for v in list(me.vertices)[::7]:
            origin, hits = Vector(v.co), 0
            while hits < 12:
                h = arch_tree.ray_cast(origin + Vector((0, 0, 1e-5)), Vector((0, 0, 1)))
                if h[0] is None:
                    break
                hits += 1
                origin = h[0] + Vector((0, 0, 1e-4))
            inside += hits % 2
        arch = min(arch_tree.find_nearest(v.co)[3] for v in me.vertices) if not overlaps and not inside else -1.0
        arch_state[t.name] = {"overlaps": overlaps, "inside_vertices": inside}
    wtree = C.bvh_of(me)
    clr = min(wtree.find_nearest(v)[3] for v in all_vertices([o for o in objs.values() if not o.name.startswith("Wheel_")
                                                              and not o.name.startswith("Fine_Axle")
                                                              and abs(o.location.y) < 3 and o.name.startswith(("Fine_Arm", "Fine_Drive", "Fine_Shock", "Prop_Upright"))
                                                              and (o.name.endswith(f"{side:+d}") or o.name[-2:-1] == "_" or "F" == o.name[-1] or "R" == o.name[-1])
                                                              and (("+" if side > 0 else "-") in o.name)]))
    bpy.data.meshes.remove(me)
    wheel_info[t.name] = {"origin_error_mm": mm((t.location - hub).length), "radius_mm": mm(max(radii)),
                          "expected_radius_mm": mm(T.WHEEL_R[end]), "lowest_z_mm": mm(zmin), "width_mm": mm(ymax - ymin),
                          "arch_clearance_mm": mm(arch) if arch is not None else None, "suspension_clearance_mm": mm(clr)}
check("wheel_tire_origins_at_hubs", all(v["origin_error_mm"] < 0.5 for v in wheel_info.values()), wheel_info)
check("wheel_tire_radii_match_display", all(abs(v["radius_mm"] - v["expected_radius_mm"]) < 1.5 for v in wheel_info.values()), None)
check("wheel_tires_touch_ground_plane_6mm", all(-1.0 < v["lowest_z_mm"] < 6.0 for v in wheel_info.values()),
      {k: v["lowest_z_mm"] for k, v in wheel_info.items()})
check("supercar_tyres_outside_shell_with_arch_clearance_50mm", all(v["arch_clearance_mm"] >= 50.0 for v in wheel_info.values() if v["arch_clearance_mm"] is not None),
      {"clearance_mm": {k: v["arch_clearance_mm"] for k, v in wheel_info.items() if v["arch_clearance_mm"] is not None},
       "state": arch_state})
check("suspension_clears_tires_5mm", all(v["suspension_clearance_mm"] >= 5.0 for v in wheel_info.values()),
      {k: v["suspension_clearance_mm"] for k, v in wheel_info.items()})
origin_bad = []
for w in wheels:
    tire = next(t for t in tires if wheel_key(t.name) == wheel_key(w.name))
    if (w.location - tire.location).length > 1e-4:
        origin_bad.append(w.name)
check("all_wheel_parts_share_hub_origin", not origin_bad, origin_bad)
counts = {}
for w in wheels:
    key = w.name.split("_")[1] + w.name.split("_")[2]
    counts[key] = counts.get(key, 0) + 1
check("wheel_part_counts", counts == {"TruckTire": 2, "TruckRim": 2, "TruckHub": 2, "TruckSpoke": 12,
                                      "CoupeTire": 2, "CoupeRim": 2, "CoupeHub": 2, "CoupeSpoke": 20,
                                      "CoupeBrake": 2, "CoupeCaliper": 2}, counts)
rim_ok = True
for w in wheels:
    if "_Rim_" in w.name:
        end = "truck" if "Truck" in w.name else "coupe"
        me = world_mesh(w)
        rr = max(math.hypot(v.co.x - w.location.x, v.co.z - w.location.z) for v in me.vertices)
        bpy.data.meshes.remove(me)
        rim_ok &= rr < T.WHEEL_R[end] - 0.04
check("rims_inside_tires", rim_ok, None)
check("wheels_are_exactly_four", len(tires) == 4 and sum(1 for n in objs if "_Tire_" in n) == 4, None)

# --- extra machinery: decorative Prop_* nodes, never wheels ------------------------------------------------------
need = ["Prop_Engine_Block", "Prop_Transaxle", "Prop_Exhaust_Muffler", "Prop_Exhaust_Tailpipe"] + [
    f"{p}_{s}" for p in ("Prop_Engine_Head", "Prop_Exhaust_Header", "Prop_Upright") for s in ("+1", "-1")]
check("prop_machinery_present_paired", all(n in objs for n in need), [n for n in need if n not in objs])
check("prop_not_wheel_named", not any("Wheel" in n for n in objs if n.startswith("Prop_")), None)
base_z = T.FLOOR_TOP_Z - 0.008
blk = world_mesh(objs["Prop_Engine_Block"])
blk_lo = min(v.co.z for v in blk.vertices)
bpy.data.meshes.remove(blk)
check("engine_sits_on_floor_pan_3mm", abs(blk_lo - base_z) < 0.012, {"block_bottom_z": round(blk_lo, 4), "floor_top_z": round(T.FLOOR_TOP_Z, 4)})
eng = all_vertices([objs["Prop_Engine_Block"]])
check("engine_vs_trace_box", abs(min(p.x for p in eng) - T.X(T.PX(T.X(437.0)) - 0.28 / T.SCALE)) < 0.005
      and max(p.z for p in all_vertices([objs["Prop_Exhaust_Muffler"]])) < T.Z(125) + 0.02,
      {"block_x": [round(min(p.x for p in eng), 3), round(max(p.x for p in eng), 3)], "trace_px": [403, 475]})

# --- glass: seated in the cage, clear of the shell, full coverage ---------------------------------------------------
cage_tree = union_tree(cage)
gl_report = {}
for g in glass:
    me = world_mesh(g)
    d_cage = [cage_tree.find_nearest(v.co)[3] for v in me.vertices]
    d_shell = [shell_tree.find_nearest(v.co)[3] for v in me.vertices]
    gt = C.bvh_of(me)
    crossing = len(gt.overlap(shell_tree))
    bpy.data.meshes.remove(me)
    gl_report[g.name] = {"min_cage_mm": mm(min(d_cage)), "min_shell_mm": mm(min(d_shell)), "shell_overlaps": crossing}
check("glass_seated_in_cage_tubes_6mm", all(v["min_cage_mm"] <= 6.0 for v in gl_report.values()),
      {k: v["min_cage_mm"] for k, v in gl_report.items()})
check("glass_never_crosses_shell", all(v["shell_overlaps"] == 0 for v in gl_report.values()),
      {k: v["shell_overlaps"] for k, v in gl_report.items() if v["shell_overlaps"]})
check("glass_clear_of_shell_surface", all(v["min_shell_mm"] > 0.0 for v in gl_report.values()), {k: v["min_shell_mm"] for k, v in gl_report.items()})
check("glass_set", sorted(gl_report) == ["Glass_Roof_+1", "Glass_Roof_-1", "Glass_Windshield"], sorted(gl_report))

full_tree = union_tree([o for o in objs.values() if not o.name.startswith("Wheel_")])
glass_tree = union_tree(glass)
holes, samples = [], 0


def covered(origin, direction):
    hg = glass_tree.ray_cast(Vector(origin), Vector(direction))
    ha = full_tree.ray_cast(Vector(origin), Vector(direction))
    return hg[0] is not None and ha[0] is not None and (ha[0] - hg[0]).length < 0.0015


for px in range(486, 552, 8):          # roof panels, from above
    for y in (0.16, 0.26, 0.36, 0.46, 0.50):
        for s in (-1, 1):
            samples += 1
            if not covered((T.X(px), s * y, 3.0), (0, 0, -1)):
                holes.append(("Roof", s, px, y))
top_c, base_c = Vector(K.pt(562, 66, 0)), Vector(K.pt(615, T.BASE_PY, 0))
wn = (base_c - top_c).cross(Vector((0, 1, 0))).normalized()
if wn.x < 0:
    wn = -wn
for i in range(1, 8):
    for j in range(-5, 6):
        t = i / 8
        c = top_c.lerp(base_c, t)
        half = (K.Y_ROOF + (K.Y_BASE - K.Y_ROOF) * t) - 0.05
        p = c + Vector((0, half * j / 5, 0))
        samples += 1
        if not covered(p + wn * 1.5, -wn):
            holes.append(("Windshield", i, j))
check("glass_covers_whole_openings", not holes, {"samples": samples, "holes": holes[:12]})

# --- hardware clearance: nothing pierces glass or wheels ----------------------------------------------------------
pierce = {}
for o in hardware + props + cage:
    me = world_mesh(o)
    n = len(C.bvh_of(me).overlap(glass_tree))
    bpy.data.meshes.remove(me)
    if n:
        pierce[o.name] = n
check("hardware_never_pierces_glass_beyond_frame_tubes", all(k.startswith("Body_Cage") for k in pierce), pierce)
wheel_tree = union_tree(wheels)
touch = {}
for o in list(objs.values()):
    if o.name.startswith(("Wheel_", "Fine_Axle")):
        continue
    me = world_mesh(o)
    n = len(C.bvh_of(me).overlap(wheel_tree))
    bpy.data.meshes.remove(me)
    if n:
        touch[o.name] = n
check("nothing_but_axles_touches_wheels", not touch, touch)

# --- attachment: every part must chain (parts within 12 mm of each other) back to Body_Shell ----------------------------
g_verts, g_faces, g_owner = [], [], []
for o in objs.values():
    me = world_mesh(o)
    off = len(g_verts)
    g_verts += [v.co.copy() for v in me.vertices]
    g_faces += [tuple(i + off for i in p.vertices) for p in me.polygons]
    g_owner += [o.name] * len(me.polygons)
    bpy.data.meshes.remove(me)
global_tree = BVHTree.FromPolygons(g_verts, g_faces)
adj = {n: set() for n in objs}
for o in objs.values():
    me = world_mesh(o)
    for v in me.vertices:
        for _loc, _nor, idx, _d in global_tree.find_nearest_range(v.co, 0.012):
            other = g_owner[idx]
            if other != o.name:
                adj[o.name].add(other)
                adj[other].add(o.name)
    bpy.data.meshes.remove(me)


def reach():
    seen, todo = {"Body_Shell"}, ["Body_Shell"]
    while todo:
        for nb in adj[todo.pop()]:
            if nb not in seen:
                seen.add(nb)
                todo.append(nb)
    return seen


# parts that interpenetrate (a bolt sunk into a plate, an axle through a hub) are chained too
trees = {}
boxes = {}
for n, o in objs.items():
    me = world_mesh(o)
    trees[n] = C.bvh_of(me)
    boxes[n] = (Vector([min(c.co[i] for c in me.vertices) for i in range(3)]) - Vector((0.012,) * 3),
                Vector([max(c.co[i] for c in me.vertices) for i in range(3)]) + Vector((0.012,) * 3))
    bpy.data.meshes.remove(me)
names_sorted = sorted(objs)
for i, a in enumerate(names_sorted):
    for b in names_sorted[i + 1:]:
        (alo, ahi), (blo, bhi) = boxes[a], boxes[b]
        if all(alo[k] <= bhi[k] and blo[k] <= ahi[k] for k in range(3)) and trees[a].overlap(trees[b]):
            adj[a].add(b)
            adj[b].add(a)
seen = reach()
for name in sorted(set(objs) - seen):
    # thin plates have few vertices: also accept another part's vertex within 12 mm of this surface
    me = world_mesh(objs[name])
    own_tree = C.bvh_of(me)
    lo = Vector([min(c.co[i] for c in me.vertices) for i in range(3)]) - Vector((0.012,) * 3)
    hi = Vector([max(c.co[i] for c in me.vertices) for i in range(3)]) + Vector((0.012,) * 3)
    for other in objs.values():
        if other.name == name:
            continue
        ome = world_mesh(other)
        for ov in ome.vertices:
            p = ov.co
            if all(lo[i] <= p[i] <= hi[i] for i in range(3)) and own_tree.find_nearest(p)[3] <= 0.012:
                adj[name].add(other.name)
                adj[other.name].add(name)
                break
        bpy.data.meshes.remove(ome)
    bpy.data.meshes.remove(me)
seen = reach()
floaters = {n: "not chained to Body_Shell within 12 mm" for n in sorted(set(objs) - seen)}
check("every_part_chained_to_shell_within_12mm", not floaters, floaters)
spring_hits = {}
for o in objs.values():
    if o.name.startswith(("Fine_ShockSpring", "Fine_ShockBody")):
        me = world_mesh(o)
        n = len(C.bvh_of(me).overlap(cage_tree))
        bpy.data.meshes.remove(me)
        if n:
            spring_hits[o.name] = n
check("shocks_clear_of_cage_tubes", not spring_hits, spring_hits)
floor_tree = union_tree([objs["Body_Floor"]])
feet = {}
for p in all_vertices([objs["Body_CageRear"]]):
    if p.z < 0.36:
        d_ = floor_tree.find_nearest(p)[3]
        if d_ > 0.03:
            feet[f"{p.x:.2f},{p.y:.2f},{p.z:.2f}"] = mm(d_)
check("rear_truss_feet_land_on_floor_pan", not feet, dict(list(feet.items())[:8]))
vent_gap = {}
for n in objs:
    if n.startswith("Fine_HoodVent"):
        worst = 0.0
        for p in all_vertices([objs[n]]):
            h = ray(shell_tree, (p.x, p.y, 3.0), (0, 0, -1))[0]
            worst = max(worst, min(abs(p.z - (h.z + 0.010)), abs(p.z - (h.z - 0.004))))
        vent_gap[n] = mm(worst)
check("hood_vents_conform_to_hood_3mm", all(g < 3.0 for g in vent_gap.values()), vent_gap)
lens_bad = {}
for n, o in objs.items():
    housing = None
    if n.startswith("Fine_TailLamp_"):
        housing = objs["Fine_TailBezel_" + n.split("_")[2]]
    elif n.startswith("Fine_RoofLamp_"):
        housing = objs["Trim_LightBar"]
    elif n.startswith("Fine_LedStrip_"):
        housing = objs["Body_Shell"]
    if housing is not None:
        ht = union_tree([housing])
        me = world_mesh(o)
        dist = [ht.find_nearest(v.co)[3] for v in me.vertices]
        bpy.data.meshes.remove(me)
        reach = 0.040 if n.startswith(("Fine_TailLamp_", "Fine_RoofLamp_")) else 0.016  # lens protrusion
        if min(dist) > 0.006 or max(dist) > reach:
            lens_bad[n] = [mm(min(dist)), mm(max(dist))]
check("lamps_seated_on_housings", not lens_bad, lens_bad)

# --- UV / materials ----------------------------------------------------------------------------------------------------------
no_uv = [n for n, o in objs.items() if not o.data.uv_layers]
mat_names = {m.name for o in objs.values() for m in o.data.materials if m is not None}
empty_slots = [n for n, o in objs.items() if any(m is None for m in o.data.materials)]
bad_idx = [n for n, o in objs.items() if any(p.material_index >= len(o.data.materials) for p in o.data.polygons)]
used = {o.data.materials[p.material_index].name for o in objs.values() for p in o.data.polygons
        if p.material_index < len(o.data.materials) and o.data.materials[p.material_index] is not None}
check("uv_complete", not no_uv, no_uv[:10])
check("materials_exact_set", mat_names == EXPECTED_MATERIALS and not bad_idx and not empty_slots and SEMANTIC <= used,
      {"extra": sorted(mat_names - EXPECTED_MATERIALS), "missing": sorted(EXPECTED_MATERIALS - mat_names),
       "unused_semantic": sorted(SEMANTIC - used)})

# --- exports and LODs ---------------------------------------------------------------------------------------------------------------
build = json.loads((MODEL_DIR / f"{STEM}_build.json").read_text())
ex = build["exports"]
tri = [ex["lod0"]["triangles"], ex["lod1"]["triangles"], ex["lod2"]["triangles"]]
check("triangle_budget_and_lod_monotonic", 30000 <= tri[0] <= 60000 and tri[0] > tri[1] > tri[2] and tri[1] <= 0.80 * tri[0]
      and tri[2] <= 0.50 * tri[0], tri)
hand = build["handoff"]
meas_r = {"A": next(v["radius_mm"] for k, v in wheel_info.items() if "Coupe" in k) / 1000.0,
          "B": next(v["radius_mm"] for k, v in wheel_info.items() if "Truck" in k) / 1000.0}
check("handoff_display_radii_match_measured", all(abs(hand["display_radii"][e] - meas_r[e]) < 0.002 for e in "AB"), [hand["display_radii"], meas_r])
check("handoff_wheel_centres_match_hubs", all(abs(hand["wheel_centres"]["A"][i] - v) < 1e-4 for i, v in
                                              enumerate((T.WHEEL_X["coupe"], T.TRACK_Y["coupe"], T.WHEEL_R["coupe"])))
      and all(abs(hand["wheel_centres"]["B"][i] - v) < 1e-4 for i, v in
              enumerate((T.WHEEL_X["truck"], T.TRACK_Y["truck"], T.WHEEL_R["truck"]))), hand["wheel_centres"])

glb_report = {}
for level, rel in ((0, f"{STEM}.glb"), (1, f"lod/{STEM}_LOD1.glb"), (2, f"lod/{STEM}_LOD2.glb")):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(MODEL_DIR / rel))
    new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    mats = {m.name.rsplit(".", 1)[0] if m.name.rsplit(".", 1)[-1].isdigit() else m.name for o in new for m in o.data.materials}
    wn_ = [o for o in new if o.name.startswith(("Wheel_Truck_", "Wheel_Coupe_"))]
    tr = [o for o in wn_ if "_Tire_" in o.name]
    prop_n = [o for o in new if o.name.startswith("Prop_")]
    pts = [o.matrix_world @ v.co for o in new for v in o.data.vertices]
    bb = (min(p.x for p in pts), max(p.x for p in pts), min(p.y for p in pts), max(p.y for p in pts),
          min(p.z for p in pts), max(p.z for p in pts))
    tire_r = {o.name: max(math.hypot((o.matrix_world @ v.co).x - o.matrix_world.translation.x,
                                     (o.matrix_world @ v.co).z - o.matrix_world.translation.z) for v in o.data.vertices) for o in tr}
    hubs = {o.name: tuple(round(c, 4) for c in o.matrix_world.translation) for o in tr}
    part_hubs = {o.name: tuple(round(c, 4) for c in o.matrix_world.translation) for o in wn_}
    glb_report[level] = {"meshes": len(new), "materials": sorted(mats), "wheel_objects": len(wn_), "tires": len(tr),
                         "prop_objects": len(prop_n), "bbox": [round(v, 3) for v in bb],
                         "tire_radius_deficit_mm": max(mm((T.WHEEL_R["truck"] if "Truck" in n else T.WHEEL_R["coupe"]) - r)
                                                       for n, r in tire_r.items()),
                         "hubs": hubs, "part_hubs": part_hubs}
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
base = glb_report[0]
LOD_OPTIONAL = set()
check("glb_reimport_counts_and_materials", all(set(glb_report[l]["materials"]) >= EXPECTED_MATERIALS - LOD_OPTIONAL
                                                and set(glb_report[l]["materials"]) <= EXPECTED_MATERIALS and glb_report[l]["tires"] == 4
                                                for l in glb_report), {l: (glb_report[l]["meshes"], glb_report[l]["wheel_objects"]) for l in glb_report})
check("glb_wheel_part_counts_stable", len({glb_report[l]["wheel_objects"] for l in glb_report}) == 1 and base["wheel_objects"] == len(wheels),
      {l: glb_report[l]["wheel_objects"] for l in glb_report})
check("glb_props_preserved_in_all_lods", all(glb_report[l]["prop_objects"] == len(props) for l in glb_report),
      {l: glb_report[l]["prop_objects"] for l in glb_report})
check("lod_envelope_matches_gameplay", all(max(abs(a - b) for a, b in zip(glb_report[l]["bbox"], base["bbox"])) < 0.05 for l in (1, 2)),
      {l: glb_report[l]["bbox"] for l in glb_report})
check("lod_tire_radius_preserved_per_wheel_3mm", all(glb_report[l]["tire_radius_deficit_mm"] < 3.0 for l in glb_report),
      {l: glb_report[l]["tire_radius_deficit_mm"] for l in glb_report})
check("glb_wheel_hubs_at_authored_positions", all(
    abs(h[0] - (T.WHEEL_X["truck"] if "Truck" in n else T.WHEEL_X["coupe"])) < 0.002
    and abs(h[2] - (T.WHEEL_R["truck"] if "Truck" in n else T.WHEEL_R["coupe"])) < 0.002
    and abs(abs(h[1]) - (T.TRACK_Y["truck"] if "Truck" in n else T.TRACK_Y["coupe"])) < 0.002
    for l in glb_report for n, h in glb_report[l]["part_hubs"].items()), base["part_hubs"])

summary = {"pass": not failures, "failed": failures, "checks": len(results), "triangles": tri, "results": results,
           "glb": {str(k): {kk: vv for kk, vv in v.items() if kk not in ("hubs", "part_hubs")} for k, v in glb_report.items()},
           "wheels": wheel_info}
out = MODEL_DIR / f"{STEM}_qa.json"
out.write_text(json.dumps(summary, indent=2) + "\n")
print("AK: VALIDATION " + ("PASS" if not failures else "FAIL " + ", ".join(failures)) + f" ({len(results)} checks)")
for k, v in results.items():
    if not v["ok"]:
        print("AK: FAIL", k, json.dumps(v["detail"])[:600])
if failures:
    raise SystemExit(1)
