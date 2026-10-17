"""Rebuild equivalence: compare two saved builds object by object (headless Blender).

Run: ak-blender check_nightshift_idempotence.py build_a.blend -- build_b.blend
For every mesh object it requires identical names, material slot names, per-material face
counts, vertex/face counts and surface area (1e-4 relative), then the symmetric Hausdorff
distance between the two vertex sets and between each vertex set and the other surface.
Vertex/face index order is irrelevant. Tolerances are explicit (TOL_*) and the largest
measured deviations are reported. This is equivalence within those tolerances, not bit-exact.
"""
import json
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

TOL_VERTEX_MM = 1.0   # vertex placement: exact-Boolean retriangulation moves vertices along the surface
TOL_SURFACE_MM = 0.01  # shape: distance of every vertex to the other build's surface
argv = sys.argv[sys.argv.index("--") + 1:]
other_path = argv[0]


def info(obj):
    mesh = obj.data
    verts = [obj.matrix_world @ v.co for v in mesh.vertices]
    polys = [tuple(p.vertices) for p in mesh.polygons]
    area = sum(p.area for p in mesh.polygons)
    names = [m.name.removeprefix(PREFIX) if m else None for m in mesh.materials]
    hist = {}
    for p in mesh.polygons:
        key = names[p.material_index] if p.material_index < len(names) else None
        hist[key] = hist.get(key, 0) + 1
    return {"verts": verts, "polys": polys, "area": area, "mats": names, "hist": hist,
            "bvh": BVHTree.FromPolygons(verts, polys) if polys else None}


# Rename this file's datablocks first so the linked file keeps its exact names (Blender would
# otherwise rewrite colliding names such as "Lamp_+0.58" unpredictably).
PREFIX = "A::"
for datablock in list(bpy.data.objects) + list(bpy.data.materials):
    datablock.name = PREFIX + datablock.name
mine = {o.name.removeprefix(PREFIX): o for o in bpy.data.objects
        if o.type == "MESH" and not o.name.removeprefix(PREFIX).startswith("Cutter")}
before = set(bpy.data.objects)
with bpy.data.libraries.load(other_path) as (src, dst):
    dst.objects = [n for n in src.objects]
other = {o.name: o for o in bpy.data.objects
         if o not in before and o.type == "MESH" and not o.name.startswith("Cutter")}

problems = []
worst = {"vertex_mm": 0.0, "surface_mm": 0.0, "object": None}
if sorted(mine) != sorted(other):
    problems.append(f"object name sets differ: only A {sorted(set(mine) - set(other))[:5]}, "
                    f"only B {sorted(set(other) - set(mine))[:5]}")
for name in sorted(set(mine) & set(other)):
    a, b = info(mine[name]), info(other[name])
    if a["mats"] != b["mats"] or a["hist"] != b["hist"]:
        problems.append(f"{name}: materials or per-material face counts differ")
    if (len(a["verts"]), len(a["polys"])) != (len(b["verts"]), len(b["polys"])):
        problems.append(f"{name}: topology counts {len(a['verts'])}/{len(a['polys'])} vs "
                        f"{len(b['verts'])}/{len(b['polys'])}")
    if abs(a["area"] - b["area"]) > 1e-4 * max(a["area"], 1e-9):
        problems.append(f"{name}: surface area {a['area']:.6f} vs {b['area']:.6f}")
    if not a["verts"] or not b["verts"]:
        continue
    kd_a, kd_b = KDTree(len(a["verts"])), KDTree(len(b["verts"]))
    for i, v in enumerate(a["verts"]):
        kd_a.insert(v, i)
    for i, v in enumerate(b["verts"]):
        kd_b.insert(v, i)
    kd_a.balance()
    kd_b.balance()
    vertex = max(max(kd_b.find(v)[2] for v in a["verts"]), max(kd_a.find(v)[2] for v in b["verts"]))
    surface = 0.0
    if a["bvh"] and b["bvh"]:
        surface = max(max(b["bvh"].find_nearest(v)[3] for v in a["verts"]),
                      max(a["bvh"].find_nearest(v)[3] for v in b["verts"]))
    if vertex * 1000 > worst["vertex_mm"]:
        worst["vertex_mm"], worst["object"] = vertex * 1000, name
    worst["surface_mm"] = max(worst["surface_mm"], surface * 1000)
    if vertex * 1000 > TOL_VERTEX_MM or surface * 1000 > TOL_SURFACE_MM:
        problems.append(f"{name}: hausdorff vertex {vertex * 1000:.4f} mm, surface {surface * 1000:.4f} mm")
report = {"idempotent": not problems, "objects": len(mine), "tolerance_vertex_mm": TOL_VERTEX_MM, "tolerance_surface_mm": TOL_SURFACE_MM,
          "worst_vertex_hausdorff_mm": round(worst["vertex_mm"], 5),
          "worst_surface_hausdorff_mm": round(worst["surface_mm"], 5),
          "worst_object": worst["object"], "problems": problems[:10]}
print("AK: " + json.dumps(report))
if problems:
    sys.exit(1)
