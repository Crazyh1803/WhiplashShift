"""Build the text-free industrial supply crate for Whiplash Shift.

Idempotent: clears the scene, rebuilds, overwrites blend/GLB/preview/QA outputs.
Blender space: +Z up (glTF export converts to Godot Y up). Crate is centred on the origin.
Run: ak-blender .ai/blender/build_item_crate.py -- [--no-render]
"""
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # noqa: E401,E702
sys.path.insert(0, os.path.join(os.path.expanduser("~"), "agent-kit", "blender"))
import argparse
import json
import math

import bpy
from mathutils import Vector, Matrix
from ak_util import report, args, repo_path, eval_counts

p = argparse.ArgumentParser()
p.add_argument("--no-render", action="store_true")
a = args(p)

BLEND = "assets/generated/crate/item_supply_crate.blend"
PREVIEW = "assets/generated/crate/item_supply_crate_preview.png"
GLB = "godot/assets/items/crate/item_supply_crate.glb"
QA = "godot/assets/items/crate/crate_qa.json"
MAX_TRIS = 6000
W, D, H = 1.8, 1.6, 1.3  # x, y(depth), z(height)

# name: (rgba, emission strength, metallic, roughness)
PALETTE = {
    "Armor": ((0.12, 0.15, 0.18, 1), 0, 0.6, 0.55),
    "Steel": ((0.36, 0.39, 0.42, 1), 0, 0.8, 0.4),
    "Dark": ((0.02, 0.025, 0.03, 1), 0, 0.3, 0.8),
    "Hazard": ((0.85, 0.58, 0.06, 1), 0, 0.2, 0.6),
    "Amber": ((1.0, 0.62, 0.12, 1), 4.0, 0.0, 0.4),
    "Cyan": ((0.15, 0.85, 1.0, 1), 4.0, 0.0, 0.4),
}
geo = {k: ([], []) for k in PALETTE}
BOX_FACES = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]


def box(mat, c, s, rot_z=0.0, rot_x=0.0):
    """Box centred c, size s; optionally rotated about its own Z then X axis."""
    v, f = geo[mat]
    o = len(v)
    m = Matrix.Rotation(rot_z, 3, "Z") @ Matrix.Rotation(rot_x, 3, "X")
    for sz in (-1, 1):
        for sy in (-1, 1):
            for sx in (-1, 1):
                local = Vector((sx * s[0] / 2, sy * s[1] / 2, sz * s[2] / 2))
                v.append(tuple(Vector(c) + m @ local))
    f.extend([tuple(i + o for i in face) for face in BOX_FACES])


def cyl(mat, c, r, h, seg=12):
    v, f = geo[mat]
    o = len(v)
    for z in (-h / 2, h / 2):
        for k in range(seg):
            ang = 2 * math.pi * k / seg
            v.append((c[0] + r * math.cos(ang), c[1] + r * math.sin(ang), c[2] + z))
    for k in range(seg):
        k2 = (k + 1) % seg
        f.append((o + k, o + k2, o + seg + k2, o + seg + k))
    f.append(tuple(o + seg - 1 - k for k in range(seg)))
    f.append(tuple(o + seg + k for k in range(seg)))


def build_crate():
    hx, hy, hz = W / 2, D / 2, H / 2
    # main body and recessed dark inner core so the seams read as gaps
    box("Dark", (0, 0, 0), (W - 0.05, D - 0.05, H - 0.05))
    # panelled faces: four sealed plates per long side, separated by dark seams
    for sy in (-1, 1):
        for i in range(3):
            x = -0.52 + i * 0.52
            box("Armor", (x, sy * (hy - 0.02), 0.0), (0.46, 0.08, H - 0.4))
            box("Steel", (x, sy * (hy + 0.01), 0.40), (0.34, 0.03, 0.05))
            for k in range(3):  # louvred vent slots
                box("Dark", (x, sy * (hy + 0.025), -0.30 + k * 0.1), (0.3, 0.02, 0.04))
            for bx in (-0.17, 0.17):  # rivets
                cyl("Steel", (x + bx, sy * (hy + 0.03), -0.5), 0.025, 0.03, seg=6)
    for sx in (-1, 1):
        for i in range(2):
            y = -0.34 + i * 0.68
            box("Armor", (sx * (hx - 0.02), y, 0.0), (0.08, 0.58, H - 0.4))
            box("Steel", (sx * (hx + 0.01), y, 0.40), (0.03, 0.46, 0.05))
        # hazard chevrons on the end faces: alternating slanted bars
        for k in range(3):  # stacked V chevrons: two slanted bars each
            for side, ang in ((-1, 0.5), (1, -0.5)):
                box("Hazard", (sx * (hx + 0.035), side * 0.17, -0.2 + k * 0.2), (0.02, 0.36, 0.07), rot_x=ang)
    # top lid: raised plate, central hatch frame and vents
    box("Steel", (0, 0, hz + 0.04), (W - 0.2, D - 0.2, 0.08))
    box("Armor", (0, 0, hz + 0.09), (W - 0.6, D - 0.6, 0.06))
    box("Dark", (0, 0, hz + 0.125), (0.9, 0.5, 0.02))
    for k in range(5):
        box("Steel", (-0.36 + k * 0.18, 0, hz + 0.14), (0.05, 0.46, 0.02))
    # bottom skid plate
    box("Steel", (0, 0, -hz - 0.04), (W - 0.1, D - 0.1, 0.08))
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("Dark", (sx * 0.55, sy * 0.45, -hz - 0.1), (0.4, 0.3, 0.06))
    # corner armor columns with caps and angled braces
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * (hx - 0.08), sy * (hy - 0.08)
            box("Steel", (cx, cy, 0), (0.22, 0.22, H + 0.06))
            box("Armor", (cx, cy, hz + 0.1), (0.3, 0.3, 0.12))
            box("Armor", (cx, cy, -hz - 0.1), (0.3, 0.3, 0.12))
            box("Hazard", (cx, cy, hz + 0.17), (0.18, 0.18, 0.02))
            box("Dark", (cx, cy, 0.0), (0.24, 0.12, 0.08))
            # corner status lamps: amber on A-side, cyan on B-side (non-text status read)
            box("Amber" if sx > 0 else "Cyan", (cx + sx * 0.0, cy + sy * 0.115, 0.28), (0.1, 0.02, 0.28))
    # horizontal bands with amber/cyan light strips
    for z in (-0.5, 0.5):
        for sy in (-1, 1):
            box("Steel", (0, sy * (hy + 0.035), z), (W - 0.3, 0.025, 0.04))
    for i in range(3):
        box("Amber", (-0.52 + i * 0.52, -(hy + 0.04), -0.5), (0.2, 0.012, 0.025))
        box("Cyan", (-0.52 + i * 0.52, hy + 0.04, -0.5), (0.2, 0.012, 0.025))
    # top status lamps
    for x in (-0.7, 0.7):
        cyl("Dark", (x, 0, hz + 0.12), 0.07, 0.06)
        cyl("Amber", (x, 0, hz + 0.16), 0.05, 0.03)
    cyl("Cyan", (0, 0, hz + 0.155), 0.06, 0.03)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for d in list(coll):
            coll.remove(d)


