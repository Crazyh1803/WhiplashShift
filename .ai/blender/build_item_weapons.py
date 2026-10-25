"""Build Whiplash Shift weapon assemblies: standard twin gun, Helix twin gun, rocket launcher.

Idempotent: every run clears the scene, rebuilds, and overwrites blend/GLB/preview/QA outputs.
Blender space: +Y forward, +Z up (glTF export converts to Godot: forward -Z, up Y).
Run: ak-blender .ai/blender/build_item_weapons.py -- [--only standard|helix|launcher]
"""
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # noqa: E401,E702
sys.path.insert(0, os.path.join(os.path.expanduser("~"), "agent-kit", "blender"))
import argparse
import json
import math

import bpy
import bmesh  # noqa: F401
from mathutils import Vector
from ak_util import report, args, repo_path, eval_counts

p = argparse.ArgumentParser()
p.add_argument("--only", default=None)
p.add_argument("--no-render", action="store_true")
a = args(p)

BLEND_DIR = "assets/generated/weapons"
GLB_DIR = "godot/assets/items/weapons"
MAX_TRIS = 15000
BARREL_X = 0.22
BARREL_Z = 0.25
MUZZLE_Y = 0.9  # Blender +Y == Godot -Z

# name: (rgba, emission strength)
PALETTES = {
    "standard": {
        "Gunmetal": ((0.16, 0.18, 0.21, 1), 0), "Plate": ((0.34, 0.37, 0.40, 1), 0),
        "Bore": ((0.01, 0.01, 0.012, 1), 0), "Accent": ((0.95, 0.45, 0.08, 1), 0),
    },
    "helix": {
        "Bone": ((0.78, 0.73, 0.60, 1), 0), "Flesh": ((0.34, 0.07, 0.13, 1), 0),
        "Bore": ((0.01, 0.01, 0.012, 1), 0), "Glow": ((0.15, 1.0, 0.72, 1), 3.0),
        "Sinew": ((0.12, 0.10, 0.14, 1), 0),
    },
    "launcher": {
        "Olive": ((0.22, 0.27, 0.16, 1), 0), "Steel": ((0.30, 0.32, 0.35, 1), 0),
        "Bore": ((0.01, 0.01, 0.012, 1), 0), "Warn": ((0.95, 0.72, 0.05, 1), 0),
        "Rocket": ((0.85, 0.12, 0.08, 1), 0),
    },
}


