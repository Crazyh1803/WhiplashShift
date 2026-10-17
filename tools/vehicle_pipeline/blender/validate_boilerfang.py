"""Numeric validation of the Boilerfang blueprint model (native source + exported GLBs).

Run: ak-blender tools/vehicle_pipeline/blender/validate_boilerfang.py \
         tools/vehicle_pipeline/blender/boilerfang_blueprint.blend
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
import boilerfang_body as B  # noqa: E402
import boilerfang_core as C  # noqa: E402
import boilerfang_trace as T  # noqa: E402

MODEL_DIR = ROOT / "godot/assets/vehicles/models/boilerfang"
STEM = "boilerfang_blueprint"
SEMANTIC = {"Boilerfang_Paint", "Boilerfang_Secondary", "Boilerfang_Stripe"}
EXPECTED_MATERIALS = SEMANTIC | {
    "Boilerfang_Glass", "Boilerfang_Rubber", "Boilerfang_Brass", "Boilerfang_Copper", "Boilerfang_Iron",
    "Boilerfang_Dial", "Boilerfang_Lamp", "Boilerfang_Amber",
}
# Intentional authored asymmetries (none: every part is mirrored by construction).
ASYMMETRIC_ALLOWED = ()
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
frames = [o for n, o in objs.items() if n.startswith("Frame_")]
hardware = [o for n, o in objs.items() if n.startswith(("Fine_", "Trim_"))]
mids = [o for n, o in objs.items() if n.startswith(("Prop_MidDrive_", "Gear_"))]


def world_mesh(obj):
    return C.evaluated_mesh(obj)


def bvh(obj):
    me = world_mesh(obj)
    tree = C.bvh_of(me)
    return tree, me


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


covered = {o.name for o in bodies + wheels + glass + frames + hardware + mids}
check("every_mesh_in_a_validated_group", set(objs) == covered, sorted(set(objs) - covered))

# --- closed, positive-volume main masses ---------------------------------------------------------
bad = {}
vol_bad = {}
for o in bodies + wheels:
    me = world_mesh(o)
    bm = bmesh.new()
    bm.from_mesh(me)
    open_edges = sum(1 for e in bm.edges if not e.is_manifold)
    vol = bm.calc_volume(signed=True)
    bm.free()
    bpy.data.meshes.remove(me)
    # spiked tyre studs are separate shells of the same mesh and wire/spoke bundles are closed prisms
    if open_edges:
        bad[o.name] = open_edges
    if vol <= 0:
        vol_bad[o.name] = round(vol, 6)
check("main_masses_closed_manifold", not bad, bad)
check("main_masses_positive_volume", not vol_bad, vol_bad)
bad = {}
for o in glass + frames + hardware + mids:
    me = world_mesh(o)
    bm = bmesh.new()
    bm.from_mesh(me)
    n = sum(1 for e in bm.edges if not e.is_manifold)
    bm.free()
    bpy.data.meshes.remove(me)
    if n:
        bad[o.name] = n
check("glass_frames_hardware_closed", not bad, bad)

# --- mirror symmetry of the whole assembly --------------------------------------------------------
pts = all_vertices([o for o in objs.values() if not o.name.startswith(ASYMMETRIC_ALLOWED or ("~",))])
kd = KDTree(len(pts))
for i, p in enumerate(pts):
    kd.insert(p, i)
kd.balance()
errs = sorted((kd.find(Vector((p.x, -p.y, p.z)))[0] - Vector((p.x, -p.y, p.z))).length for p in pts)
check("assembly_mirror_symmetry", errs[-1] < 0.002, {"max_mm": mm(errs[-1]), "p99_mm": mm(errs[int(len(errs) * 0.99)]),
                                                   "vertices": len(pts), "intentional_asymmetric": list(ASYMMETRIC_ALLOWED)})

# --- silhouette vs traced tables ------------------------------------------------------------------
mass = [o for o in bodies if o.name in ("Body_Hull", "Body_BoilerBarrel", "Body_ProwSpeedster", "Body_PlowTruck")]
mass_tree = union_tree(mass)
top_dev, sill_dev, half_dev = [], [], []
for px in range(300, 862, 6):
    x = T.X(px)
    zs = [h.z for yv in [i * 0.04 for i in range(0, 15)]
          if (h := mass_tree.ray_cast(Vector((x, yv, 3.0)), Vector((0, 0, -1)))[0]) is not None]
    if zs and px >= 440:
        top_dev.append(abs(max(zs) - T.top_z(px)) / T.SCALE)
    lows = [h.z for yv in [i * 0.04 for i in range(0, 12)]
            if (h := mass_tree.ray_cast(Vector((x, yv, -1.0)), Vector((0, 0, 1)))[0]) is not None]
    if lows:
        sill_dev.append(abs(min(lows) - T.sill_z(px)) / T.SCALE)
    ys = [h.y for z in [0.35, 0.5, 0.7, 0.9]
          if (h := mass_tree.ray_cast(Vector((x, 2.0, z)), Vector((0, -1, 0)))[0]) is not None]
    if ys and 330 <= px <= 800:
        half_dev.append(abs(max(ys) - T.half_w(px)) / T.SCALE)
check("silhouette_top_vs_trace_px", max(top_dev) < 4.0, {"max_px": round(max(top_dev), 2), "mean_px": round(sum(top_dev) / len(top_dev), 2)})
check("silhouette_sill_vs_trace_px", max(sill_dev) < 6.0, {"max_px": round(max(sill_dev), 2)})
check("silhouette_halfwidth_vs_trace_px", max(half_dev) < 4.0, {"max_px": round(max(half_dev), 2)})
allpts = all_vertices([o for o in objs.values() if not o.name.startswith("Wheel_")])
xs = [p.x for p in allpts]
check("overall_length_vs_trace", abs(min(xs) - T.X(228)) < 0.03 and abs(max(xs) - T.X(925)) < 0.06,
      {"min_x": round(min(xs), 4), "max_x": round(max(xs), 4), "trace_min": round(T.X(228), 4), "trace_max": round(T.X(925), 4)})
zmax = max(p.z for p in allpts)
check("overall_height_vs_trace", abs(zmax - T.Z(73)) < 0.05, {"max_z": round(zmax, 4), "trace_stack_top": round(T.Z(73), 4)})

# --- wheels: names, hubs, radii, track, arch clearance ----------------------------------------------
tires = [o for o in wheels if "_Tire_" in o.name]
groups = {}
for w in wheels:
    groups.setdefault((w.name.split("_")[1], w.name.split("_")[-1] if w.name.split("_")[-1] in ("+1", "-1") else w.name.split("_")[-2]), []).append(w.name)
check("one_tire_per_wheel", len(groups) == 4 and all(sum(1 for n in names_ if "_Tire_" in n) == 1 for names_ in groups.values()),
      {"/".join(k): sum(1 for n in v_ if "_Tire_" in n) for k, v_ in groups.items()})
wheel_info = {}
fender_tree = union_tree([o for o in bodies if o.name.startswith("Body_Fender")])
hull_tree = union_tree([o for o in bodies if not o.name.startswith("Body_Fender")])
for t in tires:
    end = "truck" if "Truck" in t.name else "coupe"
    side = 1 if t.name.endswith("+1") else -1
    hub = Vector((T.WHEEL_X[end], side * T.TRACK_Y[end], T.WHEEL_R[end]))
    me = world_mesh(t)
    radii = [math.hypot(v.co.x - hub.x, v.co.z - hub.z) for v in me.vertices]
    zmin = min(v.co.z for v in me.vertices)
    ymin, ymax = min(v.co.y for v in me.vertices), max(v.co.y for v in me.vertices)
    clr = min(fender_tree.find_nearest(v.co)[3] for v in me.vertices if v.co.z > hub.z and abs(v.co.y) < 0.70 + 0.2)
    hullc = min(hull_tree.find_nearest(v.co)[3] for v in me.vertices)
    bpy.data.meshes.remove(me)
    wheel_info[t.name] = {"origin_error_mm": mm((t.location - hub).length), "radius_mm": mm(max(radii)),
                          "expected_radius_mm": mm(T.WHEEL_R[end]), "lowest_z_mm": mm(zmin),
                          "width_mm": mm(ymax - ymin), "fender_clearance_mm": mm(clr), "hull_clearance_mm": mm(hullc)}
check("wheel_tire_origins_at_hubs", all(v["origin_error_mm"] < 0.5 for v in wheel_info.values()), wheel_info)
check("wheel_tire_radii_match_display", all(abs(v["radius_mm"] - v["expected_radius_mm"]) < 1.5 for v in wheel_info.values()), None)
check("wheel_tires_touch_ground_plane_6mm", all(-1.0 < v["lowest_z_mm"] < 6.0 for v in wheel_info.values()),
      {k: v["lowest_z_mm"] for k, v in wheel_info.items()})
check("wheel_fender_arch_clearance_30mm", all(v["fender_clearance_mm"] >= 30.0 for v in wheel_info.values()),
      {k: v["fender_clearance_mm"] for k, v in wheel_info.items()})
check("wheel_hull_clearance_20mm", all(v["hull_clearance_mm"] >= 20.0 for v in wheel_info.values()),
      {k: v["hull_clearance_mm"] for k, v in wheel_info.items()})
origin_bad = []
for w in wheels:
    # spokes carry a trailing index; recover the side token from the name
    side_tok = "+1" if "+1" in w.name else "-1"
    tire = next(t for t in tires if t.name.split("_")[1] == w.name.split("_")[1] and t.name.endswith(side_tok))
    if (w.location - tire.location).length > 1e-4:
        origin_bad.append(w.name)
check("all_wheel_parts_share_hub_origin", not origin_bad, origin_bad)
counts = {}
for w in wheels:
    key = w.name.split("_")[1] + w.name.split("_")[2]
    counts[key] = counts.get(key, 0) + 1
check("wheel_part_counts", counts.get("TruckTire") == 2 and counts.get("TruckRim") == 2 and counts.get("TruckHub") == 2
      and counts.get("TruckSpoke") == 16 and counts.get("CoupeTire") == 2 and counts.get("CoupeRim") == 2
      and counts.get("CoupeHub") == 2 and counts.get("CoupeWires") == 2, counts)
rim_ok = True
for w in wheels:
    if "_Rim_" in w.name:
        end = "truck" if "Truck" in w.name else "coupe"
        me = world_mesh(w)
        rr = max(math.hypot(v.co.x - w.location.x, v.co.z - w.location.z) for v in me.vertices)
        bpy.data.meshes.remove(me)
        rim_ok &= rr < T.WHEEL_R[end] - 0.04
check("rims_inside_tires", rim_ok, None)
# physical wheels are unchanged: the model is only visual (display radii differ from the tuned 0.43)
check("wheels_are_exactly_four", len({w.name for w in tires}) == 4 and sum(1 for n in objs if "_Tire_" in n) == 4, None)

# --- central mid-drive: present, paired, never Wheel_* ------------------------------------------------
names = set(objs)
need = [f"{p}_{s}" for p in ("Prop_MidDrive_Flywheel", "Prop_MidDrive_Belt", "Prop_MidDrive_Guard",
                              "Gear_MidDrive_Pulley", "Gear_MidDrive_Pinion", "Gear_MidDrive_Shaft") for s in ("+1", "-1")]
check("mid_drive_present_paired", all(n in names for n in need), [n for n in need if n not in names])
check("mid_drive_not_wheel_named", not any(("Wheel" in n and n.startswith(("Prop_MidDrive", "Gear_"))) for n in names)
      and not any(n.startswith("Wheel_") and "MidDrive" in n for n in names), None)
fly = []
for s in (1, -1):
    o = objs[f"Prop_MidDrive_Flywheel_{s:+d}"]
    me = world_mesh(o)
    r = max(math.hypot(v.co.x - o.location.x, v.co.z - o.location.z) for v in me.vertices)
    zlo = min(v.co.z for v in me.vertices)
    bpy.data.meshes.remove(me)
    fly.append({"name": o.name, "radius_mm": mm(r), "centre": [round(c, 4) for c in o.location], "lowest_z_mm": mm(zlo)})
fx, fz, fr = T.X(T.FLY_PX[0]), T.Z(T.FLY_PX[1]), T.FLY_PX[2] * T.SCALE
check("mid_drive_flywheel_vs_trace", all(abs(f["radius_mm"] - mm(fr)) < 3 and abs(f["centre"][0] - fx) < 0.003
                                         and abs(f["centre"][2] - fz) < 0.003 and abs(abs(f["centre"][1]) - T.FLY_Y) < 0.003
                                         and f["lowest_z_mm"] > 50 for f in fly), fly)

# --- glass: seating, non-crossing, full coverage ---------------------------------------------------------
shell_tree = union_tree(bodies)
frame_tree = union_tree(frames)
gl_report = {}
for g in glass:
    me = world_mesh(g)
    outside = [v.co for v in me.vertices]
    # seating = distance from the glass to the nearest hull or frame surface
    d_hull = [shell_tree.find_nearest(p)[3] for p in outside]
    d_frame = [frame_tree.find_nearest(p)[3] for p in outside]
    gt = C.bvh_of(me)
    crossing = len(gt.overlap(shell_tree))
    bpy.data.meshes.remove(me)
    gl_report[g.name] = {"min_hull_mm": mm(min(d_hull)), "max_hull_mm": mm(max(d_hull)),
                         "min_frame_mm": mm(min(d_frame)), "hull_overlaps": crossing}
side_glass = {k: v for k, v in gl_report.items() if "Skylight" not in k}
check("glass_seated_off_hull_0p5_to_7mm", all(0.5 <= v["min_hull_mm"] <= 7.0 for v in side_glass.values()),
      {k: v["min_hull_mm"] for k, v in side_glass.items()})
check("glass_never_crosses_shell", all(v["hull_overlaps"] == 0 for v in gl_report.values()),
      {k: v["hull_overlaps"] for k, v in gl_report.items() if v["hull_overlaps"]})
check("skylight_glass_seated_in_frames", all(v["min_frame_mm"] <= 6.0 for k, v in gl_report.items() if "Skylight" in k),
      {k: v["min_frame_mm"] for k, v in gl_report.items() if "Skylight" in k})

full_tree = union_tree([o for o in objs.values() if not o.name.startswith("Wheel_")])
glass_names = {g.name for g in glass}


def first_hit_is_glass(origin, direction):
    # Ray casts on the union do not return the object; test the glass tree first and require it closer.
    ho = full_tree.ray_cast(Vector(origin), Vector(direction))
    return ho


glass_tree = union_tree(glass)
holes = []
samples = 0


def covered(origin, direction):
    hg = glass_tree.ray_cast(Vector(origin), Vector(direction))
    ha = full_tree.ray_cast(Vector(origin), Vector(direction))
    if hg[0] is None or ha[0] is None:
        return False
    return (ha[0] - hg[0]).length < 0.0015 or ha[3] >= hg[3] - 1e-5


from boilerfang_cab import SKYLIGHT_PX, WINDOWS  # noqa: E402
margin = 0.03
for name, corners in WINDOWS.items():
    (pa, zba), (pb, zbb), (_, ztb), (_, zta) = corners
    for side in (-1, 1):
        for i in range(1, 9):
            for j in range(1, 6):
                t, u = i / 9, j / 6
                px = pa + (pb - pa) * t
                zb_ = zba + (zbb - zba) * t
                zt_ = zta + (ztb - zta) * t
                z = zb_ + (zt_ - zb_) * u
                if (u * (zt_ - zb_)) < margin or ((1 - u) * (zt_ - zb_)) < margin:
                    continue
                samples += 1
                if not covered((T.X(px), side * 2.0, z), (0, -side, 0)):
                    holes.append((name, side, round(px, 1), round(z, 3)))
for k, px in enumerate(SKYLIGHT_PX):
    for i in range(-3, 4):
        for j in range(-2, 3):
            samples += 1
            if not covered((T.X(px) + i * 0.02, j * 0.07, 3.0), (0, 0, -1)):
                holes.append(("Skylight", k, i, j))
for (name, a, b, ym) in (("TruckWindshield", 436.5, 452.0, 0.36), ("SpeedsterWindshield", 703.0, 720.0, 0.27)):
    for i in range(1, 6):
        for j in range(-6, 7):
            y = ym * j / 7
            if abs(y) < 0.03:
                continue
            px = a + (b - a) * i / 6
            if i in (1, 5):
                continue
            samples += 1
            if not covered((T.X(px), y, 3.0), (0, 0, -1)):
                holes.append((name, round(y, 3), round(px, 1)))
check("glass_covers_whole_openings", not holes, {"samples": samples, "holes": holes[:12]})

# --- hardware clearance: nothing pierces glass or wheels ------------------------------------------------
pierce = {}
glass_tree2 = union_tree(glass)
for o in hardware + mids:
    me = world_mesh(o)
    n = len(C.bvh_of(me).overlap(glass_tree2))
    bpy.data.meshes.remove(me)
    if n:
        pierce[o.name] = n
check("hardware_never_pierces_glass", not pierce, pierce)
wheel_tree = union_tree(wheels)
touch = {}
for o in list(objs.values()):
    if o.name.startswith("Wheel_") or o.name.startswith("Fine_Axle"):
        continue
    me = world_mesh(o)
    n = len(C.bvh_of(me).overlap(wheel_tree))
    bpy.data.meshes.remove(me)
    if n:
        touch[o.name] = n
check("nothing_but_axles_touches_wheels", not touch, touch)

# --- lamps and attachment (no floating hardware) -------------------------------------------------------------
floaters = {}
g_verts, g_faces, g_owner = [], [], []
for o in objs.values():
    me = world_mesh(o)
    off = len(g_verts)
    g_verts += [v.co.copy() for v in me.vertices]
    g_faces += [tuple(i + off for i in p.vertices) for p in me.polygons]
    g_owner += [o.name] * len(me.polygons)
    bpy.data.meshes.remove(me)
global_tree = BVHTree.FromPolygons(g_verts, g_faces)
for o in hardware + mids + glass + frames:
    me = world_mesh(o)
    ok = False
    best = 1e9
    for v in me.vertices:
        for loc, nor, idx, dist in global_tree.find_nearest_range(v.co, 0.012):
            if g_owner[idx] != o.name and not g_owner[idx].startswith("Glass_"):
                ok = True
                break
            best = min(best, dist)
        if ok:
            break
    if not ok:
        # fallback for thin parts (bars, discs): test the neighbours' vertices against this surface
        own_tree = C.bvh_of(me)
        lo = Vector((min(v.co.x for v in me.vertices), min(v.co.y for v in me.vertices), min(v.co.z for v in me.vertices))) - Vector((0.012,) * 3)
        hi = Vector((max(v.co.x for v in me.vertices), max(v.co.y for v in me.vertices), max(v.co.z for v in me.vertices))) + Vector((0.012,) * 3)
        for other in objs.values():
            if other is o or other.name.startswith("Glass_") or ok:
                continue
            ome = world_mesh(other)
            for ov in ome.vertices:
                p = ov.co
                if lo.x <= p.x <= hi.x and lo.y <= p.y <= hi.y and lo.z <= p.z <= hi.z and own_tree.find_nearest(p)[3] <= 0.012:
                    ok = True
                    break
            bpy.data.meshes.remove(ome)
    bpy.data.meshes.remove(me)
    if not ok:
        floaters[o.name] = "nothing within 12 mm"
check("no_floating_hardware_within_12mm", not floaters, floaters)
lens_bad = {}
for n, o in objs.items():
    if n.endswith("_Lens"):
        housing = objs[n[:-5]]
        ht, hm = bvh(housing)
        me = world_mesh(o)
        d = max(ht.find_nearest(v.co)[3] for v in me.vertices)
        bpy.data.meshes.remove(me)
        bpy.data.meshes.remove(hm)
        if d > 0.006:
            lens_bad[n] = mm(d)
check("lamp_lens_vertices_seated_in_housing_6mm", not lens_bad, lens_bad or {"lenses": sum(1 for n in objs if n.endswith("_Lens"))})

# --- fittings keep clear of the cab glass --------------------------------------------------------------
stack = objs["Body_Smokestack"]
sm = world_mesh(stack)
stack_gap = min(glass_tree.find_nearest(v.co)[3] for v in sm.vertices)
bpy.data.meshes.remove(sm)
check("smokestack_clears_cab_glass_100mm", stack_gap >= 0.100, {"gap_mm": mm(stack_gap)})

sunk = {}
for n, o in objs.items():
    if n.startswith(("Frame_Skylight", "Fine_Whistle", "Fine_RoofVent")):
        me = world_mesh(o)
        depth = min(v_.co.z - B.top_surface_z(T.PX(v_.co.x), abs(v_.co.y)) for v_ in me.vertices)
        bpy.data.meshes.remove(me)
        sunk[n] = mm(depth)
check("roof_fittings_sunk_into_roof", all(d < -3.0 for d in sunk.values()), sunk)

# --- UV / materials ---------------------------------------------------------------------------------------
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

# --- exports and LODs ---------------------------------------------------------------------------------------
build = json.loads((MODEL_DIR / f"{STEM}_build.json").read_text())
ex = build["exports"]
tri = [ex["lod0"]["triangles"], ex["lod1"]["triangles"], ex["lod2"]["triangles"]]
check("triangle_budget_and_lod_monotonic", 35000 <= tri[0] <= 60000 and tri[0] > tri[1] > tri[2] and tri[1] <= 0.80 * tri[0]
      and tri[2] <= 0.45 * tri[0], tri)
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
    wn = [o for o in new if o.name.startswith(("Wheel_Truck_", "Wheel_Coupe_"))]
    tr = [o for o in wn if "_Tire_" in o.name]
    mid = [o for o in new if o.name.startswith(("Prop_MidDrive_Flywheel", "Gear_MidDrive_Pulley"))]
    pts = [o.matrix_world @ v.co for o in new for v in o.data.vertices]
    bb = (min(p.x for p in pts), max(p.x for p in pts), min(p.y for p in pts), max(p.y for p in pts),
          min(p.z for p in pts), max(p.z for p in pts))
    tire_r = {o.name: max(math.hypot((o.matrix_world @ v.co).x - o.matrix_world.translation.x, (o.matrix_world @ v.co).z - o.matrix_world.translation.z)
                           for v in o.data.vertices) for o in tr}
    hubs = {o.name: tuple(round(c, 4) for c in o.matrix_world.translation) for o in tr}
    glb_report[level] = {"meshes": len(new), "materials": sorted(mats), "wheel_objects": len(wn), "tires": len(tr),
                         "mid_drive_objects": len(mid), "bbox": [round(v, 3) for v in bb],
                         "tire_radius_min_mm": mm(min(tire_r.values())),
                         "tire_radius_deficit_mm": max(mm((T.WHEEL_R["truck"] if "Truck" in n else T.WHEEL_R["coupe"]) - r) for n, r in tire_r.items()),
                         "hubs": hubs}
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
base = glb_report[0]
LOD_OPTIONAL = {"Boilerfang_Amber", "Boilerfang_Dial"}
check("glb_reimport_counts_and_materials", all(set(glb_report[l]["materials"]) >= EXPECTED_MATERIALS - LOD_OPTIONAL and set(glb_report[l]["materials"]) <= EXPECTED_MATERIALS and glb_report[l]["tires"] == 4
                                                for l in glb_report), {l: (glb_report[l]["meshes"], glb_report[l]["wheel_objects"]) for l in glb_report})
check("glb_wheel_part_counts_stable", len({glb_report[l]["wheel_objects"] for l in glb_report}) == 1 and base["wheel_objects"] == len(wheels),
      {l: glb_report[l]["wheel_objects"] for l in glb_report})
check("glb_mid_drive_preserved_in_all_lods", all(glb_report[l]["mid_drive_objects"] == 4 for l in glb_report), {l: glb_report[l]["mid_drive_objects"] for l in glb_report})
check("lod_envelope_matches_gameplay", all(max(abs(a - b) for a, b in zip(glb_report[l]["bbox"], base["bbox"])) < 0.05 for l in (1, 2)),
      {l: glb_report[l]["bbox"] for l in glb_report})
check("lod_tire_radius_preserved_per_wheel_3mm", all(glb_report[l]["tire_radius_deficit_mm"] < 3.0 for l in glb_report),
      {l: glb_report[l]["tire_radius_deficit_mm"] for l in glb_report})
check("glb_wheel_hubs_at_authored_positions", all(
    abs(h[0] - (T.WHEEL_X["truck"] if "Truck" in n else T.WHEEL_X["coupe"])) < 0.002
    and abs(h[2] - (T.WHEEL_R["truck"] if "Truck" in n else T.WHEEL_R["coupe"])) < 0.002
    and abs(abs(h[1]) - (T.TRACK_Y["truck"] if "Truck" in n else T.TRACK_Y["coupe"])) < 0.002
    for l in glb_report for n, h in glb_report[l]["hubs"].items()), base["hubs"])

summary = {"pass": not failures, "failed": failures, "checks": len(results), "triangles": tri, "results": results,
           "glb": {str(k): {kk: vv for kk, vv in v.items() if kk != "hubs"} for k, v in glb_report.items()},
           "wheels": wheel_info}
out = MODEL_DIR / f"{STEM}_qa.json"
out.write_text(json.dumps(summary, indent=2) + "\n")
print("AK: VALIDATION " + ("PASS" if not failures else "FAIL " + ", ".join(failures)) + f" ({len(results)} checks)")
for k, v in results.items():
    if not v["ok"]:
        print("AK: FAIL", k, json.dumps(v["detail"])[:600])
if failures:
    raise SystemExit(1)