def make_objects():
    mats = {}
    for name, (col, em, metal, rough) in PALETTE.items():
        m = bpy.data.materials.new(f"M_{name}")
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = col
        b.inputs["Metallic"].default_value = metal
        b.inputs["Roughness"].default_value = rough
        if em:
            b.inputs["Emission Color"].default_value = col
            b.inputs["Emission Strength"].default_value = em
        m.diffuse_color = col
        mats[name] = m
    objs = []
    for name, (v, f) in geo.items():
        if not f:
            continue
        me = bpy.data.meshes.new(f"crate_{name}")
        me.from_pydata(v, [], f)
        me.update()
        me.validate()
        me.calc_normals() if hasattr(me, "calc_normals") else None
        ob = bpy.data.objects.new(f"crate_{name}", me)
        me.materials.append(mats[name])
        bpy.context.scene.collection.objects.link(ob)
        for poly in me.polygons:
            poly.use_smooth = False
        objs.append(ob)
    # outward normals: boxes are wound consistently; recalc to be safe
    import bmesh
    for ob in objs:
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(ob.data)
        bm.free()
    return objs


def render_preview(path, objs, size=640):
    sc = bpy.context.scene
    cd = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    d = Vector((0.9, -1.0, 0.7)).normalized()
    cam.location = d * 4.2
    cam.rotation_euler = (-cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "MATERIAL"
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.image_settings.file_format = "PNG"
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


clear_scene()
build_crate()
objs = make_objects()
bpy.context.view_layer.update()
tris = sum(eval_counts(o)[1] for o in objs)
pts = [vt.co.copy() for o in objs for vt in o.data.vertices]
lo = Vector((min(v.x for v in pts), min(v.y for v in pts), min(v.z for v in pts)))
hi = Vector((max(v.x for v in pts), max(v.y for v in pts), max(v.z for v in pts)))
errors = []
if tris > MAX_TRIS:
    errors.append(f"tris {tris} > {MAX_TRIS}")
size = hi - lo
if not (1.7 <= size.x <= 2.4 and 1.5 <= size.y <= 2.2 and 1.3 <= size.z <= 1.9):
    errors.append(f"unexpected dimensions {tuple(round(s, 3) for s in size)}")
if abs((hi.z + lo.z) / 2) > 0.2:
    errors.append("crate not vertically centred")
if errors:
    report(asset="item_supply_crate", errors=errors)
    raise RuntimeError(errors)

bpy.ops.wm.save_as_mainfile(filepath=repo_path(BLEND))
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
    o.select_set(True)
os.makedirs(os.path.dirname(repo_path(GLB)), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=repo_path(GLB), export_format="GLB", use_selection=True,
                          export_yup=True, export_apply=True, export_materials="EXPORT")
if not a.no_render:
    render_preview(repo_path(PREVIEW), objs)
qa = {"asset": "item_supply_crate", "glb": GLB, "meshes": len(objs), "triangles": tris,
      "size_blender_xyz": [round(s, 3) for s in size], "bounds_min": [round(c, 3) for c in lo],
      "bounds_max": [round(c, 3) for c in hi], "materials": list(PALETTE), "text_objects": 0,
      "preview": None if a.no_render else PREVIEW, "errors": errors}
with open(repo_path(QA), "w") as fh:
    json.dump(qa, fh, indent=1)
report(**qa)