class Builder:
    """Accumulates geometry per material; build() makes one mesh object per material."""

    def __init__(self, pal):
        self.pal = pal
        self.geo = {k: ([], []) for k in pal}

    def _add(self, mat, verts, faces):
        v, f = self.geo[mat]
        o = len(v)
        v.extend(verts)
        f.extend([tuple(i + o for i in face) for face in faces])

    def box(self, mat, c, s, taper=1.0):
        """Axis-aligned box at centre c, size s. taper scales the +Y end's XZ (1 = none)."""
        cx, cy, cz = c
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        vs = []
        for sy in (-1, 1):
            t = taper if sy > 0 else 1.0
            for sz in (-1, 1):
                for sx in (-1, 1):
                    vs.append((cx + sx * hx * t, cy + sy * hy, cz + sz * hz * t))
        faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        self._add(mat, vs, faces)

    def lathe(self, mat, profile, c=(0, 0, 0), axis="y", seg=16, scale=(1, 1)):
        """Revolve closed (radius, along-axis) profile around an axis through c."""
        n = len(profile)
        vs = []
        for k in range(seg):
            ang = 2 * math.pi * k / seg
            ca, sa = math.cos(ang), math.sin(ang)
            for r, h in profile:
                u, w = r * ca * scale[0], r * sa * scale[1]
                if axis == "y":
                    vs.append((c[0] + u, c[1] + h, c[2] + w))
                elif axis == "x":
                    vs.append((c[0] + h, c[1] + u, c[2] + w))
                else:
                    vs.append((c[0] + u, c[1] + w, c[2] + h))
        faces = []
        for k in range(seg):
            k2 = (k + 1) % seg
            for i in range(n):
                j = (i + 1) % n
                faces.append((k * n + i, k2 * n + i, k2 * n + j, k * n + j))
        self._add(mat, vs, faces)

    def tube(self, mat, pts, radii, sides=6):
        """Swept tube along a point list (closed with end caps)."""
        vs, faces = [], []
        for i, pt in enumerate(pts):
            pv = Vector(pt)
            t = (Vector(pts[min(i + 1, len(pts) - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
            ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
            nrm = t.cross(ref).normalized()
            bn = t.cross(nrm).normalized()
            for s in range(sides):
                ang = 2 * math.pi * s / sides
                vs.append(tuple(pv + (nrm * math.cos(ang) + bn * math.sin(ang)) * radii[i]))
        for i in range(len(pts) - 1):
            for s in range(sides):
                s2 = (s + 1) % sides
                faces.append((i * sides + s, i * sides + s2, (i + 1) * sides + s2, (i + 1) * sides + s))
        faces.append(tuple(reversed(range(sides))))
        last = (len(pts) - 1) * sides
        faces.append(tuple(last + s for s in range(sides)))
        self._add(mat, vs, faces)

    def build(self, parent_name):
        mats = {}
        for name, (col, em) in self.pal.items():
            m = bpy.data.materials.new(f"M_{name}")
            m.use_nodes = True
            b = m.node_tree.nodes["Principled BSDF"]
            b.inputs["Base Color"].default_value = col
            b.inputs["Roughness"].default_value = 0.55
            if em:
                b.inputs["Emission Color"].default_value = col
                b.inputs["Emission Strength"].default_value = em
            m.diffuse_color = col
            mats[name] = m
        objs = []
        for name, (v, f) in self.geo.items():
            if not f:
                continue
            me = bpy.data.meshes.new(f"{parent_name}_{name}")
            me.from_pydata(v, [], f)
            me.update()
            me.validate()
            ob = bpy.data.objects.new(f"{parent_name}_{name}", me)
            me.materials.append(mats[name])
            bpy.context.scene.collection.objects.link(ob)
            bm = bmesh.new()
            bm.from_mesh(me)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.to_mesh(me)
            bm.free()
            for poly in me.polygons:
                poly.use_smooth = False
            objs.append(ob)
        return objs


def barrel_profile(r_out, r_bore, y0, y1, bore_depth):
    """Hollow barrel with recessed bore (closed loop: outer wall forward, bore wall back)."""
    return [(r_out, y0), (r_out, y1), (r_bore * 1.6, y1), (r_bore, y1 - 0.02),
            (r_bore, y1 - bore_depth), (0.0, y1 - bore_depth), (0.0, y0)]


def collar(r, y, w, step=0.012):
    return [(r - step, y - w), (r, y - w + step), (r, y + w - step), (r - step, y + w)]


def vents(b, mat, x, y0, n, z, side, sx=0.012, sy=0.035, sz=0.1, gap=0.06):
    for i in range(n):
        b.box(mat, (x, y0 + i * gap, z), (sx * 2, sy, sz))


# ---------------------------------------------------------------- standard
def build_standard():
    b = Builder(PALETTES["standard"])
    # mounting saddle with feet and bolts
    b.box("Plate", (0, 0.0, 0.03), (0.86, 0.70, 0.06))
    b.box("Gunmetal", (0, 0.0, 0.08), (0.70, 0.54, 0.04), taper=0.9)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box("Plate", (sx * 0.38, sy * 0.28, 0.015), (0.14, 0.14, 0.03))
            b.lathe("Gunmetal", [(0.0, 0.06), (0.03, 0.06), (0.03, 0.095), (0.0, 0.095)],
                    c=(sx * 0.34, sy * 0.26, 0), axis="z", seg=6)
    # pedestal and central yoke
    b.box("Gunmetal", (0, -0.02, 0.16), (0.34, 0.40, 0.16))
    b.box("Plate", (0, -0.05, 0.30), (0.30, 0.34, 0.12), taper=0.85)
    b.box("Accent", (0, 0.13, 0.205), (0.12, 0.02, 0.05))
    for sx in (-1, 1):
        x = sx * BARREL_X
        # rear receiver block per barrel
        b.box("Gunmetal", (x, -0.02, BARREL_Z), (0.22, 0.34, 0.20))
        b.box("Plate", (x, -0.02, BARREL_Z + 0.108), (0.16, 0.30, 0.02))
        vents(b, "Bore", sx * (BARREL_X + 0.112), -0.12, 4, BARREL_Z, sx, sz=0.12)
        # ammo feed box on the outer flank
        b.box("Plate", (sx * 0.42, -0.04, 0.22), (0.10, 0.26, 0.15))
        b.box("Accent", (sx * 0.475, -0.04, 0.22), (0.01, 0.16, 0.05))
        # barrel shroud + barrel with recessed bore
        b.lathe("Gunmetal", barrel_profile(0.092, 0.042, 0.15, 0.50, 0.0), c=(x, 0, BARREL_Z), seg=16)
        b.lathe("Gunmetal", barrel_profile(0.058, 0.036, 0.50, MUZZLE_Y, 0.16), c=(x, 0, BARREL_Z), seg=16)
        b.lathe("Bore", [(0.0, 0.0), (0.034, 0.0), (0.034, 0.005), (0.0, 0.005)],
                c=(x, MUZZLE_Y - 0.16, BARREL_Z), seg=12)
        # collars and muzzle brake
        for y, w, r in ((0.17, 0.025, 0.105), (0.34, 0.015, 0.10), (0.49, 0.02, 0.105), (0.66, 0.015, 0.075)):
            b.lathe("Plate", collar(r, y, w), c=(x, 0, BARREL_Z), seg=16)
        b.lathe("Gunmetal", barrel_profile(0.082, 0.038, 0.76, MUZZLE_Y, 0.14), c=(x, 0, BARREL_Z), seg=16)
        b.lathe("Accent", collar(0.085, 0.77, 0.012), c=(x, 0, BARREL_Z), seg=16)
        # shroud cooling slots (top)
        for i in range(4):
            b.box("Bore", (x, 0.22 + i * 0.07, BARREL_Z + 0.092), (0.05, 0.03, 0.012))
    # top rail + sight
    b.box("Plate", (0, 0.05, 0.395), (0.10, 0.5, 0.03))
    b.box("Gunmetal", (0, 0.20, 0.43), (0.06, 0.08, 0.05))
    b.box("Accent", (0, 0.245, 0.435), (0.03, 0.01, 0.02))
    # bridge between barrels
    b.box("Gunmetal", (0, 0.3, 0.25), (0.34, 0.08, 0.10))
    return b, {"MuzzleLeft": (-BARREL_X, MUZZLE_Y, BARREL_Z), "MuzzleRight": (BARREL_X, MUZZLE_Y, BARREL_Z)}


# ---------------------------------------------------------------- helix
def build_helix():
    b = Builder(PALETTES["helix"])
    # organic saddle: wide flesh plate with root feet
    b.lathe("Flesh", [(0.0, 0.0), (0.46, 0.0), (0.44, 0.05), (0.22, 0.09), (0.0, 0.09)],
            c=(0, 0.0, 0), axis="z", seg=16, scale=(1.0, 0.8))
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.lathe("Bone", [(0.0, 0.0), (0.075, 0.0), (0.06, 0.05), (0.0, 0.06)],
                    c=(sx * 0.37, sy * 0.25, 0), axis="z", seg=8)
    # spine ridge up the middle (vertebrae)
    for i in range(5):
        y = -0.22 + i * 0.12
        b.lathe("Bone", [(0.0, -0.045), (0.07 - i * 0.004, -0.04), (0.055, 0.0), (0.07 - i * 0.004, 0.04), (0.0, 0.045)],
                c=(0, y, 0.15 + i * 0.02), axis="y", seg=8, scale=(1.2, 1.0))
    b.box("Flesh", (0, -0.05, 0.17), (0.32, 0.38, 0.14), taper=0.8)
    # central sinew knot
    b.lathe("Sinew", [(0.0, -0.17), (0.12, -0.12), (0.15, 0.0), (0.12, 0.12), (0.0, 0.17)],
            c=(0, 0.0, 0.27), seg=12, scale=(1.1, 0.8))
    for sx in (-1, 1):
        x = sx * BARREL_X
        c = (x, 0, BARREL_Z)
        # bulbous rear gland
        b.lathe("Flesh", [(0.0, -0.20), (0.09, -0.19), (0.125, -0.10), (0.13, 0.05), (0.105, 0.17), (0.0, 0.17)],
                c=c, seg=14)
        # vertebra ribs along the barrel
        for i in range(7):
            y = 0.20 + i * 0.075
            r = 0.095 - i * 0.004
            b.lathe("Bone", [(0.0, -0.03), (r * 0.8, -0.03), (r, -0.01), (r, 0.01), (r * 0.8, 0.03), (0.0, 0.03)],
                    c=(x, y, BARREL_Z), seg=10)
        # inner core barrel with recessed bore
        b.lathe("Sinew", barrel_profile(0.058, 0.04, 0.15, 0.80, 0.07), c=c, seg=12)
        b.lathe("Bone", barrel_profile(0.07, 0.042, 0.78, MUZZLE_Y, 0.15), c=c, seg=12)
        # glowing bore floor
        b.lathe("Glow", [(0.0, 0.0), (0.034, 0.0), (0.034, 0.006), (0.0, 0.006)],
                c=(x, MUZZLE_Y - 0.15, BARREL_Z), seg=10)
        b.lathe("Glow", collar(0.074, 0.80, 0.008), c=c, seg=12)
        # petal prongs flaring around the muzzle
        for k in range(4):
            ang = math.pi / 4 + k * math.pi / 2
            ox, oz = math.cos(ang) * 0.085, math.sin(ang) * 0.085
            b.tube("Bone", [(x + ox * 0.9, 0.62, BARREL_Z + oz * 0.9),
                            (x + ox * 1.1, 0.76, BARREL_Z + oz * 1.1),
                            (x + ox * 1.35, MUZZLE_Y - 0.03, BARREL_Z + oz * 1.35)],
                   [0.016, 0.014, 0.004], sides=4)
        # counter-rotating helix strands (sinew + glow) around the barrel
        for strand, (mat, ph, rad) in enumerate((("Sinew", 0.0, 0.092), ("Glow", math.pi, 0.092))):
            pts = []
            n = 14
            for i in range(n):
                t = i / (n - 1)
                y = 0.18 + t * 0.58
                ang = ph + sx * t * math.pi * 3.0
                pts.append((x + math.cos(ang) * rad, y, BARREL_Z + math.sin(ang) * rad))
            b.tube(mat, pts, [0.011 if mat == "Glow" else 0.015] * n, sides=5)
        # flesh vents on the gland
        for i in range(3):
            b.box("Bore", (x + sx * 0.12, -0.14 + i * 0.08, BARREL_Z + 0.02), (0.012, 0.035, 0.06))
        # tendon straps down to the saddle
        b.tube("Sinew", [(x, -0.10, BARREL_Z - 0.10), (x * 1.3, -0.12, 0.14), (x * 1.55, -0.12, 0.05)],
               [0.04, 0.035, 0.03], sides=6)
    # bone ridge on top
    b.box("Bone", (0, 0.10, 0.37), (0.06, 0.45, 0.025), taper=0.5)
    b.box("Flesh", (0, 0.32, 0.25), (0.34, 0.07, 0.09))
    return b, {"MuzzleLeft": (-BARREL_X, MUZZLE_Y, BARREL_Z), "MuzzleRight": (BARREL_X, MUZZLE_Y, BARREL_Z)}


# ---------------------------------------------------------------- launcher
def build_launcher():
    b = Builder(PALETTES["launcher"])
    zc = 0.30
    # saddle + cradle
    b.box("Steel", (0, 0.0, 0.03), (0.60, 0.70, 0.06))
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box("Steel", (sx * 0.30, sy * 0.28, 0.015), (0.12, 0.12, 0.03))
            b.lathe("Olive", [(0.0, 0.06), (0.028, 0.06), (0.028, 0.09), (0.0, 0.09)],
                    c=(sx * 0.26, sy * 0.26, 0), axis="z", seg=6)
    for y in (-0.2, 0.25):
        b.box("Steel", (0, y, 0.14), (0.26, 0.10, 0.17), taper=0.9)
    # main tube with recessed bore, rear exhaust, flared muzzle
    b.lathe("Olive", barrel_profile(0.15, 0.115, -0.35, MUZZLE_Y, 0.55), c=(0, 0, zc), seg=20)
    b.lathe("Steel", [(0.115, -0.35), (0.17, -0.37), (0.20, -0.45), (0.14, -0.45), (0.0, -0.38), (0.0, -0.35)],
            c=(0, 0, zc), seg=20)
    b.lathe("Steel", [(0.14, 0.83), (0.18, 0.86), (0.19, MUZZLE_Y), (0.115, MUZZLE_Y), (0.115, 0.83)],
            c=(0, 0, zc), seg=20)
    # rocket nose visible in the bore
    b.lathe("Rocket", [(0.0, 0.0), (0.08, 0.0), (0.09, 0.08), (0.05, 0.16), (0.0, 0.2)],
            c=(0, MUZZLE_Y - 0.50, zc), axis="y", seg=12)
    b.lathe("Bore", [(0.0, 0.0), (0.108, 0.0), (0.108, 0.004), (0.0, 0.004)],
            c=(0, MUZZLE_Y - 0.545, zc), seg=16)
    # reinforcement bands and warning stripes
    for y, w in ((-0.25, 0.03), (0.0, 0.03), (0.30, 0.03), (0.55, 0.03)):
        b.lathe("Steel", collar(0.17, y, w), c=(0, 0, zc), seg=20)
    for y in (0.12, 0.17, 0.42):
        b.lathe("Warn", collar(0.157, y, 0.018, step=0.004), c=(0, 0, zc), seg=20)
    # side vents, top sight and battery pack
    for sx in (-1, 1):
        for i in range(4):
            b.box("Bore", (sx * 0.155, -0.18 + i * 0.07, zc + 0.02), (0.012, 0.035, 0.07))
        b.box("Steel", (sx * 0.19, 0.38, zc - 0.04), (0.06, 0.22, 0.10))
    b.box("Steel", (0, 0.0, zc + 0.20), (0.07, 0.40, 0.04))
    b.box("Olive", (0, 0.12, zc + 0.24), (0.05, 0.10, 0.06))
    b.box("Warn", (0, 0.18, zc + 0.245), (0.03, 0.01, 0.02))
    return b, {"Muzzle": (0, MUZZLE_Y, zc)}


BUILDERS = {"standard": ("item_gun_standard", build_standard),
            "helix": ("item_gun_helix", build_helix),
            "launcher": ("item_launcher", build_launcher)}


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for d in list(coll):
            coll.remove(d)


def render_preview(path, objs, size=640):
    sc = bpy.context.scene
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector((min(v.x for v in pts), min(v.y for v in pts), min(v.z for v in pts)))
    hi = Vector((max(v.x for v in pts), max(v.y for v in pts), max(v.z for v in pts)))
    ctr, rad = (lo + hi) / 2, (hi - lo).length / 2
    cd = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    d = Vector((0.9, 1.0, 0.75)).normalized()  # front-right-above (forward = +Y)
    dist = rad / math.sin(cd.angle / 2) * 1.05
    cam.location = ctr + d * dist
    cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
    cd.clip_end = dist * 10
    sc.camera = cam
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "MATERIAL"
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.image_settings.file_format = "PNG"
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def to_godot(v):
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def process(key):
    stem, fn = BUILDERS[key]
    clear_scene()
    b, sockets = fn()
    objs = b.build(stem)
    markers = []
    for name, loc in sockets.items():
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = "ARROWS"
        e.empty_display_size = 0.06
        e.location = loc
        bpy.context.scene.collection.objects.link(e)
        markers.append(e)
    bpy.context.view_layer.update()

    errors = []
    tris = sum(eval_counts(o)[1] for o in objs)
    pts = [vt.co.copy() for o in objs for vt in o.data.vertices]
    lo = Vector((min(v.x for v in pts), min(v.y for v in pts), min(v.z for v in pts)))
    hi = Vector((max(v.x for v in pts), max(v.y for v in pts), max(v.z for v in pts)))
    if tris > MAX_TRIS:
        errors.append(f"tris {tris} > {MAX_TRIS}")
    if abs(lo.z) > 0.001:
        errors.append(f"mount base not at origin z={lo.z:.4f}")
    if abs(hi.y - MUZZLE_Y) > 0.005:
        errors.append(f"forward extent {hi.y:.4f} != muzzle {MUZZLE_Y}")
    for m in markers:
        # socket must sit on the real muzzle face: forward extent near the marker xz
        near = [v for o in objs for v in (o.matrix_world @ vt.co for vt in o.data.vertices)
                if abs(v.x - m.location.x) < 0.2 and abs(v.y - m.location.y) < 0.005]
        if not near:
            errors.append(f"{m.name} has no geometry at tip")
    for n in {"standard": ["MuzzleLeft", "MuzzleRight"], "helix": ["MuzzleLeft", "MuzzleRight"],
              "launcher": ["Muzzle"]}[key]:
        if n not in [m.name for m in markers]:
            errors.append(f"missing marker {n}")

    if errors:
        report(asset=stem, errors=errors)
        raise RuntimeError(f"{stem} validation failed: {errors}")

    blend = repo_path(f"{BLEND_DIR}/{stem}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    glb = repo_path(f"{GLB_DIR}/{stem}.glb")
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs + markers:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True, export_materials="EXPORT")
    preview = None
    if not a.no_render:
        preview = f"{BLEND_DIR}/{stem}_preview.png"
        render_preview(repo_path(preview), objs)

    qa = {
        "asset": stem, "glb": f"{GLB_DIR}/{stem}.glb", "meshes": len(objs), "triangles": tris,
        "bounds_godot_min": to_godot((lo.x, hi.y, lo.z)), "bounds_godot_max": to_godot((hi.x, lo.y, hi.z)),
        "sockets_godot": {m.name: to_godot(m.location) for m in markers},
        "preview": preview, "errors": errors,
    }
    report(**qa)
    return qa


keys = [a.only] if a.only else list(BUILDERS)
results = [process(k) for k in keys]
if not a.only:
    with open(repo_path(f"{GLB_DIR}/weapons_qa.json"), "w") as f:
        json.dump(results, f, indent=1)
    with open(repo_path(f"{GLB_DIR}/README.md"), "w") as f:
        f.write("# Weapon assemblies\n\nGenerated by `.ai/blender/build_item_weapons.py` "
                "(sources in `assets/generated/weapons/`). Godot space: forward -Z, up Y, mount base at origin.\n\n"
                "| GLB | Sockets (Godot local) | Tris |\n|---|---|---|\n")
        for r in results:
            s = ", ".join(f"{k} {v}" for k, v in r["sockets_godot"].items())
            f.write(f"| {os.path.basename(r['glb'])} | {s} | {r['triangles']} |\n")
        f.write("\nPlace at the vehicle nose/upper deck; rotate PI about Y for end B.\n")
report(done=True, errors=sum(len(r["errors"]) for r in results))
