"""Neutral studio renders and blueprint overlays (headless, EEVEE/Workbench-free)."""
import math
from pathlib import Path

import bpy
from mathutils import Vector

import boilerfang_trace as T

REF_W, REF_H = 1024, 572
TOP_CENTER_PY = T.TOP_CENTER_PY


def build_studio(cols):
    scene = bpy.context.scene
    engines = {i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items}
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
    world = bpy.data.worlds.new("StudioWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.55, 0.60, 0.66, 1.0)
    bg.inputs["Strength"].default_value = 0.9
    scene.world = world
    objs = []
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, -0.002))
    ground = bpy.context.object
    ground.name = "Studio_Ground"
    mat = bpy.data.materials.new("Studio_Floor")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.20, 0.21, 0.22, 1)
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
    ground.data.materials.append(mat)
    cols["STUDIO"].objects.link(ground)
    bpy.context.scene.collection.objects.unlink(ground)
    objs.append(ground)
    for name, loc, energy, size in (("Key", (4, -5, 6), 900, 6), ("Fill", (-6, 4, 4), 380, 8),
                                    ("Rim", (-1, 7, 5), 520, 5), ("Top", (0, 0, 8), 300, 8)):
        light = bpy.data.lights.new(name, "AREA")
        light.energy = energy
        light.size = size
        obj = bpy.data.objects.new(name, light)
        obj.location = loc
        direction = Vector((0, 0, 0.7)) - Vector(loc)
        obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        cols["STUDIO"].objects.link(obj)
        objs.append(obj)
    cam = bpy.data.cameras.new("QA_Camera")
    camo = bpy.data.objects.new("QA_Camera", cam)
    cols["STUDIO"].objects.link(camo)
    scene.camera = camo
    objs.append(camo)
    return objs


def _aim(cam_obj, location, target):
    cam_obj.location = location
    cam_obj.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()


def configure(view, width=1280, height=720):
    scene = bpy.context.scene
    cam_obj = scene.camera
    cam = cam_obj.data
    scene.render.resolution_x, scene.render.resolution_y = width, height
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    cam.shift_x = cam.shift_y = 0
    if view in ("side", "top"):
        cam.type = "ORTHO"
        cam.ortho_scale = 6.2
        if view == "side":
            _aim(cam_obj, (0, -9, 0.9), (0, 0, 0.9))
        else:
            _aim(cam_obj, (0, 0, 9), (0, 0, 0))
            cam_obj.rotation_euler = (0, 0, 0)
        return
    cam.type = "PERSP"
    cam.lens = 55
    cam.clip_start, cam.clip_end = 0.1, 80
    presets = {
        "front_truck": ((-9.0, 0.0, 1.1), (-2.4, 0, 0.7)),
        "front_coupe": ((9.0, 0.0, 0.9), (2.3, 0, 0.5)),
        "three_quarter_truck": ((-6.2, -5.2, 2.3), (-0.2, 0, 0.7)),
        "three_quarter_coupe": ((6.4, -5.0, 2.1), (0.2, 0, 0.6)),
        "far_side_three_quarter": ((5.4, 5.6, 2.6), (0.0, 0, 0.7)),
        "wheel_truck": ((-0.9, -3.2, 1.0), (-1.72, -0.66, 0.35)),
        "wheel_coupe": ((2.6, -3.0, 0.8), (1.66, -0.50, 0.26)),
        "truck_detail": ((-4.6, -2.8, 1.7), (-2.0, 0, 0.8)),
        "coupe_detail": ((4.6, -2.8, 1.4), (2.0, 0, 0.45)),
        "cab": ((-0.3, -4.2, 2.3), (-0.5, 0, 1.0)),
        "middrive": ((1.2, -2.6, 1.0), (0.1, -0.5, 0.3)),
        "flywheel": ((0.9, -1.9, 0.6), (0.35, -0.55, 0.3)),
        "boiler_top": ((-2.4, -2.0, 3.0), (-1.7, 0, 0.9)),
        "cockpit": ((1.8, -2.3, 1.7), (0.9, 0, 0.6)),
        "roof": ((-1.8, -2.2, 3.3), (-0.5, 0, 1.3)),
        "underside": ((0.0, -2.8, 0.05), (0.0, 0, 0.3)),
    }
    loc, tgt = presets[view]
    _aim(cam_obj, loc, tgt)


def render(path):
    scene = bpy.context.scene
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(path)
    if scene.render.engine.startswith("BLENDER_EEVEE"):
        try:
            scene.eevee.taa_render_samples = 32
        except AttributeError:
            pass
    bpy.ops.render.render(write_still=True)


def overlay(view, ref_path, out_path):
    """Render the model with the reference's exact pixel mapping and blend 50/50."""
    scene = bpy.context.scene
    cam_obj = scene.camera
    cam = cam_obj.data
    cam.type = "ORTHO"
    cam.ortho_scale = REF_W * T.SCALE
    ground = bpy.data.objects.get("Studio_Ground")
    if ground:
        ground.hide_render = True
    cam.clip_start, cam.clip_end = 0.1, 12.0 if view.startswith("front") else 80.0
    scene.render.resolution_x, scene.render.resolution_y = REF_W, REF_H
    scene.render.film_transparent = True
    # camera centre sits on the reference image centre
    cx_px, cy_px = REF_W / 2, REF_H / 2
    if view == "side":
        x = T.X(cx_px)
        z = T.Z(cy_px)
        cam_obj.location = (x, -12, z)
        cam_obj.rotation_euler = (math.pi / 2, 0, 0)
    elif view == "top":
        x = T.X(cx_px)
        y = -(cy_px - TOP_CENTER_PY) * T.SCALE
        cam_obj.location = (x, y, 12)
        cam_obj.rotation_euler = (0, 0, 0)
    else:
        raise ValueError("overlays are only calibrated for side and top")
    tmp = Path(str(out_path) + ".render.png")
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = str(tmp)
    bpy.ops.render.render(write_still=True)
    rendered = bpy.data.images.load(str(tmp))
    ref = bpy.data.images.load(str(ref_path))
    assert tuple(rendered.size) == tuple(ref.size), (rendered.size, ref.size)
    a, b = list(rendered.pixels), list(ref.pixels)
    out = list(b)
    for i in range(0, len(a), 4):
        alpha = a[i + 3]
        if alpha > 0.01:
            m = 0.55 * alpha
            out[i] = b[i] * (1 - m) + (a[i] * 0.5 + 0.5) * m
            out[i + 1] = b[i + 1] * (1 - m) + (a[i + 1] * 0.5 + 0.1) * m
            out[i + 2] = b[i + 2] * (1 - m) + (a[i + 2] * 0.5) * m
    result = bpy.data.images.new("overlay", REF_W, REF_H, alpha=True)
    result.pixels = out
    result.filepath_raw = str(out_path)
    result.file_format = "PNG"
    result.save()
    for img in (rendered, ref, result):
        bpy.data.images.remove(img)
    tmp.unlink(missing_ok=True)
    scene.render.film_transparent = False
    if ground:
        ground.hide_render = False
    cam.clip_end = 80.0
