"""Studio inspection renders (EEVEE, headless) of the exported GLBs re-imported into a clean scene."""
import math
import os

import bpy
from mathutils import Vector

V = Vector


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def setup(engine_res=(960, 720), night=False):
    sc = bpy.context.scene
    names = bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items.keys()
    sc.render.engine = next((e for e in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE") if e in names), names[0])
    sc.render.resolution_x, sc.render.resolution_y = engine_res
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.012, 0.015, 0.022, 1) if night else (0.42, 0.45, 0.5, 1)
    bg.inputs[1].default_value = 1.0 if not night else 0.6
    try:
        sc.eevee.use_shadows = True
    except Exception:
        pass
    return sc


def add_light(kind, loc, energy, color=(1, 1, 1), size=1.0, target=None, spot=None):
    ld = bpy.data.lights.new(kind, kind)
    ld.energy = energy
    ld.color = color
    if kind == "AREA":
        ld.size = size
    elif kind == "SUN":
        ld.angle = 0.1
    elif kind == "POINT":
        ld.shadow_soft_size = 0.1
    ob = bpy.data.objects.new(kind, ld)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    if target is not None:
        d = V(target) - V(loc)
        ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return ob


def camera(loc, target, lens=50, name="cam"):
    cd = bpy.data.cameras.new(name)
    cd.lens = lens
    cd.clip_end = 200
    cd.clip_start = 0.05
    ob = bpy.data.objects.new(name, cd)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (V(target) - V(loc)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = ob
    return ob


def studio_lights(night=False, scale=1.0):
    if not night:
        add_light("SUN", (3, 4, 8), 3.0 * scale, (1.0, 0.96, 0.9), target=(0, 0, 1))
        add_light("AREA", (-4, 6, 3), 500 * scale, (0.8, 0.88, 1.0), size=4, target=(0, 0, 1))
        add_light("AREA", (4, 6, 2), 300 * scale, (1.0, 0.9, 0.8), size=4, target=(0, 0, 1))


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.context.scene.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
